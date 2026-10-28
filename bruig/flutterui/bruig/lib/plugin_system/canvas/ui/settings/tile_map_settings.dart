import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/render/tile_map_painter.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/kenney_packs.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/kenney_tiles.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/sprite_settings.dart' show findGrid;
import 'package:bruig/plugin_system/canvas/ui/tile_painting.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

// tile_map_settings.dart is a Tile map's settings: its tile sets -- each a
// sheet brought in or taken from one of Kenney's packs, sliced by its grid,
// its tiles laid out to pick from -- painting them onto the map, and its
// layers.

/// pickedTileSource is the tile set shown in each map's settings, by id.
final Map<String, int> pickedTileSource = {};

List<Widget> tileMapSettings(BuildContext context, CanvasController controller, TileMapElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  void now(TileMapElement next) {
    begin();
    write(next);
    commit();
  }

  var painting = controller.tilePaint?.id == e.id ? controller.tilePaint : null;
  var s = e.sources.isEmpty ? -1 : (pickedTileSource[e.id] ?? 0).clamp(0, e.sources.length - 1).toInt();
  var source = s < 0 ? null : e.sources[s];
  return [
    section(e, "tileMapTiles",
        icon: Icons.grid_on,
        title: "Tiles",
        summary: e.sources.isEmpty
            ? "None yet"
            : "${e.sources.length} ${e.sources.length == 1 ? "set" : "sets"} · ${source!.count} tiles in ${source.name}",
        initiallyOpen: true,
        children: [
          if (source != null) ...[
            if (e.sources.length > 1)
              CanvasDropdown<int>(
                key: const ValueKey("tileMapSource"),
                label: "Tile set",
                value: s,
                options: [for (var (i, x) in e.sources.indexed) (i, x.name.isEmpty ? "Set ${i + 1}" : x.name)],
                onChanged: (i) {
                  pickedTileSource[e.id] = i;
                  controller.tilePaint?.set();
                  controller.notifyListeners();
                },
              ),
            TilePalette(
              key: ValueKey("tilePalette-${e.id}-$s"),
              controller: controller,
              map: e,
              source: s,
              picked: painting?.stamp,
              onPick: (t) {
                if (controller.tilePaint?.id != e.id) controller.paintTiles(e.id);
                var p = controller.tilePaint!;
                p.set(stamp: t, tool: p.tool == TileTool.erase || p.tool == TileTool.picker ? TileTool.paint : null);
              },
            ),
            CanvasControlGroup(
              key: const ValueKey("tileMapGrid"),
              label: "Grid",
              help: "How the sheet is cut into tiles: each tile's size, how far "
                  "in from the edge the first starts, and the gap between them, "
                  "in the sheet's pixels.",
              children: [
                for (var (key, label, value, set) in [
                  ("tileMapTileW", "Width", source.tileW, (int v) => source.copyWith(tileW: v)),
                  ("tileMapTileH", "Height", source.tileH, (int v) => source.copyWith(tileH: v)),
                  ("tileMapMargin", "Margin", source.margin, (int v) => source.copyWith(margin: v)),
                  ("tileMapSpacing", "Gap", source.spacing, (int v) => source.copyWith(spacing: v)),
                ])
                  CanvasStepper(
                    key: ValueKey(key),
                    label: label,
                    value: value.toDouble(),
                    min: key.endsWith("W") || key.endsWith("H") ? 1 : 0,
                    max: 1024,
                    step: 1,
                    onChanged: (v) => write(e.copyWith(
                        sources: [for (var (i, x) in e.sources.indexed) i == s ? set(v.round()) : x])),
                    onCommit: commit,
                  ),
              ],
            ),
            CanvasToggle(
              key: const ValueKey("tileMapPixelArt"),
              label: "Pixel art: square pixels",
              value: e.pixelArt,
              onChanged: (v) => now(e.copyWith(pixelArt: v)),
            ),
          ],
          TileSetAdder(key: ValueKey("tileSetAdder-${e.id}"), controller: controller, map: e),
          if (source != null)
            CanvasTextButton(
              key: const ValueKey("tileMapRemoveSource"),
              label: "Take this set out",
              icon: Icons.delete_outline,
              onPressed: () {
                pickedTileSource[e.id] = math.max(0, s - 1);
                now(e.withoutSource(s));
              },
            ),
        ]),
    section(e, "tileMapPaint",
        icon: Icons.brush_outlined,
        title: "Paint",
        summary: painting == null ? "Off" : "${painting.tool.label} · ${e.layers[painting.layer].name}",
        initiallyOpen: true,
        children: [_paintGroup(controller, e, painting, now)]),
    section(e, "tileMapLayers",
        icon: Icons.layers_outlined,
        title: "Layers",
        summary: "${e.layers.length} · ${e.tileCount} tiles",
        initiallyOpen: true,
        children: [TileLayersEditor(controller: controller, map: e, write: write, commit: commit)]),
  ];
}

