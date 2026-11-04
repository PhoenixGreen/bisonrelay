import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/kenney_packs.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/kenney_tiles.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'dart:math' as math;
import 'package:bruig/plugin_system/canvas/model/own_motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';

// game_ready.dart is what a game still lacks, said as a list -- each thing
// with the one press that adds it -- and the games to start from: a
// platformer, a top-down game, an empty one. See the Game panel.

/// GameCheck is one thing a game needs: whether it has it, said in a line,
/// and what adds it where it does not.
class GameCheck {
  final String id;
  final String label;
  final bool done;
  final String says;
  final String fix;
  final void Function(CanvasController c) make;
  const GameCheck(this.id, this.label,
      {required this.done,
      required this.says,
      required this.fix,
      required this.make});
}

/// _everything is every element in the game: each scene's, and the
/// master's.
List<CanvasElement> _everything(CanvasDocument doc) => [
      for (var s in doc.allScenes) ...s.elements,
      ...?doc.master?.elements,
    ];

String _nameOf(CanvasElement e) => e.name.isEmpty ? e.kind.label : e.name;

/// _ends is whether [d] ends a level: another scene, or the game over.
bool _ends(GameDoes d) =>
    d == GameDoes.next || d == GameDoes.scene || d == GameDoes.stop;

/// gameChecks are what [c]'s game has, and lacks: a player, something to
/// stand on, a way to win and to lose, its counts on screen.
List<GameCheck> gameChecks(CanvasController c) {
  var doc = c.document;
  var all = _everything(doc);
  var players = [
    for (var e in all)
      if (e.base.play.as.moves) e,
  ];
  var platformer = players.any((e) => e.base.play.as == PlayAs.platformer);
  var ground = [
    for (var e in all)
      if (e.base.play.as == PlayAs.solid ||
          (e is TileMapElement && e.layers.any((l) => l.solid && !l.isObjects)))
        e,
  ];
  var winners = [
    for (var e in all)
      if (e.base.play.as.touched && _ends(e.base.play.touched.does)) e,
  ];
  var counted = [
    for (var k in doc.counts)
      if (k.reach != null && (_ends(k.then.does) || k.then.does.shows)) k,
  ];
  var hazards = [
    for (var e in all)
      if (e.base.play.as == PlayAs.hazard) e,
  ];
  var losing = [
    for (var k in doc.counts)
      if (k.reach != null && k.then.does == GameDoes.restart) k,
  ];
  var shown = {
    for (var e in all)
      if (e is CounterElement && e.source == CounterSource.game) e.gameCount,
  };
  var unshown = [
    for (var k in doc.counts)
      if (!shown.contains(k.id)) k,
  ];
  String moves(CanvasElement e) => switch (e.base.play.as) {
        PlayAs.platformer => "walks and jumps",
        PlayAs.topDown => "walks every way",
        _ => "moves the view",
      };
  var countName = {for (var k in doc.counts) k.id: k.name};
  var jumps = loopJumps(doc);
  return [
    GameCheck("player", "A player",
        done: players.isNotEmpty,
        says: players.isEmpty
            ? "Nothing moves with the controls yet"
            : [
                for (var e in players.take(2))
                  "Player ${e.base.play.player} ${moves(e)}",
              ].join("; "),
        fix: "Add a player",
        make: addPlayer),
    if (platformer)
      GameCheck("ground", "Something to stand on",
          done: ground.isNotEmpty,
          says: ground.isEmpty
              ? "Only the canvas's bottom edge holds a player up"
              : "${_nameOf(ground.first)} is solid",
          fix: "Add ground",
          make: addGround),
    GameCheck("goal", "A way to win",
        done: winners.isNotEmpty || counted.isNotEmpty,
        says: winners.isNotEmpty
            ? "Touching ${_nameOf(winners.first)} "
                "${_endWords(winners.first.base.play.touched.does)}"
            : counted.isNotEmpty
                ? "${counted.first.name} at ${counted.first.reach} "
                    "${_endWords(counted.first.then.does)}"
                : "Nothing ends a level yet",
        fix: "Add a flag",
        make: addFlag),
    GameCheck("danger", "A way to lose",
        done: hazards.isNotEmpty || losing.isNotEmpty,
        says: losing.isNotEmpty
            ? "${losing.first.name} at ${losing.first.reach} start the game "
                "again"
            : hazards.isNotEmpty
                ? "${_nameOf(hazards.first)} "
                    "${hazards.first.base.play.sendsBack ? "send the player back" : "hurt"}"
                : "Nothing can go wrong yet",
        fix: "Add lives",
        make: addLives),
    GameCheck("loops", "Smooth round the loop",
        done: jumps.isEmpty,
        says: jumps.isEmpty
            ? "Nothing jumps as the timeline loops"
            : "${_and([
                    for (var j in jumps.take(3)) _nameOf(j.element),
                  ])}${jumps.length > 3 ? " and ${jumps.length - 3} more" : ""}"
                " ${jumps.length == 1 ? "jumps" : "jump"} as the timeline "
                "loops",
        fix: "Close the loops",
        make: (c) => closeLoops(c, loopJumps(c.document))),
    if (doc.counts.isNotEmpty)
      GameCheck("hud", "The counts on screen",
          done: unshown.isEmpty,
          says: unshown.isEmpty
              ? "${[for (var k in doc.counts) k.name].join(", ")} shown"
              : "${_and([for (var k in unshown) k.name])} "
                  "${unshown.length == 1 ? "is" : "are"} kept, but nothing "
                  "shows ${unshown.length == 1 ? "it" : "them"}",
          fix: "Show on a HUD",
          make: (c) => showCounts(c, [
                for (var k in unshown)
                  if (countName.containsKey(k.id)) k
              ])),
  ];
}

