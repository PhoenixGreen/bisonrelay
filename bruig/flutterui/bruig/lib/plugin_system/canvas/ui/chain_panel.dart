import 'package:bruig/plugin_system/canvas/ui/chain_icons.dart';
import 'package:bruig/plugin_system/canvas/ui/device_presets.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart'
    show MixDevice, withDeviceIds;
import 'package:bruig/plugin_system/canvas/model/mix.dart' show sceneBusKey;
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart'
    show
        DeviceFrame,
        DeviceTier,
        chainMenuDivider,
        freezeFrom,
        chainMenuItem,
        chainMenuStyle,
        dragPointers;
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
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

  /// _copied is a chain copied by the header's ⋯, to paste into another.
  static List<MixDevice>? _copied;

  /// _dragFrom is the height and the pointer's place when a drag of the
  /// header began; measured from there, so no move between frames is lost.
  (double, double)? _dragFrom;

  /// _chainHeight is the height the chain had when an editor was opened
  /// from its tabs -- an editor wants more room, so a short panel grows to
  /// [editorLeast] -- to go back to when the chain is shown again.
  double? _chainHeight;

  /// editorLeast is how tall an editor opens the panel, at the least.
  static const double editorLeast = 380;

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var motion = c.chainShowsMotion;
    var body = (widget.height - ChainPanel.headerHeight)
        .clamp(0.0, double.infinity)
        .toDouble();
    // No tips on hover, as the prototype has none: what needs saying is
    // behind each device's "?".
    return TooltipVisibility(
      visible: false,
      child: SizedBox(
        key: const ValueKey("chainPanel"),
        height: widget.height,
        child: Column(children: [
          GestureDetector(
            supportedDevices: dragPointers,
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
                // One row, as the prototype has it: what it shows, its sound
                // or motion, its views; then how tall it is.
                child: Row(children: [
                  // What it shows and its views take what room is spare; its
                  // heights and the rest keep to the far right.
                  Expanded(
                    child: Row(children: [
                      _ChainWho(controller: c, look: look),
                      const SizedBox(width: 6),
                      _ChainSwitch(
                          motion: motion,
                          look: look,
                          onChanged: (m) => c.showChain(motion: m)),
                      Flexible(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (motion)
                              ..._motionTabs(look)
                            else
                              ..._editorTabs(look),
                          ]),
                        ),
                      ),
                      // A word on what it shows, where there is one: a scene's
                      // next, a clip's place, an element with none.
                      if (chainNote(c) case var note?)
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Text(note,
                                key: const ValueKey("chainNote"),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11, color: look.studio.muted)),
                          ),
                        ),
                    ]),
                  ),
                  ..._sizeControls(look),
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
                    onResize: (h) =>
                        widget.onResize(h + ChainPanel.headerHeight),
                  )
                : CanvasMixer.effects(
                    key: const ValueKey("chainSound"),
                    controller: c,
                    height: body,
                    onResize: (h) =>
                        widget.onResize(h + ChainPanel.headerHeight),
                    onClose: () => c.effectsOpen = false,
                  ),
          ),
        ]),
      ),
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
    // No clip in a slot: its sound on the timeline, as a clip (Ken: the two
    // are interchangeable).
    if (firstClip == null && !notes && c.timelineSoundOf(key) != null) {
      firstClip = timelineRow;
    }
    if (!notes && firstClip == null && !channel) return const [];
    var rollOn = c.pianoRollShown && c.pianoRoll?.row == null;
    var clipOn = c.clipEditorShown;
    var speechOn = c.speechShown;
    var pitchOn = c.pitchShown;
    var instrumentOn = c.instrumentShown;
    // No Pitch tab, as the prototype has none (Ken): pitch is the device's
    // that has it -- a voice's Speech's Phrasing button, Auto-tune's way
    // into the Pitch editor.
    var voice = channel && !notes && c.speechOf(key) != null;
    Widget tab(String id, String label, IconData icon, bool on,
            VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: InkWell(
            key: ValueKey(id),
            borderRadius: BorderRadius.circular(6),
            onTap: on
                ? null
                : () {
                    // An editor wants room; back on the chain, the height it
                    // had.
                    if (id == "chainTabDevices") {
                      if (_chainHeight case var was?) widget.onResize(was);
                      _chainHeight = null;
                    } else if (_chainHeight == null &&
                        !c.chainFull &&
                        widget.height < _ChainPanelState.editorLeast - 20) {
                      _chainHeight = widget.height;
                      widget.onResize(_ChainPanelState.editorLeast);
                    }
                    onTap();
                  },
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
                ChainIcon(_tabIcons[id] ?? chainIconFor(icon) ?? "plus",
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
      const SizedBox(width: 6),
      Container(width: 1, height: 22, color: look.studio.edge),
      const SizedBox(width: 4),
      tab(
          "chainTabDevices",
          "Chain",
          Icons.call_split,
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
      // Speech makes a voice channel's clips: chosen for it, as an
      // instrument is, from the Add menu's Generators.
      if (voice)
        tab("chainTabSpeech", "Speech", Icons.record_voice_over, speechOn,
            () => c.showSpeech(key)),
    ];
  }
}

extension on _ChainPanelState {
  /// _motionTabs are the motion view's: its chain.
  List<Widget> _motionTabs(MixerLook look) => [
        const SizedBox(width: 6),
        Container(width: 1, height: 22, color: look.studio.edge),
        const SizedBox(width: 4),
        _ChainTab(
            id: "chainTabMotionChain",
            label: "Chain",
            icon: Icons.call_split,
            on: true,
            look: look,
            onTap: null),
      ];

  /// _soundOwner is the strip whose effects the Chain shows -- what Copy
  /// and Paste work on -- or null showing motion.
  String? get _soundOwner =>
      c.chainShowsMotion ? null : c.effectsOf ?? c.effectsChannel;

  /// _foldEvery folds every card the Chain shows, or opens every one, as
  /// each card's own name does when pressed.
  void _foldEvery(bool fold) {
    var frames = <DeviceFrame>[];
    void visit(Element e) {
      if (e.widget case DeviceFrame f) frames.add(f);
      e.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    for (var f in frames) {
      if (f.folded != fold) f.onFold();
    }
  }

  /// _sizeControls are the header's right end: how much each device shows
  /// at this height, the heights to pick from, filling the window, and the
  /// rest behind its "more" button.
  List<Widget> _sizeControls(MixerLook look) {
    // The devices' room: the panel less its header and the lane's padding,
    // as the strip's devices are given it.
    var lane = widget.height - ChainPanel.headerHeight - 14;
    var tier = DeviceTier.of(lane);
    const heights = [
      ("Strip", 140.0),
      ("S", 178.0),
      ("M", 272.0),
      ("L", 400.0)
    ];
    var mono = TextStyle(
        fontSize: 10.5,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: look.studio.muted);
    var tierName = switch (tier) {
      DeviceTier.large => "Large",
      DeviceTier.medium => "Medium",
      DeviceTier.small => "Small",
      DeviceTier.strip => "Strip",
    };
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Tooltip(
          message: "How much each device shows at this height",
          child: Text("$tierName · ${widget.height.round()} px",
              key: const ValueKey("chainTier"), style: mono),
        ),
      ),
      _Segments(
        look: look,
        items: [
          for (var (name, h) in heights)
            (
              "chainHeight-$name",
              name,
              !c.chainFull && (widget.height - h).abs() < 2,
              () {
                c.chainFull = false;
                widget.onResize(h);
              }
            ),
        ],
      ),
      const SizedBox(width: 4),
      _IconChip(
        id: "chainMax",
        icon: c.chainFull ? Icons.close_fullscreen : Icons.open_in_full,
        tip: c.chainFull ? "Back to the canvas" : "Fill the window",
        on: c.chainFull,
        look: look,
        onTap: () => c.chainFull = !c.chainFull,
      ),
      MenuAnchor(
        style: chainMenuStyle(look),
        builder: (context, menu, _) => _IconChip(
          id: "chainMore",
          icon: Icons.more_horiz,
          tip: "More",
          on: false,
          look: look,
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
        ),
        menuChildren: [
          chainMenuItem(look,
              key: const ValueKey("chainFoldAll"),
              text: "Fold every device",
              onPressed: () => _foldEvery(true)),
          chainMenuItem(look,
              key: const ValueKey("chainUnfoldAll"),
              text: "Unfold every device",
              onPressed: () => _foldEvery(false)),
          if (_soundOwner case var owner?) ...[
            chainMenuDivider(look),
            if (c.frozenSteps(owner).isNotEmpty)
              chainMenuItem(look,
                  key: const ValueKey("chainUnfreeze"),
                  text: "Unfreeze the chain",
                  onPressed: () => c.unfreezeChain(owner))
            else if (c.canFreeze(owner) == null && c.chainOf(owner).isNotEmpty)
              chainMenuItem(look,
                  key: const ValueKey("chainFreeze"),
                  text: "Freeze this chain",
                  hint: "plays a copy",
                  onPressed: c.freezing(owner)
                      ? null
                      : () =>
                          freezeFrom(context, c, owner, c.chainOf(owner).last)),
            chainMenuItem(look,
                key: const ValueKey("chainSavePreset"),
                text: "Save the whole chain as a preset", onPressed: () {
              var name = _ChainWho.nameOf(c);
              saveDevicePreset(context, "$name chain",
                  devices: c.devicesOf(owner),
                  midi: c.instrumentChannel(owner)
                      ? c.instrumentOf(owner)?.instrument?.effects ?? const []
                      : const []);
            }),
            chainMenuItem(look,
                key: const ValueKey("chainCopy"),
                text: "Copy this chain",
                hint: "${c.devicesOf(owner).length} devices",
                onPressed: () =>
                    _ChainPanelState._copied = [...c.devicesOf(owner)]),
            chainMenuItem(look,
                key: const ValueKey("chainPaste"),
                text: "Paste a chain here",
                hint:
                    _ChainPanelState._copied == null ? "nothing copied" : null,
                onPressed: _ChainPanelState._copied == null
                    ? null
                    : () {
                        // After this chain's own, each with an id of its own.
                        c.beginInteraction();
                        c.setDevicesOf(
                            owner,
                            withDeviceIds([
                              ...c.devicesOf(owner),
                              for (var d in _ChainPanelState._copied!)
                                d.withId(""),
                            ]));
                        c.endInteraction();
                      }),
          ],
          chainMenuDivider(look),
          chainMenuItem(look,
              key: const ValueKey("chainClose"),
              text: "Close the Chain", onPressed: () {
            c.animationOpen = false;
            c.effectsOpen = false;
          }),
        ],
      ),
    ];
  }
}

