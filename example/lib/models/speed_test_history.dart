// lib/models/speed_test_history.dart
import 'package:hive_ce/hive.dart';

part 'speed_test_history.g.dart';

@HiveType(typeId: 0)
class SpeedTestHistory extends HiveObject {
  @HiveField(0)
  final DateTime timestamp;

  @HiveField(1)
  final SpeedTestResultData result;

  SpeedTestHistory({required this.timestamp, required this.result});

  /// Create from SpeedTestResult with current or custom timestamp
  factory SpeedTestHistory.fromResult(
    dynamic speedTestResult, {
    DateTime? customTimestamp,
  }) {
    return SpeedTestHistory(
      timestamp: customTimestamp ?? DateTime.now(),
      result: SpeedTestResultData.fromResult(speedTestResult),
    );
  }

  /// Get formatted time ago string
  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inSeconds < 10) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds} seconds ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';

    final weeks = (diff.inDays / 7).floor();
    if (weeks < 4) return '$weeks weeks ago';

    final months = (diff.inDays / 30).floor();
    if (months == 1) return 'Last month';
    if (months < 12) return '$months months ago';

    final years = (diff.inDays / 365).floor();
    if (years == 1) return 'Last year';
    return '$years years ago';
  }

  /// Get formatted date string
  String get formattedDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final testDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (testDate == today) {
      return 'Today at ${_formatTime(timestamp)}';
    } else if (testDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday at ${_formatTime(timestamp)}';
    } else {
      return '${_formatDate(timestamp)} at ${_formatTime(timestamp)}';
    }
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  // Convenience getters for backward compatibility
  double? get downloadMbps => result.downloadMbps;
  double? get uploadMbps => result.uploadMbps;
  double? get latencyMs => result.latencyMs;
  double? get jitterMs => result.jitterMs;
  double? get packetLossPercent => result.packetLossPercent;
  NetworkQualityData get quality => result.quality;
  NetworkMetadataData? get metadata => result.metadata;
}

@HiveType(typeId: 1)
class SpeedTestResultData {
  @HiveField(0)
  final double? downloadMbps;

  @HiveField(1)
  final double? uploadMbps;

  @HiveField(2)
  final double? latencyMs;

  @HiveField(3)
  final double? jitterMs;

  @HiveField(4)
  final double? packetLossPercent;

  @HiveField(5)
  final double? loadedLatencyMs;

  @HiveField(6)
  final NetworkQualityData quality;

  @HiveField(7)
  final NetworkMetadataData? metadata;

  SpeedTestResultData({
    this.downloadMbps,
    this.uploadMbps,
    this.latencyMs,
    this.jitterMs,
    this.packetLossPercent,
    this.loadedLatencyMs,
    required this.quality,
    this.metadata,
  });

  factory SpeedTestResultData.fromResult(dynamic result) {
    return SpeedTestResultData(
      downloadMbps: result.downloadMbps,
      uploadMbps: result.uploadMbps,
      latencyMs: result.latencyMs,
      jitterMs: result.jitterMs,
      packetLossPercent: result.packetLossPercent,
      loadedLatencyMs: result.loadedLatencyMs,
      quality: NetworkQualityData.fromQuality(result.quality),
      metadata: result.metadata != null
          ? NetworkMetadataData.fromMetadata(result.metadata!)
          : null,
    );
  }
}

@HiveType(typeId: 2)
class NetworkQualityData {
  @HiveField(0)
  final ScenarioQualityData streaming;

  @HiveField(1)
  final ScenarioQualityData gaming;

  @HiveField(2)
  final ScenarioQualityData rtc;

  NetworkQualityData({
    required this.streaming,
    required this.gaming,
    required this.rtc,
  });

  factory NetworkQualityData.fromQuality(dynamic quality) {
    return NetworkQualityData(
      streaming: ScenarioQualityData.fromScenarioQuality(quality.streaming),
      gaming: ScenarioQualityData.fromScenarioQuality(quality.gaming),
      rtc: ScenarioQualityData.fromScenarioQuality(quality.rtc),
    );
  }
}

@HiveType(typeId: 3)
class ScenarioQualityData {
  @HiveField(0)
  final String scenario;

  @HiveField(1)
  final int gradeIndex; // Store as int: 0=bad, 1=poor, 2=average, 3=good, 4=great

  ScenarioQualityData({required this.scenario, required this.gradeIndex});

  factory ScenarioQualityData.fromScenarioQuality(dynamic scenarioQuality) {
    return ScenarioQualityData(
      scenario: scenarioQuality.scenario,
      gradeIndex: scenarioQuality.grade.index,
    );
  }

  /// Get grade enum value
  NetworkQualityGrade get grade {
    return NetworkQualityGrade.values[gradeIndex];
  }

  /// Get grade text
  String get gradeText {
    switch (gradeIndex) {
      case 0:
        return 'Bad';
      case 1:
        return 'Poor';
      case 2:
        return 'Average';
      case 3:
        return 'Good';
      case 4:
        return 'Great';
      default:
        return 'Unknown';
    }
  }
}

@HiveType(typeId: 4)
class NetworkMetadataData {
  @HiveField(0)
  final String? networkName;

  @HiveField(1)
  final String? connectedVia;

  @HiveField(2)
  final String? serverLocation;

  @HiveField(3)
  final String? ipAddress;

  NetworkMetadataData({
    this.networkName,
    this.connectedVia,
    this.serverLocation,
    this.ipAddress,
  });

  factory NetworkMetadataData.fromMetadata(dynamic metadata) {
    return NetworkMetadataData(
      networkName: metadata.networkName,
      connectedVia: metadata.connectedVia,
      serverLocation: metadata.serverLocation,
      ipAddress: metadata.ipAddress,
    );
  }
}

enum NetworkQualityGrade { bad, poor, average, good, great }
