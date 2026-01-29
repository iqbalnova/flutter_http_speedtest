// lib/services/realtime_ping_monitor.dart

import 'dart:async';
import 'package:dart_ping/dart_ping.dart';
import 'package:flutter/foundation.dart';

/// Simple ping monitoring data
class RealtimePingStats {
  final double? currentPing;
  final double packetLossPercent;
  final bool isReachable;

  RealtimePingStats({
    this.currentPing,
    required this.packetLossPercent,
    required this.isReachable,
  });

  factory RealtimePingStats.initial() {
    return RealtimePingStats(
      currentPing: null,
      packetLossPercent: 0.0,
      isReachable: false,
    );
  }

  String get pingText {
    if (currentPing == null) return '--';
    return '${currentPing!.toStringAsFixed(0)} ms';
  }

  String get packetLossText {
    if (packetLossPercent == 0) return 'No Packet Loss';
    return '${packetLossPercent.toStringAsFixed(1)}%';
  }

  bool get hasPacketLoss => packetLossPercent > 0;
}

/// Simple service for real-time ping monitoring
class RealtimePingMonitor {
  final String ipAddress;
  final Duration pingInterval;
  final Duration timeout;

  StreamSubscription? _pingSubscription;
  Timer? _intervalTimer;
  final StreamController<RealtimePingStats> _statsController =
      StreamController<RealtimePingStats>.broadcast();

  double? _lastPing;
  bool _isDisposed = false;

  // Packet loss tracking
  int _packetsSent = 0;
  int _packetsLost = 0;

  RealtimePingMonitor({
    required this.ipAddress,
    this.pingInterval = const Duration(seconds: 1),
    this.timeout = const Duration(seconds: 2),
  });

  /// Stream of ping statistics
  Stream<RealtimePingStats> get statsStream => _statsController.stream;

  /// Start monitoring
  void start() {
    if (_intervalTimer != null || _isDisposed) return;

    debugPrint('Starting ping monitor for $ipAddress');

    // Send initial ping immediately
    _sendPing();

    // Schedule periodic pings
    _intervalTimer = Timer.periodic(pingInterval, (_) {
      if (!_isDisposed) {
        _sendPing();
      }
    });
  }

  /// Stop monitoring
  void stop() {
    debugPrint('Stopping ping monitor for $ipAddress');
    _intervalTimer?.cancel();
    _intervalTimer = null;
    _pingSubscription?.cancel();
    _pingSubscription = null;
  }

  /// Send a single ping
  void _sendPing() async {
    if (_isDisposed) return;

    _packetsSent++;

    try {
      final ping = Ping(
        ipAddress,
        count: 1,
        timeout: timeout.inSeconds > 0 ? timeout.inSeconds : 2,
        interval: 1,
      );

      bool hasResponse = false;
      final completer = Completer<void>();

      // Timeout timer
      final timeoutTimer = Timer(
        timeout + const Duration(milliseconds: 500),
        () {
          if (!hasResponse && !completer.isCompleted) {
            _handleTimeout();
            completer.complete();
          }
        },
      );

      _pingSubscription?.cancel();
      _pingSubscription = ping.stream.listen(
        (event) {
          if (_isDisposed) return;

          if (event.response != null && event.response!.time != null) {
            final latency = event.response!.time!.inMicroseconds / 1000.0;

            if (latency > 0 && latency < timeout.inMilliseconds) {
              hasResponse = true;
              _handleSuccess(latency);
              timeoutTimer.cancel();

              if (!completer.isCompleted) {
                completer.complete();
              }
            }
          } else if (event.error != null) {
            if (!hasResponse && !completer.isCompleted) {
              _handleTimeout();
              timeoutTimer.cancel();
              completer.complete();
            }
          }
        },
        onDone: () {
          if (!hasResponse && !completer.isCompleted) {
            _handleTimeout();
            timeoutTimer.cancel();
            completer.complete();
          }
        },
        onError: (e) {
          if (!hasResponse && !completer.isCompleted) {
            _handleTimeout();
            timeoutTimer.cancel();
            completer.complete();
          }
        },
        cancelOnError: true,
      );

      await completer.future;
      _pingSubscription?.cancel();
      _pingSubscription = null;
    } catch (e) {
      debugPrint('Ping error for $ipAddress: $e');
      if (!_isDisposed) {
        _handleTimeout();
      }
    }
  }

  /// Handle successful ping
  void _handleSuccess(double latency) {
    if (_isDisposed) return;

    _lastPing = latency;

    debugPrint('Ping $ipAddress: ${latency.toStringAsFixed(1)} ms');

    // Only add to stream if not disposed and controller is not closed
    if (!_isDisposed && !_statsController.isClosed) {
      _statsController.add(
        RealtimePingStats(
          currentPing: latency,
          packetLossPercent: _calculatePacketLoss(),
          isReachable: true,
        ),
      );
    }
  }

  /// Handle timeout
  void _handleTimeout() {
    if (_isDisposed) return;

    _packetsLost++;

    debugPrint('Ping timeout for $ipAddress');

    // Only add to stream if not disposed and controller is not closed
    if (!_isDisposed && !_statsController.isClosed) {
      _statsController.add(
        RealtimePingStats(
          currentPing: _lastPing,
          packetLossPercent: _calculatePacketLoss(),
          isReachable: false,
        ),
      );
    }
  }

  /// Calculate packet loss percentage
  double _calculatePacketLoss() {
    if (_packetsSent == 0) return 0.0;
    return (_packetsLost / _packetsSent) * 100.0;
  }

  /// Dispose resources
  void dispose() {
    if (_isDisposed) return;

    debugPrint('Disposing ping monitor for $ipAddress');
    _isDisposed = true;

    stop();

    // Close stream controller after a small delay to ensure all pending events are processed
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_statsController.isClosed) {
        _statsController.close();
      }
    });
  }
}
