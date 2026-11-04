import 'dart:convert';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// text_item.dart is the extra pieces (items) a text element carries besides
// its own paragraph: words or pictures held to a slot of its box, so a card's
// number, title and small print are one element.
//
// An item is not a *part*: a part (TextPart) is a run of the element's own
// sentence inside the paragraph's layout; an item is a separate string or
// picture in a place of its own.

/// TextSlot is where an item sits in the box: three across by three down.
/// Slots rather than coordinates, so items stay held to their edge when the
/// box is resized.
enum TextSlot {
  topLeft("Top left"),
  topCentre("Top centre"),
  topRight("Top right"),
  middleLeft("Middle left"),
  middleCentre("Middle"),
  middleRight("Middle right"),
  bottomLeft("Bottom left"),
  bottomCentre("Bottom centre"),
  bottomRight("Bottom right");

  final String label;
  const TextSlot(this.label);

  static TextSlot fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => TextSlot.topLeft);

  /// across and down are the slot's horizontal and vertical alignment.
  TextAlignSpec get across => switch (this) {
        TextSlot.topLeft ||
        TextSlot.middleLeft ||
        TextSlot.bottomLeft =>
          TextAlignSpec.left,
        TextSlot.topCentre ||
        TextSlot.middleCentre ||
        TextSlot.bottomCentre =>
          TextAlignSpec.center,
        _ => TextAlignSpec.right,
      };

  VerticalAlignSpec get down => switch (this) {
        TextSlot.topLeft ||
        TextSlot.topCentre ||
        TextSlot.topRight =>
          VerticalAlignSpec.top,
        TextSlot.middleLeft ||
        TextSlot.middleCentre ||
        TextSlot.middleRight =>
          VerticalAlignSpec.middle,
        _ => VerticalAlignSpec.bottom,
      };
}

/// _plainBox is an item's box as it is when nothing has been set.
final String _plainBox = jsonEncode(const BoxSpec(padding: 0).toJson());

/// TextItem is one extra piece of a text element: what it says (or the
/// picture it is), how it is set, and which of the nine slots it is in.
class TextItem {
  /// id is its own and survives edits, so the on-canvas editor keeps hold of
  /// the right item across rebuilds and reorders.
  final String id;

  final String text;

  /// name is what the panel calls this piece, where somebody has named it;
  /// otherwise the row shows what it says (see [says]).
  final String name;

  /// spec is how this piece is set: its own, not the element's with
  /// overrides. The slot decides alignment, so [TextSpec.align] and
  /// [TextSpec.verticalAlign] are not read here -- see textItemRects.
  final TextSpec spec;

  final TextSlot slot;

  /// icon is the picture this piece is, or null for words.
  final TextIcon? icon;

  /// gap is the room, in design units, between this piece and what is before
  /// it: the piece before it in its slot's stack, or for the first piece the
  /// box edge the slot holds it to (the top edge for a top slot, the bottom
  /// for a bottom one).
  ///
  /// Pieces in one slot are a stack in the order added, kept exactly their
  /// gaps apart however the box is resized; pieces in different slots move
  /// apart as the box grows.
  final double gap;

  /// box is what is drawn behind this piece (see BoxSpec). The default is
  /// transparent with no padding, so it takes exactly the room its words do.
  final BoxSpec box;

  /// side is the room this piece keeps from the edge its slot holds it to
  /// sideways: rightwards for a left or middle slot, leftwards for a right
  /// one. Negative moves it the other way.
  final double side;

  /// hidden leaves the piece out of the drawing while it keeps its place:
  /// the pieces after it in its slot do not move up.
  final bool hidden;

  /// locked is a piece the canvas will not open for typing.
  final bool locked;

  const TextItem({
    required this.id,
    this.text = "",
    this.name = "",
    this.spec = const TextSpec(),
    this.slot = TextSlot.topLeft,
    this.icon,
    this.box = const BoxSpec(padding: 0),
    this.gap = 0,
    this.side = 0,
    this.hidden = false,
    this.locked = false,
  });

  /// isIcon is whether this piece is a picture.
  bool get isIcon => icon != null;

