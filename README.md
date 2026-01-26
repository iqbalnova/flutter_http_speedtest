# Flutter HTTP Speed Test

A production-ready Flutter package for comprehensive Internet speed testing and network quality analysis, similar to Cloudflare Speed Test and AIM (Aggregated Internet Measurement).

[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Desktop-blue.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.0.0-blue.svg)](https://dart.dev/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## Features

✅ **Pure Dart Implementation** - Cross-platform (Android, iOS, Web, Desktop) using `dart:io` HttpClient  
✅ **Accurate TCP Socket Ping** - True network latency measurement (not HTTP overhead)  
✅ **Comprehensive Metrics** - Download/upload speed, latency, jitter, packet loss, loaded latency  
✅ **Network Quality Scoring** - AIM-inspired scoring for streaming, gaming, and video chatting  
✅ **Real-time Progress** - Live chart data and phase callbacks  
✅ **Production Ready** - Timeouts, cancellation, retry logic, graceful failures  
✅ **Rich Metadata** - IP address, IPv4/IPv6, server location, TLS/HTTP version  
✅ **Zero Native Dependencies** - No platform-specific code required

## Screenshots

| Running Test                 | Results Summary               | Quality Grades               |
| ---------------------------- | ----------------------------- | ---------------------------- |
| ![Running](docs/running.png) | ![Results](docs/results.jpeg) | ![Quality](docs/quality.png) |

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  flutter_http_speedtest:
    git:
      url: https://github.com/iqbalnova/flutter_http_speedtest.git
      ref: 0.0.2
```

Or install it from the command line:

```bash
flutter pub add flutter_http_speedtest
```

## Quick Start

### Basic Usage

```dart
import 'package:flutter_http_speedtest/flutter_http_speedtest.dart';

// Create speed test engine
final tester = SpeedTestEngine(
  downloadBytes: 10 * 1024 * 1024, // 10MB
  uploadBytes: 5 * 1024 * 1024,    // 5MB
  onPhaseChanged: (phase) => print('Phase: $phase'),
  onCompleted: (result) => print(result),
);

// Run the test
final result = await tester.run();

// Access results
print('Download: ${result.downloadMbps?.toStringAsFixed(2)} Mbps');
print('Upload: ${result.uploadMbps?.toStringAsFixed(2)} Mbps');
print('Latency: ${result.latencyMs?.toStringAsFixed(1)} ms');
print('Gaming Quality: ${result.quality.gaming.grade}');
```

### Advanced Configuration

```dart
final tester = SpeedTestEngine(
  downloadBytes: 15 * 1024 * 1024,
  uploadBytes: 10 * 1024 * 1024,
  options: const SpeedTestOptions(
    pingSamples: 20,                              // Number of latency samples
    sampleInterval: Duration(milliseconds: 200),  // Chart update interval
    pingTimeout: Duration(seconds: 5),            // Per-ping timeout
    downloadTimeout: Duration(seconds: 15),       // Download phase timeout
    uploadTimeout: Duration(seconds: 15),         // Upload phase timeout
    maxTotalDuration: Duration(seconds: 35),      // Global timeout
    retries: 1,                                   // Retry failed phases
    loadedLatencySamples: 5,                      // Samples during download
  ),
  onPhaseChanged: (phase) {
    print('Phase: $phase');
  },
  onSample: (sample) {
    if (sample is SpeedSample) {
        if (_currentPhase == TestPhase.download) {
           print('Download sample: ${sample.mbps}');
        } else if (_currentPhase == TestPhase.upload) {
          print('Upload sample: ${sample.mbps}');
        }
      } else if (sample is LatencySample) {
        print('Latency sample: ${sample.mbps}');
      }
  },
  onCompleted: (result) {
    print('Test completed!');
    print(result);
  },
  onError: (error, stack) {
    print('Error: $error');
  },
);

// Run test
await tester.run();

// Cancel test
tester.cancel();
```

## Complete Example

See the [example](example/lib/main.dart) directory for a full Flutter app with:

- Live speed charts during testing
- Real-time phase indicators
- Comprehensive results display
- Network quality cards
- Connection metadata
- Cancel functionality

```dart
void _startTest() {
  _engine = SpeedTestEngine(
    downloadBytes: 10 * 1024 * 1024,
    uploadBytes: 5 * 1024 * 1024,
    options: const SpeedTestOptions(
      pingSamples: 15,
      sampleInterval: Duration(milliseconds: 250),
    ),
    onPhaseChanged: (phase) {
      setState(() => _currentPhase = phase);
    },
    onSample: (sample) {
      setState(() {
        if (sample is SpeedSample && _currentPhase == TestPhase.download) {
          _downloadSamples.add(sample);
        }
      });
    },
    onCompleted: (result) {
      setState(() {
        _result = result;
        _isRunning = false;
      });
    },
  );

  _engine!.run();
}
```

## Architecture

### Core Components

The package is organized into clean, testable components:

```
flutter_http_speedtest/
├── src/
│   ├── speed_test_engine.dart       # Main orchestrator
│   ├── models/                      # Data models
│   │   ├── speed_test_result.dart
│   │   ├── speed_test_options.dart
│   │   ├── metadata.dart
│   │   ├── network_quality.dart
│   │   ├── phase_status.dart
│   │   ├── sample.dart
│   │   ├── enums.dart
|   |   └── exceptions.dart
│   └── services/                    # Service layer
│       ├── tcp_ping_service.dart    # TCP socket-based latency
│       ├── latency_service.dart     # HTTP-based latency (alternative)
│       ├── download_service.dart    # Download speed measurement
│       ├── upload_service.dart      # Upload speed measurement
│       ├── metadata_service.dart    # Network metadata fetching
│       └── quality_scorer.dart      # AIM-inspired quality scoring
└── flutter_http_speedtest.dart      # Public API
```

### Test Phases

The engine runs four sequential phases:

1. **Metadata** (1-2s) - Fetch network information from Cloudflare
2. **Ping** (2-5s) - Measure latency, jitter, and packet loss using TCP sockets
3. **Download** (5-15s) - Measure download throughput + loaded latency
4. **Upload** (5-15s) - Measure upload throughput

Each phase can succeed, fail, timeout, or be canceled independently, with the engine returning partial results.

## Quality Scoring System

The package implements an AIM-inspired scoring system with three usage scenarios:

### Video Streaming

Optimized for high download bandwidth and acceptable latency.

**Weights:**

- Download speed: 60%
- Latency: 20%
- Packet loss: 20%

**Good For:** Netflix, YouTube, Disney+, streaming services

### Online Gaming

Optimized for low latency, minimal jitter, and zero packet loss.

**Weights:**

- Latency: 40%
- Jitter: 25%
- Packet loss: 25%
- Download: 10%

**Good For:** Valorant, CS:GO, Fortnite, competitive gaming

### Video Chatting (RTC)

Optimized for bidirectional quality with low latency.

**Weights:**

- Latency: 30%
- Jitter: 30%
- Packet loss: 25%
- Upload: 15%

**Good For:** Zoom, Teams, Google Meet, WhatsApp calls

### Grade Thresholds

| Score  | Grade   | Description                    |
| ------ | ------- | ------------------------------ |
| 80-100 | Great   | Excellent for this use case    |
| 60-79  | Good    | Works well for this use case   |
| 40-59  | Average | Acceptable for this use case   |
| 20-39  | Poor    | May have issues                |
| 0-19   | Bad     | Not suitable for this use case |

## Latency Measurement

The package uses **TCP socket-based ping** for accurate latency measurement:

### Why TCP Socket Ping?

| Method       | Accuracy             | Overhead | Platform Support       |
| ------------ | -------------------- | -------- | ---------------------- |
| ICMP Ping    | ⭐⭐⭐⭐⭐ Excellent | None     | ❌ Requires root/admin |
| TCP Socket   | ⭐⭐⭐⭐ Very Good   | Minimal  | ✅ All platforms       |
| HTTP Request | ⭐⭐ Poor            | High     | ✅ All platforms       |

**TCP Socket Ping:**

- Measures pure TCP connection time (SYN → SYN-ACK → ACK)
- No TLS handshake overhead
- No HTTP request/response overhead
- Results match Cloudflare website (20-40ms typical)

**Alternative HTTP Ping:**

- Also included in the package (`LatencyService`)
- Uses persistent connections and HEAD requests
- Results: 40-80ms (includes HTTP overhead)

### Measured Metrics

- **Latency**: Trimmed mean of RTT samples (removes outliers)
- **Jitter**: Mean absolute deviation of consecutive RTT differences
- **Packet Loss**: Percentage of failed/timed-out samples
- **Loaded Latency**: Median RTT during download (bufferbloat indicator)

## Cloudflare Endpoints

The package uses official Cloudflare speed test endpoints:

| Endpoint                                | Purpose       | Method     |
| --------------------------------------- | ------------- | ---------- |
| `speed.cloudflare.com/__down?bytes={N}` | Download test | GET        |
| `speed.cloudflare.com/__up`             | Upload test   | POST       |
| `speed.cloudflare.com/cdn-cgi/trace`    | Metadata      | GET        |
| `speed.cloudflare.com:443`              | TCP ping      | TCP Socket |

All endpoints use HTTPS (port 443) and are globally distributed via Cloudflare's edge network.

## Performance Considerations

### Memory Usage

- ✅ Streaming downloads (no large buffers)
- ✅ Chunked uploads (32KB chunks)
- ✅ Sample deduplication
- ✅ Automatic cleanup after test

### Network Efficiency

- ✅ Connection reuse for latency tests
- ✅ Configurable sample intervals
- ✅ Early termination on timeout
- ✅ Graceful connection closure

### Recommended Sizes

| Network Type       | Download | Upload | Duration |
| ------------------ | -------- | ------ | -------- |
| Slow (< 5 Mbps)    | 5 MB     | 2 MB   | 15-20s   |
| Medium (5-50 Mbps) | 10 MB    | 5 MB   | 10-15s   |
| Fast (> 50 Mbps)   | 25 MB    | 15 MB  | 8-12s    |

```dart
// Adaptive sizing example
final downloadBytes = speedMbps < 5
    ? 5 * 1024 * 1024
    : speedMbps < 50
        ? 10 * 1024 * 1024
        : 25 * 1024 * 1024;
```

## Platform Support

| Platform | Status             | Notes                      |
| -------- | ------------------ | -------------------------- |
| Android  | ✅ Fully Supported | API 16+                    |
| iOS      | ✅ Fully Supported | iOS 9+                     |
| Web      | ✅ Supported       | CORS handled by Cloudflare |
| macOS    | ✅ Fully Supported | 10.11+                     |
| Windows  | ✅ Fully Supported | Windows 7+                 |
| Linux    | ✅ Fully Supported | Any                        |

**Pure Dart** - No platform-specific code or native dependencies required.

## FAQ

**Q: Why use Cloudflare endpoints?**  
A: Cloudflare's edge network is globally distributed, reliable, and designed for speed testing. The endpoints are free and don't require API keys.

**Q: Can I use my own server?**  
A: Yes, but you'll need to implement the server endpoints. The package architecture supports custom endpoints by modifying the service classes.

**Q: Why TCP ping instead of ICMP?**  
A: ICMP requires root/admin privileges on mobile platforms. TCP socket ping gives accurate results (20-40ms) without special permissions.

**Q: How accurate is the quality scoring?**  
A: The scoring is based on Cloudflare's AIM (Aggregated Internet Measurement) methodology and industry standards for streaming, gaming, and RTC applications.

**Q: Can I test IPv6 specifically?**  
A: The package automatically uses your system's default network stack. Cloudflare supports both IPv4 and IPv6, and the metadata indicates which was used.

**Q: Does this work on cellular networks?**  
A: Yes, the package works on WiFi, cellular (3G/4G/5G), and wired connections.

## Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Setup

```bash
# Clone repository
git clone https://github.com/yourusername/flutter_http_speedtest.git
cd flutter_http_speedtest

# Install dependencies
flutter pub get

# Run tests
flutter test

# Run example
cd example
flutter run
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- **Cloudflare** for providing reliable speed test endpoints
- **Flutter team** for the excellent cross-platform framework
- **AIM (Aggregated Internet Measurement)** for quality scoring methodology

## Support

- 📫 Issues: [GitHub Issues](https://github.com/yourusername/flutter_http_speedtest/issues)
- 💬 Discussions: [GitHub Discussions](https://github.com/yourusername/flutter_http_speedtest/discussions)
- 📧 Email: iqbalnova707@gmail.com

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

---

**Made with ❤️ by the Flutter community**';

## Implementation Details

### Streaming Architecture

- Uses `dart:io` HttpClient with streaming reads
- No large buffers in memory
- Incremental speed calculation
- Real-time chart sampling

### Latency Measurement

- HTTP RTT to lightweight endpoints
- Multiple samples for statistical accuracy
- Median for latency, mean absolute delta for jitter
- Failed requests counted as packet loss

### Loaded Latency (Bufferbloat)

- Background RTT probes during download
- Indicates network congestion under load
- Useful for gaming and real-time applications

### Cloudflare Endpoints

- Download: `https://speed.cloudflare.com/__down?bytes={N}`
- Upload: `https://speed.cloudflare.com/__up`
- Metadata: `https://speed.cloudflare.com/cdn-cgi/trace`

## Best Practices

1. **Use appropriate download/upload sizes** for network conditions
2. **Implement UI feedback** during long tests
3. **Handle partial results** gracefully
4. **Provide cancel option** for user experience
5. **Show phase progress** to keep users informed
6. **Persist results** for debugging (optional)

## Limitations

- Depends on Cloudflare infrastructure availability
- No fallback servers (can be added in future versions)
- Network metadata limited to Cloudflare trace endpoint
- ISP/ASN data not always available

## License

MIT License - see LICENSE file for details

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.
