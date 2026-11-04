import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

/// ButtonActionKind is what pressing a button does.
///
/// Everything here stays inside the canvas, for safety: a published canvas
/// runs inside a chat message or a page, and a button that could run, read
/// or call anything outside it would make opening one a risk. The only way
/// out is a link the viewer is asked to confirm.
enum ButtonActionKind {
  goToFrame("Go to frame", "Jump the playhead and hold there"),
  playFrom("Play from frame", "Jump there and start playing"),
  playToFrame("Play to frame", "Play forward and stop on that frame"),
  play("Play", "Start playing from where the playhead is"),
  pause("Pause", "Stop the playhead where it is"),
  togglePlay("Play or pause", "Start playing, or stop where it is"),
  restart("Restart", "Go back to the first frame and play"),
  toggleElement("Show or hide", "Flip another element's visibility"),
  goToScene("Go to a scene", "Show another canvas of this document"),
  openLink("Open a link", "Ask to open a URL in the browser"),

  // An Audio or Video element on the canvas, named by its id, so it has one
  // set of settings wherever it is started from. "Sound" in the saved names
  // covers video too.
  playSound("Play a sound or video", "Start an audio or video element"),
  pauseSound("Pause a sound or video", "Hold it where it is"),
  toggleSound(
      "Play or pause a sound or video", "Start it, or hold it if it is going"),
  stopSound("Stop a sound or video", "Stop it and go back to its start"),
  muteSound("Mute or unmute a sound or video", "Silence it, or bring it back");

  final String label;
  final String description;
  const ButtonActionKind(this.label, this.description);

  static ButtonActionKind fromName(String? name) => values.firstWhere(
        (k) => k.name == name,
        orElse: () => ButtonActionKind.goToFrame,
      );

  bool get needsFrame =>
      this == goToFrame || this == playFrom || this == playToFrame;
  bool get needsElement => this == toggleElement || needsSound;

  /// needsSound is whether the element named has to be an Audio or Video
  /// element.
  bool get needsSound =>
      this == playSound ||
      this == pauseSound ||
      this == toggleSound ||
      this == stopSound ||
      this == muteSound;

  /// needsScene is whether the action names a scene of this document, by id
  /// or name rather than by position, so reordering does not change it.
  bool get needsScene => this == goToScene;
  bool get needsUrl => this == openLink;
}

/// ButtonAction is one action, fully specified.
class ButtonAction {
  final ButtonActionKind kind;
  final int frame;

  /// elementId is the element an element or sound action targets, or the
  /// scene of [ButtonActionKind.goToScene] (an id or a name). One that no
  /// longer names anything makes a button that does nothing.
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
        if (kind.needsElement || kind.needsScene) "element": elementId,
        if (kind.needsUrl) "url": url,
      };

  factory ButtonAction.fromJson(Map<String, dynamic> json) => ButtonAction(
        kind: ButtonActionKind.fromName(jsonStr(json["kind"])),
        frame: jsonInt(json["frame"], 0),
        elementId: jsonString(json["element"], ""),
        url: jsonString(json["url"], ""),
      );
}

/// ButtonElement is a labelled rectangle that does something when pressed.
/// Inert in an exported picture or video; only a published interactive
/// canvas can be pressed.
class ButtonElement extends CanvasElement {
  final String label;
  final TextSpec textSpec;
  final BoxSpec box;

  /// hoverFill and hoverTextColor are what the button becomes under the
  /// pointer. Transparent means no change.
  final Color hoverFill;
  final Color hoverTextColor;

  final ButtonAction action;

  /// animation is how it arrives and leaves, like any other thing in a box.
  final ElementAnimation animation;

  const ButtonElement(
    super.base, {
    this.label = "Button",
    this.textSpec = const TextSpec(fontSize: 20, weight: 600),
    this.box =
        const BoxSpec(fill: Color(0xFF3D7EFF), borderRadius: 8, padding: 12),
    this.hoverFill = const Color(0x00000000),
    this.hoverTextColor = const Color(0x00000000),
    this.action = const ButtonAction(),
    this.animation = const ElementAnimation(),
  });

  @override
  ElementKind get kind => ElementKind.button;

  /// assetIds is the picture its box is painted with, where it has one. See
  /// BoxSpec.assetIds -- left out, the sweep takes the picture away.
  @override
  Set<String> get assetIds => box.assetIds;

  @override
  CanvasElement rebase(ElementBase base) => ButtonElement(base,
      label: label,
      textSpec: textSpec,
      box: box,
      hoverFill: hoverFill,
      hoverTextColor: hoverTextColor,
      action: action,
      animation: animation);

  ButtonElement copyWith({
    String? label,
    TextSpec? textSpec,
    BoxSpec? box,
    Color? hoverFill,
    Color? hoverTextColor,
    ButtonAction? action,
    ElementAnimation? animation,
  }) =>
      ButtonElement(base,
          label: label ?? this.label,
          textSpec: textSpec ?? this.textSpec,
          box: box ?? this.box,
          hoverFill: hoverFill ?? this.hoverFill,
          hoverTextColor: hoverTextColor ?? this.hoverTextColor,
          action: action ?? this.action,
          animation: animation ?? this.animation);

  @override
  Map<String, dynamic> props() => {
        "label": label,
        "textSpec": textSpec.toJson(),
        "box": box.toJson(),
        if (hoverFill.a > 0) "hoverFill": colorToJson(hoverFill),
        if (hoverTextColor.a > 0) "hoverText": colorToJson(hoverTextColor),
        "action": action.toJson(),
        if (animation.any) "anim": animation.toJson(),
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
              json["action"], ButtonAction.fromJson, const ButtonAction()),
          animation: jsonSpec(json["anim"], ElementAnimation.fromJson,
              const ElementAnimation()));
}