/// chainNote is the header's word on what the Chain shows, after its
/// tabs, or null for none: in the motion view, what a scene gives way to,
/// where a clip plays, or that an element has no clips yet.
String? chainNote(CanvasController c) {
  if (!c.chainShowsMotion) return null;
  var doc = c.document;
  if (c.pickedScene case var i?) {
    if (doc.editingMaster) return "unless one says otherwise";
    return i + 1 < doc.allScenes.length
        ? "gives way to ${doc.nameOf(i + 1)}"
        : "the last: gives way to nothing";
  }
  CanvasElement? e;
  MotionClip? clip;
  if (c.pickedMotion case var id?) {
    for (var x in doc.elements) {
      if (x.base.motion.clip(id) case var found?) {
        (e, clip) = (x, found);
        break;
      }
    }
  } else if (c.selected case var x?) {
    var m = x.base.motion;
    e = x;
    clip = [
      for (var s in m.slots)
        if (s.isNotEmpty) s,
      for (var p in m.placed) p.clip,
    ].map(m.clip).whereType<MotionClip>().firstOrNull;
  }
  if (e == null) return null;
  if (clip == null) {
    return "No clips: double-click its row on the timeline for one";
  }
  var place = c.pickedPlacement;
  var span = place == null ? null : c.spanOf(place);
  var slot = e.base.motion.slots.indexOf(clip.id);
  var where = span != null
      ? "On the timeline"
      : slot < 0
          ? "In no slot"
          : "Slot ${slot + 1}";
  return "${clip.name} · $where"
      "${clip.isSound ? "" : " · layer ${clip.layer + 1}"} · ${clip.kind.label}";
}

