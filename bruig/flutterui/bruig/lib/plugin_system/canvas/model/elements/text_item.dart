import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
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
        TextSlot.topLeft || TextSlot.middleLeft || TextSlot.bottomLeft =>
          TextAlignSpec.left,
        TextSlot.topCentre || TextSlot.middleCentre || TextSlot.bottomCentre =>
          TextAlignSpec.center,
        _ => TextAlignSpec.right,
      };

  VerticalAlignSpec get down => switch (this) {
        TextSlot.topLeft || TextSlot.topCentre || TextSlot.topRight =>
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

  const TextItem({
    required this.id,
    this.text = "",
    this.spec = const TextSpec(),
    this.slot = TextSlot.topLeft,
  });

  /// fresh is a new item, in [slot], set the way [like] is.
  ///
  /// Started from the element's own type rather than from nothing, because
  /// the piece being added nearly always belongs with what is already there:
  /// a caption under a headline is the headline's face, smaller and quieter.
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
  }) =>
      TextItem(
        id: id,
        text: text ?? this.text,
        spec: spec ?? this.spec,
        slot: slot ?? this.slot,
      );

  /// says is what the settings panel calls this item: its own words, cut
  /// short, or the slot it is in when it has none yet.
  String get says {
    var one = text.trim().split("\n").first.trim();
    if (one.isEmpty) return slot.label;
    return one.length <= 18 ? one : "${one.substring(0, 17)}…";
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        if (text.isNotEmpty) "t": text,
        "slot": slot.name,
        "spec": spec.toJson(),
      };

  factory TextItem.fromJson(Map<String, dynamic> json) => TextItem(
        id: json["id"] is String && (json["id"] as String).isNotEmpty
            ? json["id"] as String
            : newElementId(),
        text: json["t"] is String ? json["t"] as String : "",
        slot: TextSlot.fromName(json["slot"] as String?),
        spec: json["spec"] is Map<String, dynamic>
            ? TextSpec.fromJson((json["spec"] as Map).cast<String, dynamic>())
            : const TextSpec(),
      );
}
