import 'dart:async';
import 'dart:io' show Directory, File;
import 'dart:isolate' show Isolate;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show Color, Offset, Rect, Size;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyDownEvent, KeyEvent, KeyRepeatEvent, KeyUpEvent, LogicalKeyboardKey;
import 'package:gamepads/gamepads.dart' show Gamepads, NormalizedGamepadEvent;
import 'package:path/path.dart' as path;

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart' show ffmpegHelp, ffmpegPath;
import 'package:bruig/plugin_system/canvas/media/audio_engine.dart';
import 'package:bruig/plugin_system/canvas/media/audio_runtime.dart';
import 'package:bruig/plugin_system/canvas/media/code_dart_runner.dart';
import 'package:bruig/plugin_system/canvas/media/ffmpeg_video.dart';
import 'package:bruig/plugin_system/canvas/media/kokoro_speech.dart';
import 'package:bruig/plugin_system/canvas/media/midi_input.dart';
import 'package:bruig/plugin_system/canvas/media/mix/analysers.dart' show Wave, LoudnessReading;
import 'package:bruig/plugin_system/canvas/media/mix/dart_audio_engine.dart';
import 'package:bruig/plugin_system/canvas/media/mix/decode.dart' show ffmpegDecode, readWholeAway;
import 'package:bruig/plugin_system/canvas/media/mix/device_scope.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart' show StripProcessor, mixRate;
import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart' show PitchReading;
import 'package:bruig/plugin_system/canvas/media/phrasing.dart';
import 'package:bruig/plugin_system/canvas/media/push_surface.dart' show PadClip;
import 'package:bruig/plugin_system/canvas/media/qwen_speech.dart';
import 'package:bruig/plugin_system/canvas/media/speech.dart';
import 'package:bruig/plugin_system/canvas/media/speech_engines.dart';
import 'package:bruig/plugin_system/canvas/media/speech_finish.dart';
import 'package:bruig/plugin_system/canvas/media/synth/part_render.dart';
import 'package:bruig/plugin_system/canvas/media/synth/patch_voice.dart' show PatchWatch;
import 'package:bruig/plugin_system/canvas/media/video_runtime.dart';
import 'package:bruig/plugin_system/canvas/media/vocaliser.dart';
import 'package:bruig/plugin_system/canvas/media/warp.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/audio_tools.dart';
import 'package:bruig/plugin_system/canvas/model/automation.dart';
import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_cues.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_rulers.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_estimate.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_align.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_palette.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/cast.dart';
import 'package:bruig/plugin_system/canvas/model/chart_play.dart';
import 'package:bruig/plugin_system/canvas/model/code_runners.dart';
import 'package:bruig/plugin_system/canvas/model/code_starters.dart';
import 'package:bruig/plugin_system/canvas/model/code_timing.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/data_styles.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_performance.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/play_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/font_files.dart';
import 'package:bruig/plugin_system/canvas/model/fretting.dart' show FretPlace, placesAt;
import 'package:bruig/plugin_system/canvas/model/instances.dart' show CopyValue, ElementInstance, InstanceSet, deviceOwnKey;
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/layout_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/layout_sync.dart';
import 'package:bruig/plugin_system/canvas/model/lip_sync.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart';
import 'package:bruig/plugin_system/canvas/model/midi_file.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/modulation.dart' show macroValue;
import 'package:bruig/plugin_system/canvas/model/motion.dart' show ClipTriggerKind, ElementMotion, MotionKind;
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart' show MotionPhase;
import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:bruig/plugin_system/canvas/model/musicxml.dart';
import 'package:bruig/plugin_system/canvas/model/notation.dart' show splitKey;
import 'package:bruig/plugin_system/canvas/model/note_tools.dart';
import 'package:bruig/plugin_system/canvas/model/own_motion.dart';
import 'package:bruig/plugin_system/canvas/model/page_style.dart';
import 'package:bruig/plugin_system/canvas/model/pattern_counts.dart';
import 'package:bruig/plugin_system/canvas/model/pitch_edit.dart' show PitchEdit;
import 'package:bruig/plugin_system/canvas/model/play.dart' show ControlAction, GameSoundElement, GameSoundSlot, GameSoundStop, gameSoundOf, gameSoundStop;
import 'package:bruig/plugin_system/canvas/model/responsive_layout.dart';
import 'package:bruig/plugin_system/canvas/model/score_channels.dart';
import 'package:bruig/plugin_system/canvas/model/score_roll.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/model/sheet_files.dart';
import 'package:bruig/plugin_system/canvas/model/sheet_reshape.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart' show Heard, SpeakerGroup;
import 'package:bruig/plugin_system/canvas/model/synth_channels.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:bruig/plugin_system/canvas/model/text_looks.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/vector_brush.dart';
import 'package:bruig/plugin_system/canvas/model/vector_text.dart';
import 'package:bruig/plugin_system/canvas/render/audio_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart' show CodeShow, codeShowOf, codeLineHeight, codeScrollRoom, codeShownScroll;
import 'package:bruig/plugin_system/canvas/render/code_run_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_task_painter.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/render/metronome_painter.dart' show MetronomeShow, metronomeShowOf;
import 'package:bruig/plugin_system/canvas/render/motion_document.dart' show cameraFraming, designedNow, cameraHalfExtents, cameraLookAt, LiveMotion, MotionPreview, PointerLive, cameraOf, facesPointer, isStageScene, motionSoundPeaks, placedPlaying, poseWithMotion, sceneFraming, settledFrameOf;
import 'package:bruig/plugin_system/canvas/render/play_task_painter.dart';
import 'package:bruig/plugin_system/canvas/render/render_caches.dart';
import 'package:bruig/plugin_system/canvas/render/scene_sequence.dart';
import 'package:bruig/plugin_system/canvas/render/score_sheet.dart';
import 'package:bruig/plugin_system/canvas/render/sheet_painter.dart';
import 'package:bruig/plugin_system/canvas/render/sound_placement.dart';
import 'package:bruig/plugin_system/canvas/render/sprite_painter.dart' show spritePaintingOf;
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/render/synth_module_painter.dart' show SynthShow, synthShowOf, synthPanelFor, synthPanelFit, synthPanelOf;
import 'package:bruig/plugin_system/canvas/render/synth_task_painter.dart' show synthTaskLayout, synthTaskScale;
import 'package:bruig/plugin_system/canvas/render/team_painter.dart';
import 'package:bruig/plugin_system/canvas/render/tile_map_painter.dart' show tileMapEditingOf;
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/controller/view_types.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/image_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/image_masking.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/sprite_painting.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/tile_painting.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_items.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_shapes.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart' show newElement, newInstrument, synthRack, synthModule, codeFontFor;
import 'package:bruig/plugin_system/canvas/ui/game/canvas_game.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/motion_editing.dart' show MotionEditing, motionId, everyMotion;
import 'package:bruig/plugin_system/canvas/ui/motion/motion_player.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/asset_elements.dart' show channelClip;
import 'package:bruig/plugin_system/canvas/ui/picking/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/sound/element_sound.dart' show ownChannelOf, soundOwnerOf;
import 'package:bruig/plugin_system/canvas/ui/timeline/row_header.dart' show givenRowColour;
import 'package:bruig/plugin_system/canvas/ui/timeline/timeline_view.dart';

// The view's own types (CanvasTool, CanvasFit, the zoom's limits), so
// whatever imports the controller has them.
export 'package:bruig/plugin_system/canvas/ui/controller/view_types.dart';

part 'controller/view_settings.dart';
part 'controller/element_editing.dart';
part 'controller/brushwork.dart';
part 'controller/motion_picks.dart';
part 'controller/chain_panel.dart';
part 'controller/dock_layout.dart';
part 'controller/movement.dart';
part 'controller/staging.dart';
part 'controller/saving.dart';

