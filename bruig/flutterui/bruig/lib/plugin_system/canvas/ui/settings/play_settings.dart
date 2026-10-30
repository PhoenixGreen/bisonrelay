import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/button_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// play_settings.dart is what an element does when the canvas is played as
// a game -- see play.dart and canvas_game.dart -- as the Game panel lays it
// out: what it is, as a grid of cards, then sections that fold, each saying
// in a line how it is set, as the Design tab's do.

/// playIcons are each way of being played, drawn.
const playIcons = <PlayAs, IconData>{
  PlayAs.none: Icons.do_not_disturb_on_outlined,
  PlayAs.platformer: Icons.directions_run,
  PlayAs.topDown: Icons.open_with,
  PlayAs.camera: Icons.videocam_outlined,
  PlayAs.solid: Icons.foundation,
  PlayAs.pickup: Icons.star_outline,
  PlayAs.hazard: Icons.warning_amber_rounded,
};

/// playCardLabels are the cards' words: shorter than the labels, which
/// read in a sentence.
const _cardLabels = <PlayAs, String>{
  PlayAs.none: "Still",
  PlayAs.platformer: "Platformer",
  PlayAs.topDown: "Top-down",
  PlayAs.camera: "Camera",
  PlayAs.solid: "Solid",
  PlayAs.pickup: "Pickup",
  PlayAs.hazard: "Hazard",
};

