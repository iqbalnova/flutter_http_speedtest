// lib/src/models/phase_status.dart

import 'enums.dart';

class PhaseStatus {
  final PhaseState state;
  final String? errorMessage;

  PhaseStatus.success() : state = PhaseState.success, errorMessage = null;

  PhaseStatus.failed(this.errorMessage) : state = PhaseState.failed;

  PhaseStatus.timeout()
    : state = PhaseState.timeout,
      errorMessage = 'Operation timed out';

  PhaseStatus.canceled()
    : state = PhaseState.canceled,
      errorMessage = 'Canceled by user';

  bool get isSuccess => state == PhaseState.success;
  bool get isFailed => state == PhaseState.failed;
  bool get isTimeout => state == PhaseState.timeout;
  bool get isCanceled => state == PhaseState.canceled;

  @override
  String toString() {
    if (errorMessage != null) {
      return 'PhaseStatus($state: $errorMessage)';
    }
    return 'PhaseStatus($state)';
  }
}
