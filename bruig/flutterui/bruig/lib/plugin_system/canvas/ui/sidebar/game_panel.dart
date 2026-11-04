import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/controls_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/game_counts_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/game_ready.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/play_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// game_panel.dart is the Game tab, shown while the canvas is being made into a
// game (see CanvasDocument.game): a heading for what is picked, with Play, then
// flat sections, each saying in a line how it is set, with what the game still
// lacks first. With an element picked, what it does in the game (every element
// is still until given something to do); with nothing or the background
// picked, the game itself: its scenes, counts, players and controls.

class CanvasGamePanel extends StatelessWidget {
  final CanvasController controller;
  const CanvasGamePanel({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => CanvasWatch<(int, bool)>(
        listenable: controller,
        select: () => (controller.revision, controller.gaming),
        builder: (context, _) {
          var picked =
              controller.selection.length == 1 && !controller.backgroundSelected
                  ? controller.document.elementById(controller.selection.first)
                  : null;
          if (picked is BackgroundElement) picked = null;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heading(context, picked),
                const Divider(height: 1),
                Expanded(
                  child: ScrollConfiguration(
                    behavior: const CanvasNoScrollbar(),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
                      child: CanvasControlScope(
                        maxWidth: 240,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: picked == null
                              ? _gameSettings()
                              : _elementSettings(picked),
                        ),
                      ),
                    ),
                  ),
                ),
              ]);
        },
      );

  /// _heading is what is picked -- its kind and how it is played, in a
  /// coloured tile -- or the game; and Play.
  Widget _heading(BuildContext context, CanvasElement? picked) {
    var colors = ThemeNotifier.of(context).colors;
    var doc = controller.document;
    var as = picked?.base.play.as;
    var (icon, tint) = picked == null
        ? (Icons.sports_esports_outlined, const Color(0xFF30A46C))
        : switch (as!) {
            PlayAs.pickup => (playIcons[as]!, const Color(0xFFF2C94C)),
            PlayAs.hazard => (playIcons[as]!, const Color(0xFFE5484D)),
            PlayAs.none => (playIcons[as]!, colors.outline),
            _ => (playIcons[as]!, const Color(0xFF3D7EFF)),
          };
    var players = doc.players.length;
    var scenes = doc.allScenes.length;
    var title = picked == null
        ? (doc.title.isEmpty ? "The game" : doc.title)
        : (picked.name.isEmpty ? picked.kind.label : picked.name);
    var subtitle = picked == null
        ? "A game · $scenes scene${scenes == 1 ? "" : "s"} · "
            "$players player${players == 1 ? "" : "s"}"
        : "${picked.kind.label} · ${as!.label}";
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: tint),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                key: const ValueKey("gameHeading"),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface)),
            Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(width: 6),
        // Play, as a pill: green to start, red to stop.
        Material(
          color: controller.gaming
              ? const Color(0xFFE5484D)
              : const Color(0xFF30A46C),
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            key: const ValueKey("playGame"),
            borderRadius: BorderRadius.circular(15),
            onTap: () => controller.gaming = !controller.gaming,
            child: SizedBox(
              height: 30,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(controller.gaming ? Icons.stop : Icons.play_arrow,
                      size: 16, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(controller.gaming ? "Stop" : "Play",
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// _gameSettings are what the whole game has: what it still lacks, its
  /// scenes, the counts it keeps, and its controls -- or, with nothing on
  /// this scene played yet, the games to start from first.
  List<Widget> _gameSettings() {
    var doc = controller.document;
    var scenes = doc.allScenes;
    var hasMaster = doc.masterOn && doc.master != null && !doc.editingMaster;
    var counts = doc.counts;
    var checks = gameChecks(controller);
    var lacking = checks.where((k) => !k.done).length;
    var startName = doc.gameStart.isEmpty
        ? null
        : scenes.indexed
            .where((s) => s.$2.id == doc.gameStart)
            .map((s) => doc.nameOf(s.$1))
            .firstOrNull;
    return [
      if (gameIsEmpty(doc)) _StartFrom(controller: controller),
      GameSection(
        key: const ValueKey("gameSection-ready"),
        title: "Ready to play",
        summary: lacking == 0
            ? "all set"
            : "$lacking thing${lacking == 1 ? "" : "s"} to add",
        children: [
          for (var k in checks)
            _CheckRow(check: k, onFix: () => k.make(controller)),
        ],
      ),
      if (scenes.length > 1 || hasMaster)
        GameSection(
            key: const ValueKey("gameSection-scenes"),
            title: "Scenes",
            summary: [
              "starts on ${startName ?? "the scene showing"}",
              if (hasMaster && doc.masterOver) "HUD over all",
            ].join(" · "),
            children: [
              CanvasControlGroup(
                  label: "Scenes",
                  hideCaption: true,
                  rule: false,
                  children: [
                    _SceneStrip(controller: controller, hasMaster: hasMaster),
                    if (scenes.length > 1)
                      CanvasDropdown<String>(
                        key: const ValueKey("gameStart"),
                        label: "Starts on",
                        value: scenes.any((s) => s.id == doc.gameStart)
                            ? doc.gameStart
                            : "",
                        width: 170,
                        options: [
                          ("", "The scene showing"),
                          for (var (i, s) in scenes.indexed)
                            (s.id, doc.nameOf(i)),
                        ],
                        onChanged: (id) => controller
                            .apply(controller.document.copyWith(gameStart: id)),
                      ),
                    if (hasMaster)
                      CanvasDropdown<bool>(
                        key: const ValueKey("gameMasterOver"),
                        label: "The master",
                        value: doc.masterOver,
                        width: 170,
                        options: const [
                          (false, "Under every scene"),
                          (true, "Over every scene: a HUD"),
                        ],
                        onChanged: (over) => controller.apply(
                            controller.document.copyWith(masterOver: over)),
                      ),
                    CanvasHint(hasMaster
                        ? "The flag marks where Play starts the game, and "
                            "where it starts again; the bar, where the master "
                            "shows -- click a scene to show it there or not. "
                            "Over every scene, the master is the game's HUD: "
                            "a Counter for the coins, another for the lives."
                        : "The flag marks where Play starts the game, and "
                            "where it starts again: a title screen, a menu. A "
                            "pickup, a hazard or a count can go on to the next "
                            "scene, a level each."),
                  ]),
            ]),
      if (!doc.editingMaster && controller.timelineChannels.isNotEmpty)
        _sceneSounds(),
      GameSection(
        key: const ValueKey("gameSection-counts"),
        title: "Counts",
        summary: counts.isEmpty
            ? "None yet"
            : [for (var c in counts) c.name].join(" · "),
        children: [
          CanvasControlGroup(
            label: "Counts",
            hideCaption: true,
            rule: false,
            children: [
              ...gameCountCards(controller),
              const CanvasHint(
                  "The numbers the game keeps -- coins, lives, keys. A "
                  "pickup or a hazard adds to one or takes from it; a "
                  "Counter element shows one."),
            ],
          ),
        ],
      ),
      _ControlsSection(controller: controller),
      const SizedBox(height: 4),
      const CanvasHint(
          "Pick an element to give it something to do when the game is "
          "played: walk, jump, be a wall to stand on. Every element is "
          "still until it is."),
    ];
  }

  /// _sceneSounds is what each mixer channel does as the game comes to the
  /// scene showing: keeps playing, stops, or plays one of its slots -- see
  /// CanvasScene.gameSounds.
  Widget _sceneSounds() {
    var doc = controller.document;
    var scene = doc.scene;
    var session = controller.session;
    var set = scene.gameSounds;
    void write(String channel, String does) {
      var next = {...set};
      if (does.isEmpty) {
        next.remove(channel);
      } else {
        next[channel] = does;
      }
      var d = controller.document;
      controller.apply(d.withScene(d.at, d.scene.copyWith(gameSounds: next)));
    }

    var changed = set.length;
    return GameSection(
      key: const ValueKey("gameSection-sceneSounds"),
      title: "When ${doc.nameOf(doc.at)} starts",
      summary: changed == 0
          ? "every channel keeps playing"
          : "$changed channel${changed == 1 ? "" : "s"} changed",
      children: [
        CanvasControlGroup(
            label: "When it starts",
            hideCaption: true,
            rule: false,
            children: [
              for (var ch in controller.timelineChannels)
                CanvasDropdown<String>(
                  key: ValueKey("sceneSound-${ch.key}"),
                  label: ch.name,
                  value: () {
                    var v = set[ch.key] ?? "";
                    if (v.isEmpty || v == "stop") return v;
                    var slot = gameSoundOf(v);
                    return slot is GameSoundSlot &&
                            session.find(slot.clip)?.$1 == ch.key
                        ? v
                        : "";
                  }(),
                  width: 150,
                  options: [
                    ("", "Keeps playing"),
                    ("stop", "Stops"),
                    for (var row = 0; row < session.rows; row++)
                      if (session.at(ch.key, row) case var clip?)
                        (
                          gameSoundSlot(clip.id),
                          "Plays ${clip.name.isEmpty ? session.sceneName(row) : clip.name}"
                        ),
                  ],
                  onChanged: (v) => write(ch.key, v),
                ),
              const CanvasHint(
                  "What each channel of the mixer does as the game comes to "
                  "this scene: its music changed, a narrator's line. A slot "
                  "plays at once in a game, unless its own Launch waits for "
                  "a beat or a bar -- music on the bar, with Fade, changes "
                  "without a click."),
            ]),
      ],
    );
  }

  /// _elementSettings are what [e] does when the game is played.
  List<Widget> _elementSettings(CanvasElement e) {
    // One undo step a change, however many writes a drag makes, as in the
    // rest of the settings.
    void write(CanvasElement next) {
      controller.beginInteraction();
      controller.replaceElement(next, transient: true);
    }

    void commit() => controller.endInteraction();
    void begin() => controller.beginInteraction();

    if (e is AudioElement) {
      return const [
        CanvasHint("A sound plays on the timeline, or when a pickup is "
            "touched: there is nothing for it to do in the game of its own."),
      ];
    }
    return gameElementSettings(controller, e, write, begin, commit);
  }
}

/// _CheckRow is one thing the game needs: a tick or a mark, what it is and
/// how it stands, and -- lacking it -- the button that adds it.
class _CheckRow extends StatelessWidget {
  final GameCheck check;
  final VoidCallback onFix;
  const _CheckRow({required this.check, required this.onFix});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var done = check.done;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          key: ValueKey("gameCheck-${check.id}-${done ? "done" : "lacking"}"),
          width: 16,
          height: 16,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
              color: done ? const Color(0xFF3CCF7A) : const Color(0xFFF2B33D),
              shape: BoxShape.circle),
          child: Icon(done ? Icons.check : Icons.priority_high,
              size: 11, color: const Color(0xFF101114)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(check.label,
                style: TextStyle(fontSize: 12, color: colors.onSurface)),
            Text(check.says,
                style:
                    TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant)),
          ]),
        ),
        if (!done) ...[
          const SizedBox(width: 6),
          CanvasTextButton(
            key: ValueKey("gameFix-${check.id}"),
            label: check.fix,
            onPressed: onFix,
          ),
        ],
      ]),
    );
  }
}

