part of '../canvas_controller.dart';

// Part of CanvasController: what the Chain shows of a channel: its Curves,
// Pitch, Instrument or Speech.

extension CanvasChainViews on CanvasController {
  /// motionCurvesShown is whether the Motion view shows its Curves: the
  /// picked clip's keys across the whole panel.
  bool get motionCurvesShown => _motionCurves;

  void showMotionCurves(String element, String clip) {
    pickMotion(element, clip);
    _motionCurves = true;
    notifyListeners();
  }

  /// trackCurvesShown is whether the Motion view shows the Curves of the
  /// Keyframes card's keyframes -- an element's own, or a team player's.
  bool get trackCurvesShown => _trackCurves;

  /// trackCurvesShowing is whether those Curves fill the Motion view now:
  /// open, and the selected element's keyframes there to curve. Open on one
  /// element and another picked with none, the chain shows (with Chain lit
  /// and Keys to shut) rather than an empty Curves with no tab of its own;
  /// back on one with keyframes, its Curves again.
  bool get trackCurvesShowing {
    if (!_trackCurves) return false;
    var t = keyframeTarget;
    return t != null && !t.points && t.track.keys.length >= 2;
  }

  /// trackCurvesFrame is the keyframe the Curves opened on, picked there.
  int? get trackCurvesFrame => _trackCurvesFrame;

  /// showTrackCurves opens them, on the keyframe at [frame] where given.
  void showTrackCurves({int? frame}) {
    _trackCurves = true;
    _trackCurvesFrame = frame;
    _motionCurves = false;
    notifyListeners();
  }

  void closeTrackCurves() {
    if (!_trackCurves) return;
    _trackCurves = false;
    notifyListeners();
  }

  void closeMotionCurves() {
    if (!_motionCurves) return;
    _motionCurves = false;
    notifyListeners();
  }

  /// setElementAnimation sets how element [id] arrives, leaves and loops:
  /// the cards the Motion chain shows as the sidebar does.
  void setElementAnimation(String id, ElementAnimation animation) {
    var e = document.elementById(id);
    if (e == null) return;
    // A new preset brings its own curve and way of cutting, as the
    // sidebar's applyElementAnimation does: Build up and Break apart differ
    // only in these. Numbers set on the same preset are kept.
    var was = CanvasController.elementAnimationOf(e);
    if (animation.preset != was.preset) {
      animation = animation.copyWith(
          ease: animation.preset.wants, effect: animation.preset.effect);
    }
    replaceElement(CanvasController._withElementAnimation(e, animation),
        transient: true);
  }

  void toggleEditorWide() {
    _editorWide = !_editorWide;
    _effectsFocus = _clipEditorShown ? "clip" : "roll";
    _effectsFocusCount++;
    notifyListeners();
  }

  /// closeEditor takes the editor out of the effects strip.
  void closeEditor() {
    _clipEditorShown = false;
    _pianoRollShown = false;
    _speechShown = false;
    _pitchShown = false;
    _instrumentShown = false;
    notifyListeners();
  }

  /// pitchShown is whether the Chain's sound is on the Pitch editor of the
  /// channel [effectsOf]: its recording's notes, moved -- see pitch_edit.dart.
  bool get pitchShown => _pitchShown;

  void showPitch(String key) {
    _effectsOf = key;
    _clipEditorShown = false;
    _pianoRollShown = false;
    _speechShown = false;
    _instrumentShown = false;
    _pitchShown = true;
    _effectsFocus = "pitch";
    _effectsFocusCount++;
    _showChain(ChainView.sound);
    notifyListeners();
  }

  /// instrumentShown is whether the Chain's sound is on channel
  /// [effectsOf]'s Instrument editor: how its instrument plays.
  bool get instrumentShown => _instrumentShown;

  /// showInstrument opens [key]'s instrument in the Chain's Instrument editor.
  void showInstrument(String key) {
    _effectsOf = key;
    _clipEditorShown = false;
    _pianoRollShown = false;
    _speechShown = false;
    _pitchShown = false;
    _instrumentShown = true;
    _effectsFocus = "instrument";
    _effectsFocusCount++;
    _showChain(ChainView.sound);
    notifyListeners();
  }

  void setInstrumentShape(
          String channel, InstrumentShape Function(InstrumentShape) change,
          {bool transient = false}) =>
      setChannelPart(channel, (p) => p.copyWith(shape: change(p.shape)),
          transient: transient);

  /// speechShown is whether the Chain shows the channel's Speech: showSpeech.
  bool get speechShown => _speechShown;

  /// showSpeech opens [key]'s Speech in the Chain: its script, its takes and
  /// its voice -- what makes its clips -- and Sing, the Vocaliser. Not steps
  /// of its chain: what they make plays through it.
  void showSpeech(String key) {
    _effectsOf = key;
    _clipEditorShown = false;
    _pianoRollShown = false;
    _pitchShown = false;
    _instrumentShown = false;
    _speechShown = true;
    _effectsFocus = "speech";
    _effectsFocusCount++;
    _showChain(ChainView.sound);
    notifyListeners();
  }
}
