import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_estimate.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/canvas_sidebar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// canvas_settings_bar.dart is the band of controls above the canvas, and the
// panel of canvas settings that drops out of it.
//
// The band is one line and always exactly one line: the two tools, the zoom,
// and the actions that must never move -- undo, redo and Publish.
//
// The canvas settings are a separate widget, CanvasSettingsPanel, and the
// screen floats it *over* the top of the canvas rather than stacking it under
// the band. That is the whole reason the two are not one widget: as a second
// row inside the band it pushed the canvas down every time it was opened, so
// the design jumped forty pixels and the zoom changed underneath whatever was
// being looked at. Floating it costs a strip of the canvas's top edge while it
// is open, which is recoverable by closing it; moving the canvas is not.
//
// The selected element's settings are the second line, behind a button, and
// the band is one line whenever that button is off -- which is how it starts
// and how it stays until somebody presses it.
//
// They were taken out of here once, on the grounds that a row that has to be
// scrolled sideways shows fewer controls than a column and that two places to
// change one thing meant neither was the obvious one. Both are still true, and
// they are not the whole story: the sidebar is also where the layer list, the
// file list and the presets are, so working in the band meant the settings
// were a panel away behind whichever of those was up. Three places, each
// remembering whether it is open, lets the reader put the settings where the
// rest of their work is rather than the other way round.
//
// This one does push the canvas down when it opens, which is exactly what the
// canvas settings panel floats to avoid. It is a second line of the band and
// was asked for as one; the difference that makes it bearable is that it is
// off unless it has been switched on, and it never switches itself on.
//
// The animation settings are absent for the same sort of reason -- the frame
// count and the frame rate live on the timeline, beside the frames they
// describe. See canvas_timeline.dart.

/// CanvasSettingsBar is the settings band.
class CanvasSettingsBar extends StatefulWidget {
  final CanvasController controller;

  /// onPublish opens the publish sheet. Held by the screen rather than here,
  /// because publishing needs the document's saved name and the image store,
  /// neither of which is the settings band's business.
  final VoidCallback onPublish;

  /// canvasSettingsOpen and onToggleCanvasSettings drive the settings panel
  /// the screen floats over the canvas. Held there rather than here because
  /// the panel is not part of this widget -- see the note at the top.
  final bool canvasSettingsOpen;
  final VoidCallback onToggleCanvasSettings;

  /// guidesOpen and onToggleGuides drive the grid and guides line, which opens
  /// in the same place and the same way.
  final bool guidesOpen;
  final VoidCallback onToggleGuides;

  /// timelineOpen and onToggleTimeline show and hide the transport and the
  /// strip under the canvas.
  ///
  /// Beside the other two, because it is the third thing on this bar that
  /// decides how much of the window the design gets: a still canvas has no
  /// use for a timeline, and forty pixels of transport under a picture nobody
  /// is animating is forty pixels of picture.
  final bool timelineOpen;
  final VoidCallback onToggleTimeline;

