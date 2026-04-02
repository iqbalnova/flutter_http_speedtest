### 0.0.5

- Improved upload stream backpressure by replacing delay-based yielding with `request.flush()` to reduce memory buildup and prevent close-time timeouts.
- Improved loaded latency measurement with optional `maxDuration` bounds and full cancellation-aware waits (`cancelToken.race` for ping and interval delays).
- Updated package version to `0.0.5` in `pubspec.yaml`.
- Updated iOS example app integration for implicit Flutter engine registration (`FlutterImplicitEngineDelegate`).
- Updated iOS example plist configuration (scene manifest and related keys) to match the current Flutter/iOS template structure.
- Updated example lockfile dependency snapshots after package/tooling refresh.

### 0.0.1

- Initial release
- Full speed test implementation
- Network quality scoring
- Metadata fetching
- Real-time charting support
- Comprehensive timeout and error handling

### 0.0.2

- Fix download measurement
- Fix Handle network connection failure
- Fix Cancel Test
