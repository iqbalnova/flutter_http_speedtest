// lib/src/services/quality_scorer.dart

import 'dart:math' as math;
import '../models/network_quality.dart';
import '../models/enums.dart';

/// Computes WiFiMan / Ookla-style quality grades.
///
/// ```
/// Excellent : latency < 20ms, jitter < 5ms, loss = 0 %, dl > 50 Mbps
/// Good      : latency < 50ms, jitter < 15ms, loss < 1 %, dl > 10 Mbps
/// Fair      : latency < 100ms, jitter < 30ms, loss < 5 %, dl > 2 Mbps
/// Poor      : anything worse
/// ```
class QualityScorer {
  /// Compute the full quality profile from test results.
  static NetworkQuality calculateQuality({
    double? latencyMs,
    double? jitterMs,
    double? packetLossPercent,
    double? downloadMbps,
    double? uploadMbps,
    double? loadedLatencyMs,
  }) {
    final streaming = _streamingScore(
      downloadMbps: downloadMbps,
      latencyMs: latencyMs,
      packetLossPercent: packetLossPercent,
    );

    final gaming = _gamingScore(
      latencyMs: latencyMs,
      jitterMs: jitterMs,
      packetLossPercent: packetLossPercent,
      downloadMbps: downloadMbps,
      loadedLatencyMs: loadedLatencyMs,
    );

    final rtc = _rtcScore(
      latencyMs: latencyMs,
      jitterMs: jitterMs,
      packetLossPercent: packetLossPercent,
      uploadMbps: uploadMbps,
      downloadMbps: downloadMbps,
    );

    return NetworkQuality(streaming: streaming, gaming: gaming, rtc: rtc);
  }

  // ────────────────────────────────────────────────────────────────────
  // Scenario scorers
  // ────────────────────────────────────────────────────────────────────

  static ScenarioQuality _streamingScore({
    double? downloadMbps,
    double? latencyMs,
    double? packetLossPercent,
  }) {
    double score = 0;

    // Download speed (60 % weight)
    if (downloadMbps != null) {
      if (downloadMbps >= 50) {
        score += 60;
      } else if (downloadMbps >= 25) {
        score += 50 + (downloadMbps - 25) / 25 * 10;
      } else if (downloadMbps >= 10) {
        score += 35 + (downloadMbps - 10) / 15 * 15;
      } else if (downloadMbps >= 5) {
        score += 20 + (downloadMbps - 5) / 5 * 15;
      } else {
        score += downloadMbps / 5 * 20;
      }
    }

    // Latency (20 % weight)
    if (latencyMs != null) {
      if (latencyMs <= 50) {
        score += 20;
      } else if (latencyMs <= 100) {
        score += 15 + (50 - (latencyMs - 50)) / 50 * 5;
      } else if (latencyMs <= 200) {
        score += 10 + (100 - (latencyMs - 100)) / 100 * 5;
      } else {
        score += math.max(0, 10 - (latencyMs - 200) / 100);
      }
    }

    // Packet loss (20 % weight)
    if (packetLossPercent != null) {
      if (packetLossPercent == 0) {
        score += 20;
      } else if (packetLossPercent < 1) {
        score += 15;
      } else if (packetLossPercent < 3) {
        score += 10;
      } else if (packetLossPercent < 5) {
        score += 5;
      }
    }

    return ScenarioQuality(
      score: score.clamp(0, 100),
      grade: _scoreToGrade(score),
      scenario: 'Video Streaming',
    );
  }

