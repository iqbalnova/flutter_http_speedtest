// lib/src/models/phase_status.dart

import 'enums.dart';

/// Status of a single test phase.
class PhaseStatus {
  /// Current lifecycle state.
  final PhaseState state;

  /// Human-readable error detail (non-null for failed / timeout / canceled).
  final String? errorMessage;

  const PhaseStatus._(this.state, [this.errorMessage]);

  /// Phase has not started yet.
  const PhaseStatus.pending() : this._(PhaseState.pending);

  /// Phase is currently executing.
  const PhaseStatus.running() : this._(PhaseState.running);

  /// Phase completed successfully.
  const PhaseStatus.success() : this._(PhaseState.success);

  /// Phase failed with [errorMessage].
  const PhaseStatus.failed(String errorMessage)
    : this._(PhaseState.failed, errorMessage);

  /// Phase timed out.
  const PhaseStatus.timeout()
    : this._(PhaseState.timeout, 'Operation timed out');

  /// Phase was canceled by the user.
  const PhaseStatus.canceled()
    : this._(PhaseState.canceled, 'Canceled by user');

  /// Phase was intentionally skipped (e.g. non-critical metadata failure).
  const PhaseStatus.skipped() : this._(PhaseState.skipped, 'Skipped');

  bool get isPending => state == PhaseState.pending;
  bool get isRunning => state == PhaseState.running;
  bool get isSuccess => state == PhaseState.success;
  bool get isFailed => state == PhaseState.failed;
  bool get isTimeout => state == PhaseState.timeout;
  bool get isCanceled => state == PhaseState.canceled;
  bool get isSkipped => state == PhaseState.skipped;

  @override
  String toString() {
    if (errorMessage != null) return 'PhaseStatus($state: $errorMessage)';
    return 'PhaseStatus($state)';
  }
}