// The controller's methods live, by area, as extensions in parts of this
// library; its state stays in the class, where every part can reach it.
part 'controller/timeline_types.dart';
part 'controller/clip_play.dart';
part 'controller/pictures.dart';
part 'controller/vectors.dart';
part 'controller/scenes.dart';
part 'controller/playback.dart';
part 'controller/instruments.dart';
part 'controller/session.dart';
part 'controller/game.dart';
part 'controller/speech.dart';
part 'controller/text_styles.dart';
part 'controller/channels.dart';
part 'controller/panels.dart';
part 'controller/chain_views.dart';
part 'controller/clip_editing.dart';
part 'controller/piano_roll.dart';
part 'controller/lanes.dart';
part 'controller/mixer.dart';
part 'controller/keyframes.dart';
part 'controller/timeline_clips.dart';
part 'controller/copies.dart';
part 'controller/cast.dart';
part 'controller/scores.dart';
part 'controller/synths.dart';
part 'controller/metronomes.dart';
part 'controller/codes.dart';
part 'controller/code_runs.dart';
part 'controller/code_tasks.dart';
part 'controller/play_tasks.dart';
part 'controller/layouts.dart';
part 'controller/data_views.dart';
part 'controller/data_sheets.dart';

// canvas_controller.dart holds everything about the canvas being edited
// that is not the document itself: the selection, the playhead, the zoom,
// the undo history and whether any of it has been saved.
//
// The document is immutable, so every edit goes through [apply], the only
// place it is replaced: undo is a list of past documents, and an edit
// cannot half-happen.

/// _maxUndo bounds the history. Documents share unchanged elements, so it
/// can be generous; it is bounded only so it cannot grow without limit.
const int _maxUndo = 120;

/// _pinnedAt is [track] with [channels] pinned at [frame], keeping
/// whatever else that frame already holds.
ElementTrack _pinnedAt(
    ElementTrack track, int frame, Map<String, double> channels) {
  var at = track.keyAt(frame) ?? track.restingAt(frame);
  return track.withKey(at.copyWith(values: {...at.values, ...channels}));
}

/// FetchedRows is an element's last refresh this sitting, kept so the
/// mapping controls can change column without asking the source again.
class FetchedRows {
  /// fields is every path that led to a value in the first record.
  final List<String> fields;

  /// rows is the mapped table, and raw the same rows with the dates still in
  /// them, for a chart choosing its points by date.
  final List<List<String>> rows;
  final List<List<String>> raw;

  const FetchedRows(this.fields, this.rows, this.raw);
}

/// mixerMasterKey is the master strip where a channel's key is wanted.
const mixerMasterKey = "\u0000master";

/// CanvasController is the editing session. What it does is in the
/// extension parts under controller/, one a feature; a feature's own state is
/// in a class at the end of its part (_VectorState, _PlaybackState...), and
/// what several share is here. Widgets listen to it, or to [chrome] where
/// they show nothing that moves with a drag or a frame of play.
class CanvasController extends ChangeNotifier {
  CanvasController(CanvasDocument document,
      {AudioEngine? audioEngine, FrameSource? frameSource})
      : _document = document,
        _audioEngine = audioEngine,
        _frameSource = frameSource {
    // A task card's pattern counted off the UI isolate: drawn again.
    PatternCounts.counted.addListener(_patternCounted);
    _hookOwners.add(this);
    _takeHooks();
  }

  /// _hookOwners are the sessions alive, the newest last. The painters reach
  /// the session through hooks (synthShowOf, codeShowOf...) of which the app
  /// has one each, so they answer for the newest session: a canvas played in
  /// Files while the editor's is open behind it. When that one is shut,
  /// [dispose] hands the hooks back to the one before, or the editor's
  /// panels would go on asking a session that has gone.
  static final List<CanvasController> _hookOwners = [];

  /// _takeHooks points the painters' hooks at this session.
  void _takeHooks() {
    // Follow sound reads the recordings this canvas reads.
    motionSoundPeaks = (id) => waveformOf(id);
    // An instrument of slices plays a stored sound.
    sliceAudioReader = (id) => CanvasController.clipAudio(id);
    // A sheet's playbar shows pause while this canvas plays.
    sheetPlaying = () => playing;
    // The synth modules on the stage: their keys held, their time.
    synthShowOf = synthShowFor;
    metronomeShowOf = metronomeShowFor;
    codeShowOf = codeShowFor;
    codeRunShowOf = codeRunShowFor;
    codeTaskShowOf = codeTaskShowFor;
    playTaskShowOf = playTaskShowFor;
  }

  CanvasDocument _document;
  CanvasDocument get document => _document;

  /// lastFetched is what each element's last refresh returned, by element id.
  /// Held here because two panel sections run a refresh; not a global, which
  /// would outlive its canvas and mix up ids. Not saved: it is about this
  /// sitting, and forgotten when another canvas is opened.
  final Map<String, FetchedRows> lastFetched = {};

  final CanvasImageStore images = CanvasImageStore();

  final List<CanvasDocument> _undo = [];
  final List<CanvasDocument> _redo = [];

  /// _interaction is the document as a drag began: the gesture's undo step.
  CanvasDocument? _interaction;

  Set<String> _selection = {};
  Set<String> get selection => _selection;

  bool _backgroundSelected = false;

  /// backgroundSelected is whether the canvas's own background is being
  /// edited. A flag rather than a sentinel id in [selection], so delete,
  /// duplicate and nudge need not skip it; exclusive with the selection.
  bool get backgroundSelected => _backgroundSelected;

  void selectBackground() {
    if (_backgroundSelected && _selection.isEmpty) return;
    _selection = {};
    _backgroundSelected = true;
    notifyListeners();
  }

  int _frame = 0;
  int get frame => _frame;

  double _zoom = 1;

  /// zoom is a multiple of the size at which the canvas fills its area, not
  /// of the document's pixels, so 1 is always the whole canvas. The fitted
  /// size is worked out by CanvasStage, the only thing that knows the room.
  double get zoom => _zoom;

  /// _fitScale is what the stage last reported: how much the canvas is
  /// shrunk to fill the window before any zoom. See [viewScale].
  double _fitScale = 1;

  /// viewScale is document pixels to screen pixels, what the band's
  /// percentage means: not [zoom], which is 1 whenever the canvas fits.
  double get viewScale => _fitScale * _zoom;

  /// reportFitScale is the stage reporting how much room it found. Notifies
  /// only when the answer changes, since it is called on every layout.
  void reportFitScale(double value) {
    if (!value.isFinite || value <= 0) return;
    if ((value - _fitScale).abs() < 0.0001) return;
    _fitScale = value;
    _notifyView();
  }

  /// setViewScale zooms so one document pixel is [value] screen pixels.
  void setViewScale(double value) {
    if (!value.isFinite || value <= 0 || _fitScale <= 0) return;
    zoom = value / _fitScale;
  }

  /// atFit is whether the view shows the whole canvas untouched (Fit lit).
  bool get atFit => (_zoom - 1).abs() < 0.001 && _pan.dx == 0 && _pan.dy == 0;

  /// pan is the view: the page's middle from the window's, in screen pixels.
  Offset _pan = Offset.zero;
  Offset get pan => _pan;

  /// revision counts every change to the document rather than the view of
  /// it. The sidebar watches it, so panning, zooming and hovering do not lay
  /// out its fields again. Every notification moves it except those through
  /// [_notifyView], so a forgotten case costs a rebuild, not a stale panel.
  int get revision => _revision;
  int _revision = 0;

  /// _viewOnly is set only while [_notifyView] is running.
  bool _viewOnly = false;

  /// _playbackState is the state playback.dart keeps: see _PlaybackState.
  final _PlaybackState _playbackState = _PlaybackState();

  /// chrome tells of every change but the two that come many times a
  /// second: the playhead stepping on in play, and a gesture's edits as it
  /// goes (a drag, typing on the canvas). What shows neither -- the band's
  /// buttons, the play bar, the page's layout -- listens here rather than to
  /// the controller, so a drag redraws the canvas and not the buttons round
  /// it. Both end in an ordinary notification (endInteraction, pause), and
  /// chrome catches up then.
  Listenable get chrome => _chrome;
  final _Chrome _chrome = _Chrome();

  /// _rapid is set only while one of those two is being told of.
  bool _rapid = false;

