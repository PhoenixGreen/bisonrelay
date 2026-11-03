import 'package:bruig/plugin_system/canvas/model/elements/character_move.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:flutter/material.dart';

// character_move_panel.dart is the new Character Studio's Move step: how the
// character stands -- its stance, its hands, its feet, its body turned by
// hand -- down the left, and the open part's settings on the right. See
// character_move.dart, and vrm_pose.dart for how it is stood.

/// The Move step's parts: their ids, names, groups, and what each says.
const List<(String id, String name, String group, String says)> moveParts = [
  (
    "stance",
    "Stances",
    "Pose",
    "How it stands. Each stance is placed by where its hands and feet go, "
        "worked out for this body, so it fits however long its arms and legs "
        "are."
  ),
  (
    "hands",
    "Hands",
    "Pose",
    "The shape of each hand. Relaxed is as the stance has it."
  ),
  (
    "feet",
    "Feet and ankles",
    "Pose",
    "Each foot turned at the ankle: pointed or flexed, rolled in or out, the "
        "heel raised onto the ball of the foot, and the toes."
  ),
  (
    "body",
    "Body",
    "Pose",
    "The body turned by hand, over the stance: leaning, twisting, bending, "
        "the head turned, crouched, the weight on one side."
  ),
];

/// movePartChanged is whether part [id] of [m] is not as made.
bool movePartChanged(CharacterMove m, String id) => switch (id) {
      "stance" => m.stance != "Relaxed",
      "hands" => m.handL != "relaxed" || m.handR != "relaxed",
      "feet" => m.footL.isNotEmpty || m.footR.isNotEmpty,
      "body" => m.body.isNotEmpty,
      _ => false,
    };

/// resetMovePart is [m] with part [id] put back as made.
CharacterMove resetMovePart(CharacterMove m, String id) => switch (id) {
      "stance" => m.copyWith(stance: "Relaxed"),
      "hands" => m.copyWith(handL: "relaxed", handR: "relaxed"),
      "feet" => m.copyWith(footL: const {}, footR: const {}),
      "body" => m.copyWith(body: const {}),
      _ => m,
    };

/// CharacterMoveList is the Move step's parts, picked to open.
class CharacterMoveList extends StatelessWidget {
  final CharacterMove move;
  final String selected;
  final ValueChanged<String> onSelect;

  /// onReset is given the move with a part put back: its mark, clicked.
  final ValueChanged<CharacterMove>? onReset;
  const CharacterMoveList(
      {required this.move,
      required this.selected,
      required this.onSelect,
      this.onReset,
      super.key});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    String? group;
    for (final (id, name, g, _) in moveParts) {
      if (g != group) {
        rows.add(StudioPartHeading(g, first: rows.isEmpty));
        group = g;
      }
      rows.add(StudioPartRow(
          id: id,
          name: name,
          keyPrefix: "movePart",
          changed: movePartChanged(move, id),
          selected: id == selected,
          onTap: () => onSelect(id),
          onReset: onReset == null
              ? null
              : () => onReset!(resetMovePart(move, id))));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: rows);
  }
}

/// CharacterMoveControls are part [part]'s settings.
class CharacterMoveControls extends StatelessWidget {
  final String part;
  final CharacterMove move;
  final ValueChanged<CharacterMove> onChanged;
  const CharacterMoveControls(
      {required this.part,
      required this.move,
      required this.onChanged,
      super.key});

  @override
  Widget build(BuildContext context) {
    final m = move;
    final p =
        moveParts.where((x) => x.$1 == part).firstOrNull ?? moveParts.first;
    Widget slider(String key, String label, double value, double min,
            ValueChanged<double> change) =>
        StudioSlider(
          key: ValueKey(key),
          label: label,
          value: value,
          min: min,
          max: 1,
          rest: 0,
          onChanged: change,
        );
    final body = switch (p.$1) {
      "stance" => <Widget>[
          StudioPills<String>(
            key: const ValueKey("move-stance"),
            id: "move-stance",
            label: "Stands",
            value: m.stance,
            options: [for (final s in moveStances) (s, s)],
            onChanged: (s) => onChanged(m.copyWith(stance: s)),
          ),
        ],
      "hands" => <Widget>[
          for (final (k, label) in const [
            ("L", "Left hand"),
            ("R", "Right hand")
          ])
            StudioPills<String>(
              key: ValueKey("move-hand$k"),
              id: "move-hand$k",
              label: label,
              value: k == "L" ? m.handL : m.handR,
              options: handShapes,
              onChanged: (h) => onChanged(
                  k == "L" ? m.copyWith(handL: h) : m.copyWith(handR: h)),
            ),
        ],
      "feet" => <Widget>[
          for (final (k, label) in const [
            ("L", "Left foot"),
            ("R", "Right foot")
          ]) ...[
            StudioLabel(label),
            for (final (f, name) in moveFoot)
              slider(
                  "move-foot$k-$f",
                  name,
                  m.footOf(k, f),
                  f == "heel" || f == "toes" ? 0 : -1,
                  (v) => onChanged(m.withFoot(k, f, v))),
            const SizedBox(height: 8),
          ],
        ],
      _ => <Widget>[
          for (final (b, name) in moveBody)
            slider("move-body-$b", name, m.bodyOf(b), -1,
                (v) => onChanged(m.withBody(b, v))),
        ],
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        StudioPanelHead(
          title: p.$2,
          says: p.$4,
          onReset: movePartChanged(m, p.$1)
              ? () => onChanged(resetMovePart(m, p.$1))
              : null,
        ),
        const SizedBox(height: 12),
        ...body,
      ],
    );
  }
}
