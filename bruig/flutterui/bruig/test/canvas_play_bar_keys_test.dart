import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_dock.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/play_bar.dart';

import 'support/canvas_app.dart';
import 'support/canvas_audio_fake.dart';

// canvas_play_bar_keys_test.dart is what the play bar shows at three widths,
// as the keys of everything in it, in order, and of its timing menu open:
// with every button lit that can be (Play every scene, the knife, part of
// the timeline shown) and, where there is room for it, Back to the
// timeline. The bar drops its tempo and its names as it narrows; a change
// to how it is built that shows anything else, or in another order, shows
// here.

CanvasController _make({required bool held}) {
  var c = CanvasController(
      CanvasDocument(scenes: [
        CanvasScene(id: "one", frames: 240, elements: [
          AudioElement(
              const ElementBase(id: "m", name: "Music", visible: false),
              clip: const MediaClip(timed: true, channelName: "Music"),
              controls: const []),
        ]),
        const CanvasScene(id: "two", frames: 120),
      ]),
      audioEngine: FakeEngine(const {}));
  c.timelineTool = TimelineTool.knife;
  c.timelineShow = TimelineShow.animation;
  if (held) c.overridden["m"] = {"gain"};
  c.frame = 1;
  return c;
}

/// _named is [key] as text: a global or unique key by its kind alone, its
/// hash differing run to run.
String _named(Key key) => switch (key) {
      GlobalKey() || UniqueKey() || ObjectKey() => "${key.runtimeType}",
      _ => "$key",
    };

List<String> _keysUnder(Finder of) => [
      for (var w in find
          .descendant(
              of: of,
              matching: find.byWidgetPredicate((w) => w.key != null),
              matchRoot: true)
          .evaluate())
        _named(w.widget.key!),
    ];

void main() {
  for (var (width, name, held) in const [
    (2400.0, "wide", true),
    (1300.0, "middling", true),
    (700.0, "narrow", false),
  ]) {
    testWidgets("the play bar $name", (tester) async {
      var c = _make(held: held);
      addTearDown(c.dispose);
      setTestScreen(tester, Size(width, 1000));
      await tester.pumpWidget(canvasApp(Align(
          alignment: Alignment.bottomCenter,
          child: CanvasDock(controller: c, room: 700))));
      await tester.pump();
      await tester.pump();
      var bar = _keysUnder(find.byType(CanvasPlayBar));
      await tester.tap(find.byKey(const ValueKey("timingMenu")));
      await tester.pumpAndSettle();
      var timing = _keysUnder(find
          .ancestor(
              of: find.byKey(const ValueKey("timingClose")),
              matching: find.byWidgetPredicate(
                  (w) => w is Padding && w.padding == const EdgeInsets.all(10)))
          .first);
      expect(tester.takeException(), isNull);
      expect(bar, _shown[name]!["bar"]);
      expect(timing, _shown[name]!["timing"]);
    });
  }
}

/// _shown is what the bar shows at each width, and its timing menu.
const Map<String, Map<String, List<String>>> _shown = {
  "wide": {
    "bar": [
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<RawGestureDetectorState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<_RawMenuAnchorState>",
      "[<'dockLayouts'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'rowsToggle'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'slotsToggle'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'mixerToggle'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'chainToggle'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'toStart'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'play'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'stopPlaying'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'record'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'loop'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'playAll'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<_RawMenuAnchorState>",
      "[<'transportPosition'>]",
      "[<'timingMenu'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'playBarTempo'>]",
      "LabeledGlobalKey<_RawMenuAnchorState>",
      "[<'markerMenu'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'backToTimeline'>]",
      "[<'backToTimelineCount'>]",
      "LabeledGlobalKey<_RawMenuAnchorState>",
      "[<'backToTimelineList'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<RawGestureDetectorState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'lit-show'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'lit-toolKnife'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<_RawMenuAnchorState>",
      "[<'help-playBar'>]",
      "LabeledGlobalKey<_RawMenuAnchorState>",
      "[<'playBarSettings'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
    ],
    "timing": [
      "[<'timingClose'>]",
      "[<'canvasFrames'>]",
      "LabeledGlobalKey<EditableTextState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<RawGestureDetectorState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'canvasFrameRate'>]",
      "LabeledGlobalKey<EditableTextState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<RawGestureDetectorState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'timingRuns'>]",
      "[<'tapTempo'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'audioTempo'>]",
      "LabeledGlobalKey<EditableTextState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<RawGestureDetectorState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'audioSignature'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'audioQuantise'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'metronome'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'timingLoop'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'loopFrom'>]",
      "[<'loopLength'>]",
    ],
  },
  "middling": {
    "bar": [
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<RawGestureDetectorState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<_RawMenuAnchorState>",
      "[<'dockLayouts'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'rowsToggle'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'slotsToggle'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'mixerToggle'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'chainToggle'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'toStart'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'play'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'stopPlaying'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'record'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'loop'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'playAll'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<_RawMenuAnchorState>",
      "[<'transportPosition'>]",
      "[<'timingMenu'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<_RawMenuAnchorState>",
      "[<'markerMenu'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'backToTimeline'>]",
      "[<'backToTimelineCount'>]",
      "LabeledGlobalKey<_RawMenuAnchorState>",
      "[<'backToTimelineList'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<RawGestureDetectorState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'lit-show'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'lit-toolKnife'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<_RawMenuAnchorState>",
      "[<'help-playBar'>]",
      "LabeledGlobalKey<_RawMenuAnchorState>",
      "[<'playBarSettings'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
    ],
    "timing": [
      "[<'timingClose'>]",
      "[<'canvasFrames'>]",
      "LabeledGlobalKey<EditableTextState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<RawGestureDetectorState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'canvasFrameRate'>]",
      "LabeledGlobalKey<EditableTextState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<RawGestureDetectorState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'timingRuns'>]",
      "[<'tapTempo'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'audioTempo'>]",
      "LabeledGlobalKey<EditableTextState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<RawGestureDetectorState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'audioSignature'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'audioQuantise'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'metronome'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'timingLoop'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'loopFrom'>]",
      "[<'loopLength'>]",
    ],
  },
  "narrow": {
    "bar": [
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<RawGestureDetectorState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<_RawMenuAnchorState>",
      "[<'dockLayouts'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'rowsToggle'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'slotsToggle'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'mixerToggle'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'chainToggle'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'toStart'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'play'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'stopPlaying'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'record'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'loop'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'playAll'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<_RawMenuAnchorState>",
      "[<'transportPosition'>]",
      "[<'timingMenu'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<_RawMenuAnchorState>",
      "[<'markerMenu'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<RawGestureDetectorState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'lit-show'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'lit-toolKnife'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<_RawMenuAnchorState>",
      "[<'help-playBar'>]",
      "LabeledGlobalKey<_RawMenuAnchorState>",
      "[<'playBarSettings'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
    ],
    "timing": [
      "[<'timingClose'>]",
      "[<'canvasFrames'>]",
      "LabeledGlobalKey<EditableTextState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<RawGestureDetectorState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'canvasFrameRate'>]",
      "LabeledGlobalKey<EditableTextState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<RawGestureDetectorState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'timingRuns'>]",
      "[<'tapTempo'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'audioTempo'>]",
      "LabeledGlobalKey<EditableTextState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<RawGestureDetectorState>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'audioSignature'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'audioQuantise'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'metronome'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'timingLoop'>]",
      "LabeledGlobalKey<State<StatefulWidget>>",
      "[<'loopFrom'>]",
      "[<'loopLength'>]",
    ],
  },
};
