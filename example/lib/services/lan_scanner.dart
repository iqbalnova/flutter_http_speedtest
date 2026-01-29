// lib/services/lan_scanner.dart

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:dart_ping/dart_ping.dart';
import 'package:dart_ping_ios/dart_ping_ios.dart';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/lan_device.dart';

/// Production-grade LAN scanner with platform-specific ICMP support
class LanScanner {
  final NetworkInfo _networkInfo = NetworkInfo();
  bool _isInitialized = false;
  Isolate? _scanIsolate;

  /// Initialize the scanner (required for iOS)
  Future<void> initialize() async {
    if (_isInitialized) return;

    if (Platform.isIOS) {
      try {
        // Register dart_ping_ios for iOS native ICMP support
        DartPingIOS.register();
        _isInitialized = true;
        debugPrint('iOS ICMP support initialized');
      } catch (e) {
        debugPrint('Warning: Failed to initialize iOS ping support: $e');
        _isInitialized = true;
      }
    } else {
      _isInitialized = true;
    }
  }

  /// Scan the local network for active devices
  ///
  /// [localIp] - Optional: Device's local IP. If null, auto-detected
  /// [timeout] - Ping timeout duration (default: 1000ms)
  /// [concurrency] - Max concurrent pings (default: 50 for Android, 30 for iOS)
  /// [resolveHostnames] - Whether to resolve hostnames (default: false)
  /// [onProgress] - Optional callback for scan progress (current/total)
  /// [onDeviceFound] - Optional callback when a device is found (for live updates)
  Future<List<LanDevice>> scan({
    String? localIp,
    Duration timeout = const Duration(milliseconds: 1000),
    int? concurrency,
    bool resolveHostnames = false,
    void Function(int current, int total)? onProgress,
    void Function(LanDevice device)? onDeviceFound,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Platform-specific concurrency defaults
    final effectiveConcurrency = concurrency ?? (Platform.isIOS ? 30 : 50);

    // Get local IP if not provided
    final baseIp = localIp ?? await _getLocalIp();
    if (baseIp == null) {
      throw LanScanException(
        'Unable to detect local IP address. Ensure device is connected to WiFi.',
      );
    }

    debugPrint('Starting scan from IP: $baseIp');

    // Extract subnet (only /24 networks)
    final subnet = _extractSubnet(baseIp);
    if (subnet == null) {
      throw LanScanException('Invalid IP address format: $baseIp');
    }

    // Generate IP range (1-254, excluding 0 and 255)
    final ipsToScan = List.generate(254, (i) => '$subnet.${i + 1}');

    debugPrint(
      'Scanning ${ipsToScan.length} IPs with concurrency: $effectiveConcurrency',
    );
    debugPrint('Platform: ${Platform.operatingSystem}');
    debugPrint('Resolve hostnames: $resolveHostnames');

    List<LanDevice> results;

    if (Platform.isIOS) {
      // iOS: Run on main thread because dart_ping_ios uses platform channels
      debugPrint('Running scan on MAIN thread (iOS)');
      results = await _scanOnMainThread(
        ips: ipsToScan,
        timeout: timeout,
        concurrency: effectiveConcurrency,
        resolveHostnames: resolveHostnames,
        onProgress: onProgress,
        onDeviceFound: onDeviceFound,
      );
    } else {
      // Android: Use isolate for better performance
      debugPrint('Running scan in ISOLATE (Android)');
      results = await _scanInIsolate(
        ips: ipsToScan,
        timeout: timeout,
        concurrency: effectiveConcurrency,
        resolveHostnames: resolveHostnames,
        onProgress: onProgress,
        onDeviceFound: onDeviceFound,
      );
    }

    return results;
  }

  /// Scan on main thread (used for iOS due to platform channel limitations)
  Future<List<LanDevice>> _scanOnMainThread({
    required List<String> ips,
    required Duration timeout,
    required int concurrency,
    required bool resolveHostnames,
    void Function(int current, int total)? onProgress,
    void Function(LanDevice device)? onDeviceFound,
  }) async {
    final results = <LanDevice>[];
    final resultLock = <String>{};

    await _scanWithConcurrency(
      ips: ips,
      timeout: timeout,
      concurrency: concurrency,
      resolveHostnames: resolveHostnames,
      onResult: (device) {
        if (device.reachable &&
            device.latencyMs > 0 &&
            !resultLock.contains(device.ip)) {
          resultLock.add(device.ip);
          results.add(device);
          onDeviceFound?.call(device);
        }
      },
      onProgress: (current, total) {
        onProgress?.call(current, total);

        // Yield to event loop periodically to keep UI responsive
        if (current % 10 == 0) {
          return Future.delayed(Duration.zero);
        }
        return Future.value();
      },
    );

    // Sort by IP address
    results.sort((a, b) => _compareIpAddresses(a.ip, b.ip));

    debugPrint('Main thread scan completed. Found ${results.length} devices');
    return results;
  }

  /// Run scan in separate isolate (Android only)
  Future<List<LanDevice>> _scanInIsolate({
    required List<String> ips,
    required Duration timeout,
    required int concurrency,
    required bool resolveHostnames,
    void Function(int current, int total)? onProgress,
    void Function(LanDevice device)? onDeviceFound,
  }) async {
    final receivePort = ReceivePort();
    final results = <LanDevice>[];
    final completer = Completer<List<LanDevice>>();

    // Listen to messages from isolate
    receivePort.listen((message) {
      if (message is SendPort) {
        // Initial handshake - send scan parameters
        message.send(
          _ScanRequest(
            ips: ips,
            timeoutMs: timeout.inMilliseconds,
            concurrency: concurrency,
            resolveHostnames: resolveHostnames,
          ),
        );
      } else if (message is _ScanProgress) {
        onProgress?.call(message.current, message.total);
      } else if (message is _ScanResult) {
        if (message.device.reachable && message.device.latencyMs > 0) {
          results.add(message.device);
          onDeviceFound?.call(message.device);
        }
      } else if (message is _ScanComplete) {
        // Sort by IP address
        results.sort((a, b) => _compareIpAddresses(a.ip, b.ip));
        completer.complete(results);
        receivePort.close();
        _scanIsolate?.kill(priority: Isolate.immediate);
        _scanIsolate = null;
      } else if (message is _ScanError) {
        completer.completeError(LanScanException(message.error));
        receivePort.close();
        _scanIsolate?.kill(priority: Isolate.immediate);
        _scanIsolate = null;
      }
    });

    // Spawn isolate
    _scanIsolate = await Isolate.spawn(
      _scanIsolateEntryPoint,
      receivePort.sendPort,
    );

    return completer.future;
  }

  /// Isolate entry point (Android only)
  static void _scanIsolateEntryPoint(SendPort mainSendPort) {
    final isolateReceivePort = ReceivePort();

    debugPrint('ISOLATE: Started on ${Isolate.current.debugName}');

    // Send our port back to main isolate
    mainSendPort.send(isolateReceivePort.sendPort);

    isolateReceivePort.listen((message) async {
      if (message is _ScanRequest) {
        try {
          debugPrint('ISOLATE: Performing scan of ${message.ips.length} IPs');
          debugPrint('ISOLATE: Resolve hostnames: ${message.resolveHostnames}');

          await _performScan(
            ips: message.ips,
            timeoutMs: message.timeoutMs,
            concurrency: message.concurrency,
            resolveHostnames: message.resolveHostnames,
            onProgress: (current, total) {
              mainSendPort.send(_ScanProgress(current: current, total: total));
            },
            onResult: (device) {
              mainSendPort.send(_ScanResult(device: device));
            },
          );

          debugPrint('ISOLATE: Scan complete');
          mainSendPort.send(_ScanComplete());
        } catch (e, stackTrace) {
          debugPrint('ISOLATE: Error - $e');
          debugPrint('ISOLATE: Stack trace - $stackTrace');
          mainSendPort.send(_ScanError(error: e.toString()));
        }
      }
    });
  }

  /// Perform scan in isolate
  static Future<void> _performScan({
    required List<String> ips,
    required int timeoutMs,
    required int concurrency,
    required bool resolveHostnames,
    required void Function(int current, int total) onProgress,
    required void Function(LanDevice) onResult,
  }) async {
    final timeout = Duration(milliseconds: timeoutMs);

    await _scanWithConcurrency(
      ips: ips,
      timeout: timeout,
      concurrency: concurrency,
      resolveHostnames: resolveHostnames,
      onResult: onResult,
      onProgress: (current, total) {
        onProgress(current, total);
        return Future.value();
      },
    );
  }

  /// Cancel ongoing scan
  void cancel() {
    if (_scanIsolate != null) {
      _scanIsolate!.kill(priority: Isolate.immediate);
      _scanIsolate = null;
    }
  }

  /// Get hostname from IP address via reverse DNS lookup
  /// Returns null if hostname cannot be resolved
  static Future<String?> getHostnameFromIp(
    String ip, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      debugPrint('🔍 Reverse lookup for $ip');

      final address = InternetAddress(ip);
      final reverseAddress = await address.reverse().timeout(timeout);

      debugPrint('✅ Hostname for $ip: ${reverseAddress.host}');

      // Return hostname only if it's different from IP (actual resolution occurred)
      if (reverseAddress.host != ip) {
        return reverseAddress.host;
      }

      return null;
    } on TimeoutException {
      debugPrint('⏱ Reverse lookup timeout for $ip');
      return null;
    } on SocketException catch (e) {
      debugPrint('❌ Socket error for $ip: $e');
      return null;
    } catch (e) {
      debugPrint('❌ Reverse lookup failed for $ip: $e');
      return null;
    }
  }

