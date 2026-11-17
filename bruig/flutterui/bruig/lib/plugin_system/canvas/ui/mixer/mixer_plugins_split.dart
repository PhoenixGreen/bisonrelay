part of 'mixer_plugins.dart';

// A split's branches, a column each, with the picture of the sound dividing and
// joining and the buttons on its rows. Part of mixer_plugins.dart.

/// SplitBranches is a split's branches, a column each: name, return level,
/// mute, its devices and an add; in parallel, adding and removing branches.
class SplitBranches extends StatefulWidget {
  final MixDevice device;

  /// moved are its branches' knobs a modulator moves, each as
  /// "branch/device id/setting": a pink ring round them.
  final Set<String> moved;
  final Color ink, accent;
  final void Function(List<SplitBranch> branches, {bool transient}) onChanged;

  /// onSet changes one of the split's own settings: how it splits, and
  /// where lows give way to highs.
  final void Function(String param, double value, {bool transient}) onSet;
  final VoidCallback onCommit;
  const SplitBranches(
      {required this.device,
      required this.ink,
      required this.accent,
      required this.onChanged,
      required this.onSet,
      required this.onCommit,
      this.moved = const {},
      super.key});

  /// width is the card's: its branches listed, and the one open beside.
  static const double width = 520;

  /// _addable are the kinds a branch takes: what changes sound, not a
  /// split, a modulator or a listener.
  static List<DeviceKind> get _addable => [
        for (var k in DeviceKind.values)
          if (k != DeviceKind.split &&
              !k.modulates &&
              !listensOnly(k) &&
              k != DeviceKind.vocoder)
            k
      ];

  @override
  State<SplitBranches> createState() => _SplitBranchesState();
}

/// _SplitBranchesState draws the sound dividing, how, a row a branch, and
/// the picked branch open beside them.
class _SplitBranchesState extends State<SplitBranches> {
  int _open = 0;

