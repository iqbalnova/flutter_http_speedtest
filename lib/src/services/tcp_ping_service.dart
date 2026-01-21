// lib/src/services/tcp_ping_service.dart
//
// ALTERNATIVE IMPLEMENTATION: Pure TCP socket ping
// This is closer to ICMP ping and gives more accurate latency results
// Use this instead of HTTP-based latency measurement for best accuracy

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

/// TCP Socket-based ping service (most accurate for latency measurement)
///
/// This measures pure TCP connection time without HTTP overhead,
/// giving results much closer to ICMP ping and Cloudflare's web interface.
class TcpPingService {
  static const String _endpoint = 'speed.cloudflare.com';
  static const int _port = 443;
  final SpeedTestOptions options;

  TcpPingService(this.options);

  Future<LatencyResult> measureLatency({
    void Function(LatencySample sample)? onSample,
    Future<void>? cancelToken,
  }) async {
    final samples = <double>[];
    final startTime = DateTime.now();
    int failedSamples = 0;

    // Warmup: first connection is slower due to DNS/routing
    try {
      await _measureTcpRtt();
      await Future.delayed(const Duration(milliseconds: 50));
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
        final rtt = await _measureTcpRtt();
        samples.add(rtt);

        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        onSample?.call(LatencySample(timestampMs: elapsed, rttMs: rtt));
      } catch (e) {
        failedSamples++;
      }

      if (i < options.pingSamples - 1) {
        // Shorter delay between samples for more responsive testing
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (samples.isEmpty) {
      throw Exception('All ping samples failed');
    }

    // Use trimmed mean to handle outliers
    final latency = _calculateTrimmedMean(samples, trimPercent: 0.15);
    final jitter = _calculateJitter(samples);
    final packetLoss = (failedSamples / options.pingSamples) * 100;

    return LatencyResult(
      latencyMs: latency,
      jitterMs: jitter,
      packetLossPercent: packetLoss,
    );
  }

  /// Measure pure TCP connection time (most accurate)
  Future<double> _measureTcpRtt() async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;

    try {
      // Pure TCP connection - no TLS handshake, no HTTP
      // This is the closest we can get to ICMP ping in pure Dart
      socket = await Socket.connect(
        _endpoint,
        _port,
        timeout: const Duration(milliseconds: 1500),
      );

      stopwatch.stop();

      // Connection established - this is our RTT measurement
      return stopwatch.elapsedMicroseconds / 1000.0;
    } finally {
      socket?.destroy();
    }
  }

  /// Calculate trimmed mean (removes outliers)
  double _calculateTrimmedMean(
    List<double> values, {
    double trimPercent = 0.15,
  }) {
    if (values.isEmpty) return 0;
    if (values.length < 4) return _calculateMedian(values);

    final sorted = List<double>.from(values)..sort();
    final trimCount = (sorted.length * trimPercent).floor();

    if (trimCount == 0) {
      return sorted.reduce((a, b) => a + b) / sorted.length;
    }

    final trimmed = sorted.sublist(trimCount, sorted.length - trimCount);
    if (trimmed.isEmpty) return _calculateMedian(values);

    return trimmed.reduce((a, b) => a + b) / trimmed.length;
  }

  /// Calculate median (fallback for small samples)
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

  /// Calculate jitter as mean absolute deviation of consecutive differences
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

    for (int i = 0; i < options.loadedLatencySamples; i++) {
      if (cancelToken != null) {
        final race = await Future.any([
          Future.value(false),
          cancelToken.then((_) => true),
        ]);
        if (race) return null;
      }

      try {
        final rtt = await _measureTcpRtt();
        samples.add(rtt);
      } catch (e) {
        // Ignore failures under load
      }

      await Future.delayed(const Duration(milliseconds: 150));
    }

    if (samples.isEmpty) return null;
    return _calculateTrimmedMean(samples, trimPercent: 0.15);
  }
}

// ============================================================================
// USAGE GUIDE
// ============================================================================
// 
// To use TCP ping instead of HTTP ping, modify speed_test_engine.dart:
//
// 1. Import the service:
//    import 'services/tcp_ping_service.dart';
//
// 2. Replace LatencyService with TcpPingService in _runTest():
//    final latencyService = TcpPingService(options);
//
// 3. Update download_service.dart to use TcpPingService for loaded latency:
//    final latencyService = TcpPingService(options);
//
// This will give you results much closer to Cloudflare's website!
// ============================================================================