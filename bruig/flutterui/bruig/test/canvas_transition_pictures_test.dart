import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/render/transition_covers.dart';

import 'support/kept_pictures.dart';

// canvas_transition_pictures_test.dart keeps the cover each scene
// transition draws over the page, to the byte, at five moments on the way
// in and out: every kind of transition, every way it can go, upright and
// turned, and for the shapes transition every kind of shape. It is the
// proof that a change meant only to move or tidy how the covers are built
// draws exactly what it did before.
//
// To use it, set TRANSITION_PICTURES to a folder and run this file on the
// code as it is: each state's picture (<state>.rgba and .png) is written
// there. Run it again to see that every one is stable from run to run.
// Then make the change and run it after each step: a state whose picture
// differs fails, saying how many pixels changed and where, and leaves the
// new picture beside the kept one as <state>.new.png. Without
// TRANSITION_PICTURES each cover is still built, and nothing is drawn or
// kept, so the test costs the whole suite little.
//
// Every kind, way and shape is taken from its enum's values, so a new one
// gets its states without anyone remembering to add them.

const Rect _page = Rect.fromLTWH(0, 0, 320, 180);

const _moments = [0.15, 0.3, 0.45, 0.7, 0.9];

/// _states is every transition this test keeps, by the name its pictures
/// are kept under.
List<(String, SceneTransition)> _states() => [
      for (var kind in SceneTransitionKind.values)
        for (var way in SceneTransitionWay.values)
          for (var angle in [0.0, 30.0])
            if (kind == SceneTransitionKind.shapeWipe)
              for (var shape in ShapeKind.values)
                (
                  "${kind.name}-${way.name}-$angle-${shape.name}",
                  SceneTransition(
                      kind: kind,
                      way: way,
                      angle: angle,
                      shape: shape,
                      count: 4)
                )
            else
              (
                "${kind.name}-${way.name}-$angle",
                SceneTransition(kind: kind, way: way, angle: angle, count: 5)
              ),
    ];

void main() {
  var keeping = (Platform.environment["TRANSITION_PICTURES"] ?? "").isNotEmpty;

  test("every transition's cover is built at every moment", () async {
    for (var (name, over) in _states()) {
      for (var t in _moments) {
        var path = overlayPath(over, _page, t);
        var bounds = path.getBounds();
        expect(bounds.isFinite, isTrue, reason: "$name-$t");
        if (!keeping) continue;

        var recorder = ui.PictureRecorder();
        ui.Canvas(recorder)
            .drawPath(path, Paint()..color = const Color(0xFF000000));
        var picture = recorder.endRecording();
        var (raw, png) = await imageBytes(
            await picture.toImage(_page.width.toInt(), _page.height.toInt()));
        picture.dispose();
        keepOrCompare("TRANSITION_PICTURES", "$name-$t",
            raw: raw, png: png, width: _page.width.toInt());
      }
    }
  });
}
