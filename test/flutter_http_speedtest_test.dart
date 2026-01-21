// import 'package:flutter_test/flutter_test.dart';
// import 'package:flutter_http_speedtest/flutter_http_speedtest.dart';
// import 'package:flutter_http_speedtest/flutter_http_speedtest_platform_interface.dart';
// import 'package:flutter_http_speedtest/flutter_http_speedtest_method_channel.dart';
// import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// class MockFlutterHttpSpeedtestPlatform
//     with MockPlatformInterfaceMixin
//     implements FlutterHttpSpeedtestPlatform {

//   @override
//   Future<String?> getPlatformVersion() => Future.value('42');
// }

// void main() {
//   final FlutterHttpSpeedtestPlatform initialPlatform = FlutterHttpSpeedtestPlatform.instance;

//   test('$MethodChannelFlutterHttpSpeedtest is the default instance', () {
//     expect(initialPlatform, isInstanceOf<MethodChannelFlutterHttpSpeedtest>());
//   });

//   test('getPlatformVersion', () async {
//     FlutterHttpSpeedtest flutterHttpSpeedtestPlugin = FlutterHttpSpeedtest();
//     MockFlutterHttpSpeedtestPlatform fakePlatform = MockFlutterHttpSpeedtestPlatform();
//     FlutterHttpSpeedtestPlatform.instance = fakePlatform;

//     expect(await flutterHttpSpeedtestPlugin.getPlatformVersion(), '42');
//   });
// }
