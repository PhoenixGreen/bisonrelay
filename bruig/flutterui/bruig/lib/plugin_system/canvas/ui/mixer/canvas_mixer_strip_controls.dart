part of 'canvas_mixer.dart';

// Small controls a strip is built of: device slots and the small EQ curve on
// one, toggles, send dials, and the button adding a return. Part of
// canvas_mixer.dart.

/// _MiniCurve is an EQ drawn small, on a strip's EQ slot.
class _MiniCurve extends CustomPainter {
  final Eq eq;
  final ColorScheme colors;
  _MiniCurve(this.eq, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    var path = Path();
    for (var i = 0; i <= 40; i++) {
      var f = 20 * math.pow(1000, i / 40).toDouble();
      var db = eq.responseDb(f).clamp(-12.0, 12.0);
      var x = i / 40 * size.width;
      var y = size.height / 2 - db / 12 * (size.height / 2 - 1);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = eq.on ? colors.primary : colors.outline);
  }

  @override
  bool shouldRepaint(_MiniCurve old) =>
      !identical(old.eq, eq);
}

Widget _slot(MixerLook theme, String label, bool on, Widget trailing,
        VoidCallback onTap,
        {Key? key, VoidCallback? onRemove, Color? mark}) =>
    Material(
      color: theme.colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        // Right-clicked, a device's slot takes the device out.
        onSecondaryTap: onRemove,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: LayoutBuilder(
            builder: (context, box) => Row(children: [
              // Which side the device works on: teal for the motion's.
              if (mark != null) ...[
                Container(
                    width: 4,
                    height: 9,
                    decoration: BoxDecoration(
                        color: mark, borderRadius: BorderRadius.circular(1))),
                const SizedBox(width: 4),
              ],
              // A long label ("Add a device", a device's own name) fades at the
              // slot's edge rather than running out of it.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth * 0.7),
                child: Text(label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                        color: on
                            ? theme.colors.onSurface
                            : theme.colors.onSurfaceVariant)),
              ),
              const SizedBox(width: 4),
              // Scaled down rather than overflowing: "−12.0 dBTP" beside its label
              // is wider than a strip in some fonts.
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(fit: BoxFit.scaleDown, child: trailing),
                ),
              ),
            ]),
          ),
        ),
      ),
    );

class _Toggle extends StatelessWidget {
  final String label;

  /// icon, given, is drawn rather than [label].
  final IconData? icon;
  final bool on;
  final Color onColor;

  /// onInk is the label's colour while it is on; white by default.
  final Color? onInk;
  final double height;
  final double fontSize;
  final MixerLook theme;
  final String tooltip;
  final VoidCallback onTap;

  const _Toggle({
    this.onInk,
    this.height = 20,
    this.fontSize = 10,
    this.icon,
    required this.label,
    required this.on,
    required this.onColor,
    required this.theme,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: on ? onColor : theme.colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onTap,
            child: SizedBox(
              height: height,
              child: Center(
                child: icon != null
                    ? Icon(icon,
                        size: height * 0.62,
                        color: on
                            ? onInk ?? const Color(0xFFFFFFFF)
                            : theme.colors.onSurfaceVariant)
                    : Text(label,
                        style: TextStyle(
                            fontSize: fontSize,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            color: on
                                ? onInk ?? const Color(0xFFFFFFFF)
                                : theme.colors.onSurfaceVariant)),
              ),
            ),
          ),
        ),
      );
}

/// _Sends is a channel's sends: a dial for each return, by its letter,
/// dragged up for more, double-clicked for none.
class _Sends extends StatelessWidget {
  final ChannelMix mix;
  final List<ReturnChannel> returns;
  final MixerLook theme;
  final _MixWrite<ChannelMix> onChanged;
  final VoidCallback onCommit;

  /// narrow is a narrow column's: smaller dials, two to a row.
  final bool narrow;

  const _Sends({
    this.narrow = false,
    required this.mix,
    required this.returns,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
  });

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: 4,
        runSpacing: 2,
        children: [
          for (var (i, r) in returns.indexed)
            _SendDial(
              key: ValueKey("send-${r.id}"),
              size: narrow ? 18 : 24,
              letter: returnLetter(i),
              name: r.name,
              db: mix.sendDb(r.id),
              theme: theme,
              onChanged: (db, {transient = false}) =>
                  onChanged(mix.withSend(r.id, db), transient: transient),
              onCommit: onCommit,
            ),
        ],
      );
}

/// sendPosition and sendDb map a send onto its dial: nothing at the bottom,
/// then minus sixty to plus six round the rest of the travel.
double sendPosition(double? db) =>
    db == null ? 0 : ((db + 60) / 66).clamp(0.02, 1.0);

double? sendDbAt(double position) =>
    position <= 0.02 ? null : -60 + position.clamp(0.0, 1.0) * 66;

