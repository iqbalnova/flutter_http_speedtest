import 'package:flutter/material.dart';
import 'package:flutter_http_speedtest_example/screens/lan_scanner_screen.dart';
import 'package:flutter_http_speedtest_example/screens/wifi_info_page.dart';
import 'package:flutter_http_speedtest_example/screens/signal_monitor_page.dart';

class FeatureItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  FeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

class FeatureGrid extends StatelessWidget {
  const FeatureGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      FeatureItem(
        icon: Icons.network_cell,
        title: 'Real-Time Signal Meter',
        subtitle: 'Pantau kekuatan sinyal',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SignalMonitorPage()),
          );
        },
      ),
      FeatureItem(
        icon: Icons.wifi,
        title: 'Informasi WiFi',
        subtitle: 'Detail WiFi yang digunakan',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const WifiInfoPage()),
          );
        },
      ),
      FeatureItem(
        icon: Icons.analytics,
        title: 'Analisis Kekuatan Wifi',
        subtitle: 'Cek kualitas Wifi',
        onTap: () {},
      ),
      FeatureItem(
        icon: Icons.radar,
        title: 'LAN Scan',
        subtitle: 'Pindai perangkat di jaringan',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LanScannerScreen()),
          );
        },
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.9,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _FeatureCard(item: items[index]);
      },
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final FeatureItem item;

  const _FeatureCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ICON + ARROW (Fixed height)
            SizedBox(
              height: 42,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _GradientIcon(icon: item.icon),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey.shade400,
                    size: 20,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // CONTENT AREA (Flexible with constraints)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // TITLE (Flexible with proper constraints)
                  Flexible(
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),

                  const SizedBox(height: 4),

                  // SUBTITLE (Flexible with proper constraints)
                  Flexible(
                    child: Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientIcon extends StatelessWidget {
  final IconData icon;

  const _GradientIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [Color(0xFF8F5CFF), Color(0xFF3EC6FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}
