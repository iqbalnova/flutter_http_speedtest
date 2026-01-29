// lib/src/services/upload_service.dart

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import '../models/speed_test_options.dart';
import '../models/sample.dart';

class UploadService {
  static const String _endpoint = 'speed.cloudflare.com';
  final SpeedTestOptions options;

  UploadService(this.options);

  Future<double> measureUpload({
    required int bytes,
    void Function(SpeedSample sample)? onSample,
    Future<void>? cancelToken,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);

    // 🔥 Store all samples for final calculation (same as download)
    final List<SpeedSample> samples = [];

    try {
      final uri = Uri.https(_endpoint, '/__up');
      final request = await client.postUrl(uri).timeout(options.uploadTimeout);

      final stopwatch = Stopwatch()..start();

      // Use smaller chunks and add delays to make upload measurable
      const chunkSize = 32 * 1024; // 32KB chunks (smaller for more samples)
      int sentBytes = 0;
      int lastSampleBytes = 0;
      int lastSampleTime = 0;
      final buffer = Uint8List(chunkSize);

      // Track samples to ensure we send at least a few
      int samplesSent = 0;

      while (sentBytes < bytes) {
        if (cancelToken != null) {
          final race = await Future.any([
            Future.value(false),
            cancelToken.then((_) => true),
          ]);
          if (race) {
            await request.close();
            throw Exception('Canceled');
          }
        }

        final remaining = bytes - sentBytes;
        final toSend = math.min(remaining, chunkSize);

        request.add(buffer.sublist(0, toSend));
        sentBytes += toSend;

        // Small delay to allow network transmission and event loop processing
        // This ensures samples are actually sent at meaningful intervals
        await Future.delayed(const Duration(milliseconds: 5));

        final elapsed = stopwatch.elapsedMilliseconds;

        // Calculate speed at intervals OR force samples if too few
        final shouldSample =
            elapsed - lastSampleTime >= options.sampleInterval.inMilliseconds;
        final needMoreSamples =
            samplesSent < 3 && elapsed > 100; // Ensure minimum samples

        if (shouldSample || needMoreSamples) {
          final bytesInInterval = sentBytes - lastSampleBytes;
          final timeInInterval = math.max(1, elapsed - lastSampleTime) / 1000.0;
          final mbps = (bytesInInterval * 8) / (timeInInterval * 1000000);

          // Only send meaningful samples (avoid division by zero or extreme values)
          if (mbps > 0 && mbps < 10000) {
            final sample = SpeedSample(timestampMs: elapsed, mbps: mbps);

            // 🔥 Store sample for final calculation
            samples.add(sample);

            onSample?.call(sample);
            samplesSent++;

            lastSampleBytes = sentBytes;
            lastSampleTime = elapsed;

            // Critical: yield to event loop so UI can update
            await Future.delayed(Duration.zero);
          }
        }
      }

      // Wait for server to acknowledge receipt
      final response = await request.close().timeout(options.uploadTimeout);
      await response.drain();

      stopwatch.stop();

      // 🔥 CALCULATE FINAL SPEED USING SAME ALGORITHM AS DOWNLOAD
      final finalMbps = _calculateFinalMbps(samples);

      // Send final sample to show completion (using calculated final speed)
      if (finalMbps > 0) {
        onSample?.call(
          SpeedSample(
            timestampMs: stopwatch.elapsedMilliseconds,
            mbps: finalMbps,
          ),
        );
      }

      return finalMbps;
    } finally {
      client.close();
    }
  }

  /// ============================
  /// FINAL SPEED AGGREGATION LOGIC
  /// (Identical to DownloadService)
  /// ============================

  double _calculateFinalMbps(List<SpeedSample> samples) {
    if (samples.isEmpty) {
      // Fallback: no samples collected
      return 0.0;
    }

    // If we have very few samples, just return the average
    if (samples.length < 3) {
      final avg =
          samples.map((e) => e.mbps).reduce((a, b) => a + b) / samples.length;
      return avg;
    }

    // 🔹 1. Buang warm-up awal (30%)
    final startIndex = (samples.length * 0.3).round();
    final stableSamples = samples.length > startIndex
        ? samples.sublist(startIndex)
        : samples;

    if (stableSamples.isEmpty) {
      return samples.last.mbps;
    }

    // 🔹 2. Ambil nilai Mbps saja
    final values = stableSamples.map((e) => e.mbps).toList();

    // Sort ascending
    values.sort();

    // 🔹 3. Ambil percentile 90 sebagai peak reference
    final p90Index = (values.length * 0.9).round().clamp(0, values.length - 1);
    final p90 = values[p90Index];

    // 🔹 4. Clamp spike ekstrem (anti burst buffer)
    final filtered = values.where((v) => v <= p90 * 1.2).toList();

    final used = filtered.isNotEmpty ? filtered : values;

    // 🔹 5. Average stable window
    final avg = used.reduce((a, b) => a + b) / used.length;

    return avg;
  }
}
