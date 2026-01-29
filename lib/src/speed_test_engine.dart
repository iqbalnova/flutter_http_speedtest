// lib/src/speed_test_engine.dart

import 'dart:async';
import 'dart:io';

import 'models/speed_test_result.dart';
import 'models/speed_test_options.dart';
import 'models/metadata.dart';
import 'models/phase_status.dart';
import 'models/sample.dart';
import 'models/enums.dart';
import 'models/exceptions.dart';
import 'services/latency_service.dart';
import 'services/download_service.dart';
import 'services/tcp_ping_service.dart';
import 'services/upload_service.dart';
import 'services/metadata_service.dart';
import 'services/quality_scorer.dart';

/// Main speed test engine with production-grade cancel and error handling
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
  bool _hasError = false; // Track if error occurred
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
  ///
  /// Triggers immediate cancellation of all phases.
  /// No callbacks will be invoked after cancel.
  void cancel() {
    if (!_canceled) {
      _canceled = true;
      if (!_cancelCompleter.isCompleted) {
        _cancelCompleter.complete();
      }
    }
  }

  /// Run the complete speed test
  ///
  /// Returns the result on success.
  /// Throws on errors.
  /// Returns null and invokes no callbacks on cancel or error.
  Future<SpeedTestResult?> run() async {
    _canceled = false;
    _hasError = false;
    final globalTimeout = Timer(options.maxTotalDuration, () => cancel());

    try {
      final result = await _runTest();
      globalTimeout.cancel();

      // CRITICAL: Only call onCompleted if not canceled AND no error occurred
      if (!_canceled && !_hasError) {
        onCompleted?.call(result);
      }

      return result;
    } on SpeedTestCanceledException catch (_) {
      // Cancellation is NOT an error - exit silently
      globalTimeout.cancel();
      return null;
    } on SocketException catch (e, stack) {
      // Connection error - stop immediately
      globalTimeout.cancel();
      _hasError = true;

      if (!_canceled) {
        onError?.call(e, stack);
      }
      return null;
    } on TimeoutException catch (e, stack) {
      // Timeout error - stop immediately
      globalTimeout.cancel();
      _hasError = true;

      if (!_canceled) {
        onError?.call(e, stack);
      }
      return null;
    } catch (e, stack) {
      // Any other error - stop immediately
      globalTimeout.cancel();
      _hasError = true;

      if (!_canceled) {
        onError?.call(e, stack);
      }
      return null;
    }
  }

  Future<SpeedTestResult> _runTest() async {
    final latencyService = LatencyService(options);
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

    // ====================================================================
    // Phase 1: Metadata
    // ====================================================================
    _checkCanceled();
    onPhaseChanged?.call(TestPhase.metadata);

    try {
      metadata = await _runPhase(
        TestPhase.metadata,
        () => metadataService.fetchMetadata(),
        statuses,
      );
    } catch (e) {
      if (e is SpeedTestCanceledException) {
        rethrow;
      }
      // Connection errors in metadata phase should stop the test
      if (e is SocketException || e is TimeoutException) {
        statuses[TestPhase.metadata] = PhaseStatus.failed(e.toString());
        rethrow; // Stop immediately
      }
      // Other errors are non-critical, continue
      statuses[TestPhase.metadata] = PhaseStatus.failed(e.toString());
    }

    // ====================================================================
    // Phase 2: Ping/Latency
    // ====================================================================
    _checkCanceled();
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
      if (e is SpeedTestCanceledException) {
        rethrow;
      }
      // Connection errors should stop the test
      if (e is SocketException || e is TimeoutException) {
        statuses[TestPhase.ping] = PhaseStatus.failed(e.toString());
        rethrow; // Stop immediately
      }
      statuses[TestPhase.ping] = PhaseStatus.failed(e.toString());
    }

    // ====================================================================
    // Phase 3: Download
    // ====================================================================
    _checkCanceled();
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
      if (e is SpeedTestCanceledException) {
        rethrow;
      }
      // Connection errors should stop the test
      if (e is SocketException || e is TimeoutException) {
        statuses[TestPhase.download] = PhaseStatus.failed(e.toString());
        rethrow; // Stop immediately
      }
      statuses[TestPhase.download] = PhaseStatus.failed(e.toString());
    }

    // ====================================================================
    // Phase 4: Upload
    // ====================================================================
    _checkCanceled();
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
      if (e is SpeedTestCanceledException) {
        rethrow;
      }
      // Connection errors should stop the test
      if (e is SocketException || e is TimeoutException) {
        statuses[TestPhase.upload] = PhaseStatus.failed(e.toString());
        rethrow; // Stop immediately
      }
      statuses[TestPhase.upload] = PhaseStatus.failed(e.toString());
    }

    // ====================================================================
    // Final check before building result
    // ====================================================================
    _checkCanceled();

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

  /// Check if test was canceled and throw if so
  void _checkCanceled() {
    if (_canceled) {
      throw SpeedTestCanceledException();
    }
  }

  /// Run a single test phase with proper error handling
  Future<T> _runPhase<T>(
    TestPhase phase,
    Future<T> Function() fn,
    Map<TestPhase, PhaseStatus> statuses,
  ) async {
    try {
      // Check cancel before starting phase
      _checkCanceled();

      final result = await fn();

      // Check cancel after phase completes
      _checkCanceled();

      statuses[phase] = PhaseStatus.success();
      return result;
    } on SpeedTestCanceledException {
      // Mark as canceled and rethrow
      statuses[phase] = PhaseStatus.canceled();
      rethrow;
    } on SocketException catch (e) {
      // Connection error - mark and rethrow to stop test
      statuses[phase] = PhaseStatus.failed('Connection error: ${e.message}');
      rethrow;
    } on TimeoutException {
      statuses[phase] = PhaseStatus.timeout();
      throw SpeedTestTimeoutException(
        phase.toString(),
        options.maxTotalDuration,
      );
    } catch (e) {
      statuses[phase] = PhaseStatus.failed(e.toString());
      rethrow; // Rethrow all errors to stop the test
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
