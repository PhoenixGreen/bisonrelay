part of 'mixer_plugins.dart';

// A chain's Macros panel of eight knobs, and a macro's Random and its other
// tools. Part of mixer_plugins.dart.

/// MacroPanel is a chain's Macros: eight knobs, each saying what it turns;
/// the one picked lists its targets and amounts, and any knob to add.
class MacroPanel extends StatefulWidget {
  final int index;
  final MixDevice device;

  /// knobs are every knob of the chain a macro can turn: the device's id,
  /// the setting's, and its name ("Reverb · Size").
  final List<(String, String, String)> knobs;
  final Color accent, ink;
  final void Function(MixDevice next, {bool transient}) onChanged;
  final VoidCallback onCommit;
  const MacroPanel(
      {required this.index,
      required this.device,
      required this.knobs,
      required this.accent,
      required this.ink,
      required this.onChanged,
      required this.onCommit,
      super.key});

  /// width is its card's: eight knobs across.
  static const double width = 14.0 + 58 * macroKnobs;

  @override
  State<MacroPanel> createState() => _MacroPanelState();
}

class _MacroPanelState extends State<MacroPanel> {
  int _picked = 0;

  String _nameOf(ModTarget m) =>
      widget.knobs
          .where((k) => k.$1 == m.device && k.$2 == m.param)
          .firstOrNull
          ?.$3 ??
      "Gone";

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var studio = look.studio;
    var device = widget.device;
    var index = widget.index;
    var mods = device.mods;
    var picked = _picked.clamp(0, macroKnobs - 1);
    var accent = widget.accent;
    List<(int, ModTarget)> turnedBy(int k) => [
          for (var (j, m) in mods.indexed)
            if (m.from == k) (j, m),
        ];
    Widget column(int k) {
      var p = macroParams[k];
      var turns = turnedBy(k);
      var on = k == picked;
      var first = turns.isEmpty ? null : _nameOf(turns.first.$2);
      var short = first == null
          ? "Not set"
          : first.contains(" · ")
              ? first.substring(first.lastIndexOf(" · ") + 3)
              : first;
      return GestureDetector(
        key: ValueKey("macroPick-$index-$k"),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _picked = k),
        child: Container(
          width: 56,
          padding: const EdgeInsets.only(top: 3, bottom: 3),
          decoration: BoxDecoration(
            color: on ? accent.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: on ? accent : Colors.transparent),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _Knob(
              key: ValueKey("device-$index-${p.id}"),
              label: "Macro ${k + 1}",
              text: p.reading(device.value(p.id)),
              value: device.value(p.id),
              initial: p.initial,
              range: _Range(p.min, p.max),
              size: 26,
              accent: accent,
              ink: widget.ink,
              onChanged: (v, {transient = false}) =>
                  widget.onChanged(device.withValue(p.id, v),
                      transient: transient),
              onCommit: widget.onCommit,
            ),
            const SizedBox(height: 2),
            Text(
                turns.length > 1 ? "$short +${turns.length - 1}" : short,
                key: ValueKey("macroTurns-$index-$k"),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 9.5,
                    color: first == null
                        ? studio.muted.withValues(alpha: 0.7)
                        : modulationColour)),
          ]),
        ),
      );
    }

    var turns = turnedBy(picked);
    var free = [
      for (var k in widget.knobs)
        if (!turns.any((t) => t.$2.device == k.$1 && t.$2.param == k.$2)) k,
    ];
    var byDevice = <String, List<(String, String, String)>>{};
    for (var k in free) {
      var cut = k.$3.lastIndexOf(" · ");
      var owner = cut < 0 ? k.$3 : k.$3.substring(0, cut);
      (byDevice[owner] ??= []).add(k);
    }
    var add = MenuAnchor(
      style: chainMenuStyle(look),
      menuChildren: [
        chainMenuHeading(look, "Macro ${picked + 1} turns…"),
        for (var MapEntry(key: owner, value: list) in byDevice.entries)
          SubmenuButton(
            key: ValueKey("macroAddDevice-$index-$owner"),
            style: chainMenuItemStyle(look),
            menuStyle: chainMenuStyle(look),
            menuChildren: [
              for (var k in list)
                chainMenuItem(look,
                    key: ValueKey("macroAddKnob-$index-${k.$1}-${k.$2}"),
                    text: k.$3.substring(owner.length).replaceFirst(" · ", ""),
                    onPressed: () => widget.onChanged(device.withMods([
                          ...mods,
                          ModTarget(k.$1, k.$2, 0.5, picked),
                        ]))),
            ],
            child: Text(owner, style: const TextStyle(fontSize: 11.5)),
          ),
        if (byDevice.isEmpty)
          chainMenuHeading(look, "Nothing more in this chain to turn"),
      ],
      builder: (context, menu, _) => InkWell(
        key: ValueKey("macroAdd-$index"),
        borderRadius: BorderRadius.circular(5),
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: studio.edge)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add, size: 13, color: studio.muted),
            const SizedBox(width: 3),
            Flexible(
              child: Text("Add a knob to turn",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: studio.text)),
            ),
            Icon(Icons.arrow_drop_down, size: 14, color: studio.muted),
          ]),
        ),
      ),
    );

    return SizedBox(
      width: MacroPanel.width - 16,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Onto more rows where it is narrower than all of them.
            Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 6,
                children: [
                  for (var k = 0; k < macroKnobs; k++) column(k),
                ]),
            const SizedBox(height: 6),
            Container(
              key: ValueKey("macroTurnsPanel-$index"),
              padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
              decoration: BoxDecoration(
                color: studio.inset,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: studio.edge),
              ),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Its add button under its name where the card is narrow.
                    Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Text("MACRO ${picked + 1} TURNS",
                              style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 0.8,
                                  fontWeight: FontWeight.w600,
                                  color: studio.muted)),
                          add,
                        ]),
                    const SizedBox(height: 4),
                    if (turns.isEmpty)
                      Text(
                          "Nothing yet. Add a knob for it to turn -- any "
                          "knob of this chain -- or right-click a knob and "
                          "pick Macro ${picked + 1}.",
                          style: TextStyle(
                              fontSize: 10.5,
                              height: 1.35,
                              color: studio.muted))
                    else
                      for (var (j, m) in turns)
                        SizedBox(
                          key: ValueKey("macroTarget-$index-$j"),
                          height: 26,
                          child: Row(children: [
                            Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: const BoxDecoration(
                                    color: modulationColour,
                                    shape: BoxShape.circle)),
                            Expanded(
                              child: Text(_nameOf(m),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11, color: studio.text)),
                            ),
                            SizedBox(
                              width: 120,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    activeTrackColor: modulationColour,
                                    thumbColor: modulationColour,
                                    overlayShape:
                                        SliderComponentShape.noOverlay,
                                    thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 5)),
                                child: Slider(
                                  key: ValueKey("macroDepth-$index-$j"),
                                  value: m.depth.clamp(-1.0, 1.0),
                                  min: -1,
                                  max: 1,
                                  onChanged: (v) => widget.onChanged(
                                      device.withMods([...mods]..[j] =
                                          m.withDepth(
                                              (v * 20).roundToDouble() / 20)),
                                      transient: true),
                                  onChangeEnd: (_) => widget.onCommit(),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 38,
                              child: Text(
                                  "${m.depth >= 0 ? "+" : "−"}${(m.depth.abs() * 100).round()}%",
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                      color: studio.text)),
                            ),
                            GestureDetector(
                              key: ValueKey("macroRemove-$index-$j"),
                              onTap: () => widget.onChanged(
                                  device.withMods([...mods]..removeAt(j))),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(Icons.close,
                                    size: 13, color: studio.muted),
                              ),
                            ),
                          ]),
                        ),
                  ]),
            ),
          ]),
    );
  }
}