  /// _notifyRapid tells listeners of a change [chrome] passes over.
  void _notifyRapid({bool view = false}) {
    _rapid = true;
    try {
      view ? _notifyView() : notifyListeners();
    } finally {
      _rapid = false;
    }
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    // A drawing is edited only while it is the one thing selected: undo,
    // delete or a pruned selection ends the editing.
    var editing = _vectorEditing;
    if (editing != null &&
        (_backgroundSelected ||
            _selection.length != 1 ||
            _selection.first != editing ||
            _document.elementById(editing) is! VectorElement)) {
      _vectorEditing = null;
      _resetVectorEditing();
    }
    // And a picture's layers, by the same rule.
    var picture = _imageEditing;
    if (picture != null &&
        (_backgroundSelected ||
            _selection.length != 1 ||
            _selection.first != picture ||
            _document.elementById(picture) is! ImageElement)) {
      _imageEditing = null;
      _imageLayer = baseLayerId;
      _imageSolo = false;
    }
    if (_imageEditing != null && editingImage?.layerById(_imageLayer) == null) {
      _imageLayer = baseLayerId;
    }
    if (_imageEditing != null) {
      var e = editingImage!;
      _alsoPicked.removeWhere((id) => e.layerById(id) == null);
    }
    // Picked copies last only while their element is the one thing selected.
    if (_copiesOf case var of?
        when _selection.length != 1 || _selection.first != of) {
      _copiesOf = null;
      _pickedCopies = {};
      _allCopiesChosen = false;
      if (_placingCopies == of) _placingCopies = null;
    }
    if (!_viewOnly) _revision++;
    super.notifyListeners();
    if (!_rapid) _chrome.tell();
  }

  /// arrived redraws the settings once something they draw has loaded.
  void arrived() => notifyListeners();

  /// restoreFit puts back the frame last chosen, without notifying: it is
  /// called from initState, and notifying during a build throws. The same
  /// frame as now changes nothing, so coming back to the page finds the
  /// zoom and pan as they were left; another frame starts from the whole of
  /// it, as [fit]'s setter does.
  void restoreFit(CanvasFit value) {
    if (value == _fit) return;
    _fit = value;
    _zoom = 1;
    _pan = Offset.zero;
  }

  /// _notifyView tells listeners the view moved (zoom, pan, framing, tool)
  /// without claiming the document changed.
  void _notifyView() {
    _viewOnly = true;
    try {
      notifyListeners();
    } finally {
      _viewOnly = false;
    }
  }

  CanvasFit _fit = CanvasFit.whole;

  // ---- controller/view_settings.dart --------------------------------------

  CanvasRulers _rulers = const CanvasRulers();

  bool _autoKeyframe = false;

  bool _showOverspill = false;

  bool _showHelpers = true;

  bool _showAllBounds = false;

  bool _lockJoins = false;

  bool _hideJoins = false;

  // ---- controller/element_editing.dart ------------------------------------

  int? _focusedPlayer;

  // ---- controller/brushwork.dart ------------------------------------------

  RetouchBrush _retouch = RetouchBrush.off;

  /// _pendingStroke is a stroke drawn but not applied, on _pendingPicture.
  /// Held so it redraws as the brush settings change until it is applied.
  List<Offset>? _pendingStroke;
  String? _pendingPicture;

  /// _pendingKeeps, _pendingTeaches and _pendingFills are what the brush was
  /// doing when the stroke was drawn: changing brush starts something else.
  bool _pendingKeeps = false;
  bool _pendingTeaches = false;
  bool _pendingFills = false;

  double _brushHardness = 0.35;

  bool _cutInside = false;

  /// _brushSnap starts at nothing: clinging is an aid to reach for on
  /// purpose, and on by default it makes the brush look broken.
  double _brushSnap = 0;

  double _brushSize = 0.05;

  // ---- controller/view_settings.dart --------------------------------------

  bool _pageLocked = false;

  StageTool _stageTool = StageTool.move;

  StageNav _stageNav = StageNav.all;

  // What is picked of an element's clips, and which panels show them. The
  // editing itself is in motion_editing.dart.

  // ---- controller/motion_picks.dart ---------------------------------------

  String? _pickedMotion;
  String? _pickedPlacement;

  /// _pickedOf is the element the picked clip is on.
  String? _pickedOf;

  Set<(String, String)> _motionPicks = const {};

  /// _ownTab is the Motion clips card's Arrive, Loop or Leave picked where
  /// it has no clip (unset, or the loop, which plays without one); its
  /// Preset is set there. Picking a clip lets it go.
  MotionKind? _ownTab;

  /// _clipSettings are the elements whose preset shows its clip's own
  /// settings (speed, layer, mix, name) on the Motion clips card.
  final Set<String> _clipSettings = {};

  int? _pickedScene;

  /// _joinPicked is whether the scene picked was picked by its transition's
  /// slot: that join's own transition, even on the master (see pickJoin).
  bool _joinPicked = false;

  /// _joinPress is a transition's slot pressed, for the press it is in:
  /// the Scenes strip's own pick passes it by (see pickJoin).
  bool _joinPress = false;

  /// _previewJoin is the join whose transition is being previewed (see
  /// previewTransitionAfter), or null.
  int? _previewJoin;
  Set<String> _pickedSceneWith = const {};

  // ---- controller/chain_panel.dart ----------------------------------------

  String? _chainFocus;

  bool _chainMeters = true;

  bool _chainBadges = true;

  bool _chainMacros = true;

  bool _motionTrail = true;

  // ---- controller/dock_layout.dart ----------------------------------------

  /// _dockState is which panels under the canvas are open, the mixer's
  /// size and the Chain's view (model/dock_layout.dart). Changed through
  /// _openPanel, _closePanel and _showChain in controller/dock_layout.dart,
  /// which keep one panel to a place.
  DockState _dockState = const DockState();

  bool _barBelow = false;

  bool _trackpadScrolls = false;

  /// timelineZoomAsked counts the play bar's requests to zoom the timeline
  /// by timelineZoomFactor (0: to the whole scene). With no timeline open,
  /// a request is dropped.
  int timelineZoomAsked = 0;
  double timelineZoomFactor = 1;

  DockLayout _dock = const DockLayout();

  String? _arrangementChosen;

  TimelineShow _timelineShow = TimelineShow.everything;

  /// slotCellWidth and slotCellHeight are a slot's fixed size by the rows.
  static const double slotCellWidth = 72, slotCellHeight = 22;

  CanvasDocument? _slotsShownOf;
  int _slotsShownCount = 2;

  /// lastSlotUsed is the last cue row anything in [doc] uses, or -1.
  static int lastSlotUsed(CanvasDocument doc) {
    var last = -1;
    var grid = doc.session;
    for (var (i, name) in grid.scenes.indexed) {
      if (name.isNotEmpty) last = math.max(last, i);
    }
    for (var list in grid.slots.values) {
      for (var i = list.length - 1; i > last; i--) {
        if (list[i] != null) {
          last = i;
          break;
        }
      }
    }
    for (var e in [...doc.elements, ...?doc.master?.elements]) {
      var slots = e.base.motion.slots;
      for (var i = slots.length - 1; i > last; i--) {
        if (slots[i].isNotEmpty) {
          last = i;
          break;
        }
      }
    }
    return last;
  }

  /// _slotRowsGrown adds a cue to [next] when its last is used (slotsShown).
  static CanvasDocument _slotRowsGrown(CanvasDocument next) {
    var rows = next.session.rows;
    if (rows >= 256 || lastSlotUsed(next) < rows - 1) return next;
    return next.copyWith(session: next.session.withScene());
  }

  double _slotsColumn = slotsColumnDefault;
  static const double slotsColumnDefault = 6 * (slotCellWidth + 3) + 5,
      slotsColumnMin = slotCellWidth + 3 + 5,
      slotsColumnMax = 1600;

  /// slotsScroll is how far all the slots beside the rows are scrolled: its
  /// own notifier, so a scroll redraws the slots and nothing else.
  final ValueNotifier<double> slotsScroll = ValueNotifier(0);

  // ---- controller/view_settings.dart --------------------------------------

  CanvasTool _tool = CanvasTool.select;

  /// hoveredButton is the button under the pointer, so hover colours show.
  String? hoveredButton;

  Timer? _playback;
  bool get playing => _playback != null;

  bool _opened = false;

  /// opened is whether this session has been shown. The session outlives
  /// the page, so only the first visit restores the last save.
  bool get opened => _opened;

  /// loads counts the canvases opened in this session (load). What the page
  /// keeps about one canvas changes hands when it goes up: see KeptView.
  int get loads => _loads;
  int _loads = 0;

  /// markOpened is called by the page as it builds.
  void markOpened() => _opened = true;

  /// folder and name are where this document is saved, or null when it has
  /// never been saved. Save writes back to them; Save As changes them.
  String? folder;
  String? name;