  /// onShowSidebar brings a hidden sidebar back, and is null while it is
  /// showing. See CanvasSidebarRestoreButton -- a hidden sidebar with no way
  /// back is a trap, so the control has to be somewhere predictable, and this
  /// band is where everything else on the page already is.
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

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Container(
      width: double.infinity,
      // No bottom padding of its own: the row below supplies its own, and
      // with both the gap under the second line came out twice the gap over
      // it.
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 0),
      decoration: BoxDecoration(
        color: theme.colors.surfaceContainerLow,
        border: Border(
            bottom: BorderSide(color: theme.colors.outlineVariant, width: 1)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          _viewControls(theme),
          const Spacer(),
          _actions(theme),
        ]),
        // The gap between the two lines is here rather than being the line's
        // own margin, so that the line is exactly what it looks like: the rule
        // and what hangs under it.
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
          // The two tools first, because which one is active changes what
          // every other gesture on the page does.
          _barButton(theme,
              icon: Icons.near_me_outlined,
              tooltip: "${CanvasTool.select.label} — "
                  "${CanvasTool.select.description}",
              active: controller.tool == CanvasTool.select,
              onPressed: () => controller.tool = CanvasTool.select),
          _barButton(theme,
              icon: Icons.pan_tool_outlined,
              tooltip:
                  "${CanvasTool.pan.label} — ${CanvasTool.pan.description}",
              active: controller.tool == CanvasTool.pan,
              onPressed: () => controller.tool = CanvasTool.pan),
          _divider(theme),
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
          // The world just outside the canvas, for building entrances and
          // exits. Beside the helpers toggle because it is the same kind of
          // thing: something shown while working that is never published.
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
          _divider(theme),
          _barButton(theme,
              icon: Icons.zoom_out,
              tooltip: "Zoom out",
              onPressed: () => controller.zoomBy(1 / 1.25)),
          _barButton(theme,
              icon: Icons.zoom_in,
              tooltip: "Zoom in",
              onPressed: () => controller.zoomBy(1.25)),
          // The two frame buttons. "All of it" means two different things
          // depending on the document's shape: a wide banner is limited by the
          // height, while a 9:16 story fitted whole is a narrow strip down the
          // middle of the window with most of the screen empty either side.
          _barButton(theme,
              icon: Icons.fit_screen_outlined,
              tooltip: CanvasFit.whole.label,
              active: controller.fit == CanvasFit.whole && controller.atFit,
              onPressed: controller.showWhole),
          _barButton(theme,
              icon: Icons.width_full,
              tooltip: "${CanvasFit.width.label} — the canvas scrolls if it "
                  "is taller than the window",
              active: controller.fit == CanvasFit.width && controller.atFit,
              onPressed: controller.fitWidth),
          // What is actually on screen: document pixels to screen pixels,
          // which is the fitted scale times the zoom. It used to be the zoom
          // alone, so it read 100% for a 4096-pixel canvas squeezed into a
          // third of a window -- a claim about the view that is plainly
          // untrue, and one that made the zoom buttons look broken as well
          // since they moved a number that had started from the wrong place.
          //
          // A field rather than a label, because the obvious thing to do with
          // a percentage is type one.
          _ZoomField(controller: controller, theme: theme),
        ],
      );

  /// _actions is the canvas settings toggle, undo, redo and Publish, pinned to
  /// the right of the band.
  ///
  /// Publish is an icon rather than a labelled button. It was a labelled one
  /// floating over the top-right corner of the canvas, where it covered the
  /// design; up here it is beside the two other things you press rather than
  /// adjust, and the tooltip carries the word.
  Widget _actions(ThemeNotifier theme) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The three that decide what the window is showing, together: the
          // timeline, the grid and the canvas settings.
          _barButton(theme,
              icon: Icons.view_timeline_outlined,
              tooltip: widget.timelineOpen
                  ? "Hide the timeline"
                  : "Show the timeline",
              active: widget.timelineOpen,
              onPressed: widget.onToggleTimeline),
          // Beside the canvas settings, because they are the same kind of
          // thing: both open a line over the top of the canvas, and both are
          // about the canvas rather than about anything on it.
          _barButton(theme,
              icon: Icons.grid_4x4,
              tooltip: "Grid, guides, rulers and snapping",
              active: widget.guidesOpen,
              onPressed: widget.onToggleGuides),
          _barButton(theme,
              icon: Icons.tune,
              tooltip: "Canvas settings",
              active: widget.canvasSettingsOpen,
              onPressed: widget.onToggleCanvasSettings),
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

  /// _barButton is a control in one of the two pinned clusters.
  ///
  /// Its own thing rather than CanvasIconButton, which carries the top padding
  /// that lines it up with a captioned control. These sit on a row with no
  /// captions at all.
  Widget _barButton(
    ThemeNotifier theme, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool active = false,
  }) =>
      Tooltip(
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
/// width, and what publishing it will cost.
///
/// Floated over the top of the canvas by the screen while the band's Canvas
/// settings button is pressed. See the note at the top of this file on why it
/// is not simply a second row of the band.
class CanvasSettingsPanel extends StatefulWidget {
  final CanvasController controller;
  const CanvasSettingsPanel({required this.controller, super.key});

  @override
  State<CanvasSettingsPanel> createState() => _CanvasSettingsPanelState();
}

class _CanvasSettingsPanelState extends State<CanvasSettingsPanel> {
  CanvasController get controller => widget.controller;

  /// _scroll is held rather than left to the scroll view, so the line keeps
  /// its position across the rebuild that happens on every keystroke in any
  /// field on it.
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Material(
      // Opaque, and with a shadow. It is sitting on top of the design rather
      // than above it, so it has to read as a thing in front rather than as
      // part of the canvas.
      color: theme.colors.surfaceContainerLow,
      elevation: 6,
      child: Container(
        width: double.infinity,
        // Tight. The strip is over the design rather than beside it, so every
        // pixel of padding is a pixel of canvas -- and with the captions
        // beside their controls there is nothing here that needs the room.
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 7),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: theme.colors.outlineVariant, width: 1)),
        ),
        // Scrolls sideways rather than wrapping. A group is a Row and a Row
        // cannot break, so one wider than the window overflows instead of
        // wrapping -- which is what the band used to do at anything under about
        // a thousand pixels.
        // No scrollbar. It is a strip two lines tall over the top of the
        // design, and a bar under the controls is a third line of furniture
        // saying something the controls already say by being cut off. The
        // wheel and a trackpad still scroll it.
        child: ScrollConfiguration(
          behavior: const _NoScrollbar(),
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 5),
            // Captions beside their controls, which is what makes this two
            // lines rather than three. See CanvasControlScope.inline.
            child: CanvasControlScope(
              maxWidth: 400,
              inline: true,
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _canvasGroups(context, theme)),
            ),
          ),
        ),
      ),
    );
  }

  /// _estimateGroup is what publishing this canvas will cost.
  ///
  /// Here rather than floating over the bottom-left corner of the canvas,
  /// where it started. It belongs with the two settings that decide it -- the
  /// ratio and the export width are the only things on this page that change
  /// it much -- and over the canvas it was a line of text permanently on top
  /// of the design.
  ///
  /// An estimate rather than a measurement, and it says so: rendering the real
  /// thing on every edit would make the editor unusable. See
  /// estimateStillBytes.
  Widget _estimateGroup(
      BuildContext context, ThemeNotifier theme, CanvasDocument document) {
    var spec = document.estimate;
    // The formats that mean anything for what this canvas is. A GIF of a
    // still is a still, and a PNG of an animation is one frame of it -- both
    // are answers to a question nobody asked.
    var offered = [
      for (var format in EstimateAs.values)
        if (format.moving == document.isAnimated) format,
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
                // error rather than tertiary: tertiary is a panel background
                // in this app, near-black in the dark theme, so this icon was
                // invisible on the band it sits in.
                child: Icon(Icons.warning_amber_rounded,
                    size: 14, color: theme.colors.error),
              ),
            ],
          ]),
        ),
      ),
      // What it is being estimated as. The same canvas is four hundred
      // kilobytes as a PNG and forty as a JPEG, so a size with no format
      // beside it is a number without a question.
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

  List<Widget> _canvasGroups(BuildContext context, ThemeNotifier theme) {
    var document = controller.document;

    /// write is an immediate change -- a dropdown -- which is its own undo
    /// step.
    void write(CanvasDocument next) => controller.apply(next);

    /// edit is a change being made continuously, by typing or dragging.
    ///
    /// It opens the undo step itself rather than leaving that to the control,
    /// because beginInteraction is idempotent and forgetting it is silent: a
    /// transient edit made outside an interaction is never pushed onto the
    /// history at all, so the control works and is simply not undoable. That is
    /// what happened to the width field until a widget test pressed undo.
    void edit(CanvasDocument next) {
      controller.beginInteraction();
      controller.apply(next, transient: true);
    }

    return [
      CanvasControlGroup(label: "Canvas", children: [
        CanvasDropdown<CanvasRatio>(
          label: "Ratio",
          value: document.size.ratio,
          width: 96,
          options: [for (var r in CanvasRatio.values) (r, r.label)],
          onChanged: (v) =>
              write(document.copyWith(size: document.size.copyWith(ratio: v))),
        ),
        // The sizes that have a name *in this shape*, beside the box that
        // takes any other number. A width on its own names nothing: 1920
        // across is 1080p at sixteen by nine and is 1920 by 2716 on an A4
        // page, so the list follows the ratio and a shape with no named sizes
        // shows no list at all.
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
              // "Custom" when the width is not one of the named ones. A list
              // that showed a name for a canvas 1337 across would be saying
              // something untrue, and the pixels are already on the readout
              // two controls along -- saying them here as well is saying them
              // twice.
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
          // No nudge. These two readouts only ever appear on the band, where
          // the captions are beside their controls and there is nothing above
          // this to line it up under -- and the group centres what is on a
          // line against the rest of it.
          padding: const EdgeInsets.only(left: 2),
          child: SizedBox(
            height: controlHeight,
            child: Center(
              child: Text(
                // The file's size. Where the design is laid out in a smaller
                // space and published larger, this is the larger number --
                // it is what somebody is choosing when they choose a size.
                "${document.size.exportWidth} × ${document.size.exportHeight}",
                style: TextStyle(
                    fontSize: 10, color: theme.colors.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ]),
      _estimateGroup(context, theme, document),
      // What changing the size does, at the end of the line: it is set once
      // and left, and it belongs after the size and the cost rather than
      // between the ratio and the width they are worked out from.
      //
      // On, the size is a resolution: the design is drawn in its own space
      // and scaled on the way out, so publishing at 4K gives the same picture
      // with four times the pixels. Off, it is a page: the design keeps its
      // scale and there is more room around it.
      CanvasControlGroup(label: "Scaling", children: [
        CanvasToggle(
          key: const ValueKey("canvasScalesDesign"),
          label: "Size scales the design",
          value: document.size.scalesDesign,
          onChanged: (v) => write(
              document.copyWith(size: document.size.copyWith(scalesDesign: v))),
        ),
        const CanvasHint(
            "On, the size is a resolution: the design is drawn in its own "
            "space and scaled on the way out, so publishing larger gives the "
            "same picture with more pixels in it. Off, the size is a page: "
            "the design keeps its scale and there is more room around it."),
      ]),
    ];
  }
}

/// _NoScrollbar is a scroll behaviour with no bar on it.
///
/// The strip over the canvas is two lines tall and scrolls sideways when the
/// window is narrow. A bar under the controls is a third line of furniture
/// saying what being cut off already says.
class _NoScrollbar extends ScrollBehavior {
  const _NoScrollbar();

  @override
  Widget buildScrollbar(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}

/// _ZoomField is the percentage on the band: what is on screen, and a place
/// to type what you want instead.
///
/// Its own small widget rather than a CanvasNumberField, which is built for a
/// settings panel and is a caption plus a bordered box tall enough to make
/// this band two lines high. The band is one line and always exactly one.
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
  /// view has actually moved. Replacing it on every rebuild would fight
  /// somebody typing into it.
  int _shown = -1;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
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
    setState(() => _shown = -1);
  }

  @override
  Widget build(BuildContext context) {
    var at = (widget.controller.viewScale * 100).round();
    if (!_focus.hasFocus && at != _shown) {
      _shown = at;
      _text.text = "$at";
    }

    var type = TextStyle(
        fontSize: 12, color: widget.theme.colors.onSurfaceVariant, height: 1.1);

    // Centred against the buttons either side of it. The box is the height
    // the field actually wants -- told to be taller and centred inside that,
    // the underline is drawn at the bottom of the input rather than the
    // bottom of the box, which put a line through the digits -- so what
    // lines it up with its neighbours is where the box sits, not where the
    // text sits inside it.
    return Center(
        child: SizedBox(
      width: 56,
      height: 24,
      child: Tooltip(
        message: "How large the canvas is drawn, as a percentage of its own "
            "pixels. Type one to go there.",
        child: TextField(
          controller: _text,
          focusNode: _focus,
          // Right, so the number always sits the same distance from the per
          // cent sign after it. Centred, the gap between them was whatever
          // was left over -- wide at 100 and narrow at 1000.
          textAlign: TextAlign.right,
          style: type,
          decoration: InputDecoration(
            isDense: true,
            // Nothing until it is being typed into. A box on the band that
            // looks like a field all the time is a fourth kind of control on
            // a strip of buttons; a line under it while the cursor is in it
            // is the only moment the difference matters.
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: UnderlineInputBorder(
                borderSide:
                    BorderSide(color: widget.theme.colors.primary, width: 1)),
            suffixText: "%",
            suffixStyle: type,
            // Room under the digits for the line to sit in, and the same
            // above so the text is in the middle of its own box.
            contentPadding: const EdgeInsets.fromLTRB(2, 3, 2, 3),
          ),
          onSubmitted: (_) => _commit(),
        ),
      ),
    ));
  }
}
