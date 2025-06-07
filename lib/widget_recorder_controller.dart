import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'flutter_widget_recorder.dart';

/// Controller for recording widget
class WidgetRecorderController with ChangeNotifier {
  final FlutterWidgetRecorder recorder = FlutterWidgetRecorder();

  /// Constructor
  ///
  /// [targetFps] - target fps for recording
  ///
  WidgetRecorderController({
    required int targetFps,
  }) {
    _frameInterval = Duration(milliseconds: (1000 / targetFps).floor());
  }

  /// Frame interval for recording
  late final Duration _frameInterval;

  /// Repaint key for for widget
  final GlobalKey _repaintKey = GlobalKey();

  /// Repaint key for recording
  GlobalKey get repaintKey => _repaintKey;

  /// Is recording
  bool _isRecording = false;

  /// Is recording
  bool get isRecording => _isRecording;

  /// Timer for recording
  Timer? _timer;

  /// Path to the video
  String? _path;

  /// Path to the video
  String? get path => _path;

  /// Start recording
  Future<void> startRecording(String name) async {
    if (_isRecording) return;
    try {
      final size = _repaintKey.currentContext?.size;
      if (size == null) return;
      final ok = await recorder.startRecording(
        name: name,
        width: size.width.toInt(),
        height: size.height.toInt(),
      );

      if (ok == true) {
        _isRecording = true;
        _timer = Timer.periodic(_frameInterval, (_) => _captureFrame());
        notifyListeners();
      }
    } on PlatformException catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  /// Stop recording
  Future<void> stopRecording() async {
    if (!_isRecording) return;
    _timer?.cancel();
    _timer = null;
    _isRecording = false;
    try {
      _path = await recorder.stopRecording();
      debugPrint('Видео сохранено по пути: $_path');
    } on PlatformException catch (e) {
      debugPrint('Error stopping recording: $e');
    } finally {
      notifyListeners();
    }
  }

  /// Capture frame
  Future<void> _captureFrame() async {
    try {
      // 1. Get RenderRepaintBoundary by _repaintKey
      RenderRepaintBoundary boundary = _repaintKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary;
      // 2. Render to Image
      ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      // 3. Convert to ByteData in rawRgba format
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width;
      final height = image.height;
      image.dispose();
      if (byteData == null) return;

      // 4. Form arguments for MethodChannel
      final pixels = byteData.buffer.asUint8List();
      final timestampMs = DateTime.now().millisecondsSinceEpoch;

      // 5. Send to native
      await recorder.pushFrame(
        frame: pixels,
        width: width,
        height: height,
        timestamp: timestampMs,
      );
    } catch (e) {
      debugPrint('Error capturing frame: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_isRecording) {
      stopRecording();
    }
    super.dispose();
  }
}
