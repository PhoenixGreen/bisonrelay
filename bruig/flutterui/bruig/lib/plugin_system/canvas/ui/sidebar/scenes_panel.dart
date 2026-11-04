import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/double_click.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/preset_row.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/storyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bruig/storage_manager.dart';

// scenes_panel.dart is the list of canvases a document plays through, in the
// order they play. A plain list of names, or each scene drawn by the canvas
// renderer (so the preview cannot go stale).
//
// Above them is the master canvas, which every scene plays under: it cannot be
// moved, renamed or deleted, and is off until asked for.

class CanvasScenesPanel extends StatefulWidget {
  final CanvasController controller;

  const CanvasScenesPanel({required this.controller, super.key});

  @override
  State<CanvasScenesPanel> createState() => _CanvasScenesPanelState();
}

class _CanvasScenesPanelState extends State<CanvasScenesPanel> {
  CanvasController get controller => widget.controller;
  CanvasDocument get document => controller.document;

  /// _previews is whether each scene is drawn rather than named, saved under
  /// [_previewsKey] so it survives the panel being rebuilt.
  bool _previews = false;
  static const _previewsKey = "canvasScenePreviews";

  /// _renaming is the scene whose name is being typed, by index.
  int? _renaming;
  final TextEditingController _name = TextEditingController();

  /// _focus is the list's, for the arrow keys: taken by a click anywhere on
  /// it.
  final FocusNode _focus = FocusNode(debugLabel: "scenes");

  @override
  void initState() {
    super.initState();
    StorageManager.readBool(_previewsKey).then((on) {
      if (mounted && on != _previews) setState(() => _previews = on);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setPreviews(bool on) {
    setState(() => _previews = on);
    StorageManager.saveBool(_previewsKey, on);
  }

  /// _onKey is up and down through the list: the one before and the one
  /// after, and from the master down onto the first.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    var by = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowDown => 1,
      _ => 0,
    };
    if (by == 0) return KeyEventResult.ignored;
    var count = document.allScenes.length;
    var to = document.editingMaster ? 0 : document.at + by;
    if (to >= 0 && to < count) controller.goToScene(to);
    return KeyEventResult.handled;
  }

  void _startRename(int index, CanvasScene scene) {
    setState(() {
      _renaming = index;
      _name.text = scene.name;
      _name.selection =
          TextSelection(baseOffset: 0, extentOffset: _name.text.length);
    });
  }

  /// _nameClicks counts the second click of a pair on a scene's name. By hand
  /// rather than with a double-tap recognizer, which would hold every tap on
  /// the row back for the double-click window (a fifth of a second) and delay
  /// the menu button too. See DoubleClick.
  final DoubleClick _nameClicks = DoubleClick();

  /// _nameClicked opens the name for typing on the second click of a pair,
  /// after the frame: the rename replaces the widget the pointer is inside,
  /// and doing it mid-dispatch leaves the framework looking up a widget that
  /// has gone.
  void _nameClicked(int index, CanvasScene scene) {
    if (!_nameClicks.isSecond(index)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startRename(index, scene);
    });
  }

