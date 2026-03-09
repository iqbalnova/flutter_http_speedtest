// lib/src/models/speed_test_options.dart

import 'dart:io';
import 'enums.dart';

/// All tunables for the speed test engine.
///
/// Every value has a sensible default that matches official Ookla methodology.
/// Pass a custom instance to [SpeedTestEngine] to override any value.
class SpeedTestOptions {
  // ── Ping ────────────────────────────────────────────────────────────

  /// Number of TCP pings to measure (after warmup).
  final int pingCount;

  /// Number of initial pings discarded as warmup.
  final int pingWarmupCount;

  /// Number of loaded-latency pings sent during download/upload.
  final int loadedLatencyPings;

  /// Interval between loaded-latency pings.
  final Duration loadedLatencyInterval;

  // ── Threading ───────────────────────────────────────────────────────

  /// Minimum threads to start a speed phase with.
  final int minThreads;

  /// Maximum threads that thread-scaling may reach.
  final int maxThreads;

  /// If pre-test speed < this, start with [minThreads]; otherwise [maxThreads].
  final double threadScaleThresholdMbps;

  // ── Timing ──────────────────────────────────────────────────────────

  /// How many throughput samples to collect per second (Ookla uses ~30).
  final int sampleRatePerSecond;

  /// Duration of the download measurement phase.
  final Duration downloadDuration;

  /// Duration of the upload measurement phase.
  final Duration uploadDuration;

  /// Timeout for the entire latency (ping) phase.
  final Duration pingTimeout;

  /// Hard cap on the entire test run.
  final Duration maxTotalDuration;

  // ── Retry / pre-test ────────────────────────────────────────────────

  /// Number of retry attempts per phase (1 = one retry after first failure).
  final int retries;

  /// Bytes for the single-stream pre-test speed estimation (512 KB default).
  final int preTestBytes;

  // ── Smoothing ───────────────────────────────────────────────────────

  /// EMA alpha for real-time UI smoothing (0 = no smoothing, 1 = raw).
  final double emaAlpha;

  // ── Injectable HttpClient ───────────────────────────────────────────

  /// Optional [HttpClient] factory for testing / mocking.
  /// When `null` the services create their own clients.
  final HttpClient Function()? httpClientFactory;

  const SpeedTestOptions({
    this.pingCount = 10,
    this.pingWarmupCount = 3,
    this.loadedLatencyPings = 20,
    this.loadedLatencyInterval = const Duration(milliseconds: 500),
    this.minThreads = 2,
    this.maxThreads = 4,
    this.threadScaleThresholdMbps = 4.0,
    this.sampleRatePerSecond = 30,
    this.downloadDuration = const Duration(seconds: 10),
    this.uploadDuration = const Duration(seconds: 10),
    this.pingTimeout = const Duration(seconds: 10),
    this.maxTotalDuration = const Duration(seconds: 35),
    this.retries = 1,
    this.preTestBytes = 512 * 1024,
    this.emaAlpha = 0.3,
    this.httpClientFactory,
  });

  /// Sampling interval derived from [sampleRatePerSecond].
  int get sampleIntervalMs => (1000 / sampleRatePerSecond).round();

  /// Convenience: timeout for a specific phase.
  Duration timeoutFor(TestPhase phase) {
    switch (phase) {
      case TestPhase.metadata:
        return const Duration(seconds: 5);
      case TestPhase.ping:
        return pingTimeout;
      case TestPhase.download:
        return downloadDuration + const Duration(seconds: 5);
      case TestPhase.upload:
        return uploadDuration + const Duration(seconds: 5);
    }
  }

  /// Create an [HttpClient] using the factory or the platform default.
  HttpClient createHttpClient() {
    final client = httpClientFactory?.call() ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    return client;
  }
}
