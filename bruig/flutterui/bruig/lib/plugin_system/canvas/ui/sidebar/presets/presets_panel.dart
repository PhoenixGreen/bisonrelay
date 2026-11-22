import 'package:flutter/material.dart';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/vector_brush.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer/device_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/pitch_views.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/presets/canvas_preset_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/presets/preset_lists.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/presets/preset_row.dart';
import 'package:bruig/theming_system/theme_manager.dart';

// presets_panel.dart is the Presets panel of the sidebar: every kind of
// preset in one list, narrowed by chips and a search. Canvases
// (canvas_preset_cards.dart), scenes and elements (preset_lists.dart), then
// pitch views, text styles, pictures' actions, brushes and sound devices,
// which are for what is picked: with nothing such picked, using one says
// what to pick.

/// _Filter is one of the chips along the top.
enum _Filter {
  all("All"),
  canvas("Canvas"),
  scene("Scene"),
  element("Element"),
  football("Football"),
  text("Text"),
  looks("Actions"),
  brushes("Brushes"),
  sound("Sound");

  final String label;
  const _Filter(this.label);
}

/// _footballCanvases are the built-in canvases the Football chip shows.
const _footballCanvases = {"football"};

/// CanvasPresetsPanel is the Presets panel's body.
class CanvasPresetsPanel extends StatefulWidget {
  final CanvasController controller;

  /// onChoose starts a new document from a canvas preset; what to do about
  /// unsaved work is the screen's decision.
  final ValueChanged<CanvasDocument> onChoose;

  const CanvasPresetsPanel(
      {required this.controller, required this.onChoose, super.key});

  /// forgetForTest puts the chips back on All, as a new run has them.
  @visibleForTesting
  static void forgetForTest() => _CanvasPresetsPanelState._kept = _Filter.all;

  @override
  State<CanvasPresetsPanel> createState() => _CanvasPresetsPanelState();
}

class _CanvasPresetsPanelState extends State<CanvasPresetsPanel> {
  /// _kept is the chip pressed, kept for the run of the app.
  static _Filter _kept = _Filter.all;
  _Filter _filter = _kept;
  final TextEditingController _search = TextEditingController();

  CanvasController get controller => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _pick(_Filter f) => setState(() => _filter = _kept = f);

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var query = _search.text;
    bool shows(_Filter f) => _filter == _Filter.all || _filter == f;
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: CanvasSubHeading(text),
        );
    var football = _filter == _Filter.football;
    return ListView(
      key: const ValueKey("presetsLibrary"),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
      children: [
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (var f in _Filter.values)
            ChoiceChip(
              key: ValueKey("presetFilter-${f.name}"),
              label: Text(f.label, style: const TextStyle(fontSize: 11)),
              selected: _filter == f,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              showCheckmark: false,
              onSelected: (_) => _pick(f),
            ),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 32,
          child: TextField(
            key: const ValueKey("presetSearch"),
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              hintText: "Find a preset",
              prefixIcon: const Icon(Icons.search, size: 16),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 30, minHeight: 30),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: colors.outlineVariant)),
            ),
          ),
        ),
        if (shows(_Filter.canvas) || football) ...[
          heading(football ? "Canvases" : "Canvas"),
          CanvasPresetCards(
            controller: controller,
            onChoose: widget.onChoose,
            query: query,
            only: football ? _footballCanvases : null,
          ),
        ],
        if (shows(_Filter.scene)) ...[
          heading("Scene"),
          ScenePresetList(controller: controller, query: query),
        ],
        if (shows(_Filter.element) || football) ...[
          heading(football ? "Teams" : "Element"),
          ElementPresetList(
            controller: controller,
            query: query,
            kinds: football ? const {ElementKind.player} : null,
          ),
        ],
        if (shows(_Filter.football)) ...[
          heading("Pitch views"),
          _PitchViews(controller: controller, query: query),
        ],
        if (shows(_Filter.text)) ...[
          heading("Text styles"),
          _TextStyles(controller: controller, query: query),
        ],
        if (shows(_Filter.looks)) ...[
          heading("Actions"),
          _Looks(controller: controller, query: query),
        ],
        if (shows(_Filter.brushes)) ...[
          heading("Brushes"),
          _Brushes(controller: controller, query: query),
        ],
        if (shows(_Filter.sound)) ...[
          heading("Devices and chains"),
          _SoundPresets(controller: controller, query: query),
        ],
      ],
    );
  }
}

/// _needs says, as a use is refused, what has to be picked first.
void _needs(BuildContext context, String what) =>
    SnackBarModel.of(context).error(what);

/// _PitchViews are the pitch's saved views: used, the canvas is seen so.
class _PitchViews extends StatelessWidget {
  final CanvasController controller;
  final String query;
  const _PitchViews({required this.controller, required this.query});

