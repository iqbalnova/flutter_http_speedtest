// lib/src/services/download_service.dart

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../cancel_token.dart';
import '../models/speed_test_options.dart';
import '../models/sample.dart';
import '../models/exceptions.dart';

class DownloadService {
  static const String _endpoint = 'speed.cloudflare.com';
  static const int _scaleUpCooldownMs = 1000;

  final SpeedTestOptions options;

  DownloadService(this.options);

  Future<({double trimmedMbps, double smoothedMbps})> measureDownload({
    required CancelToken cancelToken,
    void Function(SpeedSample sample)? onSample,
  }) async {
    cancelToken.throwIfCanceled();
    final estimatedMbps = await _preTest(cancelToken);

    cancelToken.throwIfCanceled();

    final int chunkSize = _selectChunkSize(estimatedMbps);
    final int startThreads = estimatedMbps < options.threadScaleThresholdMbps
        ? options.minThreads
        : options.maxThreads;

    cancelToken.throwIfCanceled();
    final rawSamples = await _realTest(
      cancelToken: cancelToken,
      chunkSize: chunkSize,
      startThreads: startThreads,
      onSample: onSample,
    );

    final trimmed = _calculateDownloadMbps(rawSamples);

    const windowSize = 15;
    final window = rawSamples.length <= windowSize
        ? rawSamples
        : rawSamples.sublist(rawSamples.length - windowSize);
    final smoothed = window.isEmpty
        ? trimmed
        : window.reduce((a, b) => a + b) / window.length;

    return (trimmedMbps: trimmed, smoothedMbps: smoothed);
  }

  int _selectChunkSize(double estimatedMbps) {
    if (estimatedMbps < 1) return 256 * 1024;
    if (estimatedMbps <= 10) return 1024 * 1024;
    return 4 * 1024 * 1024;
  }