/// _paintGroup is painting on the map: on and off, the tool, the tile laid
/// and how it is turned, the grid, and how big the tiles are on the canvas.
Widget _paintGroup(
    CanvasController controller, TileMapElement e, TilePaintSession? painting, void Function(TileMapElement) now) {
  return CanvasControlGroup(
    key: const ValueKey("tileMapPaintGroup"),
    label: "Paint tiles",
    help: "Pick a tile above, then paint it onto the map on the canvas: along "
        "where the pen goes, in a line, over a box, or poured into the cells "
        "like the one pressed. Each stroke is one undo.",
    children: [
      CanvasToggle(
        key: const ValueKey("tileMapPaintOn"),
        label: "Paint on the canvas",
        value: painting != null,
        onChanged: (v) => controller.paintTiles(v ? e.id : null),
      ),
      if (painting != null) ...[
        CanvasTiles<TileTool>(
          key: const ValueKey("tileMapTools"),
          columns: 6,
          previewHeight: 24,
          tiles: [
            for (var t in TileTool.values)
              CanvasTile(t, t.label,
                  icon: switch (t) {
                    TileTool.paint => Icons.edit,
                    TileTool.erase => Icons.auto_fix_normal,
                    TileTool.line => Icons.horizontal_rule,
                    TileTool.rect => Icons.crop_square,
                    TileTool.fill => Icons.format_color_fill,
                    TileTool.picker => Icons.colorize,
                  }),
          ],
          selected: (t) => t == painting.tool,
          keyOf: (t) => "tileMapTool-${t.name}",
          onPick: (t) => painting.set(tool: t),
        ),
        SizedBox(
          key: const ValueKey("tileMapBrush"),
          width: 88,
          height: 44,
          child: CustomPaint(painter: _StampPainter(controller, e, painting.stamp)),
        ),
        CanvasIconButton(
          key: const ValueKey("tileMapFlipX"),
          icon: Icons.flip,
          tooltip: "Flip across",
          onPressed: () => painting.set(stamp: painting.stamp.flippedX()),
        ),
        CanvasIconButton(
          key: const ValueKey("tileMapFlipY"),
          icon: Icons.flip_camera_android_outlined,
          tooltip: "Flip down",
          onPressed: () => painting.set(stamp: painting.stamp.flippedY()),
        ),
        CanvasIconButton(
          key: const ValueKey("tileMapTurn"),
          icon: Icons.rotate_right,
          tooltip: "Turn a quarter round",
          onPressed: () => painting.set(stamp: painting.stamp.turnedRight()),
        ),
        CanvasStatus(painting.stamp.cells.length > 1
            ? painting.random
                ? "Each cell takes one of these ${painting.stamp.cells.length} tiles, at random."
                : "A stamp of ${painting.stamp.cells.length} tiles, laid whole, repeating from where you start."
            : "Drag across the tiles above, or shift-click, to pick several: a stamp. "
                "With the picker, drag a box on the map to pick up what is there."),
        CanvasToggle(
          key: const ValueKey("tileMapRandom"),
          label: "At random, from the tiles picked",
          value: painting.random,
          onChanged: (v) => painting.set(random: v),
        ),
        if (painting.random)
          CanvasStepper(
            key: const ValueKey("tileMapGaps"),
            label: "Left empty",
            value: (painting.gaps * 100).roundToDouble(),
            min: 0,
            max: 90,
            step: 5,
            suffix: " %",
            defaultValue: 0,
            onChanged: (v) => painting.set(gaps: v / 100),
          ),
        _patternsGroup(controller, e, painting, now),
        CanvasToggle(
          key: const ValueKey("tileMapPaintGrid"),
          label: "Show the grid",
          value: painting.grid,
          onChanged: (v) => painting.set(grid: v),
        ),
      ],
      CanvasStepper(
        key: const ValueKey("tileMapCell"),
        label: "Tile size",
        value: e.cell,
        min: 4,
        max: 256,
        step: 1,
        suffix: " px",
        onChanged: (v) => now(e.copyWith(cell: v)),
      ),
      if (e.extent != null)
        CanvasTextButton(
          key: const ValueKey("tileMapFit"),
          label: "Fit the box to the map",
          icon: Icons.fit_screen_outlined,
          onPressed: () {
            var (_, _, c1, r1) = e.extent!;
            var cs = e.cellSize;
            now(e.rebase(e.base.copyWith(
                width: math.max(cs.width, (c1 + 1) * cs.width), height: math.max(cs.height, (r1 + 1) * cs.height),
                lockAspect: false)) as TileMapElement);
          },
        ),
    ],
  );
}

