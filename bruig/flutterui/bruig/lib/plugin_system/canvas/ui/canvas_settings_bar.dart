import 'dart:math' as math;

import 'package:bruig/components/containers.dart' show BisonRelayLogo;
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:provider/provider.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_strip.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_estimate.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/responsive_layout.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_dialogs.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/canvas_sidebar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// canvas_settings_bar.dart is the band of controls above the canvas, and the
// panel of canvas settings that drops out of it.
//
// The band is always exactly one line: the tools, the zoom, and the actions
// that must never move (undo, redo and Publish).
//
// The canvas settings are a separate widget, CanvasSettingsPanel, which the
// screen puts in the line under the band (see canvasSecondLine).
//
// The frame count lives on the timeline, beside the frames it counts.

/// _typeARate is the Rate list's Custom entry. Not a rate, so it cannot
/// collide with one: every real rate is at least one, and zero is the entry
/// naming the rate that is set.
const int _typeARate = -1;

/// CanvasSettingsBar is the settings band.
class CanvasSettingsBar extends StatefulWidget {
  final CanvasController controller;

  /// onPublish opens the publish sheet. Held by the screen, which has the
  /// document's saved name and the image store.
  final VoidCallback onPublish;

  /// canvasSettingsOpen and onToggleCanvasSettings drive the settings panel
  /// the screen puts under the band.
  final bool canvasSettingsOpen;
  final VoidCallback onToggleCanvasSettings;

  /// guidesOpen and onToggleGuides drive the grid and guides line, which opens
  /// in the same place and the same way.
  final bool guidesOpen;
  final VoidCallback onToggleGuides;

  /// timelineOpen and onToggleTimeline show and hide the transport and the
  /// strip under the canvas. Beside the other two, since it too decides how
  /// much of the window the design gets.
  final bool timelineOpen;
  final VoidCallback onToggleTimeline;

  /// canvasShown is whether the canvas itself is on screen, and
  /// onToggleCanvas puts it away or brings it back: put away, the mixer and
  /// the effects have the whole of the room it was in.
  final bool canvasShown;
  final VoidCallback? onToggleCanvas;

  /// onShowSidebar brings a hidden sidebar back, and is null while it is
  /// showing. See CanvasSidebarRestoreButton: a hidden sidebar needs a way
  /// back somewhere predictable.
  final VoidCallback? onShowSidebar;

  const CanvasSettingsBar({
    required this.controller,
    required this.onPublish,
    required this.canvasSettingsOpen,
    required this.guidesOpen,
    required this.onToggleGuides,
    required this.timelineOpen,
    required this.onToggleTimeline,
    required this.onToggleCanvasSettings,
    this.canvasShown = true,
    this.onToggleCanvas,
    this.onShowSidebar,
    super.key,
  });

  @override
  State<CanvasSettingsBar> createState() => _CanvasSettingsBarState();
}

