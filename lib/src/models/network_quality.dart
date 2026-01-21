// lib/src/models/network_quality.dart

import 'enums.dart';

class ScenarioQuality {
  final double score; // 0-100
  final NetworkQualityGrade grade;
  final String scenario;

  ScenarioQuality({
    required this.score,
    required this.grade,
    required this.scenario,
  });

  @override
  String toString() => '$scenario: $grade (${score.toStringAsFixed(1)}/100)';
}

class NetworkQuality {
  final ScenarioQuality streaming;
  final ScenarioQuality gaming;
  final ScenarioQuality rtc;

  NetworkQuality({
    required this.streaming,
    required this.gaming,
    required this.rtc,
  });

  @override
  String toString() {
    return 'NetworkQuality(\n'
        '  $streaming\n'
        '  $gaming\n'
        '  $rtc\n'
        ')';
  }
}