/// _patternsGroup is the stamps kept with the map: one picked to paint
/// with, the stamp painted with kept, and the picked one taken out.
Widget _patternsGroup(
    CanvasController controller, TileMapElement e, TilePaintSession painting, void Function(TileMapElement) now) {
  var kept = e.patterns.indexOf(painting.stamp);
  return CanvasControlGroup(
    key: const ValueKey("tileMapPatterns"),
    label: "Patterns",
    help: "Stamps kept with the map -- a doorway, a tree of four tiles -- to "
        "paint with again.",
    children: [
      if (e.patterns.isNotEmpty)
        CanvasTiles<int>(
          key: const ValueKey("tileMapPatternTiles"),
          columns: 4,
          previewHeight: 44,
          tiles: [
            for (var (i, p) in e.patterns.indexed)
              CanvasTile(i, "${p.width}×${p.height}",
                  drawnFrom: (identityHashCode(p), e.sources.map((x) => controller.images.resolve(x.sheet, const BackgroundRemoval()) != null).join()),
                  paint: (canvas, size) => paintStamp(canvas, size, controller, e, p)),
          ],
          selected: (i) => i == kept,
          keyOf: (i) => "tileMapPattern-$i",
          onPick: (i) => painting.set(stamp: e.patterns[i], tool: TileTool.paint),
        ),
      if (kept < 0 && painting.stamp.cells.length > 1)
        CanvasTextButton(
          key: const ValueKey("tileMapKeepPattern"),
          label: "Keep this stamp",
          icon: Icons.bookmark_add_outlined,
          onPressed: () => now(e.copyWith(patterns: [...e.patterns, painting.stamp])),
        ),
      if (kept >= 0)
        CanvasTextButton(
          key: const ValueKey("tileMapDropPattern"),
          label: "Take this pattern out",
          icon: Icons.bookmark_remove_outlined,
          onPressed: () => now(e.copyWith(patterns: [...e.patterns]..removeAt(kept))),
        ),
    ],
  );
}