/// LoopJump is an element that jumps as its scene's timeline loops: on
/// [scene], where the playhead goes from [from] back to [to], it is not
/// where it was.
typedef LoopJump = ({int scene, CanvasElement element, int from, int to});

/// loopJumps are the elements in [doc] that jump each time their scene's
/// timeline loops (a patrol that does not end where it began), from a Loop
/// back to its target, or from the end to the start -- moved by its clips
/// or its keyframes.
List<LoopJump> loopJumps(CanvasDocument doc) {
  var out = <LoopJump>[];
  for (var (i, scene) in doc.allScenes.indexed) {
    var seen = doc.hasScenes ? doc.copyWith(sceneAt: i) : doc;
    var loop = scene.actions
        .where((a) =>
            a.kind == TimelineActionKind.loop &&
            a.repeats == 0 &&
            a.frame > a.target)
        .firstOrNull;
    var (from, to) =
        loop != null ? (loop.frame, loop.target) : (scene.frames - 1, 0);
    if (from <= to) continue;
    for (var e in scene.elements) {
      var track = e.track;
      if ((track == null || !track.posesAnything) && e.base.motion.isEmpty) {
        continue;
      }
      var a = poseWithMotion(e, from, seen), b = poseWithMotion(e, to, seen);
      if ((a.dx - b.dx).abs() > 1 ||
          (a.dy - b.dy).abs() > 1 ||
          (a.scale - b.scale).abs() > 0.01 ||
          (a.rotate - b.rotate).abs() > 0.5 ||
          (a.opacity - b.opacity).abs() > 0.02) {
        out.add((scene: i, element: e, from: from, to: to));
      }
    }
  }
  return out;
}

