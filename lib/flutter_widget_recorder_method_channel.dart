import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_widget_recorder_platform_interface.dart';

/// An implementation of [FlutterWidgetRecorderPlatform] that uses method channels.
class MethodChannelFlutterWidgetRecorder extends FlutterWidgetRecorderPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_widget_recorder');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