  void _commitRename() {
    var at = _renaming;
    if (at == null) return;
    controller.renameScene(at, _name.text);
    setState(() => _renaming = null);
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            if (!_focus.hasFocus) _focus.requestFocus();
          },
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _body(ThemeNotifier.of(context)),
          ),
        ),
      );

  Widget _body(ThemeNotifier theme) {
    var scenes = document.allScenes;
    // A list rather than a column: the stack sets the panel's height and
    // the scenes can be taller. The master and buttons are the first rows,
    // so a long list scrolls under them.
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      children: [
        // One line above the list: the shared canvas on the left, and on the
        // right the buttons that add to the list and change how it is drawn.
        Row(children: [
          Expanded(child: _master(theme)),
          const SizedBox(width: 4),
          _rowButton(theme, Icons.add, "New ${document.kind.one}",
              controller.addScene),
          // Only once something has been copied.
          if (CanvasController.hasCopiedScene)
            _rowButton(theme, Icons.content_paste_go,
                "Paste the copied ${document.kind.one}", controller.pasteScene),
          // The whole run as pictures -- see storyboard.dart.
          _rowButton(theme, Icons.view_module_outlined, "Storyboard",
              () => showStoryboard(context, controller)),
          _rowButton(
            theme,
            _previews ? Icons.view_list_outlined : Icons.grid_view_outlined,
            _previews
                ? "${document.kind.oneCap} preview: off"
                : "${document.kind.oneCap} preview",
            () => _setPreviews(!_previews),
            active: _previews,
          ),
        ]),
        // A rule and some air, so the first scene does not read as another
        // button in the row above.
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 9),
          child: Container(
            height: 1,
            color: theme.colors.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        if (_previews && document.hasSpread)
          ..._spreads(theme, scenes)
        else
          for (var (i, scene) in scenes.indexed)
            _scene(theme, i, scene, scenes),
      ],
    );
  }

  /// _spreads is the list drawn as the book is: facing pages side by side, and
  /// a page alone (a cover) on the side of the spine it is printed on.
  List<Widget> _spreads(ThemeNotifier theme, List<CanvasScene> scenes) {
    var out = <Widget>[];
    var done = <int>{};
    for (var i = 0; i < scenes.length; i++) {
      if (done.contains(i)) continue;
      var pair = document.spreadOf(i);
      if (pair == null) {
        done.add(i);
        out.add(_scene(theme, i, scenes[i], scenes));
        continue;
      }
      var (left, right) = pair;
      done.addAll([
        if (left != null) left,
        if (right != null) right,
      ]);
      out.add(Row(
        key: ValueKey("spread.$i"),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: left == null
                ? const SizedBox.shrink()
                : _scene(theme, left, scenes[left], scenes,
                    // Towards the spine, so a capped pair still meets.
                    align: Alignment.centerRight),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: right == null
                ? const SizedBox.shrink()
                : _scene(theme, right, scenes[right], scenes,
                    align: Alignment.centerLeft),
          ),
        ],
      ));
    }
    return out;
  }

  /// _master is the shared canvas, pinned above the list and not draggable,
  /// because it is not one of the scenes but what they all play under.
  Widget _master(ThemeNotifier theme) {
    var on = document.masterOn;
    var here = document.editingMaster;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: here ? theme.colors.secondaryContainer : null,
        border: Border.all(
            color: here ? theme.colors.primary : theme.colors.outlineVariant),
      ),
      child: Material(
        // Its own Material inside the list: the sidebar's let the highlight
        // spill over other sections and stay put when the list scrolled.
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          // Opening the master switches it on.
          onTap: controller.showMaster,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              Icon(Icons.layers,
                  size: 15,
                  color: on
                      ? theme.colors.onSurfaceVariant
                      : theme.colors.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(width: 6),
              Expanded(
                child: Text("Master ${document.kind.one}",
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: on
                            ? theme.colors.onSurfaceVariant
                            : theme.colors.onSurfaceVariant
                                .withValues(alpha: 0.5))),
              ),
              if (document.defaultTransition.on)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Tooltip(
                    message: "${document.kind.manyCap} give way with "
                        "${document.defaultTransition.kind.label} unless they "
                        "say otherwise",
                    child: Icon(Icons.compare_arrows,
                        size: 14, color: theme.colors.onSurfaceVariant),
                  ),
                ),
              // Sized to the row's text: see _Switch.
              _Switch(
                on: on,
                tooltip: on
                    ? "Turn the master ${document.kind.one} off. What is on it is kept."
                    : "Turn the master ${document.kind.one} on: what you put on it "
                        "appears on every ${document.kind.one}",
                onChanged: () => controller.masterOn = !on,
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// _says is what goes down the left of a row: the page's printed number,
  /// or the canvas's place in the order.
  String _says(int index) {
    if (!document.isPages) return "${index + 1}";
    var number = document.pageNumberAt(index);
    // Nothing for a cover: it has no number.
    return number?.toString() ?? "";
  }

  Widget _scene(
      ThemeNotifier theme, int index, CanvasScene scene, List<CanvasScene> all,
      {Alignment align = Alignment.center}) {
    var here = index == document.at && !document.editingMaster;
    var row = Container(
      key: ValueKey("scene.${scene.id}"),
      margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: here ? theme.colors.secondaryContainer : null,
        border:
            Border.all(color: here ? theme.colors.primary : Colors.transparent),
      ),
      child: Material(
        // Its own Material: see _master.
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          // No double-tap recognizer anywhere on this row: see _nameClicks.
          onTap: () => controller.goToScene(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    // The page's printed number rather than its row, for a document of
                    // pages: a cover has none and the page after it is still page one.
                    SizedBox(
                      width: 18,
                      child: Text(_says(index),
                          style: TextStyle(
                              fontSize: 11,
                              color: theme.colors.onSurfaceVariant
                                  .withValues(alpha: 0.6))),
                    ),
                    Expanded(
                      child: _renaming == index
                          ? TextField(
                              controller: _name,
                              autofocus: true,
                              style: const TextStyle(fontSize: 12),
                              decoration: const InputDecoration(
                                  isDense: true, border: InputBorder.none),
                              onSubmitted: (_) => _commitRename(),
                              onTapOutside: (_) => _commitRename(),
                            )
                          : Listener(
                              // A Listener, not a gesture detector: it is not in the gesture arena,
                              // so nothing else on the row is held back. See _nameClicks.
                              onPointerDown: (_) => _nameClicked(index, scene),
                              child: Text(document.nameOf(index),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                    ),
                    // A cover has no number in the gutter, so say it here.
                    if (document.isPages && scene.cover.isCover)
                      Tooltip(
                        message: scene.cover.label,
                        child: Icon(Icons.bookmark_outline,
                            size: 13, color: theme.colors.onSurfaceVariant),
                      ),
                    // A scene that holds does not run on into the next.
                    if (scene.holds)
                      Tooltip(
                        message: document.isPages
                            ? "Playing the document stops at this page"
                            : "Playback stops at the end of this ${document.kind.one}",
                        child: Icon(Icons.pause_circle_outline,
                            size: 13, color: theme.colors.onSurfaceVariant),
                      ),
                    if (index < all.length - 1) _transitionMark(theme, index),
                    // The button's own context, so the menu opens by the button rather
                    // than beside the panel.
                    Builder(
                      builder: (context) => _rowButton(theme, Icons.more_horiz,
                          "More", () => _menu(context, index, all.length)),
                    ),
                  ]),
                  if (_previews)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 2),
                      child: _preview(index, align),
                    ),
                ]),
          ),
        ),
      ),
    );

    return _draggable(theme, row, index, scene);
  }

  /// _transitionMark says whether this scene gives way its own way (filled) or
  /// the document's (plain).
  Widget _transitionMark(ThemeNotifier theme, int index) {
    var scene = document.allScenes[index];
    var which = document.transitionAfter(index);
    if (!which.on && !scene.custom) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Tooltip(
        message: scene.custom
            ? "${which.kind.label}, set on this ${document.kind.one}"
            : "${which.kind.label}, from the master ${document.kind.one}",
        child: Icon(
          scene.custom ? Icons.compare_arrows : Icons.arrow_right_alt,
          size: 14,
          color: scene.custom
              ? theme.colors.primary
              : theme.colors.onSurfaceVariant.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  /// _previewMaxHeight caps a preview, so a sidebar dragged wide does not make
  /// each page taller than the screen.
  static const double _previewMaxHeight = 220;

  /// _preview draws the scene, at the width the column has -- up to
  /// [_previewMaxHeight] tall, placed at [align] when that leaves room over.
  Widget _preview(int index, Alignment align) {
    var size = document.size;
    var ratio =
        math.max(0.2, size.height <= 0 ? 1.0 : size.width / size.height);
    return LayoutBuilder(builder: (context, box) {
      var width = math.min(box.maxWidth, _previewMaxHeight * ratio);
      return Align(
        alignment: align,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            key: ValueKey("scenePreview.$index"),
            width: width,
            height: width / ratio,
            child: CustomPaint(
              painter: _ScenePainter(
                  document: document, index: index, images: controller.images),
            ),
          ),
        ),
      );
    });
  }

  Widget _draggable(
      ThemeNotifier theme, Widget row, int index, CanvasScene scene) {
    // Draggable rather than a ReorderableListView, as in the layer list:
    // that widget moves rows by GlobalKey during layout, and a row with
    // tooltips cannot be re-attached that way.
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != scene.id,
      onAcceptWithDetails: (details) {
        var from = document.allScenes.indexWhere((s) => s.id == details.data);
        if (from < 0) return;
        controller.moveScene(from, index);
      },
      builder: (context, candidate, rejected) => Container(
        decoration: candidate.isEmpty
            ? null
            : BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.colors.primary, width: 1.5),
              ),
        child: LongPressDraggable<String>(
          data: scene.id,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.85,
              child: Container(
                width: 180,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: theme.colors.secondaryContainer,
                ),
                child: Text(document.nameOf(index),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colors.onSecondaryContainer)),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: row),
          child: row,
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, int index, int count) async {
    var scene = document.allScenes[index];

    // Under the button: a menu is placed relative to its overlay, so the
    // button's rectangle is measured against that, not the screen.
    var box = context.findRenderObject() as RenderBox?;
    var overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    var where = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    var chose = await showMenu<String>(
      context: context,
      position: where,
      items: [
        const PopupMenuItem(value: "duplicate", child: Text("Duplicate")),
        // Copied here and pasted into whichever canvas is open next, which is
        // how a scene moves between documents. No Rename: double-click the name.
        const PopupMenuItem(value: "copy", child: Text("Copy")),
        // Kept in the Presets sidebar as a copy: later edits to the scene do
        // not reach it.
        PopupMenuItem(
            value: "preset",
            child: Text("Save ${document.kind.one} as preset")),
        // Which end of the document this is, for a document of pages: only a
        // first or last page can be a cover.
        if (document.isPages && index == 0)
          PopupMenuItem(
            value: "front",
            child: Text(scene.cover == PageCover.front
                ? "Not the front cover"
                : "Make this the front cover"),
          ),
        if (document.isPages && count > 1 && index == count - 1)
          PopupMenuItem(
            value: "back",
            child: Text(scene.cover == PageCover.back
                ? "Not the back cover"
                : "Make this the back cover"),
          ),
        PopupMenuItem(
          value: "holds",
          child: Text(document.isPages
              ? (scene.holds ? "Read on to the next page" : "Stop at this page")
              : (scene.holds
                  ? "Run on into the next scene"
                  : "Stop at the end of this ${document.kind.one}")),
        ),
        if (count > 1)
          const PopupMenuItem(value: "delete", child: Text("Delete")),
      ],
    );
    if (!mounted) return;

    switch (chose) {
      case "copy":
        controller.copyScene(index);
      case "preset":
        await _saveAsPreset(index, scene);
      case "duplicate":
        controller.duplicateScene(index);
      case "holds":
        controller.setSceneHolds(index, !scene.holds);
      case "front":
        controller.setSceneCover(index,
            scene.cover == PageCover.front ? PageCover.none : PageCover.front);
      case "back":
        controller.setSceneCover(index,
            scene.cover == PageCover.back ? PageCover.none : PageCover.back);
      case "delete":
        controller.removeScene(index);
    }
  }

  /// _saveAsPreset keeps this scene in the Presets sidebar.
  Future<void> _saveAsPreset(int index, CanvasScene scene) async {
    var snackbar = SnackBarModel.of(context);
    var name = await askForPresetName(
        context, "Save this ${document.kind.one} as a preset",
        initial: document.nameOf(index));
    if (name == null || name.trim().isEmpty) return;
    var saved = await SavedPresetStore.scenes
        .save(name, scene.toJson(), madeOn: document.size.size);
    if (saved == null) {
      snackbar.error("Unable to save the preset.");
      return;
    }
    snackbar.success("Saved ${saved.name} to Presets › Scene.");
  }

  Widget _rowButton(ThemeNotifier theme, IconData icon, String tooltip,
          VoidCallback onTap,
          {bool active = false}) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(icon,
                size: 15,
                color: active
                    ? theme.colors.primary
                    : theme.colors.onSurfaceVariant),
          ),
        ),
      );
}

