// lib/models/lan_device.dart

/// Represents a device found during LAN scanning
class LanDevice {
  /// IP address of the device
  final String ip;

  /// Ping latency in milliseconds (0.0 if unreachable)
  final double latencyMs;

  /// Whether the device responded to ping
  final bool reachable;

  /// Hostname resolved from reverse DNS lookup (null if not resolved)
  final String? hostname;

  const LanDevice({
    required this.ip,
    required this.latencyMs,
    required this.reachable,
    this.hostname,
  });

  /// Create a copy with updated hostname
  LanDevice copyWith({
    String? ip,
    double? latencyMs,
    bool? reachable,
    String? hostname,
  }) {
    return LanDevice(
      ip: ip ?? this.ip,
      latencyMs: latencyMs ?? this.latencyMs,
      reachable: reachable ?? this.reachable,
      hostname: hostname ?? this.hostname,
    );
  }

  @override
  String toString() {
    final hostnameStr = hostname != null ? ', hostname: $hostname' : '';
    return 'LanDevice(ip: $ip, latency: ${latencyMs.toStringAsFixed(1)}ms, reachable: $reachable$hostnameStr)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LanDevice &&
        other.ip == ip &&
        other.latencyMs == latencyMs &&
        other.reachable == reachable &&
        other.hostname == hostname;
  }

  @override
  int get hashCode => Object.hash(ip, latencyMs, reachable, hostname);
}

/// Custom exception for LAN scanning errors
class LanScanException implements Exception {
  final String message;
  final dynamic originalError;

  LanScanException(this.message, [this.originalError]);

  @override
  String toString() =>
      'LanScanException: $message${originalError != null ? ' ($originalError)' : ''}';
}
