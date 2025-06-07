import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'flutter_widget_recorder.dart';

/// Controller for recording widget
class WidgetRecorderController with ChangeNotifier {
  final FlutterWidgetRecorder _recorder;
  final Duration _frameInterval;

  WidgetRecorderController({
    required int targetFps,
  })  : _frameInterval = Duration(milliseconds: (1000 / targetFps).floor()),
        _recorder = FlutterWidgetRecorder();

  final GlobalKey repaintKey = GlobalKey();
  bool _isRecording = false;
  Timer? _timer;
  String? _path;

  bool get isRecording => _isRecording;
  String? get path => _path;

  /// Start recording.
  /// Pass devicePixelRatio explicitly here.
  Future<void> startRecording(
    String name, {
    required double pixelRatio,
  }) async {
    if (_isRecording) return;
    final ctx = repaintKey.currentContext;
    if (ctx == null) return;
    final size = ctx.size;
    if (size == null) return;

    final ok = await _recorder.startRecording(
      name: name,
      width: size.width.toInt(),
      height: size.height.toInt(),
      pixelRatio: pixelRatio,
    );
    if (ok) {
      _isRecording = true;
      _timer = Timer.periodic(_frameInterval, (_) => _captureFrame(pixelRatio));
      notifyListeners();
    }
  }

  /// Stop recording.
  Future<void> stopRecording() async {
    if (!_isRecording) return;
    _timer?.cancel();
    _isRecording = false;
    _path = await _recorder.stopRecording();
    notifyListeners();
  }

  /// Capture frame and send to native.
  Future<void> _captureFrame(double pixelRatio) async {
    try {
      final boundary = repaintKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (byteData == null) return;

      final pixels = byteData.buffer.asUint8List();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      await _recorder.pushFrame(
        frame: pixels,
        width: image.width,
        height: image.height,
        timestamp: timestamp,
      );
    } catch (e) {
      debugPrint('Error capturing frame: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_isRecording) stopRecording();
    super.dispose();
  }
}
