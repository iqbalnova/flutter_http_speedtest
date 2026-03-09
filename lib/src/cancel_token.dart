// lib/src/cancel_token.dart

import 'dart:async';
import 'models/exceptions.dart';

/// A token that propagates cancellation across async operations.
///
/// Every service in the speed test pipeline accepts a [CancelToken].
/// When [cancel] is called the token transitions to the canceled state
/// and all futures racing against it via [race] immediately throw
/// [SpeedTestCanceledException].
///
/// ```dart
/// final token = CancelToken();
/// // In service code:
/// final data = await token.race(httpClient.getUrl(uri));
/// token.throwIfCanceled();
/// ```
class CancelToken {
  final Completer<void> _completer = Completer<void>();
  bool _canceled = false;

  /// Whether [cancel] has been called.
  bool get isCanceled => _canceled;

  /// Completes when [cancel] is called. Useful for `Future.any` races.
  Future<void> get future => _completer.future;

  /// Transition to the canceled state.
  ///
  /// Idempotent – calling more than once is a no-op.
  void cancel() {
    if (!_canceled) {
      _canceled = true;
      if (!_completer.isCompleted) {
        _completer.complete();
      }
    }
  }

  /// Throws [SpeedTestCanceledException] if already canceled.
  void throwIfCanceled() {
    if (_canceled) throw SpeedTestCanceledException();
  }

  /// Race [future] against the cancellation signal.
  ///
  /// If the token is already canceled the method throws immediately.
  /// Otherwise it returns the result of [future] or throws
  /// [SpeedTestCanceledException] – whichever comes first.
  Future<T> race<T>(Future<T> future) async {
    throwIfCanceled();
    final result = await Future.any<T>([
      future,
      _completer.future.then<T>((_) => throw SpeedTestCanceledException()),
    ]);
    return result;
  }
}
