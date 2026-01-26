import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_http_speedtest/flutter_http_speedtest.dart';

class SpeedTestCard extends StatelessWidget {
  final TestPhase? phase;
  final bool isRunning;
  final SpeedTestResult? result;

  final List<SpeedSample> downloadSamples;
  final List<SpeedSample> uploadSamples;
  final List<LatencySample> latencySamples;

  final VoidCallback onStart;
  final VoidCallback onCancel;

  const SpeedTestCard({
    super.key,
    required this.phase,
    required this.isRunning,
    required this.result,
    required this.downloadSamples,
    required this.uploadSamples,
    required this.latencySamples,
    required this.onStart,
    required this.onCancel,
  });

  String get _phaseText {
    switch (phase) {
      case TestPhase.download:
        return 'Measuring download...';
      case TestPhase.upload:
        return 'Measuring upload...';
      case TestPhase.ping:
        return 'Measuring latency...';
      default:
        return 'Speed Test';
    }
  }

  Color get _phaseColor {
    switch (phase) {
      case TestPhase.upload:
        return const Color(0xFFF4B400);
      case TestPhase.download:
        return const Color(0xFF7B1B7E);
      default:
        return Colors.grey;
    }
  }

  List<SpeedSample> get _currentSamples {
    if (phase == TestPhase.download) return downloadSamples;
    return uploadSamples;
  }

  double? get _downloadValue =>
      result?.downloadMbps ?? downloadSamples.lastOrNull?.mbps;

  double? get _uploadValue =>
      result?.uploadMbps ?? uploadSamples.lastOrNull?.mbps;

  double? get _latencyValue =>
      result?.latencyMs ?? latencySamples.lastOrNull?.rttMs;

  double? get _jitterValue => result?.jitterMs;

  double? get _lossValue => result?.packetLossPercent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// Header
          Row(
            children: [
              const Text(
                'Speed Test',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'Lihat semua hasil',
                  style: TextStyle(color: Color(0xFF7B1B7E)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          /// Phase label
          Text(_phaseText, style: TextStyle(color: _phaseColor, fontSize: 14)),

          const SizedBox(height: 20),

          /// Download & Upload Box
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _SpeedValueBox(
                    title: 'Download',
                    color: const Color(0xFF7B1B7E),
                    value: _downloadValue,
                    icon: Icons.arrow_downward,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SpeedValueBox(
                    title: 'Upload',
                    color: const Color(0xFFF4B400),
                    value: _uploadValue,
                    icon: Icons.arrow_upward,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          /// Latency / Jitter / Loss
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Metric(label: 'Latency', value: _latencyValue, unit: 'ms'),
              _Metric(label: 'Jitter', value: _jitterValue, unit: 'ms'),
              _Metric(label: 'Loss', value: _lossValue, unit: '%'),
            ],
          ),

          const SizedBox(height: 16),

          /// Chart
          SizedBox(
            height: 120,
            child: _SpeedChart(
              samples: _currentSamples,
              lineColor: _phaseColor,
            ),
          ),

          const SizedBox(height: 24),

          /// Button Section
          Row(
            children: [
              /// START / RUNNING BUTTON
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: isRunning ? null : onStart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B1B7E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: isRunning
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Testing...',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          )
                        : const Text(
                            'Start Test',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),

              /// CANCEL BUTTON (muncul hanya saat running)
              if (isRunning) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SpeedValueBox extends StatelessWidget {
  final String title;
  final Color color;
  final double? value;
  final IconData icon;

  const _SpeedValueBox({
    required this.title,
    required this.color,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
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
              value != null ? value!.toStringAsFixed(1) : '-',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            const Text('Mbps'),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final double? value;
  final String unit;

  const _Metric({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value != null ? '${value!.toStringAsFixed(2)} $unit' : '-',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _SpeedChart extends StatelessWidget {
  final List<SpeedSample> samples;
  final Color lineColor;

  const _SpeedChart({required this.samples, required this.lineColor});

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return const Center(child: Text('No data'));
    }

    final spots = samples
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.mbps))
        .toList();

    return LineChart(
      LineChartData(
        minY: 0,
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: lineColor,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [lineColor.withValues(alpha: .35), Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
