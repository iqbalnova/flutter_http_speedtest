// lib/src/models/sample.dart

/// Base class for all time-stamped samples emitted during a speed test.
abstract class Sample {
  /// Milliseconds since the phase started.
  final int timestampMs;
  Sample(this.timestampMs);
}

/// A single throughput measurement emitted every ~100 ms during
/// download or upload.
class SpeedSample extends Sample {
  /// Instantaneous throughput in Mbit/s (for gauge needle).
  final double mbps;

  /// Exponential-moving-average smoothed throughput (for UI number display).
  final double smoothedMbps;

  SpeedSample({
    required int timestampMs,
    required this.mbps,
    this.smoothedMbps = 0.0,
  }) : super(timestampMs);

  /// Create a copy with an updated [smoothedMbps].
  SpeedSample withSmoothed(double smoothed) =>
      SpeedSample(timestampMs: timestampMs, mbps: mbps, smoothedMbps: smoothed);

  @override
  String toString() =>
      'SpeedSample(t=${timestampMs}ms, '
      'raw=${mbps.toStringAsFixed(2)}, '
      'ema=${smoothedMbps.toStringAsFixed(2)} Mbps)';
}

/// A single round-trip-time measurement emitted during the latency phase.
class LatencySample extends Sample {
  /// Round-trip time in milliseconds.
  final double rttMs;

  LatencySample({required int timestampMs, required this.rttMs})
    : super(timestampMs);

  @override
  String toString() =>
      'LatencySample(t=${timestampMs}ms, rtt=${rttMs.toStringAsFixed(2)}ms)';
}
