// lib/src/services/latency_service.dart

import 'dart:async';
import 'dart:io';
import '../models/speed_test_options.dart';
import '../models/sample.dart';

class LatencyResult {
  final double latencyMs;
  final double jitterMs;
  final double packetLossPercent;

  LatencyResult({
    required this.latencyMs,
    required this.jitterMs,
    required this.packetLossPercent,
  });
}

class LatencyService {
  static const String _endpoint = 'speed.cloudflare.com';
  final SpeedTestOptions options;

  LatencyService(this.options);

  Future<LatencyResult> measureLatency({
    void Function(LatencySample sample)? onSample,
    Future<void>? cancelToken,
  }) async {
    final samples = <double>[];
    final startTime = DateTime.now();
    int failedSamples = 0;

    // Create a single persistent HTTP client with keep-alive
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);
    client.idleTimeout = const Duration(seconds: 30);

    try {
      // Warmup: establish connection and discard first sample
      try {
        await _measureSingleRttWithClient(client);
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        // Warmup failure is acceptable
      }

      for (int i = 0; i < options.pingSamples; i++) {
        if (cancelToken != null) {
          final race = await Future.any([
            Future.value(false),
            cancelToken.then((_) => true),
          ]);
          if (race) throw Exception('Canceled');
        }

        try {
          final rtt = await _measureSingleRttWithClient(client);
          samples.add(rtt);

          final elapsed = DateTime.now().difference(startTime).inMilliseconds;
          onSample?.call(LatencySample(timestampMs: elapsed, rttMs: rtt));
        } catch (e) {
          failedSamples++;
        }

        if (i < options.pingSamples - 1) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    } finally {
      client.close(force: false); // Allow graceful connection close
    }

    if (samples.isEmpty) {
      throw Exception('All ping samples failed');
    }

    // Use trimmed mean to remove outliers
    final latency = _calculateTrimmedMean(samples, trimPercent: 0.1);
    final jitter = _calculateJitter(samples);
    final packetLoss = (failedSamples / options.pingSamples) * 100;

    return LatencyResult(
      latencyMs: latency,
      jitterMs: jitter,
      packetLossPercent: packetLoss,
    );
  }

  /// Measure RTT using persistent HTTP client (reuses connection)
  Future<double> _measureSingleRttWithClient(HttpClient client) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Use smallest possible request - HEAD method
      final request = await client
          .openUrl('HEAD', Uri.https(_endpoint, '/cdn-cgi/trace'))
          .timeout(const Duration(milliseconds: 1500));

      // request.headers.set('User-Agent', 'flutter_http_speedtest/1.0');
      // request.headers.set('Connection', 'keep-alive');
      request.contentLength = 0;

      final response = await request.close().timeout(
        const Duration(milliseconds: 1500),
      );

      // Just read status, don't drain body for HEAD request
      final _ = response.statusCode;
      await response.drain().timeout(const Duration(milliseconds: 500));

      stopwatch.stop();
      return stopwatch.elapsedMicroseconds / 1000.0;
    } catch (e) {
      stopwatch.stop();
      rethrow;
    }
  }

  /// Calculate median (robust to outliers)
  double _calculateMedian(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[mid];
    } else {
      return (sorted[mid - 1] + sorted[mid]) / 2;
    }
  }

  /// Calculate trimmed mean (removes outliers from both ends)
  double _calculateTrimmedMean(
    List<double> values, {
    double trimPercent = 0.1,
  }) {
    if (values.isEmpty) return 0;
    if (values.length < 3) return _calculateMedian(values);

    final sorted = List<double>.from(values)..sort();
    final trimCount = (sorted.length * trimPercent).floor();

    if (trimCount == 0) {
      // If trim count is 0, just use mean
      return sorted.reduce((a, b) => a + b) / sorted.length;
    }

    final trimmed = sorted.sublist(trimCount, sorted.length - trimCount);
    if (trimmed.isEmpty) return _calculateMedian(values);

    return trimmed.reduce((a, b) => a + b) / trimmed.length;
  }

  /// Calculate jitter using consecutive differences
  double _calculateJitter(List<double> values) {
    if (values.length < 2) return 0;

    double totalDelta = 0;
    int count = 0;

    for (int i = 1; i < values.length; i++) {
      totalDelta += (values[i] - values[i - 1]).abs();
      count++;
    }

    return count > 0 ? totalDelta / count : 0;
  }

  /// Measure loaded latency during download/upload
  Future<double?> measureLoadedLatency({Future<void>? cancelToken}) async {
    final samples = <double>[];
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);
    client.idleTimeout = const Duration(seconds: 10);

    try {
      for (int i = 0; i < options.loadedLatencySamples; i++) {
        if (cancelToken != null) {
          final race = await Future.any([
            Future.value(false),
            cancelToken.then((_) => true),
          ]);
          if (race) return null;
        }

        try {
          final rtt = await _measureSingleRttWithClient(client);
          samples.add(rtt);
        } catch (e) {
          // Ignore failures under load
        }

        await Future.delayed(const Duration(milliseconds: 150));
      }
    } finally {
      client.close(force: false);
    }

    if (samples.isEmpty) return null;
    return _calculateTrimmedMean(samples, trimPercent: 0.1);
  }
}
