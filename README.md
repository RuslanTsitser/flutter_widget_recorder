# Flutter Widget Recorder

A Flutter plugin for recording widget content as video (H.264/MP4) or image sequences on iOS and Android.

## Features

- Record any Flutter widget as a video (MP4, H.264 codec)
- Frame-accurate capture with custom resolution and pixel ratio
- Handles devicePixelRatio and pixel alignment for video codecs
- Automatic padding to meet video codec requirements (multiples of 16)
- Error diagnostics and robust handling of edge cases
- Cross-platform support (iOS and Android)

## Limitations

- The plugin can only record Flutter-rendered widgets

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_widget_recorder: ^0.1.0
```

Then run:

```bash
flutter pub get
```

## Usage

First, create a controller in your StatefulWidget:

```dart
class _MyWidgetState extends State<MyWidget> {
  final WidgetRecorderController _controller = WidgetRecorderController(
    targetFps: 30, // Optional: Set target FPS
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  // ... rest of your widget code
}
```

Wrap the widget you want to record:

```dart
Widget build(BuildContext context) {
  return WidgetRecorderWrapper(
    controller: _controller,
    child: YourWidget(),
  );
}
```

Start and stop recording:

```dart
// Start recording
await _controller.startRecording(
  'my_video',
  pixelRatio: MediaQuery.devicePixelRatioOf(context),
);

// Stop recording
await _controller.stopRecording();

// Get the path to the recorded video
final videoPath = _controller.path;
```

## Example

Check out the [example](example/lib/main.dart) for a complete implementation that includes:

- Recording a widget with animation
- Start/Stop recording controls
- Sharing the recorded video
- Display of the recording path

## Platform Notes

### iOS

- **Pixel Alignment:** iOS H.264 video requires frame sizes to be multiples of 16. The plugin automatically pads frames as needed. Extra space is filled with black pixels.
- **Automatic Adjustment:** The widget automatically adjusts (pads) the recorded area to the nearest multiple of 16 pixels to ensure compatibility with the video codec. You do not need to manually align your widget size.
- **Padding:** If your widget size is not a multiple of 16, the output video will have paddings on the right and/or bottom.

### Android

- **Pixel Alignment:** Similar to iOS, Android H.264 video requires frame sizes to be multiples of 16. The plugin handles this automatically.

### Performance

- Recording at high resolutions or high frame rates may impact performance on both platforms.
- Consider using lower resolutions or frame rates for better performance.

## Troubleshooting

- If you see errors about frame size or stride, ensure you are passing the correct width, height, and pixelRatio.
- If you see black borders, this is due to codec alignment requirements (see above).
- For more details, see the [CHANGELOG.md](CHANGELOG.md).

## License

MIT