/// closeLoops brings each of [jumps] back round to where it was when its
/// timeline loops. Moved by keyframes, it gets a key where the loop goes
/// from, posed as where it goes to. Moved by clips, it gets a short clip
/// that carries it back over the last half second before the loop. One
/// undo step.
void closeLoops(CanvasController c, List<LoopJump> jumps) {
  var doc = c.document;
  var rate = math.max(1, doc.frameRate);
  for (var (i, scene) in doc.allScenes.indexed) {
    var here = {
      for (var j in jumps)
        if (j.scene == i) j.element.id: j
    };
    if (here.isEmpty) continue;
    var seen = doc.hasScenes ? doc.copyWith(sceneAt: i) : doc;
    doc = doc.withScene(
        i,
        scene.copyWith(elements: [
          for (var e in scene.elements)
            if (here[e.id] case var j?)
              e.base.motion.isEmpty
                  ? e.rebase(e.base.copyWith(
                      track: e.track!
                          .withKey(e.track!.at(j.to).copyWith(frame: j.from))))
                  : _comesBack(e, j, seen, rate)
            else
              e,
        ]));
  }
  c.apply(doc);
}

/// _comesBack is [e] with a clip that moves it, over the half second before
/// its loop, by however far it is from where the loop goes back to: layers
/// add, so on a layer of its own it closes the gap and nothing else.
CanvasElement _comesBack(
    CanvasElement e, LoopJump j, CanvasDocument seen, int rate) {
  var a = poseWithMotion(e, j.from, seen), b = poseWithMotion(e, j.to, seen);
  var took = math.min(rate / 2, (j.from - j.to) / 2) / rate;
  var start = j.from / rate - took;
  var m = e.base.motion;
  var layer = freeLayer(m, start, j.from / rate);
  var id = freeId(m, "${e.id}-back");
  List<MotionKey> keys(double by) => [
        const MotionKey(0, MotionNumber(0)),
        MotionKey(took, MotionNumber(by), ease: KeyframeEasing.easeInOut),
      ];
  var clip = MotionClip.ofKind(id, MotionKind.action,
      name: "Comes back",
      layer: layer,
      length: took,
      keys: {
        if ((b.dx - a.dx).abs() > 1e-6) MotionProp.x: keys(b.dx - a.dx),
        if ((b.dy - a.dy).abs() > 1e-6) MotionProp.y: keys(b.dy - a.dy),
        if ((b.rotate - a.rotate).abs() > 1e-6)
          MotionProp.turn: keys(b.rotate - a.rotate),
      }).copyWith(before: ClipHold.rest, after: ClipHold.last);
  return e.withBase(
      motion: m.withClip(clip).copyWith(placed: [
    ...m.placed,
    ClipPlacement(id: freeId(m, "$id-p"), clip: id, layer: layer, start: start),
  ]));
}

String _and(List<String> names) => names.length <= 1
    ? names.join()
    : "${names.take(names.length - 1).join(", ")} and ${names.last}";

String _endWords(GameDoes d) => switch (d) {
      GameDoes.next => "goes to the next scene",
      GameDoes.scene => "goes to another scene",
      GameDoes.stop => "ends the game",
      GameDoes.show => "shows something",
      _ => "does something",
    };

Size _page(CanvasDocument doc) => doc.size.size;

/// _floor is where the ground's top is: the canvas's bottom, less a
/// strip of ground where the starter lays one.
double _floor(CanvasDocument doc) =>
    _page(doc).height -
    (_everything(doc).any((e) => e.name == "Ground") ? _groundHeight : 0);

const double _groundHeight = 64;

void _add(CanvasController c, List<CanvasElement> elements,
    {List<GameCount> counts = const []}) {
  var doc = c.document;
  for (var e in elements) {
    doc = doc.addElement(e);
  }
  if (counts.isNotEmpty) doc = doc.copyWith(counts: [...doc.counts, ...counts]);
  c.apply(doc);
}

/// _shape is a plain box for the game: a stand-in until a picture is put
/// in its place.
ShapeElement _shape(String name, Rect r, Color fill, PlaySpec play,
        {ShapeKind kind = ShapeKind.rectangle, double corner = 6}) =>
    ShapeElement(
        ElementBase(
            id: newElementId(),
            name: name,
            x: r.left,
            y: r.top,
            width: r.width,
            height: r.height,
            play: play),
        shape: kind,
        fill: fill,
        cornerRadius: corner);

