import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_limits.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

/// ButtonActionKind is what pressing a button does. Everything stays inside
/// the canvas: a published canvas runs in a chat message or a page, and a
/// button that could run, read or call anything outside it would make
/// opening one a risk. The only way out is a link the viewer confirms.
///
/// The editor and a published book each carry out these actions in their
/// own code: what each does, and where the two still differ, is one table
/// at the head of ui/controller/button_actions.dart.
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

  // An Audio or Video element by id, one set of settings however it
  // is started. "Sound" in saved names covers video too.
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

  /// needsSound is whether the element named must be an Audio or Video.
  bool get needsSound =>
      this == playSound ||
      this == pauseSound ||
      this == toggleSound ||
      this == stopSound ||
      this == muteSound;

  /// needsScene is whether the action names a scene, by id or name rather
  /// than position, so reordering does not change it.
  bool get needsScene => this == goToScene;
  bool get needsUrl => this == openLink;
}

/// ButtonAction is one action, fully specified.
class ButtonAction {
  final ButtonActionKind kind;
  final int frame;

  /// elementId is what the action is done to, saved as "element" whatever it
  /// names: an element's id for showing, hiding or a sound; but for
  /// [ButtonActionKind.goToScene] not an element at all, a scene, by its id
  /// or its name, which CanvasDocument.sceneIndexNamed finds either way (by
  /// id first). Naming nothing, the button does nothing.
  final String elementId;

  final String url;

  const ButtonAction({
    this.kind = ButtonActionKind.goToFrame,
    this.frame = 0,
    this.elementId = "",
    this.url = "",
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = ButtonAction();

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
        frame:
            jsonInt(json["frame"], _defaults.frame).clamp(0, maxFrameCount - 1),
        // An element's id, or a scene's id or name (goToScene finds either).
        elementId: jsonLabel(json["element"], _defaults.elementId),
        url: jsonString(json["url"], _defaults.url),
      );
}

/// ButtonElement is a labelled rectangle that does something when pressed,
/// in a published interactive canvas only; inert in a picture or video.
class ButtonElement extends CanvasElement {
  final String label;
  final TextSpec textSpec;
  final BoxSpec box;

  /// hoverFill and hoverTextColor are what the button becomes under the
  /// pointer; transparent means no change.
  final Color hoverFill;
  final Color hoverTextColor;

  final ButtonAction action;

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

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = ButtonElement(ElementBase(id: ""));

  @override
  ElementKind get kind => ElementKind.button;

  /// assetIds is the picture its box is painted with, where it has one: left
  /// out, the sweep takes the picture away. See BoxSpec.assetIds.
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

  /// mapOwnColours maps the button's type, box and arrival, and its hover
  /// colours, each hidden while transparent (as they are saved).
  @override
  ButtonElement mapOwnColours(ColourMap f) {
    var p = ColourPass(f);
    var textSpec = p.part(this.textSpec, (s) => s.mapColours(f));
    var box = p.part(this.box, (b) => b.mapColours(f));
    var hoverFill = p(this.hoverFill, shown: this.hoverFill.a > 0);
    var hoverTextColor =
        p(this.hoverTextColor, shown: this.hoverTextColor.a > 0);
    var animation = p.part(this.animation, (a) => a.mapColours(f));
    if (!p.changed) return this;
    return copyWith(
      textSpec: textSpec,
      box: box,
      hoverFill: hoverFill,
      hoverTextColor: hoverTextColor,
      animation: animation,
    );
  }

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
          label: jsonString(json["label"], _defaults.label),
          textSpec:
              jsonSpec(json["textSpec"], TextSpec.fromJson, _defaults.textSpec),
          box: jsonSpec(json["box"], BoxSpec.fromJson, _defaults.box),
          hoverFill: colorFromJson(json["hoverFill"], _defaults.hoverFill),
          hoverTextColor:
              colorFromJson(json["hoverText"], _defaults.hoverTextColor),
          action:
              jsonSpec(json["action"], ButtonAction.fromJson, _defaults.action),
          animation: jsonSpec(
              json["anim"], ElementAnimation.fromJson, _defaults.animation));
}
