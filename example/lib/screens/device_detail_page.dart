// lib/screens/device_detail_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_http_speedtest_example/services/realtime_ping_monitor_service.dart';

class DeviceDetailPage extends StatefulWidget {
  final String ipAddress;
  final String hostname;

  const DeviceDetailPage({
    super.key,
    required this.ipAddress,
    required this.hostname,
  });

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  late RealtimePingMonitor _pingMonitor;
  final ValueNotifier<RealtimePingStats> _statsNotifier = ValueNotifier(
    RealtimePingStats.initial(),
  );

  @override
  void initState() {
    super.initState();
    _pingMonitor = RealtimePingMonitor(
      ipAddress: widget.ipAddress,
      pingInterval: const Duration(seconds: 1),
      timeout: const Duration(seconds: 2),
    );

    _pingMonitor.statsStream.listen((stats) {
      _statsNotifier.value = stats;
    });

    _pingMonitor.start();
  }

  @override
  void dispose() {
    _pingMonitor.dispose();
    _statsNotifier.dispose();
    super.dispose();
  }

  Color _getPingColor(double? ping) {
    if (ping == null) return Colors.grey;
    if (ping < 50) return Colors.green;
    if (ping < 100) return Colors.orange;
    return Colors.red;
  }

  Color _getPacketLossColor(double lossPercent) {
    if (lossPercent == 0) return Colors.green;
    if (lossPercent < 10) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    Widget buildDeviceHeader(String name) {
      return Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFFB16CEA), Color(0xFF5F9CFF)],
              ),
            ),
            child: const Icon(Icons.devices, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      );
    }

    Widget buildSectionTitle(String text) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      );
    }

    Widget buildInfoCard({required List<Widget> children}) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: children),
      );
    }

    Widget buildInfoRow({
      required String label,
      required String value,
      Color? valueColor,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
              ),
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor ?? Colors.black87,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Detail'),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          children: [
            buildDeviceHeader(widget.hostname),
            const SizedBox(height: 24),
            buildSectionTitle('Network'),
            const SizedBox(height: 8),
            ValueListenableBuilder<RealtimePingStats>(
              valueListenable: _statsNotifier,
              builder: (context, stats, _) {
                return buildInfoCard(
                  children: [
                    buildInfoRow(label: 'IP Address', value: widget.ipAddress),
                    buildInfoRow(
                      label: 'Ping',
                      value: stats.pingText,
                      valueColor: _getPingColor(stats.currentPing),
                    ),
                    buildInfoRow(
                      label: 'Packet Loss',
                      value: stats.packetLossText,
                      valueColor: _getPacketLossColor(stats.packetLossPercent),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