  Future<double> _preTest(CancelToken cancelToken) async {
    final client = options.createHttpClient();
    try {
      final uri = Uri.https(_endpoint, '/__down', {
        'bytes': options.preTestBytes.toString(),
        '_': math.Random().nextInt(999999999).toString(),
      });

      final request = await cancelToken.race(
        client.getUrl(uri).timeout(const Duration(seconds: 5)),
      );
      final response = await cancelToken.race(
        request.close().timeout(const Duration(seconds: 5)),
      );

      if (response.statusCode != 200) {
        await response.drain<void>();
        return 0;
      }

      int bytes = 0;
      final sw = Stopwatch()..start();
      await for (final chunk in response) {
        cancelToken.throwIfCanceled();
        bytes += chunk.length;
      }
      sw.stop();
      final secs = sw.elapsedMicroseconds / 1e6;
      if (secs <= 0 || bytes == 0) return 0;
      return (bytes * 8) / (secs * 1e6);
    } catch (e) {
      if (e is SpeedTestCanceledException) rethrow;
      return 0;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<double>> _realTest({
    required CancelToken cancelToken,
    required int chunkSize,
    required int startThreads,
    void Function(SpeedSample sample)? onSample,
  }) async {
    final duration = options.downloadDuration;
    final intervalMs = options.sampleIntervalMs;
    final rawSamples = <double>[];

    // Single-writer byte counter via stream listener — no concurrent mutation.
    final byteStream = StreamController<int>.broadcast();
    int totalBytes = 0;
    byteStream.stream.listen((n) => totalBytes += n);

    int currentThreads = startThreads;
    bool threadScaleLocked = false;
    int adaptiveChunkSize = chunkSize;
    int lastScaleUpMs = 0;

    final clients = <HttpClient>[];
    final activeFutures = <Future<void>>[];
    final stopwatch = Stopwatch()..start();

    int lastSnapshotBytes = 0;
    int lastSnapshotUs = 0;

    // EMA hanya dipakai sebagai fallback saat sample < 3
    // (belum cukup data untuk windowed average yang meaningful)
    double ema = 0;
    bool emaInit = false;
    const double emaAlpha = 0.3;

    void launchStream() {
      final client = options.createHttpClient();
      clients.add(client);
      activeFutures.add(
        _downloadLoop(
          client: client,
          cancelToken: cancelToken,
          stopwatch: stopwatch,
          duration: duration,
          getChunkSize: () => adaptiveChunkSize,
          onChunk: byteStream.add,
        ),
      );
    }

    try {
      for (int i = 0; i < startThreads; i++) {
        cancelToken.throwIfCanceled();
        launchStream();
      }

      final samplingDone = Completer<void>();

      final timer = Timer.periodic(Duration(milliseconds: intervalMs), (t) {
        // Snapshot FIRST — before any other work or check.
        final nowUs = stopwatch.elapsedMicroseconds;
        final elapsedMs = nowUs ~/ 1000;
        final snapshotBytes = totalBytes;

        if (cancelToken.isCanceled ||
            elapsedMs >= duration.inMilliseconds ||
            samplingDone.isCompleted) {
          t.cancel();
          if (!samplingDone.isCompleted) samplingDone.complete();
          return;
        }

        final bytesInInterval = snapshotBytes - lastSnapshotBytes;
        final usInInterval = nowUs - lastSnapshotUs;

        if (usInInterval > 0 && bytesInInterval > 0) {
          final secs = usInInterval / 1e6;
          final mbps = (bytesInInterval * 8) / (secs * 1e6);

          rawSamples.add(mbps);

          if (!emaInit) {
            ema = mbps;
            emaInit = true;
          } else {
            ema = emaAlpha * mbps + (1 - emaAlpha) * ema;
          }

          // Dengan windowed average (15 sample terakhir ≈ 500ms pada 30Hz):
          const int windowSize = 15;
          final double smoothed;
          if (rawSamples.length < 3) {
            smoothed = ema;
          } else {
            final window = rawSamples.length <= windowSize
                ? rawSamples
                : rawSamples.sublist(rawSamples.length - windowSize);
            smoothed = window.reduce((a, b) => a + b) / window.length;
          }

          onSample?.call(
            SpeedSample(
              timestampMs: elapsedMs,
              mbps: mbps,
              smoothedMbps: smoothed,
            ),
          );

          // Thread scaling — first half only, 1 s cooldown, ≥3 samples.
          if (!threadScaleLocked) {
            final halfElapsed = elapsedMs >= duration.inMilliseconds ~/ 2;
            if (halfElapsed) {
              threadScaleLocked = true;
            } else if (currentThreads < options.maxThreads &&
                rawSamples.length >= 3 &&
                elapsedMs - lastScaleUpMs >= _scaleUpCooldownMs) {
              final perThread = mbps / currentThreads;
              if (perThread < options.threadScaleThresholdMbps) {
                currentThreads++;
                launchStream();
                lastScaleUpMs = elapsedMs;
              }
            }
          }

          adaptiveChunkSize = _selectChunkSize(mbps);
        }

        lastSnapshotBytes = snapshotBytes;
        lastSnapshotUs = nowUs;
      });

      await cancelToken.race(
        Future.any([
          Future.wait(activeFutures).catchError((_) => <void>[]),
          samplingDone.future,
          Future.delayed(duration),
        ]),
      );

      timer.cancel();
      if (!samplingDone.isCompleted) samplingDone.complete();

      return rawSamples;
    } finally {
      await byteStream.close();
      for (final c in clients) {
        c.close(force: true);
      }
    }
  }

  Future<void> _downloadLoop({
    required HttpClient client,
    required CancelToken cancelToken,
    required Stopwatch stopwatch,
    required Duration duration,
    required int Function() getChunkSize,
    required void Function(int bytes) onChunk,
  }) async {
    while (!cancelToken.isCanceled && stopwatch.elapsed < duration) {
      try {
        final uri = Uri.https(_endpoint, '/__down', {
          'bytes': getChunkSize().toString(),
          '_': math.Random().nextInt(999999999).toString(),
        });

        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 5));
        final response = await request.close().timeout(
          const Duration(seconds: 5),
        );

        if (response.statusCode != 200) {
          await response.drain<void>();
          continue;
        }

        await for (final chunk in response) {
          if (cancelToken.isCanceled || stopwatch.elapsed >= duration) break;
          onChunk(chunk.length);
        }
      } on SpeedTestCanceledException {
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  // Ookla 20-slice trimmed-mean.
  // 1. Bucket raw samples into 20 equal chronological slices (floor — equal sizes).
  // 2. Sort ascending.
  // 3. Drop top 2 (burst outliers).
  // 4. Drop bottom 25 % (warmup tail).
  // 5. Average the rest.
  double _calculateDownloadMbps(List<double> rawSamples) {
    if (rawSamples.isEmpty) return 0.0;
    if (rawSamples.length == 1) return rawSamples.first;

    final slices = _aggregateInto20Slices(rawSamples);
    if (slices.isEmpty) return rawSamples.last;

    slices.sort();

    if (slices.length <= 2) return slices.last;
    final afterTopRemoved = slices.sublist(0, slices.length - 2);

    final removeBottom = (afterTopRemoved.length * 0.25).round();
    final finalSlices = afterTopRemoved.sublist(removeBottom);

    if (finalSlices.isEmpty) return afterTopRemoved.last;

    final avg = finalSlices.reduce((a, b) => a + b) / finalSlices.length;
    return double.parse(avg.toStringAsFixed(2));
  }

  List<double> _aggregateInto20Slices(List<double> samples) {
    const sliceCount = 20;
    if (samples.length < sliceCount) {
      return List<double>.from(samples);
    }
    final sliceSize = samples.length ~/ sliceCount;
    final slices = <double>[];
    for (int i = 0; i < sliceCount; i++) {
      final start = i * sliceSize;
      final end = start + sliceSize;
      final group = samples.sublist(start, end);
      slices.add(group.reduce((a, b) => a + b) / group.length);
    }
    return slices;
  }
}