/// addPlayer adds a player at the left, standing on the ground.
void addPlayer(CanvasController c) {
  var doc = c.document;
  var floor = _floor(doc);
  _add(c, [
    _shape("Player 1", Rect.fromLTWH(64, floor - 72, 48, 72),
        const Color(0xFF7FD0B5), _playerSpec,
        corner: 14),
  ]);
}

PlaySpec get _playerSpec => PlaySpec(
    as: PlayAs.platformer,
    speed: PlayFeel.normal.speed,
    jump: PlayFeel.normal.jump,
    gravity: PlayFeel.normal.gravity);

/// addGround adds a solid strip along the canvas's bottom.
void addGround(CanvasController c) {
  var page = _page(c.document);
  _add(c, [
    _shape(
        "Ground",
        Rect.fromLTWH(
            0, page.height - _groundHeight, page.width, _groundHeight),
        const Color(0xFF6BB04A),
        const PlaySpec(as: PlayAs.solid),
        corner: 0),
  ]);
}

/// addFlag adds a flag at the right: touched, the next scene -- or, on the
/// last, the game over.
void addFlag(CanvasController c) {
  var doc = c.document;
  var page = _page(doc);
  var last = doc.at >= doc.allScenes.length - 1;
  _add(c, [
    _shape(
        "Flag",
        Rect.fromLTWH(page.width - 112, _floor(doc) - 80, 40, 80),
        const Color(0xFFF2C94C),
        PlaySpec(
            as: PlayAs.pickup,
            touched: GameEffect(does: last ? GameDoes.stop : GameDoes.next))),
  ]);
}

/// addLives adds Lives -- three, the game starting again when they are
/// gone -- where the game has none, and spikes that take one.
void addLives(CanvasController c) {
  var doc = c.document;
  var page = _page(doc);
  var lives = doc.counts.where((k) => k.name == "Lives").firstOrNull;
  var made = lives == null
      ? GameCount(newElementId(), "Lives",
          start: 3, reach: 0, then: const GameEffect(does: GameDoes.restart))
      : null;
  _add(c, [
    _shape(
        "Spikes",
        Rect.fromLTWH(page.width / 2 - 32, _floor(doc) - 32, 64, 32),
        const Color(0xFFE5484D),
        PlaySpec(
            as: PlayAs.hazard,
            touched:
                GameEffect(does: GameDoes.take, count: (lives ?? made)!.id)),
        kind: ShapeKind.triangle,
        corner: 0),
  ], counts: [
    if (made != null) made
  ]);
}

/// showCounts puts a Counter for each of [counts] along the top: on the
/// master, over every scene, where the game has one -- else on this scene.
void showCounts(CanvasController c, List<GameCount> counts) {
  var doc = c.document;
  var start = doc.counts.length - counts.length;
  var made = [
    for (var (i, k) in counts.indexed)
      CounterElement(
          ElementBase(
              id: newElementId(),
              name: k.name,
              x: 24 + (start + i) * 180.0,
              y: 16,
              width: 170,
              height: 56),
          to: 1000000,
          before: "${k.name} ",
          numberSpec: _hudText(34),
          affixSpec: _hudText(22),
          source: CounterSource.game,
          gameCount: k.id,
          keyed: false),
  ];
  var master = doc.master;
  if (doc.masterOn && master != null) {
    c.apply(doc.copyWith(
        masterOver: true,
        master: master.copyWith(elements: [
          ...master.elements,
          for (var e in made) doc.laidOut(e),
        ])));
    return;
  }
  _add(c, made);
}

TextSpec _hudText(double size) => TextSpec(
    fontSize: size,
    weight: 800,
    align: TextAlignSpec.left,
    color: const Color(0xFFFFFFFF),
    outlineWidth: 4,
    outlineColor: const Color(0xFF1A1D2A));

