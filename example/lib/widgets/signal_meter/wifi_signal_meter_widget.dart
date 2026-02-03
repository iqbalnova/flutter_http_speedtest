// lib/widgets/signal_meter/wifi_signal_meter_widget.dart
import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_network_diagnostics/flutter_network_diagnostics.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

class WifiSignalMeterWidget extends StatefulWidget {
  final ValueNotifier<String>? networkNameNotifier;

  const WifiSignalMeterWidget({super.key, this.networkNameNotifier});

  @override
  State<WifiSignalMeterWidget> createState() => _WifiSignalMeterWidgetState();
}

class _WifiSignalMeterWidgetState extends State<WifiSignalMeterWidget> {
  final _service = FlutterNetworkDiagnosticsService();

  // Reactive state management - no setState!
  final _signalStreamController = StreamController<WifiSignalInfo>.broadcast();
  final _permissionStateNotifier = ValueNotifier<PermissionState>(
    PermissionState.checking,
  );
  final _signalHistoryNotifier = ValueNotifier<List<FlSpot>>([]);

  StreamSubscription<WifiSignalInfo>? _signalSubscription;
  int _timeCounter = 0;

  // Flag to prevent simultaneous permission requests
  bool _isRequestingPermission = false;

  @override
  void initState() {
    super.initState();
    _initializeMonitoring();
  }

  // Initialize monitoring - async but non-blocking
  Future<void> _initializeMonitoring() async {
    // Prevent simultaneous requests
    if (_isRequestingPermission) return;
    _isRequestingPermission = true;

    try {
      final status = await Permission.location.status;

      if (status.isGranted) {
        _permissionStateNotifier.value = PermissionState.granted;
        _startMonitoring();
      } else if (status.isDenied) {
        // Wait a bit to avoid conflicts with system permission dialogs
        await Future.delayed(const Duration(milliseconds: 300));

        final result = await Permission.location.request();
        if (result.isGranted) {
          _permissionStateNotifier.value = PermissionState.granted;
          _startMonitoring();
        } else {
          _permissionStateNotifier.value = PermissionState.denied;
        }
      } else if (status.isPermanentlyDenied) {
        _permissionStateNotifier.value = PermissionState.permanentlyDenied;
      } else {
        // Handle other states (restricted, limited, etc.)
        _permissionStateNotifier.value = PermissionState.denied;
      }
    } catch (e) {
      debugPrint('Error initializing monitoring: $e');
      _permissionStateNotifier.value = PermissionState.error;
    } finally {
      _isRequestingPermission = false;
    }
  }

  void _startMonitoring() {
    // Cancel existing subscription if any
    _signalSubscription?.cancel();

    _signalSubscription = _service
        .getWifiSignalStream(intervalMs: 1000)
        .listen(
          (info) {
            // Add to broadcast stream - no setState!
            _signalStreamController.add(info);
            _updateSignalHistory(info.rssi?.toDouble() ?? -100);

            // Update network name in parent
            _updateNetworkName(info);
          },
          onError: (error) {
            if (error is UnsupportedError) {
              _permissionStateNotifier.value = PermissionState.unsupported;
            } else {
              _permissionStateNotifier.value = PermissionState.error;
            }
          },
        );
  }

  void _updateNetworkName(WifiSignalInfo info) {
    if (widget.networkNameNotifier != null) {
      final ssid = info.ssid ?? 'WiFi';
      final band = info.band.label;
      widget.networkNameNotifier!.value = '$ssid ($band)';
    }
  }

  void _updateSignalHistory(double rssi) {
    final currentHistory = List<FlSpot>.from(_signalHistoryNotifier.value);
    currentHistory.add(FlSpot(_timeCounter.toDouble(), rssi));
    _timeCounter++;

    // Keep only last 60 points
    if (currentHistory.length > 60) {
      currentHistory.removeAt(0);
      // Adjust x values
      for (int i = 0; i < currentHistory.length; i++) {
        currentHistory[i] = FlSpot(i.toDouble(), currentHistory[i].y);
      }
      _timeCounter = currentHistory.length;
    }

    // Update notifier - triggers rebuild only for chart widget
    _signalHistoryNotifier.value = currentHistory;
  }