  /// freshIcon is a new picture piece, waiting for a picture to be chosen.
  factory TextItem.freshIcon(TextSlot slot) => TextItem(
        id: newElementId(),
        slot: slot,
        icon: const TextIcon(size: 48),
      );

  /// fresh is a new item in [slot], in [like]'s face at a smaller, regular
  /// weight, since an added piece usually belongs with the element's type.
  factory TextItem.fresh(TextSlot slot, TextSpec like) => TextItem(
        id: newElementId(),
        text: "Text",
        slot: slot,
        spec: like.copyWith(
          fontSize: (like.fontSize * 0.55).clamp(8.0, 400.0),
          weight: 400,
        ),
      );

  TextItem copyWith({
    String? text,
    String? name,
    TextSpec? spec,
    TextSlot? slot,
    TextIcon? icon,
    BoxSpec? box,
    double? gap,
    double? side,
    bool? hidden,
    bool? locked,
  }) =>
      TextItem(
        id: id,
        text: text ?? this.text,
        name: name ?? this.name,
        spec: spec ?? this.spec,
        slot: slot ?? this.slot,
        icon: icon ?? this.icon,
        box: box ?? this.box,
        gap: gap ?? this.gap,
        side: side ?? this.side,
        hidden: hidden ?? this.hidden,
        locked: locked ?? this.locked,
      );

  /// scaledBy is this piece at [by] times the size: its type, picture, box
  /// and spacing. The slot and text are unchanged.
  TextItem scaledBy(double by) => copyWith(
        spec: spec.scaledBy(by),
        icon: icon?.copyWith(
            size: icon!.size * by, outlineWidth: icon!.outlineWidth * by),
        box: box.scaledBy(by),
        gap: gap * by,
        side: side * by,
      );

  /// says is what the settings panel calls this item: its name, "Picture",
  /// its first line cut short, or its slot when it has no words yet.
  String get says {
    if (name.trim().isNotEmpty) return name.trim();
    if (isIcon) return "Picture";
    var one = text.trim().split("\n").first.trim();
    if (one.isEmpty) return slot.label;
    return one.length <= 18 ? one : "${one.substring(0, 17)}…";
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        if (text.isNotEmpty) "t": text,
        if (name.isNotEmpty) "name": name,
        "slot": slot.name,
        if (gap != 0) "gap": gap,
        if (side != 0) "side": side,
        if (icon != null) "icon": icon!.toJson(),
        if (jsonEncode(box.toJson()) != _plainBox) "box": box.toJson(),
        "spec": spec.toJson(),
        if (hidden) "hid": true,
        if (locked) "lock": true,
      };

  factory TextItem.fromJson(Map<String, dynamic> json) => TextItem(
        id: json["id"] is String && (json["id"] as String).isNotEmpty
            ? json["id"] as String
            : newElementId(),
        text: json["t"] is String ? json["t"] as String : "",
        name: json["name"] is String ? json["name"] as String : "",
        slot: TextSlot.fromName(jsonStr(json["slot"])),
        gap: json["gap"] is num
            ? (json["gap"] as num).toDouble().clamp(-400.0, 400.0)
            : 0,
        // gapL and gapR are older keys for the same room.
        side: _side(json["side"]) ??
            _side(json["gapL"]) ??
            _side(json["gapR"]) ??
            0,
        box: json["box"] is Map<String, dynamic>
            ? BoxSpec.fromJson((json["box"] as Map).cast<String, dynamic>())
            : const BoxSpec(padding: 0),
        icon: json["icon"] is Map<String, dynamic>
            ? TextIcon.fromJson((json["icon"] as Map).cast<String, dynamic>())
            : null,
        spec: json["spec"] is Map<String, dynamic>
            ? TextSpec.fromJson((json["spec"] as Map).cast<String, dynamic>())
            : const TextSpec(),
        hidden: json["hid"] == true,
        locked: json["lock"] == true,
      );
}

/// _side reads one side's own room, or null where it has none.
double? _side(Object? raw) =>
    raw is num ? raw.toDouble().clamp(-400.0, 400.0) : null;
