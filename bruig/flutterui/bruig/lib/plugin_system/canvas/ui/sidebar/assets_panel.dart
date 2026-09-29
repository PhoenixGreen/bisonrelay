import 'dart:typed_data';

import 'package:bruig/components/panel_stack.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_dialogs.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/double_click.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/media_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/stock_panel.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// assets_panel.dart is the Assets sidebar: the pictures, videos and sounds in
// the library, one panel each, in the same stack the Design sidebar is.
//
// An asset is clicked to put it in the middle of the canvas, or dragged to put
// it where it is let go -- onto a channel on the timeline, for a sound. Its
// name is double-clicked to rename it. Each section shows its assets as icons
// or as a list, whichever it was last left on. It is added here, and it
// leaves the library only from here: see CanvasLibrary.

class CanvasAssetsPanel extends StatelessWidget {
  final CanvasController controller;
  const CanvasAssetsPanel({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: CanvasLibrary.changes,
        builder: (context, _, __) => PanelStack(
          storageKey: "canvasAssets",
          panels: [
            for (var kind in AssetKind.values)
              StackPanel(
                id: kind.name,
                label: kind.label,
                icon: _iconOf(kind),
                hint: switch (kind) {
                  AssetKind.picture || AssetKind.video => "Click one to put it "
                      "in the middle of the canvas, or drag it where you want "
                      "it. Double-click a name to rename it.",
                  AssetKind.audio => "Click one for a speaker in the middle "
                      "of the canvas, or drag it onto a channel on the "
                      "timeline to play it there. Double-click a name to "
                      "rename it.",
                },
                // Keyed by its kind: panels sharing a row become tabs, and
                // without a key the one section is handed each tab's kind in
                // turn -- the Audio tab showed the pictures, and Pictures
                // showed nothing.
                body: AssetSection(
                    key: ValueKey("assets-${kind.name}"),
                    controller: controller,
                    kind: kind),
              ),
            StackPanel(
              id: "stock",
              label: "Stock",
              icon: Icons.travel_explore,
              hint: "Search Pixabay, the Noun Project, Freesound and Jamendo "
                  "with keys of your own. A result is only a preview until it "
                  "is used: click it onto the canvas, drag it, or add it to "
                  "the library with its +. It keeps who made it and its "
                  "licence.",
              // Shut until wanted: it is empty until somebody searches.
              startsOpen: false,
              body: StockPanel(
                  key: const ValueKey("assets-stock"), controller: controller),
            ),
          ],
        ),
      );
}

IconData _iconOf(AssetKind kind) => switch (kind) {
      AssetKind.picture => Icons.image_outlined,
      AssetKind.video => Icons.movie_outlined,
      AssetKind.audio => Icons.music_note_outlined,
    };

/// AssetView is how a section shows its assets.
enum AssetView { icons, list }

/// AssetSection is one of the three: an Add button, the view switch, and what
/// is in the library.
class AssetSection extends StatefulWidget {
  final CanvasController controller;
  final AssetKind kind;
  const AssetSection({required this.controller, required this.kind, super.key});

  @override
  State<AssetSection> createState() => _AssetSectionState();
}

class _AssetSectionState extends State<AssetSection> {
  List<LibraryAsset>? _assets;

  /// _view is this section's, and is kept: somebody who wants a list of
  /// sounds and icons of pictures sets each once.
  AssetView _view = AssetView.icons;

  String get _viewKey => "canvasAssets.view.${widget.kind.name}";

  @override
  void initState() {
    super.initState();
    // Sounds were a list before there was a choice, and start as one.
    if (widget.kind == AssetKind.audio) _view = AssetView.list;
    CanvasLibrary.changes.addListener(_load);
    _load();
    _readView();
  }

  @override
  void didUpdateWidget(AssetSection old) {
    super.didUpdateWidget(old);
    // And if it is ever handed another kind all the same, it shows that one.
    if (old.kind != widget.kind) {
      _assets = null;
      _load();
      _readView();
    }
  }

