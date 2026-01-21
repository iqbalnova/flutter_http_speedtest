// lib/src/models/speed_test_result.dart

import 'metadata.dart';
import 'network_quality.dart';
import 'phase_status.dart';
import 'sample.dart';
import 'enums.dart';

class SpeedTestResult {
  final double? downloadMbps;
  final double? uploadMbps;
  final double? latencyMs;
  final double? jitterMs;
  final double? packetLossPercent;
  final double? loadedLatencyMs;
  final NetworkMetadata? metadata;
  final List<SpeedSample> downloadSeries;
  final List<SpeedSample> uploadSeries;
  final List<LatencySample> latencySeries;
  final NetworkQuality quality;
  final Map<TestPhase, PhaseStatus> phaseStatuses;

  SpeedTestResult({
    this.downloadMbps,
    this.uploadMbps,
    this.latencyMs,
    this.jitterMs,
    this.packetLossPercent,
    this.loadedLatencyMs,
    this.metadata,
    required this.downloadSeries,
    required this.uploadSeries,
    required this.latencySeries,
    required this.quality,
    required this.phaseStatuses,
  });

  bool get hasDownload => downloadMbps != null;
  bool get hasUpload => uploadMbps != null;
  bool get hasLatency => latencyMs != null;

  @override
  String toString() {
    final buffer = StringBuffer('SpeedTestResult:\n');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    if (downloadMbps != null) {
      buffer.writeln('Download: ${downloadMbps!.toStringAsFixed(2)} Mbps');
    }
    if (uploadMbps != null) {
      buffer.writeln('Upload: ${uploadMbps!.toStringAsFixed(2)} Mbps');
    }

    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    if (latencyMs != null) {
      buffer.writeln('Latency: ${latencyMs!.toStringAsFixed(1)} ms');
    }
    if (jitterMs != null) {
      buffer.writeln('Jitter: ${jitterMs!.toStringAsFixed(1)} ms');
    }
    if (packetLossPercent != null) {
      buffer.writeln('Packet Loss: ${packetLossPercent!.toStringAsFixed(1)}%');
    }
    if (loadedLatencyMs != null) {
      buffer.writeln(
        'Loaded Latency: ${loadedLatencyMs!.toStringAsFixed(1)} ms',
      );
    }

    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('Quality Scores:');
    buffer.writeln('  ${quality.streaming}');
    buffer.writeln('  ${quality.gaming}');
    buffer.writeln('  ${quality.rtc}');

    if (metadata != null) {
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln(metadata);
    }

    return buffer.toString();
  }
}
