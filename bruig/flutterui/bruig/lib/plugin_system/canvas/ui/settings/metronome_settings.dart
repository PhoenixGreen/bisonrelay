import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart'
    show panelRow, cell, CanvasQuickStrip, SettingsWrite;
import 'package:flutter/material.dart';

// metronome_settings.dart is a Metronome element's settings: tempo and
// beats in a bar (as its own buttons set them), start and stop, colours.
// Its tempo and beats are set through the controller (setMetronome), which
// keeps one that is going on the beat it is on; its colours are written as
// any element's are, and leave it going as it was.

List<Widget> metronomeSettings(
  BuildContext context,
  CanvasController controller,
  MetronomeElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  var going = controller.metronomeGoing(e.id);
  return [
    elementPanel(context, controller, e, write, begin, commit,
        quick: CanvasQuickStrip(key: const ValueKey("quickStrip"), children: [
          panelRow([
            cell(
                CanvasTextButton(
                  key: const ValueKey("metronomeGo"),
                  label: going ? "Stop" : "Start",
                  icon: going ? Icons.stop : Icons.play_arrow,
                  primary: true,
                  onPressed: () => controller.toggleMetronome(e),
                ),
                min: 100),
            cell(_tempo(controller, e, begin, commit, quick: true), min: 90),
          ]),
        ]),
        contentOpen: true,
        bits: [
          PanelBit(PanelSection.content,
              summary: "${e.bpm.round()} bpm · ${tempoWord(e.bpm)}",
              children: [
                CanvasControlGroup(
                    label: "Metronome",
                    help: "Its beats a minute, and the beats in a bar -- the "
                        "first clicked louder. Tap on it sets the speed from "
                        "your own taps.",
                    children: [
                      _tempo(controller, e, begin, commit, quick: false),
                      _beats(controller, e, begin, commit),
                    ]),
                _colours(e, write, begin, commit),
              ]),
        ]),
  ];
}

/// _tempo is its beats a minute: a number in the quick strip ([quick]), a
/// slider in its section, over the same range.
Widget _tempo(CanvasController controller, MetronomeElement e,
    VoidCallback begin, VoidCallback commit,
    {required bool quick}) {
  void set(double v) {
    begin();
    controller.setMetronome(e.copyWith(bpm: v));
  }

  return quick
      ? CanvasNumberField(
          key: const ValueKey("metronomeBpm"),
          label: "BPM",
          value: e.bpm,
          min: metronomeSlowest,
          max: metronomeFastest,
          onChanged: set,
          onCommit: commit,
        )
      : CanvasSlider(
          key: const ValueKey("metronomeBpmSlider"),
          label: "BPM",
          value: e.bpm,
          min: metronomeSlowest,
          max: metronomeFastest,
          onChanged: set,
          onCommit: commit,
        );
}

/// _beats is its beats in a bar, each it can hold.
Widget _beats(CanvasController controller, MetronomeElement e,
        VoidCallback begin, VoidCallback commit) =>
    CanvasDropdown<int>(
      key: const ValueKey("metronomeBeats"),
      label: "Beats in a bar",
      value: e.beats,
      options: [
        for (var b in metronomeBeats) (b, b == 1 ? "Every beat alike" : "$b"),
      ],
      onChanged: (b) {
        begin();
        controller.setMetronome(e.copyWith(beats: b));
        commit();
      },
    );

/// _colours are its wood's and its lamp's.
Widget _colours(MetronomeElement e, SettingsWrite write, VoidCallback begin,
        VoidCallback commit) =>
    CanvasControlGroup(label: "Colours", children: [
      panelRow([
        for (var (key, label, colour, next) in [
          (
            "metronomeBody",
            "Wood",
            e.body,
            (Color c) => e.copyWith(body: c),
          ),
          (
            "metronomeAccent",
            "Lamp",
            e.accent,
            (Color c) => e.copyWith(accent: c),
          ),
        ])
          cell(CanvasColorButton(
            key: ValueKey(key),
            label: label,
            color: colour,
            onChanged: (c) {
              begin();
              write(next(c));
              commit();
            },
          )),
      ]),
    ]);