  @override
  void dispose() {
    _signalSubscription?.cancel();
    _signalStreamController.close();
    _permissionStateNotifier.dispose();
    _signalHistoryNotifier.dispose();
    super.dispose();
  }

  Color _getSignalColor(int? rssi) {
    if (rssi == null) return Colors.grey;
    if (rssi >= -50) return Colors.green;
    if (rssi >= -60) return Colors.lightGreen;
    if (rssi >= -70) return Colors.orange;
    if (rssi >= -80) return Colors.deepOrange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    // First check permission state - lightweight ValueListenableBuilder
    return ValueListenableBuilder<PermissionState>(
      valueListenable: _permissionStateNotifier,
      builder: (context, permissionState, _) {
        // Schedule network name updates after build
        void scheduleNetworkNameUpdate(String name) {
          if (widget.networkNameNotifier != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                widget.networkNameNotifier!.value = name;
              }
            });
          }
        }

        // Early return for error states - no unnecessary rebuilds
        if (permissionState == PermissionState.denied) {
          scheduleNetworkNameUpdate('WiFi (Izin Diperlukan)');

          return _buildErrorState(
            icon: Icons.location_off,
            message: 'Izin lokasi diperlukan untuk membaca informasi WiFi',
            color: Colors.orange,
            showSettings: false,
            onRetry: () async {
              // Prevent double tap
              if (_isRequestingPermission) return;
              await _initializeMonitoring();
            },
          );
        }

        if (permissionState == PermissionState.permanentlyDenied) {
          scheduleNetworkNameUpdate('WiFi (Izin Ditolak)');

          return _buildErrorState(
            icon: Icons.location_off,
            message: 'Izin lokasi ditolak permanen. Aktifkan di pengaturan.',
            color: Colors.orange,
            showSettings: true,
          );
        }

        if (permissionState == PermissionState.unsupported) {
          scheduleNetworkNameUpdate('WiFi (Tidak Didukung)');

          return _buildErrorState(
            icon: Icons.error_outline,
            message: 'Tidak didukung di platform ini',
            color: Colors.red,
          );
        }

        if (permissionState == PermissionState.error) {
          scheduleNetworkNameUpdate('WiFi (Error)');

          return _buildErrorState(
            icon: Icons.error_outline,
            message: 'Terjadi kesalahan saat membaca sinyal',
            color: Colors.red,
            onRetry: _startMonitoring,
          );
        }