  /// _edits counts changes; _savedEdits is the count the file on disk has.
  /// A count rather than a flag, so an edit made while a save is being
  /// written is not marked saved when the write finishes.
  int _edits = 0, _savedEdits = 0;
  bool get _dirty => _edits != _savedEdits;

  /// dirty is whether the file on disk lacks changes. Counted by [apply]
  /// rather than comparing documents, which is costly on every keystroke;
  /// an edit back to the saved state is still an edit.
  bool get dirty => _dirty;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// selectedElements are the chosen elements in paint order.
  List<CanvasElement> get selectedElements => [
        for (var e in _document.elements)
          if (_selection.contains(e.id)) e
      ];

  /// selected is the one chosen element, or null when none or several are.
  CanvasElement? get selected =>
      _selection.length == 1 ? _document.elementById(_selection.first) : null;

  // ------------------------------------------------------------------------
  // Editing
  // ------------------------------------------------------------------------

  /// _glideCharts starts a glide (chart_play.dart) for each chart whose
  /// numbers change from [was] to [next], so it eases rather than jumps, and
  /// keeps the stage drawing while any glides.
  void _glideCharts(CanvasDocument was, CanvasDocument next) {
    if (identical(was.elements, next.elements)) return;
    var before = {
      for (var e in was.elements)
        if (e is ChartElement) e.id: e
    };
    var started = false;
    if (!_glideListening) {
      _glideListening = true;
      chartGlideBeat.addListener(_glideBeat);
    }
    for (var e in next.elements) {
      if (e is! ChartElement) continue;
      var old = before[e.id];
      if (old == null ||
          old.data.series.isEmpty ||
          identical(old.data, e.data)) {
        continue;
      }
      if (sameData(old.data, e.data) || old.type != e.type) continue;
      // From what it is drawn as now: part-way, if it is already gliding.
      startGlide(e.id, glided(e.id, old.data));
      started = true;
    }
    // A frame to start it; chartGlideBeat asks for the rest.
    if (started) keysHeld.value++;
  }

  bool _glideListening = false;

  /// _glideBeat passes chart_play's beat to the stage, as keysHeld.
  void _glideBeat() => keysHeld.value++;

  void _patternCounted() => notifyListeners();

  /// _synthSeen is the document synthSynced last returned: what it compares
  /// the next with, so an edit touching no synth part skips it.
  CanvasDocument? _synthSeen;

  /// apply replaces the document, pushing the old one onto the undo history.
  /// [transient] skips the history, for the many small changes inside one
  /// gesture; [beginInteraction] already remembered where it started.
  void apply(CanvasDocument next, {bool transient = false}) {
    _endPreview();
    if (identical(next, _document)) return;
    // A linked copy changed in what it shares changes its Cast member, and
    // every other copy with it (see cast.dart).
    next = castSynced(_document, next);
    // What is docked in a Layout's cells goes where they go.
    next = layoutsSynced(_document, next);
    // Each synth speaker's channel plays the patch its modules make.
    var designing = next;
    next = _synthSeen = synthSynced(next,
        designedAt: (e, f) => designedNow(e, f, designing),
        since: _synthSeen);
    // Each Data element shows its sheet, and its own data changes go into
    // the sheet (data_sync.dart); a sheet made from another follows it
    // first (sheet_reshape.dart).
    next = sheetsMade(_document, next);
    next = dataSynced(_document, next);

    // A picture's frame grows to its content once a change is made, not at
    // each step of a drag, whose sums start from where it began.
    if (!transient) next = _slotRowsGrown(_imagesGrown(next, _document));

    var was = _document;
    if (!transient && _interaction == null) {
      _undo.add(_document);
      if (_undo.length > _maxUndo) _undo.removeAt(0);
      _redo.clear();
    }

    _glideCharts(_document, next);
    _document = next;
    _edits++;
    scheduleAutosave();

    // Prune ids the document no longer has, so no reader meets one.
    _selection = _selection.where((id) => _document.elementById(id) != null).toSet();

    if (_frame >= _document.frames) _frame = _document.frames - 1;

    // A sound whose element has gone goes with it, and one on the timeline
    // goes where its new settings put it.
    _audioFollowsPage(turned: false);
    _syncTimeline();
    _scheduleParts();
    if (!transient && _interaction == null) _followEdits(was);

    // A step of a gesture: endInteraction tells chrome when it is done.
    transient && _interaction != null ? _notifyRapid() : notifyListeners();
  }

  /// _imagesGrown is [next] with every picture changed since [was] grown to
  /// fit what is drawn in it (ImageElement.grownToFit).
  CanvasDocument _imagesGrown(CanvasDocument next, CanvasDocument was) {
    var out = next;
    for (var e in next.elements) {
      if (e is! ImageElement || e.clip || !e.layered) continue;
      if (identical(was.elementById(e.id), e)) continue;
      var grown = e.grownToFit();
      if (!identical(grown, e)) out = out.withElement(grown);
    }
    return out;
  }

  /// interacting is whether a gesture is under way: drawn a little faster.
  bool get interacting => _interaction != null;

  /// beginInteraction starts a gesture: one undo step until [endInteraction].
  void beginInteraction() {
    _endPreview();
    _interaction ??= _document;
  }

  /// endInteraction closes the gesture as one undo step, if anything changed.
  void endInteraction() {
    var before = _interaction;
    _interaction = null;
    if (before == null || identical(before, _document)) return;
    // In the same step as the gesture: a layer dragged out of the frame and
    // the frame grown round it are one thing to take back.
    var grown = _imagesGrown(_document, before);
    if (!identical(grown, _document)) {
      _document = grown;
      _edits++;
      scheduleAutosave();
    }
    _undo.add(before);
    if (_undo.length > _maxUndo) _undo.removeAt(0);
    _redo.clear();
    _followEdits(before);
    notifyListeners();
  }

  void undo() {
    _endPreview();
    // Close an open gesture first, so it is the step taken back.
    endInteraction();
    if (_undo.isEmpty) return;
    _redo.add(_document);
    var before = _document;
    _document = _undo.removeLast();
    _edits++;
    scheduleAutosave();
    _selection = _selection.where((id) => _document.elementById(id) != null).toSet();
    if (_frame >= _document.frames) _frame = _document.frames - 1;
    _followEdits(before);
    notifyListeners();
  }

  void redo() {
    _endPreview();
    endInteraction();
    if (_redo.isEmpty) return;
    _undo.add(_document);
    var before = _document;
    _document = _redo.removeLast();
    _edits++;
    scheduleAutosave();
    _selection = _selection.where((id) => _document.elementById(id) != null).toSet();
    if (_frame >= _document.frames) _frame = _document.frames - 1;
    _followEdits(before);
    notifyListeners();
  }

  /// _beforePreview is the real document while tryElement shows a setting.
  CanvasDocument? _beforePreview;

  // ---- controller/element_editing.dart ------------------------------------

  /// _clipboard is what was last copied. Not the system clipboard: an
  /// element has no sensible text form, and JSON would replace what the
  /// reader copied elsewhere. Static, so a copy survives leaving the page.
  static List<CanvasElement> _clipboard = const [];

  /// _pasteOffset steps each paste down and right, so it is visibly a copy.
  static const double _pasteOffset = 16;

  // ------------------------------------------------------------------------
  // Selection
  // ------------------------------------------------------------------------

  // ---- picture layers ----------------------------------------------------

  String? _imageEditing;

  /// _pictures is the state pictures.dart keeps: see _PictureState.
  final _PictureState _pictures = _PictureState();

  /// _alsoPicked are the layers picked with [imageLayer], in pick order, for
  /// the align tools and a drag; the settings are the first one's.
  final List<String> _alsoPicked = [];

  bool _imageSolo = false;

  // ---- brushwork ----------------------------------------------------------

  Offset? cloneOffset;

  // ---- vector editing ----------------------------------------------------

  String? _vectorEditing;

  /// _soloHook and _sheetMarksHook are this controller's answers to the
  /// painters' hooks (vectorSoloOf, sheetMarksOf), each made once: a method
  /// of an extension torn off is a new closure every time, never equal to
  /// the last, so the hook could not otherwise be recognised to take down.
  late final int? Function(VectorElement) _soloHook = _soloOf;
  late final SheetMarks Function(SheetElement) _sheetMarksHook = _sheetMarks;

