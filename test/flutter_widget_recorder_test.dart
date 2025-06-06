import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_recorder/flutter_widget_recorder.dart';
import 'package:flutter_widget_recorder/flutter_widget_recorder_platform_interface.dart';
import 'package:flutter_widget_recorder/flutter_widget_recorder_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterWidgetRecorderPlatform
    with MockPlatformInterfaceMixin
    implements FlutterWidgetRecorderPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterWidgetRecorderPlatform initialPlatform = FlutterWidgetRecorderPlatform.instance;

  test('$MethodChannelFlutterWidgetRecorder is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterWidgetRecorder>());
  });

  test('getPlatformVersion', () async {
    FlutterWidgetRecorder flutterWidgetRecorderPlugin = FlutterWidgetRecorder();
    MockFlutterWidgetRecorderPlatform fakePlatform = MockFlutterWidgetRecorderPlatform();
    FlutterWidgetRecorderPlatform.instance = fakePlatform;

    expect(await flutterWidgetRecorderPlugin.getPlatformVersion(), '42');
  });
}