/// paintStamp draws [stamp] of [map]'s tiles as big as fits [size], in the
/// middle.
void paintStamp(Canvas canvas, Size size, CanvasController controller, TileMapElement map, TileStamp stamp) {
  if (map.sources.isEmpty) return;
  var first = map.sources.first;
  var k = math.min(size.width / (stamp.width * first.tileW), size.height / (stamp.height * first.tileH));
  var one = TileMapElement(
      map.base.copyWith(x: 0, y: 0, width: stamp.width * first.tileW * k, height: stamp.height * first.tileH * k),
      sources: map.sources,
      cell: first.tileW * k,
      pixelArt: map.pixelArt);
  canvas.save();
  canvas.translate((size.width - one.width) / 2, (size.height - one.height) / 2);
  paintTileCells(canvas, Offset.zero & Size(one.width, one.height), one,
      {for (var (c, r, t) in stamp.cells) cellKey(c, r): t.word},
      [for (var x in map.sources) controller.images.resolve(x.sheet, const BackgroundRemoval())]);
  canvas.restore();
}

/// _StampPainter is what is laid, turned as it will be.
class _StampPainter extends CustomPainter {
  final CanvasController controller;
  final TileMapElement map;
  final TileStamp stamp;
  _StampPainter(this.controller, this.map, this.stamp);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x14000000));
    paintStamp(canvas, size, controller, map, stamp);
  }

  @override
  bool shouldRepaint(_StampPainter old) => old.stamp != stamp || !identical(old.map, map);
}

/// TilePalette is a tile set's sheet, its tiles to pick from: big enough
/// to see, scrolled when it is bigger than the room, those picked lit. A
/// click picks one; a drag across them, or a shift-click from the last,
/// picks a block of them -- a stamp.
class TilePalette extends StatefulWidget {
  final CanvasController controller;
  final TileMapElement map;
  final int source;
  final TileStamp? picked;
  final ValueChanged<TileStamp> onPick;
  const TilePalette(
      {required this.controller,
      required this.map,
      required this.source,
      required this.picked,
      required this.onPick,
      super.key});

  @override
  State<TilePalette> createState() => TilePaletteState();
}

class TilePaletteState extends State<TilePalette> {
  /// shown is how wide a tile is shown, for this run of the app.
  static double shown = 28;

  final ScrollController _down = ScrollController(), _across = ScrollController();

  /// _from is where a pick began, and _to where it has got to, as the
  /// sheet's columns and rows; _last the last one picked, for a shift-click.
  (int, int)? _from, _to, _last;

  @override
  void dispose() {
    _down.dispose();
    _across.dispose();
    super.dispose();
  }

  (int, int)? _cellOf(TileSource s, Offset local, double k) {
    var p = local / k;
    if (p.dx < 0 || p.dy < 0 || p.dx > s.sheetW || p.dy > s.sheetH) return null;
    return (
      ((p.dx - s.margin) / (s.tileW + s.spacing)).floor().clamp(0, s.columns - 1),
      ((p.dy - s.margin) / (s.tileH + s.spacing)).floor().clamp(0, s.rows - 1),
    );
  }

