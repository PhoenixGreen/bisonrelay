import 'package:bruig/plugin_system/canvas/model/elements/character_face.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// character_face_panel.dart is the new Character Studio's Face step: the
// face's parts down the left -- its expression, where it looks, each region
// of it, its blush, and what it does by itself -- and the open part's
// settings on the right. See character_face.dart.

/// The Face step's parts: their ids, names, groups, and what each says.
const List<(String id, String name, String group, String says)> faceParts = [
  (
    "expressions",
    "Expressions",
    "Expression",
    "Pick one to start from, then change any part of it below. Keep the mix "
        "to use it again: every expression is a mix of the face's own shapes."
  ),
  (
    "look",
    "Look",
    "Expression",
    "Where the eyes look, and how the head tilts. Drag in the pad."
  ),
  (
    "brows",
    "Brows",
    "By region",
    "Each brow shape the face has, in any amount."
  ),
  (
    "eyes",
    "Eyes",
    "By region",
    "Closing, smiling, narrowing and widening, each eye on its own where it "
        "can."
  ),
  (
    "mouth",
    "Mouth",
    "By region",
    "Smiles and frowns, the open shapes the mouth makes when it speaks, and "
        "fangs."
  ),
  ("blush", "Blush", "By region", "Colour in the cheeks."),
  (
    "speak",
    "Speak",
    "Alive",
    "Type a line and the mouth says it, in whatever expression it wears."
  ),
  ("idle", "Blink and glance", "Alive", "What the face does by itself."),
];

/// _regionChanged is whether [region]'s shapes are not as the expression
/// started from has them.
bool _regionChanged(CharacterFace f, String region) {
  final from = f.expressions[f.name] ?? const FaceMix();
  return (faceUnits[region] ?? const [])
      .any((u) => f.mix.unit(u.$1) != from.unit(u.$1));
}

/// facePartChanged is whether part [id] of [f] is not as the expression it
/// was started from has it.
bool facePartChanged(CharacterFace f, String id) {
  final from = f.expressions[f.name] ?? const FaceMix();
  return switch (id) {
    "expressions" => f.name != "Neutral" || f.mix != const FaceMix(),
    "look" => f.mix.gazeX != from.gazeX ||
        f.mix.gazeY != from.gazeY ||
        f.mix.tilt != from.tilt,
    "brows" || "eyes" => _regionChanged(f, id),
    "mouth" => _regionChanged(f, "mouth") || _regionChanged(f, "teeth"),
    "blush" => f.mix.blush != from.blush,
    "idle" => !f.blinks || f.glances,
    _ => false,
  };
}

/// CharacterFaceList is the Face step's parts, picked to open.
class CharacterFaceList extends StatelessWidget {
  final CharacterFace face;
  final String selected;
  final ValueChanged<String> onSelect;

  /// onReset is given the face with a part put back: its mark, clicked.
  final ValueChanged<CharacterFace>? onReset;
  const CharacterFaceList(
      {required this.face,
      required this.selected,
      required this.onSelect,
      this.onReset,
      super.key});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    String? group;
    for (final (id, name, g, _) in faceParts) {
      if (g != group) {
        rows.add(StudioPartHeading(g, first: rows.isEmpty));
        group = g;
      }
      rows.add(StudioPartRow(
          id: id,
          name: name,
          keyPrefix: "facePart",
          changed: facePartChanged(face, id),
          selected: id == selected,
          onTap: () => onSelect(id),
          onReset: onReset == null
              ? null
              : () => onReset!(resetFacePart(face, id))));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: rows);
  }
}

/// CharacterFaceControls are part [part]'s settings.
class CharacterFaceControls extends StatefulWidget {
  final String part;
  final CharacterFace face;
  final ValueChanged<CharacterFace> onChanged;

  /// onSay has the stage say a line.
  final ValueChanged<String> onSay;
  const CharacterFaceControls(
      {required this.part,
      required this.face,
      required this.onChanged,
      required this.onSay,
      super.key});

  @override
  State<CharacterFaceControls> createState() => _CharacterFaceControlsState();
}

