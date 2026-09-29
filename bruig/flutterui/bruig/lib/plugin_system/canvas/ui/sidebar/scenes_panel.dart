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
import 'package:flutter/material.dart';

// scenes_panel.dart is the list of canvases a document plays through.
//
// The order in the list is the order they play in, which is why it is a list
// and not a set of tabs: the thing being arranged here is a sequence, and a
// sequence is read top to bottom.
//
// Two ways to look at it. The plain list is names, and fits a dozen scenes in
// the column; the second draws each scene, which is how somebody finds the
// one they mean when the names are Scene 4 and Scene 5. Drawn by the same
// renderer that draws the canvas rather than from stored pictures -- the
// preview cannot go stale that way, and nothing has to remember to rebuild
// it.
//
// Above them all is the master canvas, which is not one of them: it is what
// every scene plays under. It cannot be moved, renamed or deleted, and it is
// off until somebody asks for it.

class CanvasScenesPanel extends StatefulWidget {
  final CanvasController controller;

  const CanvasScenesPanel({required this.controller, super.key});

  @override
  State<CanvasScenesPanel> createState() => _CanvasScenesPanelState();
}

class _CanvasScenesPanelState extends State<CanvasScenesPanel> {
  CanvasController get controller => widget.controller;
  CanvasDocument get document => controller.document;

  /// _previews is whether each scene is drawn rather than named.
  bool _previews = false;

  /// _renaming is the scene whose name is being typed, by index.
  int? _renaming;
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _startRename(int index, CanvasScene scene) {
    setState(() {
      _renaming = index;
      _name.text = scene.name;
      _name.selection =
          TextSelection(baseOffset: 0, extentOffset: _name.text.length);
    });
  }

  /// _nameClicks counts the second click of a pair on a scene's name. See
  /// DoubleClick, and the note on the row about why it is counted by hand.
  final DoubleClick _nameClicks = DoubleClick();

