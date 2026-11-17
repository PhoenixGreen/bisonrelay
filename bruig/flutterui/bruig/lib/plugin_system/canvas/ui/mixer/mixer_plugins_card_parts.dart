part of 'mixer_plugins.dart';

// Pieces round a device card: its bar's preset pickers, A|B switch and reading,
// the Works on menu, the folded level, and the gain and note joins between
// cards. Part of mixer_plugins.dart.

/// _PresetPicker is a card's preset on its bar ("Default ▾"): the saved
/// presets of its kind, Default to start again from, and Save.
class _PresetPicker extends StatefulWidget {
  final DeviceKind kind;
  final String? name;
  final void Function(String name, MixDevice preset) onPick;
  final VoidCallback onDefault;
  final VoidCallback onSave;
  const _PresetPicker(
      {required this.kind,
      required this.name,
      required this.onPick,
      required this.onDefault,
      required this.onSave,
      super.key});

  @override
  State<_PresetPicker> createState() => _PresetPickerState();
}

class _PresetPickerState extends State<_PresetPicker> {
  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var studio = look.studio;
    var kept = [
      for (var p in devicePresets.presets)
        if (presetDevices(p.data) case [var d] when d.kind == widget.kind)
          (p.name, d),
    ];
    return MenuAnchor(
      style: chainMenuStyle(look),
      menuChildren: [
        chainMenuHeading(look, "${widget.kind.label} presets"),
        chainMenuItem(look,
            key: const ValueKey("presetDefault"),
            text: "Default",
            current: widget.name == null,
            onPressed: widget.onDefault),
        for (var (name, d) in kept)
          chainMenuItem(look,
              key: ValueKey("preset-$name"),
              text: name,
              current: widget.name == name,
              onPressed: () => widget.onPick(name, d)),
        chainMenuDivider(look),
        chainMenuItem(look,
            key: const ValueKey("presetSave"),
            text: "Save these settings as a preset",
            onPressed: widget.onSave),
      ],
      builder: (context, menu, _) => GestureDetector(
        key: widget.key == null
            ? null
            : ValueKey("${(widget.key as ValueKey).value}-open"),
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          if (menu.isOpen) {
            menu.close();
            return;
          }
          await devicePresets.load();
          if (!mounted) return;
          setState(() {});
          menu.open();
        },
        child: _presetLabel(context, widget.name ?? "Default", studio),
      ),
    );
  }
}

/// _FoldedLevel is a folded device's level as the sound leaves it (the
/// join after it, [at]), a slim meter at the foot of its card.
class _FoldedLevel extends StatefulWidget {
  final CanvasController controller;
  final String owner;
  final int at;
  const _FoldedLevel(
      {required this.controller,
      required this.owner,
      required this.at,
      super.key});

  @override
  State<_FoldedLevel> createState() => _FoldedLevelState();
}

class _FoldedLevelState extends State<_FoldedLevel>
    with SingleTickerProviderStateMixin, _Metered {
  double _db = -90;

  @override
  CanvasController get meteredBy => widget.controller;

  @override
  void tick() {
    var taps = widget.controller.deviceLevels(widget.owner);
    var at = widget.at;
    _db = at > 0 && at < taps.length
        ? gainToDb(math.max(taps[at].$1, taps[at].$2))
        : -90;
  }

  @override
  Widget build(BuildContext context) {
    var studio = MixerLook.of(context).studio;
    var u = ((_db + 60) / 60).clamp(0.0, 1.0);
    return Center(
      child: Container(
        width: 6,
        margin: const EdgeInsets.symmetric(vertical: 4),
        alignment: Alignment.bottomCenter,
        decoration: BoxDecoration(
            color: studio.display, borderRadius: BorderRadius.circular(3)),
        child: FractionallySizedBox(
          heightFactor: u,
          child: Container(
            decoration: BoxDecoration(
                color: _db >= 0
                    ? const Color(0xFFE5484D)
                    : const Color(0xFF3FB08D),
                borderRadius: BorderRadius.circular(3)),
          ),
        ),
      ),
    );
  }
}

/// _PresetCompact tells a preset picker under it to show its mark alone,
/// its name in its tooltip: a card too narrow for "Default ▾".
class _PresetCompact extends InheritedWidget {
  const _PresetCompact({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PresetCompact>() != null;

  @override
  bool updateShouldNotify(_PresetCompact old) => false;
}

/// _presetLabel is a preset picker's face: "Default ▾", or -- compact --
/// its mark alone, the preset's name in its tooltip.
Widget _presetLabel(BuildContext context, String name, StudioColors studio) {
  if (_PresetCompact.of(context)) {
    return Tooltip(
      message: "Presets: $name",
      child: Container(
        width: 18,
        height: 16,
        margin: const EdgeInsets.only(right: 3),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: studio.edge)),
        child: Icon(Icons.tune, size: 11, color: studio.muted),
      ),
    );
  }
  return Container(
    constraints: const BoxConstraints(maxWidth: 82),
    height: 16,
    margin: const EdgeInsets.only(right: 3),
    padding: const EdgeInsets.only(left: 5, right: 1),
    decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: studio.edge)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9.5, height: 1.1, color: studio.muted)),
      ),
      Icon(Icons.arrow_drop_down, size: 12, color: studio.muted),
    ]),
  );
}

