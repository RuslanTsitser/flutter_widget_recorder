import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_widget_recorder_method_channel.dart';

abstract class FlutterWidgetRecorderPlatform extends PlatformInterface {
  /// Constructs a FlutterWidgetRecorderPlatform.
  FlutterWidgetRecorderPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterWidgetRecorderPlatform _instance = MethodChannelFlutterWidgetRecorder();

  /// The default instance of [FlutterWidgetRecorderPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterWidgetRecorder].
  static FlutterWidgetRecorderPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterWidgetRecorderPlatform] when
  /// they register themselves.
  static set instance(FlutterWidgetRecorderPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
