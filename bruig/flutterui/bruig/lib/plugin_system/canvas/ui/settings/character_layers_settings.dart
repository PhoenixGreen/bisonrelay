import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character_drawing_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character_appearance_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character_hair_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character_hands_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// character_layers_settings.dart is a sketched character's Layers: every
// part of its hair, face and body and every garment it wears, top first,
// each to show or hide, solo, and pick -- and, under the list, the picked
// layer's own settings: the sliders that shape it, or the garment's. See
// character_layers.dart for how each is drawn as a layer of its own.

/// LayerRow is one layer in the list.
class LayerRow {
  final String key;
  final String label;
  final LayerGroup group;
  const LayerRow(this.key, this.label, this.group);
}

/// layerRows is [e]'s layers, as the list shows them: the hair, the face,
/// the body, then what it wears, outermost first.
List<LayerRow> layerRows(CharacterElement e) {
  var dna = e.dna;
  var extras = dna.tail != TailKind.none ||
      dna.wings != WingKind.none ||
      dna.horns != HornKind.none ||
      dna.spikes;
  var worn = dna.worn;
  return [
    for (var l in BodyLayer.values)
      if (l != BodyLayer.extras || extras) LayerRow(l.name, l.label, l.group),
    for (var i = dna.wardrobe.length - 1; i >= 0; i--)
      if (worn.contains(dna.wardrobe[i]))
        LayerRow(garmentLayer(i), dna.wardrobe[i].title, LayerGroup.clothing),
  ]..sort((a, b) => a.group.index.compareTo(b.group.index));
}

/// appearanceOf is the parts of the Appearance editor that shape body
/// layer [l]: its own, and the skin with the head and the body, and the
/// beard with the head.
List<AppearanceGroup> appearanceOf(BodyLayer l, {bool person = true}) => switch (l) {
      BodyLayer.hairFront || BodyLayer.hairBack => [AppearanceGroup.hair],
      BodyLayer.brows => [AppearanceGroup.brows],
      BodyLayer.eyes => [AppearanceGroup.eyes],
      BodyLayer.nose => [AppearanceGroup.nose],
      BodyLayer.mouth => [AppearanceGroup.mouth],
      BodyLayer.head => [
          AppearanceGroup.head,
          AppearanceGroup.skin,
          if (person) AppearanceGroup.facialHair,
        ],
      BodyLayer.ears => [AppearanceGroup.ears],
      BodyLayer.torso => [AppearanceGroup.body, AppearanceGroup.skin],
      _ => [AppearanceGroup.body],
    };