  static ScenarioQuality _gamingScore({
    double? latencyMs,
    double? jitterMs,
    double? packetLossPercent,
    double? downloadMbps,
    double? loadedLatencyMs,
  }) {
    double score = 0;

    // Latency (35 % weight)
    if (latencyMs != null) {
      final effectiveLatency = loadedLatencyMs ?? latencyMs;
      if (effectiveLatency <= 20) {
        score += 35;
      } else if (effectiveLatency <= 50) {
        score += 25 + (30 - (effectiveLatency - 20)) / 30 * 10;
      } else if (effectiveLatency <= 100) {
        score += 10 + (50 - (effectiveLatency - 50)) / 50 * 15;
      } else {
        score += math.max(0, 10 - (effectiveLatency - 100) / 50);
      }
    }

    // Jitter (30 % weight)
    if (jitterMs != null) {
      if (jitterMs <= 5) {
        score += 30;
      } else if (jitterMs <= 15) {
        score += 20 + (10 - (jitterMs - 5)) / 10 * 10;
      } else if (jitterMs <= 30) {
        score += 10 + (15 - (jitterMs - 15)) / 15 * 10;
      } else {
        score += math.max(0, 10 - (jitterMs - 30) / 20);
      }
    }

    // Packet loss (25 % weight)
    if (packetLossPercent != null) {
      if (packetLossPercent == 0) {
        score += 25;
      } else if (packetLossPercent < 0.5) {
        score += 20;
      } else if (packetLossPercent < 1) {
        score += 10;
      } else if (packetLossPercent < 2) {
        score += 5;
      }
    }

    // Download speed (10 % weight)
    if (downloadMbps != null) {
      if (downloadMbps >= 10) {
        score += 10;
      } else if (downloadMbps >= 5) {
        score += 5 + (downloadMbps - 5) / 5 * 5;
      } else {
        score += downloadMbps / 5 * 5;
      }
    }

    return ScenarioQuality(
      score: score.clamp(0, 100),
      grade: _scoreToGrade(score),
      scenario: 'Online Gaming',
    );
  }

  static ScenarioQuality _rtcScore({
    double? latencyMs,
    double? jitterMs,
    double? packetLossPercent,
    double? uploadMbps,
    double? downloadMbps,
  }) {
    double score = 0;

    // Latency (30 % weight)
    if (latencyMs != null) {
      if (latencyMs <= 30) {
        score += 30;
      } else if (latencyMs <= 60) {
        score += 20 + (30 - (latencyMs - 30)) / 30 * 10;
      } else if (latencyMs <= 150) {
        score += 10 + (90 - (latencyMs - 60)) / 90 * 10;
      } else {
        score += math.max(0, 10 - (latencyMs - 150) / 100);
      }
    }

    // Jitter (30 % weight)
    if (jitterMs != null) {
      if (jitterMs <= 10) {
        score += 30;
      } else if (jitterMs <= 20) {
        score += 20 + (10 - (jitterMs - 10)) / 10 * 10;
      } else if (jitterMs <= 40) {
        score += 10 + (20 - (jitterMs - 20)) / 20 * 10;
      } else {
        score += math.max(0, 10 - (jitterMs - 40) / 30);
      }
    }

    // Packet loss (25 % weight)
    if (packetLossPercent != null) {
      if (packetLossPercent == 0) {
        score += 25;
      } else if (packetLossPercent < 0.5) {
        score += 20;
      } else if (packetLossPercent < 1) {
        score += 12;
      } else if (packetLossPercent < 2) {
        score += 5;
      }
    }

    // Upload speed (15 % weight)
    if (uploadMbps != null) {
      if (uploadMbps >= 5) {
        score += 15;
      } else if (uploadMbps >= 2) {
        score += 10 + (uploadMbps - 2) / 3 * 5;
      } else if (uploadMbps >= 1) {
        score += 5 + (uploadMbps - 1) * 5;
      } else {
        score += uploadMbps * 5;
      }
    }

    return ScenarioQuality(
      score: score.clamp(0, 100),
      grade: _scoreToGrade(score),
      scenario: 'Video Chatting',
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // Grade mapping – WiFiMan style
  // ────────────────────────────────────────────────────────────────────

  static NetworkQualityGrade _scoreToGrade(double score) {
    if (score >= 80) return NetworkQualityGrade.great;
    if (score >= 60) return NetworkQualityGrade.good;
    if (score >= 40) return NetworkQualityGrade.average;
    if (score >= 20) return NetworkQualityGrade.poor;
    return NetworkQualityGrade.bad;
  }
}
