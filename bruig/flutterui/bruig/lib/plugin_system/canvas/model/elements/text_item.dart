import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// text_item.dart is the extra pieces of writing a text element carries
// besides its own paragraph.
//
// A card is four pieces of writing in one rectangle: a number over a title,
// a line of small print under it, and a name against the right-hand edge.
// Built out of elements that was four elements and a shape to hold them, all
// of which had to be moved together, kept in step and re-made for the next
// card. Built out of one element it is one thing to place, one box to draw
// the rule down the side of, and one thing to animate.
//
// An item is not a *part*: a part is a run of the element's own sentence --
// see TextPart -- and lives inside the paragraph's own layout. An item is a
// separate string in a place of its own.

/// TextSlot is where an item sits in the box: three across by three down.
///
/// Slots rather than coordinates. A card wants its number in the top left and
/// its name against the right-hand edge, and it wants them to stay there when
/// the box is resized -- which is what a place expressed as a corner does and
/// what a pair of numbers does not.
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

  /// across and down are the slot taken apart: which edge it is held to
  /// sideways, and which one it is held to vertically.
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

/// TextItem is one of those extra pieces: what it says, how it is set, and
/// which of the nine slots it is in.
class TextItem {
  /// id is its own, and survives being edited.
  ///
  /// The canvas is where the words are typed -- click an item and type into
  /// it, the same gesture that opens the element's own paragraph -- and the
  /// editor has to know which item it is holding open across the rebuild that
  /// every keystroke causes. A position in the list would not do: moving an
  /// item would move the editor onto a different one.
  final String id;

  final String text;

  /// spec is how this piece is set. Its own from top to bottom rather than
  /// the element's with overrides: the number and the title of a card have
  /// nothing in common but the box they are in.
  ///
  /// The slot decides how it is aligned, so [TextSpec.align] and
  /// [TextSpec.verticalAlign] are not read here -- see textItemRects.
  final TextSpec spec;

  final TextSlot slot;

  /// icon is the picture this piece is, where it is a picture rather than
  /// words. Null for words, which is what most pieces are.
  ///
  /// The same thing in the same list, because a picture in a corner of a box
  /// and a word in a corner of a box are the same question: what, and where.
  /// They were two features -- an icon had a place of its own, an alignment
  /// of its own and a gap of its own, none of which was the ones the words
  /// used -- and the one that could do less had the whole section.
  final TextIcon? icon;

  /// gap is the room above this piece, in design units.
  ///
  /// What it buys is a *constant* distance. Two pieces in different slots are
  /// held to different corners of the box, so the space between them is
  /// whatever is left of the box -- which is the box's to decide, and a card
  /// made taller pulls them apart. Two pieces in the same slot are a stack:
  /// they sit one under the other in the order they were added, as far apart
  /// as their gaps say and no further, and the stack as a whole is what the
  /// slot holds to its corner.
  ///
  /// So a card whose number, title and note must keep their spacing puts all
  /// three in one slot; a card whose pieces belong in the corners puts them
  /// in three.
  final double gap;

  const TextItem({
    required this.id,
    this.text = "",
    this.spec = const TextSpec(),
    this.slot = TextSlot.topLeft,
    this.icon,
    this.gap = 0,
  });

  /// isIcon is whether this piece is a picture.
  bool get isIcon => icon != null;

  /// fresh is a new item, in [slot], set the way [like] is.
  ///
  /// Started from the element's own type rather than from nothing, because
  /// the piece being added nearly always belongs with what is already there:
  /// a caption under a headline is the headline's face, smaller and quieter.
  /// freshIcon is a new picture piece, waiting for a picture to be chosen.
  factory TextItem.freshIcon(TextSlot slot) => TextItem(
        id: newElementId(),
        slot: slot,
        icon: const TextIcon(size: 48),
      );

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
    TextSpec? spec,
    TextSlot? slot,
    TextIcon? icon,
    double? gap,
  }) =>
      TextItem(
        id: id,
        text: text ?? this.text,
        spec: spec ?? this.spec,
        slot: slot ?? this.slot,
        icon: icon ?? this.icon,
        gap: gap ?? this.gap,
      );

  /// says is what the settings panel calls this item: its own words, cut
  /// short, or the slot it is in when it has none yet.
  String get says {
    if (isIcon) return "Picture";
    var one = text.trim().split("\n").first.trim();
    if (one.isEmpty) return slot.label;
    return one.length <= 18 ? one : "${one.substring(0, 17)}…";
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        if (text.isNotEmpty) "t": text,
        "slot": slot.name,
        if (gap != 0) "gap": gap,
        if (icon != null) "icon": icon!.toJson(),
        "spec": spec.toJson(),
      };

  factory TextItem.fromJson(Map<String, dynamic> json) => TextItem(
        id: json["id"] is String && (json["id"] as String).isNotEmpty
            ? json["id"] as String
            : newElementId(),
        text: json["t"] is String ? json["t"] as String : "",
        slot: TextSlot.fromName(json["slot"] as String?),
        gap: json["gap"] is num
            ? (json["gap"] as num).toDouble().clamp(-400.0, 400.0)
            : 0,
        icon: json["icon"] is Map<String, dynamic>
            ? TextIcon.fromJson((json["icon"] as Map).cast<String, dynamic>())
            : null,
        spec: json["spec"] is Map<String, dynamic>
            ? TextSpec.fromJson((json["spec"] as Map).cast<String, dynamic>())
            : const TextSpec(),
      );
}