/// gameElementSettings are [e]'s game settings: what it is when played,
/// as cards; then how it moves, what touching it does, which of its layers
/// are ground, and what presses it -- each a section that folds.
List<Widget> gameElementSettings(CanvasController controller, CanvasElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var doc = controller.document;
  var spec = e.base.play;
  void set(PlaySpec next, {bool live = false}) {
    begin();
    write(e.rebase(e.base.copyWith(play: next)));
    if (!live) commit();
  }

  var pressedBy =
      doc.controlsNow.where((a) => a.id == spec.pressedBy).firstOrNull;
  var reach = _reaches
      .where((r) => (r.$1 - spec.reach).abs() < 0.5)
      .firstOrNull
      ?.$2
      .toLowerCase();
  return [
    CanvasControlGroup(label: "When played", children: [
      PlayKindCards(
        value: spec.as,
        onPick: (p) => p.touched && spec.touched.does == GameDoes.nothing
            ? _touchable(controller, e, p, write, begin, commit)
            : set(spec.copyWith(as: p)),
      ),
      CanvasHint(switch (spec.as) {
        PlayAs.none => "Still: it plays its own timeline and nothing more. "
            "Pick what it is in the game above.",
        PlayAs.platformer => "Walks left and right with the controls, "
            "falls, and jumps. It lands on whatever is solid, and on the "
            "canvas's bottom edge.",
        PlayAs.topDown => "Walks every way with the controls, stopped "
            "by whatever is solid -- a game seen from above.",
        PlayAs.camera => "Moves the view itself with the controls: "
            "everything else, and the parallax, moves with it.",
        PlayAs.solid => "Something to stand on and to bump into: a "
            "floor, a platform, a wall.",
        PlayAs.pickup => "Taken by a player touching it -- a coin, a key, "
            "a heart. The counts are the game's: pick nothing to see them.",
        PlayAs.hazard => "Hurts a player touching it -- spikes, water.",
      }),
    ]),
    if (spec.as.moves)
      section(e, "gameMovement",
          icon: Icons.open_with,
          title: "Movement",
          summary: [
            "Player ${spec.player}",
            shortNumber(spec.speed),
            if (spec.as == PlayAs.platformer) "jumps ${shortNumber(spec.jump)}",
          ].join(" · "),
          initiallyOpen: true,
          children: [
            CanvasControlGroup(
                label: "Movement",
                hideCaption: true,
                rule: false,
                children: [
                  CanvasDropdown<int>(
                    key: const ValueKey("playPlayer"),
                    label: "Player",
                    value: spec.player,
                    width: 110,
                    options: [for (var p = 1; p <= 4; p++) (p, "Player $p")],
                    onChanged: (p) => set(spec.copyWith(player: p)),
                  ),
                  CanvasNumberField(
                    key: const ValueKey("playSpeed"),
                    label: "Speed",
                    value: spec.speed,
                    min: 10,
                    max: 5000,
                    width: 64,
                    onChanged: (v) => set(spec.copyWith(speed: v), live: true),
                    onCommit: commit,
                  ),
                  if (spec.as == PlayAs.platformer) ...[
                    CanvasNumberField(
                      key: const ValueKey("playJump"),
                      label: "Jump",
                      value: spec.jump,
                      min: 0,
                      max: 5000,
                      width: 64,
                      onChanged: (v) => set(spec.copyWith(jump: v), live: true),
                      onCommit: commit,
                    ),
                    CanvasNumberField(
                      key: const ValueKey("playGravity"),
                      label: "Gravity",
                      value: spec.gravity,
                      min: 0,
                      max: 20000,
                      width: 70,
                      onChanged: (v) =>
                          set(spec.copyWith(gravity: v), live: true),
                      onCommit: commit,
                    ),
                  ],
                  if (spec.as != PlayAs.camera)
                    CanvasToggle(
                      key: const ValueKey("playFollow"),
                      label: "The view follows it",
                      value: spec.follow,
                      onChanged: (v) => set(spec.copyWith(follow: v)),
                    ),
                ]),
          ]),
    if (spec.as.touched)
      section(e, "gameTouched",
          icon: playIcons[spec.as]!,
          title: "When touched",
          summary: _touchSummary(controller, spec),
          initiallyOpen: true,
          children: [
            CanvasControlGroup(
                label: "When touched",
                hideCaption: true,
                rule: false,
                children: [
                  TouchSentence(
                      controller: controller,
                      spec: spec,
                      onChanged: (next) => set(next)),
                ]),
          ]),
    if (e is TileMapElement && e.layers.any((l) => !l.isObjects))
      section(e, "gameSolid",
          icon: Icons.layers_outlined,
          title: "Solid layers",
          summary: [
            for (var l in e.layers)
              if (l.solid && !l.isObjects) l.name,
          ].join(", ").ifEmpty("None"),
          children: [
            CanvasControlGroup(
                label: "Solid layers",
                hideCaption: true,
                rule: false,
                children: [
                  for (var (i, layer) in e.layers.indexed)
                    if (!layer.isObjects)
                      CanvasToggle(
                        key: ValueKey("gameSolid-$i"),
                        label: layer.name,
                        value: layer.solid,
                        onChanged: (v) {
                          begin();
                          write(e.withLayer(i, layer.copyWith(solid: v)));
                          commit();
                        },
                      ),
                  const CanvasHint(
                      "A solid layer's tiles are the ground: a player stands "
                      "on them and walks into their sides. The others are "
                      "scenery."),
                ]),
          ]),
    section(e, "gamePress",
        icon: Icons.touch_app_outlined,
        title: "Pressed by",
        summary: pressedBy == null
            ? "Nothing"
            : "${pressedBy.name}${spec.reach > 0 && reach != null ? " · $reach" : ""}",
        children: [
          CanvasControlGroup(
              label: "Pressed by",
              hideCaption: true,
              rule: false,
              children: _pressControls(controller, e, spec, set, commit)),
        ]),
  ];
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// _touchSummary is what touching it does, in a line: "Coins +1 · vanishes".
String _touchSummary(CanvasController controller, PlaySpec spec) {
  var doc = controller.document;
  var effect = spec.touched;
  var count = doc.counts.where((c) => c.id == effect.count).firstOrNull?.name;
  var does = switch (effect.does) {
    GameDoes.add => "${count ?? "A count"} +${effect.amount}",
    GameDoes.take => "${count ?? "A count"} −${effect.amount}",
    GameDoes.scene => "Goes to a scene",
    GameDoes.next => "Next scene",
    GameDoes.restart => "Starts again",
    GameDoes.stop => "Ends the game",
    GameDoes.nothing => "Nothing",
  };
  var then = spec.as == PlayAs.pickup
      ? (spec.stays ? "stays" : "vanishes")
      : (spec.sendsBack ? "back to the start" : "");
  return [does, if (then.isNotEmpty) then].join(" · ");
}

/// PlayKindCards are the ways of being played, as a grid of cards: what an
/// element is in the game is the first thing set, and seeing them all says
/// what the game can do.
class PlayKindCards extends StatelessWidget {
  final PlayAs value;
  final ValueChanged<PlayAs> onPick;
  const PlayKindCards({required this.value, required this.onPick, super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return LayoutBuilder(builder: (context, box) {
      const gap = 4.0;
      var width = box.maxWidth.isFinite ? box.maxWidth : 240.0;
      var card = (width - gap * 3) / 4;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (var p in PlayAs.values)
          SizedBox(
            width: card,
            height: 54,
            child: Material(
              color: p == value
                  ? colors.secondaryContainer
                  : colors.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                  side: BorderSide(
                      color: p == value
                          ? colors.primary
                          : colors.outlineVariant.withValues(alpha: 0.6))),
              child: InkWell(
                key: ValueKey("playAs-${p.name}"),
                borderRadius: BorderRadius.circular(7),
                onTap: () => onPick(p),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(playIcons[p],
                          size: 17,
                          color: p == value
                              ? colors.onSecondaryContainer
                              : colors.onSurfaceVariant),
                      const SizedBox(height: 4),
                      Text(_cardLabels[p]!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: p == value
                                  ? colors.onSecondaryContainer
                                  : colors.onSurface)),
                    ]),
              ),
            ),
          ),
      ]);
    });
  }
}

