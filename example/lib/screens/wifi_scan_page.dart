import 'package:flutter/material.dart';
import 'package:flutter_wifi_scan/flutter_wifi_scan.dart';
import 'dart:async';

/// Scanner state enum - represents all possible states
enum ScannerState {
  initializing,
  unsupported,
  permissionDenied,
  locationDisabled,
  ready,
  error,
}

/// Combined state model for the scanner
class WifiScannerModel {
  final ScannerState state;
  final List<WiFiScanResult> results;
  final String? errorMessage;

  const WifiScannerModel({
    required this.state,
    this.results = const [],
    this.errorMessage,
  });

  WifiScannerModel copyWith({
    ScannerState? state,
    List<WiFiScanResult>? results,
    String? errorMessage,
  }) {
    return WifiScannerModel(
      state: state ?? this.state,
      results: results ?? this.results,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  String get statusMessage {
    switch (state) {
      case ScannerState.initializing:
        return 'Initializing scanner...';
      case ScannerState.unsupported:
        return 'Wi-Fi scanning is not supported on this platform';
      case ScannerState.permissionDenied:
        return 'Location permission required for Wi-Fi scanning';
      case ScannerState.locationDisabled:
        return 'Please enable location services';
      case ScannerState.ready:
        return results.isEmpty
            ? 'Scanning for networks...'
            : 'Found ${results.length} networks';
      case ScannerState.error:
        return errorMessage ?? 'An error occurred';
    }
  }

  bool get canScan => state == ScannerState.ready;
  bool get needsPermission => state == ScannerState.permissionDenied;
  bool get isInitializing => state == ScannerState.initializing;
}

class WifiScanPage extends StatefulWidget {
  const WifiScanPage({super.key});

  @override
  State<WifiScanPage> createState() => _WifiScanPageState();
}

class _WifiScanPageState extends State<WifiScanPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Single source of truth for all state
  final _stateController = StreamController<WifiScannerModel>.broadcast();
  WifiScannerModel _currentState = const WifiScannerModel(
    state: ScannerState.initializing,
  );

  StreamSubscription<List<WiFiScanResult>>? _scanSubscription;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initializeScanner();
  }

  /// Safely update state - checks if widget is still mounted
  void _updateState(WifiScannerModel newState) {
    if (_isDisposed) return;

    _currentState = newState;
    _stateController.add(newState);
  }

