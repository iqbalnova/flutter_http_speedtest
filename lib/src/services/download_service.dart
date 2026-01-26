// lib/src/services/download_service.dart

import 'dart:async';
import 'dart:io';
import '../models/speed_test_options.dart';
import '../models/sample.dart';
import 'latency_service.dart';

class DownloadService {
  static const String _endpoint = 'speed.cloudflare.com';
  final SpeedTestOptions options;

  DownloadService(this.options);

  Future<double> measureDownload({
    required int bytes,
    void Function(SpeedSample sample)? onSample,
    void Function(double loadedLatency)? onLoadedLatency,
    Future<void>? cancelToken,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);

    // 🔥 Simpan semua sample untuk final calculation
    final List<SpeedSample> samples = [];

    try {
      /// Start loaded latency measurement in background
      Future<double?>? loadedLatencyFuture;
      if (onLoadedLatency != null) {
        final latencyService = LatencyService(options);
        loadedLatencyFuture = latencyService.measureLoadedLatency(
          cancelToken: cancelToken,
        );
      }

      /// Request large file
      final uri = Uri.https(_endpoint, '/__down', {'bytes': bytes.toString()});
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));

      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );

      if (response.statusCode != 200) {
        throw Exception('Download failed: ${response.statusCode}');
      }

      final stopwatch = Stopwatch()..start();

      int totalBytes = 0;
      int lastSampleBytes = 0;
      int lastSampleTime = 0;

      /// Timeout controller
      final downloadTimeoutCompleter = Completer<void>();
      final timeoutTimer = Timer(options.downloadTimeout, () {
        if (!downloadTimeoutCompleter.isCompleted) {
          downloadTimeoutCompleter.complete();
        }
      });

      try {
        await for (final chunk in response) {
          /// Cancel check
          if (cancelToken != null) {
            final race = await Future.any([
              Future.value(false),
              cancelToken.then((_) => true),
            ]);
            if (race) throw Exception('Canceled');
          }

          /// Timeout reached
          if (downloadTimeoutCompleter.isCompleted) {
            break;
          }

          totalBytes += chunk.length;
          final elapsed = stopwatch.elapsedMilliseconds;

          /// 🔥 Warm-up discard (0–500ms)
          if (elapsed < 500) {
            lastSampleBytes = totalBytes;
            lastSampleTime = elapsed;
            continue;
          }

          /// Sample at interval
          if (elapsed - lastSampleTime >=
              options.sampleInterval.inMilliseconds) {
            final bytesInInterval = totalBytes - lastSampleBytes;
            final timeInInterval = (elapsed - lastSampleTime) / 1000.0;

            if (timeInInterval > 0) {
              final mbps = (bytesInInterval * 8) / (timeInInterval * 1000000);

              final sample = SpeedSample(timestampMs: elapsed, mbps: mbps);

              samples.add(sample);
              onSample?.call(sample);
            }

            lastSampleBytes = totalBytes;
            lastSampleTime = elapsed;
          }

          /// Hard timeout break
          if (stopwatch.elapsed >= options.downloadTimeout) {
            break;
          }
        }
      } finally {
        timeoutTimer.cancel();
      }

      stopwatch.stop();

      /// 🔥 FINAL SPEED CALCULATION (ENTERPRISE GRADE)
      final finalMbps = _calculateFinalMbps(samples);

      /// Wait loaded latency
      if (loadedLatencyFuture != null) {
        final ll = await loadedLatencyFuture;
        if (ll != null) {
          onLoadedLatency?.call(ll);
        }
      }

      return finalMbps;
    } finally {
      client.close(force: true);
    }
  }

  /// ============================
  /// FINAL SPEED AGGREGATION LOGIC
  /// ============================

  double _calculateFinalMbps(List<SpeedSample> samples) {
    if (samples.isEmpty) return 0.0;

    // 🔹 1. Buang warm-up awal (30%)
    final startIndex = (samples.length * 0.3).round();
    final stableSamples = samples.length > startIndex
        ? samples.sublist(startIndex)
        : samples;

    if (stableSamples.isEmpty) {
      return samples.last.mbps;
    }

    // 🔹 2. Ambil nilai Mbps saja
    final values = stableSamples.map((e) => e.mbps).toList();

    // Sort ascending
    values.sort();

    // 🔹 3. Ambil percentile 90 sebagai peak reference
    final p90Index = (values.length * 0.9).round().clamp(0, values.length - 1);
    final p90 = values[p90Index];

    // 🔹 4. Clamp spike ekstrem (anti burst buffer)
    final filtered = values.where((v) => v <= p90 * 1.2).toList();

    final used = filtered.isNotEmpty ? filtered : values;

    // 🔹 5. Average stable window
    final avg = used.reduce((a, b) => a + b) / used.length;

    return avg;
  }
}