  @override
  Widget build(BuildContext context) {
    var device = widget.device;
    var look = MixerLook.of(context);
    var studio = look.studio;
    var ink = widget.ink, accent = widget.accent;
    var mode = device.value("mode").round();
    var parallel = mode == 0;
    var names = splitBranchNames(mode, device.branches.length);
    var branches = [
      for (var i = 0; i < names.length; i++)
        i < device.branches.length ? device.branches[i] : const SplitBranch(),
    ];
    var open = branches.isEmpty ? null : _open.clamp(0, branches.length - 1);
    var small = TextStyle(fontSize: 10.5, color: studio.text);
    void set(int i, SplitBranch b, {bool transient = false}) {
      var next = [...branches];
      next[i] = b;
      widget.onChanged(next, transient: transient);
    }

    Widget row(int i, SplitBranch b) {
      var on = i == open;
      var level = ((b.gainDb + 60) / 72).clamp(0.0, 1.0);
      return GestureDetector(
        key: ValueKey("splitBranch-$i"),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _open = i),
        child: Container(
          height: 26,
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: on ? accent.withValues(alpha: 0.12) : studio.inset,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: on ? accent : studio.edge),
          ),
          child: Row(children: [
            Container(
              width: 5,
              height: 18,
              decoration: BoxDecoration(
                  color: studio.display,
                  borderRadius: BorderRadius.circular(2)),
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: b.mute ? 0 : level,
                child: Container(
                    decoration: BoxDecoration(
                        color: const Color(0xFF5BC46B),
                        borderRadius: BorderRadius.circular(2))),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 54,
              child: Text(names[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small.copyWith(
                      color: b.mute ? studio.muted : studio.text,
                      fontWeight: on ? FontWeight.w600 : null)),
            ),
            Expanded(
              // As many of its devices as fit; the rest cut off at its end.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(children: [
                  for (var d in b.devices)
                    Container(
                      margin: const EdgeInsets.only(right: 3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                          color: studio.raised,
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(d.kind.label,
                          maxLines: 1,
                          style: TextStyle(
                              fontSize: 9.5,
                              color: d.on ? studio.muted : studio.edge)),
                    ),
                  if (b.devices.isEmpty)
                    Text("straight through",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9.5, color: studio.muted)),
                ]),
              ),
            ),
            _RowButton(
              key: ValueKey("splitMute-$i"),
              label: "M",
              on: b.mute,
              tip: b.mute ? "Hear this branch again" : "Silence this branch",
              onTap: () => set(i, b.copyWith(mute: !b.mute)),
            ),
            if (parallel && branches.length > 1)
              _RowButton(
                key: ValueKey("splitRemove-$i"),
                icon: Icons.close,
                tip: "Take this branch away",
                onTap: () {
                  if (_open >= i && _open > 0) _open--;
                  widget.onChanged([...branches]..removeAt(i));
                },
              ),
          ]),
        ),
      );
    }

    Widget editor(int i, SplitBranch b) => Container(
          key: ValueKey("splitEditor-$i"),
          decoration: BoxDecoration(
            color: studio.inset,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: studio.edge),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(6),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(names[i].toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w600,
                              color: studio.muted)),
                    ),
                    SizedBox(
                      width: 52,
                      child: _Knob(
                        key: ValueKey("splitGain-$i"),
                        label: "Level",
                        text: "${b.gainDb.toStringAsFixed(1)} dB",
                        value: b.gainDb,
                        initial: 0,
                        range: const _Range(-60, 12),
                        size: 24,
                        accent: accent,
                        ink: ink,
                        onChanged: (v, {transient = false}) => set(
                            i, b.copyWith(gainDb: (v * 2).roundToDouble() / 2),
                            transient: transient),
                        onCommit: widget.onCommit,
                      ),
                    ),
                  ]),
                  for (var (j, d) in b.devices.indexed)
                    Container(
                      key: ValueKey("splitDevice-$i-$j"),
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
                      decoration: BoxDecoration(
                        color: studio.panel,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Row(children: [
                          GestureDetector(
                            key: ValueKey("splitDevicePower-$i-$j"),
                            onTap: () => set(
                                i,
                                b.copyWith(
                                    devices: [...b.devices]..[j] =
                                        d.switched(!d.on))),
                            child: Icon(
                                d.on ? Icons.circle : Icons.circle_outlined,
                                size: 9,
                                color: d.on
                                    ? const Color(0xFF5BC46B)
                                    : studio.muted),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                              child: Text(d.kind.label.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 9.5,
                                      letterSpacing: 0.6,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          d.on ? studio.text : studio.muted))),
                          GestureDetector(
                            key: ValueKey("splitDeviceRemove-$i-$j"),
                            onTap: () => set(
                                i,
                                b.copyWith(
                                    devices: [...b.devices]..removeAt(j))),
                            child: Icon(Icons.close,
                                size: 12, color: studio.muted),
                          ),
                        ]),
                        const SizedBox(height: 3),
                        Wrap(spacing: 2, runSpacing: 2, children: [
                          for (var p in d.kind.params)
                            if (!p.isChoice)
                              SizedBox(
                                width: 46,
                                child: _Knob(
                                  key: ValueKey("splitKnob-$i-$j-${p.id}"),
                                  modulated: widget.moved.contains(
                                      "$i/${deviceIdAt(b.devices, j)}/${p.id}"),
                                  label: p.label,
                                  text: p.reading(d.value(p.id)),
                                  value: d.value(p.id),
                                  initial: p.initial,
                                  range: ParamDevice._range(p),
                                  size: 22,
                                  reading: false,
                                  accent: accent,
                                  ink: ink,
                                  bipolar: p.min < 0 && p.max > 0,
                                  onChanged: (v, {transient = false}) => set(
                                      i,
                                      b.copyWith(
                                          devices: [...b.devices]..[j] =
                                              d.withValue(p.id, v)),
                                      transient: transient),
                                  onCommit: widget.onCommit,
                                ),
                              ),
                        ]),
                      ]),
                    ),
                  const SizedBox(height: 6),
                  CanvasDropdown<DeviceKind?>(
                    key: ValueKey("splitAdd-$i"),
                    label: "",
                    value: null,
                    width: 210,
                    grow: false,
                    options: [
                      (null, "Add a device…"),
                      for (var k in SplitBranches._addable) (k, k.label),
                    ],
                    onChanged: (k) {
                      if (k == null) return;
                      set(i, b.copyWith(devices: [...b.devices, MixDevice(k)]));
                    },
                  ),
                ]),
          ),
        );

    var crossover = device.kind.param("crossover");
    var left = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: studio.edge.withValues(alpha: 0.8)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: CustomPaint(
                key: const ValueKey("splitPicture"),
                painter: _SplitPicture(
                    mode: mode,
                    names: names,
                    muted: [for (var b in branches) b.mute],
                    picked: open,
                    crossover: device.value("crossover"),
                    accent: accent,
                    back: studio.display),
              ),
            ),
          ),
          const SizedBox(height: 6),
          DeviceChoices(
            key: const ValueKey("splitMode"),
            options: [
              for (var (k, label)
                  in const ["Parallel", "Mid/Side", "L/R", "Low/High"].indexed)
                (
                  ValueKey("splitMode-$k"),
                  label,
                  mode == k,
                  () {
                    widget.onSet("mode", k.toDouble());
                    widget.onCommit();
                  }
                ),
            ],
          ),
          if (mode == 3) ...[
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Text("Lows give way at",
                    style: TextStyle(fontSize: 10.5, color: studio.muted)),
              ),
              SizedBox(
                width: 56,
                child: _Knob(
                  key: const ValueKey("splitCrossover"),
                  label: "Crossover",
                  text: crossover.reading(device.value("crossover")),
                  value: device.value("crossover"),
                  initial: crossover.initial,
                  range: ParamDevice._range(crossover),
                  size: 22,
                  accent: accent,
                  ink: ink,
                  onChanged: (v, {transient = false}) =>
                      widget.onSet("crossover", v, transient: transient),
                  onCommit: widget.onCommit,
                ),
              ),
            ]),
          ],
          const SizedBox(height: 6),
          for (var (i, b) in branches.indexed) row(i, b),
          if (parallel && branches.length < maxBranches)
            Align(
              alignment: Alignment.centerLeft,
              child: _RowButton(
                key: const ValueKey("splitAddBranch"),
                label: "+ Branch",
                tip: "Another branch, with its own devices",
                onTap: () {
                  setState(() => _open = branches.length);
                  widget.onChanged([...branches, const SplitBranch()]);
                },
              ),
            ),
        ]);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: SplitBranches.width - 16),
      child: LayoutBuilder(
        builder: (context, box) =>
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: math.min(240.0, (box.maxWidth - 8) / 2), child: left),
          const SizedBox(width: 8),
          Expanded(
            child: open == null
                ? Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Text("Add a branch to give it devices of its own.",
                        style: TextStyle(fontSize: 10.5, color: studio.muted)),
                  )
                : editor(open, branches[open]),
          ),
        ]),
      ),
    );
  }
}