class _CharacterFaceControlsState extends State<CharacterFaceControls> {
  final TextEditingController _keepAs = TextEditingController();
  final TextEditingController _line =
      TextEditingController(text: "Hello! How are you today?");

  @override
  void dispose() {
    _keepAs.dispose();
    _line.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    final f = widget.face;
    final part = faceParts.where((p) => p.$1 == widget.part).firstOrNull ??
        faceParts.first;
    void put(FaceMix m) => widget.onChanged(f.copyWith(mix: m));
    String percent(double v) => "${(v * 100).round()}%";
    final from = f.expressions[f.name] ?? const FaceMix();
    Widget units(String region) => Column(children: [
          for (final (u, label)
              in faceUnits[region] ?? const <(String, String)>[])
            StudioSlider(
              key: ValueKey("face-unit-$u"),
              label: label,
              value: f.mix.unit(u),
              min: 0,
              max: 1,
              rest: from.unit(u),
              format: percent,
              onChanged: (v) => put(f.mix.withUnit(u, v)),
            ),
        ]);
    final body = switch (part.$1) {
      "expressions" => <Widget>[
          StudioPills<String>(
            key: const ValueKey("face-expr"),
            id: "face-expr",
            label: "Start from",
            value: f.name,
            options: [for (final n in f.expressions.keys) (n, n)],
            onChanged: (n) =>
                widget.onChanged(f.copyWith(name: n, mix: f.expressions[n])),
          ),
          const SizedBox(height: 12),
          const StudioLabel("Keep this mix"),
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey("faceKeepName"),
                controller: _keepAs,
                style: TextStyle(fontSize: 13, color: colors.onSurface),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: "Its name",
                  hintStyle:
                      TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _keep(),
              ),
            ),
            const SizedBox(width: 8),
            StudioPill(
                key: const ValueKey("faceKeep"),
                label: "Keep",
                filled: true,
                onTap: _keep),
          ]),
          if (f.kept.containsKey(f.name)) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: StudioPill(
                key: const ValueKey("faceForget"),
                label: "Forget ${f.name}",
                onTap: () => widget.onChanged(f.copyWith(
                    name: "Neutral", kept: {...f.kept}..remove(f.name))),
              ),
            ),
          ],
        ],
      "look" => <Widget>[
          const StudioLabel("Eyes on"),
          _LookPad(
            x: f.mix.gazeX,
            y: f.mix.gazeY,
            onChanged: (x, y) => put(f.mix.copyWith(gazeX: x, gazeY: y)),
          ),
          const SizedBox(height: 10),
          StudioSlider(
            key: const ValueKey("face-tilt"),
            label: "Head tilt",
            value: f.mix.tilt,
            min: -1,
            max: 1,
            rest: from.tilt,
            onChanged: (v) => put(f.mix.copyWith(tilt: v)),
          ),
        ],
      "brows" || "eyes" => <Widget>[units(part.$1)],
      "mouth" => <Widget>[
          units("mouth"),
          const SizedBox(height: 8),
          const StudioLabel("Teeth"),
          units("teeth"),
        ],
      "blush" => <Widget>[
          StudioSlider(
            key: const ValueKey("face-blush"),
            label: "Blush",
            value: f.mix.blush,
            min: 0,
            max: 1,
            rest: from.blush,
            format: percent,
            onChanged: (v) => put(f.mix.copyWith(blush: v)),
          ),
        ],
      "speak" => <Widget>[
          TextField(
            key: const ValueKey("faceLine"),
            controller: _line,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(fontSize: 13, color: colors.onSurface),
            decoration: const InputDecoration(
                isDense: true, border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: StudioPill(
              key: const ValueKey("faceSay"),
              label: "Say it",
              filled: true,
              onTap: () => widget.onSay(_line.text),
            ),
          ),
        ],
      _ => <Widget>[
          StudioPills<bool>(
            key: const ValueKey("face-blinks"),
            id: "face-blinks",
            label: "Blinks",
            value: f.blinks,
            options: const [(true, "Now and then"), (false, "Never")],
            onChanged: (v) => widget.onChanged(f.copyWith(blinks: v)),
          ),
          StudioPills<bool>(
            key: const ValueKey("face-glances"),
            id: "face-glances",
            label: "Glances about",
            value: f.glances,
            options: const [(true, "Yes"), (false, "No")],
            onChanged: (v) => widget.onChanged(f.copyWith(glances: v)),
          ),
        ],
    };
    final canReset = part.$1 != "speak" &&
        part.$1 != "expressions" &&
        facePartChanged(f, part.$1);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        StudioPanelHead(
          title: part.$2,
          says: part.$4,
          resetLabel: part.$1 == "idle" ? "As made" : "As ${f.name} has it",
          onReset: !canReset
              ? null
              : () => widget.onChanged(resetFacePart(f, part.$1)),
        ),
        const SizedBox(height: 12),
        ...body,
      ],
    );
  }

  /// _keep keeps the mix as an expression of the face's own, by the name
  /// typed.
  void _keep() {
    final name = _keepAs.text.trim();
    if (name.isEmpty) return;
    final f = widget.face;
    widget.onChanged(f.copyWith(name: name, kept: {...f.kept, name: f.mix}));
    _keepAs.clear();
  }
}

