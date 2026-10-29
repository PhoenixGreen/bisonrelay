import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_channels.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// structure_panel.dart is a piece of sound's structure, where a document of
// scenes has its scenes: the sections it is laid out in -- an intro, a
// verse, a chorus, a middle eight -- each so many bars long, one after
// another along the timeline.
//
// The structure is a map of the timeline, not a cut through it: every sound
// is on the one timeline, and one that runs from the verse into the chorus
// simply plays on. With no sections the piece is its master structure, the
// whole of it as one.

class CanvasStructurePanel extends StatelessWidget {
  final CanvasController controller;
  const CanvasStructurePanel({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _body(context),
      );

  Widget _body(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var colors = theme.colors;
    var audio = controller.document.audio;
    var sections = audio.sections;
    void set(List<SongSection> next) {
      controller.beginInteraction();
      controller.setAudio(audio.copyWith(sections: next));
      controller.endInteraction();
    }

    String clock(double seconds) {
      var s = seconds.round();
      return "${s ~/ 60}:${(s % 60).toString().padLeft(2, "0")}";
    }

    Widget row(int i) {
      var section = sections[i];
      var colour = Color(sectionColors[section.color % sectionColors.length]);
      var start = audio.startBar(i);
      return Material(
        key: ValueKey("section-${section.id}"),
        color: Colors.transparent,
        child: InkWell(
          onTap: () => controller.goToSection(i),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            // One line where the sidebar has room for it; in a narrow one --
            // or at a larger text size -- the bars and the buttons go under
            // the name. They were a row of fixed widths that ran off the
            // panel's edge.
            child: LayoutBuilder(builder: (context, box) {
              var swatch = InkWell(
                key: ValueKey("sectionColour-$i"),
                onTap: () => set([...sections]..[i] = section.copyWith(
                    color: (section.color + 1) % sectionColors.length)),
                child: Container(
                  width: 10,
                  height: 28,
                  decoration: BoxDecoration(
                      color: colour, borderRadius: BorderRadius.circular(2)),
                ),
              );
              var named = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChannelNameEditor(
                        name: section.name,
                        theme: theme,
                        onRename: (name) => set(
                            [...sections]..[i] = section.copyWith(name: name)),
                        weight: FontWeight.w600,
                        fontSize: 12,
                        textKey: ValueKey("sectionName-$i"),
                        fieldKey: ValueKey("sectionNameField-$i")),
                    Text("Bar ${start + 1}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10, color: colors.onSurfaceVariant)),
                  ]);
              var controls = <Widget>[
                CanvasStepper(
                  key: ValueKey("sectionBars-$i"),
                  label: "Bars",
                  value: section.bars.toDouble(),
                  min: 1,
                  max: 512,
                  step: 1,
                  width: 76,
                  defaultValue: 8,
                  onChanged: (v) {
                    controller.beginInteraction();
                    controller.setAudio(
                        audio.copyWith(
                            sections: [...sections]..[i] =
                                section.copyWith(bars: v.round())),
                        transient: true);
                  },
                  onCommit: controller.endInteraction,
                ),
                CanvasIconButton(
                  key: ValueKey("sectionUp-$i"),
                  icon: Icons.arrow_upward,
                  tooltip: "Earlier",
                  tight: true,
                  onPressed: i == 0
                      ? null
                      : () => set([...sections]
                        ..removeAt(i)
                        ..insert(i - 1, section)),
                ),
                CanvasIconButton(
                  key: ValueKey("sectionDown-$i"),
                  icon: Icons.arrow_downward,
                  tooltip: "Later",
                  tight: true,
                  onPressed: i == sections.length - 1
                      ? null
                      : () => set([...sections]
                        ..removeAt(i)
                        ..insert(i + 1, section)),
                ),
                CanvasIconButton(
                  key: ValueKey("sectionDelete-$i"),
                  icon: Icons.delete_outline,
                  tooltip: "Take this section out of the structure. The "
                      "sounds under it stay where they are.",
                  tight: true,
                  onPressed: () => set([...sections]..removeAt(i)),
                ),
              ];
              // The one line wants the name some room besides its controls.
              var scale = MediaQuery.textScalerOf(context).scale(1);
              if (box.maxWidth >= 300 * scale) {
                return Row(children: [
                  swatch,
                  const SizedBox(width: 8),
                  Expanded(child: named),
                  ...controls,
                ]);
              }
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    swatch,
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            named,
                            const SizedBox(height: 4),
                            Wrap(
                                spacing: 0,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: controls),
                          ]),
                    ),
                  ]);
            }),
          ),
        ),
      );
    }

    // A list rather than a column, as the Scenes panel is: the stack gives
    // the panel its height, and a structure of a dozen sections -- or the
    // master's note and the chips in a short panel -- is taller than that.
    return ListView(padding: const EdgeInsets.all(8), children: [
      if (sections.isEmpty)
        Container(
          key: const ValueKey("masterStructure"),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Master structure",
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface)),
            const SizedBox(height: 2),
            Text(
                "The whole piece, as one. Add sections to lay it out — an "
                "intro, a verse, a chorus — each so many bars long. Sounds "
                "play on across them.",
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          ]),
        )
      else ...[
        for (var i = 0; i < sections.length; i++) row(i),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text(
              "${audio.totalBars} bars · "
              "${clock(audio.totalBars * audio.secondsPerBar)} at "
              "${audio.tempo.toStringAsFixed(audio.tempo % 1 == 0 ? 0 : 1)} "
              "BPM, ${audio.signature}",
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
        ),
      ],
      const SizedBox(height: 10),
      Text("Add a section",
          style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
      const SizedBox(height: 4),
      Wrap(spacing: 4, runSpacing: 4, children: [
        for (var name in sectionNames)
          ActionChip(
            key: ValueKey("addSection-$name"),
            label: Text(name, style: const TextStyle(fontSize: 11)),
            visualDensity: VisualDensity.compact,
            onPressed: () {
              controller.beginInteraction();
              controller.addSection(name);
              controller.endInteraction();
            },
          ),
      ]),
    ]);
  }
}