/// _StartFrom is a new game's first choice: a platformer, a top-down
/// game or an empty one, made on this scene with one press.
class _StartFrom extends StatefulWidget {
  final CanvasController controller;
  const _StartFrom({required this.controller});

  @override
  State<_StartFrom> createState() => _StartFromState();
}

class _StartFromState extends State<_StartFrom> {
  GameStarter _kind = GameStarter.platformer;
  bool _busy = false;
  String _said = "";

  Future<void> _make() async {
    var prefs = context.read<CanvasPreferences>();
    var snackbar = SnackBarModel.of(context, listen: false);
    setState(() {
      _busy = true;
      _said = "Making ${_kind.label.toLowerCase()}…";
    });
    var said = await startGame(widget.controller, _kind,
        allowFetching: prefs.allowFetching);
    // Said in a snackbar: once made, this section has gone.
    snackbar.success(said);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _said = "";
    });
  }

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return GameSection(
      key: const ValueKey("gameSection-start"),
      title: "Start from",
      summary: "nothing is played yet",
      children: [
        for (var k in GameStarter.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: k == _kind
                  ? colors.secondaryContainer
                  : colors.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                      color:
                          k == _kind ? colors.primary : colors.outlineVariant)),
              child: InkWell(
                key: ValueKey("gameStarter-${k.name}"),
                borderRadius: BorderRadius.circular(8),
                onTap: _busy ? null : () => setState(() => _kind = k),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(children: [
                    Icon(
                        switch (k) {
                          GameStarter.platformer => Icons.directions_run,
                          GameStarter.topDown => Icons.open_with,
                          GameStarter.empty => Icons.crop_square,
                        },
                        size: 18,
                        color: k == _kind
                            ? colors.onSecondaryContainer
                            : colors.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(k.label,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onSurface)),
                            Text(k.says,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: colors.onSurfaceVariant)),
                          ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        Text(
            _said.isNotEmpty
                ? _said
                : "Made on this scene, with Kenney's art where it can be "
                    "fetched, every part of it already wired: change any of "
                    "it after.",
            key: const ValueKey("gameStartSays"),
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
        const SizedBox(height: 8),
        CanvasTextButton(
          key: const ValueKey("gameStartMake"),
          label: _busy ? "Making…" : "Make it",
          icon: Icons.auto_awesome_outlined,
          primary: true,
          onPressed: _busy ? null : _make,
        ),
      ],
    );
  }
}

