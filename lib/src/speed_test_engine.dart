// lib/src/speed_test_engine.dart

import 'dart:async';

import 'package:flutter_http_speedtest/src/services/tcp_ping_service.dart';

import 'models/speed_test_result.dart';
import 'models/speed_test_options.dart';
import 'models/metadata.dart';
import 'models/phase_status.dart';
import 'models/sample.dart';
import 'models/enums.dart';
import 'services/latency_service.dart';
import 'services/download_service.dart';
import 'services/upload_service.dart';
import 'services/metadata_service.dart';
import 'services/quality_scorer.dart';

/// Main speed test engine
class SpeedTestEngine {
  final int downloadBytes;
  final int uploadBytes;
  final SpeedTestOptions options;

  // Callbacks
  void Function(TestPhase phase)? onPhaseChanged;
  void Function(Sample sample)? onSample;
  void Function(SpeedTestResult result)? onCompleted;
  void Function(Object error, StackTrace stack)? onError;

  bool _canceled = false;
  final Completer<void> _cancelCompleter = Completer<void>();

  SpeedTestEngine({
    this.downloadBytes = 3 * 1024 * 1024,
    this.uploadBytes = 3 * 1024 * 1024,
    this.options = const SpeedTestOptions(),
    this.onPhaseChanged,
    this.onSample,
    this.onCompleted,
    this.onError,
  });

  /// Cancel the current test
  void cancel() {
    if (!_canceled) {
      _canceled = true;
      if (!_cancelCompleter.isCompleted) {
        _cancelCompleter.complete();
      }
    }
  }

  /// Run the complete speed test
  Future<SpeedTestResult> run() async {
    _canceled = false;
    final _ = DateTime.now();
    final globalTimeout = Timer(options.maxTotalDuration, () => cancel());

    try {
      final result = await _runTest();
      globalTimeout.cancel();
      onCompleted?.call(result);
      return result;
    } catch (e, stack) {
      globalTimeout.cancel();
      onError?.call(e, stack);
      rethrow;
    }
  }