        if (permissionState == PermissionState.checking) {
          scheduleNetworkNameUpdate('Memeriksa WiFi...');

          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Memeriksa izin...'),
              ],
            ),
          );
        }

        // Permission granted - use StreamBuilder for signal data
        return StreamBuilder<WifiSignalInfo>(
          stream: _signalStreamController.stream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              scheduleNetworkNameUpdate('Menghubungkan WiFi...');

              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Menghubungkan ke monitor sinyal WiFi...'),
                  ],
                ),
              );
            }

            final signalInfo = snapshot.data!;
            final signalColor = _getSignalColor(signalInfo.rssi);

            return _buildSignalContent(signalInfo, signalColor);
          },
        );
      },
    );
  }

  Widget _buildSignalContent(WifiSignalInfo signalInfo, Color signalColor) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 16),

          // Top Stats Row - pure widget, no state
          _TopStatsRow(
            frequency: signalInfo.band.label,
            signal: '${signalInfo.rssi ?? 'N/A'} dBm',
            phySpeed: '${signalInfo.linkSpeed ?? 'N/A'} Mbps',
            signalColor: signalColor,
          ),

          const SizedBox(height: 24),

          // Speedometer Gauge - pure widget
          SizedBox(
            height: 250,
            child: _SignalSpeedometer(
              rssi: signalInfo.rssi?.toDouble() ?? -100,
              signalColor: signalColor,
            ),
          ),

          const SizedBox(height: 16),

          // Tips Card - static widget
          const _TipsCard(),

          const SizedBox(height: 24),

          // Signal Stability Chart - uses ValueListenableBuilder
          _SignalChart(signalHistoryNotifier: _signalHistoryNotifier),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildErrorState({
    required IconData icon,
    required String message,
    required Color color,
    bool showSettings = false,
    VoidCallback? onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(fontSize: 16, color: color),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (showSettings)
              ElevatedButton.icon(
                onPressed: () async {
                  await openAppSettings();
                  // After returning from settings, check permission again
                  if (mounted) {
                    await Future.delayed(const Duration(milliseconds: 500));
                    _initializeMonitoring();
                  }
                },
                icon: const Icon(Icons.settings),
                label: const Text('Buka Pengaturan'),
              ),
            if (onRetry != null)
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Coba Lagi'),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// PURE WIDGETS - No State Management
// ============================================================================

class _TopStatsRow extends StatelessWidget {
  final String frequency;
  final String signal;
  final String phySpeed;
  final Color signalColor;

  const _TopStatsRow({
    required this.frequency,
    required this.signal,
    required this.phySpeed,
    required this.signalColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatCard(
            label: 'Frekuensi',
            value: frequency,
            color: Colors.grey[700]!,
          ),
          _StatCard(label: 'Sinyal', value: signal, color: signalColor),
          _StatCard(
            label: 'PHY Speed',
            value: phySpeed,
            color: Colors.grey[700]!,
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _SignalSpeedometer extends StatelessWidget {
  final double rssi;
  final Color signalColor;

  const _SignalSpeedometer({required this.rssi, required this.signalColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: SfRadialGauge(
        axes: [
          RadialAxis(
            minimum: -100,
            maximum: 0,
            startAngle: 130,
            endAngle: 50,
            radiusFactor: 1,
            showLabels: true,
            showTicks: true,
            interval: 20,
            axisLabelStyle: const GaugeTextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
            majorTickStyle: const MajorTickStyle(
              length: 8,
              thickness: 2,
              color: Colors.grey,
            ),
            minorTickStyle: const MinorTickStyle(
              length: 4,
              thickness: 1,
              color: Colors.grey,
            ),
            axisLineStyle: const AxisLineStyle(
              thickness: 0.12,
              thicknessUnit: GaugeSizeUnit.factor,
              color: Color(0xFFEDEDED),
            ),
            ranges: [
              GaugeRange(
                startValue: -100,
                endValue: rssi.clamp(-100, 0),
                startWidth: 0.12,
                endWidth: 0.12,
                sizeUnit: GaugeSizeUnit.factor,
                color: const Color(0xFFB14BD6),
              ),
            ],
            annotations: [
              GaugeAnnotation(
                angle: 90,
                positionFactor: 0.1,
                widget: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi, size: 36, color: signalColor),
                    const SizedBox(height: 8),
                    Text(
                      '${rssi.toInt()}',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: signalColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'dBm',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline, color: Colors.purple[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tips penempatan wifi',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.purple[900],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Coba mendekati router atau gunakan wifi 5GHz untuk sinyal lebih stabil',
                  style: TextStyle(fontSize: 12, color: Colors.purple[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalChart extends StatelessWidget {
  final ValueNotifier<List<FlSpot>> signalHistoryNotifier;

  const _SignalChart({required this.signalHistoryNotifier});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Stabilitas sinyal',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: ValueListenableBuilder<List<FlSpot>>(
              valueListenable: signalHistoryNotifier,
              builder: (context, signalHistory, _) {
                if (signalHistory.isEmpty) {
                  return Center(
                    child: Text(
                      'Mengumpulkan data...',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  );
                }

                return LineChart(
                  LineChartData(
                    minY: -100,
                    maxY: -30,
                    lineBarsData: [
                      LineChartBarData(
                        spots: signalHistory,
                        isCurved: true,
                        color: Colors.purple,
                        barWidth: 2,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              Colors.purple.withValues(alpha: .3),
                              Colors.purple.withValues(alpha: .0),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              value.toInt().toString(),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 15,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              value.toInt().toString(),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
                            );
                          },
                        ),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: 10,
                      getDrawingHorizontalLine: (value) {
                        return FlLine(color: Colors.grey[300], strokeWidth: 1);
                      },
                    ),
                    borderData: FlBorderData(show: false),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PERMISSION STATE ENUM
// ============================================================================

enum PermissionState {
  checking,
  granted,
  denied,
  permanentlyDenied,
  unsupported,
  error,
}
