// lib/src/services/metadata_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../cancel_token.dart';
import '../models/metadata.dart';
import '../models/speed_test_options.dart';
import '../models/exceptions.dart';

/// Fetches network metadata from Cloudflare's `/meta` and `/cdn-cgi/trace`
/// endpoints, merging both for maximum coverage.
class MetadataService {
  static const String _endpoint = 'speed.cloudflare.com';
  static const String _metaPath = '/meta';
  static const String _tracePath = '/cdn-cgi/trace';

  final SpeedTestOptions options;

  MetadataService(this.options);

  /// Fetch metadata, racing against [cancelToken].
  Future<NetworkMetadata> fetchMetadata({
    required CancelToken cancelToken,
  }) async {
    final client = options.createHttpClient();

    try {
      NetworkMetadata? metaResult;
      NetworkMetadata? traceResult;

      // 1. Try /meta
      try {
        final body = await cancelToken.race(_get(client, _metaPath));
        metaResult = _parseMeta(body);
      } on SpeedTestCanceledException {
        rethrow;
      } catch (_) {
        // Fall through to trace
      }

      cancelToken.throwIfCanceled();

      // 2. Fallback to /cdn-cgi/trace if meta is incomplete
      if (metaResult == null || _needsTraceFallback(metaResult)) {
        try {
          final body = await cancelToken.race(_get(client, _tracePath));
          traceResult = _parseTrace(body);
        } on SpeedTestCanceledException {
          rethrow;
        } catch (_) {
          // Ignore
        }
      }

      return _merge(metaResult, traceResult);
    } finally {
      client.close(force: true);
    }
  }

  // ── HTTP helper ──────────────────────────────────────────────────────

  Future<String> _get(HttpClient client, String path) async {
    final request = await client
        .getUrl(Uri.https(_endpoint, path))
        .timeout(const Duration(seconds: 3));

    if (path == _metaPath) {
      request.headers.set(
        HttpHeaders.refererHeader,
        'https://speed.cloudflare.com',
      );
    }

    final response = await request.close().timeout(const Duration(seconds: 3));

    if (response.statusCode == 429) {
      await response.drain<void>();
      throw SpeedTestRateLimitException();
    }

    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw HttpException('Request failed ($path): ${response.statusCode}');
    }

    return body;
  }

  // ── Parsing ──────────────────────────────────────────────────────────

  NetworkMetadata _parseMeta(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;

    final ip = json['clientIp'] as String?;
    final asn = json['asn']?.toString();
    final network = json['asOrganization'] as String?;
    final country = json['country'] as String?;

    final coloObj = json['colo'] as Map<String, dynamic>?;
    final coloCode = coloObj?['iata'] as String?;
    final coloCity = coloObj?['city'] as String?;

    return NetworkMetadata(
      ipAddress: ip,
      connectedVia: ip != null ? _detectIpVersion(ip) : null,
      networkName: network,
      asn: asn,
      country: country,
      serverLocation: coloCity ?? coloCode,
      colo: coloCode,
    );
  }

  NetworkMetadata _parseTrace(String body) {
    final data = <String, String>{};
    for (final line in body.split('\n')) {
      final parts = line.split('=');
      if (parts.length == 2) {
        data[parts[0].trim()] = parts[1].trim();
      }
    }

    final ip = data['ip'];
    final colo = data['colo'];

    return NetworkMetadata(
      ipAddress: ip,
      connectedVia: ip != null ? _detectIpVersion(ip) : null,
      country: data['loc'],
      tlsVersion: data['tls'],
      httpVersion: data['http'],
      colo: colo,
      serverLocation: _mapColoToCity(colo) ?? colo,
    );
  }

  // ── Merge ────────────────────────────────────────────────────────────

  NetworkMetadata _merge(NetworkMetadata? meta, NetworkMetadata? trace) {
    if (meta == null && trace == null) {
      throw SpeedTestPhaseException(
        'metadata',
        'Failed to fetch network metadata from both endpoints',
      );
    }

    return NetworkMetadata(
      ipAddress: meta?.ipAddress ?? trace?.ipAddress,
      connectedVia: meta?.connectedVia ?? trace?.connectedVia,
      serverLocation: meta?.serverLocation ?? trace?.serverLocation,
      networkName: meta?.networkName,
      asn: meta?.asn,
      country: meta?.country ?? trace?.country,
      tlsVersion: trace?.tlsVersion,
      httpVersion: trace?.httpVersion,
      colo: meta?.colo ?? trace?.colo,
    );
  }

  bool _needsTraceFallback(NetworkMetadata meta) {
    return meta.ipAddress == null ||
        meta.networkName == null ||
        meta.asn == null ||
        meta.serverLocation == null;
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  String? _detectIpVersion(String ip) {
    if (ip.contains(':')) return 'IPv6';
    if (ip.contains('.')) return 'IPv4';
    return null;
  }

  String? _mapColoToCity(String? colo) {
    if (colo == null) return null;
    const map = {
      'SIN': 'Singapore',
      'HKG': 'Hong Kong',
      'NRT': 'Tokyo',
      'LAX': 'Los Angeles',
      'SFO': 'San Francisco',
      'SEA': 'Seattle',
      'ORD': 'Chicago',
      'IAD': 'Washington DC',
      'EWR': 'New York',
      'MIA': 'Miami',
      'LHR': 'London',
      'AMS': 'Amsterdam',
      'FRA': 'Frankfurt',
      'CDG': 'Paris',
      'SYD': 'Sydney',
      'MEL': 'Melbourne',
      'CGK': 'Jakarta',
      'BOM': 'Mumbai',
      'DEL': 'Delhi',
    };
    return map[colo.toUpperCase()];
  }
}
