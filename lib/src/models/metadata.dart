// lib/src/models/metadata.dart

class NetworkMetadata {
  final String? ipAddress;
  final String? connectedVia; // 'IPv4' or 'IPv6'
  final String? serverLocation; // City name or colo code
  final String? networkName; // ISP name
  final String? asn; // Autonomous System Number
  final String? country;
  final String? tlsVersion;
  final String? httpVersion;
  final String? colo; // Cloudflare colo code

  NetworkMetadata({
    this.ipAddress,
    this.connectedVia,
    this.serverLocation,
    this.networkName,
    this.asn,
    this.country,
    this.tlsVersion,
    this.httpVersion,
    this.colo,
  });

  @override
  String toString() {
    final buffer = StringBuffer('NetworkMetadata(\n');
    if (ipAddress != null) buffer.writeln('  IP: $ipAddress');
    if (connectedVia != null) buffer.writeln('  Connected via: $connectedVia');
    if (serverLocation != null) {
      buffer.writeln('  Server location: $serverLocation');
    }
    if (networkName != null) buffer.writeln('  Network: $networkName');
    if (asn != null) buffer.writeln('  ASN: $asn');
    if (country != null) buffer.writeln('  Country: $country');
    if (tlsVersion != null) buffer.writeln('  TLS: $tlsVersion');
    if (httpVersion != null) buffer.writeln('  HTTP: $httpVersion');
    buffer.write(')');
    return buffer.toString();
  }
}