/// _tabIcons are the prototype's icons for the Chain's views, by key.
const _tabIcons = {
  "chainTabDevices": "split",
  "chainTabMotionChain": "split",
  "chainTabNotes": "draw",
  "chainTabInstrument": "keys",
  "chainTabClip": "wave",
  "chainTabSpeech": "voice",
  "chainTabPitch": "note",
};

/// _chainKindColours are the colours of what the Chain can show, as the
/// prototype has them: a channel's by what it plays, a bus's, an element's.
const _chainKindColours = {
  "Audio": Color(0xFF4F8FD6),
  "Video": Color(0xFF4F8FD6),
  "MIDI": Color(0xFFD08F3E),
  "Voice": Color(0xFFC45C8A),
  "Element": Color(0xFF3FB08D),
  "Return": Color(0xFF8E6BD1),
  "Master": Color(0xFFCFCBDF),
  "Scene": Color(0xFF5A9FA8),
};

/// _ChainWho is the header's start: what the Chain shows -- its colour,
/// name and kind -- and, pressed, a list to pick something else from.
class _ChainWho extends StatelessWidget {
  final CanvasController controller;
  final MixerLook look;
  const _ChainWho({required this.controller, required this.look});

  CanvasController get c => controller;

  /// nameOf is the name of what [c]'s Chain shows.
  static String nameOf(CanvasController c) => _shownBy(c).$1;

