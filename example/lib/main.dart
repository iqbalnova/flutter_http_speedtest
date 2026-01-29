// example/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_http_speedtest/flutter_http_speedtest.dart';
import 'package:flutter_http_speedtest_example/widgets/feature_card.dart';
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

  // State notifiers
  final ValueNotifier<SpeedTestResult?> _resultNotifier = ValueNotifier(null);
  final ValueNotifier<TestPhase?> _currentPhaseNotifier = ValueNotifier(null);
  final ValueNotifier<bool> _isRunningNotifier = ValueNotifier(false);
  final ValueNotifier<DateTime?> _completedAtNotifier = ValueNotifier(null);
  final ValueNotifier<List<SpeedSample>> _downloadSamplesNotifier =
      ValueNotifier([]);
  final ValueNotifier<List<SpeedSample>> _uploadSamplesNotifier = ValueNotifier(
    [],
  );
  final ValueNotifier<List<LatencySample>> _latencySamplesNotifier =
      ValueNotifier([]);

  @override
  void dispose() {
    _resultNotifier.dispose();
    _currentPhaseNotifier.dispose();
    _isRunningNotifier.dispose();
    _completedAtNotifier.dispose();
    _downloadSamplesNotifier.dispose();
    _uploadSamplesNotifier.dispose();
    _latencySamplesNotifier.dispose();
    super.dispose();
  }

  void _startTest() {
    _isRunningNotifier.value = true;
    _resultNotifier.value = null;
    _currentPhaseNotifier.value = null;
    _downloadSamplesNotifier.value = [];
    _uploadSamplesNotifier.value = [];
    _latencySamplesNotifier.value = [];

    _engine = SpeedTestEngine(
      downloadBytes: 10 * 1024 * 1024, // 10MB
      uploadBytes: 3 * 1024 * 1024, // 3MB
      options: const SpeedTestOptions(
        pingSamples: 5,
        sampleInterval: Duration(milliseconds: 250),
        pingTimeout: Duration(seconds: 10),
        downloadTimeout: Duration(seconds: 10),
        uploadTimeout: Duration(seconds: 10),
        maxTotalDuration: Duration(seconds: 25),
        retries: 1,
      ),
      onPhaseChanged: (TestPhase phase) {
        print('Phase: $phase');
        _currentPhaseNotifier.value = phase;
      },
      onSample: (Sample sample) {
        print('Sample: $sample');

        if (sample is SpeedSample) {
          if (_currentPhaseNotifier.value == TestPhase.download) {
            _downloadSamplesNotifier.value = [
              ..._downloadSamplesNotifier.value,
              sample,
            ];
          } else if (_currentPhaseNotifier.value == TestPhase.upload) {
            _uploadSamplesNotifier.value = [
              ..._uploadSamplesNotifier.value,
              sample,
            ];
          }
        } else if (sample is LatencySample) {
          _latencySamplesNotifier.value = [
            ..._latencySamplesNotifier.value,
            sample,
          ];
        }
      },
      onCompleted: (result) {
        // CRITICAL: This will ONLY be called on successful completion
        print('Test completed successfully!');
        _resultNotifier.value = result;
        _completedAtNotifier.value = DateTime.now();
        _isRunningNotifier.value = false;
        _currentPhaseNotifier.value = null;
        _openResultSheet();
      },
      onError: (error, stack) {
        // CRITICAL: This will ONLY be called on actual errors
        print('Test failed with error: $error');
        _isRunningNotifier.value = false;
        _currentPhaseNotifier.value = null;

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $error')));
      },
    );

    // Run the test - returns null if canceled
    _engine!.run().then((result) {
      if (result == null) {
        // Test was canceled
        print('Test was canceled by user');
        _isRunningNotifier.value = false;
        _currentPhaseNotifier.value = null;
      }
    });
  }

  void _cancelTest() {
    print('User requested cancel');
    _engine?.cancel();

    // Immediately update UI to show cancel state
    _isRunningNotifier.value = false;
    _currentPhaseNotifier.value = null;

    // Show feedback to user
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Speed test canceled'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openResultSheet() {
    final result = _resultNotifier.value;
    final completedAt = _completedAtNotifier.value;

    if (result == null || completedAt == null) return;

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
              result: result,
              completedAt: completedAt,
              scrollController: scrollController,
            );
          },
        );
      },
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
                phaseNotifier: _currentPhaseNotifier,
                isRunningNotifier: _isRunningNotifier,
                resultNotifier: _resultNotifier,
                downloadSamplesNotifier: _downloadSamplesNotifier,
                uploadSamplesNotifier: _uploadSamplesNotifier,
                latencySamplesNotifier: _latencySamplesNotifier,
                onStart: _startTest,
                onCancel: _cancelTest,
                onTapResult: _openResultSheet,
              ),
              const SizedBox(height: 16),
              const FeatureGrid(),
            ],
          ),
        ),
      ),
    );
  }
}
