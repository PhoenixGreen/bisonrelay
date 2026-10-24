import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/svg_import.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_vector_crop_test.dart is a drawing trimmed at its edges.
//
// The case it is for is a logo: the mark wanted without the name beside it,
// while the drawing stays a reference to its file. Its view box could not do
// that -- it is the drawing's own space, rewritten whenever the drawing is
// taken apart, and a drawing nobody had taken apart never read it at all.

const _red = Color(0xFFFF0000);
const _blue = Color(0xFF0000FF);
const _white = Color(0xFFFFFFFF);

/// _halves is a 200x100 drawing, red on the left and blue on the right.
VectorElement _halves({ImageCrop crop = const ImageCrop()}) {
  var svg = importSvg(
      '<svg viewBox="0 0 200 100" xmlns="http://www.w3.org/2000/svg">'
      '<rect x="0" y="0" width="100" height="100" fill="#FF0000"/>'
      '<rect x="100" y="0" width="100" height="100" fill="#0000FF"/></svg>')!;
  return VectorElement(const ElementBase(id: "v", width: 200, height: 100),
      assetId: "halves.svg",
      viewBox: svg.viewBox,
      shapes: svg.shapes,
      crop: crop);
}

/// _Drawings hands out the same two halves as a file's own picture, for a
/// drawing nobody has taken apart.
class _Drawings extends CanvasImageSource {
  final CanvasVector vector;
  _Drawings(this.vector);
  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) => null;
  @override
  CanvasVector? resolveVector(String assetId) => vector;
}

CanvasVector _filePicture() {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(
      const Rect.fromLTWH(0, 0, 100, 100), Paint()..color = _red);
  canvas.drawRect(
      const Rect.fromLTWH(100, 0, 100, 100), Paint()..color = _blue);
  return CanvasVector(recorder.endRecording(), const Size(200, 100));
}

/// _pixels draws [e] in its own box on white, 220 wide.
Future<Color Function(int, int)> _pixels(VectorElement e,
    {CanvasImageSource? images}) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(
      const Rect.fromLTWH(0, 0, 220, 120), Paint()..color = _white);
  paintVector(canvas, e.bounds, e, images);
  var image = await recorder.endRecording().toImage(220, 120);
  var bytes = (await image.toByteData())!;
  image.dispose();
  return (x, y) {
    var p = bytes.getUint32((y * 220 + x) * 4);
    return Color(((p & 0xFF) << 24) | (p >> 8));
  };
}

void main() {
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);

  test("a crop is saved, and nothing is written without one", () {
    var cropped = _halves(crop: const ImageCrop(right: 0.5));
    var back =
        VectorElement.fromJson(cropped.toJson(), const ElementBase(id: "v"));
    expect(back.crop.right, 0.5);
    expect(_halves().toJson().containsKey("crop"), isFalse);
  });

  test("trimming the box keeps what is left where it was", () {
    // The left half, kept: the box loses its right half and nothing moves.
    var e = _halves();
    var trimmed = e.croppedTo(const ImageCrop(right: 0.5), e.viewBox);
    expect(trimmed.bounds, const Rect.fromLTWH(0, 0, 100, 100));
    // And the right half, kept, stays on the right.
    var right = e.croppedTo(const ImageCrop(left: 0.5), e.viewBox);
    expect(right.bounds, const Rect.fromLTWH(100, 0, 100, 100));
    // Back to the whole of it, from there, is the box it started as.
    expect(right.croppedTo(const ImageCrop(), e.viewBox).bounds, e.bounds);
  });

  test("only the window is drawn, from shapes or from the file", () async {
    var trimmed = _halves().croppedTo(const ImageCrop(left: 0.5),
        const Rect.fromLTWH(0, 0, 200, 100));
    var taken = await _pixels(trimmed);
    expect(taken(150, 50), _blue);
    expect(taken(50, 50), _white, reason: "the red half is cropped away");

    // Never taken apart: drawn as its file draws itself, and cropped too.
    var file = const VectorElement(
            ElementBase(id: "v", x: 100, width: 100, height: 100),
            assetId: "halves.svg",
            crop: ImageCrop(left: 0.5));
    var drawn = await _pixels(file, images: _Drawings(_filePicture()));
    expect(drawn(150, 50), _blue);
    expect(drawn(50, 50), _white);
  });

  testWidgets("the Crop fields trim the drawing", (tester) async {
    var e = _halves();
    var controller = CanvasController(const CanvasDocument().addElement(e));
    addTearDown(controller.dispose);
    controller.selectOnly("v");
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(
          home: Scaffold(body: CanvasDesignPanel(controller: controller))),
    ));
    await tester.pumpAndSettle();

    var field = find.byKey(const ValueKey("vectorCropRight"));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    tester.widget<CanvasNumberField>(field).onChanged(0.5);
    tester.widget<CanvasNumberField>(field).onCommit?.call();
    await tester.pumpAndSettle();
    var cropped = controller.document.elements.single as VectorElement;
    expect(cropped.crop.right, 0.5);
    expect(cropped.bounds.width, 100, reason: "the box trimmed with it");

    await tester.tap(find.byKey(const ValueKey("vectorCropWhole")));
    await tester.pumpAndSettle();
    var whole = controller.document.elements.single as VectorElement;
    expect(whole.crop.isWhole, isTrue);
    expect(whole.bounds, e.bounds);
  });
}
