import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_recorder/flutter_widget_recorder_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelFlutterWidgetRecorder platform =
      MethodChannelFlutterWidgetRecorder();
  const MethodChannel channel = MethodChannel('flutter_widget_recorder');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'startRecording':
            return true;
          case 'stopRecording':
            return 'hello';
          case 'pushFrame':
            return null;
          default:
            throw PlatformException(
              code: 'unimplemented',
              message: '${methodCall.method} not implemented',
            );
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('startRecording', () async {
    expect(
      await platform.startRecording(
        name: 'test',
        width: 100,
        height: 100,
        pixelRatio: 1.0,
      ),
      true,
    );
  });

  test('stopRecording', () async {
    expect(await platform.stopRecording(), 'hello');
  });

  test('pushFrame', () async {
    await platform.pushFrame(
      frame: Uint8List(0),
      width: 100,
      height: 100,
      timestamp: 0,
    );
  });
}
