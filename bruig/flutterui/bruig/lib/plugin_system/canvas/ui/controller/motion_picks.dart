part of '../canvas_controller.dart';

// The motion clips picked on an element's row, the own tab and clip settings
// open in the Chain, and the scene picked. Part of CanvasController: its fields
// and lifecycle are in canvas_controller.dart.

extension CanvasMotionPicks on CanvasController {
  /// _pickLeft is whether another element has been selected since the clip
  /// was picked. The pick is then let go as it is read, so the Chain and
  /// Delete do not act on the previous element's clip; the selection
  /// changes in too many places to clear it at each.
  bool get _pickLeft =>
      _pickedOf != null &&
      _selection.isNotEmpty &&
      !_selection.contains(_pickedOf);

  /// pickedMotion is the clip the Animation panel shows, by id: picked from
  /// a slot, or from the timeline -- then [pickedPlacement] is the place.
  String? get pickedMotion => _pickLeft ? null : _pickedMotion;

  String? get pickedPlacement => _pickLeft ? null : _pickedPlacement;

  /// motionPicks are the clips picked together on the timeline, as
  /// (element, placement), by a box drag or Shift: moved and deleted
  /// together.
  Set<(String, String)> get motionPicks => _motionPicks;

  /// pickMotions makes [picks] the clips picked together; one alone is
  /// picked as [pickMotion] picks it, for the Chain to show.
  void pickMotions(Set<(String, String)> picks) {
    _motionPicks = picks;
    if (picks.length == 1) {
      var (element, placement) = picks.single;
      var clip = _document.elementById(element)?.base.motion
          .placement(placement)
          ?.clip;
      _pickedMotion = clip;
      _pickedPlacement = clip == null ? null : placement;
      _pickedOf = clip == null ? null : element;
    } else {
      _pickedMotion = _pickedPlacement = null;
    }
    _notifyView();
  }

  /// toggleMotionPick adds clip [placement] of [element] to those picked, or
  /// takes it out: Shift and a click.
  void toggleMotionPick(String element, String placement) {
    var next = {..._motionPicks};
    if (pickedPlacement case var p? when next.isEmpty) {
      if (_selection.length == 1) next.add((_selection.first, p));
    }
    if (!next.remove((element, placement))) next.add((element, placement));
    pickMotions(next);
  }

  /// pickMotion picks [clip] of [element], and where it was placed if picked
  /// from the timeline. Null clears it.
  void pickMotion(String? element, String? clip, {String? placement}) {
    _motionPicks = element != null && clip != null && placement != null
        ? {(element, placement)}
        : const {};
    if (element != null && !(_selection.length == 1 &&
        _selection.first == element)) {
      _selection
        ..clear()
        ..add(element);
    }
    _pickedMotion = clip;
    _pickedPlacement = clip == null ? null : placement;
    _pickedOf = clip == null
        ? null
        : element ??
            _document.elements
                .where((e) => e.base.motion.clip(clip) != null)
                .firstOrNull
                ?.id;
    _pickedScene = null;
    _ownTab = null;
    _notifyView();
  }

  MotionKind? get ownTab => _ownTab;

  bool clipSettingsOpen(String element) => _clipSettings.contains(element);

  void toggleClipSettings(String element) {
    if (!_clipSettings.remove(element)) _clipSettings.add(element);
    _notifyView();
  }

  set ownTab(MotionKind? kind) {
    if (kind == _ownTab) return;
    _ownTab = kind;
    _notifyView();
  }

  /// pickedScene is the scene the Animation panel shows, by index (with its
  /// transition and camera), picked by double-clicking its timeline box. A
  /// clip picked, or a new selection, overrides it.
  int? get pickedScene {
    var i = _pickedScene;
    if (i == null || i >= _document.allScenes.length) return null;
    return setEquals(_selection, _pickedSceneWith) ? i : null;
  }

  /// transitionsAsDefault is whether the Chain's transition is the default
  /// (every scene's without its own) rather than one join's: true on the
  /// master, unless a join was picked by its own slot.
  bool get transitionsAsDefault =>
      _document.editingMaster && !(_joinPicked && pickedScene != null);

  /// pickScene opens [index] in the Animation panel.
  void pickScene(int index) {
    _joinPicked = false;
    _pickedScene = index;
    _pickedSceneWith = {..._selection};
    _pickedMotion = _pickedPlacement = null;
    _animationOpen = true;
    _effectsOpen = false;
    _dockOpening(DockPanel.chain);
    _notifyView();
  }
}
