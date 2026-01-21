import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_http_speedtest_method_channel.dart';

abstract class FlutterHttpSpeedtestPlatform extends PlatformInterface {
  /// Constructs a FlutterHttpSpeedtestPlatform.
  FlutterHttpSpeedtestPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterHttpSpeedtestPlatform _instance = MethodChannelFlutterHttpSpeedtest();

  /// The default instance of [FlutterHttpSpeedtestPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterHttpSpeedtest].
  static FlutterHttpSpeedtestPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterHttpSpeedtestPlatform] when
  /// they register themselves.
  static set instance(FlutterHttpSpeedtestPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
