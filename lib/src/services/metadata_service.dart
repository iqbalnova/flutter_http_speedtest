import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/metadata.dart';
import '../models/speed_test_options.dart';

class MetadataService {
  static const String _endpoint = 'speed.cloudflare.com';
  static const String _metaPath = '/meta';
  static const String _tracePath = '/cdn-cgi/trace';

  final SpeedTestOptions options;

  MetadataService(this.options);

  Future<NetworkMetadata> fetchMetadata() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 3);

    try {
      NetworkMetadata? metaResult;
      NetworkMetadata? traceResult;

      // 1️⃣ Try /meta first
      try {
        final metaResponse = await _get(client, _metaPath);
        metaResult = _parseMeta(metaResponse);
      } catch (_) {
        // ignore, fallback later
      }

      // 2️⃣ If meta incomplete or failed → fallback to trace
      if (metaResult == null || _needsTraceFallback(metaResult)) {
        try {
          final traceResponse = await _get(client, _tracePath);
          traceResult = _parseTrace(traceResponse);
        } catch (_) {
          // ignore
        }
      }

      // 3️⃣ Merge results (meta first, trace as fallback)
      return _merge(metaResult, traceResult);
    } finally {
      client.close();
    }
  }

  // -----------------------
  // HTTP helper
  // -----------------------
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

    final body = await response.transform(utf8.decoder).join();

    print('GET $path (${response.statusCode}): $body');

    if (response.statusCode != 200) {
      throw Exception('Request failed: $path');
    }

    return body; // RETURN BODY, BUKAN STREAM LAGI
  }

  // -----------------------
  // Parsing
  // -----------------------

  NetworkMetadata _parseMeta(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;

    final ip = json['clientIp'];
    final asn = json['asn']?.toString();
    final network = json['asOrganization'];
    final country = json['country'];

    final coloObj = json['colo'] as Map<String, dynamic>?;
    final coloCode = coloObj?['iata']; // CGK
    final coloCity = coloObj?['city']; // Jakarta

    return NetworkMetadata(
      ipAddress: ip,
      connectedVia: ip != null ? _detectIpVersion(ip) : null,
      networkName: network,
      asn: asn,
      country: country,

      /// ✅ SERVER LOCATION HARUS DARI COLO
      serverLocation: coloCity ?? coloCode,
      colo: coloCode,
    );
  }

  NetworkMetadata _parseTrace(String body) {
    final lines = body.split('\n');
    final data = <String, String>{};

    for (final line in lines) {
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

  // -----------------------
  // Merge logic
  // -----------------------

  NetworkMetadata _merge(NetworkMetadata? meta, NetworkMetadata? trace) {
    if (meta == null && trace == null) {
      throw Exception('Failed to fetch network metadata');
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

  // -----------------------
  // Helpers
  // -----------------------

  String? _detectIpVersion(String ip) {
    if (ip.contains(':')) return 'IPv6';
    if (ip.contains('.')) return 'IPv4';
    return null;
  }

  String? _mapColoToCity(String? colo) {
    if (colo == null) return null;

    const coloMap = {
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

    return coloMap[colo.toUpperCase()];
  }
}
