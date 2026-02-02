import 'package:flutter/material.dart';
import 'package:flutter_network_diagnostics/flutter_network_diagnostics.dart';

class WifiInfoPage extends StatefulWidget {
  const WifiInfoPage({super.key});

  @override
  State<WifiInfoPage> createState() => _WifiInfoPageState();
}

class _WifiInfoPageState extends State<WifiInfoPage> {
  final _diagnostics = FlutterNetworkDiagnosticsService();
  NetworkDiagnosticsData? _data;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadNetworkInfo();
  }

  Future<void> _loadNetworkInfo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await _diagnostics.getAllNetworkInfo();
      setState(() {
        _data = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading network info: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadNetworkInfo,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
          ? const Center(child: Text('No data available'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection('Connection', [
                    _buildInfoTile(
                      'Default Gateway IP',
                      _data!.defaultGatewayIP,
                    ),
                    _buildInfoTile(
                      'DNS Server',
                      [
                        _data!.dnsServerPrimary,
                        _data!.dnsServerSecondary,
                      ].where((e) => e != null && e.isNotEmpty).join('\n'),
                    ),

                    _buildInfoTile('External IP (IPv4)', _data!.externalIPv4),
                    _buildInfoTile(
                      'Default Gateway IPv6',
                      _data!.defaultGatewayIPv6,
                    ),
                    _buildInfoTile('DNS Server IPv6', _data!.dnsServerIPv6),
                    _buildInfoTile('External IP (IPv6)', _data!.externalIPv6),
                    _buildInfoTile('HTTP Proxy', _data!.httpProxy),
                  ]),
                  const SizedBox(height: 24),
                  _buildSection('Wi-Fi Information', [
                    _buildInfoTile(
                      'Network Connected',
                      _data!.isConnected ? 'Yes' : 'No',
                    ),
                    _buildInfoTile('SSID', _data!.ssid),
                    _buildInfoTile('BSSID', _data!.bssid),
                    _buildInfoTile('Vendor', _data!.vendor),
                    _buildInfoTile('Security Type', _data!.securityType),
                    _buildInfoTile('IP Address (IPv4)', _data!.ipAddressIPv4),
                    _buildInfoTile('Subnet Mask', _data!.subnetMask),
                    _buildInfoTile(
                      'Broadcast Address',
                      _data!.broadcastAddress,
                    ),
                    _buildInfoTile(
                      'IPv6 Address(es)',
                      _data!.ipv6Addresses?.join('\n'),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _testIndividualMethods,
                    icon: const Icon(Icons.science),
                    label: const Text('Test Individual Methods'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
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
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(String label, String? value) {
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
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value ?? 'N/A',
              style: TextStyle(color: value == null ? Colors.grey : null),
              textAlign: TextAlign.end,
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
                  Text('Gateway IP: ${gatewayIP ?? "N/A"}'),
                  Text('DNS Primary: ${dnsPrimary ?? "N/A"}'),
                  Text('External IPv4: ${externalIPv4 ?? "N/A"}'),
                  Text('SSID: ${ssid ?? "N/A"}'),
                  Text('BSSID: ${bssid ?? "N/A"}'),
                  Text('IPv4: ${ipv4 ?? "N/A"}'),
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
}