class _CanvasSettingsBarState extends State<CanvasSettingsBar> {
  CanvasController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// _menuHidden is whether the app's menu is put away for the canvas;
  /// false where there are no preferences to say (a test's bar).
  bool _menuHidden(BuildContext context) {
    try {
      return Provider.of<CanvasPreferences>(context).menuHidden;
    } on ProviderNotFoundException {
      return false;
    }
  }

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
          // The app's logo, while its menu is put away for the canvas: the way
          // back to it. See CanvasPreferences.menuHidden.
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
          // The tools and the zoom in one stretch that takes all the room the
          // buttons on the right do not want; a narrow window scrolls the tools
          // rather than pushing the row under the buttons. Expanded with no Spacer
          // after it: two flexible children split the leftover width between them,
          // leaving a hole when there is room and hiding the last tools when there
          // is not. The zoom sits against the tools as the end of that group.
          Expanded(
            child: Row(children: [
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _viewControls(theme),
                ),
              ),
              _zoomGroup(theme),
              // The rule that closes the group, so the percentage reads as the end
              // of the view controls.
              _divider(theme),
            ]),
          ),
          _actions(theme),
        ]),
        const SizedBox(height: 5),
      ]),
    );
  }

  /// _viewControls is the tools and the zoom: how you are looking at the
  /// canvas, rather than what is on it.
  Widget _viewControls(ThemeNotifier theme) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onShowSidebar != null) ...[
            CanvasSidebarRestoreButton(onShow: widget.onShowSidebar!),
            _divider(theme),
          ],
          // Which canvas of several is showing, first: everything to the right is
          // about that canvas. Hidden for a document of one scene.
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
            _divider(theme),
          ],
          // The tools first, because the active one changes what every other
          // gesture does. On a 3D stage they are what the gizmo on the selected
          // element does (move, rotate, scale) and how much of the view controls
          // float at the stage's right.
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
              onMore: widget.guidesOpen ? null : widget.onToggleGuides),
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
          // The joins between text boxes: locked so a drag cannot change them,
          // and hidden so the lines stop crossing the design. Like the boxes and
          // handles, drawn while working and never published. Only where there
          // is a join.
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
          // Every element's box, or only the selected one's: one switch for the
          // canvas, drawn while working and never published.
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
          // What the window shows, before the zoom: fit it all in, fit the
          // width, and show the room outside the page. "All of it" differs by
          // shape (a wide banner is limited by the height; a 9:16 story fitted
          // whole is a narrow strip), so one button says which it is and a press
          // changes to the other, or, zoomed away from it, goes back.
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
          // The world just outside the canvas, for building entrances and
          // exits.
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

  /// _zoomGroup is the zoom's reading, kept out of the scrolling part of the
  /// bar: it is the one thing here that has to be read, and in the scrolling
  /// row a narrow window would push it under the buttons on the right.
  Widget _zoomGroup(ThemeNotifier theme) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _divider(theme),
          // What is on screen: document pixels to screen pixels, the fitted scale
          // times the zoom (the zoom alone would read 100% for a 4096-pixel canvas
          // squeezed into a third of a window). A field, to type a percentage;
          // dragged sideways, it scrubs.
          _ZoomField(controller: controller, theme: theme),
        ],
      );

  /// _hasJoins is whether any text box on this canvas flows into another.
  bool get _hasJoins {
    var document = controller.document;
    for (var e in document.elements) {
      if (e is! TextElement || e.flowTo.isEmpty) continue;
      if (document.elementById(e.flowTo) != null) return true;
    }
    return false;
  }

  /// _actions is the canvas settings toggle, undo, redo and Publish, pinned to
  /// the right of the band. Publish is an icon, its tooltip carrying the word.
  Widget _actions(ThemeNotifier theme) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The grid, guides and rulers, all behind one button: the panel is
          // where they are set up.
          _barButton(theme,
              icon: Icons.grid_4x4,
              tooltip: "Grid, guides, rulers and snapping",
              active: widget.guidesOpen,
              onPressed: widget.onToggleGuides),
          _divider(theme),
          // The timeline, beside the canvas settings: both open a line across
          // the window. The mixer's button is on the timeline, beside the
          // effects'.
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
              active: widget.canvasSettingsOpen,
              onPressed: widget.onToggleCanvasSettings),
          // Lit while the canvas is away, as the others are lit while what they
          // open is out: the unusual state is the one to see. Not on an audio
          // document, which has no canvas to show.
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
          // Made into a game: the Game panel in the sidebar, where each element
          // is given what it does, and the game is played from.
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

  /// _barButton is a control in one of the two pinned clusters: not a
  /// CanvasIconButton, whose top padding lines it up with a captioned
  /// control, since this row has no captions.
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

/// CanvasSettingsPanel is the canvas's own settings: its shape, its export
/// width, and what publishing it will cost. The screen shows it under the
/// band while the band's Canvas settings button is pressed (see
/// canvasSecondLine).
class CanvasSettingsPanel extends StatefulWidget {
  final CanvasController controller;
  const CanvasSettingsPanel({required this.controller, super.key});

  @override
  State<CanvasSettingsPanel> createState() => _CanvasSettingsPanelState();
}

class _CanvasSettingsPanelState extends State<CanvasSettingsPanel> {
  CanvasController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => CanvasSettingsStrip(
      groups: (context) => _canvasGroups(context, ThemeNotifier.of(context)));

