// lib/screens/lan_scanner_screen.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_http_speedtest_example/screens/device_detail_page.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../services/lan_scanner.dart';
import '../models/lan_device.dart';
import 'package:permission_handler/permission_handler.dart';

class LanScannerScreen extends StatefulWidget {
  const LanScannerScreen({super.key});

  @override
  State<LanScannerScreen> createState() => _LanScannerScreenState();
}

class _LanScannerScreenState extends State<LanScannerScreen> {
  final LanScanner _scanner = LanScanner();
  final NetworkInfo _networkInfo = NetworkInfo();

  // State notifiers
  final ValueNotifier<List<LanDevice>> _devicesNotifier = ValueNotifier([]);
  final ValueNotifier<bool> _isScanningNotifier = ValueNotifier(false);
  final ValueNotifier<String?> _errorMessageNotifier = ValueNotifier(null);
  final ValueNotifier<int> _progressNotifier = ValueNotifier(0);
  final ValueNotifier<int> _totalNotifier = ValueNotifier(254);
  final ValueNotifier<String> _ssidNotifier = ValueNotifier('-');
  final ValueNotifier<String> _ipLocalNotifier = ValueNotifier('-');
  final ValueNotifier<String?> _gatewayIpNotifier = ValueNotifier(null);
  final ValueNotifier<bool> _locationPermissionGrantedNotifier = ValueNotifier(
    true,
  );

  bool _isDisposed = false;
  bool _hasScannedOnce = false;

  @override
  void initState() {
    super.initState();
    _initializeScanner();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _scanner.cancel();

    _devicesNotifier.dispose();
    _isScanningNotifier.dispose();
    _errorMessageNotifier.dispose();
    _progressNotifier.dispose();
    _totalNotifier.dispose();
    _ssidNotifier.dispose();
    _ipLocalNotifier.dispose();
    _gatewayIpNotifier.dispose();
    _locationPermissionGrantedNotifier.dispose();
    super.dispose();
  }

  Future<void> _initializeScanner() async {
    try {
      await _scanner.initialize();

      // Get network info on initialization
      await _fetchNetworkInfo();

      // Auto-start scan on first open
      if (!_hasScannedOnce) {
        _hasScannedOnce = true;
        _startScan();
      }
    } catch (e) {
      _errorMessageNotifier.value = 'Failed to initialize scanner: $e';
    }
  }

  /// Request location permission (required for Wi-Fi info on Android/iOS)
  Future<bool> _requestLocationPermission() async {
    // Web and desktop platforms don't need location permission
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return true;
    }

    final status = await Permission.locationWhenInUse.status;
    debugPrint('Location permission status: $status');

    if (status.isGranted) {
      return true;
    }

    if (status.isDenied || status.isRestricted) {
      final result = await Permission.locationWhenInUse.request();
      debugPrint('Permission request result: $result');
      return result.isGranted;
    }

    // Permanently denied - need to open settings
    if (status.isPermanentlyDenied) {
      debugPrint('Location permission permanently denied');
      return false;
    }

