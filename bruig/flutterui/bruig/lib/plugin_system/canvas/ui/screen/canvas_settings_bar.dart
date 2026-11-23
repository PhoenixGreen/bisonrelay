import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:bruig/components/containers.dart' show BisonRelayLogo;
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/panel_reader.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/canvas_sidebar.dart';
import 'package:bruig/theming_system/theme_manager.dart';

// The canvas's own settings, the line the band opens, so whatever imports
// the band has them.
export 'package:bruig/plugin_system/canvas/ui/screen/canvas_settings_panel.dart';

// canvas_settings_bar.dart is the band of controls above the canvas, and the
// panel of canvas settings that drops out of it. The band is always one
// line: the tools, the zoom, and the actions that never move (undo, redo,
// Publish). CanvasSettingsPanel goes in the line under the band (see
// BandLine). The frame count is on the timeline.

/// BandLine is a line that opens under the band, pushing the canvas down.
/// They share the one place, so there is one open or none.
enum BandLine {
  /// settings is the canvas's own settings (CanvasSettingsPanel).
  settings,

  /// guides is the grid, guides, rulers and snapping (CanvasGuidesPanel).
  guides,
}

class CanvasSettingsBar extends StatefulWidget {
  final CanvasController controller;

  /// onPublish opens the publish sheet, held by the screen, which has the
  /// document's saved name and the image store.
  final VoidCallback onPublish;

  /// line is the line open under the band, if one is, and onLine asks for
  /// another, or for none: the screen holds it and draws the line.
  final BandLine? line;
  final ValueChanged<BandLine?> onLine;

  final bool timelineOpen;

  /// onToggleTimeline shows or hides the panels under the canvas; null
  /// where they are always shown (a piece of sound).
  final VoidCallback? onToggleTimeline;

  /// canvasShown is whether the canvas is on screen; onToggleCanvas puts it
  /// away, giving the mixer and effects its room, or brings it back.
  final bool canvasShown;
  final VoidCallback? onToggleCanvas;

  /// onShowSidebar brings a hidden sidebar back; null while it shows.
  final VoidCallback? onShowSidebar;

  const CanvasSettingsBar({
    required this.controller,
    required this.onPublish,
    required this.onLine,
    required this.timelineOpen,
    required this.onToggleTimeline,
    this.line,
    this.canvasShown = true,
    this.onToggleCanvas,
    this.onShowSidebar,
    super.key,
  });

  @override
  State<CanvasSettingsBar> createState() => _CanvasSettingsBarState();
}

/// _hasLayouts is whether any page of [doc] has a Layout to read.
bool _hasLayouts(CanvasDocument doc) => doc.allScenes
    .any((s) => s.elements.any((e) => e is LayoutElement && e.visible));

class _CanvasSettingsBarState extends State<CanvasSettingsBar> {
  CanvasController get controller => widget.controller;

  // Not the controller itself: nothing on the band moves with a drag or a
  // frame of play (see CanvasController.chrome).
  @override
  void initState() {
    super.initState();
    controller.chrome.addListener(_onChanged);
  }

