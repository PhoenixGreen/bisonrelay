import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/button_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/controls_settings.dart'
    show keyLabel;
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

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

/// _cardLabels are the cards' words: shorter than the labels, which read
/// in a sentence.
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
  var pressedOnly = spec.as == PlayAs.none && spec.pressedBy.isNotEmpty;
  return [
    CanvasControlGroup(label: "In the game, it is", rule: false, children: [
      PlayKindCards(
        value: spec.as,
        pressed: pressedOnly,
        onPick: (p) => p.touched && spec.touched.does == GameDoes.nothing
            ? _touchable(controller, e, p, write, begin, commit)
            : set(_feltAs(spec, p)),
        // Pressed: still, but pressed -- a lever, a switch -- by the action
        // key, with a player beside it.
        onPressed: () {
          var act = doc.controlsNow.where((a) => a.id == "act").firstOrNull ??
              doc.controlsNow.firstOrNull;
          set(spec.copyWith(
              as: PlayAs.none,
              pressedBy: spec.pressedBy.isEmpty ? act?.id ?? "" : null,
              reach: spec.pressedBy.isEmpty ? 48 : null));
        },
      ),
      CanvasHint(pressedOnly
          ? "Pressed: it stays where it is, and an action pressed near it "
              "does something -- a lever, a switch, a door."
          : switch (spec.as) {
              PlayAs.none => "Still: it plays its own timeline and nothing "
                  "more. Pick what it is in the game above.",
              PlayAs.platformer => "Walks left and right with the controls, "
                  "falls, and jumps. It lands on whatever is solid, and on "
                  "the canvas's bottom edge.",
              PlayAs.topDown => "Walks every way with the controls, stopped "
                  "by whatever is solid -- a game seen from above.",
              PlayAs.camera => "Moves the view itself with the controls: "
                  "everything else, and the parallax, moves with it.",
              PlayAs.solid => "Something to stand on and to bump into: a "
                  "floor, a platform, a wall.",
              PlayAs.pickup => "Taken by a player touching it -- a coin, a "
                  "key, a heart. The counts are the game's: pick nothing to "
                  "see them.",
              PlayAs.hazard => "Hurts a player touching it -- spikes, water.",
            }),
    ]),
    if (spec.as.moves)
      GameSection(
          key: const ValueKey("gameSection-movement"),
          title: "How it moves",
          summary: spec.as == PlayAs.platformer ? "" : shortNumber(spec.speed),
          action: spec.as == PlayAs.platformer
              ? WordChoice<PlayFeel>(
                  key: const ValueKey("playFeel"),
                  value: PlayFeel.of(spec),
                  options: [
                    for (var f in PlayFeel.values)
                      if (f != PlayFeel.custom || PlayFeel.of(spec) == f)
                        (f, f.label),
                  ],
                  onChanged: (f) {
                    if (f == PlayFeel.custom) return;
                    set(spec.copyWith(
                        speed: f.speed, jump: f.jump, gravity: f.gravity));
                  },
                )
              : null,
          children: [
            if (spec.as == PlayAs.platformer)
              JumpArc(
                  key: const ValueKey("playArc"),
                  speed: spec.speed,
                  jump: spec.jump,
                  gravity: spec.gravity),
            CanvasControlGroup(
                label: "How it moves",
                hideCaption: true,
                rule: false,
                children: [
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
    if (spec.as.moves)
      GameSection(
        key: const ValueKey("gameSection-player"),
        title: "Played by",
        summary: _controlsLine(doc, spec.player),
        action: WordChoice<int>(
          key: const ValueKey("playPlayer"),
          value: spec.player,
          options: [for (var p = 1; p <= 4; p++) (p, "Player $p")],
          onChanged: (p) => set(spec.copyWith(player: p)),
        ),
        children: const [],
      ),
    if (spec.as.touched)
      GameSection(
          key: const ValueKey("gameSection-touched"),
          title: "Touched, it will",
          summary: _touchSummary(controller, spec),
          children: [
            TouchSentence(
                controller: controller,
                spec: spec,
                onChanged: (next) => set(next)),
          ]),
    // Punched or kicked (Ken, 2026-11-10): anything but a player -- a foe,
    // a crate, a wall to break.
    if (!spec.as.moves && spec.as != PlayAs.camera)
      GameSection(
          key: const ValueKey("gameSection-hit"),
          title: "Punched or kicked",
          summary: !spec.hittable
              ? "Not hit"
              : "Beaten by ${spec.hits} hit${spec.hits == 1 ? "" : "s"}",
          children: [
            HitSentence(
                controller: controller,
                spec: spec,
                onChanged: (next) => set(next)),
          ]),
    if (e is SpriteElement && spec.as != PlayAs.none)
      GameSection(
          key: const ValueKey("gameSection-touchArea"),
          title: "Touched where",
          summary: spec.touchWhole ? "Its whole box" : "Where it is drawn",
          children: [
            TouchAreaChoice(
                sprite: e,
                whole: spec.touchWhole,
                onChanged: (v) => set(spec.copyWith(touchWhole: v))),
          ]),
    if (e is TileMapElement && e.layers.any((l) => !l.isObjects))
      GameSection(
          key: const ValueKey("gameSection-solid"),
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
    GameSection(
        key: const ValueKey("gameSection-press"),
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

/// gameSoundOptions are what a game can play when something happens: each
/// mixer slot, by its channel; a Stop for each channel with slots; and the
/// sounds on the canvas -- as a game keeps each (see gameSoundOf), and named.
List<(String, String)> gameSoundOptions(CanvasController controller,
    {String none = "no sound"}) {
  var doc = controller.document;
  var session = controller.session;
  var canvas = [
    for (var e in [...doc.elements, ...?doc.master?.elements])
      if (e is AudioElement) e,
  ];
  return [
    ("", none),
    for (var ch in controller.timelineChannels) ...[
      for (var row = 0; row < session.rows; row++)
        if (session.at(ch.key, row) case var clip?)
          (
            gameSoundSlot(clip.id),
            "${ch.name} · ${clip.name.isEmpty ? session.sceneName(row) : clip.name}"
          ),
      if (session.slots[ch.key]?.any((c) => c != null) ?? false)
        (gameSoundStop(ch.key), "Stop ${ch.name}"),
    ],
    // Said apart from the slots: a channel's own sound is often named as
    // the channel is.
    for (var a in canvas)
      (a.id, "On the canvas · ${a.name.isEmpty ? "a sound" : a.name}"),
  ];
}

/// _controlsLine is how [player] plays, in a line: "Arrows or WASD move ·
/// Space jumps · E acts".
String _controlsLine(CanvasDocument doc, int player) =>
    "Player $player · ${gameControlsLine(doc.controlsFor(player))}";

/// gameControlsLine is [actions] said in a line: the keys that move first,
/// then each other action's first key.
String gameControlsLine(List<ControlAction> actions) {
  const moving = {"left", "right", "up", "down"};
  var keys = {
    for (var a in actions)
      if (moving.contains(a.id)) ...a.keys,
  };
  var arrows = {
    LogicalKeyboardKey.arrowLeft.keyId,
    LogicalKeyboardKey.arrowRight.keyId,
  };
  var wasd = {
    LogicalKeyboardKey.keyA.keyId,
    LogicalKeyboardKey.keyD.keyId,
  };
  var move = [
    if (keys.containsAll(arrows)) "Arrows",
    if (keys.containsAll(wasd)) "WASD",
  ];
  return [
    if (move.isNotEmpty) "${move.join(" or ")} move",
    for (var a in actions)
      if (!moving.contains(a.id) && a.keys.isNotEmpty)
        "${keyLabel(a.keys.first)} ${switch (a.id) {
          "jump" => "jumps",
          "act" => "acts",
          "punch" => "punches",
          "kick" => "kicks",
          _ => a.name.toLowerCase(),
        }}",
  ].join(" · ");
}

/// GameSection is one of the Game panel's sections: no box round it, a
/// line above it, its name, how it is set in a few words, and a control of
/// its own beside them.
class GameSection extends StatelessWidget {
  final String title;
  final String summary;
  final Widget? action;
  final List<Widget> children;
  const GameSection(
      {required this.title,
      this.summary = "",
      this.action,
      required this.children,
      super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var titleText = Text(title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: colors.onSurface));
    var summaryStyle = TextStyle(fontSize: 11, color: colors.onSurfaceVariant);
    return SizedBox(
      width: double.infinity,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Divider(height: 1, color: colors.outlineVariant.withValues(alpha: 0.6)),
        const SizedBox(height: 10),
        // With a control of its own on the line, how it is set goes under
        // its name, where there is room to say it all.
        if (action == null)
          Row(children: [
            Flexible(child: titleText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: summaryStyle),
            ),
          ])
        else ...[
          Row(children: [
            Expanded(child: titleText),
            const SizedBox(width: 6),
            ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: action!),
          ]),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(summary, style: summaryStyle),
          ],
        ],
        if (children.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...children,
        ],
        const SizedBox(height: 10),
      ]),
    );
  }
}

