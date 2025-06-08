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
  ///
  /// Adds padding to the widget to make it a multiple of 16.
  ///
  /// It is necessary for the video to be recorded correctly on iOS.
  const WidgetRecorderWrapper({
    super.key,
    required this.child,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: constraints.maxWidth ~/ 16 * 16,
            height: constraints.maxHeight ~/ 16 * 16,
            child: RepaintBoundary(
              key: controller.repaintKey,
              child: child,
            ),
          ),
        ],
      );
    });
  }
}
