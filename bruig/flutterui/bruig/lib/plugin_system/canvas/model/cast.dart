import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// cast.dart is the Cast: elements kept once for a whole document (a game's
// hero above all), of which its scenes hold linked copies. A copy is stored
// whole, so everything reads it as any element; what it shares is kept in
// step by CanvasController.castSynced. Its own, scene by scene: placement,
// size, facing, framing, visibility, its performance, keyframes and clips'
// timeline places, and whether it is the player there. Shared: its design,
// game settings, motion clips and chain, sounds and name.

/// castOwnKeys are the JSON keys a linked copy keeps as its scene's own, by
/// kind; [castOwnBase] every kind's.
const Set<String> castOwnBase = {
  "id",
  "x",
  "y",
  "w",
  "h",
  "rot",
  "skx",
  "sky",
  "visible",
  "locked",
  "rowColour",
  "aspect",
  "ax",
  "ay",
  "anchorLocked",
  "track",
  "typeScale",
  "ownText",
  "ownDesign",
  "shared",
  "cue",
  "spot",
  "layouts",
  "cast",
};

const Map<ElementKind, Set<String>> castOwnKeys = {
  ElementKind.character3d: {
    "framing",
    "turn",
    "tilt",
    "zoom",
    "round",
    "performance",
  },
};

/// castLinked is [shared]'s shared part with [own]'s own: a member made a
/// copy as [own] has it in its scene, or a copy's change taken into the
/// member. [own] itself where the two are different kinds.
CanvasElement castLinked(CanvasElement shared, CanvasElement own) {
  if (shared.kind != own.kind) return own;
  var from = shared.toJson(), mine = own.toJson();
  var out = <String, dynamic>{...from};
  for (var key in {...castOwnBase, ...?castOwnKeys[own.kind]}) {
    if (mine.containsKey(key)) {
      out[key] = mine[key];
    } else {
      out.remove(key);
    }
  }
  // Its game settings are shared; whether it is played here is its own.
  var play = from["play"], ownPlay = mine["play"];
  var played = ownPlay is Map ? ownPlay["as"] : null;
  if (play is Map || ownPlay is Map) {
    out["play"] = {
      ...?(play as Map?)?.cast<String, dynamic>(),
      "as": played ?? "none"
    };
  }
  // Its clips are shared; where they sit on its scene's timeline is its own.
  var motion = from["motion"], ownMotion = mine["motion"];
  var placed = ownMotion is Map ? ownMotion["placed"] : null;
  if (motion is Map || placed != null) {
    var m = <String, dynamic>{...?(motion as Map?)?.cast<String, dynamic>()};
    if (placed != null) {
      m["placed"] = placed;
    } else {
      m.remove("placed");
    }
    out["motion"] = m;
  }
  return elementFromJson(out);
}

/// sameShared is whether [a] and [b] share all they would as linked copies.
bool sameShared(CanvasElement a, CanvasElement b) =>
    _json(castLinked(a, b)) == _json(b);

String _json(CanvasElement e) => e.toJson().toString();

CanvasElement? castMember(CanvasDocument doc, String id) =>
    id.isEmpty ? null : doc.cast.where((e) => e.id == id).firstOrNull;

/// castSynced is [next] with its Cast kept in step: a linked copy on the
/// canvas being edited whose shared part changed since [was] changes its
/// member and every other copy, in every scene and on the master. [next]
/// itself where nothing shared changed, or another canvas is being edited.
CanvasDocument castSynced(CanvasDocument was, CanvasDocument next) {
  if (next.cast.isEmpty) return next;
  if (was.at != next.at || was.editingMaster != next.editingMaster) {
    return next;
  }
  var members = {for (var m in next.cast) m.id: m};
  var before = {for (var e in was.elements) e.id: e};
  var changed = <String, CanvasElement>{};
  for (var e in next.elements) {
    var m = members[e.base.cast];
    if (m == null || changed.containsKey(m.id)) continue;
    if (identical(before[e.id], e) || sameShared(m, e)) continue;
    changed[m.id] = castLinked(e, m);
  }
  if (changed.isEmpty) return next;
  return castRelinked(next, changed);
}

