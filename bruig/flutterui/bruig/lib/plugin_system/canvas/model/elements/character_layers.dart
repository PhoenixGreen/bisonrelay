// character_layers.dart is a sketched character as a stack of layers: each
// part of the body, the face and the hair, and each garment worn, drawn as
// a layer of its own that can be hidden, soloed and edited on its own.
//
// A layer is named by a key: a body layer's name, or "worn:<i>" for the
// garment at <i> in the wardrobe. The painter draws every stroke inside the
// layer it belongs to -- see _Drawing._in in character_painter.dart -- so
// hiding the arm leaves its sleeve, and soloing the sleeve shows it alone.

/// BodyLayer is a layer of the body, the face or the hair.
enum BodyLayer {
  hairFront("Front hair", LayerGroup.hair),
  // The hair over the head as one shape, the locks over it: what to
  // reshape for a hairline, or a bold lock -- see _Drawing._hairBase.
  hairBase("Hair base", LayerGroup.hair),
  brows("Brows", LayerGroup.face),
  eyes("Eyes", LayerGroup.face),
  nose("Nose", LayerGroup.face),
  mouth("Mouth", LayerGroup.face),
  head("Head", LayerGroup.body),
  ears("Ears", LayerGroup.body),
  handL("Left hand", LayerGroup.body),
  handR("Right hand", LayerGroup.body),
  armL("Left arm", LayerGroup.body),
  armR("Right arm", LayerGroup.body),
  neck("Neck", LayerGroup.body),
  torso("Body", LayerGroup.body),
  footL("Left foot", LayerGroup.body),
  footR("Right foot", LayerGroup.body),
  legL("Left leg", LayerGroup.body),
  legR("Right leg", LayerGroup.body),
  extras("Tail, wings and horns", LayerGroup.body),
  hairBack("Back hair", LayerGroup.hair);

  final String label;
  final LayerGroup group;
  const BodyLayer(this.label, this.group);

  static BodyLayer? fromName(String? name) {
    for (var l in values) {
      if (l.name == name) return l;
    }
    return null;
  }

  /// mirrored is the layer on the other side: the left hand for the right.
  BodyLayer get mirrored => switch (this) {
        handL => handR,
        handR => handL,
        armL => armR,
        armR => armL,
        footL => footR,
        footR => footL,
        legL => legR,
        legR => legL,
        _ => this,
      };
}

/// LayerGroup is what a layer is part of, in the layer list.
enum LayerGroup {
  hair("Hair"),
  face("Face"),
  body("Body"),
  clothing("Clothing");

  final String label;
  const LayerGroup(this.label);
}

/// garmentLayer is the key of the garment at [i] in the wardrobe.
String garmentLayer(int i) => "worn:$i";

/// garmentOfLayer is the wardrobe index a garment layer's [key] names, or
/// null for a body layer.
int? garmentOfLayer(String key) =>
    key.startsWith("worn:") ? int.tryParse(key.substring(5)) : null;

/// LayerView is which layers are drawn: none of [hidden], and -- with
/// [solo] -- that one alone, everything else faint behind it.
class LayerView {
  final Set<String> hidden;
  final String? solo;
  const LayerView({this.hidden = const {}, this.solo});

  static const LayerView all = LayerView();

  bool get isAll => hidden.isEmpty && solo == null;

  /// shows is whether [layer] is drawn at all.
  bool shows(String layer) => !hidden.contains(layer);

  String get key => "${(hidden.toList()..sort()).join(",")}|${solo ?? ""}";
}