/// JumpArc is the jump a platformer makes, drawn to scale: up at its jump,
/// across at its speed, down at its gravity -- and said in tiles.
class JumpArc extends StatelessWidget {
  final double speed;
  final double jump;
  final double gravity;
  const JumpArc(
      {required this.speed,
      required this.jump,
      required this.gravity,
      super.key});

  /// across is how far it goes in one jump, landing where it started from.
  double get across {
    if (gravity <= 0 || jump <= 0) return 0;
    var up = math.sqrt(2 * gravity * jump);
    return speed * 2 * up / gravity;
  }

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    String tiles(double v) => (v / 64).toStringAsFixed(1);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: double.infinity,
        height: 84,
        child: CustomPaint(
            painter: _ArcPainter(
                jump: jump,
                across: across,
                ground: colors.outlineVariant,
                line: const Color(0xFF5AA9FF),
                dot: const Color(0xFF9CC0FF))),
      ),
      const SizedBox(height: 4),
      Text(
          gravity <= 0
              ? "No gravity: it floats away"
              : "Jumps ${tiles(jump)} tiles high, ${tiles(across)} across",
          key: const ValueKey("playArcSays"),
          style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
      const SizedBox(height: 6),
    ]);
  }
}

class _ArcPainter extends CustomPainter {
  final double jump, across;
  final Color ground, line, dot;
  _ArcPainter(
      {required this.jump,
      required this.across,
      required this.ground,
      required this.line,
      required this.dot});