  /// _nameClicked opens the name for typing on the second click of a pair.
  ///
  /// The rename is opened after the frame the click landed in, because it
  /// replaces the very widget the pointer is inside: done in the middle of
  /// dispatching the press, the framework is left looking up a widget that
  /// has already gone.
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
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _body(ThemeNotifier.of(context)),
      );

  Widget _body(ThemeNotifier theme) {
    var scenes = document.allScenes;
    // A list rather than a column: the panel is given a height by the stack
    // it sits in, and a dozen scenes -- or three with their pictures drawn --
    // is taller than that. A column simply overflowed the panel it was in.
    //
    // The master and the two buttons are the first rows of the same list, so
    // that a long list scrolls under them rather than pushing them out.
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      children: [
        // One line above the list: the shared canvas on the left, and on the
        // right the two things that act on the list -- adding to it, and
        // changing how it is drawn. A row of its own for two icons was a
        // line of mostly nothing in a narrow column.
        Row(children: [
          Expanded(child: _master(theme)),
          const SizedBox(width: 4),
          _rowButton(theme, Icons.add, "New ${document.kind.one}",
              controller.addScene),
          // Only once something has been copied: a paste button with
          // nothing behind it does nothing, and this row is narrow.
          if (CanvasController.hasCopiedScene)
            _rowButton(theme, Icons.content_paste_go,
                "Paste the copied ${document.kind.one}", controller.pasteScene),
          _rowButton(
            theme,
            _previews ? Icons.view_list_outlined : Icons.grid_view_outlined,
            _previews
                ? "${document.kind.oneCap} preview: off"
                : "${document.kind.oneCap} preview",
            () => setState(() => _previews = !_previews),
            active: _previews,
          ),
        ]),
        // A line and some air between what acts on the list and the list
        // itself: without them the first scene read as another button in the
        // row above it.
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

  /// _spreads is the list drawn as the book is: two pages that face each
  /// other side by side, and a page alone -- a cover -- on the side of the
  /// spine it is printed on, with the other half left empty.
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

  /// _master is the shared canvas, pinned above the list.
  ///
  /// Above rather than in it, and not draggable, because it is not one of the
  /// scenes: it is what they all play under. Off by default -- a document
  /// that does not need one should not have an extra canvas to think about.
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
        // Its own, inside the list: on the sidebar's the highlight spilled
        // over the other sections and stayed put when the list scrolled.
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          // Asking to edit the master is asking for one: it is switched on by
          // being opened rather than by a second press somewhere else.
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
              // A switch drawn to the height of the row's own text. The
              // Material one is built for a settings page and made this line
              // half again as tall as every scene under it; an icon button was
              // the other way, small enough to read as a decoration.
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
    // Nothing for a cover rather than a dash or a zero: it has no number, and
    // a symbol standing in for one is a number that has to be learnt.
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
        // Its own, inside the list: on the sidebar's the highlight spilled
        // over the other sections and stayed put when the list scrolled.
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          // No double-tap recognizer anywhere on this row. One here holds
          // every single tap back until the double-click window has passed --
          // a fifth of a second between pressing a scene and seeing it -- and
          // one on the name alone still shares the arena with this and with
          // the menu button, which then opened late as well. The second click
          // on the name is counted by hand instead: see _nameClicked.
          onTap: () => controller.goToScene(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    // The page's own number rather than its place in the list, for
                    // a document of pages: a cover has no number and the first page
                    // after one is still page one, so counting rows would be
                    // saying something the document does not.
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
                              // Not a gesture detector: a Listener is not in the
                              // gesture arena, so nothing else on the row is held
                              // back by it. See _nameClicked.
                              onPointerDown: (_) => _nameClicked(index, scene),
                              child: Text(scene.saysAt(index, document.kind),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                    ),
                    // A cover, said in the list. Its row has no number in the
                    // gutter -- it has none -- so without this the only difference
                    // between the cover and page one is a blank space.
                    if (document.isPages && scene.cover.isCover)
                      Tooltip(
                        message: scene.cover.label,
                        child: Icon(Icons.bookmark_outline,
                            size: 13, color: theme.colors.onSurfaceVariant),
                      ),
                    // A scene that holds is one that does not run on into the
                    // next, which is worth saying in the list: it is the
                    // difference between a sequence and a set of stills.
                    if (scene.holds)
                      Tooltip(
                        message: document.isPages
                            ? "Playing the document stops at this page"
                            : "Playback stops at the end of this ${document.kind.one}",
                        child: Icon(Icons.pause_circle_outline,
                            size: 13, color: theme.colors.onSurfaceVariant),
                      ),
                    if (index < all.length - 1) _transitionMark(theme, index),
                    // The button's own context, not the panel's: a menu placed
                    // from the panel appeared beside the panel, which for a row
                    // half way down a list is nowhere near what was pressed.
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

  /// _transitionMark says whether this scene gives way its own way or the
  /// document's.
  ///
  /// Plain for the default and filled for a scene with one of its own, so a
  /// list of twelve scenes says at a glance which of them have been given
  /// something particular -- which is the question somebody scanning it is
  /// asking.
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

  /// _previewMaxHeight caps a preview. Drawn at the column's width alone, a
  /// sidebar dragged wide made each page taller than the screen.
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
    // Draggable rather than a ReorderableListView, for the reason the layer
    // list is: that widget moves a row by GlobalKey during layout, and a row
    // carrying tooltips cannot be re-attached that way.
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
                child: Text(scene.saysAt(index, document.kind),
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

    // Under the button that was pressed. A menu takes its place from the
    // overlay it opens in rather than from the screen, so the button's
    // rectangle has to be measured against that overlay -- handed plain
    // global coordinates it lands wherever the overlay happens to begin.
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
        // Copied here and pasted into whichever canvas is open next, which
        // is what carries a scene from one document to another. No Rename:
        // the name itself is double-clicked.
        const PopupMenuItem(value: "copy", child: Text("Copy")),
        // Kept for good, in the Presets sidebar, as a copy: the scene goes
        // on being edited and none of that reaches the preset.
        PopupMenuItem(
            value: "preset",
            child: Text("Save ${document.kind.one} as preset")),
        // Which of the two ends of the document this is, for a document of
        // pages. Only at the ends: a cover in the middle of a document is
        // not a cover, and offering it there is offering nonsense.
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
        initial: scene.saysAt(index, document.kind));
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

/// _ScenePainter draws one scene, small.
///
/// The document's own renderer, handed the scene as though it were the
/// document: a preview drawn by anything else is a second opinion about what
/// the canvas looks like, and the one that is easy to draw is the one that is
/// wrong.
class _ScenePainter extends CustomPainter {
  final CanvasDocument document;
  final int index;

  /// images is the editor's own picture store. Without it every picture was
  /// drawn as its "Loading" placeholder, for good: nothing here ever asked for
  /// the picture itself. Repainted when a picture arrives.
  final CanvasImageStore images;

  _ScenePainter(
      {required this.document, required this.index, required this.images})
      : super(repaint: images);

  /// frameOf is the moment a scene is shown at: the middle of its timeline,
  /// where what it is about is on screen. Frame nought is usually before any
  /// of it has arrived.
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
      // What the facing page hangs across the spine is part of this page, as
      // it is on the canvas: its paper first, then the neighbour's overhang,
      // then this page's own elements over it. Drawn alone, a picture laid
      // across the spread was cut off at the spine in the list.
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
/// text.
///
/// Its own thing because neither of the two ready-made answers fits a list
/// row: Material's switch is built for a settings page and is half again as
/// tall as a row, and an icon button is small enough to read as a decoration
/// rather than as something to press.
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