  Future<void> _initializeScanner() async {
    try {
      // Step 1: Check platform support
      final supported = await FlutterWifiScan.isSupported;
      if (!supported) {
        _updateState(_currentState.copyWith(state: ScannerState.unsupported));
        return;
      }

      // Step 2: Check permissions
      final hasPerms = await FlutterWifiScan.hasPermissions;
      if (!hasPerms) {
        _updateState(
          _currentState.copyWith(state: ScannerState.permissionDenied),
        );
        return;
      }

      // Step 3: REMOVED WiFi enabled check - scanning works even when WiFi is off
      // Android allows WiFi scanning even when WiFi radio is disabled

      // Step 4: Check location enabled (still required for Android)
      final locationEnabled = await FlutterWifiScan.isLocationEnabled;
      if (!locationEnabled) {
        _updateState(
          _currentState.copyWith(state: ScannerState.locationDisabled),
        );
        return;
      }

      // All checks passed - start scanning
      _updateState(_currentState.copyWith(state: ScannerState.ready));
      _startScanning();
    } catch (e) {
      _updateState(
        _currentState.copyWith(
          state: ScannerState.error,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  void _startScanning() {
    // Cancel any existing subscription to prevent duplicates
    _scanSubscription?.cancel();

    _scanSubscription = FlutterWifiScan.startScan().listen(
      (results) {
        if (_isDisposed) return;

        _updateState(
          _currentState.copyWith(state: ScannerState.ready, results: results),
        );
      },
      onError: (error) {
        if (_isDisposed) return;

        _updateState(
          _currentState.copyWith(
            state: ScannerState.error,
            errorMessage: error.toString(),
          ),
        );
      },
    );
  }

  Future<void> _requestPermissions() async {
    try {
      final granted = await FlutterWifiScan.requestPermissions();

      if (granted) {
        // Re-run the full initialization sequence
        await _initializeScanner();
      } else {
        _updateState(
          _currentState.copyWith(state: ScannerState.permissionDenied),
        );
      }
    } catch (e) {
      _updateState(
        _currentState.copyWith(
          state: ScannerState.error,
          errorMessage: 'Failed to request permissions: $e',
        ),
      );
    }
  }

  Future<void> _refreshScan() async {
    if (_currentState.canScan) {
      try {
        await FlutterWifiScan.refreshScan();
      } catch (e) {
        // Silently handle refresh errors
        debugPrint('Refresh scan error: $e');
      }
    }
  }

  Future<void> _openWifiSettings() async {
    // Uncomment when android_intent_plus is available
    // final intent = AndroidIntent(
    //   action: 'android.settings.WIFI_SETTINGS',
    // );
    // await intent.launch();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _scanSubscription?.cancel();
    FlutterWifiScan.stopScan();
    _tabController.dispose();
    _stateController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Scanner'),
        actions: [
          // Refresh button - only show when ready
          StreamBuilder<WifiScannerModel>(
            stream: _stateController.stream,
            initialData: _currentState,
            builder: (context, snapshot) {
              final model = snapshot.data!;
              if (model.canScan) {
                return IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _refreshScan,
                );
              }
              return const SizedBox.shrink();
            },
          ),
          // Settings button
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openWifiSettings,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: '2.4 GHz'),
            Tab(text: '5 GHz'),
            Tab(text: '6 GHz'),
          ],
        ),
      ),
      body: StreamBuilder<WifiScannerModel>(
        stream: _stateController.stream,
        initialData: _currentState,
        builder: (context, snapshot) {
          final model = snapshot.data!;

          return Column(
            children: [
              // Status bar
              _buildStatusBar(context, model),

              // Main content area
              Expanded(child: _buildContent(context, model)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context, WifiScannerModel model) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Row(
        children: [
          Icon(
            _getStatusIcon(model.state),
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              model.statusMessage,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon(ScannerState state) {
    switch (state) {
      case ScannerState.initializing:
        return Icons.hourglass_empty;
      case ScannerState.ready:
        return Icons.wifi_find;
      case ScannerState.error:
        return Icons.error_outline;
      default:
        return Icons.wifi_off;
    }
  }

  Widget _buildContent(BuildContext context, WifiScannerModel model) {
    // Show appropriate UI based on state
    switch (model.state) {
      case ScannerState.initializing:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing Wi-Fi scanner...'),
            ],
          ),
        );

      case ScannerState.unsupported:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.phonelink_off, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Wi-Fi scanning not supported',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
            ],
          ),
        );

      case ScannerState.permissionDenied:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.security, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Location Permission Required',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Wi-Fi scanning requires location permission to function',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _requestPermissions,
                  icon: const Icon(Icons.security),
                  label: const Text('Grant Permission'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

      case ScannerState.locationDisabled:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  model.state == ScannerState.locationDisabled
                      ? Icons.wifi_off
                      : Icons.location_off,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  model.statusMessage,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _openWifiSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('Open Settings'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

      case ScannerState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text('Error', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  model.errorMessage ?? 'An unknown error occurred',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _initializeScanner,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        );

      case ScannerState.ready:
        return TabBarView(
          controller: _tabController,
          children: [
            _buildNetworkList(model.results, null),
            _buildNetworkList(model.results, WiFiBand.band24GHz),
            _buildNetworkList(model.results, WiFiBand.band5GHz),
            _buildNetworkList(model.results, WiFiBand.band6GHz),
          ],
        );
    }
  }

  Widget _buildNetworkList(
    List<WiFiScanResult> allResults,
    WiFiBand? filterBand,
  ) {
    // Filter by band
    var networks = allResults;
    if (filterBand != null) {
      networks = networks.where((n) => n.band == filterBand).toList();
    }

    if (networks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              filterBand == null
                  ? 'No networks found'
                  : 'No networks in ${filterBand.displayName}',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    // Sort by signal strength (strongest first)
    final sortedNetworks = List<WiFiScanResult>.from(networks)
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return ListView.builder(
      itemCount: sortedNetworks.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        return _buildNetworkTile(sortedNetworks[index]);
      },
    );
  }

  Widget _buildNetworkTile(WiFiScanResult result) {
    final strength = result.signalStrengthPercent;
    final quality = _getSignalQuality(strength);
    final color = _getSignalColor(strength);

    return GestureDetector(
      onTap: () => _showNetworkDetails(result),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header (SSID + RSSI + Quality)
            Row(
              children: [
                Icon(Icons.wifi, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.ssid.isEmpty ? '<Hidden Network>' : result.ssid,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  quality.label,
                  style: TextStyle(
                    color: quality.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),
            Text(
              '${result.rssi} dBm',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 12),

            // Signal bars
            _buildSignalBars(strength, color),

            const SizedBox(height: 16),

            // Info rows
            _buildInfoRow('Security', result.security.displayName),
            _buildInfoRow('Channel', result.channel?.toString() ?? '-'),
            _buildInfoRow(
              'Channel Width',
              result.channelWidth != null ? '${result.channelWidth} MHz' : '-',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignalBars(int strength, Color color) {
    int activeBars;
    if (strength >= 75) {
      activeBars = 4;
    } else if (strength >= 50) {
      activeBars = 3;
    } else if (strength >= 25) {
      activeBars = 2;
    } else {
      activeBars = 1;
    }

    return Row(
      children: List.generate(4, (index) {
        final isActive = index < activeBars;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            height: 8,
            decoration: BoxDecoration(
              color: isActive ? color : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  ({String label, Color color}) _getSignalQuality(int strength) {
    if (strength >= 70) {
      return (label: 'Sangat Kuat', color: Colors.green);
    } else if (strength >= 40) {
      return (label: 'Cukup', color: Colors.orange);
    } else {
      return (label: 'Lemah', color: Colors.red);
    }
  }

  Color _getSignalColor(int strength) {
    if (strength >= 60) return Colors.green;
    if (strength >= 40) return Colors.orange;
    return Colors.red;
  }

  void _showNetworkDetails(WiFiScanResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) {
          return NetworkDetailView(
            result: result,
            scrollController: scrollController,
          );
        },
      ),
    );
  }
}

class NetworkDetailView extends StatelessWidget {
  final WiFiScanResult result;
  final ScrollController scrollController;

  const NetworkDetailView({
    super.key,
    required this.result,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Center(
            child: Text(
              'Detail jaringan Wi-Fi',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),

          const SizedBox(height: 24),

          _detailRow('SSID', result.ssid.isEmpty ? '<Hidden>' : result.ssid),
          _detailRow('BSSID', result.bssid),
          _detailRow('Security', result.security.displayName),
          _detailRow('Band', result.band.displayName),
          _detailRow('RSSI', '${result.rssi} dBm'),
          _detailRow('Signal Strength', '${result.signalStrengthPercent}%'),
          if (result.manufacturer != null)
            _detailRow('Manufacturer', result.manufacturer!),
          if (result.frequency != null)
            _detailRow('Frequency', '${result.frequency} MHz'),
          if (result.channel != null)
            _detailRow('Channel', '${result.channel}'),
          if (result.channelWidth != null)
            _detailRow('Channel Width', '${result.channelWidth} MHz'),
          if (result.phyMaxSpeedMbps != null)
            _detailRow('Max PHY Speed', '${result.phyMaxSpeedMbps} Mbps'),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
