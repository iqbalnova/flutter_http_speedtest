// example/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_http_speedtest/flutter_http_speedtest.dart';
import 'package:flutter_http_speedtest_example/widgets/speedtest_card.dart';
import 'package:flutter_http_speedtest_example/widgets/speedtest_result_sheet.dart';

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
  DateTime? _completedAt;

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
      downloadBytes: 10 * 1024 * 1024, // 10MB
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
        print('Phase: $phase');
        setState(() {
          _currentPhase = phase;
        });
      },
      onSample: (Sample sample) {
        print('Sample: $sample');

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
        // CRITICAL: This will ONLY be called on successful completion
        // Never called after cancel
        print('Test completed successfully!');
        setState(() {
          _result = result;
          _completedAt = DateTime.now();
          _isRunning = false;
          _currentPhase = null;
        });
      },
      onError: (error, stack) {
        // CRITICAL: This will ONLY be called on actual errors
        // Never called after cancel
        print('Test failed with error: $error');
        setState(() {
          _isRunning = false;
          _currentPhase = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $error')));
      },
    );

    // Run the test - returns null if canceled
    _engine!.run().then((result) {
      if (result == null) {
        // Test was canceled - this is the only callback you'll get
        print('Test was canceled by user');
        setState(() {
          _isRunning = false;
          _currentPhase = null;
        });
      }
    });
  }

  void _cancelTest() {
    print('User requested cancel');
    _engine?.cancel();

    // Immediately update UI to show cancel state
    setState(() {
      _isRunning = false;
      _currentPhase = null;
    });

    // Show feedback to user
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Speed test canceled'),
        duration: Duration(seconds: 2),
      ),
    );
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
              SpeedTestCard(
                phase: _currentPhase,
                isRunning: _isRunning,
                result: _result,
                downloadSamples: _downloadSamples,
                uploadSamples: _uploadSamples,
                latencySamples: _latencySamples,
                onStart: _startTest,
                onCancel: _cancelTest,
              ),
              if (_result != null)
                TextButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      enableDrag: true,
                      builder: (_) {
                        return DraggableScrollableSheet(
                          initialChildSize: 0.85,
                          minChildSize: 0.5,
                          maxChildSize: 0.95,
                          builder: (context, scrollController) {
                            return SpeedTestResultSheet(
                              result: _result!,
                              completedAt: _completedAt!,
                              scrollController: scrollController,
                            );
                          },
                        );
                      },
                    );
                  },
                  child: const Text('Speedtest Detail'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