/// TouchSentence is what touching a pickup or a hazard does, written as a
/// sentence whose words are its controls: "Add 1 to Coins, play coin.ogg
/// and vanish".
class TouchSentence extends StatelessWidget {
  final CanvasController controller;
  final PlaySpec spec;
  final ValueChanged<PlaySpec> onChanged;
  const TouchSentence(
      {required this.controller,
      required this.spec,
      required this.onChanged,
      super.key});

  @override
  Widget build(BuildContext context) {
    var doc = controller.document;
    var effect = spec.touched;
    void setEffect(GameEffect next) => onChanged(spec.copyWith(touched: next));
    var scenes = doc.allScenes;
    var sounds = [
      for (var a in doc.elements)
        if (a is AudioElement) a,
    ];
    return SizedBox(
      width: double.infinity,
      child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            WordChoice<GameDoes>(
              key: const ValueKey("playTouched-does"),
              value: effect.does,
              options: [
                for (var d in GameDoes.values) (d, _verbs[d]!),
              ],
              onChanged: (d) => setEffect(effect.copyWith(
                  does: d,
                  count:
                      d.counts && effect.count.isEmpty && doc.counts.isNotEmpty
                          ? doc.counts.first.id
                          : null)),
            ),
            if (effect.does.counts) ...[
              NumberWord(
                  key: const ValueKey("playTouched-amount"),
                  value: effect.amount,
                  onChanged: (n) => setEffect(effect.copyWith(amount: n))),
              _Plain(effect.does == GameDoes.add ? "to" : "from"),
              WordChoice<String>(
                key: const ValueKey("playTouched-count"),
                value: doc.counts.any((c) => c.id == effect.count)
                    ? effect.count
                    : "",
                options: [
                  if (!doc.counts.any((c) => c.id == effect.count))
                    ("", "a count"),
                  for (var c in doc.counts) (c.id, c.name),
                ],
                onChanged: (id) => setEffect(effect.copyWith(count: id)),
              ),
            ],
            if (effect.does == GameDoes.scene)
              WordChoice<String>(
                key: const ValueKey("playTouched-scene"),
                value:
                    scenes.any((s) => s.id == effect.scene) ? effect.scene : "",
                options: [
                  ("", "which scene?"),
                  for (var (i, s) in scenes.indexed) (s.id, doc.nameOf(i)),
                ],
                onChanged: (id) => setEffect(effect.copyWith(scene: id)),
              ),
            const _Plain(", play"),
            WordChoice<String>(
              key: const ValueKey("playSound"),
              value: sounds.any((a) => a.id == spec.sound) ? spec.sound : "",
              options: [
                ("", "no sound"),
                for (var a in sounds)
                  (a.id, a.name.isEmpty ? "a sound" : a.name),
              ],
              onChanged: (id) => onChanged(spec.copyWith(sound: id)),
            ),
            const _Plain("and"),
            if (spec.as == PlayAs.pickup)
              WordChoice<bool>(
                key: const ValueKey("playStays"),
                value: spec.stays,
                options: const [(false, "vanish"), (true, "stay")],
                onChanged: (v) => onChanged(spec.copyWith(stays: v)),
              )
            else
              WordChoice<bool>(
                key: const ValueKey("playSendsBack"),
                value: spec.sendsBack,
                options: const [
                  (true, "send the player back"),
                  (false, "leave the player be"),
                ],
                onChanged: (v) => onChanged(spec.copyWith(sendsBack: v)),
              ),
          ]),
    );
  }
}

