// lib/src/services/latency_service.dart

import 'dart:async';
import 'dart:io';
import 'package:dart_ping/dart_ping.dart';
import 'package:dart_ping_ios/dart_ping_ios.dart';
import '../cancel_token.dart';
import '../models/speed_test_options.dart';
import '../models/sample.dart';
import '../models/exceptions.dart';

class LatencyResult {
  final double latencyMs;
  final double jitterMs;
  final double packetLossPercent;
  final double minMs;
  final double maxMs;
  final double medianMs;

  LatencyResult({
    required this.latencyMs,
    required this.jitterMs,
    required this.packetLossPercent,
    required this.minMs,
    required this.maxMs,
    required this.medianMs,
  });
}

class LatencyService {
  static const String _defaultHost = '1.1.1.1';
  final SpeedTestOptions options;
  final String targetHost;
  bool _isInitialized = false;

  LatencyService(this.options, {this.targetHost = _defaultHost});

  Future<void> _initialize() async {
    if (_isInitialized) return;
    if (Platform.isIOS) {
      try {
        DartPingIOS.register();
      } catch (_) {
        // iOS ping registration failed, continue
      }
    }
    _isInitialized = true;
  }

  Future<LatencyResult> measureLatency({
    required CancelToken cancelToken, // CHANGED: CancelToken
    void Function(LatencySample sample)? onSample,
  }) async {
    await _initialize();

    final samples = <double>[];
    final startTime = DateTime.now();
    int failedSamples = 0;

    // Warmup: discard first pingWarmupCount samples
    for (int w = 0; w < options.pingWarmupCount; w++) {
      // CHANGED: pingWarmupCount
      cancelToken.throwIfCanceled();
      try {
        await cancelToken.race(_measureSinglePing());
        await Future.delayed(const Duration(milliseconds: 100));
      } on SpeedTestCanceledException {
        rethrow;
      } catch (_) {
        // Warmup failure is acceptable
      }
    }

    for (int i = 0; i < options.pingCount; i++) {
      // CHANGED: pingCount
      cancelToken.throwIfCanceled();

      try {
        final rtt = await cancelToken.race(_measureSinglePing());
        samples.add(rtt);

        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        onSample?.call(LatencySample(timestampMs: elapsed, rttMs: rtt));
      } on SpeedTestCanceledException {
        rethrow;
      } catch (_) {
        failedSamples++;
      }

      if (i < options.pingCount - 1) {
        // CHANGED: pingCount
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (samples.isEmpty) {
      throw SpeedTestPhaseException(
        'ping',
        'All ${options.pingCount} ping samples failed', // CHANGED: pingCount
      );
    }

    final sorted = List<double>.from(samples)..sort();
    final minMs = sorted.first;
    final maxMs = sorted.last;
    final medianMs = _calculateMedian(sorted);
    final latency = _calculateTrimmedMean(samples, trimPercent: 0.1);
    final jitter = _calculateJitter(samples);
    final packetLoss =
        (failedSamples / options.pingCount) * 100; // CHANGED: pingCount

    return LatencyResult(
      latencyMs: latency,
      jitterMs: jitter,
      packetLossPercent: packetLoss,
      minMs: minMs,
      maxMs: maxMs,
      medianMs: medianMs,
    );
  }

  Future<double> _measureSinglePing() async {
    final completer = Completer<double>();
    bool hasResponse = false;

    final ping = Ping(targetHost, count: 1, timeout: 2, interval: 1);

    final timeoutTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Ping timeout'));
      }
    });

    StreamSubscription? subscription;

    subscription = ping.stream.listen(
      (event) {
        if (event.response != null &&
            event.response!.time != null &&
            !hasResponse) {
          final latency = event.response!.time!.inMicroseconds / 1000.0;
          if (latency > 0 && latency < 2000) {
            hasResponse = true;
            timeoutTimer.cancel();
            subscription?.cancel();
            if (!completer.isCompleted) {
              completer.complete(latency);
            }
          }
        } else if (event.error != null && !hasResponse) {
          timeoutTimer.cancel();
          subscription?.cancel();
          if (!completer.isCompleted) {
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
      onError: (Object e) {
        timeoutTimer.cancel();
        subscription?.cancel();
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      },
      cancelOnError: true,
    );

    try {
      return await completer.future;
    } finally {
      timeoutTimer.cancel();
      await subscription.cancel();
    }
  }

  Future<double?> measureLoadedLatency({
    required CancelToken cancelToken, // CHANGED: CancelToken
  }) async {
    await _initialize();

    final samples = <double>[];

    for (int i = 0; i < options.loadedLatencyPings; i++) {
      // CHANGED: loadedLatencyPings
      if (cancelToken.isCanceled) break;

      try {
        final rtt = await _measureSinglePing();
        samples.add(rtt);
      } catch (_) {
        // Ignore failures under load
      }

      if (i < options.loadedLatencyPings - 1) {
        // CHANGED: loadedLatencyPings
        await Future.delayed(
          options.loadedLatencyInterval,
        ); // CHANGED: loadedLatencyInterval
      }
    }

    if (samples.isEmpty) return null;
    return _calculateTrimmedMean(samples, trimPercent: 0.1);
  }

  double _calculateMedian(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  double _calculateTrimmedMean(
    List<double> values, {
    double trimPercent = 0.1,
  }) {
    if (values.isEmpty) return 0;
    if (values.length < 3) return _calculateMedian(values);

    final sorted = List<double>.from(values)..sort();
    final trimCount = (sorted.length * trimPercent).floor();

    if (trimCount == 0) {
      return sorted.reduce((a, b) => a + b) / sorted.length;
    }

    final trimmed = sorted.sublist(trimCount, sorted.length - trimCount);
    if (trimmed.isEmpty) return _calculateMedian(values);

    return trimmed.reduce((a, b) => a + b) / trimmed.length;
  }

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
}
