import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/preset_scaling.dart';

// element_preset.dart is a design somebody wants again: an element's own JSON
// with a name on it, so a new setting needs nothing here. Choosing one puts
// an ordinary, fully editable element on the canvas.

/// ElementPreset is a saved element, ready to be put on a canvas again.
class ElementPreset {
  /// id is how the preset is addressed on disk and in the panel. Built-in
  /// ones carry a name chosen in code; saved ones get one from the clock.
  final String id;

  final String name;

  /// kind is what the preset makes, so the settings for a table offer table
  /// presets and nothing else.
  final ElementKind kind;

  /// element is the element's own JSON -- see CanvasElement.toJson.
  final Map<String, dynamic> element;

  /// builtIn presets ship with the app. They can be used and copied but not
  /// renamed or deleted.
  final bool builtIn;

  /// madeOn is the page this was designed on, so it can be sized to the page
  /// it is dropped on. Null for built-in presets and older saved ones.
  final Size? madeOn;

  const ElementPreset({
    required this.id,
    required this.name,
    required this.kind,
    required this.element,
    this.builtIn = false,
    this.madeOn,
  });

  /// build is a fresh element from this preset, always under a new id: two
  /// elements sharing one would be treated as one element.
  CanvasElement build() => elementFromJson({...element, "id": newElementId()});

  /// buildFor is the same element scaled from [madeOn] to a page [on] big
  /// and put in the middle of it. See presetScale.
  CanvasElement buildFor(Size on) =>
      centredOn(scaledElement(build(), presetScale(madeOn, on)), on);

  ElementPreset copyWith({String? name}) => ElementPreset(
        id: id,
        name: name ?? this.name,
        kind: kind,
        element: element,
        builtIn: builtIn,
        madeOn: madeOn,
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "kind": kind.name,
        "element": element,
        if (madeOn case var made?) "madeOn": sizeToJson(made),
      };

  factory ElementPreset.fromJson(Map<String, dynamic> json,
          {bool builtIn = false}) =>
      ElementPreset(
        id: jsonString(json["id"], ""),
        name: jsonString(json["name"], "Preset"),
        kind: ElementKind.values.firstWhere(
          (k) => k.name == json["kind"],
          orElse: () => ElementKind.shape,
        ),
        element: json["element"] is Map<String, dynamic>
            ? json["element"] as Map<String, dynamic>
            : const {},
        builtIn: builtIn,
        madeOn: sizeFromJson(json["madeOn"]),
      );
}
