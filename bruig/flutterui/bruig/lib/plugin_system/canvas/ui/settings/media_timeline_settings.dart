import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// media_timeline_settings.dart is putting a video or a sound on the timeline.
//
// One switch and one number, shared by the video and the background sound so
// they are said the same way in both. On the timeline a clip stops being
// something a reader presses and becomes part of the animation: it plays with
// the playhead from the frame it is placed at, is scrubbed with it, and goes
// into an exported video with everything else. See MediaClip.timed.

/// timelineControls is the switch, the frame it starts at, and -- where the
/// clip runs past the end of the timeline -- a button that makes room for it.
///
/// [key] prefixes the widgets' keys, so the video's and the sound's can both
/// be found.
List<Widget> timelineControls(
  CanvasController controller,
  MediaClip clip, {
  required String key,
  required void Function(MediaClip) now,
  required void Function(MediaClip) write,
  required VoidCallback commit,
}) {
  var document = controller.document;
  var rate = document.frameRate <= 0 ? 1 : document.frameRate;
  var lasts = (clip.runLength * rate).ceil();
  var ends = clip.at + lasts;
  // The master's timeline is the whole run, whose length is its scenes'; it
  // cannot be lengthened from here.
  var short = !document.editingMaster &&
      clip.loop == MediaLoop.none &&
      ends > document.frames &&
      lasts > 0;

  return [
    CanvasToggle(
      key: ValueKey("${key}Timed"),
      label: "On the timeline",
      value: clip.timed,
      onChanged: (v) => now(clip.copyWith(timed: v)),
    ),
    if (clip.timed) ...[
      CanvasNumberField(
        key: ValueKey("${key}At"),
        label: "From frame",
        // One-based on screen, the same as the timeline's own frame field.
        value: (clip.at + 1).toDouble(),
        min: 1,
        max: maxFrameCount.toDouble() * 100,
        width: 68,
        onChanged: (v) => write(clip.copyWith(at: math.max(0, v.round() - 1))),
        onCommit: commit,
      ),
      if (short)
        CanvasIconButton(
          key: ValueKey("${key}Fit"),
          icon: Icons.unfold_more_double,
          tooltip: "It runs to frame $ends and the timeline stops at "
              "${document.frames}. Make the timeline long enough for it.",
          onPressed: () {
            controller.beginInteraction();
            controller.apply(controller.document
                .copyWith(frames: math.min(ends, maxFrameCount)));
            controller.endInteraction();
          },
        ),
      const CanvasHint(
          "On the timeline it plays with the playhead from this frame: "
          "scrubbed with it, held when it stops, and put into an exported "
          "video with its sound. Nothing on it is pressed, and it is not "
          "there before it starts or after it ends. Move it and trim it on "
          "the Channels strip."),
    ],
  ];
}
