import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_widget_recorder_platform_interface.dart';

/// An implementation of [FlutterWidgetRecorderPlatform] that uses method channels.
class MethodChannelFlutterWidgetRecorder extends FlutterWidgetRecorderPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_widget_recorder');

  @override
  Future<bool> startRecording({
    required String name,
    required int width,
    required int height,
  }) async {
    const String methodName = 'startRecording';
    final Map<String, dynamic> args = {
      'name': name,
      'width': width,
      'height': height,
    };

    final bool? result =
        await methodChannel.invokeMethod<bool>(methodName, args);
    return result ?? false;
  }

  @override
  Future<void> pushFrame({
    required Uint8List frame,
    required int width,
    required int height,
    required int timestamp,
  }) async {
    final pixels = frame.buffer.asUint8List();
    const String methodName = 'pushFrame';
    final Map<String, dynamic> args = {
      'pixels': pixels,
      'width': width,
      'height': height,
      'timestampMs': timestamp,
    };
    await methodChannel.invokeMethod<void>(methodName, args);
  }

  @override
  Future<String?> stopRecording() async {
    const String methodName = 'stopRecording';
    final String? result = await methodChannel.invokeMethod<String>(methodName);
    return result;
  }
}
