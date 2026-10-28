import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/kenney_packs.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// kenney_browser.dart is Kenney's free sprites in the Stock sidebar: a pack
// picked, fetched once and kept, and the sprites in it -- each run of
// numbered frames an animation, each folder's other pictures a set -- one
// clicked onto the canvas as a Sprite element. See kenney_packs.dart.

class KenneyBrowser extends StatefulWidget {
  final CanvasController controller;
  const KenneyBrowser({required this.controller, super.key});

  @override
  State<KenneyBrowser> createState() => KenneyBrowserState();
}

class KenneyBrowserState extends State<KenneyBrowser> {
  /// last is the pack looked at last, for this run of the app.
  static String last = "";

  KenneyPack? _pack;
  bool _kept = false;
  bool _busy = false;
  String _said = "";
  List<SpriteGroup> _groups = const [];
  Archive? _archive;
  final Map<String, ui.Image?> _thumbs = {};

  @override
  void initState() {
    super.initState();
    var pack = kenneyPacks.where((p) => p.slug == last).firstOrNull;
    if (pack != null) _choose(pack);
  }

  Future<void> _choose(KenneyPack pack) async {
    last = pack.slug;
    setState(() {
      _pack = pack;
      _groups = const [];
      _archive = null;
      _thumbs.clear();
      _said = "";
    });
    var file = await kenneyFile(pack);
    var kept = await file.exists();
    if (!mounted || _pack != pack) return;
    setState(() => _kept = kept);
    if (kept) await _open(pack);
  }

  Future<void> _open(KenneyPack pack) async {
    setState(() => _busy = true);
    try {
      var (groups, archive) = await kenneyGroups(await kenneyFile(pack));
      if (!mounted || _pack != pack) return;
      setState(() {
        _groups = groups;
        _archive = archive;
        _said = groups.isEmpty ? "Nothing in this pack to make a sprite of." : "";
      });
      // Each sprite's first frame, for its tile.
      for (var g in groups.take(80)) {
        var img = await groupFrame(archive, g.files.first);
        if (!mounted || _pack != pack) return;
        setState(() => _thumbs["${g.folder}|${g.name}"] = img);
      }
    } catch (_) {
      if (mounted) setState(() => _said = "The pack could not be read.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fetch(KenneyPack pack) async {
    var prefs = context.read<CanvasPreferences>();
    setState(() {
      _busy = true;
      _said = "Fetching ${pack.title} from OpenGameArt…";
    });
    var file = await kenneyFetch(pack,
        allowFetching: prefs.allowFetching, proxied: await networkIsProxied());
    if (!mounted) return;
    if (file == null) {
      setState(() {
        _busy = false;
        _said = "It could not be fetched. Check the connection, and that fetching is allowed.";
      });
      return;
    }
    setState(() => _kept = true);
    await _open(pack);
  }

  /// _use makes [group] a sprite: the picked one, when it has no sheet
  /// yet, or a new one on the canvas.
  Future<void> _use(SpriteGroup group) async {
    var archive = _archive;
    if (archive == null) return;
    var c = widget.controller;
    var picked = c.selection.length == 1 ? c.document.elementById(c.selection.first) : null;
    var into = picked is SpriteElement && !picked.hasSheet
        ? picked
        : newElement(ElementKind.sprite, c.document) as SpriteElement;
    setState(() => _busy = true);
    var made = await spriteFromGroup(into, group, archive);
    if (!mounted) return;
    setState(() => _busy = false);
    if (made == null) {
      setState(() => _said = "That sprite could not be made.");
      return;
    }
    var cell = made.frameRect(0).size;
    var box = made.base;
    var sized = made.rebase(box.copyWith(
        width: cell.height <= 0 ? box.width : box.height * cell.width / cell.height, lockAspect: true));
    c.beginInteraction();
    if (identical(into, picked)) {
      c.replaceElement(sized);
    } else {
      c.addElement(sized);
    }
    c.endInteraction();
  }

  @override
  Widget build(BuildContext context) {
    var pack = _pack;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CanvasDropdown<String>(
        key: const ValueKey("kenneyPack"),
        label: "Pack",
        value: pack?.slug ?? "",
        options: [
          if (pack == null) ("", "Pick a pack…"),
          for (var k in KenneyKind.values)
            for (var p in kenneyPacks)
              if (p.kind == k) (p.slug, "${k.label} · ${p.title}"),
        ],
        onChanged: (slug) {
          var p = kenneyPacks.where((p) => p.slug == slug).firstOrNull;
          if (p != null) _choose(p);
        },
      ),
      const CanvasStatus("Kenney's art is CC0: free for anything, no credit asked. "
          "He makes it with the help of donations, at kenney.nl."),
      if (pack != null && !_kept && !_busy)
        CanvasTextButton(
          key: const ValueKey("kenneyFetch"),
          label: "Fetch ${pack.title}",
          icon: Icons.download_outlined,
          primary: true,
          onPressed: () => _fetch(pack),
        ),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      if (_said.isNotEmpty) CanvasStatus(_said),
      if (_groups.isNotEmpty)
        CanvasTiles<int>(
          key: const ValueKey("kenneySprites"),
          label: "Click one onto the canvas",
          columns: 3,
          previewHeight: 64,
          tiles: [
            for (var (i, g) in _groups.indexed)
              CanvasTile(i, "${g.name} · ${g.files.length}",
                  drawnFrom: "${pack?.slug}|${g.folder}|${g.name}|${_thumbs["${g.folder}|${g.name}"] != null}",
                  paint: (canvas, size) {
                    var img = _thumbs["${g.folder}|${g.name}"];
                    if (img == null) return;
                    var k = math.min(size.width / img.width, size.height / img.height) * 0.9;
                    var w = img.width * k, h = img.height * k;
                    canvas.drawImageRect(
                        img,
                        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
                        Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h),
                        Paint()..filterQuality = img.width <= 32 ? FilterQuality.none : FilterQuality.medium);
                  }),
          ],
          selected: (_) => false,
          keyOf: (i) => "kenneySprite-$i",
          onPick: (i) => _use(_groups[i]),
        ),
    ]);
  }
}