/// _verbs are what can happen, as the first word of the sentence.
const _verbs = <GameDoes, String>{
  GameDoes.nothing: "Do nothing",
  GameDoes.add: "Add",
  GameDoes.take: "Take",
  GameDoes.scene: "Go to",
  GameDoes.next: "Go to the next scene",
  GameDoes.restart: "Start the game again",
  GameDoes.stop: "End the game",
};

/// _Plain is a sentence's own words, between its controls.
class _Plain extends StatelessWidget {
  final String text;
  const _Plain(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontSize: 12,
          color: ThemeNotifier.of(context).colors.onSurfaceVariant));
}

/// WordChoice is one word of a sentence that is a dropdown: chosen from
/// [options], drawn as a chip in the line.
class WordChoice<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  const WordChoice(
      {required this.value,
      required this.options,
      required this.onChanged,
      super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var shown = options.any((o) => o.$1 == value) ? value : options.first.$1;
    return Container(
      height: 28,
      padding: const EdgeInsets.only(left: 8, right: 4),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.55),
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      // As wide as its words: a dropdown's items fill whatever width they
      // are offered, and in a sentence that wraps that is the whole line.
      child: IntrinsicWidth(
          child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: shown,
          isDense: true,
          // Filling the width it is given -- its own words', or the line's
          // where they are longer, cut short with an ellipsis.
          isExpanded: true,
          iconSize: 16,
          focusColor: Colors.transparent,
          dropdownColor: colors.surfaceContainerHigh,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.onSurface),
          items: [
            for (var (v, label) in options)
              DropdownMenuItem<T>(
                  value: v,
                  child: Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      )),
    );
  }
}

/// NumberWord is a number in a sentence, typed in place: one or more.
class NumberWord extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const NumberWord({required this.value, required this.onChanged, super.key});

  @override
  State<NumberWord> createState() => _NumberWordState();
}

class _NumberWordState extends State<NumberWord> {
  late final TextEditingController _text =
      TextEditingController(text: "${widget.value}");

  @override
  void didUpdateWidget(NumberWord old) {
    super.didUpdateWidget(old);
    if ("${widget.value}" != _text.text &&
        int.tryParse(_text.text) != widget.value) {
      _text.text = "${widget.value}";
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return Container(
      width: 46,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.55),
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: TextField(
        controller: _text,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: colors.onSurface),
        decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero),
        onChanged: (t) {
          var n = int.tryParse(t.trim());
          if (n != null && n >= 1) widget.onChanged(n);
        },
      ),
    );
  }
}

/// _touchable makes [e] a pickup or a hazard ready to use: a pickup adding
/// one to Coins, a hazard taking one from Lives -- three of them, the game
/// starting again when they are gone -- each count made if the game has
/// none of that name yet. One undo step.
void _touchable(CanvasController controller, CanvasElement e, PlayAs as,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var doc = controller.document;
  var pickup = as == PlayAs.pickup;
  var name = pickup ? "Coins" : "Lives";
  var count = doc.counts.where((c) => c.name == name).firstOrNull;
  begin();
  if (count == null) {
    count = pickup
        ? GameCount(newElementId(), name)
        : GameCount(newElementId(), name,
            start: 3, reach: 0, then: const GameEffect(does: GameDoes.restart));
    controller.apply(doc.copyWith(counts: [...doc.counts, count]),
        transient: true);
  }
  var now = controller.document.elementById(e.id) ?? e;
  write(now.rebase(now.base.copyWith(
      play: now.base.play.copyWith(
          as: as,
          touched: GameEffect(
              does: pickup ? GameDoes.add : GameDoes.take, count: count.id)))));
  commit();
}

