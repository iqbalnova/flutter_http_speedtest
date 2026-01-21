// lib/src/services/metadata_service.dart

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import '../models/speed_test_options.dart';
import '../models/metadata.dart';

class MetadataService {
  static const String _endpoint = 'speed.cloudflare.com';
  static const String _tracePath = '/cdn-cgi/trace';
  final SpeedTestOptions options;

  MetadataService(this.options);

  Future<NetworkMetadata> fetchMetadata() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 3);

    try {
      final request = await client
          .getUrl(Uri.https(_endpoint, _tracePath))
          .timeout(const Duration(seconds: 3));
      // request.headers.set('User-Agent', 'flutter_http_speedtest/1.0');

      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );

      if (response.statusCode != 200) {
        throw Exception('Metadata fetch failed: ${response.statusCode}');
      }

      final body = await response.transform(utf8.decoder).join();
      return _parseTrace(body);
    } finally {
      client.close();
    }
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
    final connectedVia = ip != null ? _detectIpVersion(ip) : null;
    final colo = data['colo'];
    final loc = data['loc'];
    final serverLocation = _mapColoToCity(colo) ?? colo;

    return NetworkMetadata(
      ipAddress: ip,
      connectedVia: connectedVia,
      serverLocation: serverLocation,
      colo: colo,
      country: loc,
      tlsVersion: data['tls'],
      httpVersion: data['http'],
      // ASN and network name not available in trace, would need /meta endpoint
    );
  }

  String? _detectIpVersion(String ip) {
    if (ip.contains(':')) {
      return 'IPv6';
    } else if (ip.contains('.')) {
      return 'IPv4';
    }
    return null;
  }

  String? _mapColoToCity(String? colo) {
    if (colo == null) return null;

    // Partial mapping of common Cloudflare colo codes
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