class _SendDial extends StatefulWidget {
  final String letter;
  final String name;
  final double? db;
  final MixerLook theme;
  final void Function(double? db, {bool transient}) onChanged;
  final VoidCallback onCommit;
  final double size;

  const _SendDial({
    this.size = 24,
    required this.letter,
    required this.name,
    required this.db,
    required this.theme,
    required this.onChanged,
    required this.onCommit,
    super.key,
  });

  @override
  State<_SendDial> createState() => _SendDialState();
}

class _SendDialState extends State<_SendDial> {
  /// _from is where the drag started, and _was where the dial was then: the
  /// turn is measured from the press, not summed from each move, which loses
  /// moves that arrive between two frames.
  double _from = 0, _was = 0;

  @override
  Widget build(BuildContext context) {
    var db = widget.db;
    return Tooltip(
      message: "Send to ${widget.letter}"
          "${widget.name.isEmpty ? "" : " · ${widget.name}"}: "
          "${db == null ? "nothing" : "${dbText(db)} dB"}. Drag up for "
          "more; double-click for none.",
      child: GestureDetector(
        supportedDevices: dragPointers,
        dragStartBehavior: DragStartBehavior.down,
        onVerticalDragStart: (d) {
          _from = d.globalPosition.dy;
          _was = sendPosition(widget.db);
        },
        onVerticalDragUpdate: (d) => widget.onChanged(
            sendDbAt(_was + (_from - d.globalPosition.dy) / 120),
            transient: true),
        onVerticalDragEnd: (_) => widget.onCommit(),
        onDoubleTap: () => widget.onChanged(null),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CustomPaint(
              size: Size.square(widget.size),
              painter: _ArcKnob(sendPosition(db), widget.theme.studio),
            ),
            Text(widget.letter,
                style: TextStyle(
                    fontSize: 9,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: widget.theme.studio.text)),
          ]),
        ),
      ),
    );
  }
}

/// _ArcKnob is a dial drawn as the studio draws them: a track round seven
/// o'clock to five, lit in the "on" colour as far as it is turned.
class _ArcKnob extends CustomPainter {
  final double value;
  final StudioColors colors;
  _ArcKnob(this.value, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    var c = size.center(Offset.zero);
    var r = size.shortestSide / 2 - 2;
    var rect = Rect.fromCircle(center: c, radius: r);
    const start = math.pi * 0.75, sweep = math.pi * 1.5;
    var track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = colors.raised;
    canvas.drawArc(rect, start, sweep, false, track);
    if (value > 0.02) {
      canvas.drawArc(
          rect, start, sweep * value, false, track..color = colors.on);
    }
    var a = start + sweep * value;
    canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * 3,
        c + Offset(math.cos(a), math.sin(a)) * r,
        Paint()
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..color = colors.text);
  }

  @override
  bool shouldRepaint(_ArcKnob old) => old.value != value;
}

class _AddReturn extends StatelessWidget {
  final MixerLook theme;
  final VoidCallback onAdd;
  const _AddReturn({required this.theme, required this.onAdd});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: "Add a return: a reverb every channel can send to",
        child: InkWell(
          key: const ValueKey("addReturn"),
          onTap: onAdd,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.studio.edge),
            ),
            // Shrunk to fit, in a mixer at its least.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, size: 18, color: theme.studio.muted),
                const SizedBox(height: 6),
                RotatedBox(
                  quarterTurns: 3,
                  child: Text("Return",
                      style:
                          TextStyle(fontSize: 11, color: theme.studio.muted)),
                ),
              ]),
            ),
          ),
        ),
      );
}

/// _motionDeviceSlots are [e]'s motion devices as slots in its strip's
/// devices band, before its sound's: its Instances first, where it is
/// reused, then its chain, each marked teal. Clicked, the Chain opens.
List<Widget> _motionDeviceSlots(
    CanvasController controller, MixerLook theme, CanvasElement e) {
  var m = e.base.motion;
  void open() {
    controller.selectOnly(e.id);
    controller.showChain(motion: true);
  }

  var colors = theme.colors;
  Widget dot(bool on) => Icon(Icons.circle,
      size: 7, color: on ? theme.studio.on : colors.outline);
  return [
    if (m.instances != null)
      _slot(theme, MotionDeviceKind.instances.label, true,
          Text("×${m.instances!.count}",
              style: TextStyle(fontSize: 10, color: theme.studio.muted)),
          open,
          mark: motionColour, key: ValueKey("motionDeviceSlot-${e.id}-instances")),
    for (var (i, d) in m.devices.indexed)
      _slot(theme, d.kind.label, d.on && !m.off, dot(d.on && !m.off), open,
          mark: motionColour, key: ValueKey("motionDeviceSlot-${e.id}-$i")),
  ];
}
