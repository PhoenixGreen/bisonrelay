import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

/// ButtonActionKind is what pressing a button does.
///
/// Everything here is about the canvas itself. A published interactive canvas
/// runs inside a chat message or a page, and a button that could reach outside
/// it -- run something, read something, call something -- would make opening
/// somebody's canvas a risk. So the whole vocabulary is: move the playhead,
/// show or hide something, and one deliberately-confirmed link.
enum ButtonActionKind {
  goToFrame("Go to frame", "Jump the playhead and hold there"),
  playFrom("Play from frame", "Jump there and start playing"),
  playToFrame("Play to frame", "Play forward and stop on that frame"),
  play("Play", "Start playing from where the playhead is"),
  pause("Pause", "Stop the playhead where it is"),
  restart("Restart", "Go back to the first frame and play"),
  toggleElement("Show or hide", "Flip another element's visibility"),
  openLink("Open a link", "Ask to open a URL in the browser");

  final String label;
  final String description;
  const ButtonActionKind(this.label, this.description);

  static ButtonActionKind fromName(String? name) => values.firstWhere(
        (k) => k.name == name,
        orElse: () => ButtonActionKind.goToFrame,
      );

  bool get needsFrame =>
      this == goToFrame || this == playFrom || this == playToFrame;
  bool get needsElement => this == toggleElement;
  bool get needsUrl => this == openLink;
}

/// ButtonAction is one action, fully specified.
class ButtonAction {
  final ButtonActionKind kind;
  final int frame;

  /// elementId is the target of [ButtonActionKind.toggleElement]. An id that
  /// no longer names anything is simply a button that does nothing, which is
  /// what deleting the thing it pointed at should leave behind.
  final String elementId;

  final String url;

  const ButtonAction({
    this.kind = ButtonActionKind.goToFrame,
    this.frame = 0,
    this.elementId = "",
    this.url = "",
  });

  ButtonAction copyWith({
    ButtonActionKind? kind,
    int? frame,
    String? elementId,
    String? url,
  }) =>
      ButtonAction(
        kind: kind ?? this.kind,
        frame: frame ?? this.frame,
        elementId: elementId ?? this.elementId,
        url: url ?? this.url,
      );

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        if (kind.needsFrame) "frame": frame,
        if (kind.needsElement) "element": elementId,
        if (kind.needsUrl) "url": url,
      };

  factory ButtonAction.fromJson(Map<String, dynamic> json) => ButtonAction(
        kind: ButtonActionKind.fromName(json["kind"] as String?),
        frame: jsonInt(json["frame"], 0),
        elementId: jsonString(json["element"], ""),
        url: jsonString(json["url"], ""),
      );
}

/// ButtonElement is a labelled rectangle that does something when pressed.
///
/// It is drawn like every other element and is inert in an exported PNG or
/// GIF -- there is nothing to press in a picture. It is the reason to publish
/// a canvas as an interactive canvas rather than as an image, and the settings
/// bar says so when a button is added to a document nobody has published that
/// way.
class ButtonElement extends CanvasElement {
  final String label;
  final TextSpec textSpec;
  final BoxSpec box;

  /// hoverFill and hoverTextColor are what the button becomes under the
  /// pointer. Transparent means "no change", so a button with no hover styling
  /// costs nothing and still works.
  final Color hoverFill;
  final Color hoverTextColor;

  final ButtonAction action;

  const ButtonElement(
    super.base, {
    this.label = "Button",
    this.textSpec = const TextSpec(fontSize: 20, weight: 600),
    this.box =
        const BoxSpec(fill: Color(0xFF3D7EFF), borderRadius: 8, padding: 12),
    this.hoverFill = const Color(0x00000000),
    this.hoverTextColor = const Color(0x00000000),
    this.action = const ButtonAction(),
  });

  @override
  ElementKind get kind => ElementKind.button;

  @override
  CanvasElement rebase(ElementBase base) => ButtonElement(base,
      label: label,
      textSpec: textSpec,
      box: box,
      hoverFill: hoverFill,
      hoverTextColor: hoverTextColor,
      action: action);

  ButtonElement copyWith({
    String? label,
    TextSpec? textSpec,
    BoxSpec? box,
    Color? hoverFill,
    Color? hoverTextColor,
    ButtonAction? action,
  }) =>
      ButtonElement(base,
          label: label ?? this.label,
          textSpec: textSpec ?? this.textSpec,
          box: box ?? this.box,
          hoverFill: hoverFill ?? this.hoverFill,
          hoverTextColor: hoverTextColor ?? this.hoverTextColor,
          action: action ?? this.action);

  @override
  Map<String, dynamic> props() => {
        "label": label,
        "textSpec": textSpec.toJson(),
        "box": box.toJson(),
        if (hoverFill.a > 0) "hoverFill": colorToJson(hoverFill),
        if (hoverTextColor.a > 0) "hoverText": colorToJson(hoverTextColor),
        "action": action.toJson(),
      };

  factory ButtonElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      ButtonElement(b,
          label: jsonString(json["label"], "Button"),
          textSpec: jsonSpec(json["textSpec"], TextSpec.fromJson,
              const TextSpec(fontSize: 20, weight: 600)),
          box: jsonSpec(
              json["box"],
              BoxSpec.fromJson,
              const BoxSpec(
                  fill: Color(0xFF3D7EFF), borderRadius: 8, padding: 12)),
          hoverFill: colorFromJson(json["hoverFill"], const Color(0x00000000)),
          hoverTextColor:
              colorFromJson(json["hoverText"], const Color(0x00000000)),
          action: jsonSpec(
              json["action"], ButtonAction.fromJson, const ButtonAction()));
}
