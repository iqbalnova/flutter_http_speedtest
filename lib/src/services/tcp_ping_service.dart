// lib/src/services/tcp_ping_service.dart
//
// Re-exported from latency_service.dart for backwards compatibility.
// All TCP-ping logic now lives in LatencyService.

export 'latency_service.dart' show LatencyResult, LatencyService;

//    final latencyService = TcpPingService(options);
//
// 3. Update download_service.dart to use TcpPingService for loaded latency:
//    final latencyService = TcpPingService(options);
//
// This will give you results much closer to Cloudflare's website!
// ============================================================================