  /// _gameKeyHook and _waitKeyHook are the keyboard handlers a game and a
  /// waiting stop put up, made once for the same reason: HardwareKeyboard
  /// takes a handler down only when handed the one it was given.
  late final bool Function(KeyEvent) _gameKeyHook = _gameKey;
  late final bool Function(KeyEvent) _waitKeyHook = _waitKey;

  /// _vectors is the state vectors.dart keeps: see _VectorState.
  final _VectorState _vectors = _VectorState();

  SpritePaintSession? _spritePaint;

  TilePaintSession? _tilePaint;

  /// studio3dOpen is whether the Character Studio has the page, in place of
  /// the canvas (character_studio_3d.dart).
  final ValueNotifier<bool> studio3dOpen = ValueNotifier(false);

  /// scoreStudio is the score the Score Studio has the page for, by id, or
  /// null while the canvas has it (score_studio.dart).
  final ValueNotifier<String?> scoreStudio = ValueNotifier(null);

  /// codeStudio is the Code panel the Code Studio has the page for, by id,
  /// or null for the canvas. See code_studio.dart.
  final ValueNotifier<String?> codeStudio = ValueNotifier(null);

  /// dataStudio is the sheet the Data Studio is open on, or null while it
  /// is shut; dataStudioView the Data element it opened with picked.
  final ValueNotifier<String?> dataStudio = ValueNotifier(null);
  String? dataStudioView;

  /// _rangeEnd is the frame a sheet's range of bars stops playing at (see
  /// playSheet), or null.
  int? _rangeEnd;

  /// studio3dElement is the 3D character the Studio was opened for, if any.
  String? studio3dElement;

  Set<String> _offCanvas = const {};

  // ---- scenes -------------------------------------------------------------

  bool _playAll = false;

  int? _previewAt;

  /// _previewEnd is where the preview stops, so a transition does not run on.
  int _previewEnd = 0;

  /// _previewFrom is the scene the preview started on, returned to after it.
  int? _previewFrom;

  /// _previewFromMaster is whether the master was open as the preview began.
  bool _previewFromMaster = false;

  // ------------------------------------------------------------------------
  // Cues -- see model/canvas_cues.dart.

  /// _wordQuery is what an element's cue card searches the words for. Unsaved.
  String _wordQuery = "";

  /// _sceneFrames is where the playhead was on each scene when last left, by
  /// scene id: where somebody is, so not in the document.
  final Map<String, int> _sceneFrames = {};

  /// _sceneClipboard is the scene last copied: static, like [_clipboard], so
  /// it pastes into another canvas.
  static CanvasScene? _sceneClipboard;

  static bool get hasCopiedScene => _sceneClipboard != null;

  /// forgetCopiedScene empties it, for tests, as the clipboard is static.
  @visibleForTesting
  static void forgetCopiedScene() => _sceneClipboard = null;

  bool _cameraView = false;

  // ------------------------------------------------------------------------
  // View
  // ------------------------------------------------------------------------

  set zoom(double value) {
    var next = value.clamp(minZoom, maxZoom);
    if (next == _zoom) return;
    // Scale the pan with the page, so the window's middle stays put.
    var f = next / _zoom;
    _pan = Offset(_pan.dx * f, _pan.dy * f);
    _zoom = next;
    // Back at the fit, re-centre, or an earlier pan leaves it off-centre.
    if ((_zoom - 1).abs() < 0.001) _pan = Offset.zero;
    _notifyView();
  }

  set pan(Offset value) {
    _pan = value;
    _notifyView();
  }

  // ------------------------------------------------------------------------
  // Playback
  // ------------------------------------------------------------------------

  set frame(int value) {
    var next = value.clamp(0, math.max(0, _document.frames - 1)).toInt();
    // A playhead moved by hand ends a transition it was stepped into (see
    // goToRunFrame).
    if (_playAll && _previewFrom == null && !playing && _previewAt != null) {
      _previewAt = null;
      notifyListeners();
    }
    if (next == _frame) return;
    if (!playing) _forgetCodePicks();
    _frame = next;
    _syncTimeline();
    notifyListeners();
  }

  // ------------------------------------------------------------------------
  // The control bar's switches
  // ------------------------------------------------------------------------

  /// _mainBands are the bands one of which always shows: a mixer of send
  /// dials alone, or of nothing, is only its names.
  static const _mainBands = [
    MixerSection.clips,
    MixerSection.devices,
    MixerSection.mixer,
  ];

  final Set<String> _narrowStrips = {};

  /// clockForTest stands in for the playback clock, in microseconds since
  /// Play, and tickClockForTest is a tick of the timer against it -- so a
  /// test can make a tick late without waiting for one to be.
  @visibleForTesting
  int Function()? clockForTest;

  // ------------------------------------------------------------------------
  // Live counters
  // ------------------------------------------------------------------------

  final Map<String, DateTime> _countersSince = {};

  Timer? _counterTimer;

  // ------------------------------------------------------------------------
  // Sound
  // ------------------------------------------------------------------------

  final AudioEngine? _audioEngine;
  AudioRuntime? _audio;

  final FrameSource? _frameSource;
  VideoRuntime? _video;

  // ------------------------------------------------------------------------
  // Instruments
  // ------------------------------------------------------------------------

  /// _instruments is the state instruments.dart keeps: see _InstrumentState.
  final _InstrumentState _instruments = _InstrumentState();

  /// _metroStarted is when each running metronome started on _metroClock,
  /// by id; _metroTick redraws them; _metroTaps are each one's last taps.
  final Map<String, double> _metroStarted = {};
  final Stopwatch _metroClock = Stopwatch();
  Timer? _metroTick;
  final Map<String, List<double>> _metroTaps = {};

  /// _codePicked is the tab each pane of each Code panel was shown by hand
  /// while paused, by element id and pane; _codePane the pane last pressed;
  /// _codeEditing the pane the stage's editor is open on.
  final Map<String, Map<int, String>> _codePicked = {};
  final Map<String, int> _codePane = {};
  (String, int)? _codeEditing;

  /// _codeFull are the Code panels showing the whole of their code, and
  /// _codeScroll each pane scrolled by hand, in lines.
  final Set<String> _codeFull = {};

  /// _codeRanNow are the Run panels run by hand since the playhead last
  /// moved: their runs shown now, whatever the scene's clock says.
  final Set<String> _codeRanNow = {};

  /// _codeRunHere are the Run panels run on this machine since the canvas
  /// was opened. Only these are opened live (see liveCode): a received
  /// canvas's run, kept with it, is a picture until Run is pressed here.
  final Set<String> _codeRunHere = {};
  final Map<String, Map<int, double>> _codeScroll = {};

  /// _codeRuns are the Run panels running now, by id, and what each printed.
  final Map<String, List<CodeLog>> _codeRuns = {};

  /// _codeLive is the Run panel open live, by id, and what it has printed;
  /// codeLiveSnap takes its picture, set by the stage's live preview.
  (String, List<CodeLog>)? _codeLive;
  Future<List<int>?> Function()? codeLiveSnap;

  /// _codeTaskChecks is each task card's last check: the code it was made
  /// against (a fingerprint) and whether that built; _codeTaskBusy the
  /// cards checking now.
  final Map<String, (int, bool?)> _codeTaskChecks = {};

  /// _playTasks is how far each play task card has got (play_tasks.dart).
  final _playTasks = _PlayTaskState();

  /// _layouts is the cell picked in each Layout (layouts.dart).
  final _layouts = _LayoutState();
  final Set<String> _codeTaskBusy = {};

  /// codeRunHost runs code for Run panels: set by the app (the browser and
  /// interpreters, see media/code_run_host.dart), a fake in the tests; null
  /// where code cannot be run.
  static CodeRunHost? codeRunHost;

  /// saveCodePicture keeps a run's preview picture, returning its asset id.
  static Future<String?> Function(List<int> png) saveCodePicture =
      (png) => CanvasAssets.save(png);

  /// _slowSheet is the sheet played off real time, its notes live (see
  /// playSheet); _slowHeld the keys it sounds, by channel.
  String? _slowSheet;
  final Map<String, Set<int>> _slowHeld = {};

  /// _synthPressed is each keyboard module's keys held, by element id.
  final Map<String, Set<int>> _synthPressed = {};

  /// _synthTarget lets go of a task card's target once it has been heard.
  Timer? _synthTarget;

  /// _synthWatches are the notes being watched on each speaker, by its
  /// id, for the screens (see PatchWatch); _synthTick plays them on and
  /// redraws, _synthClock how long since it last did.
  final Map<String, PatchWatch> _synthWatches = {};
  Timer? _synthTick;
  final Stopwatch _synthClock = Stopwatch();