/// worksOnMenu is a card's ⋯ "Works on": the whole sound, its middle
/// (what both sides share) or its sides (where they differ).
Widget worksOnMenu(MixerLook look,
        {required String id,
        required int value,
        required ValueChanged<int> onPick}) =>
    SubmenuButton(
      key: ValueKey(id),
      style: chainMenuItemStyle(look),
      menuStyle: chainMenuStyle(look),
      menuChildren: [
        for (var (k, label) in const [
          (0, "Both sides"),
          (1, "Mid: what both sides share"),
          (2, "Side: where they differ"),
        ])
          chainMenuItem(look,
              key: ValueKey("$id-$k"),
              text: label,
              current: value == k,
              onPressed: () => onPick(k)),
      ],
      child: Text(
          "Works on: ${const ["both sides", "mid", "side"][value.clamp(0, 2)]}"),
    );

List<(String, Map<String, dynamic>)> _stripKept(StripPart part) => [
      for (var p in devicePresets.presets)
        if (stripPresetOf(p.data) case (var of, var value) when of == part)
          (p.name, value),
    ];

/// _StripPresetPicker is the Presets ▾ of a strip's own card (EQ,
/// compressor, limiter, Ducker): Default, built-ins, saved ones, Save.
class _StripPresetPicker extends StatefulWidget {
  /// label is what it is the presets of: "EQ", "Wiggle".
  final String label;

  /// kept are the saved presets it offers, by name, as written: asked for
  /// as it opens, once they are read.
  final List<(String, Map<String, dynamic>)> Function() kept;

  /// name is the preset last put on, or null for its own settings.
  final String? name;

  /// builtIn are its starting points, by name, as written (see toJson).
  final List<(String, Map<String, dynamic>)> builtIn;
  final void Function(String name, Map<String, dynamic> value) onPick;
  final VoidCallback onDefault;
  final VoidCallback onSave;
  const _StripPresetPicker(
      {required this.label,
      required this.kept,
      required this.name,
      required this.builtIn,
      required this.onPick,
      required this.onDefault,
      required this.onSave,
      super.key});

  @override
  State<_StripPresetPicker> createState() => _StripPresetPickerState();
}

class _StripPresetPickerState extends State<_StripPresetPicker> {
  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var studio = look.studio;
    var kept = widget.kept();
    var id = (widget.key as ValueKey?)?.value ?? "stripPreset";
    return MenuAnchor(
      style: chainMenuStyle(look),
      menuChildren: [
        chainMenuHeading(look, "${widget.label} presets"),
        chainMenuItem(look,
            key: ValueKey("$id-default"),
            text: "Default",
            current: widget.name == null,
            onPressed: widget.onDefault),
        for (var (name, value) in [...widget.builtIn, ...kept])
          chainMenuItem(look,
              key: ValueKey("$id-$name"),
              text: name,
              current: widget.name == name,
              onPressed: () => widget.onPick(name, value)),
        chainMenuDivider(look),
        chainMenuItem(look,
            key: ValueKey("$id-save"),
            text: "Save these settings as a preset",
            onPressed: widget.onSave),
      ],
      builder: (context, menu, _) => GestureDetector(
        key: ValueKey("$id-open"),
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          if (menu.isOpen) {
            menu.close();
            return;
          }
          await devicePresets.load();
          if (!mounted) return;
          setState(() {});
          menu.open();
        },
        child: _presetLabel(context, widget.name ?? "Default", studio),
      ),
    );
  }
}

/// _GainBadge is a device's level change, read between it and the one
/// before while sound passes ("+2.2" warm, "−4.1" cool).
class _GainBadge extends StatefulWidget {
  final CanvasController controller;
  final String channel;
  final String id;
  const _GainBadge(
      {required this.controller,
      required this.channel,
      required this.id,
      super.key});

  @override
  State<_GainBadge> createState() => _GainBadgeState();
}

