// lib/pages/signal_monitor_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_http_speedtest_example/widgets/signal_meter/mobile_signal_meter_widget.dart';
import 'package:flutter_http_speedtest_example/widgets/signal_meter/wifi_signal_meter_widget.dart';
import 'package:permission_handler/permission_handler.dart';

class SignalMonitorPage extends StatefulWidget {
  const SignalMonitorPage({super.key});

  @override
  State<SignalMonitorPage> createState() => _SignalMonitorPageState();
}

class _SignalMonitorPageState extends State<SignalMonitorPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Network name notifiers for each tab
  final _wifiNetworkNameNotifier = ValueNotifier<String>('WiFi');
  final _mobileNetworkNameNotifier = ValueNotifier<String>('Seluler');
  final _currentNetworkNameNotifier = ValueNotifier<String>('WiFi');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Listen to tab changes to update current network name
    _tabController.addListener(_onTabChanged);

    // Listen to network name changes from child widgets
    _wifiNetworkNameNotifier.addListener(_onWifiNetworkNameChanged);
    _mobileNetworkNameNotifier.addListener(_onMobileNetworkNameChanged);

    // Request permissions asynchronously - don't wait for result
    // Individual widgets will handle permission states
    _requestPermissionsAsync();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      // Update current network name based on active tab
      if (_tabController.index == 0) {
        _currentNetworkNameNotifier.value = _wifiNetworkNameNotifier.value;
      } else {
        _currentNetworkNameNotifier.value = _mobileNetworkNameNotifier.value;
      }
    }
  }

  void _onWifiNetworkNameChanged() {
    // Update current network name if WiFi tab is active
    if (_tabController.index == 0) {
      _currentNetworkNameNotifier.value = _wifiNetworkNameNotifier.value;
    }
  }

  void _onMobileNetworkNameChanged() {
    // Update current network name if Mobile tab is active
    if (_tabController.index == 1) {
      _currentNetworkNameNotifier.value = _mobileNetworkNameNotifier.value;
    }
  }

  // Fire and forget - no setState needed
  void _requestPermissionsAsync() {
    [Permission.location, Permission.phone].request();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _wifiNetworkNameNotifier.removeListener(_onWifiNetworkNameChanged);
    _mobileNetworkNameNotifier.removeListener(_onMobileNetworkNameChanged);
    _tabController.dispose();
    _wifiNetworkNameNotifier.dispose();
    _mobileNetworkNameNotifier.dispose();
    _currentNetworkNameNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(child: _buildTabBarView()),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: ValueListenableBuilder<String>(
        valueListenable: _currentNetworkNameNotifier,
        builder: (context, networkName, _) {
          return Text(networkName, style: const TextStyle(fontSize: 14));
        },
      ),
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.help_outline),
          onPressed: _showHelpDialog,
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.purple,
        unselectedLabelColor: Colors.grey,
        indicatorColor: Colors.purple,
        tabs: const [
          Tab(text: 'WiFi'),
          Tab(text: 'Seluler'),
        ],
      ),
    );
  }

  Widget _buildTabBarView() {
    return TabBarView(
      controller: _tabController,
      physics: const NeverScrollableScrollPhysics(), // Prevent swipe
      children: [
        WifiSignalMeterWidget(networkNameNotifier: _wifiNetworkNameNotifier),
        MobileSignalMeterWidget(
          networkNameNotifier: _mobileNetworkNameNotifier,
        ),
      ],
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tentang Signal Monitor'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Monitor sinyal WiFi dan seluler secara real-time.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text('WiFi:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text('• RSSI: -30 dBm (sangat baik) sampai -100 dBm (buruk)'),
              Text('• Frekuensi: 2.4 GHz atau 5 GHz'),
              Text('• PHY Speed: Kecepatan maksimum koneksi'),
              SizedBox(height: 12),
              Text('Seluler:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text('• RSRP: -80 dBm (baik) sampai -120 dBm (buruk)'),
              Text('• Teknologi: 2G, 3G, 4G, 5G'),
              Text('• Operator: Nama provider seluler'),
              SizedBox(height: 12),
              Text('Tips:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text(
                '• Semakin tinggi nilai dBm (mendekati 0), semakin baik sinyalnya',
              ),
              Text('• Gunakan WiFi 5 GHz untuk kecepatan lebih tinggi'),
              Text('• Hindari penghalang fisik untuk sinyal optimal'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }
}
