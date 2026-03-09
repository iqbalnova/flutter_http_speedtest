// lib/src/models/speed_test_result.dart

import 'metadata.dart';
import 'network_quality.dart';
import 'phase_status.dart';
import 'sample.dart';
import 'enums.dart';

/// Complete result of a speed test run.
class SpeedTestResult {
  // ── Speed ────────────────────────────────────────────────────────────
  final double? downloadMbps;
  final double? uploadMbps;

  // ── Latency ──────────────────────────────────────────────────────────
  final double? latencyMs;
  final double? jitterMs;
  final double? packetLossPercent;
  final double? latencyMinMs;
  final double? latencyMaxMs;
  final double? latencyMedianMs;

  // ── Loaded latency (bufferbloat) ────────────────────────────────────
  final double? loadedLatencyMs;

  // ── Metadata ────────────────────────────────────────────────────────
  final NetworkMetadata? metadata;

  // ── Time-series ─────────────────────────────────────────────────────
  final List<SpeedSample> downloadSeries;
  final List<SpeedSample> uploadSeries;
  final List<LatencySample> latencySeries;

  // ── Quality ─────────────────────────────────────────────────────────
  final NetworkQuality quality;

  // ── Phase statuses ──────────────────────────────────────────────────
  final Map<TestPhase, PhaseStatus> phaseStatuses;

  SpeedTestResult({
    this.downloadMbps,
    this.uploadMbps,
    this.latencyMs,
    this.jitterMs,
    this.packetLossPercent,
    this.latencyMinMs,
    this.latencyMaxMs,
    this.latencyMedianMs,
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
    final b = StringBuffer('SpeedTestResult:\n');
    b.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    if (downloadMbps != null) {
      b.writeln('Download : ${downloadMbps!.toStringAsFixed(2)} Mbps');
    }
    if (uploadMbps != null) {
      b.writeln('Upload   : ${uploadMbps!.toStringAsFixed(2)} Mbps');
    }
    b.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    if (latencyMs != null) {
      b.writeln('Latency  : ${latencyMs!.toStringAsFixed(1)} ms');
    }
    if (latencyMinMs != null) {
      b.writeln('  Min    : ${latencyMinMs!.toStringAsFixed(1)} ms');
    }
    if (latencyMaxMs != null) {
      b.writeln('  Max    : ${latencyMaxMs!.toStringAsFixed(1)} ms');
    }
    if (latencyMedianMs != null) {
      b.writeln('  Median : ${latencyMedianMs!.toStringAsFixed(1)} ms');
    }
    if (jitterMs != null) {
      b.writeln('Jitter   : ${jitterMs!.toStringAsFixed(1)} ms');
    }
    if (packetLossPercent != null) {
      b.writeln('Loss     : ${packetLossPercent!.toStringAsFixed(1)} %');
    }
    if (loadedLatencyMs != null) {
      b.writeln('Loaded   : ${loadedLatencyMs!.toStringAsFixed(1)} ms');
    }
    b.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    b.writeln('Quality  : ${quality.overallGrade.name.toUpperCase()}');
    b.writeln('  ${quality.streaming}');
    b.writeln('  ${quality.gaming}');
    b.writeln('  ${quality.rtc}');
    if (metadata != null) {
      b.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      b.writeln(metadata);
    }
    return b.toString();
  }
}
