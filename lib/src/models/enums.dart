// lib/src/models/enums.dart

/// Phases of a speed test run, in execution order.
enum TestPhase { metadata, ping, download, upload }

/// Lifecycle state of a single phase.
enum PhaseState {
  pending,
  running,
  success,
  failed,
  timeout,
  canceled,
  skipped,
}

/// Overall network quality grade (WiFiMan / Ookla style).
enum NetworkQualityGrade { bad, poor, average, good, great }
