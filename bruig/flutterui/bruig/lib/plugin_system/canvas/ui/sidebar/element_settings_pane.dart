import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// element_settings_pane.dart is the settings of whatever is selected, and the
// collapsible section that carries them.
//
// Lifted out of layers_panel.dart, which is where they started and where they
// were the only copy. One tab is not enough places for them: the Design
// Elements tab is where an element is added, and the first thing anybody does
// after adding one is change it, which meant a trip to another tab and back
// for every element on the canvas. So both sidebar tabs have them, and so does
// the band above the canvas.
//
// Three places, and each remembers its own open state and its own height. That
// is the point rather than an accident of the implementation: somebody working
// in the band wants the sidebar's copy shut so the layer list has the room,
// and somebody working in the sidebar wants the band back to one line.
//
// Nothing here ever opens itself. A section that was closed stays closed when
// an element is selected or added -- closing it is an instruction about the
// shape of the page, and a panel that reappears because something was clicked
// is a panel that has to be closed again and again.

/// elementSettingsBody is the settings for the current selection.
///
/// The four cases are a real selection, the canvas background, more than one
/// element, and nothing -- and the last two say what to do rather than
/// showing an empty space, because an empty space reads as broken.
/// [stacked] lays the controls down a column, which is what a sidebar wants.
/// False puts them along a row, for the band above the canvas.
///
/// [explainEmpty] says what to do with nothing selected. The band says so in
/// words, because its line is there whether anything is selected or not and an
/// empty strip reads as broken. The sidebar does not: the same sentence lives
/// on the question mark beside the section's own name, where it is read once
/// rather than sitting in the column for ever.
Widget elementSettingsBody(BuildContext context, CanvasController controller,
    {bool stacked = true, bool explainEmpty = true}) {
  var selected = controller.selected;

  if (controller.backgroundSelected) {
    return ProceduralSettings(
      spec: controller.document.background.spec,
      label: "Background",
      onBegin: controller.beginInteraction,
      onCommit: controller.endInteraction,
      onChanged: (spec) {
        controller.beginInteraction();
        controller.apply(
            controller.document.copyWith(
                background: controller.document.background.copyWith(spec: spec)),
            transient: true);
      },
    );
  }

  if (selected != null) {
    var controls = elementSettings(context, controller, selected);
    return stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CanvasSectionHeading(selected.name),
              ...controls,
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: controls,
          );
  }

  if (controller.selection.length > 1) {
    return Txt.S("${controller.selection.length} elements selected. "
        "Choose one to change its settings.");
  }

  return explainEmpty
      ? const Txt.S(elementSettingsHint)
      : const SizedBox.shrink();
}

/// elementSettingsHint is what this section is for, in one sentence. Shown in
/// the band and, in the sidebar, on the question mark beside its name.
const String elementSettingsHint =
    "Choose a layer to change its settings, or the background at the bottom "
    "of the list to change the whole canvas.";

/// CanvasSectionHeading is a small capitalised label above a group of things,
/// with an optional question mark beside it explaining what they are.
class CanvasSectionHeading extends StatelessWidget {
  final String text;
  final String? hint;
  const CanvasSectionHeading(this.text, {this.hint, super.key});

  @override
  Widget build(BuildContext context) {
    var label = Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
        color: ThemeNotifier.of(context)
            .colors
            .onSurfaceVariant
            .withValues(alpha: 0.75),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: hint == null
          ? label
          : Row(mainAxisSize: MainAxisSize.min, children: [
              label,
              CanvasHint(hint!),
            ]),
    );
  }
}

/// CanvasSettingsSplit is [top] with a collapsible settings section under it.
///
/// The bar between them is both the handle that opens the section and, while
/// it is open, the grip that decides how the height is shared. Two jobs on one
/// strip because there is only room for one strip, and they are the same
/// question asked twice: how much of this panel is settings.
class CanvasSettingsSplit extends StatefulWidget {
  final CanvasController controller;
  final Widget top;

  /// storageKey names where this section's own open state and height are
  /// remembered. Each place that shows the settings passes a different one --
  /// that is what makes the three independent of each other.
  final String storageKey;