/// _MacroTools are a macro's Random -- every knob somewhere new -- and its
/// Variation: its knobs' settings kept, by number, and brought back.
class _MacroTools extends StatelessWidget {
  final int index;
  final MixDevice device;
  final MixerLook look;
  final ValueChanged<MixDevice> onChanged;
  const _MacroTools(
      {required this.index,
      required this.device,
      required this.look,
      required this.onChanged,
      super.key});

  Map<String, double> get _now => {
        for (var p in macroParams) p.id: device.value(p.id),
      };

  bool _isNow(Map<String, double> v) =>
      macroParams.every((p) => (v[p.id] ?? 0) == device.value(p.id));

  @override
  Widget build(BuildContext context) {
    var studio = look.studio;
    var variations = device.variations;
    var current = variations.indexWhere(_isNow);
    Widget button(String key, String icon, String label, VoidCallback onTap) =>
        InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: studio.edge)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon.isNotEmpty) ...[
                ChainIcon(icon, size: 12, color: studio.muted),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: studio.text)),
              ),
            ]),
          ),
        );
    return SizedBox(
      width: MacroPanel.width - 16,
      child: Wrap(spacing: 4, runSpacing: 4, children: [
        button("macroRandom-$index", "dice", "Random", () {
          var dice = math.Random();
          var next = device;
          for (var p in macroParams) {
            next = next.withValue(p.id, dice.nextDouble());
          }
          onChanged(next);
        }),
        MenuAnchor(
          style: chainMenuStyle(look),
          builder: (context, menu, _) => button(
              "macroVariation-$index",
              "",
              current >= 0
                  ? "Variation ${current + 1} ▾"
                  : variations.isEmpty
                      ? "Variations ▾"
                      : "Variation · changed ▾",
              () => menu.isOpen ? menu.close() : menu.open()),
          menuChildren: [
            chainMenuHeading(look, "Variations"),
            for (var (i, v) in variations.indexed)
              chainMenuItem(look,
                  key: ValueKey("macroVariation-$index-$i"),
                  text: "Variation ${i + 1}",
                  current: i == current, onPressed: () {
                var next = device;
                for (var p in macroParams) {
                  next = next.withValue(p.id, v[p.id] ?? 0);
                }
                onChanged(next);
              }),
            if (variations.isNotEmpty) chainMenuDivider(look),
            chainMenuItem(look,
                key: ValueKey("macroVariationSave-$index"),
                text: "Keep these as Variation ${variations.length + 1}",
                onPressed: () =>
                    onChanged(device.withVariations([...variations, _now]))),
            if (current >= 0)
              chainMenuItem(look,
                  key: ValueKey("macroVariationForget-$index"),
                  text: "Forget Variation ${current + 1}",
                  onPressed: () => onChanged(device
                      .withVariations([...variations]..removeAt(current)))),
          ],
        ),
      ]),
    );
  }
}
