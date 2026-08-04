import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// appRepaintBoundaryKey wraps the whole navigated app (see main.dart's
// MaterialApp.builder) so pickColorFromApp can capture its current frame.
final GlobalKey appRepaintBoundaryKey = GlobalKey();

// pickColorFromApp captures a snapshot of the app's current frame and lets
// the user tap anywhere in it to sample that pixel's color -- an in-app
// "eyedropper". This can only sample what's currently visible somewhere in
// the app itself, unlike an OS-level eyedropper (which would need a native
// screen-capture package per platform, plus permissions like macOS's
// Screen Recording grant) -- that's a deliberate, much smaller scope.
//
// If a modal (e.g. a color-picker dialog) is covering the content the user
// wants to sample, close it before calling this so the capture shows what's
// underneath.
Future<Color?> pickColorFromApp(BuildContext context) async {
  final boundary = appRepaintBoundaryKey.currentContext?.findRenderObject()
      as RenderRepaintBoundary?;
  if (boundary == null) return null;

  final pixelRatio = MediaQuery.of(context).devicePixelRatio;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) return null;
  if (!context.mounted) return null;

  return Navigator.of(context, rootNavigator: true).push<Color>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => _EyedropperOverlay(image: image, bytes: bytes),
    ),
  );
}

class _EyedropperOverlay extends StatefulWidget {
  final ui.Image image;
  final ByteData bytes;
  const _EyedropperOverlay({required this.image, required this.bytes});

  @override
  State<_EyedropperOverlay> createState() => _EyedropperOverlayState();
}

class _EyedropperOverlayState extends State<_EyedropperOverlay> {
  Offset? _hoverPos;
  Color? _hoverColor;

  Color? _colorAt(Offset localPos, Size displaySize) {
    final img = widget.image;
    var x = (localPos.dx / displaySize.width * img.width).floor();
    var y = (localPos.dy / displaySize.height * img.height).floor();
    if (x < 0 || y < 0 || x >= img.width || y >= img.height) return null;
    var offset = (y * img.width + x) * 4;
    if (offset < 0 || offset + 3 >= widget.bytes.lengthInBytes) return null;
    var r = widget.bytes.getUint8(offset);
    var g = widget.bytes.getUint8(offset + 1);
    var b = widget.bytes.getUint8(offset + 2);
    var a = widget.bytes.getUint8(offset + 3);
    return Color.fromARGB(a, r, g, b);
  }

  @override
  Widget build(BuildContext context) {
    var displaySize = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: MouseRegion(
            onHover: (e) => setState(() {
              _hoverPos = e.localPosition;
              _hoverColor = _colorAt(e.localPosition, displaySize);
            }),
            child: GestureDetector(
              onTapUp: (d) => Navigator.of(context)
                  .pop(_colorAt(d.localPosition, displaySize)),
              child: SizedBox(
                width: displaySize.width,
                height: displaySize.height,
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: SizedBox(
                    width: widget.image.width.toDouble(),
                    height: widget.image.height.toDouble(),
                    child: RawImage(image: widget.image),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: 16,
          right: 56,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              "Tap anywhere in the app to sample its color",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: "Cancel",
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        if (_hoverColor != null && _hoverPos != null)
          Positioned(
            left: (_hoverPos!.dx + 20).clamp(0, displaySize.width - 150),
            top: (_hoverPos!.dy + 20).clamp(0, displaySize.height - 40),
            child: IgnorePointer(
              child: Container(
                width: 130,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _hoverColor,
                  border: Border.all(color: Colors.white, width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#${_hoverColor!.toARGB32().toRadixString(16).padLeft(8, '0')}',
                  style: TextStyle(
                    color: _hoverColor!.computeLuminance() > 0.5
                        ? Colors.black
                        : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