/// GameStarter is a game to start from.
enum GameStarter {
  platformer("A platformer",
      "A player, ground, coins and spikes, lives and coins on a HUD, a flag to the next scene"),
  topDown("A top-down game",
      "A player walking every way, walls, a key and a door, the view following"),
  empty("An empty game",
      "Only the counts and controls: everything else added by hand");

  final String label;
  final String says;
  const GameStarter(this.label, this.says);
}

/// startGame lays [kind] out on this scene, with Kenney's pictures where his
/// platformer pack is kept or can be fetched, plain shapes where not; the
/// counts on screen follow as a second undo step. What it says back is how
/// it went.
Future<String> startGame(CanvasController c, GameStarter kind,
    {required bool allowFetching}) async {
  var doc = c.document;
  var coins = doc.counts.where((k) => k.name == "Coins").firstOrNull ??
      GameCount(newElementId(), "Coins");
  var lives = doc.counts.where((k) => k.name == "Lives").firstOrNull ??
      GameCount(newElementId(), "Lives",
          start: 3, reach: 0, then: const GameEffect(does: GameDoes.restart));
  var keys = doc.counts.where((k) => k.name == "Keys").firstOrNull ??
      GameCount(newElementId(), "Keys");
  var wanted = switch (kind) {
    GameStarter.platformer => [coins, lives],
    GameStarter.topDown => [keys],
    GameStarter.empty => [coins, lives],
  };
  var counts = [
    for (var k in wanted)
      if (!doc.counts.any((h) => h.id == k.id)) k,
  ];
  if (kind == GameStarter.empty) {
    c.apply(doc.copyWith(game: true, counts: [...doc.counts, ...counts]));
    return "Coins and Lives are kept: add what plays from the canvas.";
  }
  var art = await _KenneyArt.open(allowFetching);
  var page = _page(c.document);
  var made = kind == GameStarter.platformer
      ? await _platformer(page, coins, lives, art)
      : await _topDown(page, keys, art);
  doc = c.document.copyWith(game: true);
  for (var e in made) {
    doc = doc.addElement(e);
  }
  c.apply(doc.copyWith(counts: [...doc.counts, ...counts]));
  // The counts on screen, after: a step of its own.
  var hud = [
    for (var k in wanted)
      if (!_everything(c.document).any((e) =>
          e is CounterElement &&
          e.source == CounterSource.game &&
          e.gameCount == k.id))
        k,
  ];
  if (hud.isNotEmpty) showCounts(c, hud);
  return art == null
      ? "Made with plain shapes: Kenney's pictures could not be fetched. "
          "Allow fetching in Settings to have them."
      : "Made with Kenney's pictures. Change any of it after.";
}

/// _KenneyArt is Kenney's platformer pack, opened, for the starters.
class _KenneyArt {
  final List<SpriteGroup> groups;
  final Archive archive;
  _KenneyArt(this.groups, this.archive);

  static Future<_KenneyArt?> open(bool allowFetching) async {
    try {
      var pack =
          kenneyPacks.firstWhere((p) => p.slug == "platformer-art-deluxe");
      var file = await kenneyFetch(pack,
          allowFetching: allowFetching, proxied: await networkIsProxied());
      if (file == null) return null;
      var (groups, archive) = await kenneyGroups(file);
      return _KenneyArt(groups, archive);
    } catch (_) {
      return null;
    }
  }

  /// sprite is [files] of the pack as a sprite in [base], or null.
  Future<SpriteElement?> sprite(
      ElementBase base, String name, List<String> files) async {
    try {
      return await spriteFromGroup(SpriteElement(base),
          SpriteGroup(name, "", files, files.length > 1), archive);
    } catch (_) {
      return null;
    }
  }

