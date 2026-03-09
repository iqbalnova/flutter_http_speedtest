// lib/src/services/download_service.dart

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../cancel_token.dart';
import '../models/speed_test_options.dart';
import '../models/sample.dart';
import '../models/exceptions.dart';

/// Download speed measurement using the official Ookla methodology.
///
/// 1. **Pre-test** — single-stream 512 KB probe to estimate line speed.
/// 2. **Real test** — multi-stream, duration-based, with adaptive thread
///    scaling in the first half and high-frequency sampling (30 Hz).
/// 3. **Aggregation** — 20-slice trimmed mean (remove top 2, bottom 25 %).
class DownloadService {
  static const String _endpoint = 'speed.cloudflare.com';

  final SpeedTestOptions options;

  DownloadService(this.options);

  /// Run the full Ookla-style download measurement.
  ///
  /// Returns the final download speed in Mbit/s.
  Future<double> measureDownload({
    required CancelToken cancelToken,
    void Function(SpeedSample sample)? onSample,
  }) async {
    // ── Phase A: Pre-test (speed estimation) ───────────────────────
    cancelToken.throwIfCanceled();
    final estimatedMbps = await _preTest(cancelToken);

    cancelToken.throwIfCanceled();

    // Select chunk size based on estimated speed
    final int chunkSize;
    if (estimatedMbps < 1) {
      chunkSize = 256 * 1024; // 256 KB
    } else if (estimatedMbps <= 10) {
      chunkSize = 1024 * 1024; // 1 MB
    } else {
      chunkSize = 4 * 1024 * 1024; // 4 MB
    }

    // Select initial thread count
    final int startThreads = estimatedMbps < options.threadScaleThresholdMbps
        ? options.minThreads
        : options.maxThreads;

    // ── Phase B: Real test (duration-based, multi-stream) ──────────
    cancelToken.throwIfCanceled();
    final rawSamples = await _realTest(
      cancelToken: cancelToken,
      chunkSize: chunkSize,
      startThreads: startThreads,
      onSample: onSample,
    );

    // ── Phase C: Ookla 20-slice aggregation ────────────────────────
    return _calculateDownloadMbps(rawSamples);
  }

  // ══════════════════════════════════════════════════════════════════
  // Phase A — Pre-test
  // ══════════════════════════════════════════════════════════════════