  /// _shown is what the Chain shows now: its name and its kind.
  (String, String) _shown() => _shownBy(c);

  static (String, String) _shownBy(CanvasController c) {
    if (c.chainShowsMotion) {
      if (c.pickedScene case var i?) {
        return (
          c.document.editingMaster
              ? "Every ${c.document.kind.one}"
              : c.document.nameOf(i),
          "Scene"
        );
      }
      var e = c.selected;
      if (e == null && c.pickedMotion != null) {
        e = c.document.elements
            .where((x) => x.base.motion.clip(c.pickedMotion!) != null)
            .firstOrNull;
      }
      if (e == null) return ("Nothing picked", "");
      return (e.name.isEmpty ? e.id : e.name, "Element");
    }
    var key = c.effectsOf ?? c.effectsChannel;
    if (key == mixerMasterKey) return ("Master", "Master");
    if (key == sceneBusKey) {
      return (c.document.nameOf(c.document.at), "Scene");
    }
    if (c.returnOf(key) case var r?) return (r.name, "Return");
    var lane = c.timelineChannels.where((l) => l.key == key).firstOrNull;
    if (lane == null) return ("Nothing picked", "");
    var kind = c.instrumentChannel(key)
        ? "MIDI"
        : c.speechOf(key) != null
            ? "Voice"
            : key.startsWith("snd-")
                ? "Element"
                : lane.video
                    ? "Video"
                    : "Audio";
    return (lane.name, kind);
  }