  /// initialSplit is the fraction of the height [top] gets before anybody has
  /// dragged the grip.
  final double initialSplit;

  /// maxControlWidth caps one control, so a wide one shrinks rather than
  /// overflowing the column it is in.
  final double maxControlWidth;

  const CanvasSettingsSplit({
    required this.controller,
    required this.top,
    required this.storageKey,
    this.initialSplit = 0.55,
    this.maxControlWidth = 240,
    super.key,
  });

  @override
  State<CanvasSettingsSplit> createState() => _CanvasSettingsSplitState();
}

class _CanvasSettingsSplitState extends State<CanvasSettingsSplit> {
  /// _minSection keeps either half from being dragged away entirely. A divider
  /// that can be pushed to the edge is a divider that can be lost.
  static const double _minSection = 90;
  static const double _dividerHeight = 11;

  double _split = 0.55;
  bool _open = true;

  String get _splitKey => "${widget.storageKey}Split";
  String get _openKey => "${widget.storageKey}Open";

  @override
  void initState() {
    super.initState();
    _split = widget.initialSplit;
    _restore();
  }

  Future<void> _restore() async {
    var split = await StorageManager.readData(_splitKey);
    var open = await StorageManager.readData(_openKey);
    if (!mounted) return;
    setState(() {
      if (split is num) _split = split.toDouble().clamp(0.1, 0.9);
      if (open is bool) _open = open;
    });
  }

  void _toggle() {
    setState(() => _open = !_open);
    StorageManager.saveData(_openKey, _open);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            var height = constraints.maxHeight;
            var handle = _handle();

            // Closed, or with too little room to split. Two sections too short
            // to show anything are worse than one that works, and the handle
            // stays either way -- a section with no way back is a trap.
            if (!_open || height < _minSection * 2 + _dividerHeight * 2) {
              return Column(children: [
                Expanded(child: widget.top),
                handle,
                if (_open) Expanded(child: _settings()),
              ]);
            }

            var topHeight = (height * _split).clamp(
                _minSection, height - _minSection - _dividerHeight * 2);
            return Column(children: [
              SizedBox(height: topHeight, child: widget.top),
              _grip(height),
              handle,
              Expanded(child: _settings()),
            ]);
          },
        ),
      );

  /// _handle opens and closes the section, and says what it is when it is
  /// closed -- which is the state in which a bare chevron means nothing.
  Widget _handle() {
    var theme = ThemeNotifier.of(context);
    return InkWell(
      onTap: _toggle,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.4),
          border: Border(
            top: BorderSide(color: theme.colors.outlineVariant),
            bottom: BorderSide(
                color: _open ? theme.colors.outlineVariant : Colors.transparent),
          ),
        ),
        child: Row(children: [
          Icon(_open ? Icons.expand_more : Icons.expand_less,
              size: 16, color: theme.colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            "Element settings",
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
              color: theme.colors.onSurfaceVariant,
            ),
          ),
          const CanvasHint(elementSettingsHint),
        ]),
      ),
    );
  }

  /// _grip decides how the height is shared. Only while the section is open:
  /// with it closed there is nothing to share.
  Widget _grip(double panelHeight) {
    var theme = ThemeNotifier.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Vertical drag rather than a pan, so a slightly diagonal drag still
        // moves the divider instead of being claimed by the list's scroll.
        onVerticalDragUpdate: (details) {
          if (panelHeight <= 0) return;
          setState(() => _split =
              (_split + details.delta.dy / panelHeight).clamp(0.1, 0.9));
        },
        onVerticalDragEnd: (_) => StorageManager.saveData(_splitKey, _split),
        child: SizedBox(
          height: _dividerHeight,
          child: Center(
            child: Container(
              height: 3,
              width: 34,
              decoration: BoxDecoration(
                color: theme.colors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _settings() => CanvasControlScope(
        stacked: true,
        maxWidth: widget.maxControlWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          children: [
            elementSettingsBody(context, widget.controller,
                explainEmpty: false),
          ],
        ),
      );
}