  Future<double> _preTest(CancelToken cancelToken) async {
    final client = options.createHttpClient();
    try {
      final cacheBust = math.Random().nextInt(999999999);
      final uri = Uri.https(_endpoint, '/__down', {
        'bytes': options.preTestBytes.toString(),
        '_': cacheBust.toString(),
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
      if (secs <= 0) return 0;
      return (bytes * 8) / (secs * 1e6); // Mbit/s
    } catch (e) {
      if (e is SpeedTestCanceledException) rethrow;
      return 0; // Fallback: assume slow
    } finally {
      client.close(force: true);
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // Phase B — Real test
  // ══════════════════════════════════════════════════════════════════

  Future<List<double>> _realTest({
    required CancelToken cancelToken,
    required int chunkSize,
    required int startThreads,
    void Function(SpeedSample sample)? onSample,
  }) async {
    final duration = options.downloadDuration;
    final intervalMs = options.sampleIntervalMs;
    final rawSamples = <double>[];

    // Shared mutable state — main isolate only.
    int totalBytes = 0;
    int currentThreads = startThreads;
    bool threadScaleLocked = false;
    int adaptiveChunkSize = chunkSize;

    final clients = <HttpClient>[];
    final activeFutures = <Future<void>>[];

    final stopwatch = Stopwatch()..start();
    int lastSampleBytes = 0;
    int lastSampleTimeUs = 0;

    double ema = 0;
    bool emaInit = false;

    // ── Helper: launch one download stream ────────────────────────
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
          onChunk: (int n) {
            totalBytes += n;
          },
        ),
      );
    }

    try {
      // Launch initial threads
      for (int i = 0; i < startThreads; i++) {
        cancelToken.throwIfCanceled();
        launchStream();
      }

      // ── Sampling timer ──────────────────────────────────────────
      final samplingDone = Completer<void>();
      final timer = Timer.periodic(Duration(milliseconds: intervalMs), (t) {
        if (cancelToken.isCanceled ||
            stopwatch.elapsed >= duration ||
            samplingDone.isCompleted) {
          t.cancel();
          if (!samplingDone.isCompleted) samplingDone.complete();
          return;
        }

        final nowUs = stopwatch.elapsedMicroseconds;
        final bytesInInterval = totalBytes - lastSampleBytes;
        final usInInterval = nowUs - lastSampleTimeUs;

        if (usInInterval > 0 && bytesInInterval > 0) {
          final secs = usInInterval / 1e6;
          final mbps = (bytesInInterval * 8) / (secs * 1e6);
          rawSamples.add(mbps);

          // EMA for UI
          if (!emaInit) {
            ema = mbps;
            emaInit = true;
          } else {
            ema = options.emaAlpha * mbps + (1 - options.emaAlpha) * ema;
          }

          final sample = SpeedSample(
            timestampMs: stopwatch.elapsedMilliseconds,
            mbps: mbps,
            smoothedMbps: ema,
          );
          onSample?.call(sample);

          // ── Thread scaling (first half only) ──────────────────
          if (!threadScaleLocked) {
            final halfDone =
                stopwatch.elapsed >=
                Duration(milliseconds: duration.inMilliseconds ~/ 2);
            if (halfDone) {
              threadScaleLocked = true;
            } else if (currentThreads < options.maxThreads) {
              // Heuristic: if current throughput is below 80 % of estimated
              // capacity per thread, add another thread.
              final perThread = mbps / currentThreads;
              if (perThread < options.threadScaleThresholdMbps) {
                currentThreads++;
                launchStream();
              }
            }
          }

          // ── Adaptive chunk size ────────────────────────────────
          if (mbps < 1) {
            adaptiveChunkSize = 256 * 1024;
          } else if (mbps <= 10) {
            adaptiveChunkSize = 1024 * 1024;
          } else {
            adaptiveChunkSize = 4 * 1024 * 1024;
          }
        }

        lastSampleBytes = totalBytes;
        lastSampleTimeUs = nowUs;
      });

      // Wait for duration to elapse (or cancel)
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
      for (final c in clients) {
        c.close(force: true);
      }
    }
  }

  /// A single download stream that loops chunk requests until duration expires.
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
        final cacheBust = math.Random().nextInt(999999999);
        final uri = Uri.https(_endpoint, '/__down', {
          'bytes': getChunkSize().toString(),
          '_': cacheBust.toString(),
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
        // Single request failure — loop retries automatically.
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // Phase C — Ookla 20-slice aggregation
  // ══════════════════════════════════════════════════════════════════

  /// Exact Ookla download result aggregation.
  ///
  /// 1. Aggregate raw samples into 20 equal chronological slices.
  /// 2. Sort ascending.
  /// 3. Remove the 2 fastest (top outliers).
  /// 4. Remove the bottom 25 % of what remains.
  /// 5. Average the rest.
  double _calculateDownloadMbps(List<double> rawSamples) {
    if (rawSamples.isEmpty) return 0.0;
    if (rawSamples.length == 1) return rawSamples.first;

    // Step 1-2: Aggregate into 20 slices
    final slices = _aggregateInto20Slices(rawSamples);

    // Step 3: Sort ascending
    slices.sort();

    // Step 4: Remove 2 fastest (top)
    if (slices.length <= 2) return slices.last;
    final afterTopRemoved = slices.sublist(0, slices.length - 2);

    // Step 5: Remove bottom 1/4 of what remains
    final removeBottom = (afterTopRemoved.length * 0.25).round();
    final finalSlices = afterTopRemoved.sublist(removeBottom);

    if (finalSlices.isEmpty) return afterTopRemoved.last;

    // Step 6: Average the rest
    final result = finalSlices.reduce((a, b) => a + b) / finalSlices.length;
    return double.parse(result.toStringAsFixed(2));
  }

  List<double> _aggregateInto20Slices(List<double> samples) {
    const sliceCount = 20;
    final sliceSize = (samples.length / sliceCount).ceil().clamp(
      1,
      samples.length,
    );
    final slices = <double>[];

    for (int i = 0; i < samples.length; i += sliceSize) {
      final end = (i + sliceSize).clamp(0, samples.length);
      final group = samples.sublist(i, end);
      final avg = group.reduce((a, b) => a + b) / group.length;
      slices.add(avg);
    }

    return slices;
  }
}