class _GainBadgeState extends State<_GainBadge>
    with SingleTickerProviderStateMixin, _Metered {
  double? _change;

  @override
  CanvasController get meteredBy => widget.controller;

  /// Hidden from the Chain's ⋯, it reads nothing.
  @override
  bool get metering => widget.controller.chainBadges;

  @override
  void didUpdateWidget(_GainBadge old) {
    super.didUpdateWidget(old);
    meterAgain();
  }

  @override
  void tick() {
    var i = widget.controller.chainOf(widget.channel).indexOf(widget.id);
    var taps = widget.controller.deviceLevels(widget.channel);
    if (i < 0 || i + 1 >= taps.length) {
      _change = null;
      return;
    }
    double db((double, double) p) => gainToDb(math.max(p.$1, p.$2));
    var a = db(taps[i]), b = db(taps[i + 1]);
    var now = a <= -80 || b <= -80 ? null : b - a;
    // Steadied, so it can be read.
    _change = now == null
        ? null
        : _change == null
            ? now
            : _change! + (now - _change!) * 0.15;
  }

  @override
  Widget build(BuildContext context) {
    var c = _change;
    if (!widget.controller.chainBadges) return const SizedBox.shrink();
    if (c == null || c.abs() < 0.05) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Text(
          "${c >= 0 ? "+" : "−"}${c.abs().toStringAsFixed(1)}",
          key: ValueKey("deviceGain-${widget.id}"),
          style: TextStyle(
              fontSize: 9.5,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: c > 0 ? const Color(0xFFE2B04A) : const Color(0xFF7FC8F8))),
    );
  }
}

/// NoteJoin is a join on a MIDI chain: the notes passing there as dots,
/// one lit for each -- what is sounding now, done to by the first [upto]
/// of its MIDI effects (a chord adds notes, a scale moves them).
class NoteJoin extends StatefulWidget {
  final CanvasController controller;
  final String channel;
  final int upto;
  final double height;

  /// name tells it from the other joins in its keys: by default how many
  /// effects are before it.
  final String? name;
  const NoteJoin(
      {super.key,
      required this.controller,
      required this.channel,
      required this.upto,
      required this.height,
      this.name});

  @override
  State<NoteJoin> createState() => _NoteJoinState();
}

class _NoteJoinState extends State<NoteJoin>
    with SingleTickerProviderStateMixin, _Metered {
  int _notes = 0;

  @override
  CanvasController get meteredBy => widget.controller;

  /// Hidden from the Chain's ⋯, it reads nothing.
  @override
  bool get metering => widget.controller.chainMeters;

  @override
  void didUpdateWidget(NoteJoin old) {
    super.didUpdateWidget(old);
    meterAgain();
  }

  // Counted again as keys go down and up -- live keys sound nothing a
  // meter would wake for -- and once to begin with.
  @override
  void initState() {
    super.initState();
    tick();
    widget.controller.keysHeld.addListener(_keys);
  }

  void _keys() {
    if (mounted && metering) setState(tick);
  }

  @override
  void dispose() {
    widget.controller.keysHeld.removeListener(_keys);
    super.dispose();
  }

  @override
  void tick() {
    var e = widget.controller.instrumentOf(widget.channel);
    var part = e?.instrument;
    if (e == null || part == null) {
      _notes = 0;
      return;
    }
    var keys = widget.controller.audioState(e).keys;
    var effects = part.effects.take(widget.upto).toList();
    _notes = effects.isEmpty
        ? keys.length
        : {
            for (var k in keys)
              for (var (out, _) in liveKeys(effects, k, 96)) out,
          }.length;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.chainMeters) return const SizedBox(width: 4);
    var studio = MixerLook.of(context).studio;
    const dots = 6;
    return Tooltip(
      message: _notes == 0
          ? "No notes passing"
          : "$_notes note${_notes == 1 ? "" : "s"} passing",
      child: SizedBox(
        key: ValueKey("noteJoin-${widget.name ?? widget.upto}"),
        width: 16,
        height: widget.height,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < dots; i++)
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dots - 1 - i < _notes
                      ? midiColour
                      : studio.edge.withValues(alpha: 0.6),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// _ReadingBadge is a card's reading in its bar, a cool turn down.
class _ReadingBadge extends StatelessWidget {
  final String text;
  const _ReadingBadge({required this.text, super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 9.5,
                fontFeatures: [FontFeature.tabularFigures()],
                color: Color(0xFF7FC8F8))),
      );
}

/// _ABSwitch is a card's A|B: the one heard lit; a press hears the other.
class _ABSwitch extends StatelessWidget {
  final bool b;
  final VoidCallback onTap;
  const _ABSwitch({required this.b, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var studio = look.studio;
    Widget half(String letter, bool lit) => Container(
          width: 15,
          alignment: Alignment.center,
          color: lit ? look.colors.primary : null,
          child: Text(letter,
              style: TextStyle(
                  fontSize: 9.5,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: lit ? look.colors.onPrimary : studio.muted)),
        );
    return Tooltip(
      message: b
          ? "Hearing B: press to hear A again"
          : "Hearing A: press to try a second set of settings, B",
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 16,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: studio.edge)),
          clipBehavior: Clip.antiAlias,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            half("A", !b),
            Container(width: 1, color: studio.edge),
            half("B", b),
          ]),
        ),
      ),
    );
  }
}