  /// _synthSeconds is how long the screens have been ticking.
  double _synthSeconds = 0;

  static String _channelOf(AudioElement e) =>
      e.clip.channel.isEmpty ? e.id : e.clip.channel;

  final Set<String> _armed = {};

  final Map<String, Map<int, int>> _soundCount = {};

  /// _arps are the arpeggiators playing live, by element id.
  final Map<String, _LiveArp> _arps = {};

  bool _recording = false;

  final Map<String, List<MidiNote>> _taken = {};

  // ------------------------------------------------------------------------
  // The elements' slots: their clips launched live -- see motion_player.dart
  // ------------------------------------------------------------------------

  /// motionPlayer is what the elements' slots are playing.
  final MotionPlayer motionPlayer = MotionPlayer();

  /// _triggeredOff are the elements a trigger (scene start, click, key) took
  /// off their timelines this Play. Stop puts them back so the next Play
  /// starts as the canvas does; slot launches stay off until Back.
  final Set<String> _triggeredOff = {};

  /// _sessionState is the state session.dart keeps: see _SessionState.
  final _SessionState _sessionState = _SessionState();

  // ------------------------------------------------------------------------
  // The session view: clips launched live
  // ------------------------------------------------------------------------

  /// _clipChannels is what each channel plays from its slots, and will next.
  final Map<String, _ClipChannel> _clipChannels = {};

  /// _clipRecord is the clip being recorded into a slot, if one is.
  _ClipRecord? _clipRecord;

  /// _clipLog is what the slots have played since Record was pressed, to be
  /// written onto the timeline when it is let go.
  final List<_ClipPlayed> _clipLog = [];

  final Stopwatch _gameClockWatch = Stopwatch();

  /// gameClockForTest stands in for [_gameClock], in microseconds.
  @visibleForTesting
  int Function()? gameClockForTest;

  bool _sessionOnly = false;

  /// _sessionSeconds is the slots' own clock, playing on their own.
  double _sessionSeconds = 0;

  /// _sessionClock is the session's clock while the timeline plays: from the
  /// playhead at Play, one frame on per frame played. A Loop, a Jump or a
  /// new scene does not move it back, so clips waiting for a loop's end
  /// come and playing ones end.
  double _sessionClock = 0;

  /// _offTimeline are the channels that have left the timeline for their
  /// slots, as Ableton's tracks do: silent on the timeline from a clip's
  /// launch until Back to the timeline.
  final Set<String> _offTimeline = {};

  /// launchLevel is how loud [clip] plays launched at [velocity]: its
  /// Velocity's share of the way from full to the pad's.
  static double launchLevel(SessionClip clip, int velocity) =>
      1 - clip.velocity * (1 - velocity.clamp(0, 127) / 127);

  // ------------------------------------------------------------------------
  // Played as a game
  // ------------------------------------------------------------------------

  GameRun? _game;

  /// _gameState is the state game.dart keeps: see _GameState.
  final _GameState _gameState = _GameState();

  Timer? _gameTimer;
  bool _gamePaused = false;

  /// escStopsGame is whether Escape ends the game, as in the editor, or is
  /// left to a published game's player, where Escape leaves.
  bool escStopsGame = true;

  // ------------------------------------------------------------------------
  // Practising
  // ------------------------------------------------------------------------

  /// _practice is the Sheet music being practised, by id, while a take is
  /// going; the rest is how the take is going.
  String? _practice;
  final Set<int> _waiting = {};

  /// _mine is whether [n] is the player's to play: of the hand practised
  /// (the right from middle C up), and not in Listen.
  static bool _mine(SheetElement sheet, MidiNote n) =>
      sheet.mode != PracticeMode.listen &&
      switch (sheet.hands) {
        PracticeHands.right => n.key >= splitKey,
        PracticeHands.left => n.key < splitKey,
        PracticeHands.both => true,
      };

  /// partRenderer plays a part into WAV bytes and partStore keeps them,
  /// returning the file's id (part_render.dart): stand-ins for tests.
  @visibleForTesting
  static Future<Uint8List> Function(InstrumentPart part, {String? bankPath})
      partRenderer = partWav;
  @visibleForTesting
  static Future<String?> Function(Uint8List wav) partStore = _storePart;

  /// bankReady is whether the sound bank is here -- see soundBankReady.
  @visibleForTesting
  static Future<bool> Function() bankReady = soundBankReady;

  static Future<String?> _storePart(Uint8List wav) async {
    var dir = await Directory.systemTemp.createTemp("canvas-part");
    try {
      var file = File(path.join(dir.path, "part.wav"));
      await file.writeAsBytes(wav, flush: true);
      return await CanvasMedia.saveFile(MediaKind.audio, file.path);
    } finally {
      await dir.delete(recursive: true).catchError((_) => dir);
    }
  }

  Timer? _partTimer;

  /// _speechState is the state speech.dart keeps: see _SpeechState.
  final _SpeechState _speechState = _SpeechState();

  bool _disposed = false;

  // ---- The Speech device

  /// speechEngineFor is the engine a spec speaks with: Kokoro, or the
  /// expressive voices. Tests put a stand-in here.
  static SpeechEngine Function(SpeechSpec spec) speechEngineFor =
      (spec) => switch (spec.engine) {
            SpeechEngineKind.expressive => QwenSpeech(),
            SpeechEngineKind.local => KokoroSpeech(),
          };

  /// speechQueue is each channel's lines waiting to be spoken, by their
  /// lineKey: the first is being spoken now.
  final Map<String, List<String>> speechQueue = {};

  /// speechLineKey is what a line is known by while it waits: its words
  /// and how it is said, which a join, a split or an edit change.
  static String speechLineKey(SpeechLine l) =>
      "${l.direction.name}|${l.own}|${l.text}";

  static String _firstWords(String text) {
    var words = text.split(RegExp(r"\s+"));
    return words.length <= 6 ? text : "${words.take(6).join(" ")}…";
  }

  /// speechLibrary lists a spoken take in the Audio library as [name], and
  /// speechUnlist unlists one, keeping its file: stand-ins for tests.
  @visibleForTesting
  static Future<void> Function(String id, String name, double seconds)
      speechLibrary = (id, name, seconds) => CanvasLibrary.add(LibraryAsset(
          id: id,
          kind: AssetKind.audio,
          name: name,
          added: DateTime.now(),
          length: seconds));
  @visibleForTesting
  static Future<void> Function(String id) speechUnlist =
      (id) => CanvasLibrary.unlist(id);

  /// keepRecording keeps a recording made from another, such as a voice's
  /// notes moved in the Pitch editor, as a take is kept; answers its id.
  static Future<String?> keepRecording(Uint8List wav) => speechTakeStore(wav);

  /// speechTakeStore keeps a take's [wav] apart from the library, answering
  /// its id: listed only once saved or put on the timeline, and tidied once
  /// no canvas has it. A stand-in for tests.
  @visibleForTesting
  static Future<String?> Function(Uint8List wav) speechTakeStore =
      (wav) async {
    try {
      var id = "${sha256.convert(wav).toString().substring(0, 16)}.wav";
      var file = File(path.join(await CanvasStorage.speechTakesDir(), id));
      if (!await file.exists()) await writeWhole(file.path, wav);
      return id;
    } catch (e) {
      debugPrint("Unable to keep a take: $e");
      return null;
    }
  };

  // ---- Phrasing: a take's words shaped after it is spoken

  /// phrasingPicked are the words picked, by place in the take as spoken,
  /// for a drag or a setting to change; the settings show the first.
  Set<int> phrasingPicked = const {0};

  Timer? _shapeTimer;

  /// speechSplitAt is where section [text] splits: at the sentence end
  /// nearest its middle, else the comma, or null for none.
  static int? speechSplitAt(String text) {
    var body = text.isEmpty ? text : text.substring(0, text.length - 1);
    List<int> at(String marks) => [
          for (var m in RegExp("[$marks]\\s").allMatches(body)) m.start + 1
        ];
    var marks = at(".!?…");
    if (marks.isEmpty) marks = at(",;:");
    if (marks.isEmpty) return null;
    var middle = text.length / 2;
    return marks.reduce(
        (a, b) => (b - middle).abs() < (a - middle).abs() ? b : a);
  }

