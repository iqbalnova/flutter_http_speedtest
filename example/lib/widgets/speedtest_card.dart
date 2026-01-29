import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_http_speedtest/flutter_http_speedtest.dart';

class SpeedTestCard extends StatelessWidget {
  final ValueNotifier<TestPhase?> phaseNotifier;
  final ValueNotifier<bool> isRunningNotifier;
  final ValueNotifier<SpeedTestResult?> resultNotifier;
  final ValueNotifier<List<SpeedSample>> downloadSamplesNotifier;
  final ValueNotifier<List<SpeedSample>> uploadSamplesNotifier;
  final ValueNotifier<List<LatencySample>> latencySamplesNotifier;

  final VoidCallback onStart;
  final VoidCallback onCancel;
  final VoidCallback onTapResult;

  const SpeedTestCard({
    super.key,
    required this.phaseNotifier,
    required this.isRunningNotifier,
    required this.resultNotifier,
    required this.downloadSamplesNotifier,
    required this.uploadSamplesNotifier,
    required this.latencySamplesNotifier,
    required this.onStart,
    required this.onCancel,
    required this.onTapResult,
  });

  String _getPhaseText(TestPhase? phase) {
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

  Color _getPhaseColor(TestPhase? phase) {
    switch (phase) {
      case TestPhase.upload:
        return const Color(0xFFF4B400);
      case TestPhase.download:
        return const Color(0xFF7B1B7E);
      default:
        return Colors.grey;
    }
  }

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
              ValueListenableBuilder<SpeedTestResult?>(
                valueListenable: resultNotifier,
                builder: (context, result, _) {
                  if (result == null) return const SizedBox.shrink();

                  return TextButton(
                    onPressed: onTapResult,
                    child: const Text(
                      'Lihat hasil',
                      style: TextStyle(color: Color(0xFF7B1B7E)),
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 4),

          /// Phase label
          ValueListenableBuilder<TestPhase?>(
            valueListenable: phaseNotifier,
            builder: (context, phase, _) {
              return Text(
                _getPhaseText(phase),
                style: TextStyle(color: _getPhaseColor(phase), fontSize: 14),
              );
            },
          ),

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
                    icon: Icons.arrow_downward,
                    resultNotifier: resultNotifier,
                    samplesNotifier: downloadSamplesNotifier,
                    isDownload: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SpeedValueBox(
                    title: 'Upload',
                    color: const Color(0xFFF4B400),
                    icon: Icons.arrow_upward,
                    resultNotifier: resultNotifier,
                    samplesNotifier: uploadSamplesNotifier,
                    isDownload: false,
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
              _Metric(
                label: 'Latency',
                resultNotifier: resultNotifier,
                latencySamplesNotifier: latencySamplesNotifier,
                unit: 'ms',
                type: _MetricType.latency,
              ),
              _Metric(
                label: 'Jitter',
                resultNotifier: resultNotifier,
                latencySamplesNotifier: latencySamplesNotifier,
                unit: 'ms',
                type: _MetricType.jitter,
              ),
              _Metric(
                label: 'Loss',
                resultNotifier: resultNotifier,
                latencySamplesNotifier: latencySamplesNotifier,
                unit: '%',
                type: _MetricType.loss,
              ),
            ],
          ),

          const SizedBox(height: 16),

          /// Chart
          ValueListenableBuilder<TestPhase?>(
            valueListenable: phaseNotifier,
            builder: (context, phase, _) {
              final samplesNotifier = phase == TestPhase.download
                  ? downloadSamplesNotifier
                  : uploadSamplesNotifier;

              return ValueListenableBuilder<List<SpeedSample>>(
                valueListenable: samplesNotifier,
                builder: (context, samples, _) {
                  if (samples.isEmpty) return const SizedBox.shrink();

                  return SizedBox(
                    height: 120,
                    child: _SpeedChart(
                      samples: samples,
                      lineColor: _getPhaseColor(phase),
                    ),
                  );
                },
              );
            },
          ),

          const SizedBox(height: 24),

          /// Button Section
          ValueListenableBuilder<bool>(
            valueListenable: isRunningNotifier,
            builder: (context, isRunning, _) {
              return Row(
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
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Testing...',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
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

                  /// CANCEL BUTTON
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
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SpeedValueBox extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final ValueNotifier<SpeedTestResult?> resultNotifier;
  final ValueNotifier<List<SpeedSample>> samplesNotifier;
  final bool isDownload;

  const _SpeedValueBox({
    required this.title,
    required this.color,
    required this.icon,
    required this.resultNotifier,
    required this.samplesNotifier,
    required this.isDownload,
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
        ValueListenableBuilder<SpeedTestResult?>(
          valueListenable: resultNotifier,
          builder: (context, result, _) {
            return ValueListenableBuilder<List<SpeedSample>>(
              valueListenable: samplesNotifier,
              builder: (context, samples, _) {
                final value = isDownload
                    ? (result?.downloadMbps ?? samples.lastOrNull?.mbps)
                    : (result?.uploadMbps ?? samples.lastOrNull?.mbps);

                return Row(
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
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('Mbps'),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

enum _MetricType { latency, jitter, loss }

class _Metric extends StatelessWidget {
  final String label;
  final ValueNotifier<SpeedTestResult?> resultNotifier;
  final ValueNotifier<List<LatencySample>> latencySamplesNotifier;
  final String unit;
  final _MetricType type;

  const _Metric({
    required this.label,
    required this.resultNotifier,
    required this.latencySamplesNotifier,
    required this.unit,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 4),
        ValueListenableBuilder<SpeedTestResult?>(
          valueListenable: resultNotifier,
          builder: (context, result, _) {
            return ValueListenableBuilder<List<LatencySample>>(
              valueListenable: latencySamplesNotifier,
              builder: (context, samples, _) {
                final double? value;
                switch (type) {
                  case _MetricType.latency:
                    value = result?.latencyMs ?? samples.lastOrNull?.rttMs;
                    break;
                  case _MetricType.jitter:
                    value = result?.jitterMs;
                    break;
                  case _MetricType.loss:
                    value = result?.packetLossPercent;
                    break;
                }

                return Text(
                  value != null ? '${value.toStringAsFixed(2)} $unit' : '-',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                );
              },
            );
          },
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
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: lineColor,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
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
