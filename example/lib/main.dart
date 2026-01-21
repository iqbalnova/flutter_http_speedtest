// example/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_http_speedtest/flutter_http_speedtest.dart';
import 'dart:math' as math;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speed Test',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const SpeedTestScreen(),
    );
  }
}

class SpeedTestScreen extends StatefulWidget {
  const SpeedTestScreen({super.key});

  @override
  State<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends State<SpeedTestScreen> {
  SpeedTestEngine? _engine;
  SpeedTestResult? _result;
  TestPhase? _currentPhase;
  bool _isRunning = false;

  final List<SpeedSample> _downloadSamples = [];
  final List<SpeedSample> _uploadSamples = [];
  final List<LatencySample> _latencySamples = [];

  void _startTest() {
    setState(() {
      _isRunning = true;
      _result = null;
      _currentPhase = null;
      _downloadSamples.clear();
      _uploadSamples.clear();
      _latencySamples.clear();
    });

    _engine = SpeedTestEngine(
      downloadBytes: 5 * 1024 * 1024, // 5MB
      uploadBytes: 3 * 1024 * 1024, // 3MB
      options: const SpeedTestOptions(
        pingSamples: 15,
        sampleInterval: Duration(milliseconds: 250),
        pingTimeout: Duration(seconds: 4),
        downloadTimeout: Duration(seconds: 10),
        uploadTimeout: Duration(seconds: 10),
        maxTotalDuration: Duration(seconds: 25),
        retries: 1,
      ),
      onPhaseChanged: (TestPhase phase) {
        setState(() {
          _currentPhase = phase;
        });
      },
      onSample: (Sample sample) {
        setState(() {
          if (sample is SpeedSample) {
            if (_currentPhase == TestPhase.download) {
              _downloadSamples.add(sample);
            } else if (_currentPhase == TestPhase.upload) {
              _uploadSamples.add(sample);
            }
          } else if (sample is LatencySample) {
            _latencySamples.add(sample);
          }
        });
      },
      onCompleted: (result) {
        setState(() {
          _result = result;
          _isRunning = false;
          _currentPhase = null;
        });
      },
      onError: (error, stack) {
        setState(() {
          _isRunning = false;
          _currentPhase = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $error')));
      },
    );

    _engine!.run();
  }

  void _cancelTest() {
    _engine?.cancel();
    setState(() {
      _isRunning = false;
      _currentPhase = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Internet Speed Test'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildActionButton(),
              const SizedBox(height: 24),
              if (_isRunning) _buildProgressSection(),
              if (_result != null) _buildResultsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    return ElevatedButton(
      onPressed: _isRunning ? _cancelTest : _startTest,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: _isRunning ? Colors.red : Colors.blue,
      ),
      child: Text(
        _isRunning ? 'Cancel Test' : 'Start Speed Test',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildProgressSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              _getPhaseText(_currentPhase),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            if (_currentPhase == TestPhase.download &&
                _downloadSamples.isNotEmpty)
              _buildLiveChart('Download', _downloadSamples, Colors.blue),
            if (_currentPhase == TestPhase.upload && _uploadSamples.isNotEmpty)
              _buildLiveChart('Upload', _uploadSamples, Colors.green),
            if (_currentPhase == TestPhase.ping && _latencySamples.isNotEmpty)
              _buildLatencyChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveChart(String title, List<SpeedSample> samples, Color color) {
    if (samples.isEmpty) return const SizedBox.shrink();

    final maxSpeed = samples.map((s) => s.mbps).reduce(math.max);
    final currentSpeed = samples.last.mbps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title: ${currentSpeed.toStringAsFixed(2)} Mbps',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: CustomPaint(
            painter: ChartPainter(samples, maxSpeed, color),
            child: Container(),
          ),
        ),
      ],
    );
  }

  Widget _buildLatencyChart() {
    if (_latencySamples.isEmpty) return const SizedBox.shrink();

    final maxLatency = _latencySamples.map((s) => s.rttMs).reduce(math.max);
    final currentLatency = _latencySamples.last.rttMs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Latency: ${currentLatency.toStringAsFixed(1)} ms',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: CustomPaint(
            painter: LatencyChartPainter(_latencySamples, maxLatency),
            child: Container(),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsSection() {
    final result = _result!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSpeedCard(
          'Download',
          result.downloadMbps,
          Icons.download,
          Colors.blue,
        ),
        const SizedBox(height: 12),
        _buildSpeedCard(
          'Upload',
          result.uploadMbps,
          Icons.upload,
          Colors.green,
        ),
        const SizedBox(height: 24),
        _buildLatencyCard(result),
        const SizedBox(height: 24),
        _buildQualityCards(result),
        if (result.metadata != null) ...[
          const SizedBox(height: 24),
          _buildMetadataCard(result.metadata!),
        ],
      ],
    );
  }

  Widget _buildSpeedCard(
    String label,
    double? mbps,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mbps != null ? '${mbps.toStringAsFixed(2)} Mbps' : 'N/A',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLatencyCard(SpeedTestResult result) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Network Performance',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),
            _buildMetricRow(
              'Latency',
              result.latencyMs != null
                  ? '${result.latencyMs!.toStringAsFixed(1)} ms'
                  : 'N/A',
            ),
            _buildMetricRow(
              'Jitter',
              result.jitterMs != null
                  ? '${result.jitterMs!.toStringAsFixed(1)} ms'
                  : 'N/A',
            ),
            _buildMetricRow(
              'Packet Loss',
              result.packetLossPercent != null
                  ? '${result.packetLossPercent!.toStringAsFixed(1)}%'
                  : 'N/A',
            ),
            if (result.loadedLatencyMs != null)
              _buildMetricRow(
                'Loaded Latency',
                '${result.loadedLatencyMs!.toStringAsFixed(1)} ms',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityCards(SpeedTestResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Network Quality',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildQualityItem(result.quality.streaming),
        const SizedBox(height: 8),
        _buildQualityItem(result.quality.gaming),
        const SizedBox(height: 8),
        _buildQualityItem(result.quality.rtc),
      ],
    );
  }

  Widget _buildQualityItem(ScenarioQuality quality) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                quality.scenario,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getGradeColor(quality.grade),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _getGradeText(quality.grade),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${quality.score.toStringAsFixed(0)}/100',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataCard(NetworkMetadata metadata) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Connection Info',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),
            if (metadata.ipAddress != null)
              _buildMetricRow('Your IP', metadata.ipAddress!),
            if (metadata.connectedVia != null)
              _buildMetricRow('Connected via', metadata.connectedVia!),
            if (metadata.serverLocation != null)
              _buildMetricRow('Server location', metadata.serverLocation!),
            if (metadata.country != null)
              _buildMetricRow('Country', metadata.country!),
            if (metadata.tlsVersion != null)
              _buildMetricRow('TLS', metadata.tlsVersion!),
            if (metadata.httpVersion != null)
              _buildMetricRow('HTTP', metadata.httpVersion!),
          ],
        ),
      ),
    );
  }

  String _getPhaseText(TestPhase? phase) {
    switch (phase) {
      case TestPhase.metadata:
        return 'Fetching metadata...';
      case TestPhase.ping:
        return 'Measuring latency...';
      case TestPhase.download:
        return 'Testing download speed...';
      case TestPhase.upload:
        return 'Testing upload speed...';
      default:
        return 'Initializing...';
    }
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

// Simple chart painter for speed samples
class ChartPainter extends CustomPainter {
  final List<SpeedSample> samples;
  final double maxSpeed;
  final Color color;

  ChartPainter(this.samples, this.maxSpeed, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    final maxTime = samples.last.timestampMs.toDouble();

    for (int i = 0; i < samples.length; i++) {
      final sample = samples[i];
      final x = (sample.timestampMs / maxTime) * size.width;
      final y = size.height - (sample.mbps / maxSpeed) * size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(ChartPainter oldDelegate) => true;
}

// Simple chart painter for latency samples
class LatencyChartPainter extends CustomPainter {
  final List<LatencySample> samples;
  final double maxLatency;

  LatencyChartPainter(this.samples, this.maxLatency);

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final paint = Paint()
      ..color = Colors.purple
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    final maxTime = samples.last.timestampMs.toDouble();

    for (int i = 0; i < samples.length; i++) {
      final sample = samples[i];
      final x = (sample.timestampMs / maxTime) * size.width;
      final y = size.height - (sample.rttMs / maxLatency) * size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(LatencyChartPainter oldDelegate) => true;
}