  @override
  void dispose() {
    controller.chrome.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// _menuHidden is whether the app's menu is put away.
  bool _menuHidden(BuildContext context) =>
      Provider.of<CanvasPreferences>(context).menuHidden;

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Container(
      width: double.infinity,
      // No bottom padding: the SizedBox under the row supplies it.
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 0),
      decoration: BoxDecoration(
        color: theme.colors.surfaceContainerLow,
        border: Border(
            bottom: BorderSide(color: theme.colors.outlineVariant, width: 1)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          // The app's logo while its menu is put away for the canvas: the way
          // back to it (CanvasPreferences.menuHidden).
          if (_menuHidden(context))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: "Show the menu",
                child: InkWell(
                  key: const ValueKey("canvasShowMenu"),
                  borderRadius: BorderRadius.circular(4),
                  onTap: () =>
                      Provider.of<CanvasPreferences>(context, listen: false)
                          .menuHidden = false,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: BisonRelayLogo(size: controlHeight),
                  ),
                ),
              ),
            ),
          // The tools and zoom in one stretch taking the room the right-hand
          // buttons do not; a narrow window scrolls the tools rather than
          // pushing the row under the buttons. No Spacer after it: two
          // flexible children would split the leftover, leaving a hole or
          // hiding the last tools.
          Expanded(
            child: Row(children: [
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _viewControls(theme),
                ),
              ),
              _zoomGroup(theme),
              // Closes the group, so the percentage ends the view controls.
              _divider(theme),
            ]),
          ),
          _actions(theme),
        ]),
        const SizedBox(height: 5),
      ]),
    );
  }

  /// _viewControls is the tools and zoom: how the canvas is looked at.
  Widget _viewControls(ThemeNotifier theme) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onShowSidebar != null) ...[
            CanvasSidebarRestoreButton(onShow: widget.onShowSidebar!),
            _divider(theme),
          ],
          // Which scene shows, first, as all to its right is about it.
          if (controller.document.hasScenes) ...[
            _barButton(theme,
                icon: Icons.skip_previous_outlined,
                tooltip: "The scene before this one",
                onPressed: controller.document.at <= 0
                    ? null
                    : () => controller.goToScene(controller.document.at - 1)),
            _SceneField(controller: controller, theme: theme),
            _barButton(theme,
                icon: Icons.skip_next_outlined,
                tooltip: "The scene after this one",
                onPressed: controller.document.at >=
                        controller.document.allScenes.length - 1
                    ? null
                    : () => controller.goToScene(controller.document.at + 1)),
            // Panel mode, to try the book as a reader steps through it.
            if (_hasLayouts(controller.document))
              _barButton(theme,
                  key: const ValueKey("readPanels"),
                  icon: Icons.auto_stories_outlined,
                  tooltip: "Read panel by panel: back and forward step "
                      "through each page's panels, in their reading order",
                  onPressed: () => showPanelReader(
                      context, controller.document, controller.images,
                      scene: controller.document.at)),
            _divider(theme),
          ],
          // The tools first: the active one changes what every gesture does.
          // On a 3D stage they are what the gizmo does (move, rotate, scale)
          // and how much of the view controls float at the stage's right.
          if (controller.onStage3d) ...[
            for (var (tool, icon) in const [
              (StageTool.move, Icons.open_with),
              (StageTool.rotate, Icons.rotate_right),
              (StageTool.scale, Icons.open_in_full),
            ])
              _barButton(theme,
                  key: ValueKey("stageTool-${tool.name}"),
                  icon: icon,
                  tooltip: "${tool.label} (${tool.key}) — ${tool.description}",
                  active: controller.stageTool == tool,
                  onPressed: () => controller.stageTool = tool),
            _barButton(theme,
                key: const ValueKey("stageNav"),
                icon: switch (controller.stageNav) {
                  StageNav.all => Icons.threed_rotation,
                  StageNav.orbit => Icons.radio_button_checked,
                  StageNav.none => Icons.visibility_off_outlined,
                },
                tooltip: switch (controller.stageNav) {
                  StageNav.all =>
                    "View controls: all of them — press for the orbit ball "
                        "alone",
                  StageNav.orbit =>
                    "View controls: the orbit ball alone — press to hide "
                        "them",
                  StageNav.none => "View controls: hidden — press to show "
                      "them all",
                },
                active: controller.stageNav != StageNav.none,
                onPressed: () =>
                    controller.stageNav = switch (controller.stageNav) {
                      StageNav.all => StageNav.orbit,
                      StageNav.orbit => StageNav.none,
                      StageNav.none => StageNav.all,
                    }),
          ] else ...[
            _barButton(theme,
                key: const ValueKey("canvasToolSelect"),
                icon: Icons.near_me_outlined,
                tooltip: "${CanvasTool.select.label} — "
                    "${CanvasTool.select.description}",
                active: controller.tool == CanvasTool.select,
                onPressed: () => controller.tool = CanvasTool.select),
            _barButton(theme,
                key: const ValueKey("canvasToolPan"),
                icon: Icons.pan_tool_outlined,
                tooltip:
                    "${CanvasTool.pan.label} — ${CanvasTool.pan.description}",
                active: controller.tool == CanvasTool.pan,
                onPressed: () => controller.tool = CanvasTool.pan),
          ],
          // Snap and the page lock, on a page and on a stage alike.
          _SnapButton(
              controller: controller,
              theme: theme,
              onMore: widget.line == BandLine.guides
                  ? null
                  : () => widget.onLine(BandLine.guides)),
          _barButton(theme,
              key: const ValueKey("pageLock"),
              icon: controller.pageLocked
                  ? Icons.lock_outline
                  : Icons.lock_open_outlined,
              tooltip: switch ((controller.pageLocked, controller.onStage3d)) {
                (true, true) => "Unlock the page (L) — while it is locked "
                    "the page stays put and drags, scrolls and pinches steer "
                    "the stage's camera",
                (true, false) => "Unlock the page (L) — it cannot be "
                    "scrolled or zoomed while locked",
                (false, true) => "Lock the page in place (L): then drags, "
                    "scrolls and pinches steer the stage's camera, not the "
                    "page",
                (false, false) => "Lock the page in place (L): no scrolling "
                    "or zooming it by accident",
              },
              active: controller.pageLocked,
              onPressed: () => controller.pageLocked = !controller.pageLocked),
          _divider(theme),
          // Text box joins: locked so a drag cannot change them, and hidden
          // so the lines stop crossing the design. Drawn while working, never
          // published; only where there is a join.
          if (_hasJoins) ...[
            _barButton(theme,
                icon: controller.lockJoins ? Icons.link_off : Icons.link,
                tooltip: controller.lockJoins
                    ? "Let the joins between text boxes be dragged again"
                    : "Lock the joins between text boxes",
                active: controller.lockJoins,
                onPressed: () => controller.lockJoins = !controller.lockJoins),
            _barButton(theme,
                icon: controller.hideJoins
                    ? Icons.timeline
                    : Icons.polyline_outlined,
                tooltip: controller.hideJoins
                    ? "Show the lines between linked text boxes"
                    : "Hide the lines between linked text boxes, keeping their "
                        "grips",
                active: controller.hideJoins,
                onPressed: () => controller.hideJoins = !controller.hideJoins),
          ],
          // Every element's box, or only the selected one's.
          _barButton(theme,
              icon: controller.showAllBounds
                  ? Icons.select_all
                  : Icons.check_box_outline_blank,
              tooltip: controller.showAllBounds
                  ? "Hide the boxes around the elements that are not selected"
                  : "Keep every element's box in sight",
              active: controller.showAllBounds,
              onPressed: () =>
                  controller.showAllBounds = !controller.showAllBounds),
          _barButton(theme,
              icon: controller.showHelpers
                  ? Icons.highlight_alt
                  : Icons.crop_free,
              tooltip: controller.showHelpers
                  ? "Hide the selection box and handles"
                  : "Show the selection box and handles",
              active: controller.showHelpers,
              onPressed: () =>
                  controller.showHelpers = !controller.showHelpers),
          _divider(theme),
          // What the window shows before the zoom: fit it all, fit the width,
          // or show the room outside the page. "All of it" differs by shape
          // (a banner is limited by height, a 9:16 story is a narrow strip),
          // so the button says which it is; a press changes to the other, or,
          // zoomed away, goes back.
          _barButton(theme,
              key: const ValueKey("canvasFit"),
              icon: controller.fit == CanvasFit.whole
                  ? Icons.fit_screen_outlined
                  : Icons.width_full,
              tooltip: switch ((controller.fit, controller.atFit)) {
                (CanvasFit.whole, true) => "Showing the whole canvas — "
                    "press to fit to width instead",
                (CanvasFit.width, true) => "Fitting to width, the canvas "
                    "scrolling if it is taller than the window — press to "
                    "show the whole canvas instead",
                (CanvasFit.whole, false) => "Show the whole canvas again",
                (CanvasFit.width, false) => "Fit to width again",
              },
              active: controller.atFit,
              onPressed: controller.pageLocked
                  ? null
                  : () => !controller.atFit
                      ? (controller.fit == CanvasFit.whole
                          ? controller.showWhole()
                          : controller.fitWidth())
                      : (controller.fit == CanvasFit.whole
                          ? controller.fitWidth()
                          : controller.showWhole())),
          // The world outside the canvas, for building entrances and exits.
          _barButton(theme,
              icon: controller.showOverspill
                  ? Icons.select_all
                  : Icons.filter_center_focus,
              tooltip: controller.showOverspill
                  ? "Hide the area outside the canvas"
                  : "Show a margin outside the canvas, for animating things "
                      "on and off",
              active: controller.showOverspill,
              onPressed: () =>
                  controller.showOverspill = !controller.showOverspill),
        ],
      );

  /// _zoomGroup is the zoom reading, kept out of the scrolling part: it
  /// must be read, and would be pushed under the right-hand buttons.
  Widget _zoomGroup(ThemeNotifier theme) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _divider(theme),
          // Document to screen pixels, the fitted scale times the zoom (the
          // zoom alone would read 100% for a 4096-pixel canvas squeezed into
          // a third of a window). Typed into, or dragged sideways to scrub.
          _ZoomField(controller: controller, theme: theme),
        ],
      );

  /// _hasJoins is whether any text box on this canvas flows into another.
  bool get _hasJoins {
    var document = controller.document;
    for (var e in document.elements) {
      if (e is! TextElement || !e.flowsOnIn(document)) continue;
      if (document.elementById(e.flowTo) != null) return true;
    }
    return false;
  }

  /// _toggle opens [line] under the band, or shuts it if it is the one open.
  void _toggle(BandLine line) =>
      widget.onLine(widget.line == line ? null : line);

  /// _actions is the settings toggle, undo, redo and Publish, pinned right.
  Widget _actions(ThemeNotifier theme) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grid, guides and rulers behind one button: the panel sets them up.
          _barButton(theme,
              icon: Icons.grid_4x4,
              tooltip: "Grid, guides, rulers and snapping",
              active: widget.line == BandLine.guides,
              onPressed: () => _toggle(BandLine.guides)),
          _divider(theme),
          // The timeline beside the canvas settings: both open a line across
          // the window. The mixer's button is on the timeline.
          _barButton(theme,
              icon: Icons.view_timeline_outlined,
              tooltip: widget.timelineOpen
                  ? "Hide the timeline"
                  : "Show the timeline",
              active: widget.timelineOpen,
              onPressed: widget.onToggleTimeline),
          _barButton(theme,
              icon: Icons.tune,
              tooltip: "Canvas settings",
              active: widget.line == BandLine.settings,
              onPressed: () => _toggle(BandLine.settings)),
          // Lit while the canvas is away: the unusual state is the one to
          // see. Not on an audio document, which has no canvas to show.
          if (widget.onToggleCanvas != null)
            _barButton(theme,
                key: const ValueKey("toggleCanvas"),
                icon: widget.canvasShown
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                tooltip: widget.canvasShown
                    ? "Hide the canvas, to give the mixer and effects the room"
                    : "Show the canvas",
                active: !widget.canvasShown,
                onPressed: widget.onToggleCanvas),
          // Made into a game: the Game panel, where elements get their parts.
          _barButton(theme,
              key: const ValueKey("makeGame"),
              icon: Icons.sports_esports_outlined,
              tooltip: controller.document.game
                  ? "Making a game: its settings are in the Game panel. "
                      "Press to make it an ordinary canvas again"
                  : "Make a game: the Game panel in the sidebar gives each "
                      "element what it does when played",
              active: controller.document.game,
              onPressed: () =>
                  controller.makingGame = !controller.document.game),
          _divider(theme),
          _barButton(theme,
              icon: Icons.undo,
              tooltip: "Undo",
              onPressed: controller.canUndo ? controller.undo : null),
          _barButton(theme,
              icon: Icons.redo,
              tooltip: "Redo",
              onPressed: controller.canRedo ? controller.redo : null),
          const SizedBox(width: 4),
          Tooltip(
            message: "Publish this canvas",
            child: Material(
              color: theme.colors.primary,
              borderRadius: BorderRadius.circular(5),
              child: InkWell(
                borderRadius: BorderRadius.circular(5),
                onTap: widget.onPublish,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.ios_share,
                      size: 16, color: theme.colors.onPrimary),
                ),
              ),
            ),
          ),
        ],
      );

  Widget _divider(ThemeNotifier theme) => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        color: theme.colors.outlineVariant,
      );

  /// _barButton is a control in a pinned cluster: not a CanvasIconButton,
  /// whose top padding lines up with captions this row does not have.
  Widget _barButton(
    ThemeNotifier theme, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool active = false,
    Key? key,
  }) =>
      Tooltip(
        key: key,
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: onPressed,
          child: Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: active ? theme.colors.secondaryContainer : null,
            ),
            child: Icon(
              icon,
              size: 15,
              color: onPressed == null
                  ? theme.colors.onSurfaceVariant.withValues(alpha: 0.3)
                  : active
                      ? theme.colors.onSecondaryContainer
                      : theme.colors.onSurfaceVariant,
            ),
          ),
        ),
      );
}