  @override
  Widget build(BuildContext context) {
    var (name, kind) = _shown();
    var colour = _chainKindColours[kind] ?? look.studio.muted;
    var elements = [
      for (var e in c.document.elements)
        if (e is! AudioElement) e,
    ];
    var shown = c.chainShowsMotion ? null : c.effectsOf ?? c.effectsChannel;
    return MenuAnchor(
      style: chainMenuStyle(look),
      builder: (context, menu, _) => InkWell(
        key: const ValueKey("chainWho"),
        borderRadius: BorderRadius.circular(6),
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        child: Container(
          height: 24,
          padding: const EdgeInsets.fromLTRB(6, 0, 4, 0),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: colour, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(name,
                  key: const ValueKey("chainWhoName"),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: look.studio.text)),
            ),
            if (kind.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(kind,
                  style: TextStyle(fontSize: 11, color: look.studio.muted)),
            ],
            Icon(Icons.expand_more, size: 15, color: look.studio.muted),
          ]),
        ),
      ),
      menuChildren: [
        _heading("Channels"),
        for (var lane in c.timelineChannels)
          chainMenuItem(look,
              key: ValueKey("chainWho-${lane.key}"),
              text: lane.name,
              current: shown == lane.key,
              onPressed: () => c.openEffects(lane.key)),
        _heading("Buses"),
        for (var r in c.document.returns)
          chainMenuItem(look,
              key: ValueKey("chainWho-${r.id}"),
              text: r.name,
              current: shown == r.id,
              onPressed: () => c.openEffects(r.id)),
        chainMenuItem(look,
            key: const ValueKey("chainWho-master"),
            text: "Master",
            current: shown == mixerMasterKey,
            onPressed: () => c.openEffects(mixerMasterKey)),
        if (elements.isNotEmpty) _heading("Elements"),
        for (var e in elements)
          chainMenuItem(look,
              key: ValueKey("chainWho-${e.id}"),
              text: e.name.isEmpty ? e.id : e.name,
              current: c.chainShowsMotion && c.selected?.id == e.id,
              onPressed: () {
            c.selectOnly(e.id);
            c.showChain(motion: true);
          }),
      ],
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w500,
                color: look.studio.muted)),
      );
}

/// _ChainTab is one of the header's views: on, raised with a line under.
class _ChainTab extends StatelessWidget {
  final String id, label;
  final IconData icon;
  final bool on;
  final MixerLook look;
  final VoidCallback? onTap;
  const _ChainTab(
      {required this.id,
      required this.label,
      required this.icon,
      required this.on,
      required this.look,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
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
                      bottom: BorderSide(color: look.colors.primary, width: 2))
                  : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ChainIcon(_tabIcons[id] ?? chainIconFor(icon) ?? "plus",
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
}

/// _Segments is a row of joined buttons, the one on filled: the header's
/// heights.
class _Segments extends StatelessWidget {
  final MixerLook look;

  /// items are each button's key, label, whether it is on, and its press.
  final List<(String, String, bool, VoidCallback)> items;
  const _Segments({required this.look, required this.items});

  @override
  Widget build(BuildContext context) => Container(
        height: 24,
        decoration: BoxDecoration(
          border: Border.all(color: look.studio.edge),
          borderRadius: BorderRadius.circular(6),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var (i, (id, label, on, tap)) in items.indexed) ...[
            if (i > 0) Container(width: 1, color: look.studio.edge),
            InkWell(
              key: ValueKey(id),
              onTap: tap,
              child: Container(
                color: on ? look.colors.primary : null,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: on ? look.colors.onPrimary : look.studio.muted)),
              ),
            ),
          ],
        ]),
      );
}

/// _IconChip is a small square button of the header's: filled when [on].
class _IconChip extends StatelessWidget {
  final String id, tip;
  final IconData icon;
  final bool on;
  final MixerLook look;
  final VoidCallback onTap;
  const _IconChip(
      {required this.id,
      required this.icon,
      required this.tip,
      required this.on,
      required this.look,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: InkWell(
          key: ValueKey(id),
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: on ? look.colors.primary : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: chainIconOr(icon,
                  size: 15,
                  color: on ? look.colors.onPrimary : look.studio.muted),
            ),
          ),
        ),
      );
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
              chainIconOr(icon,
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