  @override
  void dispose() {
    CanvasLibrary.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    var kind = widget.kind;
    var found = await CanvasLibrary.list(kind: kind);
    // Only if it is still this kind by the time the list arrives.
    if (mounted && widget.kind == kind) setState(() => _assets = found);
  }

  Future<void> _readView() async {
    var saved = await StorageManager.readString(_viewKey);
    var view = AssetView.values.where((v) => v.name == saved).firstOrNull;
    if (mounted && view != null) setState(() => _view = view);
  }

  void _setView(AssetView view) {
    setState(() => _view = view);
    StorageManager.saveString(_viewKey, view.name);
  }

  Future<void> _add() async {
    var controller = widget.controller;
    switch (widget.kind) {
      case AssetKind.picture:
        await pickCanvasImage(context);
      case AssetKind.video:
        await pickCanvasVideo(context, controller);
      case AssetKind.audio:
        await pickCanvasAudio(context, controller);
    }
  }

  Future<void> _remove(LibraryAsset asset) async {
    var users = await CanvasLibrary.usedBy(asset.id);
    if (!mounted) return;
    var inUse = users.isEmpty
        ? ""
        : " It is used by ${users.length == 1 ? "the canvas" : "the canvases"} "
            "${users.map((u) => "“$u”").join(", ")}, which will show it as "
            "missing.";
    var sure = await askToConfirm(context,
        title: "Remove ${asset.name}?",
        message: "It will be deleted from the library.$inUse",
        confirm: "Remove");
    if (!sure) return;
    await CanvasLibrary.remove(asset.id);
  }

  void _use(LibraryAsset asset) {
    var controller = widget.controller;
    controller.addElement(elementForAsset(asset, controller.document));
  }

  void _rename(LibraryAsset asset, String name) =>
      CanvasLibrary.rename(asset.id, name);

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var assets = _assets;
    var kind = widget.kind.name;
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      children: [
        Row(children: [
          TextButton.icon(
            key: ValueKey("addAsset-$kind"),
            onPressed: _add,
            icon: const Icon(Icons.add, size: 16),
            label: const Text("Add"),
          ),
          const Spacer(),
          CanvasIconButton(
            key: ValueKey("assetIcons-$kind"),
            icon: Icons.grid_view,
            tooltip: "Show as icons",
            active: _view == AssetView.icons,
            tight: true,
            onPressed: () => _setView(AssetView.icons),
          ),
          CanvasIconButton(
            key: ValueKey("assetList-$kind"),
            icon: Icons.view_list,
            tooltip: "Show as a list",
            active: _view == AssetView.list,
            tight: true,
            onPressed: () => _setView(AssetView.list),
          ),
        ]),
        if (assets == null)
          const SizedBox(height: 40)
        else if (assets.isEmpty)
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              "Nothing here yet. What is added stays here until it is "
              "removed, whether or not a canvas is using it.",
              style:
                  TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant),
            ),
          )
        else if (_view == AssetView.list)
          for (var a in assets)
            _draggable(
                a,
                _Row(
                    asset: a,
                    onRemove: () => _remove(a),
                    onRename: (n) => _rename(a, n)))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var a in assets)
                _draggable(
                    a,
                    _Tile(
                        asset: a,
                        onRemove: () => _remove(a),
                        onRename: (n) => _rename(a, n))),
            ],
          ),
      ],
    );
  }

  Widget _draggable(LibraryAsset asset, Widget body) => Draggable<LibraryAsset>(
        key: ValueKey("asset-${asset.id}"),
        data: asset,
        // Carried from the pointer rather than from wherever in the tile it
        // was picked up: where it is dropped is where the pointer is, which
        // is the frame on a channel and the middle of the element on the
        // canvas.
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(
              opacity: 0.8,
              child: SizedBox(width: 96, child: _Feedback(asset: asset))),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: body),
        child: Material(
          // Its own, inside the list: on the sidebar's the highlight spilled
          // over the other sections and stayed put when the list scrolled.
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _use(asset),
            child: body,
          ),
        ),
      );
}