/// _SceneField is which scene of how many, with a box to type one to go to.
/// It says Master while the shared canvas is edited.
class _SceneField extends StatefulWidget {
  final CanvasController controller;
  final ThemeNotifier theme;

  const _SceneField({required this.controller, required this.theme});

  @override
  State<_SceneField> createState() => _SceneFieldState();
}

class _SceneFieldState extends State<_SceneField> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// _shown is what the box last said; the text is replaced on a new scene.
  String _shown = "";

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        // The number alone while it is being typed into.
        _text.text = "${widget.controller.document.at + 1}";
        _text.selection =
            TextSelection(baseOffset: 0, extentOffset: _text.text.length);
        return;
      }
      _commit();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    var wanted = int.tryParse(_text.text.split("/").first.trim());
    if (wanted != null) widget.controller.goToScene(wanted - 1);
    setState(() => _shown = "");
  }

  @override
  Widget build(BuildContext context) {
    var document = widget.controller.document;
    var reading = document.editingMaster
        ? "Master"
        : "${document.at + 1}/${document.allScenes.length}";
    if (!_focus.hasFocus && reading != _shown) {
      _shown = reading;
      _text.text = reading;
    }

    var type = TextStyle(
        fontSize: 12, color: widget.theme.colors.onSurfaceVariant, height: 1.1);

    return Center(
      child: SizedBox(
        // Room for the longest thing it says, the word Master.
        width: _widest(type),
        child: Tooltip(
          message: "Which ${document.kind.one} is showing. "
              "Type a number to go to one.",
          child: TextField(
            key: const ValueKey("sceneField"),
            controller: _text,
            focusNode: _focus,
            // Centred: the box is as wide as the longest reading.
            textAlign: TextAlign.center,
            style: type,
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: UnderlineInputBorder(
                  borderSide:
                      BorderSide(color: widget.theme.colors.primary, width: 1)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 2),
            ),
            onSubmitted: (_) => _commit(),
          ),
        ),
      ),
    );
  }

  double _widest(TextStyle style) => _readingWidth(context, "Master", style);
}

