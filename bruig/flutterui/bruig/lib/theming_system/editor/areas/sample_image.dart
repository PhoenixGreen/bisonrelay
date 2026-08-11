import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// sample_image.dart draws the picture the Markdown area's image settings are
// previewed on.
//
// Drawn rather than bundled. An embed carries its own bytes, so a preview
// that goes through the real embed path -- which is the only way to be sure
// the settings are being seen doing what they will actually do -- needs
// actual image data, and shipping an asset for it would be a file in the
// repo whose only job is to be looked at once in a settings page.
//
// Async, because encoding a PNG is. It is done once and kept: the settings
// page rebuilds on every drag of every slider, and re-encoding an image for
// each frame of that would be absurd.

String? _cached;

/// sampleImageMarkdown is an embed of a small drawn image, ready to be put
/// into a preview's markdown, or null before it has been prepared.
String? get sampleImageMarkdown =>
    _cached == null ? null : "--embed[type=image/png,data=$_cached]--";

/// prepareSampleImage draws the sample once.
///
/// [seed] colours it, so the picture belongs to the theme it is previewed in
/// rather than being a stray block of grey.
Future<void> prepareSampleImage(Color seed) async {
  if (_cached != null) return;

  const width = 320.0;
  const height = 180.0;
  var recorder = ui.PictureRecorder();
  var canvas = Canvas(recorder);

  // A gradient with a few shapes on it: a flat colour would show the corner
  // radius and the border perfectly well and would say nothing about how a
  // photograph sits at 60% of the column.
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, width, height),
    Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(width, height),
        [seed, HSLColor.fromColor(seed).withLightness(0.25).toColor()],
      ),
  );
  var light = Paint()..color = Colors.white.withValues(alpha: 0.22);
  canvas.drawCircle(const Offset(74, 62), 38, light);
  canvas.drawRRect(
    RRect.fromLTRBR(150, 96, 286, 150, const Radius.circular(6)),
    light,
  );

  var image = await recorder.endRecording().toImage(
        width.round(),
        height.round(),
      );
  var bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) return;
  _cached = base64Encode(bytes.buffer.asUint8List());
}