/// _Still is what an asset looks like, small: a picture, a video's poster, or
/// a sound's note.
class _Still extends StatelessWidget {
  final LibraryAsset asset;
  final double width;
  final double height;
  const _Still(this.asset, {required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var still = switch (asset.kind) {
      AssetKind.picture => asset.id,
      AssetKind.video => asset.poster,
      AssetKind.audio => "",
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(width < 60 ? 3 : 6),
      child: Container(
        width: width,
        height: height,
        color: theme.colors.surfaceContainerHighest,
        child: still.isEmpty
            ? Icon(_iconOf(asset.kind),
                size: height * 0.5, color: theme.colors.onSurfaceVariant)
            : AssetThumb(id: still),
      ),
    );
  }
}

/// _Feedback is what is carried under the pointer: the asset's picture.
class _Feedback extends StatelessWidget {
  final LibraryAsset asset;
  const _Feedback({required this.asset});

  @override
  Widget build(BuildContext context) => _Still(asset, width: 96, height: 72);
}

/// _Tile is an asset in the icon view: its picture, its name, and a remove
/// button that shows under the pointer.
class _Tile extends StatefulWidget {
  final LibraryAsset asset;
  final VoidCallback onRemove;
  final ValueChanged<String> onRename;
  const _Tile(
      {required this.asset, required this.onRemove, required this.onRename});

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    var a = widget.asset;
    return MouseRegion(
      onEnter: (_) => setState(() => _over = true),
      onExit: (_) => setState(() => _over = false),
      child: SizedBox(
        width: 96,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            _Still(a, width: 96, height: 72),
            if (a.length > 0 && a.kind != AssetKind.picture)
              Positioned(
                left: 4,
                bottom: 4,
                child: _Badge(_duration(a.length)),
              ),
            if (_over)
              Positioned(
                right: 2,
                top: 2,
                child: _RemoveButton(asset: a, onRemove: widget.onRemove),
              ),
          ]),
          AssetName(asset: a, onRename: widget.onRename, fontSize: 11),
        ]),
      ),
    );
  }
}

/// _Row is an asset in the list view: its picture small on the left, its
/// name, how long it is, and a remove button that shows under the pointer.
class _Row extends StatefulWidget {
  final LibraryAsset asset;
  final VoidCallback onRemove;
  final ValueChanged<String> onRename;
  const _Row(
      {required this.asset, required this.onRemove, required this.onRename});

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var a = widget.asset;
    return MouseRegion(
      onEnter: (_) => setState(() => _over = true),
      onExit: (_) => setState(() => _over = false),
      child: SizedBox(
        height: 36,
        child: Row(children: [
          _Still(a, width: 40, height: 28),
          const SizedBox(width: 8),
          Expanded(
            child: a.credited
                // Where it came from, under the name, for a stock asset: the
                // credit a licence like CC BY asks the user to give.
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        AssetName(
                            asset: a, onRename: widget.onRename, fontSize: 12),
                        Text(
                          [a.author, a.from, a.license]
                              .where((s) => s.isNotEmpty)
                              .join(" · "),
                          key: ValueKey("assetCredit-${a.id}"),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10,
                              color: theme.colors.onSurfaceVariant),
                        ),
                      ])
                : AssetName(asset: a, onRename: widget.onRename, fontSize: 12),
          ),
          if (a.length > 0 && a.kind != AssetKind.picture)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(_duration(a.length),
                  style: TextStyle(
                      fontSize: 11, color: theme.colors.onSurfaceVariant)),
            ),
          SizedBox(
            width: 28,
            child: _over
                ? _RemoveButton(asset: a, onRemove: widget.onRemove)
                : null,
          ),
        ]),
      ),
    );
  }
}

/// AssetName is an asset's name, double-clicked to rename it in place.
///
/// A click on the name never uses the asset: a double-click would otherwise
/// put it on the canvas twice on the way to renaming it. The second click is
/// counted by hand, as the preset rows count it -- see DoubleClick.
class AssetName extends StatefulWidget {
  final LibraryAsset asset;
  final ValueChanged<String> onRename;
  final double fontSize;
  const AssetName(
      {required this.asset,
      required this.onRename,
      this.fontSize = 12,
      super.key});