  @override
  Widget build(BuildContext context) => StorePresetList(
        store: SavedPresetStore.pitchViews,
        query: query,
        icon: Icons.videocam_outlined,
        empty: "A view is saved from a pitch's Camera settings.",
        onUse: (context, p) {
          var background = controller.document.background;
          if (background.spec.style != ProceduralStyle.pitch) {
            _needs(context, "A pitch view needs a pitch behind the canvas.");
            return;
          }
          controller.setBackground(background.copyWith(
              spec: withPitchCamera(background.spec, {
            for (var k in pitchCameraKeys)
              if (p.data[k] is num) k: (p.data[k] as num).toDouble(),
          })));
        },
      );
}

/// _TextStyles are the document's own text styles: used, the text takes it.
class _TextStyles extends StatelessWidget {
  final CanvasController controller;
  final String query;
  const _TextStyles({required this.controller, required this.query});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          var styles = [
            for (var t in controller.textStyles)
              if (presetMatches(t.name, query)) t
          ];
          if (styles.isEmpty) {
            return query.isEmpty
                ? const CanvasHint("A style is kept from a text's Presets "
                    "line, for every text in this document.")
                : const SizedBox.shrink();
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var t in styles)
                  PresetRow(
                    key: ValueKey("textStyle:${t.name}"),
                    name: t.name,
                    icon: Icons.text_fields,
                    onUse: () {
                      var e = controller.selected;
                      if (e is! TextElement) {
                        _needs(context, "Pick a text to set it in a style.");
                        return;
                      }
                      controller.useTextStyle(e.id, t.name);
                    },
                  ),
              ]);
        },
      );
}

/// _Looks are the pictures' saved actions: used, the steps are added to
/// the picture.
class _Looks extends StatelessWidget {
  final CanvasController controller;
  final String query;
  const _Looks({required this.controller, required this.query});

  @override
  Widget build(BuildContext context) => StorePresetList(
        store: SavedPresetStore.looks,
        query: query,
        icon: Icons.auto_fix_high_outlined,
        empty: "An action is kept from a picture's Actions.",
        onUse: (context, p) {
          var e = controller.selected;
          if (e is! ImageElement) {
            _needs(context, "Pick a picture to do an action to.");
            return;
          }
          controller.changeImage(withLookApplied(e, p.data, replace: false));
        },
      );
}

/// _SoundPresets are the sound devices and chains kept with "Save as a
/// preset": used, they go on the end of the chain the Chain shows.
class _SoundPresets extends StatelessWidget {
  final CanvasController controller;
  final String query;
  const _SoundPresets({required this.controller, required this.query});

  @override
  Widget build(BuildContext context) => StorePresetList(
        store: devicePresets,
        query: query,
        icon: Icons.tune,
        empty: "A device or a chain is kept from its ⋯ in the Chain: "
            "Save as a preset.",
        onUse: (context, p) {
          var owner = controller.chainShowsMotion || !controller.effectsOpen
              ? null
              : controller.effectsOf ?? controller.effectsChannel;
          if (owner == null) {
            _needs(context, "Open a channel's Chain to add it to.");
            return;
          }
          if (!useDevicePreset(controller, owner, p.data)) {
            _needs(context, "Nothing in it goes on that chain.");
          }
        },
      );
}

/// _Brushes are the drawing and paint brushes: used, it is in hand.
class _Brushes extends StatefulWidget {
  final CanvasController controller;
  final String query;
  const _Brushes({required this.controller, required this.query});

  @override
  State<_Brushes> createState() => _BrushesState();
}

class _BrushesState extends State<_Brushes> {
  CanvasController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    SavedPresetStore.brushes.load();
    SavedPresetStore.paintBrushes.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge(
            [SavedPresetStore.brushes, SavedPresetStore.paintBrushes]),
        builder: (context, _) {
          var q = widget.query;
          var drawing = [
            for (var b in builtInBrushes)
              if (presetMatches(b.name, q)) (b.name, b, null as String?),
            for (var p in SavedPresetStore.brushes.presets)
              if (presetMatches(p.name, q))
                (
                  p.name,
                  VectorBrush.fromJson(p.data).copyWith(name: p.name),
                  p.id
                ),
          ];
          var paint = [
            for (var b in brushPresets)
              if (presetMatches(b.name, q)) b,
            for (var p in SavedPresetStore.paintBrushes.presets)
              if (presetMatches(p.name, q))
                BrushPreset.fromJson(p.id, p.name, p.data),
          ];
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var (name, brush, id) in drawing)
                  PresetRow(
                    key: ValueKey("drawingBrush:${id ?? name}"),
                    name: name,
                    icon: Icons.draw_outlined,
                    says: "Drawing",
                    onUse: () => controller.vectorBrush = brush,
                  ),
                for (var b in paint)
                  PresetRow(
                    key: ValueKey("paintBrushPreset:${b.id}"),
                    name: b.name,
                    icon: Icons.brush_outlined,
                    says: "Paint",
                    onUse: () => controller.useBrush(b),
                  ),
              ]);
        },
      );
}