/// _ControlsSection is the game's controls, said in a line -- and, with
/// Change, each player's keys and buttons.
class _ControlsSection extends StatefulWidget {
  final CanvasController controller;
  const _ControlsSection({required this.controller});

  @override
  State<_ControlsSection> createState() => _ControlsSectionState();
}

class _ControlsSectionState extends State<_ControlsSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    var doc = widget.controller.document;
    var players = doc.players.length;
    return GameSection(
      key: const ValueKey("gameSection-controls"),
      title: "Controls",
      summary: players > 1
          ? "$players players"
          : gameControlsLine(doc.controlsFor(1)),
      action: CanvasTextButton(
        key: const ValueKey("controlsChange"),
        label: _open ? "Done" : "Change",
        onPressed: () => setState(() => _open = !_open),
      ),
      children: [
        // One player's said in the line above; more, each in a line here.
        if (!_open && players > 1)
          for (var p in doc.players.toList()..sort())
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                  "${players > 1 ? "Player $p: " : ""}"
                  "${gameControlsLine(doc.controlsFor(p))}",
                  style: TextStyle(
                      fontSize: 11,
                      color:
                          ThemeNotifier.of(context).colors.onSurfaceVariant)),
            )
        else if (_open)
          GameControlsGroup(controller: widget.controller),
      ],
    );
  }
}