  /// Resolve hostnames for a list of devices
  /// This runs in the background and doesn't block the UI
  static Future<List<LanDevice>> resolveHostnamesForDevices(
    List<LanDevice> devices, {
    Duration timeout = const Duration(seconds: 2),
    int concurrency = 10,
    void Function(int current, int total)? onProgress,
  }) async {
    final results = <LanDevice>[];
    final completer = Completer<void>();
    var activeCount = 0;
    var queueIndex = 0;
    var completedCount = 0;
    final totalCount = devices.length;

    void startNextJob() {
      if (queueIndex >= devices.length) {
        if (activeCount == 0 && !completer.isCompleted) {
          completer.complete();
        }
        return;
      }

      final device = devices[queueIndex++];
      activeCount++;

      getHostnameFromIp(device.ip, timeout: timeout)
          .then((hostname) {
            results.add(device.copyWith(hostname: hostname));
          })
          .catchError((e) {
            // Keep device without hostname on error
            results.add(device);
          })
          .whenComplete(() {
            activeCount--;
            completedCount++;

            onProgress?.call(completedCount, totalCount);

            // Start next job
            startNextJob();

            // Complete when all done
            if (completedCount >= totalCount &&
                activeCount == 0 &&
                !completer.isCompleted) {
              completer.complete();
            }
          });
    }

    // Start initial batch
    for (var i = 0; i < concurrency && i < devices.length; i++) {
      startNextJob();
    }

    await completer.future;

    // Sort by original order (by IP)
    results.sort((a, b) => _compareIpAddresses(a.ip, b.ip));

    return results;
  }

