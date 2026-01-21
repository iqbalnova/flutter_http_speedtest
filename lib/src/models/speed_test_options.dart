// lib/src/models/speed_test_options.dart

class SpeedTestOptions {
  final int pingSamples;
  final Duration sampleInterval;
  final Duration pingTimeout;
  final Duration downloadTimeout;
  final Duration uploadTimeout;
  final Duration maxTotalDuration;
  final int retries;
  final int loadedLatencySamples;

  const SpeedTestOptions({
    this.pingSamples = 15,
    this.sampleInterval = const Duration(milliseconds: 250),
    this.pingTimeout = const Duration(seconds: 4),
    this.downloadTimeout = const Duration(seconds: 10),
    this.uploadTimeout = const Duration(seconds: 10),
    this.maxTotalDuration = const Duration(seconds: 25),
    this.retries = 1,
    this.loadedLatencySamples = 5,
  });
}
