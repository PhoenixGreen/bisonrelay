import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show newElementId;
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/play_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// game_counts_settings.dart is the numbers a game keeps -- coins, lives,
// keys -- in the Game panel with nothing picked: a small card each, saying
// what it is, what happens when it reaches a number and where it starts,
// opened to change it. A pickup or a hazard adds to them and takes from
// them; a Counter element shows one.

/// _justAdded is the count added last, opened for its name to be given.
String? _justAdded;

/// gameCountCards are the game's counts as cards, and a way to add another.
List<Widget> gameCountCards(CanvasController controller) {
  var counts = controller.document.counts;
  return [
    for (var (i, c) in counts.indexed)
      _CountCard(
        key: ValueKey("count-card-${c.id}"),
        controller: controller,
        index: i,
        count: c,
        initiallyOpen: c.id == _justAdded,
      ),
    CanvasTextButton(
      key: const ValueKey("countAdd"),
      label: "Count",
      icon: Icons.add,
      onPressed: () {
        var c = GameCount(newElementId(), "Count ${counts.length + 1}");
        _justAdded = c.id;
        controller.apply(controller.document
            .copyWith(counts: [...controller.document.counts, c]));
      },
    ),
  ];
}

/// countRule is what happens to [c], in a line: "At 0: start again on
/// Title" -- and whether a Counter shows it.
String countRule(CanvasDocument doc, GameCount c) {
  String scene(String id) {
    var i = doc.sceneIndexNamed(id);
    return i < 0 ? "a scene" : doc.nameOf(i);
  }

  var then = c.then;
  var count = doc.counts.where((o) => o.id == then.count).firstOrNull?.name;
  var does = switch (then.does) {
    GameDoes.nothing => "nothing",
    GameDoes.add => "add ${then.amount} to ${count ?? "a count"}",
    GameDoes.take => "take ${then.amount} from ${count ?? "a count"}",
    GameDoes.scene => "go to ${scene(then.scene)}",
    GameDoes.next => "on to the next scene",
    GameDoes.restart => doc.gameStart.isEmpty
        ? "start again"
        : "start again on ${scene(doc.gameStart)}",
    GameDoes.stop => "the game ends",
  };
  var shown = [
    ...doc.elements,
    ...?doc.master?.elements,
  ].any((e) =>
      e is CounterElement &&
      e.source == CounterSource.game &&
      e.gameCount == c.id);
  return [
    if (c.reach case var at?) "At $at: $does",
    if (shown) "shown by a counter",
  ].join(" · ").ifBlank("Kept, for a counter to show");
}

extension on String {
  String ifBlank(String other) => isEmpty ? other : this;
}

class _CountCard extends StatefulWidget {
  final CanvasController controller;
  final int index;
  final GameCount count;
  final bool initiallyOpen;
  const _CountCard(
      {required this.controller,
      required this.index,
      required this.count,
      this.initiallyOpen = false,
      super.key});

  @override
  State<_CountCard> createState() => _CountCardState();
}

class _CountCardState extends State<_CountCard> {
  late bool _open = widget.initiallyOpen;

  static const _tints = [
    Color(0xFFF2C94C),
    Color(0xFFE5484D),
    Color(0xFF30A46C),
    Color(0xFF3D7EFF),
    Color(0xFFB07CFF),
  ];

  @override
  Widget build(BuildContext context) {
    var controller = widget.controller;
    var doc = controller.document;
    var c = widget.count;
    var i = widget.index;
    var colors = ThemeNotifier.of(context).colors;
    void write(GameCount next) {
      controller.beginInteraction();
      controller.apply(
          controller.document
              .copyWith(counts: [...controller.document.counts]..[i] = next),
          transient: true);
    }

    void commit() => controller.endInteraction();
    void now(GameCount next) {
      write(next);
      commit();
    }

    var tint = _tints[i % _tints.length];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          key: ValueKey("count-open-$i"),
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: tint, borderRadius: BorderRadius.circular(6)),
                child: Text(
                    c.name.isEmpty
                        ? "?"
                        : c.name.characters.first.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111111))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name.isEmpty ? "Count" : c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface)),
                      Text(countRule(doc, c),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10.5, color: colors.onSurfaceVariant)),
                    ]),
              ),
              const SizedBox(width: 8),
              Text("${c.start}",
                  style: TextStyle(
                      fontSize: 13,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: colors.onSurface)),
            ]),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            child: CanvasControlGroup(
              label: c.name,
              hideCaption: true,
              rule: false,
              children: [
                CanvasTextField(
                  key: ValueKey("count-name-$i"),
                  label: "Name",
                  value: c.name,
                  onChanged: (v) => write(c.copyWith(name: v)),
                  onCommit: commit,
                ),
                CanvasNumberField(
                  key: ValueKey("count-start-$i"),
                  label: "Starts at",
                  value: c.start.toDouble(),
                  min: -1000000,
                  max: 1000000,
                  width: 64,
                  onChanged: (v) => write(c.copyWith(start: v.round())),
                  onCommit: commit,
                ),
                CanvasToggle(
                  key: ValueKey("count-reaches-$i"),
                  label: "Does something at a number",
                  value: c.reach != null,
                  onChanged: (on) => now(on
                      ? c.copyWith(
                          reach: c.start > 0 ? 0 : 10,
                          then: c.then.does == GameDoes.nothing
                              ? const GameEffect(does: GameDoes.restart)
                              : null)
                      : c.copyWith(noReach: true)),
                ),
                if (c.reach case var at?) ...[
                  CanvasNumberField(
                    key: ValueKey("count-at-$i"),
                    label: "At",
                    value: at.toDouble(),
                    min: -1000000,
                    max: 1000000,
                    width: 64,
                    onChanged: (v) => write(c.copyWith(reach: v.round())),
                    onCommit: commit,
                  ),
                  ...gameEffectControls(controller, c.then,
                      (next) => now(c.copyWith(then: next)), commit,
                      key: "count-then-$i", label: "Then"),
                ],
                CanvasTextButton(
                  key: ValueKey("count-remove-$i"),
                  label: "Take it out",
                  icon: Icons.delete_outline,
                  onPressed: () => controller.apply(controller.document
                      .copyWith(
                          counts: [...controller.document.counts]
                            ..removeAt(i))),
                ),
              ],
            ),
          ),
      ]),
    );
  }
}
