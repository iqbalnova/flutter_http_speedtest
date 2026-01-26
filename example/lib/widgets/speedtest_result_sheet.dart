import 'package:flutter/material.dart';
import 'package:flutter_http_speedtest/flutter_http_speedtest.dart';

class SpeedTestResultSheet extends StatelessWidget {
  final SpeedTestResult result;
  final ScrollController scrollController;
  final DateTime completedAt;

  const SpeedTestResultSheet({
    super.key,
    required this.result,
    required this.scrollController,
    required this.completedAt,
  });

  String _formatTimeAgo(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    // Seconds
    if (diff.inSeconds < 10) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds} seconds ago';

    // Minutes
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';

    // Hours
    if (diff.inHours < 24) return '${diff.inHours} hours ago';

    // Yesterday
    if (diff.inDays == 1) return 'Yesterday';

    // Days (2–6 days)
    if (diff.inDays < 7) return '${diff.inDays} days ago';

    // Weeks
    final weeks = (diff.inDays / 7).floor();
    if (weeks < 4) return '$weeks weeks ago';

    // Months
    final months = (diff.inDays / 30).floor();
    if (months == 1) return 'Last month';
    if (months < 12) return '$months months ago';

    // Years
    final years = (diff.inDays / 365).floor();
    if (years == 1) return 'Last year';
    return '$years years ago';
  }

  @override
  Widget build(BuildContext context) {
    final metadata = result.metadata;
    final quality = result.quality;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          /// Handle
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
                  /// Title
                  const Text(
                    'Test Result',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),

                  const SizedBox(height: 16),

                  /// Network header
                  _buildHeader(metadata),

                  const SizedBox(height: 20),

                  /// Speed summary
                  _buildSpeedSummary(),

                  const SizedBox(height: 16),

                  /// Latency row
                  _buildLatencyRow(),

                  const SizedBox(height: 20),

                  /// Network Quality
                  _buildQualitySection(quality),

                  const SizedBox(height: 20),

                  /// Server Location / Metadata
                  _buildMetadataSection(metadata),

                  const SizedBox(height: 28),

                  /// Buttons
                  _buildButtons(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(NetworkMetadata? metadata) {
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
                'Internet → ${'Device'}',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        Text(
          _formatTimeAgo(completedAt),
          style: const TextStyle(color: Colors.grey),
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
              title: 'Download',
              color: const Color(0xFF7B1B7E),
              value: result.downloadMbps,
              icon: Icons.arrow_downward,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _speedBox(
              title: 'Upload',
              color: const Color(0xFFF4B400),
              value: result.uploadMbps,
              icon: Icons.arrow_upward,
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
        _metric('Latency', result.latencyMs, 'ms'),
        _metric('Jitter', result.jitterMs, 'ms'),
        _metric('Loss', result.packetLossPercent, '%'),
      ],
    );
  }

  Widget _buildQualitySection(NetworkQuality quality) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// Header
          Row(
            children: [
              const Text(
                'Network Quality',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
            ],
          ),

          const SizedBox(height: 16),

          /// 3 Columns Row
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

  Widget _buildMetadataSection(NetworkMetadata? metadata) {
    if (metadata == null) return const SizedBox();

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
          _row('Connected Via', metadata.connectedVia),
          _row('Server Location', metadata.serverLocation),
          _row('Your Network', metadata.networkName),
          _rowLink('IP Address', metadata.ipAddress),
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
              child: const Text(
                'Selesai',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF7B1B7E)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text(
                'Bagikan Hasil',
                style: TextStyle(color: Color(0xFF7B1B7E)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _speedBox({
    required String title,
    required Color color,
    required double? value,
    required IconData icon,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title),
            const SizedBox(width: 6),
            const Icon(Icons.info_outline, size: 16),
          ],
        ),
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

  Widget _qualityColumn(ScenarioQuality quality) {
    final color = _getGradeColor(quality.grade);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Text(
            quality.scenario,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        const SizedBox(height: 8),

        /// Grade
        Text(
          _getGradeText(quality.grade),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String? value) {
    if (value == null) return const SizedBox();
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

  Widget _rowLink(String label, String? value) {
    if (value == null) return const SizedBox();
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

  String _getGradeText(NetworkQualityGrade grade) {
    switch (grade) {
      case NetworkQualityGrade.great:
        return 'Great';
      case NetworkQualityGrade.good:
        return 'Good';
      case NetworkQualityGrade.average:
        return 'Average';
      case NetworkQualityGrade.poor:
        return 'Poor';
      case NetworkQualityGrade.bad:
        return 'Bad';
    }
  }
}