  /// _estimateGroup is what publishing this canvas will cost, beside the
  /// ratio and export width that decide it. An estimate rather than a
  /// measurement, and it says so: rendering on every edit would be too slow.
  /// See estimateStillBytes.
  Widget _estimateGroup(
      BuildContext context, ThemeNotifier theme, CanvasDocument document) {
    var spec = document.estimate;
    // The formats that mean anything for this canvas: a GIF of a still is a
    // still, and a PNG of an animation is one frame of it.
    var offered = [
      for (var format in EstimateAs.values)
        if (format == EstimateAs.audio || format.moving == document.isAnimated)
          format,
    ];
    if (!offered.contains(spec.format)) {
      spec = spec.copyWith(format: offered.first);
    }

    var bytes = estimateBytes(document, spec);
    var behind = document.lastAnimatedFrame >= document.frames;

    void set(CanvasEstimate next) =>
        controller.apply(document.copyWith(estimate: next));

    return CanvasControlGroup(label: "Estimated size", children: [
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: SizedBox(
          height: controlHeight,
          child: Row(children: [
            Text(
              formatBytes(bytes),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colors.onSurface),
            ),
            if (behind) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: "There are keyframes past the end of the timeline. "
                    "Raise the frame count to reach them.",
                // error rather than tertiary: tertiary is a panel background, near-black
                // in the dark theme.
                child: Icon(Icons.warning_amber_rounded,
                    size: 14, color: theme.colors.error),
              ),
            ],
          ]),
        ),
      ),
      // What it is estimated as: the same canvas is four hundred kilobytes
      // as a PNG and forty as a JPEG.
      CanvasDropdown<EstimateAs>(
        key: const ValueKey("estimateAs"),
        label: "As a",
        value: spec.format,
        width: 118,
        options: [for (var format in offered) (format, format.label)],
        onChanged: (v) => set(spec.copyWith(format: v)),
      ),
      if (spec.format.lossy)
        CanvasNumberField(
          key: const ValueKey("estimateQuality"),
          label: "Quality",
          value: spec.quality.toDouble(),
          min: 1,
          max: 100,
          decimals: 0,
          width: 56,
          onChanged: (v) {
            controller.beginInteraction();
            controller.apply(
                document.copyWith(estimate: spec.copyWith(quality: v.round())),
                transient: true);
          },
          onCommit: controller.endInteraction,
        ),
      CanvasHint("An estimate rather than a measurement: encoding the real "
          "thing on every edit would make the editor unusable. "
          "${spec.format.description}."
          "${spec.format.lossy ? " Quality is what it is squeezed to — "
              "everything above about 90 costs a great deal and shows almost "
              "nothing." : ""}"),
    ]);
  }

  /// _audioGroup is the document's sound as a production: where it is going
  /// (a preset that sets everything at once), how it is written, and how loud
  /// it is brought to. Tempo, metre and quantise are on the timeline's control
  /// bar.
  Widget _audioGroup(CanvasDocument document) {
    var audio = document.audio;
    var export = audio.export;
    var mix = document.masterMix;
    void write(AudioSettings next, {MasterMix? master}) =>
        controller.apply(document.copyWith(audio: next, masterMix: master));
    void writeExport(AudioOptions next) => write(audio.copyWith(export: next));
    var preset = AudioPreset.values
        .where((p) =>
            p.options == export &&
            mix.normalise &&
            p.target == mix.target &&
            p.ceilingDb == mix.ceilingDb)
        .firstOrNull;
    var fixed = export.format.fixedRate;
    return CanvasControlGroup(label: "Audio", children: [
      CanvasDropdown<String>(
        key: const ValueKey("audioPreset"),
        label: "For",
        value: preset?.name ?? "",
        width: 150,
        options: [
          if (preset == null) ("", "Custom"),
          for (var p in AudioPreset.values) (p.name, p.label),
        ],
        onChanged: (name) {
          var p = AudioPreset.values.where((p) => p.name == name).firstOrNull;
          if (p == null) return;
          write(audio.copyWith(export: p.options),
              master: mix.copyWith(
                  target: p.target,
                  ceilingDb: p.ceilingDb,
                  normalise: true,
                  limiter: true));
        },
      ),
      // What it is mixed for. Surround is heard here folded down to two
      // speakers, and written whole wherever the file can carry it.
      CanvasDropdown<SpeakerLayout>(
        key: const ValueKey("audioSpeakers"),
        label: "Speakers",
        value: audio.speakers,
        width: 110,
        options: [for (var l in SpeakerLayout.values) (l, l.label)],
        onChanged: (l) => write(audio.copyWith(speakers: l)),
      ),
      CanvasDropdown<AudioFormat>(
        key: const ValueKey("audioFormat"),
        label: "Format",
        value: export.format,
        width: 104,
        options: [for (var f in AudioFormat.values) (f, f.label)],
        onChanged: (f) => writeExport(export.copyWith(format: f)),
      ),
      if (fixed == null)
        CanvasDropdown<int>(
          key: const ValueKey("audioRate"),
          label: "Rate",
          value: export.sampleRate,
          width: 86,
          options: [
            for (var r in audioRates)
              (r, "${(r / 1000).toStringAsFixed(1)} kHz")
          ],
          onChanged: (r) => writeExport(export.copyWith(sampleRate: r)),
        ),
      export.format.lossless
          ? CanvasDropdown<int>(
              key: const ValueKey("audioDepth"),
              label: "Depth",
              value: export.bitDepth,
              width: 76,
              options: [for (var d in audioDepths) (d, "$d-bit")],
              onChanged: (d) => writeExport(export.copyWith(bitDepth: d)),
            )
          : CanvasDropdown<int>(
              key: const ValueKey("audioBitrate"),
              label: "Bitrate",
              value: export.kbps,
              width: 90,
              options: [for (var k in audioBitrates) (k, "$k kbps")],
              onChanged: (k) => writeExport(export.copyWith(kbps: k)),
            ),
      CanvasToggle(
        key: const ValueKey("audioToTarget"),
        label: "To a loudness",
        value: mix.normalise,
        onChanged: (v) => controller
            .apply(document.copyWith(masterMix: mix.copyWith(normalise: v))),
      ),
      if (mix.normalise)
        CanvasDropdown<double>(
          key: const ValueKey("audioTarget"),
          label: "Of",
          value: mix.target,
          width: 104,
          options: [
            for (var (t, _) in loudnessOptions(mix.target))
              (t, "${t.round()} LUFS"),
          ],
          onChanged: (t) => controller
              .apply(document.copyWith(masterMix: mix.copyWith(target: t))),
        ),
      CanvasHint("Where this is going, and how its sound is written when it "
          "is published — every publish starts from these. ${preset?.note ?? "Choose a destination to set the format and the loudness at once, or set each yourself."} "
          "The loudness is measured over the whole mix and then limited, "
          "so a quiet piece is brought up and a loud one down."
          "${audio.speakers.isSurround ? " Mixed for ${audio.speakers.label}: heard here folded down to two speakers, and published with every speaker in WAV, FLAC, AAC, Opus and video — an MP3 carries the fold-down." : ""}"),
    ]);
  }

  List<Widget> _canvasGroups(BuildContext context, ThemeNotifier theme) {
    var document = controller.document;

    /// write is an immediate change (a dropdown), its own undo step.
    void write(CanvasDocument next) => controller.apply(next);

    /// edit is a change being made continuously, by typing or dragging. It
    /// opens the undo step itself: beginInteraction is idempotent, and a
    /// transient edit made outside an interaction is silently never pushed onto
    /// the history.
    void edit(CanvasDocument next) {
      controller.beginInteraction();
      controller.apply(next, transient: true);
    }

    return [
      CanvasControlGroup(label: "Canvas", children: [
        // What this document is for, first, because everything after follows
        // from it: the canvas's shape, its rate, what happens between two of
        // them and what they are called. See CanvasKind.
        CanvasDropdown<CanvasKind>(
          key: const ValueKey("canvasKind"),
          label: "Type",
          value: document.kind,
          width: 104,
          options: [for (var k in CanvasKind.values) (k, k.label)],
          onChanged: controller.setKind,
        ),
        CanvasHint("Scenes are canvases played one after another — a video, "
            "an animation, a presentation, a set of images. Pages are the "
            "leaves of a document: they take covers, page numbers and facing "
            "pages, and one gives way to the next with a page turn. Choosing "
            "Pages puts a new canvas on A4 at one frame a second; a canvas "
            "already on paper is left as it is."),
        // A piece of sound starts with no picture (Ratio "None") and can be
        // given one. Everything else always has one.
        if (document.kind.isAudio)
          CanvasDropdown<String>(
            key: const ValueKey("canvasRatio"),
            label: "Ratio",
            value: document.hasCanvas ? document.size.ratio.name : "",
            width: 116,
            options: [
              ("", "None"),
              for (var r in CanvasRatio.values) (r.name, r.label),
            ],
            onChanged: (name) {
              var r = CanvasRatio.values.where((r) => r.name == name);
              controller.beginInteraction();
              controller.setHasCanvas(r.isNotEmpty);
              if (r.isNotEmpty && r.first != document.size.ratio) {
                controller.setShape(document.size.copyWith(ratio: r.first));
              }
              controller.endInteraction();
            },
          )
        else
          CanvasDropdown<CanvasRatio>(
            key: const ValueKey("canvasRatio"),
            label: "Ratio",
            value: document.size.ratio,
            width: 116,
            options: [for (var r in CanvasRatio.values) (r, r.label)],
            // The shapes this document is laid out for are marked in the list,
            // each with a cross to give it up: clicking a shape starts a layout for
            // it. See CanvasDocument.targets.
            marked: {
              for (var r in CanvasRatio.values)
                if (document.targets.contains(r.name)) r,
            },
            removeTip: (r) => r.name == shapeKey(document.size)
                ? "Lay ${r.label} out again from another shape"
                : "Stop laying out for ${r.label}",
            onRemove: (r) {
              // The shape on screen cannot simply be dropped, so its cross lays it
              // out again from another.
              if (r.name != shapeKey(document.size)) {
                controller.forgetShape(r.name);
                return;
              }
              var other = document.targets
                  .where((t) => t != shapeKey(document.size))
                  .firstOrNull;
              if (other != null) controller.resetShape(other);
            },
            onChanged: (v) {
              // A shape change carries its own frame rate with it, but only where
              // nobody has chosen one (a typed 30 is kept).
              var rate = document.frameRate;
              if (rate == defaultRateFor(document.size.ratio, document.kind)) {
                // Through defaultRateFor rather than the shape alone: a document of
                // pages on A4 must not drop to one frame a second, because its pages
                // turn.
                rate = defaultRateFor(v, document.kind);
              }
              // Through the controller, which keeps the layout of the shape being
              // left and takes out the one of the shape being opened. See
              // CanvasController.setShape.
              controller.setShape(document.size.copyWith(ratio: v),
                  frameRate: rate);
            },
          ),
        // The sizes that have a name in this shape, beside the box that takes
        // any other number: 1920 across is 1080p at 16:9 and nothing on A4, so
        // the list follows the ratio. With no canvas there is no size nor frames
        // to count: the timeline goes by the tempo.
        if (document.hasCanvas) ...[
          if (sizePresetsFor(document.size.ratio) case var named
              when named.isNotEmpty)
            CanvasDropdown<int>(
              key: const ValueKey("canvasWidthPreset"),
              label: "Size",
              value: named.any((p) => p.width == document.size.exportWidth)
                  ? document.size.exportWidth
                  : 0,
              width: 168,
              options: [
                // "Custom" when the width is not one of the named ones.
                if (!named.any((p) => p.width == document.size.exportWidth))
                  (0, "Custom"),
                for (var preset in named)
                  (preset.width, "${preset.label} · ${preset.width}"),
              ],
              onChanged: (v) {
                if (v == 0) return;
                write(document.copyWith(
                    size: document.size.copyWith(exportWidth: v)));
              },
            ),
          CanvasNumberField(
            key: const ValueKey("canvasWidth"),
            label: "Max width",
            value: document.size.exportWidth.toDouble(),
            min: minCanvasWidth.toDouble(),
            max: maxCanvasWidth.toDouble(),
            width: 66,
            suffix: "px",
            onChanged: (v) => edit(document.copyWith(
                size: document.size.copyWith(exportWidth: v.round()))),
            onCommit: controller.endInteraction,
          ),
          // How many frames a second this canvas runs at, beside the shape since
          // the answer follows it: a page is one a second, a screen twenty-four.
          CanvasDropdown<int>(
            key: const ValueKey("canvasRatePreset"),
            label: "Rate",
            value: canvasFrameRates.contains(document.frameRate)
                ? document.frameRate
                : 0,
            width: 118,
            options: [
              // The rate somebody has typed, at the top and only while it is set:
              // there is never more than one custom rate to keep.
              if (!canvasFrameRates.contains(document.frameRate))
                (0, "Custom · ${document.frameRate}"),
              for (var rate in canvasFrameRates)
                (rate, rate == 1 ? "Still · 1" : "$rate fps"),
              (_typeARate, "Custom…"),
            ],
            onChanged: (v) async {
              // The rate already set: writing it would be an undo step for nothing.
              if (v == 0) return;
              if (v != _typeARate) {
                write(document.copyWith(frameRate: v));
                return;
              }
              var typed =
                  await askForFrameRate(context, initial: document.frameRate);
              if (typed == null) return;
              // The document as it is now: the one captured when the list was built
              // is out of date by the time the dialog closes.
              write(controller.document.copyWith(frameRate: typed));
            },
          ),
          if (document.size.ratio == CanvasRatio.custom)
            CanvasNumberField(
              key: const ValueKey("canvasAspect"),
              label: "Aspect",
              value: document.size.customRatio,
              min: 0.05,
              max: 20,
              decimals: 3,
              width: 58,
              onChanged: (v) => edit(document.copyWith(
                  size: document.size.copyWith(customRatio: v))),
              onCommit: controller.endInteraction,
            ),
          Padding(
            // No nudge: these readouts only appear on the band, where captions are
            // beside their controls and there is nothing above to line up under.
            padding: const EdgeInsets.only(left: 2),
            child: SizedBox(
              height: controlHeight,
              child: Center(
                child: Text(
                  // The file's size: where the design is laid out smaller and published
                  // larger, the larger number.
                  "${document.size.exportWidth} × ${document.size.exportHeight}",
                  style: TextStyle(
                      fontSize: 10, color: theme.colors.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ],
      ]),
      // The settings only a document of pages reads.
      if (document.isPages)
        CanvasControlGroup(label: "Pages", children: [
          CanvasToggle(
            key: const ValueKey("pagesFacing"),
            label: "Facing pages",
            value: document.pages.facing,
            onChanged: (v) => write(
                document.copyWith(pages: document.pages.copyWith(facing: v))),
          ),
          CanvasNumberField(
            key: const ValueKey("pagesStartAt"),
            label: "Numbered from",
            value: document.pages.startAt.toDouble(),
            min: 0,
            max: 9999,
            decimals: 0,
            width: 74,
            onChanged: (v) => edit(document.copyWith(
                pages: document.pages.copyWith(startAt: v.round()))),
            onCommit: controller.endInteraction,
          ),
          CanvasToggle(
            key: const ValueKey("pagesCountCovers"),
            label: "Covers count",
            value: document.pages.countCovers,
            onChanged: (v) => write(document.copyWith(
                pages: document.pages.copyWith(countCovers: v))),
          ),
          // Only where covers are counted, so a cover has a number to print.
          if (document.pages.countCovers)
            CanvasToggle(
              key: const ValueKey("pagesNumbersOnCovers"),
              label: "Number on covers",
              value: document.pages.numbersOnCovers,
              onChanged: (v) => write(document.copyWith(
                  pages: document.pages.copyWith(numbersOnCovers: v))),
            ),
          CanvasHint(
              "Facing pages draws the page beside the one you are working "
              "on, so a spread is seen as it is read — every page is still "
              "one page. Numbering is drawn by a counter element set to show "
              "the page number: put one on the master canvas and every page "
              "wears it. Covers are left out of the count unless you say "
              "otherwise${document.pages.countCovers ? "" : ", and are never "
                  "paired with another page"}."),
        ]),
      _audioGroup(document),
      // What changing the size does, at the end of the line. On, the size is
      // a resolution: the design is drawn in its own space and scaled on the
      // way out, so 4K is the same picture with four times the pixels. Off, it
      // is a page: the design keeps its scale and there is more room round it.
      if (document.hasCanvas)
        CanvasControlGroup(label: "Scaling", children: [
          CanvasToggle(
            key: const ValueKey("canvasScalesDesign"),
            label: "Size scales the design",
            value: document.size.scalesDesign,
            onChanged: (v) => write(document.copyWith(
                size: document.size.copyWith(scalesDesign: v))),
          ),
          const CanvasHint(
              "On, the size is a resolution: the design is drawn in its own "
              "space and scaled on the way out, so publishing larger gives the "
              "same picture with more pixels in it. Off, the size is a page: "
              "the design keeps its scale and there is more room around it."),
        ]),
      // Last, at the far end of the row: what all of the above comes to.
      _estimateGroup(context, theme, document),
    ];
  }
}

/// _SceneField is which canvas of how many, and a way to type a number and
/// go there. It says Master while the shared canvas is being edited.
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

  /// _shown is what the box last said, so the text is only replaced when the
  /// scene has changed.
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
            // Centred between the two buttons, since the box is as wide as the
            // longest reading.
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

  double _widest(TextStyle style) {
    var painter = TextPainter(
      text: TextSpan(text: "Master", style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width + 4 + 6;
  }
}

/// _ZoomField is the percentage on the band: what is on screen, and a place
/// to type what you want instead, or, dragged sideways, to scrub it (right
/// zooms in, left out). A double-click fits the canvas again, and a single
/// click opens it for typing. Still while the page is locked. Not a
/// CanvasNumberField, whose caption and box would make the band two lines.
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

  /// _shown is what the box last said, so the text is only replaced when the
  /// view has moved, not on every rebuild, which would fight somebody typing.
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

  /// _typing is whether the reading has been clicked open to type into.
  bool _typing = false;

  /// _type opens the reading for typing, and puts the caret in it once
  /// the field is there.
  void _type() {
    setState(() => _typing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  /// _scrubbing is whether the reading is being dragged.
  bool _scrubbing = false;

  /// _scrub zooms by a drag of [dx] screen pixels: a little over a
  /// doubling for every hundred and twenty.
  void _scrub(double dx) {
    var c = widget.controller;
    if (c.pageLocked) return;
    c.zoomBy(math.exp(dx * 0.006));
  }

  /// _fit puts the canvas back to the fit it was last given.
  void _fit() {
    var c = widget.controller;
    if (c.pageLocked) return;
    c.fit == CanvasFit.whole ? c.showWhole() : c.fitWidth();
  }

  /// _boxWidth is the room the widest reading takes: one size for every
  /// reading, so the box never changes width as the view moves on its own.
  /// Four eights rather than a real number, since eight is the widest digit
  /// of this face (1400% would measure narrow because of the one).
  double _boxWidth(TextStyle style) {
    var painter = TextPainter(
      text: TextSpan(text: "8888%", style: style),
      textDirection: TextDirection.ltr,
      // At the reader's text size, which is what the reading is drawn at.
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // The padding either side, and the room the caret needs at the end.
    return painter.width + 4 + 6;
  }

  @override
  Widget build(BuildContext context) {
    var at = (widget.controller.viewScale * 100).round();
    var locked = widget.controller.pageLocked;
    if (!_focus.hasFocus && at != _shown) {
      _shown = at;
      // The sign is part of the reading rather than a suffix widget, which
      // would be positioned against a box whose width depended on the number.
      _text.text = "$at%";
    }

    var type = TextStyle(
        fontSize: 12, color: widget.theme.colors.onSurfaceVariant, height: 1.1);

    // No height of its own: the field is as tall as its text and the row
    // centres it against the buttons either side (in a taller box, the
    // underline would be drawn through the digits). Not being typed into,
    // it is a reading to drag; the field takes over once clicked.
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
      // The room this reading needs, with the per cent sign pinned to the
      // right of the box. See _boxWidth.
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
            // Collapsed: no padding of its own. Dense still reserves room under
            // the text for a decoration, which lifts the digits above the buttons.
            isCollapsed: true,
            // Nothing until it is being typed into: a line under it while the
            // cursor is in it is the only moment it needs to look like a field.
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

/// _SnapButton is Snap on the band, as a split button: the switch, and an
/// arrow for what it snaps to (the page's lines on a page, the 3D steps on a
/// stage). The same switch as the one in the Grid and guides settings, which
/// the menu's last line opens.
class _SnapButton extends StatelessWidget {
  final CanvasController controller;
  final ThemeNotifier theme;

  /// onMore opens the Grid and guides settings, or is null while they are
  /// open already.
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
          tick(
              "To edges",
              guides.snapTo.edges,
              () => _set(guides.copyWith(
                  snapTo:
                      guides.snapTo.copyWith(edges: !guides.snapTo.edges)))),
          tick(
              "To centres",
              guides.snapTo.centres,
              () => _set(guides.copyWith(
                  snapTo: guides.snapTo
                      .copyWith(centres: !guides.snapTo.centres)))),
          tick(
              "To other elements",
              guides.snapTo.objects,
              () => _set(guides.copyWith(
                  snapTo: guides.snapTo
                      .copyWith(objects: !guides.snapTo.objects)))),
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
