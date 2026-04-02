// lib/src/services/upload_service.dart

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import '../cancel_token.dart';
import '../models/speed_test_options.dart';
import '../models/sample.dart';
import '../models/exceptions.dart';

/// Upload speed measurement — chunk-based sequential POST.
///
/// Sends data in 32 KB chunks via a single POST request, sampling
/// throughput at regular intervals. Uses the old p90-trimmed average
/// aggregation for the final result.
class UploadService {
  static const String _endpoint = 'speed.cloudflare.com';

  final SpeedTestOptions options;

  UploadService(this.options);

  /// Run the upload measurement.
  ///
  /// Returns the final upload speed in Mbit/s.
  Future<double> measureUpload({
    required CancelToken cancelToken,
    void Function(SpeedSample sample)? onSample,
  }) async {
    cancelToken.throwIfCanceled();

    // Derive max bytes from duration (assume 10 MB/s ceiling)
    final maxBytes = options.uploadDuration.inSeconds * 10 * 1024 * 1024;

    final client = options.createHttpClient();
    final samples = <SpeedSample>[];

    double ema = 0;
    bool emaInit = false;

    try {
      final uri = Uri.https(_endpoint, '/__up');
      final request = await cancelToken.race(
        client
            .postUrl(uri)
            .timeout(options.uploadDuration + const Duration(seconds: 5)),
      );

      final stopwatch = Stopwatch()..start();

      const chunkSize = 32 * 1024; // 32 KB
      int sentBytes = 0;
      int lastSampleBytes = 0;
      int lastSampleTime = 0;
      int samplesSent = 0;

      final buffer = Uint8List(chunkSize);

      while (sentBytes < maxBytes) {
        // ── Cancel check ──────────────────────────────────────
        cancelToken.throwIfCanceled();

        // ── Duration check ────────────────────────────────────
        if (stopwatch.elapsed >= options.uploadDuration) break;

        final remaining = maxBytes - sentBytes;
        final toSend = math.min(remaining, chunkSize);

        request.add(buffer.sublist(0, toSend));
        sentBytes += toSend;

        // ── Enforce Backpressure ──────────────────────────────
        // Wait for the data to actually flush to the OS socket.
        // This prevents memory bloat and the timeout on request.close().
        await request.flush();

        cancelToken.throwIfCanceled();

        final elapsed = stopwatch.elapsedMilliseconds;

        // ── Sampling ──────────────────────────────────────────
        final shouldSample =
            elapsed - lastSampleTime >= options.sampleIntervalMs;
        final needMoreSamples = samplesSent < 3 && elapsed > 100;

        if (shouldSample || needMoreSamples) {
          final bytesInInterval = sentBytes - lastSampleBytes;
          final timeInInterval = math.max(1, elapsed - lastSampleTime) / 1000.0;
          final mbps = (bytesInInterval * 8) / (timeInInterval * 1000000);

          if (mbps > 0 && mbps < 10000) {
            // ── EMA smoothing ────────────────────────────────
            if (!emaInit) {
              ema = mbps;
              emaInit = true;
            } else {
              ema = options.emaAlpha * mbps + (1 - options.emaAlpha) * ema;
            }

            final sample = SpeedSample(
              timestampMs: elapsed,
              mbps: mbps,
              smoothedMbps: ema,
            );

            samples.add(sample);
            onSample?.call(sample);
            samplesSent++;

            lastSampleBytes = sentBytes;
            lastSampleTime = elapsed;

            // Yield so UI can update
            await Future.delayed(Duration.zero);
          }
        }
      }

      // Flush and wait for server ACK
      final response = await cancelToken.race(
        request.close().timeout(
          options.uploadDuration + const Duration(seconds: 5),
        ),
      );
      await response.drain<void>();

      stopwatch.stop();

      // ── Final aggregation ──────────────────────────────────
      final finalMbps = _calculateFinalMbps(samples);

      // Emit final sample
      if (finalMbps > 0) {
        onSample?.call(
          SpeedSample(
            timestampMs: stopwatch.elapsedMilliseconds,
            mbps: finalMbps,
            smoothedMbps: finalMbps,
          ),
        );
      }

      return finalMbps;
    } on SpeedTestCanceledException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } catch (e) {
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // Aggregation — p90 trimmed average (kept from old service)
  // ══════════════════════════════════════════════════════════════════

  /// Aggregates samples using p90-trimmed average:
  /// 1. Discard bottom 30 % warmup samples.
  /// 2. Sort remaining values.
  /// 3. Use p90 as spike ceiling (clamp at p90 × 1.2).
  /// 4. Average the clamped values.
  double _calculateFinalMbps(List<SpeedSample> samples) {
    if (samples.isEmpty) return 0.0;

    if (samples.length < 3) {
      return samples.map((e) => e.mbps).reduce((a, b) => a + b) /
          samples.length;
    }

    // Step 1: Discard bottom 30% (warmup)
    final startIndex = (samples.length * 0.3).round();
    final stableSamples = samples.length > startIndex
        ? samples.sublist(startIndex)
        : samples;

    if (stableSamples.isEmpty) return samples.last.mbps;

    // Step 2: Extract and sort Mbps values
    final values = stableSamples.map((e) => e.mbps).toList()..sort();

    // Step 3: p90 as peak reference
    final p90Index = (values.length * 0.9).round().clamp(0, values.length - 1);
    final p90 = values[p90Index];

    // Step 4: Filter spikes above p90 × 1.2
    final filtered = values.where((v) => v <= p90 * 1.2).toList();
    final used = filtered.isNotEmpty ? filtered : values;

    // Step 5: Average
    final avg = used.reduce((a, b) => a + b) / used.length;
    return double.parse(avg.toStringAsFixed(2));
  }
}