/// _SceneStrip is the game's scenes, small, in a row: the flag on the one it
/// starts on, the bar where the master shows -- and, with a master, a click
/// on one shows it there or not.
class _SceneStrip extends StatelessWidget {
  final CanvasController controller;
  final bool hasMaster;
  const _SceneStrip({required this.controller, required this.hasMaster});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var doc = controller.document;
    var scenes = doc.allScenes;
    var page = doc.size;
    var aspect =
        page.width <= 0 || page.height <= 0 ? 16 / 9 : page.width / page.height;
    var start = doc.gameStart.isEmpty
        ? doc.at
        : math.max(0, doc.sceneIndexNamed(doc.gameStart));
    return SizedBox(
      width: double.infinity,
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: scenes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          var scene = scenes[i];
          var hud = hasMaster && !scene.masterOff;
          return SizedBox(
            width: 64,
            child: Material(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(
                      color: i == start
                          ? const Color(0xFFF2B33D)
                          : colors.outlineVariant)),
              child: InkWell(
                key: ValueKey("gameScene-$i"),
                borderRadius: BorderRadius.circular(6),
                onTap: hasMaster
                    ? () => controller.setSceneMasterOff(i, !scene.masterOff)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(children: [
                    AspectRatio(
                      aspectRatio: aspect,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Stack(fit: StackFit.expand, children: [
                          CustomPaint(
                              painter: _SceneThumb(
                                  document: doc,
                                  index: i,
                                  images: controller.images)),
                          if (hud)
                            Positioned(
                              left: 3,
                              right: 3,
                              top: 3,
                              height: 5,
                              child: DecoratedBox(
                                key: ValueKey("gameSceneHud-$i"),
                                decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(2)),
                              ),
                            ),
                          if (i == start)
                            const Positioned(
                              right: 2,
                              bottom: 2,
                              child: Icon(Icons.flag,
                                  key: ValueKey("gameSceneStart"),
                                  size: 12,
                                  color: Color(0xFFF2B33D)),
                            ),
                        ]),
                      ),
                    ),
                    const Spacer(),
                    Text(doc.nameOf(i),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface)),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// _SceneThumb draws one scene, small, with the document's own renderer --
/// as the Scenes panel does.
class _SceneThumb extends CustomPainter {
  final CanvasDocument document;
  final int index;
  final CanvasImageStore images;
  _SceneThumb(
      {required this.document, required this.index, required this.images})
      : super(repaint: images);

  @override
  void paint(Canvas canvas, Size size) {
    var page = document.size;
    if (page.width <= 0 || page.height <= 0) return;
    var scene = document.goToScene(index).copyWith(onMaster: false);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / page.width, size.height / page.height);
    paintCanvasDocument(canvas, scene,
        frame: math.max(0, scene.frames - 1) ~/ 2, images: images);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SceneThumb old) =>
      old.index != index || !identical(old.document, document);
}
