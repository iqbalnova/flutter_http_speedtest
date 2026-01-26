// lib/src/models/exceptions.dart

/// Thrown when a speed test is explicitly canceled by the user
///
/// This is NOT an error - it's a normal control flow state.
/// Cancellation should never trigger error callbacks or be logged as failures.
class SpeedTestCanceledException implements Exception {
  final String message;

  SpeedTestCanceledException([this.message = 'Speed test was canceled']);

  @override
  String toString() => 'SpeedTestCanceledException: $message';
}

/// Thrown when a phase times out
class SpeedTestTimeoutException implements Exception {
  final String phase;
  final Duration timeout;

  SpeedTestTimeoutException(this.phase, this.timeout);

  @override
  String toString() =>
      'SpeedTestTimeoutException: $phase timed out after ${timeout.inSeconds}s';
}

/// Thrown when a phase fails due to network or other errors
class SpeedTestPhaseException implements Exception {
  final String phase;
  final Object cause;

  SpeedTestPhaseException(this.phase, this.cause);

  @override
  String toString() => 'SpeedTestPhaseException in $phase: $cause';
}

/// Thrown when there is no internet connection or network unreachable
class SpeedTestNoInternetException implements Exception {
  final String message;
  final Object? cause;

  SpeedTestNoInternetException([
    this.message = 'No internet connection',
    this.cause,
  ]);

  @override
  String toString() =>
      'SpeedTestNoInternetException: $message${cause != null ? ' ($cause)' : ''}';
}