  @override
  State<AssetName> createState() => _AssetNameState();
}

class _AssetNameState extends State<AssetName> {
  bool _renaming = false;
  final TextEditingController _name = TextEditingController();
  final DoubleClick _clicks = DoubleClick();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// _second is set by the press that completes a double-click, and acted
  /// on when that press is let go.
  bool _second = false;

  /// _pressed counts the click: on the press, so a slow release does not
  /// stretch the pair past DoubleClick.window.
  void _pressed() => _second = _clicks.isSecond(this);

  /// _released opens the field -- on the release, never the press. Opened
  /// on the press, the name was replaced while the button was still down,
  /// the name's own click went with it, and letting go was a click on the
  /// tile: which put the asset on the canvas on the way to renaming it.
  void _released() {
    if (!_second) return;
    _second = false;
    // After the frame, so the release has been settled by then; and a frame
    // asked for, since the name has no ink to ask for one -- without it the
    // field opened whenever the mouse next moved.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _renaming = true;
        _name.text = widget.asset.name;
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _commit() {
    if (!_renaming) return;
    var typed = _name.text.trim();
    setState(() => _renaming = false);
    if (typed.isEmpty || typed == widget.asset.name) return;
    widget.onRename(typed);
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var style =
        TextStyle(fontSize: widget.fontSize, color: theme.colors.onSurface);
    if (_renaming) {
      return TextField(
        key: ValueKey("assetRename-${widget.asset.id}"),
        controller: _name,
        autofocus: true,
        style: style,
        decoration:
            const InputDecoration(isDense: true, border: InputBorder.none),
        onSubmitted: (_) => _commit(),
        onTapOutside: (_) => _commit(),
      );
    }
    return Listener(
      onPointerDown: (_) => _pressed(),
      onPointerUp: (_) => _released(),
      onPointerCancel: (_) => _second = false,
      // Taken here, so a click on the name reaches nothing under it -- not the
      // tile's own click, which would use the asset.
      //
      // The whole line, not just the letters: a short name left most of the
      // line to the tile, and a double-click that landed past the end of the
      // word put the asset on the canvas instead of renaming it.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: SizedBox(
          key: ValueKey("assetNameLine-${widget.asset.id}"),
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(widget.asset.name,
                key: ValueKey("assetName-${widget.asset.id}"),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style),
          ),
        ),
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  final LibraryAsset asset;
  final VoidCallback onRemove;
  const _RemoveButton({required this.asset, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    // No hover text: the cross says it, and removing asks first anyway.
    return InkResponse(
      key: ValueKey("removeAsset-${asset.id}"),
      onTap: onRemove,
      radius: 14,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: theme.colors.surface.withValues(alpha: 0.85),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.close, size: 14, color: theme.colors.onSurface),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xAA000000),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 10, color: Color(0xFFFFFFFF))),
      );
}

String _duration(double seconds) {
  if (seconds <= 0) return "";
  var s = seconds.round();
  return "${s ~/ 60}:${(s % 60).toString().padLeft(2, "0")}";
}

/// AssetThumb is a stored picture, small: read once and kept while the
/// sidebar is open, so scrolling does not read it again.
class AssetThumb extends StatefulWidget {
  final String id;
  const AssetThumb({required this.id, super.key});

  @override
  State<AssetThumb> createState() => _AssetThumbState();
}

class _AssetThumbState extends State<AssetThumb> {
  static final Map<String, Uint8List> _cache = {};
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    var bytes = _cache[widget.id];
    if (bytes == null) {
      var read = await CanvasAssets.load(widget.id);
      if (read == null) return;
      bytes = Uint8List.fromList(read);
      if (_cache.length > 200) _cache.remove(_cache.keys.first);
      _cache[widget.id] = bytes;
    }
    if (mounted) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    var bytes = _bytes;
    if (bytes == null) return const SizedBox.expand();
    if (widget.id.endsWith(".svg")) {
      return SvgPicture.memory(bytes, fit: BoxFit.contain);
    }
    return Image.memory(bytes,
        fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 192);
  }
}
