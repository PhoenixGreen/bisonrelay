part of '../canvas_controller.dart';

// The Chain panel's own state: whether it is open and full, what it shows of an
// element, its meters, badges, macros and trail, the keys strip, and whether
// everything is folded. Part of CanvasController: its fields and lifecycle are
// in canvas_controller.dart.

extension CanvasChainPanel on CanvasController {
  /// animationOpen is whether the Chain panel is open on its motion (see
  /// dock). Opening it puts the Chain's sound away: one view at a time.
  bool get animationOpen => _animationOpen;

  set animationOpen(bool value) {
    if (_animationOpen == value) return;
    _animationOpen = value;
    if (value) {
      _effectsOpen = false;
      _chainMotion = true;
      _dockOpening(DockPanel.chain);
    }
    _notifyView();
  }

  /// chainFocus is the card the settings last asked the Chain to show (a
  /// device id, or "clips"), until the Chain has (see chainFocused).
  String? get chainFocus => _chainFocus;

  /// chainFocused is the Chain saying it has shown [chainFocus].
  void chainFocused() => _chainFocus = null;

  /// showInChain opens [element]'s Chain on its motion at [device], or with
  /// [clip] at [placement] picked, for a settings line (panel_parts.dart).
  void showInChain(String element, String? device,
      {String? clip, String? placement}) {
    if (clip != null) {
      pickMotion(element, clip, placement: placement);
    } else if (!(_selection.length == 1 && _selection.first == element)) {
      selectOnly(element);
    }
    _chainFocus = device ?? (clip != null ? "clips" : null);
    animationOpen = true;
    _notifyView();
  }

  /// chainShowsMotion is whether the Chain shows motion rather than sound.
  bool get chainShowsMotion => _animationOpen;

  /// chainMeters, chainBadges and chainMacros show the meters between the
  /// Chain's devices, each device's effect on the level, and the Macros
  /// zone; each can be hidden for room. A view setting, not saved.
  bool get chainMeters => _chainMeters;

  set chainMeters(bool on) {
    if (on == _chainMeters) return;
    _chainMeters = on;
    notifyListeners();
  }

  bool get chainBadges => _chainBadges;

  set chainBadges(bool on) {
    if (on == _chainBadges) return;
    _chainBadges = on;
    notifyListeners();
  }

  bool get chainMacros => _chainMacros;

  set chainMacros(bool on) {
    if (on == _chainMacros) return;
    _chainMacros = on;
    notifyListeners();
  }

  /// motionTrail shows the trail (the path its middle takes) and onion skin
  /// of the element whose motion the Chain is open on. On by default.
  bool get motionTrail => _motionTrail;

  set motionTrail(bool on) {
    if (on == _motionTrail) return;
    _motionTrail = on;
    notifyListeners();
  }

  /// _chainOpensOnMotion is the view the Chain's button opens on: motion for
  /// an element drawn on the canvas, sound for a channel or sound, else the
  /// last view. Only the header's switch changes an open Chain.
  bool get _chainOpensOnMotion {
    var picked = selectedElements;
    if (picked.any((e) => e is! AudioElement)) return true;
    if (picked.isNotEmpty || selectedChannel != null) return false;
    return _chainMotion;
  }

  /// showChain shows the Chain's motion, or its sound (the last channel's).
  void showChain({required bool motion}) {
    if (motion) {
      animationOpen = true;
    } else {
      openEffects(effectsChannel);
    }
  }

  /// chainFull: see _chainFull. While set, the dock fills the canvas's room.
  bool get chainFull => _chainFull;

  set chainFull(bool full) {
    if (full == _chainFull) return;
    _chainFull = full;
    notifyListeners();
  }

  bool get keysShown => CanvasController._keysShown;

  double? get keysHeight => CanvasController._keysHeight;

  set keysHeight(double? height) {
    if (height == CanvasController._keysHeight) return;
    CanvasController._keysHeight = height;
    notifyListeners();
  }

  set keysShown(bool shown) {
    if (shown == CanvasController._keysShown) return;
    CanvasController._keysShown = shown;
    notifyListeners();
  }

  MotionPhase? get chainPhase => _chainPhase;

  set chainPhase(MotionPhase? phase) {
    if (phase == _chainPhase) return;
    _chainPhase = phase;
    notifyListeners();
  }

  /// allFolded is whether the All group (the master's rows, in every scene)
  /// is folded under its heading, on the timeline and in the mixer.
  bool get allFolded => _allFolded;

  set allFolded(bool folded) {
    if (folded == _allFolded) return;
    _allFolded = folded;
    notifyListeners();
  }
}
