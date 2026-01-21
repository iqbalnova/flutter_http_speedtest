// lib/src/models/sample.dart

abstract class Sample {
  final int timestampMs;
  Sample(this.timestampMs);
}

class SpeedSample extends Sample {
  final double mbps;

  SpeedSample({required int timestampMs, required this.mbps})
    : super(timestampMs);

  @override
  String toString() =>
      'SpeedSample(time: ${timestampMs}ms, speed: ${mbps.toStringAsFixed(2)} Mbps)';
}

class LatencySample extends Sample {
  final double rttMs;

  LatencySample({required int timestampMs, required this.rttMs})
    : super(timestampMs);

  @override
  String toString() =>
      'LatencySample(time: ${timestampMs}ms, rtt: ${rttMs.toStringAsFixed(2)}ms)';
}
