// lib/src/services/latency_service.dart

import 'dart:async';
import 'dart:io';
import 'package:dart_ping/dart_ping.dart';
import 'package:dart_ping_ios/dart_ping_ios.dart';
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
  static const String _defaultHost = '1.1.1.1'; // Cloudflare DNS
  final SpeedTestOptions options;
  final String targetHost;
  bool _isInitialized = false;

  LatencyService(this.options, {this.targetHost = _defaultHost});

  /// Initialize platform-specific ping support
  Future<void> _initialize() async {
    if (_isInitialized) return;

    if (Platform.isIOS) {
      try {
        DartPingIOS.register();
        _isInitialized = true;
      } catch (e) {
        // iOS ping registration failed, but continue
        _isInitialized = true;
      }
    } else {
      _isInitialized = true;
    }
  }

  Future<LatencyResult> measureLatency({
    void Function(LatencySample sample)? onSample,
    Future<void>? cancelToken,
  }) async {
    await _initialize();

    final samples = <double>[];
    final startTime = DateTime.now();
    int failedSamples = 0;

    // Warmup: discard first sample to establish connection
    try {
      await _measureSinglePing();
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
        final rtt = await _measureSinglePing();
        samples.add(rtt);

        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        onSample?.call(LatencySample(timestampMs: elapsed, rttMs: rtt));
      } catch (e) {
        failedSamples++;
      }

      // Small delay between pings
      if (i < options.pingSamples - 1) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
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

  /// Measure single ping using ICMP
  Future<double> _measureSinglePing() async {
    final completer = Completer<double>();
    bool hasResponse = false;

    final ping = Ping(
      targetHost,
      count: 1,
      timeout: 2, // 2 second timeout
      interval: 1,
    );

    final timeoutTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Ping timeout'));
      }
    });

    StreamSubscription? subscription;

    subscription = ping.stream.listen(
      (event) {
        if (event.response != null && event.response!.time != null) {
          final latency = event.response!.time!.inMicroseconds / 1000.0;

          if (latency > 0 && latency < 2000 && !hasResponse) {
            hasResponse = true;
            timeoutTimer.cancel();
            subscription?.cancel();

            if (!completer.isCompleted) {
              completer.complete(latency);
            }
          }
        } else if (event.error != null) {
          if (!hasResponse && !completer.isCompleted) {
            timeoutTimer.cancel();
            subscription?.cancel();
            completer.completeError(Exception('Ping error: ${event.error}'));
          }
        }
      },
      onDone: () {
        if (!hasResponse && !completer.isCompleted) {
          timeoutTimer.cancel();
          completer.completeError(Exception('Ping completed without response'));
        }
      },
      onError: (e) {
        if (!completer.isCompleted) {
          timeoutTimer.cancel();
          subscription?.cancel();
          completer.completeError(e);
        }
      },
      cancelOnError: true,
    );

    try {
      return await completer.future;
    } finally {
      timeoutTimer.cancel();
      subscription.cancel();
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
    await _initialize();

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
        final rtt = await _measureSinglePing();
        samples.add(rtt);
      } catch (e) {
        // Ignore failures under load
      }

      await Future.delayed(const Duration(milliseconds: 150));
    }

    if (samples.isEmpty) return null;
    return _calculateTrimmedMean(samples, trimPercent: 0.1);
  }
}
