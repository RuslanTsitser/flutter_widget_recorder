import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_recorder_example/main.dart' as app;
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('getPlatformVersion test', (WidgetTester tester) async {
    // Start the app
    app.main();
    await tester.pump();

    final textNoPath = find.byKey(const Key('no_path_text'));
    expect(textNoPath, findsOneWidget);

    // Find the start button
    final startButton = find.byKey(const Key('start_button'));
    expect(startButton, findsOneWidget);
    await tester.tap(startButton);
    await tester.pump();

    await Future.delayed(const Duration(seconds: 1));

    // Stop the recording
    final stopButton = find.byKey(const Key('stop_button'));
    expect(stopButton, findsOneWidget);
    await tester.tap(stopButton);
    await tester.pump();

    // Check the path
    final textPath = find.byKey(const Key('path_text'));
    expect(textPath, findsOneWidget);
    expect(textPath.evaluate().first.toString(), contains('example.mp4'));
  });
}
