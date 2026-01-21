import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_http_speedtest_platform_interface.dart';

/// An implementation of [FlutterHttpSpeedtestPlatform] that uses method channels.
class MethodChannelFlutterHttpSpeedtest extends FlutterHttpSpeedtestPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_http_speedtest');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
