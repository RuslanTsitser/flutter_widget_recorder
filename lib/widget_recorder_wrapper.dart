import 'package:flutter/material.dart';

import 'widget_recorder_controller.dart';

/// Wrapper for recording widget
class WidgetRecorderWrapper extends StatelessWidget {
  /// Widget to record
  final Widget child;

  /// Controller for recording
  final WidgetRecorderController controller;

  /// Constructor
  ///
  /// [child] - widget to record
  /// [controller] - controller for recording
  const WidgetRecorderWrapper({
    super.key,
    required this.child,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: controller.repaintKey,
      child: child,
    );
  }
}