  /// tiles is [files] of the pack laid out as a tile set.
  Future<TileSource?> tiles(String name, List<String> files) async {
    try {
      return await tileSourceFrom(TileSheetOffer(name, files: files), archive);
    } catch (_) {
      return null;
    }
  }
}

ElementBase _base(String name, Rect r, PlaySpec play) => ElementBase(
    id: newElementId(),
    name: name,
    x: r.left,
    y: r.top,
    width: r.width,
    height: r.height,
    play: play);

/// _piece is [name] in [r]: Kenney's [files] where there is [art], else a
/// shape of [fill].
Future<CanvasElement> _piece(_KenneyArt? art, String name, Rect r,
    PlaySpec play, List<String> files, Color fill,
    {ShapeKind kind = ShapeKind.rectangle, double corner = 6}) async {
  if (art != null) {
    var made = await art.sprite(_base(name, r, play), name, files);
    if (made != null) return made;
  }
  return _shape(name, r, fill, play, kind: kind, corner: corner);
}

/// _strip is something solid laid along [r] a tile deep: Kenney's [file]
/// in a row where there is [art] -- a picture stretched along it would be
/// one tile, small, in the middle -- else a shape of [fill].
Future<CanvasElement> _strip(
    _KenneyArt? art, String name, Rect r, String file, Color fill) async {
  var source = await art?.tiles(name, [file]);
  if (source != null) {
    var cell = r.height;
    var across = (r.width / cell).ceil();
    return TileMapElement(_base(name, r, const PlaySpec()),
        sources: [source],
        cell: cell,
        pixelArt: false,
        layers: [
          TileLayer(name: name, solid: true, cells: {
            for (var col = 0; col < across; col++)
              cellKey(col, 0): TileRef.of(0, 0).word,
          }),
        ]);
  }
  return _shape(name, r, fill, const PlaySpec(as: PlayAs.solid), corner: 0);
}

/// _ground is a strip of solid ground along the bottom of [page].
Future<CanvasElement> _ground(_KenneyArt? art, Size page) => _strip(
    art,
    "Ground",
    Rect.fromLTWH(0, page.height - _groundHeight, page.width, _groundHeight),
    "Tiles/grassMid.png",
    const Color(0xFF6BB04A));

Future<List<CanvasElement>> _platformer(
    Size page, GameCount coins, GameCount lives, _KenneyArt? art) async {
  var floor = page.height - _groundHeight;
  var player = await _piece(
      art,
      "Player 1",
      Rect.fromLTWH(80, floor - 92, 66, 92),
      _playerSpec,
      [
        "Player/p1_stand.png",
        for (var i = 1; i <= 11; i++)
          "Player/p1_walk/PNG/p1_walk${i.toString().padLeft(2, "0")}.png",
        "Player/p1_jump.png",
      ],
      const Color(0xFF7FD0B5),
      corner: 14);
  // Stood still, walking and jumping: the frames the game plays for each.
  if (player is SpriteElement) {
    player = player.copyWith(actions: const [
      SpriteAction("Idle",
          frames: {
            SpriteFacing.front: [0]
          },
          fps: 2),
      SpriteAction("Walk",
          frames: {
            SpriteFacing.front: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
          },
          fps: 20),
      SpriteAction("Jump",
          frames: {
            SpriteFacing.front: [12]
          },
          fps: 2),
    ], action: "Idle");
  }
  var coin = PlaySpec(
      as: PlayAs.pickup,
      touched: GameEffect(does: GameDoes.add, count: coins.id));
  var made = <CanvasElement>[
    await _ground(art, page),
    // A ledge three tiles up, which the Normal jump reaches.
    await _strip(
        art,
        "Ledge",
        Rect.fromLTWH(page.width * 0.42, floor - 192, 192, 64),
        "Tiles/grassHalf.png",
        const Color(0xFF7CC357)),
    for (var i = 0; i < 3; i++)
      await _piece(
          art,
          "Coin",
          Rect.fromLTWH(page.width * 0.42 + 16 + i * 56, floor - 248, 44, 44),
          coin,
          const ["Items/coinGold.png"],
          const Color(0xFFF2C94C),
          kind: ShapeKind.circle),
    for (var i = 0; i < 3; i++)
      await _piece(
          art,
          "Coin",
          Rect.fromLTWH(page.width * 0.18 + i * 56, floor - 56, 44, 44),
          coin,
          const ["Items/coinGold.png"],
          const Color(0xFFF2C94C),
          kind: ShapeKind.circle),
    await _piece(
        art,
        "Spikes",
        Rect.fromLTWH(page.width * 0.72, floor - 48, 64, 48),
        PlaySpec(
            as: PlayAs.hazard,
            touched: GameEffect(does: GameDoes.take, count: lives.id)),
        const ["Items/spikes.png"],
        const Color(0xFFE5484D),
        kind: ShapeKind.triangle,
        corner: 0),
    await _piece(
        art,
        "Flag",
        Rect.fromLTWH(page.width - 120, floor - 70, 70, 70),
        const PlaySpec(
            as: PlayAs.pickup, touched: GameEffect(does: GameDoes.next)),
        const ["Items/flagGreen.png", "Items/flagGreen2.png"],
        const Color(0xFF30A46C)),
    player,
  ];
  return made;
}

