// lib/src/models/network_quality.dart

import 'enums.dart';

/// Quality assessment for a specific use-case scenario.
class ScenarioQuality {
  /// Score on a 0–100 scale.
  final double score;

  /// Discrete grade derived from [score].
  final NetworkQualityGrade grade;

  /// Human label, e.g. "Video Streaming".
  final String scenario;

  ScenarioQuality({
    required this.score,
    required this.grade,
    required this.scenario,
  });

  @override
  String toString() => '$scenario: $grade (${score.toStringAsFixed(1)}/100)';
}

/// Aggregated quality profile covering the three main use-cases.
class NetworkQuality {
  final ScenarioQuality streaming;
  final ScenarioQuality gaming;
  final ScenarioQuality rtc;

  /// Overall grade (worst of the three scenarios).
  final NetworkQualityGrade overallGrade;

  NetworkQuality({
    required this.streaming,
    required this.gaming,
    required this.rtc,
  }) : overallGrade = _worst([streaming.grade, gaming.grade, rtc.grade]);

  static NetworkQualityGrade _worst(List<NetworkQualityGrade> grades) {
    const order = [
      NetworkQualityGrade.bad,
      NetworkQualityGrade.poor,
      NetworkQualityGrade.average,
      NetworkQualityGrade.good,
      NetworkQualityGrade.great,
    ];
    for (final g in order) {
      if (grades.contains(g)) return g;
    }
    return NetworkQualityGrade.bad;
  }

  @override
  String toString() =>
      'NetworkQuality(overall=$overallGrade)\n'
      '  $streaming\n'
      '  $gaming\n'
      '  $rtc';
}