  Future<SpeedTestResult> _runTest() async {
    // final latencyService = LatencyService(options);
    final latencyService = TcpPingService(options);

    final downloadService = DownloadService(options);
    final uploadService = UploadService(options);
    final metadataService = MetadataService(options);

    // Phase statuses
    final statuses = <TestPhase, PhaseStatus>{};

    // Results
    double? downloadMbps;
    double? uploadMbps;
    double? latencyMs;
    double? jitterMs;
    double? packetLossPercent;
    double? loadedLatencyMs;
    NetworkMetadata? metadata;

    List<SpeedSample> downloadSeries = [];
    List<SpeedSample> uploadSeries = [];
    List<LatencySample> latencySeries = [];

    // Phase 1: Metadata
    onPhaseChanged?.call(TestPhase.metadata);
    try {
      metadata = await _runPhase(
        TestPhase.metadata,
        () => metadataService.fetchMetadata(),
        statuses,
      );
    } catch (e) {
      statuses[TestPhase.metadata] = PhaseStatus.failed(e.toString());
    }

    if (_canceled) {
      return _buildResult(
        statuses: statuses,
        downloadMbps: downloadMbps,
        uploadMbps: uploadMbps,
        latencyMs: latencyMs,
        jitterMs: jitterMs,
        packetLossPercent: packetLossPercent,
        loadedLatencyMs: loadedLatencyMs,
        metadata: metadata,
        downloadSeries: downloadSeries,
        uploadSeries: uploadSeries,
        latencySeries: latencySeries,
      );
    }

    // Phase 2: Ping/Latency
    onPhaseChanged?.call(TestPhase.ping);
    try {
      final pingResult = await _runPhase(
        TestPhase.ping,
        () => latencyService.measureLatency(
          onSample: (sample) {
            latencySeries.add(sample);
            onSample?.call(sample);
          },
          cancelToken: _cancelCompleter.future,
        ),
        statuses,
      );
      latencyMs = pingResult.latencyMs;
      jitterMs = pingResult.jitterMs;
      packetLossPercent = pingResult.packetLossPercent;
    } catch (e) {
      statuses[TestPhase.ping] = PhaseStatus.failed(e.toString());
    }

    if (_canceled) {
      return _buildResult(
        statuses: statuses,
        downloadMbps: downloadMbps,
        uploadMbps: uploadMbps,
        latencyMs: latencyMs,
        jitterMs: jitterMs,
        packetLossPercent: packetLossPercent,
        loadedLatencyMs: loadedLatencyMs,
        metadata: metadata,
        downloadSeries: downloadSeries,
        uploadSeries: uploadSeries,
        latencySeries: latencySeries,
      );
    }

    // Phase 3: Download
    onPhaseChanged?.call(TestPhase.download);
    try {
      final downloadResult = await _runPhase(
        TestPhase.download,
        () => downloadService.measureDownload(
          bytes: downloadBytes,
          onSample: (SpeedSample sample) {
            downloadSeries.add(sample);
            onSample?.call(sample);
          },
          onLoadedLatency: (ll) => loadedLatencyMs = ll,
          cancelToken: _cancelCompleter.future,
        ),
        statuses,
      );
      downloadMbps = downloadResult;
    } catch (e) {
      statuses[TestPhase.download] = PhaseStatus.failed(e.toString());
    }

    if (_canceled) {
      return _buildResult(
        statuses: statuses,
        downloadMbps: downloadMbps,
        uploadMbps: uploadMbps,
        latencyMs: latencyMs,
        jitterMs: jitterMs,
        packetLossPercent: packetLossPercent,
        loadedLatencyMs: loadedLatencyMs,
        metadata: metadata,
        downloadSeries: downloadSeries,
        uploadSeries: uploadSeries,
        latencySeries: latencySeries,
      );
    }

    // Phase 4: Upload
    onPhaseChanged?.call(TestPhase.upload);
    try {
      final uploadResult = await _runPhase(
        TestPhase.upload,
        () => uploadService.measureUpload(
          bytes: uploadBytes,
          onSample: (sample) {
            uploadSeries.add(sample);
            onSample?.call(sample);
          },
          cancelToken: _cancelCompleter.future,
        ),
        statuses,
      );
      uploadMbps = uploadResult;
    } catch (e) {
      statuses[TestPhase.upload] = PhaseStatus.failed(e.toString());
    }

    return _buildResult(
      statuses: statuses,
      downloadMbps: downloadMbps,
      uploadMbps: uploadMbps,
      latencyMs: latencyMs,
      jitterMs: jitterMs,
      packetLossPercent: packetLossPercent,
      loadedLatencyMs: loadedLatencyMs,
      metadata: metadata,
      downloadSeries: downloadSeries,
      uploadSeries: uploadSeries,
      latencySeries: latencySeries,
    );
  }

  Future<T> _runPhase<T>(
    TestPhase phase,
    Future<T> Function() fn,
    Map<TestPhase, PhaseStatus> statuses,
  ) async {
    try {
      final result = await fn();
      statuses[phase] = PhaseStatus.success();
      return result;
    } on TimeoutException {
      statuses[phase] = PhaseStatus.timeout();
      rethrow;
    } catch (e) {
      if (_canceled) {
        statuses[phase] = PhaseStatus.canceled();
      } else {
        statuses[phase] = PhaseStatus.failed(e.toString());
      }
      rethrow;
    }
  }

  SpeedTestResult _buildResult({
    required Map<TestPhase, PhaseStatus> statuses,
    required double? downloadMbps,
    required double? uploadMbps,
    required double? latencyMs,
    required double? jitterMs,
    required double? packetLossPercent,
    required double? loadedLatencyMs,
    required NetworkMetadata? metadata,
    required List<SpeedSample> downloadSeries,
    required List<SpeedSample> uploadSeries,
    required List<LatencySample> latencySeries,
  }) {
    final quality = QualityScorer.calculateQuality(
      latencyMs: latencyMs,
      jitterMs: jitterMs,
      packetLossPercent: packetLossPercent,
      downloadMbps: downloadMbps,
      uploadMbps: uploadMbps,
      loadedLatencyMs: loadedLatencyMs,
    );

    return SpeedTestResult(
      downloadMbps: downloadMbps,
      uploadMbps: uploadMbps,
      latencyMs: latencyMs,
      jitterMs: jitterMs,
      packetLossPercent: packetLossPercent,
      loadedLatencyMs: loadedLatencyMs,
      metadata: metadata,
      downloadSeries: downloadSeries,
      uploadSeries: uploadSeries,
      latencySeries: latencySeries,
      quality: quality,
      phaseStatuses: statuses,
    );
  }
}
