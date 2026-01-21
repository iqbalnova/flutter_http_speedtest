// lib/src/services/upload_service_v2.dart
//
// IMPROVED VERSION: Guarantees upload samples are visible
// Replace your existing upload_service.dart with this

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

    try {
      final uri = Uri.https(_endpoint, '/__up');
      final request = await client.postUrl(uri).timeout(options.uploadTimeout);
      // request.headers.set('User-Agent', 'flutter_http_speedtest/1.0');
      // request.headers.set('Content-Length', bytes.toString());
      // request.headers.contentType = ContentType('application', 'octet-stream');

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
            onSample?.call(SpeedSample(timestampMs: elapsed, mbps: mbps));
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

      // Send final sample to show completion
      final totalSeconds = math.max(
        0.001,
        stopwatch.elapsedMilliseconds / 1000.0,
      );
      final finalMbps = (sentBytes * 8) / (totalSeconds * 1000000);

      // Always send at least one final sample
      if (samplesSent == 0 ||
          stopwatch.elapsedMilliseconds - lastSampleTime > 100) {
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
}
