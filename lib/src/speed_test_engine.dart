// lib/src/speed_test_engine.dart

import 'dart:async';
import 'dart:io';

import 'cancel_token.dart';
import 'models/speed_test_result.dart';
import 'models/speed_test_options.dart';
import 'models/metadata.dart';
import 'models/phase_status.dart';
import 'models/sample.dart';
import 'models/enums.dart';
import 'models/exceptions.dart';
import 'services/latency_service.dart';
import 'services/download_service.dart';
import 'services/upload_service.dart';
import 'services/metadata_service.dart';
import 'services/quality_scorer.dart';

/// Production-grade speed test orchestrator (Ookla methodology).
///
/// Runs metadata → ping → download (+ loaded latency) → upload in sequence.
/// Uses a shared [CancelToken] for cooperative cancellation across all phases.
///
/// The engine is **reusable** — call [run] multiple times.
/// Each invocation resets state and creates a fresh [CancelToken].
class SpeedTestEngine {
  /// Tunables for the entire run.
  final SpeedTestOptions options;

  // ── Callbacks ──────────────────────────────────────────────────────

  /// Fires when a phase begins or its status changes.
  void Function(TestPhase phase, PhaseStatus status)? onPhaseChanged;

  /// Fires for every latency or speed sample (for gauge animation).
  void Function(Sample sample)? onSample;

  /// Fires once after all phases complete successfully.
  void Function(SpeedTestResult result)? onCompleted;

  /// Fires on fatal errors (never on cancel).
  void Function(Object error, StackTrace stack)? onError;

  // ── Internal state ─────────────────────────────────────────────────

  CancelToken _cancelToken = CancelToken();

  SpeedTestEngine({
    this.options = const SpeedTestOptions(),
    this.onPhaseChanged,
    this.onSample,
    this.onCompleted,
    this.onError,
  });

  /// Cancel the currently running test.
  ///
  /// Idempotent — safe to call more than once or when idle.
  /// After cancellation the engine can be reused; [run] creates a fresh
  /// [CancelToken] on each invocation.
  void cancel() => _cancelToken.cancel();