/// _readingWidth is the room [text] takes in a field on the band, set in
/// [style] at the app's text size (which is what it is drawn at), with the
/// padding either side and the room the caret needs at the end.
double _readingWidth(BuildContext context, String text, TextStyle style) {
  var painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  var width = painter.width;
  painter.dispose();
  return width + 4 + 6;
}

/// _ZoomField is the percentage on the band: what is on screen, typed into
/// after a click, or dragged sideways to scrub (right zooms in). A
/// double-click fits the canvas again. Still while the page is locked. Not a
/// CanvasNumberField, whose caption would make the band two lines.
class _ZoomField extends StatefulWidget {
  final CanvasController controller;
  final ThemeNotifier theme;

  const _ZoomField({required this.controller, required this.theme});

  @override
  State<_ZoomField> createState() => _ZoomFieldState();
}

class _ZoomFieldState extends State<_ZoomField> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// _shown is what the box last said, so the text is replaced only when the
  /// view moves: replacing it every rebuild would fight the typist.
  int _shown = -1;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        // The digits alone while it is being typed into.
        _text.text = _text.text.replaceAll("%", "").trim();
        _text.selection =
            TextSelection(baseOffset: 0, extentOffset: _text.text.length);
        return;
      }
      _commit();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    var wanted = double.tryParse(_text.text.replaceAll("%", "").trim());
    if (wanted != null) widget.controller.setViewScale(wanted / 100);
    setState(() {
      _shown = -1;
      _typing = false;
    });
  }

  bool _typing = false;

  /// _type opens the reading for typing, with the caret in it.
  void _type() {
    setState(() => _typing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  bool _scrubbing = false;

  /// _scrub zooms by a drag of [dx] pixels: about doubling per 120.
  void _scrub(double dx) {
    var c = widget.controller;
    if (c.pageLocked) return;
    c.zoomBy(math.exp(dx * 0.006));
  }

  /// _fit puts back the fit last chosen.
  void _fit() {
    var c = widget.controller;
    if (c.pageLocked) return;
    c.fit == CanvasFit.whole ? c.showWhole() : c.fitWidth();
  }

  /// _boxWidth is the room the widest reading takes, so the box never
  /// changes width as the view moves. Four eights, since eight is this face's
  /// widest digit (1400% would measure narrow because of the one).
  double _boxWidth(TextStyle style) => _readingWidth(context, "8888%", style);

  @override
  Widget build(BuildContext context) {
    var at = (widget.controller.viewScale * 100).round();
    var locked = widget.controller.pageLocked;
    if (!_focus.hasFocus && at != _shown) {
      _shown = at;
      // The sign is part of the reading, not a suffix widget placed against
      // a box whose width depends on the number.
      _text.text = "$at%";
    }

    var type = TextStyle(
        fontSize: 12, color: widget.theme.colors.onSurfaceVariant, height: 1.1);

    // No height of its own: as tall as its text, centred against the buttons
    // (in a taller box the underline crosses the digits). Not typed into, it
    // is a reading to drag; clicked, the field takes over.
    if (!_typing) {
      var colors = widget.theme.colors;
      return Center(
        child: Opacity(
          opacity: locked ? 0.45 : 1,
          child: Tooltip(
            message: locked
                ? "How large the canvas is drawn. The page is locked, so it "
                    "stays as it is."
                : "How large the canvas is drawn, as a percentage of its own "
                    "pixels. Drag sideways to zoom, double-click to fit the "
                    "canvas again, click to type one.",
            child: MouseRegion(
              cursor: locked
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                key: const ValueKey("zoomScrub"),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart:
                    locked ? null : (_) => setState(() => _scrubbing = true),
                onHorizontalDragUpdate:
                    locked ? null : (d) => _scrub(d.delta.dx),
                onHorizontalDragEnd:
                    locked ? null : (_) => setState(() => _scrubbing = false),
                onDoubleTap: locked ? null : _fit,
                onTap: locked ? null : _type,
                child: Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _scrubbing ? colors.secondaryContainer : null,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.code, size: 11, color: colors.onSurfaceVariant),
                    const SizedBox(width: 2),
                    SizedBox(
                      width: _boxWidth(type) - 6,
                      child: Text("$at%", style: type),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Center(
        child: SizedBox(
      // The reading's room, with the per cent sign pinned right (_boxWidth).
      width: _boxWidth(type) + 13,
      child: Tooltip(
        message: "How large the canvas is drawn, as a percentage of its own "
            "pixels. Type one to go there.",
        child: TextField(
          controller: _text,
          focusNode: _focus,
          // Left, against the buttons it belongs to.
          textAlign: TextAlign.left,
          style: type,
          decoration: InputDecoration(
            // Collapsed: no padding. Dense still reserves room under the
            // text for a decoration, lifting the digits above the buttons.
            isCollapsed: true,
            // No line until typed into: only then must it look like a field.
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: UnderlineInputBorder(
                borderSide:
                    BorderSide(color: widget.theme.colors.primary, width: 1)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 2),
          ),
          // Committed as the caret leaves it -- see initState.
          onSubmitted: (_) => _focus.unfocus(),
        ),
      ),
    ));
  }
}

/// _SnapButton is Snap on the band as a split button: the switch, and an
/// arrow for what it snaps to (page lines on a page, 3D steps on a stage).
/// The same switch as in the Grid and guides settings.
class _SnapButton extends StatelessWidget {
  final CanvasController controller;
  final ThemeNotifier theme;

  /// onMore opens the Grid and guides settings; null while they are open.
  final VoidCallback? onMore;

  const _SnapButton(
      {required this.controller, required this.theme, this.onMore});

  void _set(CanvasGuides next) =>
      controller.apply(controller.document.copyWith(guides: next));

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    var guides = controller.document.guides;
    var on = controller.canvasSnap;
    var three = controller.onStage3d;
    var ink = on ? colors.onSecondaryContainer : colors.onSurfaceVariant;
    String metres(double v) =>
        v == v.roundToDouble() ? "${v.round()} m" : "$v m";
    MenuItemButton tick(String label, bool ticked, VoidCallback act,
            {Key? key}) =>
        MenuItemButton(
          key: key,
          onPressed: act,
          leadingIcon: Icon(
              ticked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 16),
          child: Text(label, style: const TextStyle(fontSize: 12)),
        );
    return MenuAnchor(
      menuChildren: [
        if (three) ...[
          for (var step in const [0.1, 0.25, 0.5, 1.0])
            tick("Moves in steps of ${metres(step)}", guides.stageStep == step,
                () => _set(guides.copyWith(stageStep: step)),
                key: ValueKey("snapStep-$step")),
          const Divider(height: 1),
          for (var turn in const [5.0, 15.0, 45.0])
            tick("Turns in steps of ${turn.round()}°", guides.stageTurn == turn,
                () => _set(guides.copyWith(stageTurn: turn)),
                key: ValueKey("snapTurn-${turn.round()}")),
        ] else ...[
          // The targets the guides panel offers, worded as a menu's.
          for (var target in SnapTarget.values)
            tick(
                "To ${target.label.toLowerCase()}",
                target.of(guides.snapTo),
                () => _set(guides.copyWith(
                    snapTo:
                        target.set(guides.snapTo, !target.of(guides.snapTo))))),
        ],
        const Divider(height: 1),
        MenuItemButton(
          key: const ValueKey("snapMore"),
          onPressed: onMore,
          leadingIcon: const Icon(Icons.grid_4x4, size: 16),
          child: const Text("All the snapping settings",
              style: TextStyle(fontSize: 12)),
        ),
      ],
      builder: (context, menu, _) => Container(
        height: 26,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          color: on ? colors.secondaryContainer : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Tooltip(
            message: on
                ? "Snapping (⇧S) — press to stop"
                : "Snap (⇧S) — ${three ? "move and turn in steps" : "land on "
                    "the guides, the grid and other elements"}",
            child: InkWell(
              key: const ValueKey("snapToggle"),
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(5)),
              onTap: () => controller.canvasSnap = !on,
              child: SizedBox(
                width: 24,
                height: 26,
                child: CustomPaint(painter: _MagnetIcon(ink)),
              ),
            ),
          ),
          Tooltip(
            message: "What it snaps to",
            child: InkWell(
              key: const ValueKey("snapMenu"),
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(5)),
              onTap: () => menu.isOpen ? menu.close() : menu.open(),
              child: SizedBox(
                width: 13,
                height: 26,
                child: Icon(Icons.arrow_drop_down, size: 14, color: ink),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// _MagnetIcon is Snap's magnet: there is none among the icons.
class _MagnetIcon extends CustomPainter {
  final Color color;
  const _MagnetIcon(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 24-unit square, as an icon is, 15 units across.
    var k = 15 / 24;
    canvas.translate(size.width / 2 - 12 * k, size.height / 2 - 12 * k);
    canvas.scale(k);
    var pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
        Path()
          ..moveTo(6, 4)
          ..lineTo(6, 12)
          ..arcToPoint(const Offset(18, 12),
              radius: const Radius.circular(6), clockwise: false)
          ..lineTo(18, 4),
        pen);
    canvas.drawLine(const Offset(6, 8), const Offset(10, 8), pen);
    canvas.drawLine(const Offset(14, 8), const Offset(18, 8), pen);
  }

  @override
  bool shouldRepaint(_MagnetIcon old) => old.color != color;
}