  /// Get the device's local IP address
  Future<String?> _getLocalIp() async {
    try {
      final wifiIP = await _networkInfo.getWifiIP();
      return wifiIP;
    } catch (e) {
      throw LanScanException('Failed to retrieve local IP', e);
    }
  }

  /// Extract subnet from IP address (returns first 3 octets)
  String? _extractSubnet(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;

    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return null;
    }

    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }

  /// Scan IPs with controlled concurrency
  static Future<void> _scanWithConcurrency({
    required List<String> ips,
    required Duration timeout,
    required int concurrency,
    required bool resolveHostnames,
    required void Function(LanDevice) onResult,
    required Future<void> Function(int current, int total) onProgress,
  }) async {
    final completer = Completer<void>();
    var activeCount = 0;
    var queueIndex = 0;
    var completedCount = 0;
    final totalCount = ips.length;

    void startNextJob() {
      if (queueIndex >= ips.length) {
        if (activeCount == 0 && !completer.isCompleted) {
          completer.complete();
        }
        return;
      }

      final ip = ips[queueIndex++];
      activeCount++;

      _pingHost(ip, timeout)
          .then((device) async {
            // If device is reachable and hostname resolution is enabled
            if (device.reachable && resolveHostnames) {
              final hostname = await getHostnameFromIp(
                ip,
                timeout: const Duration(seconds: 2),
              );
              onResult(device.copyWith(hostname: hostname));
            } else {
              onResult(device);
            }
          })
          .catchError((e) {
            onResult(LanDevice(ip: ip, latencyMs: 0.0, reachable: false));
          })
          .whenComplete(() {
            activeCount--;
            completedCount++;

            // Report progress
            onProgress(completedCount, totalCount).then((_) {
              // Start next job after progress callback
              startNextJob();

              // Complete when all done
              if (completedCount >= totalCount &&
                  activeCount == 0 &&
                  !completer.isCompleted) {
                completer.complete();
              }
            });
          });
    }

    // Start initial batch
    for (var i = 0; i < concurrency && i < ips.length; i++) {
      startNextJob();
    }

    return completer.future;
  }

  /// Ping a single host
  static Future<LanDevice> _pingHost(String ip, Duration timeout) async {
    try {
      final ping = Ping(
        ip,
        count: 1,
        timeout: timeout.inSeconds > 0 ? timeout.inSeconds : 1,
        interval: 1,
      );

      final completer = Completer<LanDevice>();
      StreamSubscription? subscription;
      bool hasResponse = false;

      final timeoutTimer = Timer(
        timeout + const Duration(milliseconds: 200),
        () {
          if (!completer.isCompleted) {
            subscription?.cancel();
            completer.complete(
              LanDevice(ip: ip, latencyMs: 0.0, reachable: false),
            );
          }
        },
      );

      subscription = ping.stream.listen(
        (event) {
          if (event.response != null && event.response!.time != null) {
            final latency = event.response!.time!.inMicroseconds;

            if (latency > 0 && latency < timeout.inMicroseconds) {
              hasResponse = true;
              if (!completer.isCompleted) {
                timeoutTimer.cancel();
                subscription?.cancel();
                completer.complete(
                  LanDevice(
                    ip: ip,
                    latencyMs: latency / 1000.0,
                    reachable: true,
                  ),
                );
              }
            }
          } else if (event.error != null) {
            if (!completer.isCompleted && !hasResponse) {
              timeoutTimer.cancel();
              subscription?.cancel();
              completer.complete(
                LanDevice(ip: ip, latencyMs: 0.0, reachable: false),
              );
            }
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            timeoutTimer.cancel();
            subscription?.cancel();
            completer.complete(
              LanDevice(ip: ip, latencyMs: 0.0, reachable: false),
            );
          }
        },
        onError: (e) {
          if (!completer.isCompleted) {
            timeoutTimer.cancel();
            subscription?.cancel();
            completer.complete(
              LanDevice(ip: ip, latencyMs: 0.0, reachable: false),
            );
          }
        },
        cancelOnError: true,
      );

      return await completer.future;
    } catch (e) {
      return LanDevice(ip: ip, latencyMs: 0.0, reachable: false);
    }
  }

  /// Compare IP addresses numerically
  static int _compareIpAddresses(String a, String b) {
    final aParts = a.split('.').map(int.parse).toList();
    final bParts = b.split('.').map(int.parse).toList();

    for (int i = 0; i < 4; i++) {
      if (aParts[i] != bParts[i]) {
        return aParts[i].compareTo(bParts[i]);
      }
    }
    return 0;
  }

  /// Cleanup resources
  void dispose() {
    cancel();
  }
}

// Message types for isolate communication
abstract class _IsolateMessage {}

class _ScanRequest extends _IsolateMessage {
  final List<String> ips;
  final int timeoutMs;
  final int concurrency;
  final bool resolveHostnames;

  _ScanRequest({
    required this.ips,
    required this.timeoutMs,
    required this.concurrency,
    required this.resolveHostnames,
  });
}

class _ScanProgress extends _IsolateMessage {
  final int current;
  final int total;

  _ScanProgress({required this.current, required this.total});
}

class _ScanResult extends _IsolateMessage {
  final LanDevice device;

  _ScanResult({required this.device});
}

class _ScanComplete extends _IsolateMessage {}

class _ScanError extends _IsolateMessage {
  final String error;

  _ScanError({required this.error});
}