  /// _block is the tiles from [a] to [b] on [s], a stamp.
  TileStamp _block(TileSource s, (int, int) a, (int, int) b) {
    var (c0, r0) = (math.min(a.$1, b.$1), math.min(a.$2, b.$2));
    var (c1, r1) = (math.max(a.$1, b.$1), math.max(a.$2, b.$2));
    return TileStamp([
      for (var r = r0; r <= r1; r++)
        for (var c = c0; c <= c1; c++) (c - c0, r - r0, TileRef.of(widget.source, r * s.columns + c)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var s = widget.map.sources[widget.source];
    var k = shown / s.tileW;
    var w = s.sheetW * k, h = s.sheetH * k;
    var lit = <int>{
      if ((_from, _to) case ((var a, var b), (var c, var d)))
        for (var (_, _, t) in _block(s, (a, b), (c, d)).cells) t.index
      else if (widget.picked case var p?)
        for (var (_, _, t) in p.cells)
          if (t.source == widget.source) t.index,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListenableBuilder(
        listenable: widget.controller.images,
        builder: (context, _) {
          var sheet = widget.controller.images.resolve(s.sheet, const BackgroundRemoval());
          return Container(
            key: const ValueKey("tilePaletteBox"),
            width: double.infinity,
            height: math.min(h + 12, 300),
            decoration: BoxDecoration(
                color: theme.colors.surfaceContainerHighest, border: Border.all(color: theme.colors.outlineVariant)),
            child: Scrollbar(
              controller: _down,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _down,
                child: Scrollbar(
                  controller: _across,
                  thumbVisibility: true,
                  notificationPredicate: (n) => n.depth == 0,
                  child: SingleChildScrollView(
                    controller: _across,
                    scrollDirection: Axis.horizontal,
                    // The pointer itself, not a gesture: a drag across the
                    // tiles picks them rather than scrolling.
                    child: Listener(
                      key: const ValueKey("tilePaletteSheet"),
                      onPointerDown: (d) {
                        var at = _cellOf(s, d.localPosition, k);
                        if (at == null) return;
                        var shift = HardwareKeyboard.instance.isShiftPressed;
                        setState(() {
                          _from = shift && _last != null ? _last : at;
                          _to = at;
                        });
                      },
                      onPointerMove: (d) {
                        if (_from == null) return;
                        var at = _cellOf(s, d.localPosition, k);
                        if (at != null && at != _to) setState(() => _to = at);
                      },
                      onPointerUp: (_) {
                        var (from, to) = (_from, _to);
                        if (from == null || to == null) return;
                        setState(() {
                          _from = _to = null;
                          // A shift-click goes on from where the block began.
                          if (!HardwareKeyboard.instance.isShiftPressed) _last = from;
                        });
                        widget.onPick(_block(s, from, to));
                      },
                      onPointerCancel: (_) => setState(() => _from = _to = null),
                      child: CustomPaint(
                        size: Size(w, h),
                        painter: _PalettePainter(s, sheet, k, widget.map.pixelArt, lit, theme.colors.primary),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      CanvasStepper(
        key: const ValueKey("tilePaletteZoom"),
        label: "Shown at",
        value: shown,
        min: 12,
        max: 96,
        step: 4,
        suffix: " px",
        onChanged: (v) => setState(() => shown = v),
      ),
    ]);
  }
}

class _PalettePainter extends CustomPainter {
  final TileSource s;
  final ui.Image? sheet;
  final double k;
  final bool pixelArt;
  final Set<int> lit;
  final Color accent;
  _PalettePainter(this.s, this.sheet, this.k, this.pixelArt, this.lit, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    if (sheet case var img?) {
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), Offset.zero & size,
          Paint()..filterQuality = pixelArt ? FilterQuality.none : FilterQuality.medium);
    }
    var on = Paint()..color = accent.withValues(alpha: 0.25);
    var edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = accent;
    for (var i in lit) {
      var r = s.tileRect(i);
      var box = Rect.fromLTWH(r.left * k, r.top * k, r.width * k, r.height * k);
      canvas.drawRect(box, on);
      canvas.drawRect(box, edge);
    }
  }

  @override
  bool shouldRepaint(_PalettePainter old) =>
      !identical(old.sheet, sheet) || old.k != k || !setEquals(old.lit, lit) || !identical(old.s, s);
}

/// TileSetAdder adds a tile set to the map: a sheet brought in -- a
/// picture, or a Tiled tileset with its picture beside it -- or one of the
/// sets in one of Kenney's packs.
class TileSetAdder extends StatefulWidget {
  final CanvasController controller;
  final TileMapElement map;
  const TileSetAdder({required this.controller, required this.map, super.key});

  @override
  State<TileSetAdder> createState() => TileSetAdderState();
}

class TileSetAdderState extends State<TileSetAdder> {
  /// pack is the Kenney pack looked at last, for this run of the app.
  static String pack = "roguelikerpg-pack-1700-tiles";

  bool? _kept;
  bool _busy = false;
  String _said = "";
  Archive? _archive;
  List<TileSheetOffer> _offers = const [];
  int _offer = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  KenneyPack get _pack => kenneyPacks.firstWhere((p) => p.slug == pack, orElse: () => kenneyPacks.first);

  Future<void> _check() async {
    var p = _pack;
    var kept = await (await kenneyFile(p)).exists();
    if (!mounted || p != _pack) return;
    setState(() {
      _kept = kept;
      _archive = null;
      _offers = const [];
    });
    if (kept) await _open(p);
  }

  Future<void> _open(KenneyPack p) async {
    setState(() => _busy = true);
    try {
      var bytes = await (await kenneyFile(p)).readAsBytes();
      var archive = ZipDecoder().decodeBytes(bytes);
      var offers = tileSheetsIn(archive);
      if (!mounted || p != _pack) return;
      setState(() {
        _archive = archive;
        _offers = offers;
        _offer = 0;
        _said = offers.isEmpty ? "No tiles in this pack." : "";
      });
    } catch (_) {
      if (mounted) setState(() => _said = "The pack could not be read.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fetch() async {
    var prefs = context.read<CanvasPreferences>();
    var p = _pack;
    setState(() {
      _busy = true;
      _said = "Fetching ${p.title} from OpenGameArt…";
    });
    var file = await kenneyFetch(p, allowFetching: prefs.allowFetching, proxied: await networkIsProxied());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _kept = file != null;
      _said = file == null ? "It could not be fetched. Check that fetching is allowed in Settings." : "";
    });
    if (file != null) await _open(p);
  }

  /// _add adds [made] to the map as its newest set, picked: and, as its
  /// first, sizes its cells for it.
  void _add(TileSource made) {
    var c = widget.controller;
    var m = c.document.elementById(widget.map.id);
    if (m is! TileMapElement) return;
    var first = m.sources.isEmpty;
    var next = m.copyWith(
      sources: [...m.sources, made],
      // Small tiles are pixel art, drawn twice their size; big ones as they are.
      cell: first ? (made.tileW <= 32 ? made.tileW * 2.0 : made.tileW.toDouble()) : null,
      pixelArt: first ? made.tileW <= 32 : null,
    );
    pickedTileSource[m.id] = next.sources.length - 1;
    c.beginInteraction();
    c.replaceElement(next);
    c.endInteraction();
    if (c.tilePaint?.id != m.id) c.paintTiles(m.id);
    c.tilePaint!.set(brush: TileRef.of(next.sources.length - 1, 0), tool: TileTool.paint);
  }

  Future<void> _addOffer() async {
    var archive = _archive;
    if (archive == null || _offers.isEmpty) return;
    setState(() => _busy = true);
    var made = await tileSourceFrom(_offers[_offer], archive);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _said = made == null ? "Those tiles could not be read." : "";
    });
    if (made != null) _add(made);
  }

  /// bringIn makes a set of the sheet at [file] -- or the sheet a Tiled
  /// tileset there names -- sliced as its notes say, or by the gaps between
  /// its tiles, or in 16s.
  Future<void> bringIn(String file) async {
    try {
      var picture = file;
      TilesetNotes? notes;
      if (file.toLowerCase().endsWith(".tsx")) {
        notes = readTilesets(await File(file).readAsString()).firstOrNull;
        if (notes == null) {
          setState(() => _said = "That .tsx does not describe a tileset with a picture.");
          return;
        }
        picture = path.normalize(path.join(path.dirname(file), notes.image));
      }
      var bytes = await File(picture).readAsBytes();
      var codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
      var image = (await codec.getNextFrame()).image;
      var id = await CanvasAssets.save(bytes);
      if (id == null) {
        setState(() => _said = "That picture could not be stored.");
        return;
      }
      var name = path.basenameWithoutExtension(picture);
      await CanvasLibrary.addPicture(id, name, bytes);
      var (tw, th) = (notes?.tileW ?? 16, notes?.tileH ?? 16);
      if (notes == null) {
        if (await findGrid(image) case (var cols, var rows)) {
          (tw, th) = (image.width ~/ cols, image.height ~/ rows);
        } else if (image.width % 16 != 0 && image.width % 32 == 0) {
          (tw, th) = (32, 32);
        }
      }
      _add(TileSource(
          sheet: id,
          name: name,
          sheetW: image.width,
          sheetH: image.height,
          tileW: tw,
          tileH: th,
          margin: notes?.margin ?? 0,
          spacing: notes?.spacing ?? 0));
      if (mounted) {
        setState(() => _said = notes != null
            ? "Sliced as its tileset says."
            : "Sliced in ${tw}s. Check the grid above: each tile's size, and any gap.");
      }
    } on FileSystemException {
      if (mounted) setState(() => _said = "That file could not be opened.");
    } catch (_) {
      if (mounted) setState(() => _said = "That file could not be read as a picture.");
    }
  }

  @override
  Widget build(BuildContext context) {
    var p = _pack;
    return CanvasControlGroup(
      key: const ValueKey("tileSetAdd"),
      label: widget.map.sources.isEmpty ? "Add a tile set" : "Add another tile set",
      help: "A sheet of tiles side by side -- a picture, or a Tiled tileset "
          "(.tsx) with its picture beside it -- or one of the sets in Kenney's "
          "free packs, fetched once and kept.",
      children: [
        CanvasTextButton(
          key: const ValueKey("tileMapImport"),
          label: "Bring in a tile sheet…",
          icon: Icons.file_open_outlined,
          primary: widget.map.sources.isEmpty,
          onPressed: () async {
            var picked = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: const ["png", "gif", "webp", "jpg", "jpeg", "tsx"],
              withData: false,
            );
            var file = picked?.files.singleOrNull?.path;
            if (file != null) await bringIn(file);
          },
        ),
        CanvasDropdown<String>(
          key: const ValueKey("tileMapKenneyPack"),
          label: "Kenney's pack",
          value: p.slug,
          options: [
            for (var k in [KenneyKind.tiles, KenneyKind.figures, KenneyKind.items, KenneyKind.effects])
              for (var x in kenneyPacks)
                if (x.kind == k) (x.slug, "${k.label} · ${x.title}"),
          ],
          onChanged: (slug) {
            setState(() => pack = slug);
            _check();
          },
        ),
        if (_kept == false && !_busy)
          CanvasTextButton(
            key: const ValueKey("tileMapKenneyFetch"),
            label: "Fetch ${p.title}",
            icon: Icons.download_outlined,
            onPressed: _fetch,
          ),
        if (_offers.isNotEmpty) ...[
          CanvasDropdown<int>(
            key: const ValueKey("tileMapKenneySet"),
            label: "Its tiles",
            value: _offer.clamp(0, _offers.length - 1),
            options: [for (var (i, o) in _offers.indexed) (i, o.name)],
            onChanged: (i) => setState(() => _offer = i),
          ),
          CanvasTextButton(
            key: const ValueKey("tileMapKenneyAdd"),
            label: "Add these tiles",
            icon: Icons.add,
            primary: widget.map.sources.isEmpty,
            onPressed: _busy ? null : _addOffer,
          ),
        ],
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_said.isNotEmpty) CanvasStatus(_said),
      ],
    );
  }
}

/// TileLayersEditor is the map's layers, the top one first: each picked,
/// shown or hidden, locked; added, taken out, moved up and down; and the
/// picked one's name, how see-through it is, and its tint.
class TileLayersEditor extends StatelessWidget {
  final CanvasController controller;
  final TileMapElement map;
  final SettingsWrite write;
  final VoidCallback commit;
  const TileLayersEditor(
      {required this.controller, required this.map, required this.write, required this.commit, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var e = map;
    var picked = (pickedTileLayer[e.id] ?? e.layers.length - 1).clamp(0, e.layers.length - 1).toInt();
    void now(TileMapElement next) {
      controller.beginInteraction();
      write(next);
      commit();
    }

    void pick(int i) {
      pickedTileLayer[e.id] = i;
      controller.tilePaint?.set();
      controller.notifyListeners();
    }

    var layer = e.layers[picked];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = e.layers.length - 1; i >= 0; i--)
        Material(
          key: ValueKey("tileLayer-$i"),
          color: i == picked ? theme.colors.primary.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => pick(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(children: [
                CanvasIconButton(
                  key: ValueKey("tileLayerShown-$i"),
                  tight: true,
                  icon: e.layers[i].visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  tooltip: e.layers[i].visible ? "Hide" : "Show",
                  onPressed: () => now(e.withLayer(i, e.layers[i].copyWith(visible: !e.layers[i].visible))),
                ),
                CanvasIconButton(
                  key: ValueKey("tileLayerLocked-$i"),
                  tight: true,
                  icon: e.layers[i].locked ? Icons.lock_outline : Icons.lock_open_outlined,
                  tooltip: e.layers[i].locked ? "Unlock" : "Lock",
                  onPressed: () => now(e.withLayer(i, e.layers[i].copyWith(locked: !e.layers[i].locked))),
                ),
                Expanded(
                  child: Text(e.layers[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colors.onSurface,
                          fontWeight: i == picked ? FontWeight.w600 : FontWeight.normal)),
                ),
                Text("${e.layers[i].cells.length}",
                    style: TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant)),
              ]),
            ),
          ),
        ),
      const SizedBox(height: 6),
      Wrap(spacing: 2, children: [
        CanvasIconButton(
          key: const ValueKey("tileLayerAdd"),
          tight: true,
          icon: Icons.add,
          tooltip: "Add a layer above",
          onPressed: () {
            var layers = [...e.layers]..insert(picked + 1, TileLayer(name: "Layer ${e.layers.length + 1}"));
            pickedTileLayer[e.id] = picked + 1;
            now(e.copyWith(layers: layers));
          },
        ),
        CanvasIconButton(
          key: const ValueKey("tileLayerRemove"),
          tight: true,
          icon: Icons.delete_outline,
          tooltip: "Take this layer out",
          onPressed: e.layers.length < 2
              ? null
              : () {
                  pickedTileLayer[e.id] = math.max(0, picked - 1);
                  now(e.copyWith(layers: [...e.layers]..removeAt(picked)));
                },
        ),
        CanvasIconButton(
          key: const ValueKey("tileLayerUp"),
          tight: true,
          icon: Icons.arrow_upward,
          tooltip: "Move up",
          onPressed: picked >= e.layers.length - 1
              ? null
              : () {
                  var layers = [...e.layers];
                  layers.insert(picked + 1, layers.removeAt(picked));
                  pickedTileLayer[e.id] = picked + 1;
                  now(e.copyWith(layers: layers));
                },
        ),
        CanvasIconButton(
          key: const ValueKey("tileLayerDown"),
          tight: true,
          icon: Icons.arrow_downward,
          tooltip: "Move down",
          onPressed: picked == 0
              ? null
              : () {
                  var layers = [...e.layers];
                  layers.insert(picked - 1, layers.removeAt(picked));
                  pickedTileLayer[e.id] = picked - 1;
                  now(e.copyWith(layers: layers));
                },
        ),
      ]),
      CanvasControlGroup(
        key: ValueKey("tileLayerProps-$picked"),
        label: "This layer",
        children: [
          CanvasTextField(
            key: ValueKey("tileLayerName-${e.id}-$picked"),
            label: "Name",
            value: layer.name,
            onChanged: (v) => write(e.withLayer(picked, layer.copyWith(name: v))),
            onCommit: commit,
          ),
          CanvasStepper(
            key: const ValueKey("tileLayerOpacity"),
            label: "Opacity",
            value: layer.opacity * 100,
            min: 0,
            max: 100,
            step: 5,
            suffix: " %",
            onChanged: (v) => write(e.withLayer(picked, layer.copyWith(opacity: v / 100))),
            onCommit: commit,
          ),
          CanvasColorButton(
            key: const ValueKey("tileLayerTint"),
            label: "Tint",
            color: layer.tint ?? const Color(0xFFFFFFFF),
            onChanged: (c) => now(e.withLayer(
                picked, c.toARGB32() == 0xFFFFFFFF ? layer.copyWith(noTint: true) : layer.copyWith(tint: c))),
          ),
        ],
      ),
    ]);
  }
}