/// resetFacePart is [f] with part [id] put back as the expression it was
/// started from has it -- or, for the expressions, Neutral again.
CharacterFace resetFacePart(CharacterFace f, String id) {
  final from = f.expressions[f.name] ?? const FaceMix();
  var m = f.mix;
  switch (id) {
    case "expressions":
      return f.copyWith(name: "Neutral", mix: const FaceMix());
    case "look":
      m = m.copyWith(gazeX: from.gazeX, gazeY: from.gazeY, tilt: from.tilt);
    case "blush":
      m = m.copyWith(blush: from.blush);
    case "idle":
      return f.copyWith(blinks: true, glances: false);
    default:
      for (final region in id == "mouth" ? ["mouth", "teeth"] : [id]) {
        for (final (u, _) in faceUnits[region] ?? const <(String, String)>[]) {
          m = m.withUnit(u, from.unit(u));
        }
      }
  }
  return f.copyWith(mix: m);
}

/// _LookPad is where the eyes look: a square, the viewer at its middle, a
/// dot dragged about in it.
class _LookPad extends StatelessWidget {
  final double x, y;
  final void Function(double x, double y) onChanged;
  const _LookPad({required this.x, required this.y, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth.clamp(120.0, 240.0);
      void at(Offset p) => onChanged((p.dx / side * 2 - 1).clamp(-1.0, 1.0),
          (1 - p.dy / side * 2).clamp(-1.0, 1.0));
      return GestureDetector(
        key: const ValueKey("faceLookPad"),
        onPanDown: (d) => at(d.localPosition),
        onPanUpdate: (d) => at(d.localPosition),
        onDoubleTap: () => onChanged(0, 0),
        child: CustomPaint(
          size: Size(side, side),
          painter: _LookPadPainter(x, y,
              line: colors.outlineVariant,
              dot: colors.primary,
              fill: colors.surfaceContainerHigh),
        ),
      );
    });
  }
}

class _LookPadPainter extends CustomPainter {
  final double x, y;
  final Color line, dot, fill;
  _LookPadPainter(this.x, this.y,
      {required this.line, required this.dot, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final r =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
    canvas.drawRRect(r, Paint()..color = fill);
    final ink = Paint()
      ..color = line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(size.width / 2, 6),
        Offset(size.width / 2, size.height - 6), ink);
    canvas.drawLine(Offset(6, size.height / 2),
        Offset(size.width - 6, size.height / 2), ink);
    canvas.drawRRect(r, ink..style = PaintingStyle.stroke);
    final p = Offset((x + 1) / 2 * size.width, (1 - y) / 2 * size.height);
    canvas.drawCircle(p, 8, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_LookPadPainter old) =>
      old.x != x || old.y != y || old.dot != dot;
}
