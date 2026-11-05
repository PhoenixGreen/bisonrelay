import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/vector_brush.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/pitch_views.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/preset_panels.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/preset_row.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/presets_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// presets_library.dart is the Presets panel: every kind of preset in one
// list, narrowed by the chips along its top and a search -- canvases to
// start from, scenes and elements to add, the pitch's saved views, the
// document's text styles, the pictures' looks and the brushes. Those last
// four are for what is picked: a text takes a style, a picture a look; with
// nothing of the kind picked, using one says what to pick.

/// PresetFilter is one of the chips along the top.
enum PresetFilter {
  all("All"),
  canvas("Canvas"),
  scene("Scene"),
  element("Element"),
  football("Football"),
  text("Text"),
  looks("Looks"),
  brushes("Brushes");

  final String label;
  const PresetFilter(this.label);
}

/// footballCanvases are the built-in canvases the Football chip shows.
const footballCanvases = {"football"};

/// CanvasPresetsLibrary is the Presets panel: see the top of the file.
class CanvasPresetsLibrary extends StatefulWidget {
  final CanvasController controller;

  /// onChoose starts a new document from a canvas preset. What to do about
  /// unsaved work is the screen's decision.
  final void Function(CanvasPreset? preset, CanvasDocument document) onChoose;

  const CanvasPresetsLibrary(
      {required this.controller, required this.onChoose, super.key});

  @override
  State<CanvasPresetsLibrary> createState() => _CanvasPresetsLibraryState();
}

class _CanvasPresetsLibraryState extends State<CanvasPresetsLibrary> {
  /// _filter is the chip pressed, kept for the session.
  static PresetFilter _kept = PresetFilter.all;
  PresetFilter _filter = _kept;
  final TextEditingController _search = TextEditingController();

  CanvasController get controller => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _pick(PresetFilter f) => setState(() => _filter = _kept = f);

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var query = _search.text;
    bool shows(PresetFilter f) => _filter == PresetFilter.all || _filter == f;
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: CanvasSubHeading(text),
        );
    var football = _filter == PresetFilter.football;
    return ListView(
      key: const ValueKey("presetsLibrary"),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
      children: [
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (var f in PresetFilter.values)
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
        if (shows(PresetFilter.canvas) || football) ...[
          heading(football ? "Canvases" : "Canvas"),
          CanvasPresetsPanel(
            controller: controller,
            onChoose: widget.onChoose,
            query: query,
            embedded: true,
            only: football ? footballCanvases : null,
          ),
        ],
        if (shows(PresetFilter.scene)) ...[
          heading("Scene"),
          ScenePresetsPanel(
              controller: controller, query: query, embedded: true),
        ],
        if (shows(PresetFilter.element) || football) ...[
          heading(football ? "Teams" : "Element"),
          ElementPresetsPanel(
            controller: controller,
            query: query,
            embedded: true,
            kinds: football ? const {ElementKind.player} : null,
          ),
        ],
        if (shows(PresetFilter.football)) ...[
          heading("Pitch views"),
          _PitchViews(controller: controller, query: query),
        ],
        if (shows(PresetFilter.text)) ...[
          heading("Text styles"),
          _TextStyles(controller: controller, query: query),
        ],
        if (shows(PresetFilter.looks)) ...[
          heading("Looks"),
          _Looks(controller: controller, query: query),
        ],
        if (shows(PresetFilter.brushes)) ...[
          heading("Brushes"),
          _Brushes(controller: controller, query: query),
        ],
      ],
    );
  }
}

/// _needs says, as a use is refused, what has to be picked first.
void _needs(BuildContext context, String what) =>
    SnackBarModel.of(context).error(what);

/// _StoreList is a saved-preset store's presets as rows, kept up as it
/// changes.
class _StoreList extends StatefulWidget {
  final SavedPresetStore store;
  final String query;
  final IconData icon;
  final String empty;
  final void Function(BuildContext context, SavedPresetRef preset) onUse;
  const _StoreList(
      {required this.store,
      required this.query,
      required this.icon,
      required this.empty,
      required this.onUse});

  @override
  State<_StoreList> createState() => _StoreListState();
}

/// SavedPresetRef is a saved preset as a row uses it.
typedef SavedPresetRef = ({String id, String name, Map<String, dynamic> data});

class _StoreListState extends State<_StoreList> {
  @override
  void initState() {
    super.initState();
    widget.store.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          var shown = [
            for (var p in widget.store.presets)
              if (presetMatches(p.name, widget.query)) p
          ];
          if (shown.isEmpty) {
            return widget.query.isEmpty
                ? CanvasHint(widget.empty)
                : const SizedBox.shrink();
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var p in shown)
                  PresetRow(
                    key: ValueKey("savedPreset:${p.id}"),
                    name: p.name,
                    icon: widget.icon,
                    onUse: () => widget
                        .onUse(context, (id: p.id, name: p.name, data: p.data)),
                    onRename: (name) => widget.store.rename(p, name),
                    onDelete: () => widget.store.remove(p),
                  ),
              ]);
        },
      );
}

/// _PitchViews are the pitch's saved views: used, the pitch behind the
/// canvas is seen through it.
class _PitchViews extends StatelessWidget {
  final CanvasController controller;
  final String query;
  const _PitchViews({required this.controller, required this.query});

  @override
  Widget build(BuildContext context) => _StoreList(
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

/// _TextStyles are the document's own text styles: used, the text picked is
/// set in it.
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

/// _Looks are the pictures' saved looks: used, the picture being worked on
/// wears it.
class _Looks extends StatelessWidget {
  final CanvasController controller;
  final String query;
  const _Looks({required this.controller, required this.query});

  @override
  Widget build(BuildContext context) => _StoreList(
        store: SavedPresetStore.looks,
        query: query,
        icon: Icons.auto_fix_high_outlined,
        empty: "A look is kept from a picture's Colour settings.",
        onUse: (context, p) {
          var e = controller.selected;
          if (e is! ImageElement) {
            _needs(context, "Pick a picture to wear a look.");
            return;
          }
          controller.changeImage(withLookApplied(e, p.data));
        },
      );
}

/// _Brushes are the drawing brushes and the paint brushes, the ones that
/// come with the canvas and the saved ones: used, it is the brush in hand.
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
