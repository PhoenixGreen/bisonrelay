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
import 'package:bruig/plugin_system/canvas/ui/settings/controls_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/game_counts_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/play_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// game_panel.dart is the Game tab, there while the canvas is being made into
// a game -- see CanvasDocument.game and the Make game button in the bar --
// laid out as the Design tab is: a heading for what is picked, then
// sections that fold, each saying in a line how it is set.
//
// With an element picked, what that element does when the game is played:
// every element is still until it is given something to do. With nothing
// picked -- or the background -- the game itself: its scenes as a strip,
// the counts it keeps, its players and their controls. And the game is
// played from the heading, whichever it is.

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

  /// _gameSettings are what the whole game has: its scenes, the counts it
  /// keeps, and its players with their controls.
  List<Widget> _gameSettings() {
    var doc = controller.document;
    var scenes = doc.allScenes;
    var hasMaster = doc.masterOn && doc.master != null && !doc.editingMaster;
    var counts = doc.counts;
    var players = doc.players.length;
    return [
      if (scenes.length > 1 || hasMaster)
        CanvasControlGroup(label: "Scenes", children: [
          _SceneStrip(controller: controller, hasMaster: hasMaster),
          if (scenes.length > 1)
            CanvasDropdown<String>(
              key: const ValueKey("gameStart"),
              label: "Starts on",
              value:
                  scenes.any((s) => s.id == doc.gameStart) ? doc.gameStart : "",
              width: 170,
              options: [
                ("", "The scene showing"),
                for (var (i, s) in scenes.indexed) (s.id, doc.nameOf(i)),
              ],
              onChanged: (id) =>
                  controller.apply(controller.document.copyWith(gameStart: id)),
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
              onChanged: (over) => controller
                  .apply(controller.document.copyWith(masterOver: over)),
            ),
          CanvasHint(hasMaster
              ? "The flag marks where Play starts the game, and where it "
                  "starts again; the bar, where the master shows -- click a "
                  "scene to show it there or not. Over every scene, the "
                  "master is the game's HUD: a Counter for the coins, "
                  "another for the lives."
              : "The flag marks where Play starts the game, and where it "
                  "starts again: a title screen, a menu. A pickup, a hazard "
                  "or a count can go on to the next scene, a level each."),
        ]),
      CanvasSection(
        key: const ValueKey("gameSection-counts"),
        icon: Icons.bar_chart,
        title: "Counts",
        summary: counts.isEmpty
            ? "None yet"
            : [for (var c in counts) c.name].join(" · "),
        remember: "game.counts",
        initiallyOpen: true,
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
      CanvasSection(
        key: const ValueKey("gameSection-players"),
        icon: Icons.people_outline,
        title: "Players and controls",
        summary: "$players player${players == 1 ? "" : "s"}",
        remember: "game.players",
        children: [GameControlsGroup(controller: controller)],
      ),
      const CanvasHint(
          "Pick an element to give it something to do when the game is "
          "played: walk, jump, be a wall to stand on. Every element is "
          "still until it is."),
    ];
  }

  /// _elementSettings are what [e] does when the game is played.
  List<Widget> _elementSettings(CanvasElement e) {
    // As the rest of the settings do: one undo step a change, however many
    // writes a drag of it makes.
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
