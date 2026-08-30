import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

/// TextElement is a paragraph in a box.
///
/// Everything about how the letters look is in [textSpec]; everything about
/// the box around them is in [box]. This class is only the string and the
/// wiring, which is why it is short and why adding a type control means
/// touching TextSpec rather than touching every element that draws words.
class TextElement extends CanvasElement {
  final String text;
  final TextSpec textSpec;
  final BoxSpec box;

  /// autoSize grows the type to fill the box rather than wrapping it.
  ///
  /// What a title wants and what a paragraph does not, so it is a switch
  /// rather than a mode: a headline should get bigger when its box does,
  /// while body copy should reflow.
  final bool autoSize;

  const TextElement(
    super.base, {
    this.text = "Text",
    this.textSpec = const TextSpec(),
    this.box = const BoxSpec(),
    this.autoSize = false,
  });

  @override
  ElementKind get kind => ElementKind.text;

  /// displayText is what actually goes on the canvas -- the typed string with
  /// the case transform applied. See TextCase on why the transform is not
  /// baked into [text].
  String get displayText => textSpec.textCase.apply(text);

  @override
  CanvasElement rebase(ElementBase base) => TextElement(base,
      text: text, textSpec: textSpec, box: box, autoSize: autoSize);

  TextElement copyWith({
    String? text,
    TextSpec? textSpec,
    BoxSpec? box,
    bool? autoSize,
  }) =>
      TextElement(base,
          text: text ?? this.text,
          textSpec: textSpec ?? this.textSpec,
          box: box ?? this.box,
          autoSize: autoSize ?? this.autoSize);

  @override
  Map<String, dynamic> props() => {
        "text": text,
        "textSpec": textSpec.toJson(),
        "box": box.toJson(),
        if (autoSize) "autoSize": true,
      };

  factory TextElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      TextElement(b,
          text: jsonString(json["text"], "Text"),
          textSpec: jsonSpec(json["textSpec"], TextSpec.fromJson,
              const TextSpec()),
          box: jsonSpec(json["box"], BoxSpec.fromJson, const BoxSpec()),
          autoSize: jsonBool(json["autoSize"], false));
}
