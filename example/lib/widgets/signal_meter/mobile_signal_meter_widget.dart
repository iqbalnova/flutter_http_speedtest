// lib/widgets/signal_meter/mobile_signal_meter_widget.dart
import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_network_diagnostics/flutter_network_diagnostics.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

class MobileSignalMeterWidget extends StatefulWidget {
  final ValueNotifier<String>? networkNameNotifier;

  const MobileSignalMeterWidget({super.key, this.networkNameNotifier});

  @override
  State<MobileSignalMeterWidget> createState() =>
      _MobileSignalMeterWidgetState();
}

class _MobileSignalMeterWidgetState extends State<MobileSignalMeterWidget> {
  final _service = FlutterNetworkDiagnosticsService();

  // Reactive state - NO setState!
  final _signalStreamController =
      StreamController<MobileSignalInfo>.broadcast();
  final _permissionStateNotifier = ValueNotifier<_PermissionState>(
    _PermissionState.checking,
  );
  final _signalHistoryNotifier = ValueNotifier<List<FlSpot>>([]);

  StreamSubscription<MobileSignalInfo>? _subscription;
  int _timeCounter = 0;
  bool _isRequestingPermission = false;

  @override
  void initState() {
    super.initState();
    _initializeMonitoring();
  }

  Future<void> _initializeMonitoring() async {
    if (_isRequestingPermission) return;
    _isRequestingPermission = true;

    try {
      final status = await Permission.phone.status;

      if (status.isGranted) {
        _permissionStateNotifier.value = _PermissionState.granted;
        _startMonitoring();
      } else if (status.isDenied) {
        await Future.delayed(const Duration(milliseconds: 300));

        final result = await Permission.phone.request();
        _permissionStateNotifier.value = result.isGranted
            ? _PermissionState.granted
            : _PermissionState.denied;
        if (result.isGranted) _startMonitoring();
      } else if (status.isPermanentlyDenied) {
        _permissionStateNotifier.value = _PermissionState.permanentlyDenied;
      } else {
        _permissionStateNotifier.value = _PermissionState.denied;
      }
    } catch (e) {
      debugPrint('Error initializing monitoring: $e');
      _permissionStateNotifier.value = _PermissionState.error;
    } finally {
      _isRequestingPermission = false;
    }
  }

  void _startMonitoring() {
    _subscription?.cancel();

    _subscription = _service
        .getMobileSignalStream(intervalMs: 1000)
        .listen(
          (info) {
            _signalStreamController.add(info);
            _updateSignalHistory(info.signalStrength?.toDouble() ?? -110);

            // Update network name in parent
            _updateNetworkName(info);
          },
          onError: (e) {
            debugPrint('Error in mobile signal stream: $e');
            _permissionStateNotifier.value = _PermissionState.error;
          },
        );
  }

  void _updateNetworkName(MobileSignalInfo info) {
    if (widget.networkNameNotifier != null) {
      if (!info.isConnected) {
        widget.networkNameNotifier!.value = 'Seluler (Tidak Terhubung)';
      } else {
        final operator = info.operatorName ?? 'Seluler';
        final network = info.networkGeneration.label;
        widget.networkNameNotifier!.value = '$operator ($network)';
      }
    }
  }

  void _updateSignalHistory(double rssi) {
    final history = List<FlSpot>.from(_signalHistoryNotifier.value);
    history.add(FlSpot(_timeCounter.toDouble(), rssi));
    _timeCounter++;

    if (history.length > 60) {
      history.removeAt(0);
      for (int i = 0; i < history.length; i++) {
        history[i] = FlSpot(i.toDouble(), history[i].y);
      }
      _timeCounter = history.length;
    }

    _signalHistoryNotifier.value = history;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _signalStreamController.close();
    _permissionStateNotifier.dispose();
    _signalHistoryNotifier.dispose();
    super.dispose();
  }

