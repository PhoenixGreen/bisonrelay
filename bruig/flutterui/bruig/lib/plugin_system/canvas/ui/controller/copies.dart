part of '../canvas_controller.dart';

// The copies of an element reused (Ken, 2026-11-08): each an object on the
// canvas -- picked with a click, Shift-click for more, dragged on its own,
// placed with a click while placing -- and each with what it has of its
// own: a start, a speed, a size, a turn, an opacity, a colour, or any knob
// of the element's chain. Whatever copies are picked are what the chain
// edits; none picked, every copy.
// Part of CanvasController: the state is the class's, in
// canvas_controller.dart; these are its methods.

extension CanvasCopies on CanvasController {
  /// pickedCopiesOf is which of [element]'s copies are picked, by id: none
  /// where it is not picked itself, or has no copies.
  Set<String> pickedCopiesOf(String element) {
    if (_copiesOf != element || !_selection.contains(element)) return const {};
    var set = motionOf(element).instances;
    if (set == null) return const {};
    return {
      for (var id in _pickedCopies)
        if (set.indexOf(id) >= 0) id
    };
  }

  /// copiesPicked is whether some, not all, of [element]'s copies are what
  /// is edited.
  bool copiesPicked(String element) => pickedCopiesOf(element).isNotEmpty;

  /// pickCopy picks copy [id] of [element] -- with [toggle], in or out of
  /// those picked -- the element picked with it.
  void pickCopy(String element, String id, {bool toggle = false}) {
    if (!_selection.contains(element) || _selection.length != 1) {
      selectOnly(element);
    }
    if (_copiesOf != element) {
      _copiesOf = element;
      _pickedCopies = {};
    }
    if (toggle) {
      _pickedCopies.contains(id)
          ? _pickedCopies.remove(id)
          : _pickedCopies.add(id);
    } else {
      _pickedCopies = {id};
    }
    notifyListeners();
  }

  /// pickCopies picks [ids] of [element]'s copies; empty is all of them.
  void pickCopies(String element, Set<String> ids) {
    if (!_selection.contains(element)) selectOnly(element);
    _copiesOf = element;
    _pickedCopies = {...ids};
    notifyListeners();
  }

  /// pickAllCopies goes back to editing every copy of [element].
  void pickAllCopies(String element) => pickCopies(element, const {});

  /// placingCopies is the element a click on the canvas places a copy of,
  /// or null. Set to start placing; Escape, or the button again, stops.
  String? get placingCopies => _placingCopies;

  set placingCopies(String? element) {
    if (_placingCopies == element) return;
    _placingCopies = element;
    notifyListeners();
  }

  /// copyCentre is where copy [i] of [e] stands on the page, as placed.
  Offset copyCentre(CanvasElement e, ElementInstance copy) => Offset(
      e.base.x + e.base.width / 2 + copy.dx,
      e.base.y + e.base.height / 2 + copy.dy);

  /// placeCopyAt puts a new copy of [element] with its middle at [point] on
  /// the page, picked; an element placed once becomes two. Its id.
  String? placeCopyAt(String element, Offset point) {
    var e = _document.elementById(element);
    if (e == null) return null;
    var set = motionOf(element).instances ??
        const InstanceSet(items: [ElementInstance("i0")]);
    var centre =
        Offset(e.base.x + e.base.width / 2, e.base.y + e.base.height / 2);
    var next = set.withNewCopy(point.dx - centre.dx, point.dy - centre.dy);
    if (identical(next, set)) return null;
    setInstances(element, next);
    var id = next.items.last.id;
    _copiesOf = element;
    _pickedCopies = {id};
    return id;
  }

  /// moveCopies moves [ids] of [element]'s copies [by] on the page.
  void moveCopies(String element, Set<String> ids, Offset by,
      {bool transient = false}) {
    var set = motionOf(element).instances;
    if (set == null || ids.isEmpty) return;
    setInstances(
        element,
        set.copyWith(items: [
          for (var x in set.items)
            ids.contains(x.id)
                ? x.copyWith(dx: x.dx + by.dx, dy: x.dy + by.dy)
                : x,
        ]),
        transient: transient);
  }

  /// duplicateCopies puts a new copy beside each of [ids], [by] from it,
  /// picked in their place: an Alt-drag. The new ids.
  Set<String> duplicateCopies(String element, Set<String> ids, Offset by) {
    var had = motionOf(element).instances;
    if (had == null) return const {};
    var set = had;
    var made = <String>{};
    for (var id in ids) {
      var i = set.indexOf(id);
      if (i < 0) continue;
      var from = set.items[i];
      var next = set.withNewCopy(from.dx + by.dx, from.dy + by.dy);
      if (identical(next, set)) break;
      // Its own values with it.
      var fresh = next.items.last;
      set = next.withCopy(fresh.id, (x) => x.copyWith(own: from.own));
      made.add(fresh.id);
    }
    setInstances(element, set, transient: true);
    _copiesOf = element;
    _pickedCopies = made;
    return made;
  }

  /// removeCopies takes [ids] of [element]'s copies away; the last one
  /// left, it is placed once again.
  void removeCopies(String element, Set<String> ids) {
    var set = motionOf(element).instances;
    if (set == null || ids.isEmpty) return;
    var left = set.without(ids);
    setInstances(
        element, left.count <= 1 && left.items.first.own.isEmpty ? null : left);
    _pickedCopies = {};
  }

  /// copyValueOf is [element]'s [key] as its first picked copy has it --
  /// its own, or null for the element's -- and whether any picked copy has
  /// its own.
  double? copyOwnOf(String element, String key) {
    var set = motionOf(element).instances;
    var picked = pickedCopiesOf(element);
    if (set == null || picked.isEmpty) return null;
    for (var x in set.items) {
      if (picked.contains(x.id) && x.own.containsKey(key)) return x.own[key];
    }
    return null;
  }

  /// setCopyOwn gives the picked copies of [element] [key] of their own --
  /// [value], or none (the element's) where null.
  void setCopyOwn(String element, String key, double? value,
      {bool transient = false}) {
    var set = motionOf(element).instances;
    var picked = pickedCopiesOf(element);
    if (set == null || picked.isEmpty) return;
    setInstances(
        element,
        set.copyWith(items: [
          for (var x in set.items)
            picked.contains(x.id) ? x.withOwn(key, value) : x,
        ]),
        transient: transient);
  }

  /// revertCopies takes back all the picked copies have of their own, but
  /// where they are.
  void revertCopies(String element, {Set<String>? ids}) {
    var set = motionOf(element).instances;
    ids ??= pickedCopiesOf(element);
    if (set == null || ids.isEmpty) return;
    setInstances(
        element,
        set.copyWith(items: [
          for (var x in set.items) ids.contains(x.id) ? x.reverted : x,
        ]));
  }

  /// copyValue is [v] of [element] as the chain edits it: the first picked
  /// copy's, or -- none picked -- the first copy's as the set varies it.
  double copyValue(String element, CopyValue v) {
    var set = motionOf(element).instances;
    if (set == null) return v.initial;
    var picked = pickedCopiesOf(element);
    var i =
        picked.isEmpty ? 0 : set.items.indexWhere((x) => picked.contains(x.id));
    return set.valueOf(math.max(0, i), v);
  }

  /// deviceKnob is [param] of [element]'s device [device] as the chain
  /// edits it -- the first picked copy's own, or the shared [shared] -- and
  /// whether it is a copy's own.
  (double, bool) deviceKnob(
      String element, String device, String param, double shared) {
    var own = copyOwnOf(element, deviceOwnKey(device, param));
    return own == null ? (shared, false) : (own, true);
  }
}
