// lib/src/models/exceptions.dart

/// Thrown when a speed test is explicitly canceled by the user.
///
/// This is NOT an error – it is normal control flow.
/// Cancellation must never trigger error callbacks.
class SpeedTestCanceledException implements Exception {
  final String message;
  SpeedTestCanceledException([this.message = 'Speed test was canceled']);

  @override
  String toString() => 'SpeedTestCanceledException: $message';
}

/// Thrown when a phase exceeds its configured timeout.
class SpeedTestTimeoutException implements Exception {
  final String phase;
  final Duration timeout;
  SpeedTestTimeoutException(this.phase, this.timeout);

  @override
  String toString() =>
      'SpeedTestTimeoutException: $phase timed out after ${timeout.inSeconds}s';
}

/// Thrown when a phase fails due to an underlying error.
class SpeedTestPhaseException implements Exception {
  final String phase;
  final Object cause;
  SpeedTestPhaseException(this.phase, this.cause);

  @override
  String toString() => 'SpeedTestPhaseException in $phase: $cause';
}

/// Thrown when there is no internet connection or the network is unreachable.
class SpeedTestNoInternetException implements Exception {
  final String message;
  final Object? cause;
  SpeedTestNoInternetException([
    this.message = 'No internet connection',
    this.cause,
  ]);

  @override
  String toString() =>
      'SpeedTestNoInternetException: $message'
      '${cause != null ? ' ($cause)' : ''}';
}

/// Thrown when the server responds with HTTP 429 (Too Many Requests).
class SpeedTestRateLimitException implements Exception {
  final Duration? retryAfter;
  SpeedTestRateLimitException([this.retryAfter]);

  @override
  String toString() =>
      'SpeedTestRateLimitException: rate limited'
      '${retryAfter != null ? ', retry after ${retryAfter!.inSeconds}s' : ''}';
}
