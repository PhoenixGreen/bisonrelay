import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character_appearance_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character_hair_settings.dart';
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
        _LayerList(
          key: const ValueKey("characterLayerList"),
          rows: rows,
          hidden: hidden,
          picked: picked,
          solo: solo,
          onPick: (key) => controller.pickCharacterLayer(picked == key ? null : key),
          onShow: (key, shown) {
            begin();
            write(e.withLayerShown(key, shown));
            commit();
          },
          onSolo: (key) => controller.soloLayer(e.id, key),
        ),
        if (pickedRow != null) ...[
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
        ] else
          const CanvasHint(
              "Pick a layer to shape it here. The eye shows or hides it; S solos it, "
              "drawing everything else faint behind it."),
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

class _LayerList extends StatelessWidget {
  final List<LayerRow> rows;
  final Set<String> hidden;
  final String? picked;
  final String? solo;
  final ValueChanged<String> onPick;
  final void Function(String key, bool shown) onShow;
  final ValueChanged<String> onSolo;
  const _LayerList(
      {required this.rows,
      required this.hidden,
      required this.picked,
      required this.solo,
      required this.onPick,
      required this.onShow,
      required this.onSolo,
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