  @override
  void paint(Canvas canvas, Size size) {
    var base = size.height - 8;
    canvas.drawLine(
        Offset(0, base), Offset(size.width, base), Paint()..color = ground);
    // A tile a mark along the ground, to read the arc against.
    var k = math.min(
        20 / 64,
        math.min(across > 0 ? (size.width - 28) / across : 1.0,
            jump > 0 ? (base - 6) / jump : 1.0));
    for (var x = 12.0; x < size.width; x += 64 * k) {
      canvas.drawLine(
          Offset(x, base), Offset(x, base + 4), Paint()..color = ground);
    }
    canvas.drawCircle(Offset(12, base - 5), 5, Paint()..color = dot);
    if (across <= 0 || jump <= 0) return;
    var path = Path();
    for (var i = 0; i <= 40; i++) {
      var t = i / 40;
      var x = 12 + across * t * k;
      // Up and down, a parabola: highest half way.
      var y = base - 5 - jump * 4 * t * (1 - t) * k;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = line);
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.jump != jump || old.across != across || old.ground != ground;
}

/// TouchAreaChoice is what of a sprite a game touches: where it is drawn,
/// or its whole box -- the two drawn small, with the line the canvas shows.
class TouchAreaChoice extends StatelessWidget {
  final SpriteElement sprite;
  final bool whole;
  final ValueChanged<bool> onChanged;
  const TouchAreaChoice(
      {required this.sprite,
      required this.whole,
      required this.onChanged,
      super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var box = const Rect.fromLTWH(0, 0, 1, 1);
    var area = whole ? box : sprite.touchIn(box);
    Widget chip(String label, bool on, bool value) => Material(
          color: on ? colors.secondaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(
                  color: on ? colors.primary : colors.outlineVariant)),
          child: InkWell(
            key: ValueKey(value ? "touchWhole" : "touchDrawn"),
            borderRadius: BorderRadius.circular(6),
            onTap: () => onChanged(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color:
                          on ? colors.onSecondaryContainer : colors.onSurface)),
            ),
          ),
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 56,
        height: 56,
        child: CustomPaint(
            painter: _AreaPainter(
                area: area,
                frame: colors.outlineVariant,
                line: const Color(0xFF5AA9FF))),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            chip("It is drawn", !whole, false),
            chip("Its whole box", whole, true),
          ]),
          const SizedBox(height: 6),
          Text("The blue line, on the canvas too while the Game tab is open.",
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
        ]),
      ),
    ]);
  }
}

