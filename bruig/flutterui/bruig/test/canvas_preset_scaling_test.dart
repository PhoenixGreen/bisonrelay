import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/element_preset.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/preset_scaling.dart';
import 'package:bruig/plugin_system/canvas/model/saved_preset.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_preset_scaling_test.dart is a saved design arriving on a canvas of
// another size.
//
// Reported as presets coming in too big: a headline built for a 1920-wide
// banner arrived on a 600-wide canvas still 1920 wide, in type nobody could
// use. It arrives at the scale it was designed at now -- the box *and* what
// is inside it, which is the part a plain resize gets wrong.

void main() {
  TextElement headline(Size on) => TextElement(
        ElementBase(
            id: "t", x: 100, y: 50, width: on.width / 2, height: 120),
        text: "Spend or burn",
        textSpec: const TextSpec(fontSize: 60),
      );

  group("how much a preset is sized by", () {
    test("the smaller of the two ratios, so it fits across and down", () {
      expect(presetScale(const Size(1920, 1080), const Size(960, 540)), 0.5);
      // Wide design, tall page: across is what decides.
      expect(presetScale(const Size(1000, 100), const Size(500, 500)), 0.5);
    });

    test("and nothing at all where there is nothing to go on", () {
      // An older preset, saved before the page was kept: it arrives as it
      // was rather than being guessed at.
      expect(presetScale(null, const Size(600, 600)), 1);
      expect(presetScale(const Size(0, 0), const Size(600, 600)), 1);
      expect(presetScale(const Size(600, 600), const Size(600, 600)), 1);
    });
  });

  test("an element preset arrives at the size it was designed at", () {
    const banner = Size(1920, 1080);
    var preset = ElementPreset(
      id: "p",
      name: "Headline",
      kind: ElementKind.text,
      element: {...headline(banner).toJson()}
        ..remove("id")
        ..remove("x")
        ..remove("y"),
      madeOn: banner,
    );

    var built = preset.buildFor(const Size(960, 540)) as TextElement;
    expect(built.width, 480, reason: "half the page, as it was on the banner");
    expect(built.textSpec.fontSize, 30,
        reason: "and the type with it -- a box scaled alone is a stretch");
    // Dropped in the middle, because a preset carries no place of its own.
    expect(built.x, closeTo((960 - 480) / 2, 0.5));
    expect(built.y, closeTo((540 - built.height) / 2, 0.5));
  });

  test("and is left alone when the page has not changed", () {
    const page = Size(960, 540);
    var preset = ElementPreset(
      id: "p",
      name: "Headline",
      kind: ElementKind.text,
      element: {...headline(page).toJson()}..remove("id"),
      madeOn: page,
    );
    var built = preset.buildFor(page) as TextElement;
    expect(built.width, 480);
    expect(built.textSpec.fontSize, 60);
  });

  test("a scene preset brings everything on it down together", () {
    const banner = Size(1920, 1080);
    var preset = SavedPreset(
      id: "p",
      name: "Title card",
      kind: SavedPresetKind.scene,
      made: DateTime.now(),
      madeOn: banner,
      data: CanvasScene(id: "s", elements: [headline(banner)]).toJson(),
    );

    var scene = preset.buildScene(on: const Size(960, 540))!;
    var text = scene.elements.single as TextElement;
    expect(text.width, 480);
    expect(text.x, 50, reason: "where it was, at the new scale");
    expect(text.textSpec.fontSize, 30);
  });

  test("a saved canvas is sized by its own page when its scenes are added",
      () {
    // A canvas preset carries its page in its own JSON, so that is what its
    // scenes are scaled from -- it needs no madeOn of its own.
    var document = CanvasDocument(
      size: const CanvasSize(ratio: CanvasRatio.wide, width: 1920),
      scenes: [
        CanvasScene(id: "a", elements: [headline(const Size(1920, 1080))]),
      ],
    );
    var preset = SavedPreset(
      id: "p",
      name: "Match report",
      kind: SavedPresetKind.canvas,
      made: DateTime.now(),
      data: document.toJson(),
    );

    var scenes = preset.buildScenes(on: const Size(960, 540));
    var text = scenes.single.elements.single as TextElement;
    expect(text.width, 480);
    expect(text.textSpec.fontSize, 30);

    // Starting a document from it is another matter: it brings its own page,
    // so there is nothing to scale to.
    var started = preset.buildDocument()!;
    expect(started.size.width, 1920);
    expect(
        (started.allScenes.single.elements.single as TextElement).width, 960);
  });
}
