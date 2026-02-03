import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_network_diagnostics/flutter_network_diagnostics.dart';
import 'package:permission_handler/permission_handler.dart';

class WifiInfoPage extends StatefulWidget {
  const WifiInfoPage({super.key});

  @override
  State<WifiInfoPage> createState() => _WifiInfoPageState();
}

class _WifiInfoPageState extends State<WifiInfoPage> {
  final _diagnostics = FlutterNetworkDiagnosticsService();

  // Reactive state management
  final _dataNotifier = ValueNotifier<NetworkDiagnosticsData?>(null);
  final _isLoadingNotifier = ValueNotifier<bool>(false);
  final _permissionStateNotifier = ValueNotifier<PermissionStatus>(
    PermissionStatus.denied,
  );

  bool _isRequestingPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndLoad();
  }

  Future<void> _checkPermissionAndLoad() async {
    if (_isRequestingPermission) return;
    _isRequestingPermission = true;

    try {
      final status = await Permission.location.status;
      _permissionStateNotifier.value = status;
      await _loadNetworkInfo();
    } finally {
      _isRequestingPermission = false;
    }
  }

  Future<void> _requestPermission() async {
    if (_isRequestingPermission) return;
    _isRequestingPermission = true;

    try {
      final status = await Permission.location.status;

      if (status.isDenied) {
        await Future.delayed(const Duration(milliseconds: 300));
        final result = await Permission.location.request();
        _permissionStateNotifier.value = result;

        if (result.isGranted) {
          await _loadNetworkInfo();
        }
      } else if (status.isPermanentlyDenied) {
        await openAppSettings();
        // Wait and recheck after returning from settings
        await Future.delayed(const Duration(milliseconds: 500));
        final newStatus = await Permission.location.status;
        _permissionStateNotifier.value = newStatus;

        if (newStatus.isGranted) {
          await _loadNetworkInfo();
        }
      }
    } catch (e) {
      debugPrint('Error requesting permission: $e');
    } finally {
      _isRequestingPermission = false;
    }
  }

  Future<void> _loadNetworkInfo() async {
    _isLoadingNotifier.value = true;

    try {
      final data = await _diagnostics.getAllNetworkInfo();
      _dataNotifier.value = data;
    } catch (e) {
      debugPrint('Error loading network info: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading network info: $e')),
        );
      }
    } finally {
      _isLoadingNotifier.value = false;
    }
  }

  @override
  void dispose() {
    _dataNotifier.dispose();
    _isLoadingNotifier.dispose();
    _permissionStateNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Diagnostics'),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _isLoadingNotifier,
            builder: (context, isLoading, _) {
              return IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: isLoading ? null : _loadNetworkInfo,
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: _isLoadingNotifier,
        builder: (context, isLoading, _) {
          if (isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return ValueListenableBuilder<NetworkDiagnosticsData?>(
            valueListenable: _dataNotifier,
            builder: (context, data, _) {
              if (data == null) {
                return const Center(child: Text('No data available'));
              }

              return ValueListenableBuilder<PermissionStatus>(
                valueListenable: _permissionStateNotifier,
                builder: (context, permissionStatus, _) {
                  return _buildContent(data, permissionStatus);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildContent(
    NetworkDiagnosticsData data,
    PermissionStatus permissionStatus,
  ) {
    final needsPermission = !permissionStatus.isGranted;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (needsPermission) _buildPermissionBanner(permissionStatus),

          _buildSection('Connection', [
            _buildInfoTile('Default Gateway IP', data.defaultGatewayIP),
            _buildInfoTile(
              'DNS Server',
              [
                data.dnsServerPrimary,
                data.dnsServerSecondary,
              ].where((e) => e != null && e.isNotEmpty).join('\n'),
            ),
            _buildInfoTile('External IP (IPv4)', data.externalIPv4),
            _buildInfoTile('Default Gateway IPv6', data.defaultGatewayIPv6),
            _buildInfoTile('DNS Server IPv6', data.dnsServerIPv6),
            _buildInfoTile('External IP (IPv6)', data.externalIPv6),
            _buildInfoTile('HTTP Proxy', data.httpProxy),
          ]),

          const SizedBox(height: 24),

          _buildSection('Wi-Fi Information', [
            _buildInfoTile(
              'Network Connected',
              data.isConnected ? 'Yes' : 'No',
            ),
            _buildInfoTile(
              'SSID',
              data.ssid,
              needsPermission: needsPermission,
              onPermissionTap: _requestPermission,
            ),
            _buildInfoTile(
              'BSSID',
              data.bssid,
              needsPermission: needsPermission,
              onPermissionTap: _requestPermission,
            ),
            _buildInfoTile('Vendor', data.vendor),
            _buildInfoTile('Security Type', data.securityType),
            _buildInfoTile('IP Address (IPv4)', data.ipAddressIPv4),
            _buildInfoTile('Subnet Mask', data.subnetMask),
            _buildInfoTile('Broadcast Address', data.broadcastAddress),
            _buildInfoTile('IPv6 Address(es)', data.ipv6Addresses?.join('\n')),
          ]),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _testIndividualMethods,
              icon: const Icon(Icons.science),
              label: const Text('Test Individual Methods'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionBanner(PermissionStatus status) {
    final isPermanentlyDenied = status.isPermanentlyDenied;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange[700], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPermanentlyDenied
                      ? 'Izin Lokasi Ditolak Permanen'
                      : 'Izin Lokasi Diperlukan',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[900],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isPermanentlyDenied
                      ? 'Beberapa informasi WiFi memerlukan izin lokasi. Aktifkan di pengaturan.'
                      : 'Beberapa informasi WiFi seperti SSID dan BSSID memerlukan izin lokasi.',
                  style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _isRequestingPermission ? null : _requestPermission,
            child: Text(
              isPermanentlyDenied ? 'Pengaturan' : 'Izinkan',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orange[900],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(
    String label,
    String? value, {
    bool needsPermission = false,
    VoidCallback? onPermissionTap,
  }) {
    final displayValue = needsPermission && (value == null || value.isEmpty)
        ? 'N/A'
        : value ?? 'N/A';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    displayValue,
                    style: TextStyle(color: value == null ? Colors.grey : null),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 3,
                  ),
                ),
                if (needsPermission && onPermissionTap != null) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onPermissionTap,
                    child: Tooltip(
                      message: 'Memerlukan izin lokasi. Tap untuk mengizinkan.',
                      child: Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Colors.orange[700],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testIndividualMethods() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Test individual methods
      final gatewayIP = await _diagnostics.getDefaultGatewayIP();
      final dnsPrimary = await _diagnostics.getDnsServerPrimary();
      final externalIPv4 = await _diagnostics.getExternalIPv4();
      final ssid = await _diagnostics.getWifiSSID();
      final bssid = await _diagnostics.getWifiBSSID();
      final ipv4 = await _diagnostics.getWifiIPv4Address();

      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Individual Method Results'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildResultRow('Gateway IP', gatewayIP),
                  _buildResultRow('DNS Primary', dnsPrimary),
                  _buildResultRow('External IPv4', externalIPv4),
                  _buildResultRow('SSID', ssid),
                  _buildResultRow('BSSID', bssid),
                  _buildResultRow('IPv4', ipv4),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Widget _buildResultRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value ?? 'N/A',
              style: TextStyle(color: value == null ? Colors.grey : null),
            ),
          ),
        ],
      ),
    );
  }
}