/// gameEffectControls set [effect]: what happens, and to which count by
/// how many, or to which scene. [key] starts each control's key.
List<Widget> gameEffectControls(CanvasController controller, GameEffect effect,
    void Function(GameEffect next) set, VoidCallback commit,
    {required String key, required String label, bool counts = true}) {
  var doc = controller.document;
  var scenes = doc.allScenes;
  return [
    CanvasDropdown<GameDoes>(
      key: ValueKey("$key-does"),
      label: label,
      value: effect.does,
      width: 170,
      options: [
        for (var d in GameDoes.values)
          if (counts || !d.counts) (d, d.label),
      ],
      onChanged: (d) => set(effect.copyWith(
          does: d,
          count: d.counts && effect.count.isEmpty && doc.counts.isNotEmpty
              ? doc.counts.first.id
              : null)),
    ),
    if (effect.does.counts) ...[
      CanvasDropdown<String>(
        key: ValueKey("$key-count"),
        label: "Count",
        value: doc.counts.any((c) => c.id == effect.count) ? effect.count : "",
        width: 120,
        options: [
          if (!doc.counts.any((c) => c.id == effect.count)) ("", "—"),
          for (var c in doc.counts) (c.id, c.name),
        ],
        onChanged: (id) => set(effect.copyWith(count: id)),
      ),
      CanvasNumberField(
        key: ValueKey("$key-amount"),
        label: "By",
        value: effect.amount.toDouble(),
        min: 1,
        max: 1000000,
        width: 56,
        onChanged: (v) => set(effect.copyWith(amount: v.round())),
        onCommit: commit,
      ),
    ],
    // Held by id, as a button's scene is: moving the scenes about does
    // not point it at another.
    if (effect.does == GameDoes.scene)
      CanvasDropdown<String>(
        key: ValueKey("$key-scene"),
        label: "Scene",
        value: scenes.any((sc) => sc.id == effect.scene) ? effect.scene : "",
        width: 170,
        options: [
          ("", "Nothing"),
          for (var (i, sc) in scenes.indexed) (sc.id, doc.nameOf(i)),
        ],
        onChanged: (id) => set(effect.copyWith(scene: id)),
      ),
  ];
}

/// _reaches are how near a player has to be to press something: anywhere,
/// touching, beside it, near it -- in canvas units.
const _reaches = <(double, String)>[
  (0, "Anywhere"),
  (8, "A player touching it"),
  (48, "A player beside it"),
  (160, "A player near it"),
];

/// _pressControls are an action pressing [e] while the game plays: which
/// action, from how near, and what it does -- a Button its own action.
List<Widget> _pressControls(
    CanvasController controller,
    CanvasElement e,
    PlaySpec spec,
    void Function(PlaySpec next, {bool live}) set,
    VoidCallback commit) {
  var actions = controller.document.controlsNow;
  var reach = _reaches
      .reduce((a, b) =>
          (a.$1 - spec.reach).abs() <= (b.$1 - spec.reach).abs() ? a : b)
      .$1;
  return [
    CanvasDropdown<String>(
      key: const ValueKey("playPressedBy"),
      label: "Pressed by",
      value: actions.any((a) => a.id == spec.pressedBy) ? spec.pressedBy : "",
      width: 170,
      options: [
        ("", "Nothing"),
        for (var a in actions) (a.id, a.name),
      ],
      onChanged: (id) => set(spec.copyWith(pressedBy: id)),
    ),
    if (spec.pressedBy.isNotEmpty) ...[
      CanvasDropdown<double>(
        key: const ValueKey("playReach"),
        label: "From",
        value: reach,
        width: 170,
        options: _reaches,
        onChanged: (r) => set(spec.copyWith(reach: r)),
      ),
      if (e is ButtonElement)
        const CanvasHint("Pressed, it does what the button does when it is "
            "clicked.")
      else
        ...buttonActionControls(
            controller,
            spec.press,
            e.id,
            (next, {live = false}) =>
                set(spec.copyWith(press: next), live: live),
            commit,
            key: "playPress"),
    ],
  ];
}
