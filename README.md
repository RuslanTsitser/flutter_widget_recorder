# Flutter Widget Recorder

A Flutter plugin for recording widget content as video (H.264/MP4) or image sequences on iOS.

## Features

- Record any Flutter widget as a video (MP4, H.264 codec)
- Frame-accurate capture with custom resolution and pixel ratio
- Handles devicePixelRatio and pixel alignment for video codecs
- Automatic padding to meet iOS video codec requirements (multiples of 16)
- Error diagnostics and robust handling of edge cases

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_widget_recorder:
    git:
      url: <your-repo-url>
```

Then run:

```
flutter pub get
```

## Usage

Wrap the widget you want to record:

```dart
import 'package:flutter_widget_recorder/flutter_widget_recorder.dart';

Widget build(BuildContext context) {
  return WidgetRecorder(
    controller: _recorderController,
    child: YourWidget(),
  );
}
```

Start and stop recording:

```dart
final _recorderController = WidgetRecorderController();

// Start recording
await _recorderController.startRecording(
  name: 'my_video',
  width: widgetWidth,
  height: widgetHeight,
  pixelRatio: MediaQuery.devicePixelRatioOf(context),
);

// Push frames (usually handled automatically)
await _recorderController.pushFrame();

// Stop recording
final path = await _recorderController.stopRecording();
```

## iOS Notes

- **Pixel Alignment:** iOS H.264 video requires frame sizes to be multiples of 16. The plugin automatically pads frames as needed. Extra space is filled with black pixels.
- **Automatic Adjustment:** The widget automatically adjusts (pads) the recorded area to the nearest multiple of 16 pixels to ensure compatibility with the video codec. You do not need to manually align your widget size.
- **Black Borders:** If your widget size is not a multiple of 16, the output video will have black borders on the right and/or bottom.
- **Performance:** Recording at high resolutions or high frame rates may impact performance.

## Troubleshooting

- If you see errors about frame size or stride, ensure you are passing the correct width, height, and pixelRatio.
- If you see black borders, this is due to codec alignment requirements (see above).
- For more details, see the [CHANGELOG.md](CHANGELOG.md).

## License

MIT