/// _ScenePainter draws one scene, small, with the document's own renderer
/// handed the scene as though it were the document, so the preview cannot
/// disagree with the canvas.
class _ScenePainter extends CustomPainter {
  final CanvasDocument document;
  final int index;

  /// images is the editor's own picture store; without it every picture draws
  /// as its "Loading" placeholder. Repainted when a picture arrives.
  final CanvasImageStore images;

  _ScenePainter(
      {required this.document, required this.index, required this.images})
      : super(repaint: images);

  /// frameOf is the moment a scene is shown at: the middle of its timeline,
  /// since frame nought is usually before anything has arrived.
  static int frameOf(CanvasDocument scene) =>
      math.max(0, scene.frames - 1) ~/ 2;

  @override
  void paint(Canvas canvas, Size size) {
    var page = document.size;
    if (page.width <= 0 || page.height <= 0) return;
    var scene = document.goToScene(index).copyWith(onMaster: false);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / page.width, size.height / page.height);
    var beside = document.facingAt(index);
    if (beside == null) {
      paintCanvasDocument(canvas, scene, frame: frameOf(scene), images: images);
    } else {
      // The facing page's overhang across the spine is part of this page, as
      // on the canvas: this page's paper, then the overhang, then its own
      // elements.
      var over = document.goToScene(beside).copyWith(onMaster: false);
      var aside = (document.facingIsLeft(index) ?? false)
          ? page.width.toDouble()
          : -page.width.toDouble();
      paintCanvasDocument(canvas, scene,
          frame: frameOf(scene),
          part: CanvasPaintPart.backdrop,
          images: images);
      canvas.save();
      canvas.translate(aside, 0);
      paintCanvasDocument(canvas, over,
          frame: frameOf(over), part: CanvasPaintPart.contents, images: images);
      canvas.restore();
      paintCanvasDocument(canvas, scene,
          frame: frameOf(scene),
          part: CanvasPaintPart.contents,
          images: images);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.index != index ||
      !identical(old.document, document) ||
      !identical(old.images, images);
}

/// _Switch is an on-and-off drawn to the height of a line of this panel's
/// text: Material's switch is half again as tall as a row, and an icon
/// button reads as a decoration.
class _Switch extends StatelessWidget {
  final bool on;
  final String tooltip;
  final VoidCallback onChanged;

  const _Switch({
    required this.on,
    required this.tooltip,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onChanged,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Container(
            width: 26,
            height: 14,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              color: on
                  ? theme.colors.primary.withValues(alpha: 0.8)
                  : theme.colors.outlineVariant,
            ),
            child: Align(
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on
                        ? theme.colors.onPrimary
                        : theme.colors.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
