import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart'
    show panelRow, cell, CanvasQuickStrip;
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// metronome_settings.dart is a Metronome element's settings: how fast and
// the beats in a bar -- as its own buttons set them -- start and stop, and
// its colours.

List<Widget> metronomeSettings(
  BuildContext context,
  CanvasController controller,
  MetronomeElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  void now(MetronomeElement next) {
    begin();
    controller.setMetronome(next);
    commit();
  }

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
            cell(
                CanvasNumberField(
                  key: const ValueKey("metronomeBpm"),
                  label: "BPM",
                  value: e.bpm,
                  min: metronomeSlowest,
                  max: metronomeFastest,
                  onChanged: (v) {
                    begin();
                    controller.setMetronome(e.copyWith(bpm: v));
                  },
                  onCommit: commit,
                ),
                min: 90),
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
                      CanvasSlider(
                        key: const ValueKey("metronomeBpmSlider"),
                        label: "BPM",
                        value: e.bpm,
                        min: metronomeSlowest,
                        max: metronomeFastest,
                        onChanged: (v) {
                          begin();
                          controller.setMetronome(e.copyWith(bpm: v));
                        },
                        onCommit: commit,
                      ),
                      CanvasDropdown<int>(
                        key: const ValueKey("metronomeBeats"),
                        label: "Beats in a bar",
                        value: e.beats,
                        options: [
                          for (var b in metronomeBeats)
                            (b, b == 1 ? "Every beat alike" : "$b"),
                        ],
                        onChanged: (b) => now(e.copyWith(beats: b)),
                      ),
                    ]),
                CanvasControlGroup(label: "Colours", children: [
                  panelRow([
                    cell(CanvasColorButton(
                      key: const ValueKey("metronomeBody"),
                      label: "Wood",
                      color: e.body,
                      onChanged: (c) => now(e.copyWith(body: c)),
                    )),
                    cell(CanvasColorButton(
                      key: const ValueKey("metronomeAccent"),
                      label: "Lamp",
                      color: e.accent,
                      onChanged: (c) => now(e.copyWith(accent: c)),
                    )),
                  ]),
                ]),
              ]),
        ]),
  ];
}