  /// _joinAway joins [sounds] (the chosen [takes], with pauses), finishes
  /// them and makes the WAV, on an isolate of its own.
  static Future<
      ({Uint8List wav, double seconds, List<TimedWord> words, bool exact})>
      _joinAway(List<Float32List> sounds, List<SpeechTake> takes, double speed,
          {required double room, required bool boost}) {
    var words = [for (var t in takes) t.words];
    var exact = [for (var t in takes) t.exact];
    return Isolate.run(() {
      var joined = finished(
          joinLines([
            for (var (i, s) in sounds.indexed)
              SpokenAudio(s, s, words[i], exact: exact[i]),
          ], speed),
          room: room,
          boost: boost);
      return (
        wav: wav16(joined.l, joined.r),
        seconds: joined.seconds,
        words: joined.words,
        exact: joined.exact,
      );
    });
  }

  /// joining is the channels whose lines are being joined into the clip.
  final Set<String> joining = {};

  // ---- Hearing a take, or a voice, on its own

  String? speechPreviewing;
  Timer? _heardWatch;

  /// takePath is where a stored take's file is: a stand-in for tests.
  @visibleForTesting
  static Future<String?> Function(String assetId) takePath = (id) async {
    // A take's id is a document's, which may have come from anyone: only a
    // store id ever becomes a path.
    if (!CanvasMedia.isId(id)) return null;
    // Saved, in the Audio library; else kept apart -- see speechTakeStore.
    if (await CanvasMedia.existingPath(MediaKind.audio, id) case var p?) {
      return p;
    }
    var kept = path.join(await CanvasStorage.speechTakesDir(), id);
    return await File(kept).exists() ? kept : null;
  };

  /// speechSample is what a voice says for its preview.
  static const speechSample = "Good evening, everyone. I have some news for you.";

  Directory? _previewDir;

  // ---- MIDI files from the library

  /// midiOfAsset reads stored MIDI file [assetId]'s notes, in seconds, or
  /// null where it cannot be read. A stand-in for tests.
  static Future<MidiImport?> Function(String assetId) midiOfAsset = (id) async {
    var file = await CanvasMedia.existingPath(MediaKind.audio, id);
    if (file == null) return null;
    try {
      return readMidiFile(await File(file).readAsBytes());
    } on FormatException {
      return null;
    }
  };

  // ---- The Vocaliser

  /// takeAudio reads a take's file as one side at the mix rate: a
  /// stand-in for tests.
  static Future<Float32List?> Function(String assetId) takeAudio = (id) async {
    var file = await takePath(id);
    if (file == null) return null;
    var sound = await readWholeAway(file);
    if (sound == null) return null;
    var (l, r) = sound;
    return Float32List.fromList(
        [for (var i = 0; i < l.length; i++) (l[i] + r[i]) * 0.5]);
  };

  /// singing is the channels singing now, so their Sing shows it.
  final Set<String> singing = {};

  /// speechStore keeps a spoken take's file, answering its id: a stand-in
  /// for tests.
  @visibleForTesting
  static Future<String?> Function(String file) speechStore =
      (file) => CanvasMedia.saveFile(MediaKind.audio, file);

  ((CanvasDocument, int, bool, int?, List<String>), List<TimelineChannel>)?
      _channels;

  /// _lanesKept and _pressedKept are timedLanes and interactiveLanes as last
  /// worked out, with what they were worked out from.
  ((CanvasDocument, int, bool, int?), List<TimedLane>)? _lanesKept;
  (CanvasDocument, List<TimedLane>)? _pressedKept;

  static bool _sameChannelKey((CanvasDocument, int, bool, int?, List<String>) a,
          (CanvasDocument, int, bool, int?, List<String>) b) =>
      identical(a.$1, b.$1) &&
      a.$2 == b.$2 &&
      a.$3 == b.$3 &&
      a.$4 == b.$4 &&
      identical(a.$5, b.$5);

  // ------------------------------------------------------------------------
  // Sound tools -- see audio_tools.dart.

  Set<String> _selectedChannels = {};

  /// _panelState is the state panels.dart keeps: see _PanelState.
  final _PanelState _panelState = _PanelState();

  /// laneHeights is each channel's dragged height: the reader's, kept per
  /// canvas by the screen (see canvasView).
  final Map<String, double> laneHeights = {};

  // ---- Kept between visits

  /// timelineView is the stretch the timeline is zoomed to (null for all),
  /// as last drawn; timelineViewSet counts restores from outside.
  TimelineView? timelineView;
  int timelineViewSet = 0;

  /// _speechShown is whether the Chain's sound shows the channel's Speech.
  /// Speech makes clips rather than being a chain step, so it shows on ask.
  bool _speechShown = false;

  /// _pitchShown is whether the Chain shows its channel's Pitch editor.
  bool _pitchShown = false;

  /// _instrumentShown is whether the Chain shows its Instrument editor.
  bool _instrumentShown = false;

  /// _chainFull is whether the Chain fills the window, the canvas put away.
  bool _chainFull = false;

  // ---- controller/chain_panel.dart ----------------------------------------

  /// _keysShown is whether the Chain's Keys strip is open: for the session.
  static bool _keysShown = false;

  /// _keysHeight is the Keys strip's dragged height, or null for its own.
  static double? _keysHeight;

  /// _chainPhase is the Chain's filter: only what plays in one phase -- its
  /// cards and its keys -- or null for all of it.
  MotionPhase? _chainPhase;

  /// _hear is which surround speakers the editor plays: see hearSpeakers.
  SpeakerGroup _hear = SpeakerGroup.all;

  /// _soundFrom is where a game last set a channel's sound off -- the
  /// instance of an element reused it touched -- by channel: see gameSound.
  final Map<String, Heard> _soundFrom = {};

  String? _effectsFocus;
  int _effectsFocusCount = 0;

  // ---- The clip editor

  bool _editorWide = true;

  /// _mixerState is the state mixer.dart keeps: see _MixerState.
  final _MixerState _mixerState = _MixerState();

  Timer? _controlIdle;

  final Set<String> _abB = {};

  bool _motionCurves = false;

  /// _trackCurves is whether the Motion view shows the Curves of what the
  /// Keyframes card edits, and _trackCurvesFrame the keyframe it opened on.
  bool _trackCurves = false;
  int? _trackCurvesFrame;

  /// _copiesOf and _pickedCopies are the copies of an element reused that
  /// are picked -- on the canvas or in its Instances card -- and so what
  /// its chain edits; none picked is all of them. See controller/copies.dart.
  String? _copiesOf;
  Set<String> _pickedCopies = {};

  /// _allCopiesChosen is All pressed in its Instances: see allCopiesChosen.
  bool _allCopiesChosen = false;

  /// _placingCopies is the element whose copies a click on the canvas
  /// places, one a click: see placingCopies.
  String? _placingCopies;

  PianoRollTarget? _clipEditing;
  bool _clipEditorShown = false;

  /// rollSelected are the notes picked in the piano roll, by their place in
  /// its notes: what the Notes tools change.
  final Set<int> rollSelected = {};

  /// _rollStep is the piano roll's Step input: each key played writes a
  /// note at the cursor, a grid step [_rollStepGrid] long; keys held
  /// together a chord, and the cursor moves on when all are let go.
  /// [_stepAt] is where the chord being held goes; [_stepHeld] its keys.
  bool _rollStep = false;

  /// keysHeld ticks when a key is pressed or let go live, for the stage to
  /// draw held keys by. The sound is sent first and only the stage redraws,
  /// not the whole editor, so a key's note is heard at once.
  final ValueNotifier<int> keysHeld = _Beat();

  /// playheadMoved ticks each time the playhead moves on in play, so what
  /// draws only the playhead (the piano roll's line) need not rebuild.
  final ValueNotifier<int> playheadMoved = _Beat();

  double _rollStepGrid = 0.25;
  double? _stepAt;
  final Set<int> _stepHeld = {};

  (String, int)? _selectedSlot;

  int _noteToolPresses = 1;