    return false;
  }

  /// Fetch network information (SSID and IP)
  Future<void> _fetchNetworkInfo() async {
    try {
      // Always get Wi-Fi IP (doesn't require permission)
      final wifiIP = await _networkInfo.getWifiIP();
      _ipLocalNotifier.value = wifiIP ?? 'Not connected';
      debugPrint('Wi-Fi IP: $wifiIP');

      // Always get gateway IP (doesn't require permission)
      final gatewayIP = await _networkInfo.getWifiGatewayIP();
      _gatewayIpNotifier.value = gatewayIP;
      debugPrint('Gateway IP: $gatewayIP');

      // Request permission for Wi-Fi name only
      final hasPermission = await _requestLocationPermission();

      if (!hasPermission) {
        debugPrint('Location permission not granted - cannot get Wi-Fi name');
        _locationPermissionGrantedNotifier.value = false;
        _ssidNotifier.value = '-';
        return;
      }

      _locationPermissionGrantedNotifier.value = true;

      // Get Wi-Fi name (requires location permission)
      final wifiName = await _networkInfo.getWifiName();
      print('Wifi name: $wifiName');
      _ssidNotifier.value = wifiName ?? 'Unknown Network';
      debugPrint('Wi-Fi Name: $wifiName');
    } catch (e) {
      debugPrint('Failed to get network info: $e');

      // Try to at least get IP if Wi-Fi name failed
      if (_ipLocalNotifier.value == '-') {
        try {
          final wifiIP = await _networkInfo.getWifiIP();
          _ipLocalNotifier.value = wifiIP ?? 'Not connected';
        } catch (_) {}
      }

      // Set error state for SSID if permission was granted but still failed
      if (_locationPermissionGrantedNotifier.value) {
        _ssidNotifier.value = 'Error getting SSID';
        _errorMessageNotifier.value = 'Failed to get Wi-Fi name: $e';
      }
    }
  }

  /// Show dialog to prompt user to open settings
  Future<void> _showPermissionDialog() async {
    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission Required'),
        content: const Text(
          'Location permission is required to access Wi-Fi network name (SSID). '
          'Please grant the permission in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );

    if (shouldOpenSettings == true) {
      await openAppSettings();
      // Re-check permission after returning from settings
      await _fetchNetworkInfo();
    }
  }

  Future<void> _startScan() async {
    _isScanningNotifier.value = true;
    _errorMessageNotifier.value = null;
    _devicesNotifier.value = [];
    _progressNotifier.value = 0;

    debugPrint('Starting scan...');

    try {
      final devices = await _scanner.scan(
        timeout: Duration(milliseconds: Platform.isAndroid ? 5000 : 1000),
        resolveHostnames: true,
        onProgress: (current, total) {
          debugPrint('Scan progress: $current/$total');
          if (_isDisposed) return;

          _progressNotifier.value = current;
          _totalNotifier.value = total;
        },
      );

      debugPrint(
        'Scan completed. Found ${devices.length} device${devices.length != 1 ? 's' : ''}.',
      );

      if (_isDisposed) return;

      _devicesNotifier.value = devices;
      _isScanningNotifier.value = false;
    } on LanScanException catch (e) {
      debugPrint('Scan failed: ${e.message}');
      if (_isDisposed) return;

      _errorMessageNotifier.value = e.message;
      _isScanningNotifier.value = false;
    } catch (e) {
      debugPrint('Unexpected error: $e');
      if (_isDisposed) return;

      _errorMessageNotifier.value = 'Unexpected error: $e';
      _isScanningNotifier.value = false;
    }
  }

  void _cancelScan() {
    _scanner.cancel();
    _isScanningNotifier.value = false;
  }

  /// Handle refresh button tap
  Future<void> _handleRefresh() async {
    await _fetchNetworkInfo();
    if (!_isScanningNotifier.value) {
      _startScan();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LAN Scanner'),
        elevation: 2,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _isScanningNotifier,
            builder: (context, isScanning, _) {
              if (isScanning) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _handleRefresh,
                tooltip: 'Refresh',
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Permission warning banner
          ValueListenableBuilder<bool>(
            valueListenable: _locationPermissionGrantedNotifier,
            builder: (context, isGranted, _) {
              if (!isGranted) {
                return _buildPermissionBanner();
              }
              return const SizedBox.shrink();
            },
          ),

          // Error banner
          ValueListenableBuilder<String?>(
            valueListenable: _errorMessageNotifier,
            builder: (context, errorMessage, _) {
              if (errorMessage != null) {
                return _buildErrorBanner(errorMessage);
              }
              return const SizedBox.shrink();
            },
          ),

          // Scanning banner
          ValueListenableBuilder<bool>(
            valueListenable: _isScanningNotifier,
            builder: (context, isScanning, _) {
              if (isScanning) {
                return _buildScanningBanner();
              }
              return const SizedBox.shrink();
            },
          ),

          Expanded(child: _buildDeviceList()),
        ],
      ),
    );
  }

  Widget _buildPermissionBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.orange.shade100,
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange.shade900),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Location permission required to view Wi-Fi name',
              style: TextStyle(color: Colors.orange.shade900),
            ),
          ),
          TextButton(
            onPressed: _showPermissionDialog,
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange.shade900,
            ),
            child: const Text('Grant'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String errorMessage) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.red.shade100,
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade900),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              errorMessage,
              style: TextStyle(color: Colors.red.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.blue.shade50,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.radar, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scanning jaringan...',
                  style: TextStyle(
                    color: Colors.blue.shade900,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                ValueListenableBuilder<int>(
                  valueListenable: _progressNotifier,
                  builder: (context, progress, _) {
                    return ValueListenableBuilder<int>(
                      valueListenable: _totalNotifier,
                      builder: (context, total, _) {
                        return Text(
                          '$progress / $total IP dipindai',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 12,
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<int>(
                  valueListenable: _progressNotifier,
                  builder: (context, progress, _) {
                    return ValueListenableBuilder<int>(
                      valueListenable: _totalNotifier,
                      builder: (context, total, _) {
                        return LinearProgressIndicator(
                          value: total > 0 ? progress / total : 0.0,
                          minHeight: 4,
                          backgroundColor: Colors.blue.shade100,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.blue.shade700,
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: _cancelScan,
            style: TextButton.styleFrom(
              foregroundColor: Colors.blue.shade900,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _networkInfoCard({
    required String ssid,
    required String localIp,
    required int deviceCount,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.wifi, size: 26, color: Colors.grey.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ssid,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$localIp • $deviceCount Perangkat Ditemukan',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return ValueListenableBuilder<List<LanDevice>>(
      valueListenable: _devicesNotifier,
      builder: (context, devices, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: _isScanningNotifier,
          builder: (context, isScanning, _) {
            if (devices.isEmpty && !isScanning) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.devices, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'No devices found',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap refresh icon to search for devices',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              );
            }

            if (devices.isEmpty && isScanning) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Scanning for devices...',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Network info card with reactive values
                ValueListenableBuilder<String>(
                  valueListenable: _ssidNotifier,
                  builder: (context, ssid, _) {
                    return ValueListenableBuilder<String>(
                      valueListenable: _ipLocalNotifier,
                      builder: (context, ip, _) {
                        return _networkInfoCard(
                          ssid: ssid,
                          localIp: ip,
                          deviceCount: devices.length,
                        );
                      },
                    );
                  },
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '${devices.length} Perangkat Ditemukan',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DeviceDetailPage(
                              ipAddress: device.ip,
                              hostname: device.hostname ?? 'Generic',
                            ),
                          ),
                        ),
                        child: Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: InkWell(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DeviceDetailPage(
                                  ipAddress: device.ip,
                                  hostname: device.hostname ?? 'Generic',
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  /// LEADING ICON
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.purple.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.devices,
                                      color: Colors.purple.shade400,
                                      size: 24,
                                    ),
                                  ),

                                  const SizedBox(width: 12),

                                  /// HOSTNAME + BADGES
                                  Expanded(
                                    child: ValueListenableBuilder<String?>(
                                      valueListenable: _ipLocalNotifier,
                                      builder: (context, localIp, _) {
                                        return ValueListenableBuilder<String?>(
                                          valueListenable: _gatewayIpNotifier,
                                          builder: (context, gatewayIp, _) {
                                            final isMe = device.ip == localIp;
                                            final isGateway =
                                                device.ip == gatewayIp;

                                            return Row(
                                              children: [
                                                /// HOSTNAME
                                                Flexible(
                                                  child: Text(
                                                    device.hostname ??
                                                        'Generic',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                ),

                                                if (isMe)
                                                  const SizedBox(width: 6),
                                                if (isMe)
                                                  const _DeviceBadge(
                                                    label: 'Me',
                                                    backgroundColor: Color(
                                                      0xFFF3E8FF,
                                                    ),
                                                    textColor: Color(
                                                      0xFF7C3AED,
                                                    ),
                                                  ),

                                                if (isGateway)
                                                  const SizedBox(width: 6),
                                                if (isGateway)
                                                  const _DeviceBadge(
                                                    label: 'Gateway',
                                                    backgroundColor: Color(
                                                      0xFFE0F2FE,
                                                    ),
                                                    textColor: Color(
                                                      0xFF0284C7,
                                                    ),
                                                  ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),

                                  const SizedBox(width: 12),

                                  /// IP ADDRESS (RIGHT SIDE)
                                  Text(
                                    device.ip,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),

                                  const SizedBox(width: 8),

                                  /// CHEVRON
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _DeviceBadge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;

  const _DeviceBadge({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