class _AreaPainter extends CustomPainter {
  final Rect area;
  final Color frame, line;
  _AreaPainter({required this.area, required this.frame, required this.line});

  @override
  void paint(Canvas canvas, Size size) {
    var all = Offset.zero & size;
    canvas.drawRRect(
        RRect.fromRectAndRadius(all.deflate(1), const Radius.circular(4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = frame);
    var r = Rect.fromLTRB(area.left * size.width, area.top * size.height,
        area.right * size.width, area.bottom * size.height);
    canvas.drawRect(
        r.deflate(2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = line);
  }

  @override
  bool shouldRepaint(_AreaPainter old) => old.area != area;
}

/// _feltAs is [spec] played as [as]: a platformer never yet set moving takes
/// the Normal feel, whose jump reaches a ledge three tiles up.
PlaySpec _feltAs(PlaySpec spec, PlayAs as) {
  const fresh = PlaySpec();
  var untouched = spec.speed == fresh.speed &&
      spec.jump == fresh.jump &&
      spec.gravity == fresh.gravity;
  if (as != PlayAs.platformer || !untouched) return spec.copyWith(as: as);
  var f = PlayFeel.normal;
  return spec.copyWith(
      as: as, speed: f.speed, jump: f.jump, gravity: f.gravity);
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// gameShowables are what a game can show or hide: this scene's elements
/// and the HUD's on the master -- not its sounds or its backdrop -- as id
/// and name.
List<(String, String)> gameShowables(CanvasDocument doc) => [
      for (var e in [...doc.elements, ...?doc.master?.elements])
        if (e is! AudioElement && e is! BackgroundElement)
          (e.id, e.name.isEmpty ? e.kind.label : e.name),
    ];

/// _showableName is [id]'s name, for a summary: "something" where it has
/// gone.
String _showableName(CanvasDocument doc, String id) =>
    gameShowables(doc).where((s) => s.$1 == id).firstOrNull?.$2 ?? "something";

/// _touchSummary is what touching it does, in a line: "Coins +1 · vanishes".
String _touchSummary(CanvasController controller, PlaySpec spec) {
  var doc = controller.document;
  var effect = spec.touched;
  var count = doc.counts.where((c) => c.id == effect.count).firstOrNull?.name;
  var does = switch (effect.does) {
    GameDoes.add => "${count ?? "A count"} +${effect.amount}",
    GameDoes.take => "${count ?? "A count"} −${effect.amount}",
    GameDoes.show => "Shows ${_showableName(doc, effect.element)}",
    GameDoes.hide => "Hides ${_showableName(doc, effect.element)}",
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

  /// pressed is whether it is the eighth card, Pressed: still, but pressed
  /// by an action -- picked with [onPressed].
  final bool pressed;
  final VoidCallback? onPressed;
  const PlayKindCards(
      {required this.value,
      required this.onPick,
      this.pressed = false,
      this.onPressed,
      super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return LayoutBuilder(builder: (context, box) {
      const gap = 4.0;
      var width = box.maxWidth.isFinite ? box.maxWidth : 240.0;
      var card = (width - gap * 3) / 4;
      Widget cardOf(String key, IconData icon, String label, bool on,
              VoidCallback tap) =>
          SizedBox(
            width: card,
            height: 54,
            child: Material(
              color: on
                  ? colors.secondaryContainer
                  : colors.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                  side: BorderSide(
                      color: on
                          ? colors.primary
                          : colors.outlineVariant.withValues(alpha: 0.6))),
              child: InkWell(
                key: ValueKey(key),
                borderRadius: BorderRadius.circular(7),
                onTap: tap,
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon,
                          size: 17,
                          color: on
                              ? colors.onSecondaryContainer
                              : colors.onSurfaceVariant),
                      const SizedBox(height: 4),
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: on
                                  ? colors.onSecondaryContainer
                                  : colors.onSurface)),
                    ]),
              ),
            ),
          );
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (var p in PlayAs.values)
          cardOf("playAs-${p.name}", playIcons[p]!, _cardLabels[p]!,
              p == value && !pressed, () => onPick(p)),
        if (onPressed != null)
          cardOf("playAs-pressed", Icons.touch_app_outlined, "Pressed", pressed,
              onPressed!),
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
    var sounds = gameSoundOptions(controller);
    return SizedBox(
      width: double.infinity,
      child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...effectWords(doc, effect, setEffect, "playTouched"),
            const _Plain(", play"),
            WordChoice<String>(
              key: const ValueKey("playSound"),
              value: sounds.any((o) => o.$1 == spec.sound) ? spec.sound : "",
              options: sounds,
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
  GameDoes.show: "Show",
  GameDoes.hide: "Hide",
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
    if (effect.does.shows)
      CanvasDropdown<String>(
        key: ValueKey("$key-element"),
        label: "What",
        value: gameShowables(doc).any((e) => e.$1 == effect.element)
            ? effect.element
            : "",
        width: 170,
        options: [
          ("", "—"),
          ...gameShowables(doc),
        ],
        onChanged: (id) => set(effect.copyWith(element: id)),
      ),
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

/// _soundDropdown is "Plays": what is heard as it happens -- a slot, a
/// channel stopped, a sound on the canvas.
Widget _soundDropdown(CanvasController controller, String key, String value,
    ValueChanged<String> onChanged) {
  var options = gameSoundOptions(controller, none: "Nothing");
  return CanvasDropdown<String>(
    key: ValueKey(key),
    label: "Plays",
    value: options.any((o) => o.$1 == value) ? value : "",
    width: 170,
    options: options,
    onChanged: onChanged,
  );
}

/// gameSoundDropdown is the "Plays" dropdown for [effect]: what is heard as
/// it happens. [key] starts its key.
Widget gameSoundDropdown(CanvasController controller, GameEffect effect,
        void Function(GameEffect next) set, {required String key}) =>
    _soundDropdown(controller, "$key-sound", effect.sound,
        (ref) => set(effect.copyWith(sound: ref)));

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
      _soundDropdown(controller, "playPressSound", spec.pressSound,
          (ref) => set(spec.copyWith(pressSound: ref))),
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

/// effectWords are what a game does, as words to choose in a sentence --
/// "Add 1 to Coins", "Show the gate", "Go to Caves" -- keyed by [prefix]:
/// a touch's, a defeat's.
List<Widget> effectWords(CanvasDocument doc, GameEffect effect,
    ValueChanged<GameEffect> setEffect, String prefix) {
  var scenes = doc.allScenes;
  return [
    WordChoice<GameDoes>(
      key: ValueKey("$prefix-does"),
      value: effect.does,
      options: [
        for (var d in GameDoes.values) (d, _verbs[d]!),
      ],
      onChanged: (d) => setEffect(effect.copyWith(
          does: d,
          count: d.counts && effect.count.isEmpty && doc.counts.isNotEmpty
              ? doc.counts.first.id
              : null)),
    ),
    if (effect.does.counts) ...[
      NumberWord(
          key: ValueKey("$prefix-amount"),
          value: effect.amount,
          onChanged: (n) => setEffect(effect.copyWith(amount: n))),
      _Plain(effect.does == GameDoes.add ? "to" : "from"),
      WordChoice<String>(
        key: ValueKey("$prefix-count"),
        value: doc.counts.any((c) => c.id == effect.count) ? effect.count : "",
        options: [
          if (!doc.counts.any((c) => c.id == effect.count)) ("", "a count"),
          for (var c in doc.counts) (c.id, c.name),
        ],
        onChanged: (id) => setEffect(effect.copyWith(count: id)),
      ),
    ],
    if (effect.does.shows)
      WordChoice<String>(
        key: ValueKey("$prefix-element"),
        value: gameShowables(doc).any((e) => e.$1 == effect.element)
            ? effect.element
            : "",
        options: [
          ("", "what?"),
          ...gameShowables(doc),
        ],
        onChanged: (id) => setEffect(effect.copyWith(element: id)),
      ),
    if (effect.does == GameDoes.scene)
      WordChoice<String>(
        key: ValueKey("$prefix-scene"),
        value: scenes.any((s) => s.id == effect.scene) ? effect.scene : "",
        options: [
          ("", "which scene?"),
          for (var (i, s) in scenes.indexed) (s.id, doc.nameOf(i)),
        ],
        onChanged: (id) => setEffect(effect.copyWith(scene: id)),
      ),
  ];
}

/// HitSentence is what punching or kicking it does (Ken, 2026-11-10), as a
/// sentence: "Beaten by two hits: Add 1 to Foes, each hit plays Thud."
class HitSentence extends StatelessWidget {
  final CanvasController controller;
  final PlaySpec spec;
  final ValueChanged<PlaySpec> onChanged;
  const HitSentence(
      {required this.controller,
      required this.spec,
      required this.onChanged,
      super.key});

  @override
  Widget build(BuildContext context) {
    var doc = controller.document;
    var sounds = gameSoundOptions(controller);
    const counts = [1, 2, 3, 5, 10];
    return SizedBox(
      width: double.infinity,
      child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            WordChoice<int>(
              key: const ValueKey("playHits"),
              value: spec.hits,
              options: [
                (0, "It cannot be hit"),
                if (spec.hits > 0 && !counts.contains(spec.hits))
                  (spec.hits, "Beaten by ${spec.hits} hits"),
                for (var n in counts)
                  (n, n == 1 ? "Beaten by one hit" : "Beaten by $n hits"),
              ],
              onChanged: (n) => onChanged(spec.copyWith(hits: n)),
            ),
            if (spec.hittable) ...[
              const _Plain(". Each hit:"),
              ...effectWords(
                  doc,
                  spec.struck,
                  (next) => onChanged(spec.copyWith(struck: next)),
                  "playStruck"),
              const _Plain(". Beaten:"),
              ...effectWords(
                  doc,
                  spec.defeated,
                  (next) => onChanged(spec.copyWith(defeated: next)),
                  "playDefeated"),
              const _Plain(", and each hit plays"),
              WordChoice<String>(
                key: const ValueKey("playHitSound"),
                value: sounds.any((o) => o.$1 == spec.hitSound)
                    ? spec.hitSound
                    : "",
                options: sounds,
                onChanged: (id) => onChanged(spec.copyWith(hitSound: id)),
              ),
            ],
          ]),
    );
  }
}