Widget characterLayersSection(BuildContext context, CanvasController controller,
    CharacterElement e, SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var rows = layerRows(e);
  var hidden = e.layerView().hidden;
  var picked = controller.pickedCharacterLayer;
  if (picked != null && !rows.any((r) => r.key == picked)) picked = null;
  var solo = controller.soloLayerOf(e.id);
  var pickedRow = rows.where((r) => r.key == picked).firstOrNull;
  return section(e, "layers",
      icon: Icons.layers_outlined,
      title: "Layers",
      summary: [
        "${rows.length} layers",
        if (hidden.isNotEmpty) "${hidden.length} hidden",
        if (solo != null) "${rows.where((r) => r.key == solo).firstOrNull?.label ?? solo} soloed",
      ].join(" · "),
      initiallyOpen: true,
      children: [
        _viewStrip(controller, e, write, begin, commit),
        _LayerList(
          key: const ValueKey("characterLayerList"),
          rows: rows,
          hidden: hidden,
          picked: picked,
          solo: solo,
          drawingOn: controller.drawingOn == e.id
              ? (controller.drawingLayer ??
                  (controller.drawingGarment == null
                      ? null
                      : garmentLayer(controller.drawingGarment!)))
              : null,
          onPick: (key) => controller.pickCharacterLayer(picked == key ? null : key),
          onShow: (key, shown) {
            begin();
            write(e.withLayerShown(key, shown));
            commit();
          },
          onSolo: (key) => controller.soloLayer(e.id, key),
          onDraw: (key) {
            // Drawing on it already: done. Otherwise, taken apart on this
            // view -- its own shapes, to edit -- and the tools on it.
            if (controller.drawingOn == e.id &&
                (controller.drawingLayer == key ||
                    (controller.drawingGarment != null &&
                        garmentLayer(controller.drawingGarment!) == key))) {
              controller.stopDrawingOnCharacter();
              return;
            }
            controller.pickCharacterLayer(key);
            if (!controller.layerTakenApart(e.id, key)) {
              controller.takeApartCharacterLayer(e.id, key);
            }
            controller.drawOnCharacter(e.id, layer: key);
          },
          detail: pickedRow == null
              ? null
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _onThisView(controller, e, pickedRow),
          if (BodyLayer.fromName(pickedRow.key) case var body?
              when controller.layerTakenApart(e.id, pickedRow.key))
            _keyforms(controller, e, pickedRow, body),
          // The hair, as strokes or as its style draws it.
          if (pickedRow.key == BodyLayer.hairFront.name ||
              pickedRow.key == BodyLayer.hairBack.name)
            HairStrokesEditor(
              key: ValueKey("characterHairStrokes-${e.id}"),
              controller: controller,
              character: e,
              write: write,
              commit: commit,
            ),
          // A person's hands and feet: their shape and stance.
          if (BodyLayer.fromName(pickedRow.key) case var body?
              when _hands(e) &&
                  (body == BodyLayer.handL || body == BodyLayer.handR))
            handEditor(controller, e, write, commit, body == BodyLayer.handL),
          if (BodyLayer.fromName(pickedRow.key) case var body?
              when _feet(e) &&
                  (body == BodyLayer.footL || body == BodyLayer.footR))
            footEditor(controller, e, write, commit, body == BodyLayer.footL),
          if (BodyLayer.fromName(pickedRow.key) case var body?)
            for (var group in appearanceOf(body, person: e.dna.kind.person))
              AppearanceEditor(
                key: ValueKey("characterLayerLook-${e.id}-${body.name}"
                    "${group == appearanceOf(body).first ? "" : "-${group.name}"}"),
                controller: controller,
                character: e,
                write: write,
                commit: commit,
                only: group,
                keyed: {
                  if (keysOf(e, pickedRow.key, controller.frame,
                          controller.document.frameRate)
                      case var k?)
                    if (Look.fromName(k.look) case var l?) l,
                },
              )
          else if (garmentOfLayer(pickedRow.key) case var i?)
            GarmentEditor(
              key: ValueKey("characterLayerGarment-${e.id}-$i"),
              controller: controller,
              character: e,
              index: i,
              write: write,
              commit: commit,
            ),
              ]),
        ),
        if (pickedRow == null)
          const CanvasHint(
              "Pick a layer to shape it: its settings open under it. The eye "
              "shows or hides it; the pencil edits it with the drawing tools; "
              "S solos it, drawing everything else faint behind it."),
        // Clothes put on as layers of their own.
        WardrobeAdder(
          key: ValueKey("characterLayerAdd-${e.id}"),
          controller: controller,
          character: e,
          write: write,
          commit: commit,
        ),
      ]);
}

/// _viewStrip is the character from each of its views, side by side --
/// what a change to a layer does on every one of them -- the view it is
/// seen from lit, and a tap on another showing that one.
Widget _viewStrip(CanvasController controller, CharacterElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var frame = controller.frame;
  var now = e.viewKey(e.inView(e.poseAtFrame(frame)));
  var views = panelOptions(e, adding: false);
  return CanvasTiles<String>(
    key: const ValueKey("characterViewStrip"),
    label: "Views",
    help: "The character from each of its views, as it is drawn there: what "
        "changing a layer does on every one. Pick one to see it from there "
        "on the canvas -- and to draw on it.",
    scrolls: true,
    tileWidth: 64,
    previewHeight: 96,
    tiles: [
      for (var (key, label) in views)
        CanvasTile(key, label.split(" · ").first,
            drawnFrom: "${identityHashCode(e)}|$key|$frame",
            paint: (canvas, size) {
              var shown = showPanel(controller, e, key);
              var b = e.bounds;
              var k = math.min(size.width / b.width, size.height / b.height);
              canvas.translate((size.width - b.width * k) / 2, (size.height - b.height * k) / 2);
              canvas.scale(k);
              canvas.translate(-b.left, -b.top);
              paintElement(canvas, shown, frame);
            }),
    ],
    selected: (key) => key == now,
    keyOf: (key) => "characterView-$key",
    onPick: (key) {
      begin();
      write(showPanel(controller, e, key));
      commit();
    },
  );
}