Future<List<CanvasElement>> _topDown(
    Size page, GameCount keys, _KenneyArt? art) async {
  const wall = PlaySpec(as: PlayAs.solid);
  const t = 32.0;
  // Plain, as a wall seen from above is: Kenney's are drawn side on.
  Future<CanvasElement> block(String name, Rect r) async =>
      _shape(name, r, const Color(0xFF8A8FA0), wall, corner: 0);
  var door = await _piece(
      art,
      "Door",
      Rect.fromLTWH(page.width - t, page.height / 2 - 48, t, 96),
      wall,
      const ["Tiles/lock_yellow.png"],
      const Color(0xFFB8902A),
      corner: 0);
  return [
    await block("Wall", Rect.fromLTWH(0, 0, page.width, t)),
    await block("Wall", Rect.fromLTWH(0, page.height - t, page.width, t)),
    await block("Wall", Rect.fromLTWH(0, 0, t, page.height)),
    await block(
        "Wall", Rect.fromLTWH(page.width - t, 0, t, page.height / 2 - 48)),
    await block(
        "Wall",
        Rect.fromLTWH(
            page.width - t, page.height / 2 + 48, t, page.height / 2 - 48)),
    await block("Wall",
        Rect.fromLTWH(page.width / 2 - t / 2, t, t, page.height * 0.55)),
    door,
    await _piece(
        art,
        "Key",
        Rect.fromLTWH(page.width * 0.75, page.height * 0.25, 44, 44),
        PlaySpec(
            as: PlayAs.pickup,
            touched: GameEffect(does: GameDoes.hide, element: door.id)),
        const ["Items/keyYellow.png"],
        const Color(0xFFF2C94C),
        kind: ShapeKind.diamond),
    await _piece(
        art,
        "Way out",
        // Behind the door: reached only once the key has opened it.
        Rect.fromLTWH(page.width - 12, page.height / 2 - 48, 12, 96),
        const PlaySpec(
            as: PlayAs.pickup, touched: GameEffect(does: GameDoes.next)),
        const [],
        const Color(0x0030A46C)),
    await _piece(
        art,
        "Player 1",
        Rect.fromLTWH(96, page.height / 2 - 40, 56, 76),
        const PlaySpec(as: PlayAs.topDown, speed: 300),
        const ["Player/p1_front.png"],
        const Color(0xFF7FD0B5),
        corner: 14),
  ];
}

/// gameIsEmpty is whether nothing on this scene is played yet: a new game,
/// to be started from something.
bool gameIsEmpty(CanvasDocument doc) =>
    doc.elements.every((e) => e.base.play.isNone);