  /// Run the complete speed test.
  ///
  /// Returns a [SpeedTestResult] on success, or `null` if the test was
  /// canceled or a fatal error occurred.
  Future<SpeedTestResult?> run() async {
    // Fresh state for every run — makes the engine fully reusable.
    _cancelToken = CancelToken();
    final ct = _cancelToken;

    final globalTimeout = Timer(options.maxTotalDuration, cancel);

    try {
      final result = await _runTest(ct);
      globalTimeout.cancel();

      if (!ct.isCanceled) {
        onCompleted?.call(result);
      }
      return result;
    } on SpeedTestCanceledException {
      // Cancel is NOT an error — exit silently, zero callbacks.
      globalTimeout.cancel();
      return null;
    } catch (e, stack) {
      globalTimeout.cancel();
      if (!ct.isCanceled) {
        onError?.call(e, stack);
      }
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Internal orchestration
  // ══════════════════════════════════════════════════════════════════════

  Future<SpeedTestResult> _runTest(CancelToken ct) async {
    final latencyService = LatencyService(options);
    final downloadService = DownloadService(options);
    final uploadService = UploadService(options);
    final metadataService = MetadataService(options);

    // Phase statuses — start everything as pending.
    final statuses = <TestPhase, PhaseStatus>{
      TestPhase.metadata: const PhaseStatus.pending(),
      TestPhase.ping: const PhaseStatus.pending(),
      TestPhase.download: const PhaseStatus.pending(),
      TestPhase.upload: const PhaseStatus.pending(),
    };

    // Collected results
    double? downloadMbps;
    double? uploadMbps;
    double? latencyMs;
    double? jitterMs;
    double? packetLossPercent;
    double? latencyMinMs;
    double? latencyMaxMs;
    double? latencyMedianMs;
    double? loadedLatencyMs;
    NetworkMetadata? metadata;

    final downloadSeries = <SpeedSample>[];
    final uploadSeries = <SpeedSample>[];
    final latencySeries = <LatencySample>[];

    // ================================================================
    // Phase 1: Metadata (non-critical — log and skip on failure)
    // ================================================================
    ct.throwIfCanceled();
    _emit(TestPhase.metadata, const PhaseStatus.running(), statuses);

    try {
      metadata = await _withRetry(
        () => metadataService.fetchMetadata(cancelToken: ct),
        ct,
      );
      _emit(TestPhase.metadata, const PhaseStatus.success(), statuses);
    } on SpeedTestCanceledException {
      _emit(TestPhase.metadata, const PhaseStatus.canceled(), statuses);
      rethrow;
    } catch (_) {
      // Metadata failure is non-critical — skip and continue.
      _emit(TestPhase.metadata, const PhaseStatus.skipped(), statuses);
    }

    // ================================================================
    // Phase 2: Ping / Latency (critical — stop on failure)
    // ================================================================
    ct.throwIfCanceled();
    _emit(TestPhase.ping, const PhaseStatus.running(), statuses);

    try {
      final pingResult = await _withRetry(
        () => latencyService.measureLatency(
          cancelToken: ct,
          onSample: (sample) {
            latencySeries.add(sample);
            onSample?.call(sample);
          },
        ),
        ct,
      );
      latencyMs = pingResult.latencyMs;
      jitterMs = pingResult.jitterMs;
      packetLossPercent = pingResult.packetLossPercent;
      latencyMinMs = pingResult.minMs;
      latencyMaxMs = pingResult.maxMs;
      latencyMedianMs = pingResult.medianMs;
      _emit(TestPhase.ping, const PhaseStatus.success(), statuses);
    } on SpeedTestCanceledException {
      _emit(TestPhase.ping, const PhaseStatus.canceled(), statuses);
      rethrow;
    } catch (e) {
      _emit(TestPhase.ping, PhaseStatus.failed(e.toString()), statuses);
      rethrow; // Ping failure → stop entire test
    }

    // ================================================================
    // Phase 3: Download + loaded latency (concurrent)
    // ================================================================
    ct.throwIfCanceled();
    _emit(TestPhase.download, const PhaseStatus.running(), statuses);

    try {
      final dlFuture = _withRetry(
        () => downloadService.measureDownload(
          cancelToken: ct,
          onSample: (sample) {
            downloadSeries.add(sample);
            onSample?.call(sample);
          },
        ),
        ct,
      );

      final llFuture = latencyService.measureLoadedLatency(cancelToken: ct);

      final results = await Future.wait<Object?>([dlFuture, llFuture]);
      downloadMbps = results[0] as double;
      loadedLatencyMs = results[1] as double?;

      _emit(TestPhase.download, const PhaseStatus.success(), statuses);
    } on SpeedTestCanceledException {
      _emit(TestPhase.download, const PhaseStatus.canceled(), statuses);
      rethrow;
    } catch (e) {
      _emit(TestPhase.download, PhaseStatus.failed(e.toString()), statuses);
      rethrow; // Download failure → stop
    }

    // ================================================================
    // Phase 4: Upload (critical — stop on failure)
    // ================================================================
    ct.throwIfCanceled();
    _emit(TestPhase.upload, const PhaseStatus.running(), statuses);

    try {
      uploadMbps = await _withRetry(
        () => uploadService.measureUpload(
          cancelToken: ct,
          onSample: (sample) {
            uploadSeries.add(sample);
            onSample?.call(sample);
          },
        ),
        ct,
      );
      _emit(TestPhase.upload, const PhaseStatus.success(), statuses);
    } on SpeedTestCanceledException {
      _emit(TestPhase.upload, const PhaseStatus.canceled(), statuses);
      rethrow;
    } catch (e) {
      _emit(TestPhase.upload, PhaseStatus.failed(e.toString()), statuses);
      rethrow; // Upload failure → stop
    }

    // ================================================================
    // Build result
    // ================================================================
    ct.throwIfCanceled();

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
      latencyMinMs: latencyMinMs,
      latencyMaxMs: latencyMaxMs,
      latencyMedianMs: latencyMedianMs,
      loadedLatencyMs: loadedLatencyMs,
      metadata: metadata,
      downloadSeries: downloadSeries,
      uploadSeries: uploadSeries,
      latencySeries: latencySeries,
      quality: quality,
      phaseStatuses: statuses,
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // Helpers
  // ══════════════════════════════════════════════════════════════════════

  /// Emit a phase status change and notify the callback.
  void _emit(
    TestPhase phase,
    PhaseStatus status,
    Map<TestPhase, PhaseStatus> statuses,
  ) {
    statuses[phase] = status;
    onPhaseChanged?.call(phase, status);
  }

  /// Retry [fn] up to [options.retries] additional attempts.
  ///
  /// Only retries on timeout / HTTP errors.
  /// [SocketException] (network down) and cancellation propagate immediately.
  Future<T> _withRetry<T>(
    Future<T> Function() fn,
    CancelToken cancelToken, {
    int? maxAttempts,
    Duration delay = const Duration(milliseconds: 500),
  }) async {
    final attempts = (maxAttempts ?? options.retries) + 1;
    for (int attempt = 0; attempt < attempts; attempt++) {
      cancelToken.throwIfCanceled();
      try {
        return await fn();
      } on SpeedTestCanceledException {
        rethrow;
      } on SocketException {
        rethrow; // Network down — no point retrying.
      } catch (e) {
        if (attempt == attempts - 1) rethrow;
        await Future.delayed(delay);
        cancelToken.throwIfCanceled();
      }
    }
    throw StateError('unreachable');
  }
}