/// _hands and _feet are whether [e] has hands with fingers, and feet that
/// stand: not paws, wings or fins.
bool _hands(CharacterElement e) =>
    !e.dna.species.animal && !e.dna.fourLegs && !e.dna.species.legless;
bool _feet(CharacterElement e) =>
    !e.dna.species.legless && !e.dna.fourLegs && e.dna.species != Species.bird;

class _LayerList extends StatelessWidget {
  final List<LayerRow> rows;
  final Set<String> hidden;
  final String? picked;
  final String? solo;
  final ValueChanged<String> onPick;
  final void Function(String key, bool shown) onShow;
  final ValueChanged<String> onSolo;

  /// drawingOn is the layer being edited with the drawing tools, and onDraw
  /// what its pencil does.
  final String? drawingOn;
  final ValueChanged<String> onDraw;

  /// detail is the picked layer's settings, opened under it.
  final Widget? detail;
  const _LayerList(
      {required this.rows,
      required this.hidden,
      required this.picked,
      required this.solo,
      required this.onPick,
      required this.onShow,
      required this.onSolo,
      required this.onDraw,
      this.drawingOn,
      this.detail,
      super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var c = theme.colors;
    var children = <Widget>[];
    LayerGroup? group;
    for (var r in rows) {
      if (r.group != group) {
        group = r.group;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
          child: Text(group.label.toUpperCase(),
              style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                  color: c.onSurfaceVariant)),
        ));
      }
      var shown = !hidden.contains(r.key);
      var on = r.key == picked;
      var soloed = r.key == solo;
      children.add(Material(
        type: MaterialType.transparency,
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: on ? c.secondaryContainer : null,
          ),
          child: Row(children: [
            IconButton(
              key: ValueKey("layerEye-${r.key}"),
              tooltip: shown ? "Hide ${r.label}" : "Show ${r.label}",
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              onPressed: () => onShow(r.key, !shown),
              icon: Icon(shown ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: c.onSurfaceVariant),
            ),
            Expanded(
              child: InkWell(
                key: ValueKey("layer-${r.key}"),
                borderRadius: BorderRadius.circular(6),
                onTap: () => onPick(r.key),
                child: Container(
                  height: 34,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(r.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          color: shown
                              ? (on ? c.onSecondaryContainer : c.onSurface)
                              : c.onSurfaceVariant)),
                ),
              ),
            ),
            IconButton(
              key: ValueKey("layerDraw-${r.key}"),
              tooltip: drawingOn == r.key
                  ? "Stop editing ${r.label}"
                  : "Edit ${r.label} with the drawing tools",
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              onPressed: () => onDraw(r.key),
              icon: Icon(drawingOn == r.key ? Icons.edit : Icons.edit_outlined,
                  color: drawingOn == r.key ? c.primary : c.onSurfaceVariant),
            ),
            Tooltip(
              message: soloed ? "Stop soloing" : "Solo ${r.label}",
              child: InkWell(
                key: ValueKey("layerSolo-${r.key}"),
                borderRadius: BorderRadius.circular(6),
                onTap: () => onSolo(r.key),
                child: Container(
                  width: 26,
                  height: 24,
                  margin: const EdgeInsets.only(right: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: soloed ? c.primary : c.outlineVariant),
                    color: soloed ? c.primary.withValues(alpha: 0.16) : null,
                  ),
                  child: Text("S",
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: soloed ? c.primary : c.onSurfaceVariant)),
                ),
              ),
            ),
          ]),
        ),
      ));
      // The picked layer's settings, right under it.
      if (on && detail != null) {
        children.add(Container(
          key: ValueKey("layerDetail-${r.key}"),
          margin: const EdgeInsets.fromLTRB(10, 2, 0, 8),
          padding: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: c.primary.withValues(alpha: 0.5), width: 2)),
          ),
          child: detail,
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// _onThisView is the picked layer on the panel seen where the playhead is:
/// drawn as it is made, or by its own shapes -- and the way to draw on it,
/// take it apart there, or put it back.
Widget _onThisView(CanvasController controller, CharacterElement e, LayerRow row) {
  var pose = e.inView(e.poseAtFrame(controller.frame));
  var apart = controller.layerTakenApart(e.id, row.key);
  var drawing = controller.drawingOn == e.id &&
      (controller.drawingLayer == row.key ||
          (controller.drawingGarment != null &&
              garmentLayer(controller.drawingGarment!) == row.key));
  return CanvasControlGroup(
      key: const ValueKey("characterLayerView"),
      label: "${row.label} on this view",
      help: "Seen from the ${viewLabel(pose.panelTurn, pose.panelTilt).toLowerCase()}. "
          "Take it apart to edit its outline point by point here: the "
          "other views, and the rest of the figure, stay as they are made. "
          "Draw on it to add shapes that go with it.",
      children: [
        CanvasStatus(apart
            ? "Drawn by its own shapes on this view. Its sliders change the other views."
            : "Drawn from its sliders on this view."),
        CanvasTextButton(
          key: const ValueKey("characterLayerDraw"),
          label: drawing ? "Stop drawing on it" : "Draw on it",
          icon: Icons.draw_outlined,
          primary: drawing,
          onPressed: () => drawing
              ? controller.stopDrawingOnCharacter()
              : controller.drawOnCharacter(e.id, layer: row.key),
        ),
        apart
            ? CanvasTextButton(
                key: const ValueKey("characterLayerPutBack"),
                label: "Put it back here",
                icon: Icons.restart_alt,
                onPressed: () => controller.putCharacterLayerBack(e.id, row.key),
              )
            : CanvasTextButton(
                key: const ValueKey("characterLayerTakeApart"),
                label: "Take it apart here",
                icon: Icons.scatter_plot_outlined,
                onPressed: () => controller.takeApartCharacterLayer(e.id, row.key),
              ),
      ]);
}

