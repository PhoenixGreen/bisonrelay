import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:bruig/plugin_system/canvas/render/sound_placement.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// placement_settings.dart is where a sound is heard from, set on the sound
// itself: an Audio element's, or a Video's. See SoundPlacement.
//
// Its channel follows it, in place of the channel's own pan -- and the
// strip in the mixer shows where the picture has put it.

/// placementSummary is how a sound is placed, in a few words.
String placementSummary(SoundPlacement place) => switch (place.by) {
      PlaceBy.off => "Its channel's pan",
      PlaceBy.canvas => "Across the canvas, ${place.arc.round()}° wide",
      PlaceBy.stage => "A spot on a stage",
      PlaceBy.follow => "With another element",
    };

/// placementGroup is [e]'s sound's placement, as settings: what it is
/// placed by, and what that needs.
Widget placementGroup(CanvasController controller, CanvasElement e,
    MediaClip clip, void Function(MediaClip next) clipNow,
    {void Function(MediaClip next)? clipLive, VoidCallback? commit}) {
  var doc = controller.document;
  var place = clip.place;
  void set(SoundPlacement next) => clipNow(clip.copyWith(place: next));
  void live(SoundPlacement next) =>
      (clipLive ?? clipNow)(clip.copyWith(place: next));
  var stages = stagesIn(doc.elements, backdrop: doc.drawnBackground);
  var followed = place.by == PlaceBy.follow
      ? doc.elementById(place.follow)
      : null;
  var onStage = place.by == PlaceBy.stage ||
      (followed is CharacterElement && followed.onStage != null);
  var across = place.by == PlaceBy.canvas ||
      (place.by == PlaceBy.follow && !onStage);
  var heard = heardAt(doc, e, place, controller.frame);
  return CanvasControlGroup(
    label: "Placement",
    rule: false,
    children: [
      CanvasDropdown<PlaceBy>(
        key: const ValueKey("placeBy"),
        label: "Heard from",
        value: place.by,
        width: 190,
        options: [
          for (var p in PlaceBy.values)
            if (p != PlaceBy.stage || stages.isNotEmpty) (p, p.label),
        ],
        onChanged: (by) => set(place.copyWith(
          by: by,
          // A first stage, when it has none yet.
          stage: by == PlaceBy.stage && place.stage.isEmpty && stages.isNotEmpty
              ? stages.first.$1
              : null,
        )),
      ),
      if (place.by == PlaceBy.stage)
        CanvasDropdown<String>(
          key: const ValueKey("placeStage"),
          label: "Stage",
          value: place.stage,
          width: 150,
          options: [
            for (var (id, name) in stages) (id, name),
            if (!stages.any((s) => s.$1 == place.stage))
              (place.stage, "Not here"),
          ],
          onChanged: (id) => set(place.copyWith(stage: id)),
        ),
      if (place.by == PlaceBy.follow)
        CanvasDropdown<String>(
          key: const ValueKey("placeFollow"),
          label: "Element",
          value: place.follow,
          width: 150,
          options: [
            if (!doc.elements.any((x) => x.id == place.follow))
              (place.follow, "Choose one"),
            for (var x in doc.elements)
              if (x.id != e.id) (x.id, x.name.isEmpty ? x.kind.label : x.name),
          ],
          onChanged: (id) => set(place.copyWith(follow: id)),
        ),
      if (place.by == PlaceBy.stage) ...[
        CanvasNumberField(
          key: const ValueKey("placeX"),
          label: "Across (m)",
          value: place.x,
          min: -100,
          max: 100,
          decimals: 1,
          width: 56,
          onChanged: (v) => live(place.copyWith(x: v)),
          onCommit: commit,
        ),
        CanvasNumberField(
          key: const ValueKey("placeZ"),
          label: "Back (m)",
          value: place.z,
          min: -100,
          max: 100,
          decimals: 1,
          width: 56,
          onChanged: (v) => live(place.copyWith(z: v)),
          onCommit: commit,
        ),
        CanvasNumberField(
          key: const ValueKey("placeY"),
          label: "Height (m)",
          value: place.y,
          min: 0,
          max: 50,
          decimals: 1,
          width: 56,
          onChanged: (v) => live(place.copyWith(y: v)),
          onCommit: commit,
        ),
      ],
      if (across)
        CanvasSlider(
          key: const ValueKey("placeArc"),
          label: "Wide",
          value: place.arc,
          min: 0,
          max: 360,
          decimals: 0,
          onChanged: (v) => live(place.copyWith(arc: v)),
          onCommit: commit,
        ),
      if (onStage) ...[
        CanvasSlider(
          key: const ValueKey("placeRolloff"),
          label: "Fades with distance",
          value: place.rolloff,
          min: 0,
          max: 2,
          decimals: 1,
          onChanged: (v) => live(place.copyWith(rolloff: v)),
          onCommit: commit,
        ),
        CanvasNumberField(
          key: const ValueKey("placeNear"),
          label: "Full to (m, 0 = middle)",
          value: place.near,
          min: 0,
          max: 100,
          decimals: 1,
          width: 56,
          onChanged: (v) => live(place.copyWith(near: v)),
          onCommit: commit,
        ),
      ],
      CanvasHint(switch (place.by) {
        PlaceBy.off => "Heard where its channel's pan in the mixer puts it.",
        _ when heard == null =>
          "What it is placed by is not here, so it is heard where its "
              "channel's pan puts it.",
        PlaceBy.canvas =>
          "Heard from where it is on the canvas: the left edge to the right "
              "is ${place.arc.round()}° round the listener. On this frame, "
              "${_say(heard)}.",
        _ => "Heard from where it is, by a listener at the camera"
            "${onStage ? ", quieter further off than the middle of the stage" : ""}. "
            "On this frame, ${_say(heard)}.",
      }),
    ],
  );
}

String _say(Heard h) {
  var a = wrapAngle(h.angle);
  var where = a.abs() < 1
      ? "straight ahead"
      : "${a.abs().round()}° to the ${a < 0 ? "left" : "right"}"
          "${a.abs() > 90 ? ", behind" : ""}";
  var level = h.gain >= 0.999
      ? ""
      : ", ${(20 * _log10(h.gain)).toStringAsFixed(1)} dB";
  return "$where$level";
}

double _log10(double x) => x <= 0 ? -99 : math.log(x) / math.ln10;
