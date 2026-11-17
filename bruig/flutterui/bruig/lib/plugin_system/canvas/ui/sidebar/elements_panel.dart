import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// elements_panel.dart is what can be put on a canvas: a grid of chips, each
// clicked to add one mid-page, or dragged to add it where it is dropped.

/// _addable is the kinds offered, most wanted first, not enum order.
const List<ElementKind> _addable = [
  ElementKind.text,
  ElementKind.shape,
  ElementKind.image,
  ElementKind.vector,
  ElementKind.line,
  // The Data element: a sheet as a table, switched to a chart in settings.
  ElementKind.table,
  ElementKind.button,
  ElementKind.counter,
  ElementKind.audio,
  ElementKind.sheet,
  ElementKind.metronome,
  ElementKind.video,
  ElementKind.background,
  ElementKind.player,
  // A character to animate and dress (in the Character Studio), and a 3D
  // object, its model then chosen from the library's 3D objects.
  ElementKind.character3d,
  ElementKind.object3d,
  ElementKind.path,
  ElementKind.sprite,
  ElementKind.tileMap,
  ElementKind.camera,
  // No 3D stage: that is a background kind (BackdropKind).
];

IconData iconForKind(ElementKind kind) => switch (kind) {
      ElementKind.text => Icons.title,
      ElementKind.image => Icons.image_outlined,
      ElementKind.vector => Icons.draw_outlined,
      ElementKind.shape => Icons.category_outlined,
      ElementKind.line => Icons.timeline,
      ElementKind.chart => Icons.bar_chart,
      ElementKind.table => Icons.table_chart_outlined,
      ElementKind.button => Icons.smart_button_outlined,
      ElementKind.counter => Icons.timer_outlined,
      ElementKind.audio => Icons.volume_up_outlined,
      ElementKind.video => Icons.smart_display_outlined,
      ElementKind.background => Icons.blur_on,
      ElementKind.player => Icons.person_pin_circle_outlined,
      ElementKind.path => Icons.gesture,
      ElementKind.character3d => Icons.view_in_ar_outlined,
      ElementKind.stage => Icons.view_in_ar_outlined,
      ElementKind.sprite => Icons.directions_run,
      ElementKind.tileMap => Icons.grid_view,
      ElementKind.parallax => Icons.landscape_outlined,
      ElementKind.sheet => Icons.queue_music,
      ElementKind.camera => Icons.videocam_outlined,
      ElementKind.object3d => Icons.view_in_ar,
      ElementKind.synth => Icons.cable,
      ElementKind.synthTask => Icons.checklist,
      ElementKind.metronome => Icons.av_timer,
      ElementKind.code => Icons.code,
      ElementKind.codeRun => Icons.play_circle_outline,
      ElementKind.codeTask => Icons.fact_check_outlined,
    };

class CanvasElementsPanel extends StatelessWidget {
  final CanvasController controller;
  const CanvasElementsPanel({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var kind in _addable) ...[
                _AddChip(controller, kind),
                // An instrument is an Audio element, after the speaker.
                if (kind == ElementKind.audio) _AddInstrument(controller),
                // A synth of modules to patch, after the instruments.
                if (kind == ElementKind.audio) _AddSynth(controller),
                // A Code panel and its Run panel, after the metronome.
                if (kind == ElementKind.metronome) _AddCode(controller),
              ],
            ],
          ),
        ],
      );
}

class _AddChip extends StatelessWidget {
  final CanvasController controller;
  final ElementKind kind;

  const _AddChip(this.controller, this.kind);

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var body = Container(
      width: 76,
      // At least this tall, taller with larger text, so two lines fit.
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colors.outlineVariant),
        color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
        Icon(kind == ElementKind.table ? Icons.dataset_outlined : iconForKind(kind),
            size: 20, color: theme.colors.onSurfaceVariant),
        const SizedBox(height: 4),
        Text(
          kind == ElementKind.table ? "Data" : kind.label,
          style: TextStyle(fontSize: 10, color: theme.colors.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ]),
    );

    // No hover text: the chip's own icon and name say what it adds.
    return Draggable<ElementKind>(
      data: kind,
      // The same chip under the pointer, faded, to show what is carried.
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.8, child: body),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: body),
      child: Material(
        // Its own Material inside the list: the sidebar's would let the
        // highlight spill over other sections and stay put on scroll.
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () =>
              controller.addElement(newElement(kind, controller.document)),
          child: body,
        ),
      ),
    );
  }
}

/// _AddInstrument adds an instrument: keys to play, a part on the timeline.
class _AddInstrument extends StatelessWidget {
  final CanvasController controller;
  const _AddInstrument(this.controller);

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const ValueKey("addInstrument"),
        borderRadius: BorderRadius.circular(8),
        onTap: () =>
            controller.addElement(newInstrument(controller.document)),
        child: Container(
          width: 76,
          constraints: const BoxConstraints(minHeight: 62),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colors.outlineVariant),
            color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            Icon(Icons.piano, size: 20, color: theme.colors.onSurfaceVariant),
            const SizedBox(height: 4),
            Text("Instrument",
                style: TextStyle(
                    fontSize: 10, color: theme.colors.onSurfaceVariant),
                textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}

/// _AddSynth is the chip that puts down a synth: a rack of modules, ready
/// to patch, its speaker on a channel of its own.
class _AddSynth extends StatelessWidget {
  final CanvasController controller;
  const _AddSynth(this.controller);

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const ValueKey("addSynth"),
        borderRadius: BorderRadius.circular(8),
        onTap: () => controller.addSynthRack(),
        child: Container(
          width: 76,
          constraints: const BoxConstraints(minHeight: 62),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colors.outlineVariant),
            color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cable,
                    size: 20, color: theme.colors.onSurfaceVariant),
                const SizedBox(height: 4),
                Text("Synth",
                    style: TextStyle(
                        fontSize: 10, color: theme.colors.onSurfaceVariant),
                    textAlign: TextAlign.center),
              ]),
        ),
      ),
    );
  }
}


/// _AddCode is the chip that puts down a Code panel (an empty web page, kind
/// and examples in its settings) and the Run panel beside it that runs it.
class _AddCode extends StatelessWidget {
  final CanvasController controller;
  const _AddCode(this.controller);

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const ValueKey("addCode"),
        borderRadius: BorderRadius.circular(8),
        onTap: () => controller.addCodeLesson(),
        child: Container(
          width: 76,
          constraints: const BoxConstraints(minHeight: 62),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colors.outlineVariant),
            color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.code,
                    size: 20, color: theme.colors.onSurfaceVariant),
                const SizedBox(height: 4),
                Text("Code",
                    style: TextStyle(
                        fontSize: 10, color: theme.colors.onSurfaceVariant),
                    textAlign: TextAlign.center),
              ]),
        ),
      ),
    );
  }
}