/// _keyforms is the picked layer -- taken apart on this view -- shaped by a
/// slider through drawings kept at its values: which slider, the keyforms,
/// and keeping another where the slider is now. See LayerKeys.
Widget _keyforms(CanvasController controller, CharacterElement e, LayerRow row, BodyLayer body) {
  var keys = keysOf(e, row.key, controller.frame, controller.document.frameRate);
  var looks = [
    for (var g in appearanceOf(body, person: e.dna.kind.person)) ...Look.inGroup(g),
  ];
  var look = keys == null ? null : Look.fromName(keys.look);
  var value = look == null ? 0.0 : e.dna.look[look];
  var onKey = keys != null && keys.keyAt(value) >= 0;
  String pc(double v) => "${(v * 100).round()}%";
  return CanvasControlGroup(
      key: const ValueKey("characterLayerKeys"),
      label: "Keyforms",
      help: "Shape this layer by one of its sliders through your own drawings: "
          "keep a keyform at a value, move the slider, keep another, and draw "
          "each as it should look. In between, the drawings blend point by "
          "point; past the first or last, they hold. With the slider on a "
          "keyform, drawing on the layer changes it; anywhere else, drawing "
          "keeps a new one there.",
      children: [
        CanvasDropdown<Look?>(
          key: const ValueKey("characterLayerKeyLook"),
          label: "Shaped by",
          value: look,
          options: [
            (null, "No slider"),
            for (var l in looks) (l, l.label),
          ],
          onChanged: (l) => controller.keyCharacterLayer(e.id, row.key, l?.name),
        ),
        if (keys != null) ...[
          for (var (v, _) in keys.keys) ...[
            const CanvasLineBreak(),
            CanvasTextButton(
              key: ValueKey("characterLayerKey-${pc(v)}"),
              label: "${(v - value).abs() < 0.005 ? "◆ " : ""}At ${pc(v)}",
              primary: (v - value).abs() < 0.005,
              onPressed: () => controller.goToKeyform(e.id, keys.look, v),
            ),
            CanvasIconButton(
              key: ValueKey("characterLayerKeyOff-${pc(v)}"),
              icon: Icons.close,
              tooltip: "Remove this keyform",
              onPressed: () => controller.removeKeyform(e.id, row.key, v),
            ),
          ],
          const CanvasLineBreak(),
          CanvasTextButton(
            key: const ValueKey("characterLayerKeyAdd"),
            label: onKey ? "A keyform is here" : "Keep a keyform at ${pc(value)}",
            icon: Icons.add,
            onPressed: onKey ? null : () => controller.addKeyform(e.id, row.key),
          ),
        ],
      ]);
}