/// _RowButton is a small boxed button on a split's rows, lit where [on].
class _RowButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool on;
  final String tip;
  final VoidCallback onTap;
  const _RowButton(
      {this.label,
      this.icon,
      this.on = false,
      required this.tip,
      required this.onTap,
      super.key});

  @override
  Widget build(BuildContext context) {
    var studio = MixerLook.of(context).studio;
    return Tooltip(
      message: tip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 18,
          margin: const EdgeInsets.only(left: 3),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 2 : 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? const Color(0xFFE0A84F) : studio.raised,
            borderRadius: BorderRadius.circular(4),
            border:
                Border.all(color: on ? const Color(0xFFE0A84F) : studio.edge),
          ),
          child: label == null
              ? Icon(icon, size: 12, color: studio.muted)
              : Text(label!,
                  style: TextStyle(
                      fontSize: 10,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: on ? Colors.black : studio.text)),
        ),
      ),
    );
  }
}

/// _SplitPicture is a split's sound dividing into [names] and joining
/// again, the [picked] branch bright and a muted one faint; split by
/// frequency, the lows' and highs' curves crossing at [crossover].
class _SplitPicture extends CustomPainter {
  final int mode;
  final List<String> names;
  final List<bool> muted;
  final int? picked;
  final double crossover;
  final Color accent, back;
  _SplitPicture(
      {required this.mode,
      required this.names,
      required this.muted,
      required this.picked,
      required this.crossover,
      required this.accent,
      required this.back});

  static const _colours = [
    Color(0xFFE0A84F),
    Color(0xFF9A92EA),
    Color(0xFF5CC6B8),
    Color(0xFFE57AA8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = back);
    void label(String text, double x, double y, Color colour) {
      var tp = paintedLabel(text, TextStyle(fontSize: 9, color: colour));
      tp.paint(canvas, Offset(x, y - tp.height / 2));
    }

    if (mode == 3) {
      // The lows' and highs' curves, over 20 Hz to 20 kHz, crossing.
      var xc = math.log(crossover.clamp(20, 20000) / 20) / math.log(1000);
      for (var (k, low) in [true, false].indexed) {
        var p = Path();
        for (var i = 0; i <= 80; i++) {
          var x = i / 80;
          var d = (x - xc) * 9;
          var g = low ? 1 / (1 + math.exp(d)) : 1 / (1 + math.exp(-d));
          var y = h - 6 - g * (h - 16);
          i == 0 ? p.moveTo(x * w, y) : p.lineTo(x * w, y);
        }
        var colour = _colours[k]
            .withValues(alpha: k < muted.length && muted[k] ? 0.3 : 1);
        canvas.drawPath(
            p,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = picked == k ? 2.2 : 1.6
              ..color = colour);
        if (k < names.length) {
          label(names[k], low ? 6 : w - 30, 10, colour);
        }
      }
      canvas.drawLine(Offset(xc * w, 4), Offset(xc * w, h - 4),
          Paint()..color = Colors.white.withValues(alpha: 0.25));
      return;
    }
    var n = math.max(1, names.length);
    for (var i = 0; i < n; i++) {
      var y = names.isEmpty ? h / 2 : (i + 0.5) * h / n;
      var colour = _colours[i % _colours.length]
          .withValues(alpha: i < muted.length && muted[i] ? 0.28 : 1);
      var path = Path()
        ..moveTo(0, h / 2)
        ..cubicTo(w * 0.22, h / 2, w * 0.14, y, w * 0.32, y)
        ..lineTo(w * 0.68, y)
        ..cubicTo(w * 0.86, y, w * 0.78, h / 2, w, h / 2);
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = picked == i ? 2.4 : 1.5
            ..color = colour);
      if (i < names.length) label(names[i], w * 0.36, y - 6, colour);
    }
  }

  @override
  bool shouldRepaint(_SplitPicture old) =>
      old.mode != mode ||
      old.picked != picked ||
      old.crossover != crossover ||
      old.names.length != names.length ||
      old.muted.toString() != muted.toString();
}