  Color _getSignalColor(int rssi) {
    if (rssi >= -80) return Colors.green;
    if (rssi >= -90) return Colors.lightGreen;
    if (rssi >= -100) return Colors.orange;
    if (rssi >= -110) return Colors.deepOrange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_PermissionState>(
      valueListenable: _permissionStateNotifier,
      builder: (context, state, _) {
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

        // Early returns for error states
        if (state == _PermissionState.denied) {
          scheduleNetworkNameUpdate('Seluler (Izin Diperlukan)');

          return _ErrorStateWidget(
            icon: Icons.phonelink_lock,
            message:
                'Izin telepon diperlukan untuk membaca informasi sinyal seluler',
            color: Colors.orange,
            onRetry: () async {
              if (_isRequestingPermission) return;
              await _initializeMonitoring();
            },
          );
        }

        if (state == _PermissionState.permanentlyDenied) {
          scheduleNetworkNameUpdate('Seluler (Izin Ditolak)');

          return const _ErrorStateWidget(
            icon: Icons.phonelink_lock,
            message: 'Izin telepon ditolak permanen. Aktifkan di pengaturan.',
            color: Colors.orange,
            showSettings: true,
          );
        }

        if (state == _PermissionState.error) {
          scheduleNetworkNameUpdate('Seluler (Error)');

          return _ErrorStateWidget(
            icon: Icons.error_outline,
            message: 'Terjadi kesalahan saat membaca sinyal seluler',
            color: Colors.red,
            onRetry: _startMonitoring,
          );
        }

        if (state == _PermissionState.checking) {
          scheduleNetworkNameUpdate('Memeriksa Seluler...');

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

        // Permission granted - stream signal data
        return StreamBuilder<MobileSignalInfo>(
          stream: _signalStreamController.stream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              scheduleNetworkNameUpdate('Menghubungkan Seluler...');

              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Menghubungkan ke monitor sinyal seluler...'),
                  ],
                ),
              );
            }

            final info = snapshot.data!;

            if (!info.isConnected) {
              scheduleNetworkNameUpdate('Seluler (Tidak Terhubung)');

              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.signal_cellular_off,
                      size: 64,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Tidak ada sinyal seluler',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            final rssi = info.signalStrength ?? -110;
            final signalColor = _getSignalColor(rssi);

            return _MobileSignalContent(
              network: info.networkGeneration.label,
              operatorName: info.operatorName ?? '-',
              rssi: rssi,
              signalColor: signalColor,
              signalHistoryNotifier: _signalHistoryNotifier,
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// PURE WIDGETS - No State
// ============================================================================

class _MobileSignalContent extends StatelessWidget {
  final String network;
  final String operatorName;
  final int rssi;
  final Color signalColor;
  final ValueNotifier<List<FlSpot>> signalHistoryNotifier;

  const _MobileSignalContent({
    required this.network,
    required this.operatorName,
    required this.rssi,
    required this.signalColor,
    required this.signalHistoryNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 16),

          // Top Stats Row
          _MobileHeaderCard(
            network: network,
            operatorName: operatorName,
            rssi: rssi,
            signalColor: signalColor,
          ),

          const SizedBox(height: 24),

          // Speedometer
          SizedBox(
            height: 250,
            child: _MobileSpeedometer(rssi: rssi.toDouble()),
          ),

          const SizedBox(height: 16),

          // Info Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tentang sinyal seluler',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[900],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sinyal seluler dipengaruhi jarak BTS, kondisi indoor, dan interferensi.',
                        style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Signal Chart
          _SignalChart(signalHistoryNotifier: signalHistoryNotifier),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _MobileHeaderCard extends StatelessWidget {
  final String network;
  final String operatorName;
  final int rssi;
  final Color signalColor;

  const _MobileHeaderCard({
    required this.network,
    required this.operatorName,
    required this.rssi,
    required this.signalColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  network,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(operatorName, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
          Text(
            '$rssi dBm',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: signalColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileSpeedometer extends StatelessWidget {
  final double rssi;

  const _MobileSpeedometer({required this.rssi});

  Color _getSignalColor(int rssi) {
    if (rssi >= -80) return Colors.green;
    if (rssi >= -90) return Colors.lightGreen;
    if (rssi >= -100) return Colors.orange;
    if (rssi >= -110) return Colors.deepOrange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return SfRadialGauge(
      axes: [
        RadialAxis(
          minimum: -120,
          maximum: -40,
          startAngle: 130,
          endAngle: 50,
          radiusFactor: 1,
          interval: 20,
          showLabels: true,
          showTicks: true,
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
              startValue: -120,
              endValue: rssi.clamp(-120, -40),
              startWidth: 0.12,
              endWidth: 0.12,
              sizeUnit: GaugeSizeUnit.factor,
              color: Colors.blue,
            ),
          ],
          annotations: [
            GaugeAnnotation(
              angle: 90,
              positionFactor: 0.1,
              widget: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.signal_cellular_alt,
                    size: 36,
                    color: _getSignalColor(rssi.toInt()),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    rssi.toInt().toString(),
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: _getSignalColor(rssi.toInt()),
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
          const Text(
            'Stabilitas sinyal',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: ValueListenableBuilder<List<FlSpot>>(
              valueListenable: signalHistoryNotifier,
              builder: (context, history, _) {
                if (history.isEmpty) {
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
                        spots: history,
                        isCurved: true,
                        color: Colors.blue,
                        barWidth: 2,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              Colors.blue.withValues(alpha: .3),
                              Colors.blue.withValues(alpha: .0),
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

class _ErrorStateWidget extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final bool showSettings;
  final VoidCallback? onRetry;

  const _ErrorStateWidget({
    required this.icon,
    required this.message,
    required this.color,
    this.showSettings = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: color),
            ),
            const SizedBox(height: 24),
            if (showSettings)
              ElevatedButton.icon(
                onPressed: () async {
                  await openAppSettings();
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
// ENUMS
// ============================================================================

enum _PermissionState { checking, granted, denied, permanentlyDenied, error }