  /// clipAudio is a whole stored sound, both sides at the mix rate, for
  /// Reverse and Crop, or null. Tests replace it.
  static Future<(Float32List, Float32List)?> Function(String assetId)
      clipAudio = (id) async {
    var file = await CanvasMedia.existingPath(MediaKind.audio, id);
    if (file == null) return null;
    // Read by the mix engine's own decoder, or by ffmpeg for what it has no
    // reader for (M4A, AAC, Opus, a video's sound). Off the app's isolate: a
    // whole song read there stalls everything, the mixer's sound included.
    if (await readWholeAway(file) case var sound?) return sound;
    var ffmpeg = await ffmpegPath();
    return ffmpeg == null ? null : ffmpegDecode(ffmpeg, file);
  };

  // ---- Warping

  /// warping are the clips whose sound is being warped now, by id.
  final Set<String> warping = {};
  final Map<String, Future<MediaSource?>> _warpingNow = {};
  Timer? _warpTimer;

  // ---- The piano roll

  PianoRollTarget? _pianoRoll;
  bool _pianoRollShown = false;

  double _clipCursor = 0;

  String? _effectsOf;

  /// _laneState is the state lanes.dart keeps: see _LaneState.
  final _LaneState _laneState = _LaneState();

  /// foldedDevices are the mixer's devices folded to their switch and a
  /// meter, by device id ("eq", "comp" ...), the same on every strip.
  final Set<String> foldedDevices = {};

  // M to start; S is the overview, an element's motion alone.
  int _laneSize = 1;

  double _headerWidth = 240;

  bool _allFolded = false;

  /// _keyframes is the state keyframes.dart keeps: see _KeyframeState.
  final _KeyframeState _keyframes = _KeyframeState();

  /// cueColumnLeast and cueColumnMost bound the mixer's cue column width.
  static const double cueColumnLeast = 40;
  static const double cueColumnMost = 240;

  /// _waveforms is each stored sound's shape, read once (see waveformOf).
  static final Map<String, Float32List?> _waveforms = {};
  static final Set<String> _readingWaveform = {};

  /// seedWaveform gives [assetId] a shape without reading it, for tests.
  @visibleForTesting
  static void seedWaveform(String assetId, Float32List peaks) =>
      _waveforms[assetId] = peaks;

  bool _disposedForWaveform = false;

  // ------------------------------------------------------------------------
  // The mixer
  // ------------------------------------------------------------------------

  // ---- Automation: see automation.dart

  final Map<String, Set<String>> _overridden = {};

  // ------------------------------------------------------------------------
  // Keyframes
  // ------------------------------------------------------------------------

  /// elementLoopOf is [element]'s loop, whatever kind of element: the words'
  /// and a chart's are in animations of their own.
  static ElementLoop elementLoopOf(CanvasElement element) => switch (element) {
        TextElement e => e.animation.loop,
        ChartElement e => e.animation.loop,
        _ => elementAnimationOf(element).loop,
      };

  /// elementAnimationOf is [element]'s own arrival, or an empty one for
  /// kinds without. A switch rather than a getter on CanvasElement, which
  /// would promise every element animates this way.
  static ElementAnimation elementAnimationOf(CanvasElement element) =>
      switch (element) {
        ShapeElement e => e.animation,
        ImageElement e => e.animation,
        VectorElement e => e.animation,
        LineElement e => e.animation,
        PathElement e => e.animation,
        TableElement e => e.animation,
        CounterElement e => e.animation,
        ButtonElement e => e.animation,
        AudioElement e => e.animation,
        VideoElement e => e.animation,
        Character3dElement e => e.animation,
        _ => const ElementAnimation(),
      };

  /// loops is whether [element] can loop: everything that animates, and the
  /// words and charts, whose animations are their own.
  static bool loops(CanvasElement element) =>
      animates(element) || element is TextElement || element is ChartElement;

  /// animates is whether [element] arrives as a thing in a box. Not a chart,
  /// whose animation knows bars and slices (see applyChartAnimation), and not
  /// text, whose presets are scoped to words and letters.
  static bool animates(CanvasElement element) =>
      element is ShapeElement ||
      element is ImageElement ||
      element is VectorElement ||
      element is LineElement ||
      element is PathElement ||
      element is TableElement ||
      // A counter arrives like any box, whatever its number does.
      element is CounterElement ||
      // And a button: arriving is not pressing.
      element is ButtonElement ||
      element is AudioElement ||
      element is VideoElement ||
      element is Character3dElement;

  /// withElementAnimation is [element] with [animation] as its own, for
  /// the kinds that have one (see animates).
  static CanvasElement withElementAnimation(
          CanvasElement element, ElementAnimation animation) =>
      _withElementAnimation(element, animation);

  static CanvasElement _withElementAnimation(
          CanvasElement element, ElementAnimation animation) =>
      switch (element) {
        ShapeElement e => e.copyWith(animation: animation),
        ImageElement e => e.copyWith(animation: animation),
        VectorElement e => e.copyWith(animation: animation),
        LineElement e => e.copyWith(animation: animation),
        PathElement e => e.copyWith(animation: animation),
        TableElement e => e.copyWith(animation: animation),
        CounterElement e => e.copyWith(animation: animation),
        ButtonElement e => e.copyWith(animation: animation),
        AudioElement e => e.copyWith(animation: animation),
        VideoElement e => e.copyWith(animation: animation),
        Character3dElement e => e.copyWith(animation: animation),
        _ => element,
      };

  ({String id, int frame})? _previewing;
  int _previewingEnd = 0;

  // ------------------------------------------------------------------------
  // Loading and saving
  // ------------------------------------------------------------------------

  // ---- controller/saving.dart ---------------------------------------------

  Timer? _autosave;

  /// _autosaveDelay is how long the editing has to stop for: long enough
  /// that a drag is one write, short enough to lose nothing.
  static const Duration _autosaveDelay = Duration(seconds: 3);

  @override
  void dispose() {
    PatternCounts.counted.removeListener(_patternCounted);
    _hookOwners.remove(this);
    if (_hookOwners.isNotEmpty) _hookOwners.last._takeHooks();
    _endWait();
    chartGlideBeat.removeListener(_glideBeat);
    chartGlides.clear();
    slotsScroll.dispose();
    // A stepped note's release, due shortly, would land after the end.
    if (_stepped[this] case (var timer, _, _)) timer.cancel();
    _stepped[this] = null;
    for (var n in <ChangeNotifier>[
      studio3dOpen,
      scoreStudio,
      codeStudio,
      dataStudio,
      keysHeld,
      playheadMoved,
    ]) {
      n.dispose();
    }
    _heardWatch?.cancel();
    _previewDir?.delete(recursive: true).catchError((_) => _previewDir!);
    _disposed = true;
    _chrome.dispose();
    _partTimer?.cancel();
    _synthTarget?.cancel();
    _synthTick?.cancel();
    _metroTick?.cancel();
    _warpTimer?.cancel();
    for (var a in _arps.values) {
      a.timer?.cancel();
    }
    _arps.clear();
    _shapeTimer?.cancel();
    if (gaming) {
      if (_gamePaused) {
        if (audio.engine case DartAudioEngine e) e.held = false;
      }
      HardwareKeyboard.instance.removeHandler(_gameKeyHook);
      _gameTimer?.cancel();
      _game?.dispose();
      _game = null;
    }
    if (sheetMarksOf == _sheetMarksHook) sheetMarksOf = null;
    if (vectorSoloOf == _soloHook) vectorSoloOf = null;
    if (_spritePaint != null) {
      _spritePaint!.dispose();
      _spritePaint = null;
      spritePaintingOf = null;
    }
    if (_tilePaint != null) {
      _tilePaint!.dispose();
      _tilePaint = null;
      tileMapEditingOf = null;
    }
    _disposedForWaveform = true;
    _autosave?.cancel();
    _playback?.cancel();
    _counterTimer?.cancel();
    _video?.removeListener(notifyListeners);
    _video?.dispose();
    _audio?.removeListener(notifyListeners);
    _audio?.dispose();
    images.dispose();
    super.dispose();
  }
}

/// _Chrome is the notifier behind [CanvasController.chrome].
class _Chrome extends ChangeNotifier {
  void tell() => notifyListeners();
}

/// _Beat is a counter ticked to say something moved (a key, the playhead),
/// which goes quiet once disposed: ticks come from timers, players and code
/// runners that can land a moment after the canvas has shut, and there is
/// nothing left then to tell.
class _Beat extends ValueNotifier<int> {
  _Beat() : super(0);

  bool _gone = false;

  @override
  set value(int v) {
    if (!_gone) super.value = v;
  }

  @override
  void dispose() {
    _gone = true;
    super.dispose();
  }
}