/// castRelinked is [doc] with members [changed] put in its Cast, by id, and
/// every copy of them remade, wherever it is.
CanvasDocument castRelinked(
    CanvasDocument doc, Map<String, CanvasElement> changed) {
  List<CanvasElement> relinked(List<CanvasElement> list) => [
        for (var e in list)
          if (changed[e.base.cast] case var m?) castLinked(m, e) else e,
      ];
  var out = doc.copyWith(
      cast: [for (var m in doc.cast) changed[m.id] ?? m],
      elements: relinked(doc.elements));
  for (var (i, scene) in doc.allScenes.indexed) {
    if (!doc.editingMaster && i == doc.at) continue;
    out = out.withScene(i, scene.copyWith(elements: relinked(scene.elements)));
  }
  if (doc.master case var master? when !doc.editingMaster) {
    out = out.copyWith(
        master: master.copyWith(elements: relinked(master.elements)));
  }
  return out;
}

/// castAdded is [doc] with [e] made a new Cast member, and [e] and every
/// other copy of it linked to it: in every scene and on the master, each
/// element of its id and kind, and for a 3D character each of its design
/// too, so copies already placed join. Each keeps its own; what they share
/// becomes [e]'s. Returns the document and the new member's id.
(CanvasDocument, String) castAdded(CanvasDocument doc, CanvasElement e,
    {required String id}) {
  var member = e.rebase(e.base.copyWith(id: id, cast: ""));
  bool same(CanvasElement x) =>
      x.kind == e.kind &&
      x.base.cast.isEmpty &&
      (x.id == e.id || _sameDesign(x, e));
  List<CanvasElement> linked(List<CanvasElement> list) => [
        for (var x in list)
          if (same(x))
            castLinked(member, x.rebase(x.base.copyWith(cast: id)))
          else
            x,
      ];
  var out =
      doc.copyWith(cast: [...doc.cast, member], elements: linked(doc.elements));
  for (var (i, scene) in doc.allScenes.indexed) {
    if (!doc.editingMaster && i == doc.at) continue;
    out = out.withScene(i, scene.copyWith(elements: linked(scene.elements)));
  }
  if (doc.master case var master? when !doc.editingMaster) {
    out = out.copyWith(
        master: master.copyWith(elements: linked(master.elements)));
  }
  return (out, id);
}

bool _sameDesign(CanvasElement a, CanvasElement b) {
  var da = a.toJson()["design"], db = b.toJson()["design"];
  return da is Map &&
      db is Map &&
      da["id"] != null &&
      da["id"] != "" &&
      da["id"] == db["id"];
}

/// castUnlinked is [doc] with copy [id] on the edited canvas unlinked.
CanvasDocument castUnlinked(CanvasDocument doc, String id) =>
    doc.copyWith(elements: [
      for (var e in doc.elements)
        if (e.id == id) e.rebase(e.base.copyWith(cast: "")) else e,
    ]);

/// castRemoved is [doc] without Cast member [id], its copies kept unlinked.
CanvasDocument castRemoved(CanvasDocument doc, String id) {
  List<CanvasElement> freed(List<CanvasElement> list) => [
        for (var e in list)
          if (e.base.cast == id) e.rebase(e.base.copyWith(cast: "")) else e,
      ];
  var out = doc.copyWith(cast: [
    for (var m in doc.cast)
      if (m.id != id) m
  ], elements: freed(doc.elements));
  for (var (i, scene) in doc.allScenes.indexed) {
    if (!doc.editingMaster && i == doc.at) continue;
    out = out.withScene(i, scene.copyWith(elements: freed(scene.elements)));
  }
  if (doc.master case var master? when !doc.editingMaster) {
    out =
        out.copyWith(master: master.copyWith(elements: freed(master.elements)));
  }
  return out;
}

/// castCopies is how many copies of member [id] [doc] holds, everywhere.
int castCopies(CanvasDocument doc, String id) {
  var n = 0;
  for (var scene in doc.allScenes) {
    n += scene.elements.where((e) => e.base.cast == id).length;
  }
  n += doc.master?.elements.where((e) => e.base.cast == id).length ?? 0;
  return n;
}
