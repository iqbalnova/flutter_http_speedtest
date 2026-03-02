// lib/pages/speed_test_history_page.dart

import 'package:flutter/material.dart';
import '../models/speed_test_history.dart';
import '../services/speed_test_history_service.dart';

class SpeedTestHistoryPage extends StatefulWidget {
  const SpeedTestHistoryPage({super.key});

  @override
  State<SpeedTestHistoryPage> createState() => _SpeedTestHistoryPageState();
}

class _SpeedTestHistoryPageState extends State<SpeedTestHistoryPage> {
  final _historyService = SpeedTestHistoryService();
  List<SpeedTestHistory> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      await _historyService.init();
      setState(() {
        _history = _historyService.getAll();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading history: $e')));
      }
    }
  }

  Future<void> _deleteItem(SpeedTestHistory item) async {
    try {
      await _historyService.delete(item);
      setState(() {
        _history = _historyService.getAll();
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('History item deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting: $e')));
      }
    }
  }

  Future<void> _deleteAll() async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All History'),
        content: const Text(
          'Are you sure you want to delete all speed test history? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _historyService.deleteAll();
        setState(() {
          _history = [];
        });

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('All history deleted')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error deleting all: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Speed Test History'),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteAll,
              tooltip: 'Delete All',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
          ? _buildEmptyState()
          : _buildHistoryList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No history yet',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Your speed test results will appear here',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    final grouped = _historyService.getGroupedByDate();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final dateKey = grouped.keys.elementAt(index);
        final items = grouped[dateKey]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                dateKey,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
            ),
            ...items.map((item) => _buildHistoryItem(item)),
          ],
        );
      },
    );
  }

  Widget _buildHistoryItem(SpeedTestHistory item) {
    return Dismissible(
      key: ValueKey(item.key),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete History'),
            content: const Text('Are you sure you want to delete this item?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) => _deleteItem(item),
      child: InkWell(
        onTap: () => _showHistoryDetail(item),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.wifi, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.metadata?.networkName ?? 'Unknown Network',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    item.timeAgo,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _speedIndicator(
                      'Download',
                      item.downloadMbps,
                      const Color(0xFF7B1B7E),
                      Icons.arrow_downward,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _speedIndicator(
                      'Upload',
                      item.uploadMbps,
                      const Color(0xFFF4B400),
                      Icons.arrow_upward,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _miniMetric('Latency', item.latencyMs, 'ms'),
                  _miniMetric('Jitter', item.jitterMs, 'ms'),
                  _miniMetric('Loss', item.packetLossPercent, '%'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _speedIndicator(
    String label,
    double? value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Text(
                  value != null ? '${value.toStringAsFixed(1)} Mbps' : '-',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniMetric(String label, double? value, String unit) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          value != null ? '${value.toStringAsFixed(1)} $unit' : '-',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ],
    );
  }

  void _showHistoryDetail(SpeedTestHistory item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) {
          return HistoryDetailSheet(
            history: item,
            scrollController: scrollController,
            onDelete: () {
              Navigator.pop(context);
              _deleteItem(item);
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    // Don't dispose singleton service
    // _historyService.dispose();
    super.dispose();
  }
}

class HistoryDetailSheet extends StatelessWidget {
  final SpeedTestHistory history;
  final ScrollController scrollController;
  final VoidCallback onDelete;

  const HistoryDetailSheet({
    super.key,
    required this.history,
    required this.scrollController,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final metadata = history.metadata;
    final quality = history.quality;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 5,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                children: [
                  const Text(
                    'Test Result',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  _buildHeader(metadata),
                  const SizedBox(height: 20),
                  _buildSpeedSummary(),
                  const SizedBox(height: 16),
                  _buildLatencyRow(),
                  const SizedBox(height: 20),
                  _buildQualitySection(quality),
                  if (metadata != null) ...[
                    const SizedBox(height: 20),
                    _buildMetadataSection(metadata),
                  ],
                  const SizedBox(height: 28),
                  _buildButtons(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(NetworkMetadataData? metadata) {
    return Row(
      children: [
        const Icon(Icons.wifi, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metadata?.networkName ?? 'Unknown Network',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                history.formattedDate,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedSummary() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _speedBox(
              'Download',
              const Color(0xFF7B1B7E),
              history.downloadMbps,
              Icons.arrow_downward,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _speedBox(
              'Upload',
              const Color(0xFFF4B400),
              history.uploadMbps,
              Icons.arrow_upward,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatencyRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _metric('Latency', history.latencyMs, 'ms'),
        _metric('Jitter', history.jitterMs, 'ms'),
        _metric('Loss', history.packetLossPercent, '%'),
      ],
    );
  }

  Widget _buildQualitySection(NetworkQualityData quality) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Network Quality',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _qualityColumn(quality.streaming)),
              Expanded(child: _qualityColumn(quality.gaming)),
              Expanded(child: _qualityColumn(quality.rtc)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataSection(NetworkMetadataData metadata) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Server Location',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (metadata.connectedVia != null)
            _row('Connected Via', metadata.connectedVia!),
          if (metadata.serverLocation != null)
            _row('Server Location', metadata.serverLocation!),
          if (metadata.networkName != null)
            _row('Your Network', metadata.networkName!),
          if (metadata.ipAddress != null)
            _rowLink('IP Address', metadata.ipAddress!),
        ],
      ),
    );
  }

  Widget _buildButtons(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B1B7E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text('Close', style: TextStyle(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: onDelete,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _speedBox(String title, Color color, double? value, IconData icon) {
    return Column(
      children: [
        Text(title),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: color,
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
            Text(
              value != null ? value.toStringAsFixed(1) : '-',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            const Text('Mbps'),
          ],
        ),
      ],
    );
  }

  Widget _metric(String label, double? value, String unit) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value != null ? '${value.toStringAsFixed(2)} $unit' : '-',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _qualityColumn(ScenarioQualityData quality) {
    final color = _getGradeColor(quality.grade);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          quality.scenario,
          style: const TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Text(
          quality.gradeText,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _rowLink(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF7B1B7E),
            ),
          ),
        ],
      ),
    );
  }

  Color _getGradeColor(NetworkQualityGrade grade) {
    switch (grade) {
      case NetworkQualityGrade.great:
        return Colors.green;
      case NetworkQualityGrade.good:
        return Colors.lightGreen;
      case NetworkQualityGrade.average:
        return Colors.orange;
      case NetworkQualityGrade.poor:
        return Colors.deepOrange;
      case NetworkQualityGrade.bad:
        return Colors.red;
    }
  }
}
