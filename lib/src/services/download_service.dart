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

    try {
      // Start loaded latency measurement in background
      Future<double?>? loadedLatencyFuture;
      if (onLoadedLatency != null) {
        final latencyService = LatencyService(options);
        loadedLatencyFuture = latencyService.measureLoadedLatency(
          cancelToken: cancelToken,
        );
      }

      final uri = Uri.https(_endpoint, '/__down', {'bytes': bytes.toString()});
      final request = await client.getUrl(uri).timeout(options.downloadTimeout);
      // request.headers.set('User-Agent', 'flutter_http_speedtest/1.0');

      final response = await request.close().timeout(options.downloadTimeout);

      if (response.statusCode != 200) {
        throw Exception('Download failed: ${response.statusCode}');
      }

      final stopwatch = Stopwatch()..start();
      int totalBytes = 0;
      int lastSampleBytes = 0;
      int lastSampleTime = 0;

      await for (final chunk in response) {
        if (cancelToken != null) {
          final race = await Future.any([
            Future.value(false),
            cancelToken.then((_) => true),
          ]);
          if (race) throw Exception('Canceled');
        }

        totalBytes += chunk.length;
        final elapsed = stopwatch.elapsedMilliseconds;

        // Sample at intervals
        if (elapsed - lastSampleTime >= options.sampleInterval.inMilliseconds) {
          final bytesInInterval = totalBytes - lastSampleBytes;
          final timeInInterval = (elapsed - lastSampleTime) / 1000.0;
          final mbps = (bytesInInterval * 8) / (timeInInterval * 1000000);

          onSample?.call(SpeedSample(timestampMs: elapsed, mbps: mbps));

          lastSampleBytes = totalBytes;
          lastSampleTime = elapsed;
        }
      }

      stopwatch.stop();
      final totalSeconds = stopwatch.elapsedMilliseconds / 1000.0;
      final mbps = (totalBytes * 8) / (totalSeconds * 1000000);

      // Wait for loaded latency
      if (loadedLatencyFuture != null) {
        final ll = await loadedLatencyFuture;
        if (ll != null) {
          onLoadedLatency?.call(ll);
        }
      }

      return mbps;
    } finally {
      client.close();
    }
  }
}
