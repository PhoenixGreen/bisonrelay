import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/pitch_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/material.dart';

// chain_panel.dart is the Chain: one panel under the canvas for what is
// picked, its sound -- the chain of effects -- or its motion -- the
// animation -- switched in its header. It took the place of the Effects and
// Animation panels, and its two views are what they were (see
// CanvasController.chainShowsMotion); the devices of both are to become one
// kind of card in it.

/// ChainPanel is the Chain, [height] tall: a header with its Sound | Motion
/// switch, which also takes a drag to resize it (see [onResize]), over the
/// view it is on.
class ChainPanel extends StatefulWidget {
  final CanvasController controller;
  final double height;

  /// onResize is the header dragged up or down: the height asked for.
  final ValueChanged<double> onResize;

  /// headerHeight is the header's height, switch and all.
  static const double headerHeight = 30;

  const ChainPanel(
      {required this.controller,
      required this.height,
      required this.onResize,
      super.key});

  @override
  State<ChainPanel> createState() => _ChainPanelState();
}

class _ChainPanelState extends State<ChainPanel> {
  CanvasController get c => widget.controller;

  /// _dragFrom is the height and the pointer's place when a drag of the
  /// header began; measured from there, so no move between frames is lost.
  (double, double)? _dragFrom;

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var motion = c.chainShowsMotion;
    var body = (widget.height - ChainPanel.headerHeight)
        .clamp(0.0, double.infinity)
        .toDouble();
    return SizedBox(
      key: const ValueKey("chainPanel"),
      height: widget.height,
      child: Column(children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (d) =>
              _dragFrom = (widget.height, d.globalPosition.dy),
          onVerticalDragUpdate: (d) {
            if (_dragFrom case (var h, var y)) {
              widget.onResize(h + (y - d.globalPosition.dy));
            }
          },
          onVerticalDragEnd: (_) => _dragFrom = null,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: Container(
              height: ChainPanel.headerHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: look.studio.panel,
                border: Border(bottom: BorderSide(color: look.studio.edge)),
              ),
              child: Row(children: [
                Text("Chain",
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: look.studio.text)),
                const SizedBox(width: 10),
                _ChainSwitch(
                    motion: motion,
                    look: look,
                    onChanged: (m) => c.showChain(motion: m)),
                if (!motion) ..._editorTabs(look),
                const Spacer(),
                IconButton(
                  key: const ValueKey("chainClose"),
                  tooltip: "Close the Chain",
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, color: look.studio.text),
                  onPressed: () {
                    c.animationOpen = false;
                    c.effectsOpen = false;
                  },
                ),
              ]),
            ),
          ),
        ),
        Expanded(
          child: motion
              ? AnimationPanel(
                  key: const ValueKey("chainMotion"),
                  controller: c,
                  height: body,
                  onResize: (h) => widget.onResize(h + ChainPanel.headerHeight),
                )
              : CanvasMixer.effects(
                  key: const ValueKey("chainSound"),
                  controller: c,
                  height: body,
                  onResize: (h) => widget.onResize(h + ChainPanel.headerHeight),
                  onClose: () => c.effectsOpen = false,
                ),
        ),
      ]),
    );
  }
}

extension on _ChainPanelState {
  /// _editorTabs are the Chain's sound's views besides its devices: the
  /// channel's notes (an instrument's part, in the piano roll) and its
  /// first clip (in the clip editor), each opened in the chain.
  List<Widget> _editorTabs(MixerLook look) {
    var key = c.effectsOf ?? c.effectsChannel;
    int? firstClip;
    for (var row = 0; row < c.session.rows; row++) {
      if (c.session.at(key, row) != null) {
        firstClip = row;
        break;
      }
    }
    var notes = c.instrumentChannel(key);
    var channel = c.timelineChannels.any((l) => l.key == key);
    if (!notes && firstClip == null && !channel) return const [];
    var rollOn = c.pianoRollShown && c.pianoRoll?.row == null;
    var clipOn = c.clipEditorShown;
    var speechOn = c.speechShown;
    var pitchOn = c.pitchShown;
    var instrumentOn = c.instrumentShown;
    // A recording to tune: a channel's sound, not an instrument's.
    var tunable = channel && !notes && c.pitchElementOf(key) != null;
    Widget tab(String id, String label, IconData icon, bool on,
            VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: InkWell(
            key: ValueKey(id),
            borderRadius: BorderRadius.circular(6),
            onTap: on ? null : onTap,
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: on ? look.studio.raised : null,
                borderRadius: BorderRadius.circular(6),
                border: on
                    ? Border(
                        bottom:
                            BorderSide(color: look.colors.primary, width: 2))
                    : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon,
                    size: 14, color: on ? look.studio.text : look.studio.muted),
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: on ? look.studio.text : look.studio.muted)),
              ]),
            ),
          ),
        );
    return [
      const SizedBox(width: 8),
      Container(width: 1, height: 18, color: look.studio.edge),
      const SizedBox(width: 6),
      tab(
          "chainTabDevices",
          "Devices",
          Icons.linear_scale,
          !rollOn && !clipOn && !speechOn && !pitchOn && !instrumentOn,
          c.closeEditor),
      if (notes)
        tab("chainTabNotes", "Notes", Icons.piano, rollOn,
            () => c.openPianoRoll(key)),
      if (notes)
        tab("chainTabInstrument", "Instrument", Icons.tune, instrumentOn,
            () => c.showInstrument(key)),
      if (firstClip case var row?)
        tab("chainTabClip", "Clip", Icons.graphic_eq, clipOn,
            () => c.openClipEditor(key, row)),
      // Speech makes a channel's clips: any channel but an instrument's.
      if (channel && !notes)
        tab("chainTabSpeech", "Speech", Icons.record_voice_over, speechOn,
            () => c.showSpeech(key)),
      if (tunable)
        tab("chainTabPitch", "Pitch", Icons.multiline_chart, pitchOn,
            () => c.showPitch(key)),
    ];
  }
}

/// _ChainSwitch is the header's Sound | Motion: which of the picked
/// thing's chains the panel shows.
class _ChainSwitch extends StatelessWidget {
  final bool motion;
  final MixerLook look;
  final ValueChanged<bool> onChanged;
  const _ChainSwitch(
      {required this.motion, required this.look, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget side(String label, IconData icon, bool on, bool value) => InkWell(
          key: ValueKey(value ? "chainShowMotion" : "chainShowSound"),
          onTap: on ? null : () => onChanged(value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            color: on ? look.colors.primary : null,
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  size: 14,
                  color: on ? look.colors.onPrimary : look.studio.text),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: on ? look.colors.onPrimary : look.studio.text)),
            ]),
          ),
        );
    return Container(
      height: 22,
      decoration: BoxDecoration(
        border: Border.all(color: look.studio.edge),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        side("Sound", Icons.graphic_eq, !motion, false),
        Container(width: 1, color: look.studio.edge),
        side("Motion", Icons.timeline, motion, true),
      ]),
    );
  }
}
