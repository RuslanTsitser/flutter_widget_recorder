import 'dart:typed_data';

import 'flutter_widget_recorder_platform_interface.dart';

class FlutterWidgetRecorder {
  Future<bool> startRecording({
    required String name,
    required int width,
    required int height,
  }) {
    return FlutterWidgetRecorderPlatform.instance.startRecording(
      name: name,
      width: width,
      height: height,
    );
  }

  Future<void> pushFrame({
    required Uint8List frame,
    required int width,
    required int height,
    required int timestamp,
  }) {
    return FlutterWidgetRecorderPlatform.instance.pushFrame(
      frame: frame,
      width: width,
      height: height,
      timestamp: timestamp,
    );
  }

  Future<String?> stopRecording() {
    return FlutterWidgetRecorderPlatform.instance.stopRecording();
  }
}
