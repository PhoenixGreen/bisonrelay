import 'package:bruig/plugin_system/canvas/media/synth/patch_voice.dart'
    show PatchWatch;
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart' show mixRate;
import 'package:bruig/plugin_system/canvas/render/synth_module_painter.dart'
    show SynthShow, synthShowOf;
import 'package:bruig/plugin_system/canvas/model/synth_channels.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'dart:async';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/automation.dart';
import 'package:bruig/plugin_system/canvas/model/pitch_edit.dart'
    show PitchEdit;
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/media/phrasing.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/media/kokoro_speech.dart';
import 'package:bruig/plugin_system/canvas/media/speech_engines.dart';
import 'package:bruig/plugin_system/canvas/media/qwen_speech.dart';
import 'package:bruig/plugin_system/canvas/media/speech_finish.dart';
import 'package:bruig/plugin_system/canvas/media/warp.dart';
import 'package:bruig/plugin_system/canvas/media/vocaliser.dart';
import 'package:bruig/plugin_system/canvas/model/midi_file.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart';
import 'package:bruig/plugin_system/canvas/model/musicxml.dart';
import 'package:bruig/plugin_system/canvas/model/note_tools.dart';
import 'package:bruig/plugin_system/canvas/media/midi_input.dart';
import 'package:bruig/plugin_system/canvas/media/push_surface.dart'
    show PadClip;
import 'package:bruig/plugin_system/canvas/model/canvas_estimate.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dart_audio_engine.dart';
import 'package:bruig/plugin_system/canvas/media/mix/device_scope.dart';
import 'package:bruig/plugin_system/canvas/media/mix/decode.dart'
    show ffmpegDecode, readWholeAway;
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart'
    show StripProcessor, mixRate;
import 'package:bruig/plugin_system/canvas/ui/element_sound.dart'
    show ownChannelOf, soundOwnerOf;
import 'package:bruig/plugin_system/canvas/ui/row_header.dart'
    show givenRowColour;
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'dart:math' as math;
import 'dart:io' show Directory, File;
import 'dart:isolate' show Isolate;

import 'package:crypto/crypto.dart' show sha256;
import 'dart:ui' as ui;
import 'dart:ui' show Color, Offset, Rect, Size;

import 'package:bruig/components/paint_spec.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/audio_tools.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_cues.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_palette.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/text_looks.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/team_painter.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/cast.dart';
import 'package:bruig/plugin_system/canvas/model/responsive_layout.dart';
import 'package:bruig/plugin_system/canvas/render/scene_sequence.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/lip_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_performance.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';
import 'package:bruig/plugin_system/canvas/ui/sprite_painting.dart';
import 'package:bruig/plugin_system/canvas/ui/tile_painting.dart';
import 'package:bruig/plugin_system/canvas/render/tile_map_painter.dart' show tileMapEditingOf;
import 'package:bruig/plugin_system/canvas/render/sprite_painter.dart' show spritePaintingOf;
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/vector_text.dart';
import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:bruig/plugin_system/canvas/model/font_files.dart';
import 'package:bruig/plugin_system/canvas/model/vector_brush.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/image_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/image_masking.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart'
    show channelClip;
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_items.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_shapes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/score_channels.dart';
import 'package:bruig/plugin_system/canvas/model/score_roll.dart';
import 'package:bruig/plugin_system/canvas/render/score_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:bruig/plugin_system/canvas/model/modulation.dart'
    show macroValue;
import 'package:bruig/plugin_system/canvas/ui/canvas_game.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart' show
        ControlAction,
        GameSoundElement,
        GameSoundSlot,
        GameSoundStop,
        gameSoundOf,
        gameSoundStop;
import 'package:gamepads/gamepads.dart' show Gamepads, NormalizedGamepadEvent;
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart'
    show newElement, newInstrument, synthRack, synthModule;
import 'package:bruig/plugin_system/canvas/model/elements/synth_task_element.dart';
import 'package:bruig/plugin_system/canvas/render/synth_task_painter.dart'
    show synthTaskLayout, synthTaskScale;
import 'package:bruig/plugin_system/canvas/model/notation.dart' show splitKey;
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/render/sheet_painter.dart';
import 'package:bruig/plugin_system/canvas/media/synth/part_render.dart';
import 'package:path/path.dart' as path;
import 'package:bruig/plugin_system/canvas/media/mix/analysers.dart'
    show Wave, LoudnessReading;
import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart'
    show PitchReading;
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart'
    show ffmpegHelp, ffmpegPath;
import 'package:bruig/plugin_system/canvas/media/ffmpeg_video.dart';
import 'package:bruig/plugin_system/canvas/media/speech.dart';
import 'package:bruig/plugin_system/canvas/media/video_runtime.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';
import 'package:bruig/plugin_system/canvas/media/audio_engine.dart';
import 'package:bruig/plugin_system/canvas/media/audio_runtime.dart';
import 'package:bruig/plugin_system/canvas/render/sound_placement.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart'
    show Heard, SpeakerGroup;
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/render/audio_painter.dart';

import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/render/render_caches.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_player.dart';
import 'package:bruig/plugin_system/canvas/model/own_motion.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart'
    show MotionEditing, motionId, everyMotion;
import 'package:bruig/plugin_system/canvas/model/instances.dart'
    show CopyValue, ElementInstance, InstanceSet, deviceOwnKey;
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart'
    show MotionPhase;
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart'
    show ClipTriggerKind, ElementMotion, MotionKind;
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show
        cameraFraming,
        cameraHalfExtents,
        cameraLookAt,
        LiveMotion,
        MotionPreview,
        PointerLive,
        cameraOf,
        facesPointer,
        isStageScene,
        motionSoundPeaks,
        placedPlaying,
        poseWithMotion,
        sceneFraming,
        settledFrameOf;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, KeyRepeatEvent, KeyUpEvent, LogicalKeyboardKey;

// The controller's methods, by area, as extensions in parts of this
// library: its state stays here, in the class, where every part can reach
// it. A method goes in the part for its area; a field goes in the class.
part 'controller/pictures.dart';
part 'controller/vectors.dart';
part 'controller/scenes.dart';
part 'controller/playback.dart';
part 'controller/instruments.dart';
part 'controller/session.dart';
part 'controller/game.dart';
part 'controller/speech.dart';
part 'controller/tools.dart';
part 'controller/mixer.dart';
part 'controller/keyframes.dart';
part 'controller/timeline_clips.dart';
part 'controller/copies.dart';
part 'controller/cast.dart';
part 'controller/scores.dart';
part 'controller/synths.dart';

// canvas_controller.dart holds everything about the canvas being edited that
// is not the document itself: the selection, the playhead, the zoom, the undo
// history and whether any of it has been saved.
//
// The document is immutable (see canvas_document.dart), so every edit goes
// through [apply], the only place the document is replaced. Undo is therefore
// a list of past documents rather than operations to reverse, and an edit
// cannot half-happen: the selection and the document change in one
// assignment.

/// _maxUndo bounds the history. Documents are small and share unchanged
/// elements, so it can be generous; it is bounded only because a session
/// spent nudging a slider would otherwise grow without limit.
const int _maxUndo = 120;

/// minZoom and maxZoom bound the view, as multiples of the fitted size (see
/// [CanvasController.zoom]): 1 is the whole canvas filling the area.
const double minZoom = 0.25;
const double maxZoom = 16;

/// RetouchBrush is what the brush does to a picture's background.
enum RetouchBrush {
  off("Off"),

  /// erase takes the picture away, for a patch the automatic pass missed.
  erase("Rub out"),

  /// cutAround draws a boundary rather than a mark: everything outside it
  /// goes. See RemovalStroke.fill.
  cutAround("Cut around"),

  /// restore puts it back, for a hand or a shoulder the automatic pass ate.
  restore("Put back"),

  /// markBackground and markSubject do not change the picture at all: they
  /// leave evidence for RemovalMode.learn to work from. See
  /// BackgroundRemoval.hints.
  markBackground("Mark background"),
  markSubject("Mark subject");

  final String label;
  const RetouchBrush(this.label);

  bool get on => this != RetouchBrush.off;

  /// teaches is whether this brush leaves a hint rather than rubbing something
  /// out. It matters only where the stroke is stored.
  bool get teaches =>
      this == RetouchBrush.markBackground || this == RetouchBrush.markSubject;

  /// keeps is whether the mark is about the subject rather than the
  /// background.
  bool get keeps =>
      this == RetouchBrush.restore || this == RetouchBrush.markSubject;

  /// fills is whether the stroke is a boundary rather than a mark.
  bool get fills => this == RetouchBrush.cutAround;
}

/// CanvasTool is what dragging on the canvas does. An explicit tool rather
/// than a gesture that guesses, so the view can be made to stay still.
enum CanvasTool {
  /// select moves and selects elements. The view does not move in this tool,
  /// by dragging or scrolling, so nothing shifts under a careful adjustment.
  select("Select", "Move and select elements; the view stays put"),

  /// pan moves the view. Dragging slides the canvas about and the wheel zooms.
  pan("Pan", "Drag to move around the canvas, scroll to zoom");

  final String label;
  final String description;
  const CanvasTool(this.label, this.description);
}

/// StageTool is what the gizmo on an element standing on a 3D stage does:
/// the bar's three 3D tools, in place of Select and Pan while the scene is
/// a stage. Their keys are G, R and S.
enum StageTool {
  move("Move", "G",
      "arrows along the stage, the square across the floor"),
  rotate("Rotate", "R", "turn it round on the floor"),
  scale("Scale", "S", "drag the box up to grow it, down to shrink it");

  final String label;
  final String key;
  final String description;
  const StageTool(this.label, this.key, this.description);
}

/// StageNav is how much of the 3D view controls float at the stage's
/// right: all of them, the orbit ball alone, or none.
enum StageNav { all, orbit, none }

/// CanvasFit is how large the canvas's frame is drawn. Two modes because a
/// tall document fitted whole is a narrow strip down the middle of the window.
enum CanvasFit {
  /// whole shows all of the canvas at once, limited by whichever of the two
  /// dimensions runs out first. Nothing scrolls.
  whole("Show the whole canvas"),

  /// width fills the area's full width and lets the canvas be as tall as it
  /// needs, scrolling if that is taller than the window.
  width("Fit to width");

  final String label;
  const CanvasFit(this.label);
}

/// _pinnedAt is [track] with [channels] pinned at [frame], keeping
/// whatever else that frame already holds.
ElementTrack _pinnedAt(
    ElementTrack track, int frame, Map<String, double> channels) {
  var at = track.keyAt(frame) ?? track.restingAt(frame);
  return track.withKey(at.copyWith(values: {...at.values, ...channels}));
}

/// FetchedRows is what one element's last refresh in this sitting returned,
/// kept so the mapping controls can change column without asking the source
/// again.
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

/// CanvasController is the editing session.
class CanvasController extends ChangeNotifier {
  CanvasController(CanvasDocument document,
      {AudioEngine? audioEngine, FrameSource? frameSource})
      : _document = document,
        _audioEngine = audioEngine,
        _frameSource = frameSource {
    // Follow sound reads the recordings this canvas reads.
    motionSoundPeaks = (id) => waveformOf(id);
    // An instrument of slices plays a stored sound.
    sliceAudioReader = (id) => CanvasController.clipAudio(id);
    // A sheet's playbar shows pause while this canvas plays.
    sheetPlaying = () => playing;
    // The synth modules on the stage: their keys held, their time.
    synthShowOf = synthShowFor;
  }

  CanvasDocument _document;
  CanvasDocument get document => _document;

  /// lastFetched is what each element's last refresh returned, by element id.
  ///
  /// Here rather than in the settings panel, because two buttons run a
  /// refresh (the Data source section's and the Table section's); and not a
  /// global, which would outlive its canvas and mix up element ids across
  /// canvases. Not saved in the document: it is a fact about this sitting.
  final Map<String, FetchedRows> lastFetched = {};

  final CanvasImageStore images = CanvasImageStore();

  final List<CanvasDocument> _undo = [];
  final List<CanvasDocument> _redo = [];

  /// _interaction is the document as it was when a drag began, so the whole
  /// gesture is one undo step: pushed onto the history when it ends.
  CanvasDocument? _interaction;

  Set<String> _selection = {};
  Set<String> get selection => _selection;

  bool _backgroundSelected = false;

  /// backgroundSelected is whether the canvas's own background is the thing
  /// being edited.
  ///
  /// A flag rather than a sentinel id in [selection], so the operations that
  /// walk the selection (delete, duplicate, nudge) need not learn to skip it.
  /// It is exclusive with the element selection.
  bool get backgroundSelected => _backgroundSelected;

  /// selectBackground makes the background the selected layer.
  void selectBackground() {
    if (_backgroundSelected && _selection.isEmpty) return;
    _selection = {};
    _backgroundSelected = true;
    notifyListeners();
  }

  int _frame = 0;
  int get frame => _frame;

  double _zoom = 1;

  /// zoom is a multiple of the size at which the canvas fills the area it is
  /// drawn in, not of the document's own pixels: a document's pixel size
  /// depends only on its export width, so the canvas always fills the area to
  /// begin with and 1 is the whole canvas. The fitted size is worked out by
  /// the stage (CanvasStage), the only thing that knows how much room there is.
  double get zoom => _zoom;

  /// _fitScale is what the stage last reported: how much the canvas is
  /// shrunk to fill the window before any zoom. See [viewScale].
  double _fitScale = 1;

  /// viewScale is document pixels to screen pixels: what the percentage on
  /// the band means. Not [zoom], which is 1 whenever the whole canvas shows,
  /// whatever size that is.
  double get viewScale => _fitScale * _zoom;

  /// reportFitScale is the stage telling the controller how much room it
  /// found. Notifies only when the answer changes, since it is asked on every
  /// layout.
  void reportFitScale(double value) {
    if (!value.isFinite || value <= 0) return;
    if ((value - _fitScale).abs() < 0.0001) return;
    _fitScale = value;
    _notifyView();
  }

  /// setViewScale zooms so that one document pixel is [value] screen pixels,
  /// which is what typing a percentage into the band means.
  void setViewScale(double value) {
    if (!value.isFinite || value <= 0 || _fitScale <= 0) return;
    zoom = value / _fitScale;
  }

  /// atFit is whether the view is showing the whole canvas, untouched: what
  /// the Fit button lights up for.
  bool get atFit => (_zoom - 1).abs() < 0.001 && _pan.dx == 0 && _pan.dy == 0;

  Offset2 _pan = const Offset2(0, 0);
  Offset2 get pan => _pan;

  /// revision counts every change that is about the *document* rather than
  /// the view of it. The sidebar watches it, so panning, zooming and hovering
  /// do not lay out its many fields again.
  ///
  /// Safe by default: every notification moves it except the few that go
  /// through [_notifyView], so a forgotten case costs a needless rebuild
  /// rather than a panel showing something untrue.
  int get revision => _revision;
  int _revision = 0;

  /// _viewOnly is set only while [_notifyView] is running.
  bool _viewOnly = false;

  /// _playheadOnly is set only while the playhead's moving on is told of:
  /// see notifyingPlayhead.
  bool _playheadOnly = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    // A drawing is edited only while it is there and is the one thing
    // selected: whatever took that away (undo, delete, a pruned selection)
    // ends the editing.
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
    // Picked copies, only while their element is the one thing selected,
    // and only those it still has.
    if (_copiesOf case var of?
        when _selection.length != 1 || _selection.first != of) {
      _copiesOf = null;
      _pickedCopies = {};
      _allCopiesChosen = false;
      if (_placingCopies == of) _placingCopies = null;
    }
    if (!_viewOnly) _revision++;
    super.notifyListeners();
  }

  /// arrived says something the settings draw from has finished loading --
  /// a model their tiles show -- so they are drawn again with it.
  void arrived() => notifyListeners();

  /// restoreFit puts back the frame the reader last chose, without notifying:
  /// it is called from initState, and notifying a Provider-held controller
  /// during a build throws (with a costly stack capture). The first build
  /// reads the new value anyway.
  void restoreFit(CanvasFit value) {
    _fit = value;
    _zoom = 1;
    _pan = const Offset2(0, 0);
  }

  /// _notifyView tells everyone that the *view* moved -- the zoom, the pan,
  /// how the canvas is framed, which tool is in hand -- without claiming the
  /// document changed.
  void _notifyView() {
    _viewOnly = true;
    try {
      notifyListeners();
    } finally {
      _viewOnly = false;
    }
  }

  CanvasFit _fit = CanvasFit.whole;

  /// fit is how large the frame is drawn. See [CanvasFit].
  CanvasFit get fit => _fit;

  set fit(CanvasFit value) {
    if (_fit == value) return;
    _fit = value;
    // A zoom chosen against the old frame means a different magnification
    // against the new one.
    _zoom = 1;
    _pan = const Offset2(0, 0);
    _notifyView();
  }

  bool _autoKeyframe = false;

  /// autoKeyframe makes every move record itself: dragging anything with the
  /// playhead on frame N writes a keyframe at N instead of moving the thing.
  /// Off by default, so a document can be tidied without recording the
  /// tidying.
  bool get autoKeyframe => _autoKeyframe;

  set autoKeyframe(bool value) {
    if (_autoKeyframe == value) return;
    _autoKeyframe = value;
    notifyListeners();
  }

  bool _showOverspill = false;

  /// showOverspill draws a margin of the world outside the canvas. Off by
  /// default, since the canvas shows what gets published; on, an element
  /// entering from off the page can be seen, selected and dragged there.
  bool get showOverspill => _showOverspill;

  set showOverspill(bool value) {
    if (_showOverspill == value) return;
    _showOverspill = value;
    notifyListeners();
  }

  bool _showHelpers = true;

  /// showHelpers is whether the editing furniture is drawn: the box around the
  /// selection, the resize handles and the rotation ring. Off, it shows the
  /// design as published, and the handles stop answering the pointer too, so
  /// nothing invisible can be grabbed.
  bool get showHelpers => _showHelpers;

  set showHelpers(bool value) {
    if (_showHelpers == value) return;
    _showHelpers = value;
    _notifyView();
  }

  bool _showAllBounds = false;

  /// showAllBounds outlines every element on the canvas, not only the selected
  /// one: for elements that relate to each other, such as a chain of text
  /// boxes. Off by default; one switch for the whole canvas.
  bool get showAllBounds => _showAllBounds;

  set showAllBounds(bool value) {
    if (_showAllBounds == value) return;
    _showAllBounds = value;
    _notifyView();
  }

  bool _lockJoins = false;

  /// lockJoins keeps the connectors between text boxes from being changed by
  /// a drag: their small grips sit on the same outline as the resize handles.
  /// Locked, the grips are still drawn but do not answer the pointer.
  bool get lockJoins => _lockJoins;

  set lockJoins(bool value) {
    if (_lockJoins == value) return;
    _lockJoins = value;
    _notifyView();
  }

  bool _hideJoins = false;

  /// hideJoins leaves the lines between linked text boxes undrawn. The grips
  /// stay, still saying there is a chain and whether the words all fit.
  bool get hideJoins => _hideJoins;

  set hideJoins(bool value) {
    if (_hideJoins == value) return;
    _hideJoins = value;
    _notifyView();
  }

  int? _focusedPlayer;

  /// focusedPlayer is which player of the selected team the timeline is about.
  /// A player is not an element and cannot be selected, so this says which
  /// one the keyframe controls point at. Set by clicking one on the canvas and
  /// cleared whenever the selection changes.
  int? get focusedPlayer => _focusedPlayer;

  set focusedPlayer(int? value) {
    if (_focusedPlayer == value) return;
    _focusedPlayer = value;
    notifyListeners();
  }

  /// focusedTeam is the selected element when it is a team, and null
  /// otherwise. What the timeline asks before offering a player's keyframes.
  TeamElement? get focusedTeam {
    var element = selected;
    return element is TeamElement ? element : null;
  }

  RetouchBrush _retouch = RetouchBrush.off;

  /// retouch is whether the pointer is painting a picture's background in or
  /// out rather than moving things about. A mode rather than a modifier key,
  /// since retouching takes a run of strokes.
  RetouchBrush get retouch => _retouch;

  set retouch(RetouchBrush value) {
    if (_retouch == value) return;
    _retouch = value;
    notifyListeners();
  }

  /// _pendingStroke is a stroke that has been drawn but not yet applied, and
  /// _pendingPicture is the picture it was drawn on. Held so it is redrawn
  /// against the brush settings as they change, and applied when the reader
  /// is satisfied.
  List<Offset>? _pendingStroke;
  String? _pendingPicture;

  /// pendingKeeps and pendingTeaches are what the brush was doing when the
  /// stroke was drawn. Kept with the stroke rather than read live: changing
  /// brush is doing something else, not adjusting this stroke.
  bool _pendingKeeps = false;
  bool _pendingTeaches = false;
  bool _pendingFills = false;

  List<Offset>? get pendingStroke => _pendingStroke;
  String? get pendingPicture => _pendingPicture;
  bool get pendingKeeps => _pendingKeeps;
  bool get pendingTeaches => _pendingTeaches;
  bool get pendingFills => _pendingFills;
  bool get hasPendingStroke =>
      _pendingStroke != null && _pendingStroke!.isNotEmpty;

  /// holdStroke keeps a freshly drawn stroke back for adjustment.
  void holdStroke(String pictureId, List<Offset> points,
      {required bool keeps, required bool teaches, bool fills = false}) {
    if (points.isEmpty) return;
    _pendingPicture = pictureId;
    _pendingStroke = List.unmodifiable(points);
    _pendingKeeps = keeps;
    _pendingTeaches = teaches;
    _pendingFills = fills;
    notifyListeners();
  }

  /// discardStroke throws the held stroke away.
  void discardStroke() {
    if (_pendingStroke == null) return;
    _pendingStroke = null;
    _pendingPicture = null;
    notifyListeners();
  }

  /// applyStroke writes the held stroke onto its picture, with the brush's
  /// settings as they stand now.
  void applyStroke() {
    var id = _pendingPicture;
    var points = _pendingStroke;
    if (id == null || points == null || points.isEmpty) return;

    var picture = _document.elementById(id);
    if (picture is! ImageElement) {
      discardStroke();
      return;
    }

    var stroke = RemovalStroke(
      points: points,
      radius: _brushSize,
      keep: _pendingKeeps,
      // A hint is a sample rather than a mark on the picture, so it is taken
      // exactly where it was drawn: softening or snapping it would collect
      // colours the reader did not point at.
      hardness: _pendingTeaches ? 1 : _brushHardness,
      snap: _clingFor(_pendingTeaches, _pendingKeeps),
      fill: _pendingFills,
      fillInside: _pendingFills && _cutInside,
    );

    replaceElement(picture.copyWith(
        removal: _pendingTeaches
            ? picture.removal
                .copyWith(hints: [...picture.removal.hints, stroke])
            : picture.removal
                .copyWith(strokes: [...picture.removal.strokes, stroke])));
    discardStroke();
  }

  /// magnetiseCling finds the edge the held stroke crossed, and sets the cling
  /// to it: the stroke's colour distances fall into two clusters with a gap
  /// between them. See suggestSnap. Returns false when there is no edge, as
  /// for a stroke drawn entirely on the background.
  Future<bool> magnetiseCling() async {
    var stroke = pendingAsStroke();
    var id = _pendingPicture;
    if (stroke == null || id == null) return false;

    var picture = _document.elementById(id);
    if (picture is! ImageElement) return false;
    var source = images.original(picture.assetId);
    if (source == null) return false;

    var found = await snapForStroke(source, stroke);
    if (found == null) return false;
    brushSnap = found;
    return true;
  }

  /// pendingAsStroke is the held stroke as it would be applied right now,
  /// which is what the preview on the canvas is drawn from.
  RemovalStroke? pendingAsStroke() {
    var points = _pendingStroke;
    if (points == null || points.isEmpty) return null;
    return RemovalStroke(
      points: points,
      radius: _brushSize,
      keep: _pendingKeeps,
      hardness: _pendingTeaches ? 1 : _brushHardness,
      snap: _clingFor(_pendingTeaches, _pendingKeeps),
      fill: _pendingFills,
      fillInside: _pendingFills && _cutInside,
    );
  }

  /// _clingFor is how much a stroke should cling. Never for a hint, which
  /// must be sampled exactly where drawn, and never for putting something
  /// back: the subject is every colour there is, so clinging would restore
  /// only the pixels like the first one.
  double _clingFor(bool teaches, bool keeps) =>
      teaches || keeps ? 0 : _brushSnap;

  double _brushHardness = 0.35;

  /// brushHardness is how abruptly a stroke stops at its own edge. See
  /// RemovalStroke.hardness.
  double get brushHardness => _brushHardness;

  set brushHardness(double value) {
    var next = value.clamp(0.05, 1.0);
    if (next == _brushHardness) return;
    _brushHardness = next;
    notifyListeners();
  }

  bool _cutInside = false;

  /// cutInside takes what a boundary encloses rather than what surrounds it.
  /// Read when the stroke is applied, so it can be turned over while one is
  /// held.
  bool get cutInside => _cutInside;

  set cutInside(bool value) {
    if (_cutInside == value) return;
    _cutInside = value;
    notifyListeners();
  }

  /// _brushSnap starts at nothing: clinging is an aid to reach for
  /// deliberately, and on by default it made the brush look broken.
  double _brushSnap = 0;

  /// brushSnap makes a stroke cling to what is already in the picture. See
  /// RemovalStroke.snap.
  double get brushSnap => _brushSnap;

  set brushSnap(double value) {
    var next = value.clamp(0.0, 0.6);
    if (next == _brushSnap) return;
    _brushSnap = next;
    notifyListeners();
  }

  double _brushSize = 0.05;

  /// brushSize is the brush's radius as a fraction of the picture's shorter
  /// side, as a stroke is stored, so it is independent of zoom.
  double get brushSize => _brushSize;

  set brushSize(double value) {
    var next = value.clamp(0.005, 0.6);
    if (next == _brushSize) return;
    _brushSize = next;
    notifyListeners();
  }

  bool _pageLocked = false;

  /// pageLocked holds the page where it is: nothing scrolls or zooms it.
  /// On a 3D stage the gestures that would have moved it steer the
  /// stage's camera instead -- drags orbit, a shifted drag pans, a pinch
  /// zooms -- so the camera can be flown without the page sliding about.
  bool get pageLocked => _pageLocked;

  set pageLocked(bool value) {
    if (_pageLocked == value) return;
    _pageLocked = value;
    _notifyView();
  }

  StageTool _stageTool = StageTool.move;

  /// stageTool is what the gizmo does on an element standing on a stage.
  StageTool get stageTool => _stageTool;

  set stageTool(StageTool value) {
    if (_stageTool == value) return;
    _stageTool = value;
    _notifyView();
  }

  StageNav _stageNav = StageNav.all;

  /// stageNav is how much of the 3D view controls are shown. See StageNav.
  StageNav get stageNav => _stageNav;

  set stageNav(StageNav value) {
    if (_stageNav == value) return;
    _stageNav = value;
    _notifyView();
  }

  // ------------------------------------------------------------ clips
  // What is picked of an element's clips, and which panels show them. The
  // editing itself is in motion_editing.dart.

  String? _pickedMotion;
  String? _pickedPlacement;

  /// _pickedOf is the element the picked clip is on.
  String? _pickedOf;

  /// _pickLeft is whether the selection has moved on from the picked
  /// clip's element: another element clicked. Its clip is no longer what
  /// the Chain shows (Ken, 2026-11-12: "when I click a different element
  /// the clips shown are still the previous" -- and Delete took nothing,
  /// aimed at that clip on the element now picked). The selection changes
  /// in many places; the pick is let go here, as it is read.
  bool get _pickLeft =>
      _pickedOf != null &&
      _selection.isNotEmpty &&
      !_selection.contains(_pickedOf);

  /// pickedMotion is the clip the Animation panel shows, by id: picked from
  /// a slot, or from the timeline -- then [pickedPlacement] is the place.
  String? get pickedMotion => _pickLeft ? null : _pickedMotion;
  String? get pickedPlacement => _pickLeft ? null : _pickedPlacement;

  Set<(String, String)> _motionPicks = const {};

  /// motionPicks are the clips picked together on the timeline, as
  /// (element, placement): by the box dragged across the lanes, or with
  /// Shift (Ken, 2026-11-11: "select multiple audio/motion clips and then
  /// ... move them"). Moved together, and taken out together by Delete.
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

  /// _ownTab is the Motion clips card's Arrive, Loop or Leave picked where
  /// it has no clip to pick -- not set up yet, or the loop, which plays
  /// without one (Ken, 2026-11-12): its Preset is set up there. A clip
  /// picked lets it go.
  MotionKind? _ownTab;

  MotionKind? get ownTab => _ownTab;

  /// _clipSettings are the elements whose own preset shows its clip's own
  /// settings -- speed, layer, how it mixes, its name -- on the Motion
  /// clips card: for the session.
  final Set<String> _clipSettings = {};

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

  /// pickedScene is the scene the Animation panel shows, by index -- the
  /// transition after it, and its camera -- picked by a double click on its
  /// box on the timeline. It gives way to a clip picked, or to anything
  /// selected after it.
  int? get pickedScene {
    var i = _pickedScene;
    if (i == null || i >= _document.allScenes.length) return null;
    return setEquals(_selection, _pickedSceneWith) ? i : null;
  }

  /// transitionsAsDefault is whether the Chain's transition is the default
  /// -- every scene's that has none of its own -- rather than one join's:
  /// on the master, but for a join picked by its own slot (Ken, 2026-11-10:
  /// each transition clicked on the master's Scenes strip showed the same,
  /// the default).
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

  bool _animationOpen = false;

  /// _chainMotion is the view the Chain panel opens on when its button
  /// opens it: the one it was last on.
  bool _chainMotion = false;

  /// animationOpen is whether the Chain panel is out on its motion -- what
  /// was the Animation panel -- in its place under the canvas (see dock).
  /// Opening it puts the Chain's sound away: one view at a time.
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

  String? _chainFocus;

  /// chainFocus is the card the settings panel last asked the Chain to show
  /// -- a look's or a move's device id, or "clips" for the clip picked --
  /// until the Chain has brought it into view (see chainFocused).
  String? get chainFocus => _chainFocus;

  /// chainFocused is the Chain saying it has shown [chainFocus].
  void chainFocused() => _chainFocus = null;

  /// showInChain opens [element]'s Chain on its motion at device [device]
  /// -- or at [clip], placed as [placement], picked -- for a line of the
  /// settings panel that says what its Chain does (see panel_parts.dart).
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

  /// chainShowsMotion is whether the Chain panel shows its motion rather
  /// than its sound.
  bool get chainShowsMotion => _animationOpen;

  /// chainMeters, chainBadges and chainMacros are what the Chain shows
  /// besides its devices -- the meters between them, what each does to the
  /// level, the Macros zone -- each hidden from its ⋯ for room, as the
  /// prototype's. The reader's view, not the canvas's.
  bool get chainMeters => _chainMeters;
  bool _chainMeters = true;
  set chainMeters(bool on) {
    if (on == _chainMeters) return;
    _chainMeters = on;
    notifyListeners();
  }

  bool get chainBadges => _chainBadges;
  bool _chainBadges = true;
  set chainBadges(bool on) {
    if (on == _chainBadges) return;
    _chainBadges = on;
    notifyListeners();
  }

  bool get chainMacros => _chainMacros;
  bool _chainMacros = true;
  set chainMacros(bool on) {
    if (on == _chainMacros) return;
    _chainMacros = on;
    notifyListeners();
  }

  /// motionTrail is whether the stage shows the element whose motion the
  /// Chain is open on with its trail and onion skin: the path its middle
  /// takes, and faint copies of where it was a moment before. On until
  /// hidden, as the prototype's.
  bool get motionTrail => _motionTrail;
  bool _motionTrail = true;
  set motionTrail(bool on) {
    if (on == _motionTrail) return;
    _motionTrail = on;
    notifyListeners();
  }

  /// _chainOpensOnMotion is the view the Chain's button opens it on: what
  /// is picked -- an element drawn on the canvas its motion, a channel or a
  /// sound its sound -- or, with neither, the view it was last on. It never
  /// switches an open Chain: only the switch in its header does.
  bool get _chainOpensOnMotion {
    var picked = selectedElements;
    if (picked.any((e) => e is! AudioElement)) return true;
    if (picked.isNotEmpty || selectedChannel != null) return false;
    return _chainMotion;
  }

  /// showChain switches the Chain panel to its motion, or its sound: the
  /// effects of the channel last opened there.
  void showChain({required bool motion}) {
    if (motion) {
      animationOpen = true;
    } else {
      openEffects(effectsChannel);
    }
  }

  bool _rowsShown = true;

  /// rowsShown is the Timeline panel: the timeline's rows, under the play
  /// bar, in their place (see dock).
  bool get rowsShown => _rowsShown;

  set rowsShown(bool value) {
    if (_rowsShown == value) return;
    _rowsShown = value;
    if (value) _dockOpening(DockPanel.timeline);
    _notifyView();
  }

  bool _barBelow = false;

  /// barBelow is whether the play bar is under the panels rather than over
  /// them: the reader's choice, kept by the play bar (see CanvasPlayBar).
  bool get barBelow => _barBelow;
  set barBelow(bool value) {
    if (_barBelow == value) return;
    _barBelow = value;
    _notifyView();
  }

  bool _trackpadScrolls = false;

  /// trackpadScrolls is whether a sideways swipe or the wheel moves the
  /// timeline along. Off unless asked for: somebody swiping up and down
  /// through the channels would find the frames sliding under them.
  bool get trackpadScrolls => _trackpadScrolls;
  set trackpadScrolls(bool value) {
    if (_trackpadScrolls == value) return;
    _trackpadScrolls = value;
    _notifyView();
  }

  /// timelineZoomAsked counts the times the play bar's menu has asked the
  /// timeline to zoom, by timelineZoomFactor (nought: to the whole scene).
  /// The timeline takes each up as it sees it; with none open, it is
  /// dropped.
  int timelineZoomAsked = 0;
  double timelineZoomFactor = 1;

  void askTimelineZoom(double factor) {
    timelineZoomFactor = factor;
    timelineZoomAsked++;
    _notifyView();
  }

  // ------------------------------------------------------------------------
  // The panels under the canvas: see dock_layout.dart
  // ------------------------------------------------------------------------

  DockLayout _dock = const DockLayout();

  /// dock is where each panel under the canvas opens, how many places there
  /// are and how they are switched: the reader's, kept by the screen in the
  /// preferences. Changed, each place is left showing one panel at most.
  DockLayout get dock => _dock;

  set dock(DockLayout next) {
    if (next == _dock) return;
    _dock = next;
    _dockSettle();
    _notifyView();
  }

  /// restoreDock puts back [layout] without telling anyone, as the screen
  /// opens.
  void restoreDock(DockLayout layout) {
    _dock = layout;
    _dockSettle();
  }

  /// dockOpen is whether [panel] is open, in its place.
  bool dockOpen(DockPanel panel) => switch (panel) {
        DockPanel.timeline => _rowsShown,
        DockPanel.slots => _slotsBeside,
        DockPanel.mixer => _mixerOpen,
        DockPanel.chain => _animationOpen || _effectsOpen,
      };

  /// setDockOpen opens or closes [panel]: opened, whatever else was showing
  /// in its place gives way.
  void setDockOpen(DockPanel panel, bool open) {
    switch (panel) {
      case DockPanel.timeline:
        rowsShown = open;
      case DockPanel.slots:
        slotsBeside = open;
      case DockPanel.mixer:
        mixerOpen = open;
      case DockPanel.chain:
        if (open) {
          showChain(motion: _chainOpensOnMotion);
        } else {
          _animationOpen = false;
          effectsOpen = false;
          _notifyView();
        }
    }
  }

  /// toggleDock is [panel]'s button: open it, or close it if it is open.
  /// [beside] opens it on the left, beside main, where there is a left.
  void toggleDock(DockPanel panel, {bool beside = false}) {
    if (beside && _dock.places != DockPlaces.one) {
      if (_dock.homeOf(panel) != DockPlace.left) {
        _dock = _dock.withHome(panel, DockPlace.left);
        _dockSettle();
      }
      setDockOpen(panel, true);
      _notifyView();
      return;
    }
    setDockOpen(panel, !dockOpen(panel));
  }

  /// moveDockPanel has [panel] open in [place] from now on, and opens it
  /// there.
  void moveDockPanel(DockPanel panel, DockPlace place) {
    if (!_dock.placesShown.contains(place)) return;
    _dock = _dock.withHome(panel, place);
    _dockSettle();
    setDockOpen(panel, true);
    _notifyView();
  }

  /// dockShownIn is the panel showing in [place], or null.
  DockPanel? dockShownIn(DockPlace place) {
    for (var panel in DockPanel.values) {
      if (dockOpen(panel) && _dock.placeOf(panel) == place) return panel;
    }
    return null;
  }

  /// dockArrangement is the layout last chosen, while nothing has been
  /// changed since; null otherwise.
  String? get dockArrangement => _arrangementChosen;
  String? _arrangementChosen;

  /// arrange shows [layout]: the panel it names in each place, and nothing
  /// else. With one place, its own one panel.
  void arrange(DockArrangement layout) {
    var homes = {..._dock.homes, ...layout.homes};
    Map<DockPlace, DockPanel> shown;
    if (_dock.places == DockPlaces.one) {
      var one = layout.one ??
          layout.shown[DockPlace.main] ??
          layout.shown[DockPlace.left] ??
          layout.shown[DockPlace.above];
      shown = {if (one != null) DockPlace.main: one};
    } else {
      shown = _dock.places == DockPlaces.three || layout.fallback == null
          ? layout.shown
          : layout.fallback!;
      for (var e in shown.entries) {
        if (_dock.placesShown.contains(e.key)) homes[e.value] = e.key;
      }
      if (_dock.places != DockPlaces.three) {
        shown = {
          for (var e in shown.entries)
            if (e.key != DockPlace.above) e.key: e.value
        };
      }
    }
    _dock = _dock.copyWith(homes: homes);
    if (shown.containsValue(DockPanel.chain)) _chainMotion = layout.chainMotion;
    for (var panel in DockPanel.values) {
      _setDockRaw(panel, shown.containsValue(panel));
    }
    _arrangementChosen = layout.name;
    _notifyView();
  }

  /// saveArrangement keeps what is showing now as a layout of the reader's
  /// own, called [name].
  DockArrangement saveArrangement(String name) {
    var layout = DockArrangement(
      name,
      shown: {
        for (var place in _dock.placesShown)
          if (dockShownIn(place) case var panel?) place: panel
      },
      homes: {..._dock.homes},
      one: dockShownIn(DockPlace.main),
      chainMotion: chainShowsMotion,
    );
    var saved = [
      ..._dock.saved.where((a) => a.name != name),
      layout,
    ];
    _dock = _dock.copyWith(
        saved: saved.length > maxSavedArrangements
            ? saved.sublist(saved.length - maxSavedArrangements)
            : saved);
    _arrangementChosen = name;
    _notifyView();
    return layout;
  }

  /// removeArrangement forgets the reader's layout called [name].
  void removeArrangement(String name) {
    _dock = _dock.copyWith(
        saved: [..._dock.saved.where((a) => a.name != name)]);
    if (_arrangementChosen == name) _arrangementChosen = null;
    _notifyView();
  }

  /// _dockOpening is [panel] opening: whatever else is showing in its place
  /// closes, without telling anyone (the caller does).
  void _dockOpening(DockPanel panel) {
    var place = _dock.placeOf(panel);
    for (var other in DockPanel.values) {
      if (other != panel && dockOpen(other) && _dock.placeOf(other) == place) {
        _setDockRaw(other, false);
      }
    }
    _arrangementChosen = null;
  }

  /// _dockSettle leaves each place showing one panel at most, after the
  /// places or the homes change: the first open one, in the buttons' order.
  void _dockSettle() {
    var taken = <DockPlace>{};
    for (var panel in DockPanel.values) {
      if (!dockOpen(panel)) continue;
      if (!taken.add(_dock.placeOf(panel))) _setDockRaw(panel, false);
    }
  }

  /// _setDockRaw opens or closes [panel] and nothing else.
  void _setDockRaw(DockPanel panel, bool open) {
    switch (panel) {
      case DockPanel.timeline:
        _rowsShown = open;
      case DockPanel.slots:
        _slotsBeside = open;
      case DockPanel.mixer:
        _mixerOpen = open;
        if (!open) _mixerMinimised = _mixerSmallest = false;
      case DockPanel.chain:
        _animationOpen = open && _chainMotion;
        _effectsOpen = open && !_chainMotion;
    }
  }

  TimelineShow _timelineShow = TimelineShow.everything;

  /// timelineShow is the ⋯ menu's Show: everything, only the animation, or
  /// only the sound -- on the timeline and in the mixer alike.
  TimelineShow get timelineShow => _timelineShow;
  set timelineShow(TimelineShow value) {
    if (_timelineShow == value) return;
    _timelineShow = value;
    _notifyView();
  }

  bool _slotsBeside = false;

  /// slotsBeside is the Slots panel: each element's and channel's slots, in
  /// their place (see dock) -- beside the timeline's rows, lined up with
  /// them, when the slots are on the left and the timeline in main.
  bool get slotsBeside => _slotsBeside;
  set slotsBeside(bool value) {
    if (_slotsBeside == value) return;
    _slotsBeside = value;
    if (value) _dockOpening(DockPanel.slots);
    _notifyView();
  }

  /// slotsWithRows is the slots open beside the timeline's rows: the two
  /// drawn as one, a row of slots level with each row of the timeline.
  bool get slotsWithRows =>
      _slotsBeside &&
      _rowsShown &&
      _dock.placeOf(DockPanel.slots) == DockPlace.left &&
      _dock.placeOf(DockPanel.timeline) == DockPlace.main;

  /// slotCellWidth and slotCellHeight are a slot beside the rows: one size
  /// however wide the column or tall the row.
  static const double slotCellWidth = 72, slotCellHeight = 22;

  /// slotsShown is how many slots each row has: two to begin with, and one
  /// more past the last used -- by a clip in any element's or channel's
  /// slots, or a named cue -- never more than the cues there are. See
  /// _slotRowsGrown, which adds a cue as the last one fills.
  int get slotsShown {
    if (!identical(_slotsShownOf, _document)) {
      _slotsShownOf = _document;
      _slotsShownCount = math.min(session.rows,
          math.max(2, lastSlotUsed(_document) + 2));
    }
    return _slotsShownCount;
  }

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

  /// _slotRowsGrown is [next] with a cue added when its last is in use, so
  /// there is always an empty slot to fill. See slotsShown.
  static CanvasDocument _slotRowsGrown(CanvasDocument next) {
    var rows = next.session.rows;
    if (rows >= 256 || lastSlotUsed(next) < rows - 1) return next;
    return next.copyWith(session: next.session.withScene());
  }

  /// slotsColumn is the most the slots beside the rows take across, dragged
  /// by the grip between them and the time: they grow to it as they are
  /// filled, and scroll past it (see slotsScroll).
  double get slotsColumn => _slotsColumn;
  double _slotsColumn = slotsColumnDefault;
  static const double slotsColumnDefault = 6 * (slotCellWidth + 3) + 5,
      slotsColumnMin = slotCellWidth + 3 + 5,
      slotsColumnMax = 1600;

  set slotsColumn(double value) {
    var next = value.clamp(slotsColumnMin, slotsColumnMax).toDouble();
    if (next == _slotsColumn) return;
    _slotsColumn = next;
    _clampSlotsScroll();
    notifyListeners();
  }

  /// slotsContent is how wide every slot shown is, laid side by side.
  double get slotsContent => slotsShown * (slotCellWidth + 3) + 5;

  /// slotsScroll is how far the slots beside the rows are scrolled along,
  /// every row together: a notifier of its own, so a scroll redraws the
  /// slots and nothing else.
  final ValueNotifier<double> slotsScroll = ValueNotifier(0);

  /// scrollSlots scrolls the slots by [by] pixels, as far as there is more
  /// of them than the [shown] column (the slots beside the rows', unless
  /// given) shows.
  void scrollSlots(double by, {double? shown}) {
    slotsScroll.value = (slotsScroll.value + by)
        .clamp(0.0, math.max(0.0, slotsContent - (shown ?? slotsWidth)))
        .toDouble();
  }

  void _clampSlotsScroll() => scrollSlots(0);

  /// slotsWidth is the slots beside the rows, a cue each, or nought with
  /// them put away or the mixer in their place; leftWidth everything left
  /// of the lanes -- the strips and the slots -- which is where the time
  /// starts.
  double get slotsWidth =>
      slotsWithRows ? math.min(_slotsColumn, slotsContent) : 0;
  double get leftWidth => headerWidth + slotsWidth;

  /// canvasSnap is the bar's Snap: the page's snap switch on a page, and
  /// on a 3D stage the stage's own, which starts off -- both in the Grid
  /// and guides settings. Not [snapping], which is the timeline's.
  bool get canvasSnap =>
      onStage3d ? _document.guides.stageSnap : _document.guides.snap;

  set canvasSnap(bool value) {
    if (canvasSnap == value) return;
    var g = _document.guides;
    apply(_document.copyWith(
        guides: onStage3d
            ? g.copyWith(stageSnap: value)
            : g.copyWith(snap: value)));
  }

  /// steeredStage is the 3D stage the view controls steer: the one the
  /// selected element stands on, or else the scene's first -- the canvas
  /// background's, then a Background element's. Null where the scene has
  /// none, and the bar shows the page's tools.
  StageElement? get steeredStage {
    if (_selection.length == 1) {
      var spot = _document.elementById(_selection.first)?.base.spot;
      if (spot != null) {
        if (stageOf(spot.stage) case var s?) return s;
      }
    }
    for (var (id, _)
        in stagesIn(_document.elements, backdrop: _document.drawnBackground)) {
      if (stageOf(id) case var s?) return s;
    }
    return null;
  }

  /// onStage3d is whether the scene shows a 3D stage.
  bool get onStage3d => steeredStage != null;

  /// steer moves the steered stage's camera to [to] of where it is on this
  /// frame -- its own setting, or this frame's key where it is keyed.
  /// Nothing where there is no stage, or it is locked.
  void steer(StageCamera Function(StageCamera) to, {bool transient = false}) {
    var s = steeredStage;
    if (s == null || s.locked) return;
    putStage(stageFilmed(s, to(s.cameraAt(_frame))), transient: transient);
  }

  /// orbitBy swings the steered stage's camera round by [dx], [dy]
  /// degrees: across goes round the stage, down looks from higher.
  void orbitBy(double dx, double dy, {bool transient = false}) =>
      steer(
          (c) => c.copyWith(
              yaw: (c.yaw + dx + 540) % 360 - 180, pitch: c.pitch + dy),
          transient: transient);

  /// panCameraBy slides the steered stage's camera by [by], page units:
  /// the stage follows the pointer.
  void panCameraBy(Offset by, {bool transient = false}) {
    var s = steeredStage;
    if (s == null) return;
    var view = stageView(s, _frame);
    steer((c) => view.panned(by), transient: transient);
  }

  /// dollyBy takes the steered stage's camera [factor] times as far from
  /// what it looks at: below one nearer.
  void dollyBy(double factor, {bool transient = false}) =>
      steer((c) => c.copyWith(distance: c.distance * factor),
          transient: transient);

  /// frameSelected turns the steered stage's camera on the selected
  /// element, near enough to fill the view with it. Nothing unless one
  /// element standing on a stage is selected.
  void frameSelected() {
    if (_selection.length != 1) return;
    var e = _document.elementById(_selection.first);
    if (e == null) return;
    var at = stagedIn(_document, e, _frame);
    if (at == null) return;
    var spot = at.spot;
    var tall = e is Character3dElement
        ? 1.75
        : spot.height * e.height / math.max(1.0, math.max(e.width, e.height));
    var size = math.max(tall, spot.height);
    var middle = spot.stand == SpotStand.wall
        ? (spot.x, spot.lift + tall / 2, -at.stage.size)
        : (spot.x, spot.lift + tall / 2, spot.z);
    steer((c) => at.view.framing(middle.$1, middle.$2, middle.$3, size));
  }

  /// resetCamera puts the steered stage's camera back where a stage's
  /// camera starts, with its lens kept.
  void resetCamera() => steer((c) => StageCamera(lens: c.lens));

  CanvasTool _tool = CanvasTool.select;

  /// tool is what dragging on the canvas does. Select to begin with.
  CanvasTool get tool => _tool;

  set tool(CanvasTool value) {
    if (_tool == value) return;
    _tool = value;
    _notifyView();
  }

  /// hoveredButton is the button under the pointer, which the renderer needs
  /// so hover colours can be seen while they are being chosen.
  String? hoveredButton;

  Timer? _playback;
  bool get playing => _playback != null;

  /// _loopCounts tracks how many times each loop marker has fired, so a marker
  /// with a repeat limit stops rather than running forever.
  final Map<int, int> _loopCounts = {};

  /// _stoppedAt is the frame a stop marker last stopped playback on.
  int? _stoppedAt;

  bool _opened = false;

  /// opened is whether this session has ever been shown. The session
  /// outlives the page, so only the first visit restores what was last saved;
  /// later ones would throw away the work in progress.
  bool get opened => _opened;

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

  /// dirty is whether there are changes the file on disk does not have. Set
  /// by [apply] rather than by comparing documents: comparing deeply on every
  /// keystroke is expensive, and an edit that restores the saved state is
  /// still an edit.
  bool get dirty => _dirty;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// selectedElements are the chosen elements in paint order, which is the
  /// order every multi-element operation wants.
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

  /// apply replaces the document, pushing the old one onto the undo history.
  /// [transient] skips the history, for the many small changes inside one
  /// gesture; [beginInteraction] already remembered where it started.
  void apply(CanvasDocument next, {bool transient = false}) {
    _endPreview();
    if (identical(next, _document)) return;
    // A linked copy changed in what it shares changes its Cast member, and
    // every other copy with it (see cast.dart).
    next = castSynced(_document, next);
    // Each synth speaker's channel plays the patch its modules make.
    next = synthSynced(next);

    // A picture's frame takes in what was put past it once a change is made,
    // not at every step of a drag, whose sums start from where things were
    // when it began. See endInteraction, and changePaint.
    if (!transient) next = _slotRowsGrown(_imagesGrown(next, _document));

    var was = _document;
    if (!transient && _interaction == null) {
      _undo.add(_document);
      if (_undo.length > _maxUndo) _undo.removeAt(0);
      _redo.clear();
    }

    _document = next;
    _edits++;
    scheduleAutosave();

    // A selection can outlive the elements it names (a delete, another
    // document); pruning here spares every reader an id that resolves to
    // nothing.
    _selection = _selection.where((id) => _document.elementById(id) != null).toSet();

    if (_frame >= _document.frames) _frame = _document.frames - 1;

    // A sound whose element has gone goes with it, and one on the timeline
    // goes where its new settings put it.
    _audioFollowsPage(turned: false);
    _syncTimeline();
    _scheduleParts();
    if (!transient && _interaction == null) _followEdits(was);

    notifyListeners();
  }

  /// _imagesGrown is [next] with the frame of every picture changed since
  /// [was] grown to take in what is drawn in it. See
  /// ImageElement.grownToFit.
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

  /// interacting is whether a gesture is under way (a drag, a number being
  /// scrubbed), which the canvas draws a little faster for.
  bool get interacting => _interaction != null;

  /// beginInteraction starts a gesture: everything until [endInteraction] is
  /// one undo step.
  void beginInteraction() {
    _endPreview();
    _interaction ??= _document;
  }

  /// endInteraction closes the gesture, pushing its starting document onto the
  /// history if anything actually changed.
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
    // A gesture still open is closed first, so what it did is the step taken
    // back rather than pushed later on top of the undo.
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

  /// _beforePreview is the document as it really is while a setting is being
  /// tried on the canvas -- see tryElement -- and null otherwise.
  CanvasDocument? _beforePreview;

  /// trying is whether the canvas is showing a setting being tried.
  bool get trying => _beforePreview != null;

  /// tryElement shows [element] on the canvas in place of the one it
  /// replaces, without it being an edit: not in the undo history, not saved,
  /// and gone with a null or with the next real edit. For previewing the
  /// options of a list before one is chosen.
  void tryElement(CanvasElement? element) {
    if (element == null) {
      if (_endPreview()) notifyListeners();
      return;
    }
    _beforePreview ??= _document;
    _document = _beforePreview!.withElement(element);
    notifyListeners();
  }

  /// _endPreview puts the document back as it really is, and says whether
  /// there was a preview to end.
  bool _endPreview() {
    var before = _beforePreview;
    if (before == null) return false;
    _beforePreview = null;
    _document = before;
    return true;
  }

  /// withCountLaidOut is a new keyframed counter with its count pinned: its
  /// start where the playhead is and its finish two seconds on, or the two
  /// seconds before the end when the playhead is too near it. Otherwise From
  /// and To would do nothing until both were pinned by hand.
  CounterElement withCountLaidOut(CounterElement e) {
    var last = _document.frames - 1;
    if (!e.keyed || e.track != null || last < 1) return e;
    var rate = math.max(1, _document.frameRate);
    var start = _frame.clamp(0, last);
    var end = math.min(last, start + rate * 2);
    if (end - start < rate ~/ 2) {
      end = last;
      start = math.max(0, last - rate * 2);
    }
    return e.withBase(
        track: ElementTrack([
      Keyframe(frame: start).withValue(KeyframeChannel.count, e.from),
      Keyframe(frame: end).withValue(KeyframeChannel.count, e.to),
    ])) as CounterElement;
  }

  /// replaceElement applies a change to one element.
  void replaceElement(CanvasElement element, {bool transient = false}) =>
      apply(_document.withElement(element), transient: transient);

  void addElement(CanvasElement element, {bool select = true}) {
    if (element is CounterElement) element = withCountLaidOut(element);
    var next = _document.addElement(element);
    // A stage is the set everything else is played in front of.
    if (element is StageElement ||
        (element is BackgroundElement && element.isStage)) {
      next = next.reorder(next.elements.length - 1, 0);
    }
    apply(next);
    if (select) selectOnly(element.id);
  }

  void deleteSelected() {
    // While a drawing is being edited, Delete takes out the points picked,
    // or the shape picked -- and with neither, nothing: never the drawing.
    if (editingVector != null) {
      deleteVectorPoint();
      return;
    }
    // Clips picked together on the timeline: those placings, not their
    // elements -- and then the sounds picked with them, which are elements.
    if (_motionPicks.length > 1) {
      beginInteraction();
      for (var (element, placement) in _motionPicks) {
        removePlacement(element, placement);
      }
      _motionPicks = const {};
      _pickedMotion = _pickedPlacement = null;
      var sounds = {..._selection, ..._offCanvas}
          .where((id) => _document.elementById(id) is AudioElement ||
              _offCanvas.contains(id))
          .toSet();
      _selection = {
        for (var id in _selection)
          if (sounds.contains(id)) id
      };
      if (_selection.isEmpty && _offCanvas.isEmpty) {
        endInteraction();
        notifyListeners();
        return;
      }
      deleteSelected();
      endInteraction();
      return;
    }
    // A clip picked on the timeline: that placing of it, not the element.
    if ((pickedPlacement, _selection.length) case (var p?, 1)) {
      var element = _selection.first;
      _pickedMotion = null;
      _pickedPlacement = null;
      removePlacement(element, p);
      return;
    }
    if (_selection.isEmpty && _offCanvas.isEmpty) return;
    var next = _document;
    for (var id in _selection) {
      next = next.removeElement(id);
      // Its own sound's channel goes with it: see element_sound.dart.
      var own = "snd-$id";
      for (var e in [...next.elements]) {
        if (e is AudioElement && e.clip.channel == own) {
          next = next.removeElement(e.id);
        }
      }
    }
    // And the clips picked on the timeline from another canvas (another
    // scene's, or the master's), which are as much on the timeline as this
    // scene's.
    for (var id in _offCanvas) {
      next = _removedAnywhere(next, id);
    }
    _selection = {};
    _offCanvas = const {};
    apply(next);
  }

  /// _removedAnywhere is [doc] without element [id], wherever it is.
  CanvasDocument _removedAnywhere(CanvasDocument doc, String id) {
    if (doc.elements.any((e) => e.id == id)) return doc.removeElement(id);
    var master = doc.master;
    if (master != null && master.elements.any((e) => e.id == id)) {
      return doc.copyWith(
          master: master.copyWith(elements: [
        for (var e in master.elements)
          if (e.id != id) e,
      ]));
    }
    for (var (i, scene) in doc.allScenes.indexed) {
      if (!scene.elements.any((e) => e.id == id)) continue;
      return doc.withScene(
          i,
          scene.copyWith(elements: [
            for (var e in scene.elements)
              if (e.id != id) e,
          ]));
    }
    return doc;
  }

  /// clipRunStart is where element [id]'s clip starts on the run's clock --
  /// its canvas's start and its own -- or null for one not on a canvas.
  int? clipRunStart(String id) {
    var start = _canvasStart(id);
    if (start == null) return null;
    CanvasElement? found;
    _everyElement(_document, (e, _) {
      if (e.id == id) found = e;
      return e;
    });
    var clip = switch (found) {
      AudioElement a => a.clip,
      VideoElement v => v.clip,
      _ => null,
    };
    return clip == null ? null : start + clip.at;
  }

  /// placeTimedClip puts [e]'s [clip] at frame [run] of the whole run. A clip
  /// on a scene goes to the scene [run] falls in, so one dragged past the end
  /// of its own becomes the next one's; one on the master goes where it is
  /// put, and one on the backdrop as before.
  void placeTimedClip(CanvasElement e, MediaClip clip, int run,
      {bool transient = false}) {
    run = math.max(0, run);
    var master = _document.master;
    var onMaster = master != null && master.elements.any((x) => x.id == e.id);
    int? from;
    for (var (i, scene) in _document.allScenes.indexed) {
      if (scene.elements.any((x) => x.id == e.id)) from = i;
    }
    // The master and a document of one scene run on the run's own clock.
    if (onMaster || from == null || !_document.hasScenes) {
      setTimedClip(e, clip.copyWith(at: run), transient: transient);
      return;
    }
    var scenes = _document.allScenes;
    var to = scenes.length - 1;
    for (var i = 0; i < scenes.length; i++) {
      if (run < _document.startOfScene(i) + scenes[i].frames) {
        to = i;
        break;
      }
    }
    var at = run - _document.startOfScene(to);
    if (to == from) {
      setTimedClip(e, clip.copyWith(at: at), transient: transient);
      return;
    }
    var placed = switch (e) {
      VideoElement v => v.copyWith(clip: clip.copyWith(at: at)),
      AudioElement a => a.copyWith(clip: clip.copyWith(at: at)),
      _ => null,
    };
    if (placed == null) return;
    var next = _removedAnywhere(_document, e.id);
    var scene = next.allScenes[to];
    next = next.withScene(
        to, scene.copyWith(elements: [...scene.elements, placed]));
    // Still picked, wherever it has gone: on this canvas it is part of the
    // selection, and off it one of the clips picked elsewhere.
    var picked = clipSelection.contains(e.id);
    apply(next, transient: transient);
    if (picked) {
      _selection = {..._selection}..remove(e.id);
      _offCanvas = {..._offCanvas}..remove(e.id);
      if (_onCanvas(e.id)) {
        _selection = {..._selection, e.id};
      } else {
        _offCanvas = {..._offCanvas, e.id};
      }
      notifyListeners();
    }
  }

  /// deleteElement takes out the element [id] -- a layers row's delete, for
  /// screens with no Delete key. Being edited, its editing is put down first.
  void deleteElement(String id) {
    if (_document.elementById(id) == null) return;
    if (_vectorEditing == id) editVector(null);
    if (editingImage?.id == id) editImage(null);
    _selection = {..._selection}..remove(id);
    apply(_document.removeElement(id));
  }

  /// duplicateSelected copies the chosen elements, offset a little so the copy
  /// is visibly a second thing.
  void duplicateSelected() {
    if (_selection.isEmpty) return;
    var next = _document;
    var made = <String>{};
    var ids = <String, String>{};
    for (var element in selectedElements) {
      var copy = element
          .withId(newElementId())
          .withBase(x: element.x + 24, y: element.y + 24);
      next = next.addElement(copy);
      made.add(copy.id);
      ids[element.id] = copy.id;
    }
    // Synth modules copied together patched to each other, not the
    // originals.
    apply(synthCopied(next, ids));
    _selection = made;
    notifyListeners();
  }

  /// _clipboard is what was last copied. Held here rather than on the system
  /// clipboard: an element has no sensible text form, and JSON there would
  /// replace whatever the reader had copied elsewhere. Static, so a copy
  /// survives leaving the page.
  static List<CanvasElement> _clipboard = const [];

  /// _pasteOffset is how far each paste is stepped down and right, so each
  /// paste is visibly another copy.
  static const double _pasteOffset = 16;

  /// canPaste is whether there is anything to paste.
  bool get canPaste => _clipboard.isNotEmpty;

  /// copySelected puts the selection on the clipboard, with the clips picked
  /// on the timeline from another canvas (such as the master's music picked
  /// from a scene, which is not in the selection).
  void copySelected() {
    var chosen = [...selectedElements];
    if (_offCanvas.isNotEmpty) {
      _everyElement(_document, (e, _) {
        if (_offCanvas.contains(e.id)) chosen.add(e);
        return e;
      });
    }
    if (chosen.isEmpty) return;
    _clipboard = List.unmodifiable(chosen);
    notifyListeners();
  }

  /// _canvasStart is where the canvas holding element [id] starts on the
  /// run's clock -- 0 for the master, which runs on it -- or null when it is
  /// not on one: copied from somewhere since taken out.
  int? _canvasStart(String id) {
    var master = _document.master;
    if (master != null && master.elements.any((e) => e.id == id)) return 0;
    for (var (i, scene) in _document.allScenes.indexed) {
      if (scene.elements.any((e) => e.id == id)) {
        return _document.startOfScene(i);
      }
    }
    return null;
  }

  /// cutSelected copies and then deletes.
  void cutSelected() {
    if (_selection.isEmpty && _offCanvas.isEmpty) return;
    copySelected();
    deleteSelected();
  }

  /// paste drops the clipboard onto the canvas and selects what it added:
  /// with new ids, in their order relative to each other, on top.
  void paste() {
    if (_clipboard.isEmpty) return;
    var next = _document;
    var made = <String>{};
    var ids = <String, String>{};
    var elsewhere = <String>{};
    for (var element in _clipboard) {
      CanvasElement copy;
      var timed = (element is AudioElement && element.clip.timed) ||
          (element is VideoElement && element.clip.timed);
      // A clip from the master, copied from a scene, goes back onto the
      // master beside the one copied, at the playhead on the run's clock. One
      // from another scene comes to the scene the playhead is in: sent back
      // to its own at a frame past its end, it would never play.
      var away = timed &&
              !_onCanvas(element.id) &&
              (_document.master?.elements.any((e) => e.id == element.id) ??
                  false)
          ? 0
          : null;
      var at = away == null ? _frame : math.max(0, runFrame - away);
      if (element is AudioElement && element.clip.timed) {
        // A sound on the timeline goes where the playhead is, on the channel
        // it was copied from -- which is how one channel comes to hold two.
        copy = element
            .copyWith(clip: element.clip.copyWith(at: at))
            .withId(newElementId());
      } else if (element is VideoElement && element.clip.timed) {
        // And a video on the timeline the same: at the playhead, in the same
        // place on the canvas -- the same shot, later.
        copy = element
            .copyWith(clip: element.clip.copyWith(at: at))
            .withId(newElementId());
      } else {
        copy = element
            .withId(newElementId())
            .withBase(x: element.x + _pasteOffset, y: element.y + _pasteOffset);
      }
      if (away != null) {
        if (_addedBeside(next, element.id, copy) case var added?) {
          next = added;
          elsewhere.add(copy.id);
          continue;
        }
      }
      made.add(copy.id);
      ids[element.id] = copy.id;
      next = next.addElement(copy);
    }
    apply(synthCopied(next, ids));
    _backgroundSelected = false;
    _focusedPlayer = null;
    _selection = made;
    // Picked where they went, as a click on them would pick them.
    _offCanvas = elsewhere;
    notifyListeners();
  }

  /// duplicateElement is the layer list's button: copy and paste in one
  /// press. The clipboard is left alone, so whatever was copied is kept.
  void duplicateElement(String id) {
    var element = _document.elementById(id);
    if (element == null) return;
    var copy = element
        .withId(newElementId())
        .withBase(x: element.x + _pasteOffset, y: element.y + _pasteOffset);
    apply(synthCopied(_document.addElement(copy), {id: copy.id}));
    _backgroundSelected = false;
    _focusedPlayer = null;
    _selection = {copy.id};
    notifyListeners();
  }

  /// nudgeSelected moves everything chosen: the arrow keys.
  void nudgeSelected(double dx, double dy, {bool transient = false}) {
    if (_selection.isEmpty) return;
    // With a picture's layers open and picture layers picked, the arrows
    // move those layers inside it; with the base picked, the picture.
    if (editingImage case var e?) {
      var ids = [for (var l in alignableLayers) l.id];
      if (ids.isNotEmpty) {
        replaceElement(withLayersMoved(e, ids, Offset(dx, dy)),
            transient: transient);
        return;
      }
    }
    var next = _document;
    for (var element in selectedElements) {
      if (element.locked) continue;
      next = next.withElement(_moved(element, dx, dy));
    }
    apply(next, transient: transient);
  }

  /// alignSelected lines every chosen element up on one edge or middle,
  /// against the selection's own box rather than the canvas (the guides and
  /// snapping are for that). One element is therefore a no-op, and the
  /// buttons are dead until there are two.
  void alignSelected(CanvasAlign align, {bool transient = false}) {
    // With a picture's layers open, its picked layers -- against the box
    // they make between them, as elements are.
    if (editingImage case var e?) {
      var ids = [for (var l in alignableLayers) l.id];
      if (ids.length >= 2) {
        replaceElement(withLayersAligned(e, ids, align), transient: transient);
      }
      return;
    }
    var chosen = [
      for (var e in selectedElements)
        if (!e.locked) e
    ];
    if (chosen.length < 2) return;

    Rect? box;
    for (var element in chosen) {
      box = box == null ? element.bounds : box.expandToInclude(element.bounds);
    }
    if (box == null) return;

    var next = _document;
    for (var element in chosen) {
      var at = element.bounds;
      var dx = switch (align) {
        CanvasAlign.left => box.left - at.left,
        CanvasAlign.centreX => box.center.dx - at.center.dx,
        CanvasAlign.right => box.right - at.right,
        _ => 0.0,
      };
      var dy = switch (align) {
        CanvasAlign.top => box.top - at.top,
        CanvasAlign.middleY => box.center.dy - at.center.dy,
        CanvasAlign.bottom => box.bottom - at.bottom,
        _ => 0.0,
      };
      if (dx == 0 && dy == 0) continue;
      next = next.withElement(_moved(element, dx, dy));
    }
    apply(next, transient: transient);
  }

  /// spreadSelected puts an even gap between the chosen elements: the two on
  /// the ends stay and the rest move, so it needs three. Even gaps rather
  /// than even centres, since elements of different sizes spaced by centre
  /// leave visibly different gaps.
  void spreadSelected(bool across, {bool transient = false}) {
    if (editingImage case var e?) {
      var ids = [for (var l in alignableLayers) l.id];
      if (ids.length >= 3) {
        replaceElement(withLayersSpread(e, ids, across), transient: transient);
      }
      return;
    }
    var chosen = [
      for (var e in selectedElements)
        if (!e.locked) e
    ];
    if (chosen.length < 3) return;
    chosen.sort((a, b) => across
        ? a.bounds.left.compareTo(b.bounds.left)
        : a.bounds.top.compareTo(b.bounds.top));

    var first = chosen.first.bounds;
    var last = chosen.last.bounds;
    var span = across ? last.right - first.left : last.bottom - first.top;
    var filled = chosen.fold<double>(
        0, (sum, e) => sum + (across ? e.bounds.width : e.bounds.height));
    var gap = (span - filled) / (chosen.length - 1);

    var next = _document;
    var at = across ? first.left : first.top;
    for (var element in chosen) {
      var bounds = element.bounds;
      var shift = at - (across ? bounds.left : bounds.top);
      if (shift != 0) {
        next = next.withElement(
            _moved(element, across ? shift : 0, across ? 0 : shift));
      }
      at += (across ? bounds.width : bounds.height) + gap;
    }
    apply(next, transient: transient);
  }

  /// posesRatherThanMoves is whether dragging [element] should record a
  /// keyframe instead of relocating it.
  ///
  /// A keyframe's dx and dy are offsets from the element's resting position,
  /// so moving the rest moves every keyframe with it; a drag meant as a pose
  /// would record nothing. So a drag poses when the document is animated and
  /// either auto-keyframe is on or the element has already been posed. The X
  /// and Y fields still move the rest, and the animation with it.
  ///
  /// Posed, not merely keyed: a chart given an arrival preset has keys that
  /// say only how much is drawn, and dragging it should move it.
  bool posesRatherThanMoves(CanvasElement element) =>
      _document.isAnimated &&
      // Never for something a path is driving: a pose written by a drag would
      // be overwritten the next time a point moved, so the drag moves its
      // start instead and the whole run travels with it.
      pathDriving(element.id) == null &&
      (_autoKeyframe || (element.track?.posesAnything == true));

  /// _moved is one element shifted, as either a pose or a relocation.
  CanvasElement _moved(CanvasElement element, double dx, double dy) {
    if (!posesRatherThanMoves(element)) {
      return element.withBase(x: element.x + dx, y: element.y + dy);
    }
    var track = (element.track ?? ElementTrack.empty).seededFor(_frame);
    var pose = track.at(_frame);
    return element.withBase(
      track: track.withKey(
          pose.copyWith(frame: _frame, dx: pose.dx + dx, dy: pose.dy + dy)),
    );
  }

  /// movedTo is the stage's drag: where [element]'s top-left should now be.
  /// An absolute target rather than a delta, since accumulated deltas drift
  /// and on a pose would compound into the keyframe.
  CanvasElement movedTo(CanvasElement element, Offset topLeft) {
    // Something on a stage is moved across its floor -- or up and along its
    // back wall -- to under where it has been dragged to.
    if (element.base.spot != null) {
      var at = stagedIn(_document, element, _frame);
      if (at != null) {
        // Where it stands on this frame, keyed or its own; where it is keyed,
        // the move is a key on this frame.
        var spot = at.spot;
        var by = topLeft - at.box.topLeft;
        var view = at.view;
        // Snapping, it lands on the 3D steps -- there are no lines on a
        // stage to land on.
        var step =
            _document.guides.stageSnap ? _document.guides.stageStep : 0.0;
        double snap(double v) =>
            step > 0 ? (v / step).roundToDouble() * step : v;
        switch (spot.stand) {
          case SpotStand.wall:
            var was = view.toWall(at.box.bottomCenter, -at.stage.size + 0.01);
            var now = view.toWall(at.box.bottomCenter + by,
                -at.stage.size + 0.01);
            if (was == null || now == null) return element;
            return spotted(
                element,
                spot.copyWith(
                    x: snap(spot.x + now.dx - was.dx),
                    lift: snap(spot.lift + now.dy - was.dy)));
          default:
            // The point on the floor under the pointer moves as the pointer
            // does, on the level the element is lifted to, so it stays under
            // the hand.
            var level = spot.stand == SpotStand.floor ? 0.0 : spot.lift;
            var was = view.toFloor(at.foot, y: level),
                now = view.toFloor(at.foot + by, y: level);
            if (was == null || now == null) return element;
            return spotted(
                element,
                spot.copyWith(
                    x: snap(spot.x + now.dx - was.dx),
                    z: snap(spot.z + now.dy - was.dy)));
        }
      }
    }
    if (!posesRatherThanMoves(element)) {
      return element.withBase(x: topLeft.dx, y: topLeft.dy);
    }
    var track = (element.track ?? ElementTrack.empty).seededFor(_frame);
    var pose = track.at(_frame);
    return element.withBase(
      track: track.withKey(pose.copyWith(
        frame: _frame,
        dx: topLeft.dx - element.x,
        dy: topLeft.dy - element.y,
      )),
    );
  }

  /// cameraShifted is [start] -- a camera as a drag began -- looking [by]
  /// further across and down: a keyframe on this frame where it is
  /// animated, else its box moved. Kept to what the framing allows (the
  /// picture stays on the page), so a drag past the edge does not leave a
  /// pose the frame cannot follow (Ken, 2026-11-14: the camera was hard to
  /// move; a keyed one jumped, moved by the frame's corner, not its box's).
  CanvasElement cameraShifted(CameraElement start, Offset by) {
    var page = _document.size.rect;
    var (zoom, _) = cameraFraming(start, _frame, _document);
    var roll = cameraLookAt(start, _frame, _document).roll;
    var (hx, hy) = cameraHalfExtents(zoom, roll, page.size);
    var posed = posesRatherThanMoves(start);
    var track = (start.track ?? ElementTrack.empty).seededFor(_frame);
    var pose = posed ? track.at(_frame) : Keyframe.rest;
    var centre = start.bounds.center + Offset(pose.dx, pose.dy) + by;
    var kept = Offset(centre.dx.clamp(page.left + hx, page.right - hx),
        centre.dy.clamp(page.top + hy, page.bottom - hy));
    var moved = kept - (start.bounds.center + Offset(pose.dx, pose.dy));
    if (!posed) {
      return start.withBase(x: start.x + moved.dx, y: start.y + moved.dy);
    }
    return start.withBase(
        track: track.withKey(pose.copyWith(
            frame: _frame, dx: pose.dx + moved.dx, dy: pose.dy + moved.dy)));
  }

  /// cameraZoomed is [start] -- a camera as a drag began -- [factor] times
  /// closer (below one, further), about the middle of what it shows: a
  /// keyframe's size where it is animated, else its box. Never further out
  /// than the whole page, nor closer than eight times.
  CanvasElement cameraZoomed(CameraElement start, double factor) {
    if (!factor.isFinite || factor <= 0) return start;
    var (zoom, at) = cameraFraming(start, _frame, _document);
    var next = (zoom * factor).clamp(1.0, 8.0);
    var by = next / zoom;
    CanvasElement out;
    if (posesRatherThanMoves(start)) {
      var track = (start.track ?? ElementTrack.empty).seededFor(_frame);
      var pose = track.at(_frame);
      // Where it looks stays put: the pose's shift is from its box's middle.
      out = start.withBase(
          track: track.withKey(pose.copyWith(
              frame: _frame,
              scale: pose.scale * by,
              dx: at.dx - start.bounds.center.dx,
              dy: at.dy - start.bounds.center.dy)));
    } else {
      var w = start.width / by, h = start.height / by;
      out = start.withBase(
          x: at.dx - w / 2, y: at.dy - h / 2, width: w, height: h);
    }
    // Further out near an edge, the framing moves it back onto the page.
    var cam = out as CameraElement;
    var (_, now) = cameraFraming(cam, _frame, _document.withElement(cam));
    var raw = cam.bounds.center +
        (posesRatherThanMoves(cam)
            ? Offset((cam.track ?? ElementTrack.empty).at(_frame).dx,
                (cam.track ?? ElementTrack.empty).at(_frame).dy)
            : Offset.zero);
    if ((now - raw).distance > 1e-6) {
      return cameraShifted(cam, now - raw);
    }
    return cam;
  }

  /// pathDriving is the path that owns [elementId]'s keyframes, if one does.
  /// A follower's track is rewritten whenever the route or its timing
  /// changes, so the timeline refuses hand edits to it and shows the path's
  /// points instead.
  PathElement? pathDriving(String elementId, {int? playerIndex}) {
    for (var element in _document.elements) {
      if (element is! PathElement) continue;
      var follow = element.follow;
      if (follow == null || follow.elementId != elementId) continue;
      if (follow.playerIndex != playerIndex) continue;
      return element;
    }
    return null;
  }

  /// applyPathFollow writes [path]'s route into its follower's keyframes.
  ///
  /// Baked rather than evaluated live, so the renderer, the GIF encoder and a
  /// published canvas play it as any other track and cannot disagree. The
  /// follower's keyframes are owned by the path, as the settings say. One
  /// keyframe per frame between the first node and the last, sampled by arc
  /// length (see PathElement.positionOnSegment).
  void applyPathFollow(PathElement path) {
    var follow = path.follow;
    if (follow == null || path.nodes.length < 2) return;

    var target = _document.elementById(follow.elementId);
    if (target == null) return;

    var from = path.firstFrame;
    var to = path.lastFrame;
    if (to <= from) return;

    var index = follow.playerIndex;
    if (target is TeamElement && index != null) {
      if (index < 0 || index >= target.players.length) return;
      var spot = target.players[index];
      // On a pitch, every point of the route is carried down onto the
      // pitch's own metres, so the follower keeps to the curve as drawn
      // however the pitch is seen.
      var ground = teamGround(_document, target, from);
      if (ground != null) {
        replaceElement(target.withPlayer(
            index,
            spot.copyWith(
                track: _bakeOnPitch(path, ground, target, spot, from, to))));
        return;
      }
      var rest = target.centreOf(spot);
      replaceElement(target.withPlayer(
          index, spot.copyWith(track: _bake(path, rest, from, to))));
      return;
    }

    // An element is placed by its top-left, so the route, which describes
    // where the thing is, is measured from its centre and shifted back.
    replaceElement(
        target.withBase(track: _bake(path, target.center, from, to)));
  }

  /// _bakeOnPitch is [_bake] for a player standing on a pitch: the route's
  /// points found on the field, and kept as a run in the units a run on a
  /// pitch is kept in -- see playerPlace.
  ElementTrack _bakeOnPitch(PathElement path, TeamGround ground,
      TeamElement team, PlayerSpot spot, int from, int to) {
    var rest = teamFieldPoint(team, spot, ground.place);
    var ref = ground.place.reference;
    var keys = <Keyframe>[];
    for (var f = from; f <= to; f++) {
      var at = path.positionAtFrame(f);
      if (at == null) continue;
      var field = ground.field(at);
      if (field == null) continue;
      keys.add(Keyframe(
          frame: f,
          dx: (field.dx - rest.dx) * ref,
          dy: -(field.dy - rest.dy) * ref));
    }
    return ElementTrack(keys);
  }

  /// _bake turns a path into a track of poses relative to [rest].
  ElementTrack _bake(PathElement path, Offset rest, int from, int to) {
    var keys = <Keyframe>[];
    for (var f = from; f <= to; f++) {
      var at = path.positionAtFrame(f);
      if (at == null) continue;
      keys.add(Keyframe(frame: f, dx: at.dx - rest.dx, dy: at.dy - rest.dy));
    }
    return ElementTrack(keys);
  }

  /// clearPathFollow takes the baked keyframes back off, as unlinking a
  /// follower must, or the element is stranded on the route.
  void clearPathFollow(PathElement path) {
    var follow = path.follow;
    if (follow == null) return;
    var target = _document.elementById(follow.elementId);
    if (target == null) return;

    var index = follow.playerIndex;
    if (target is TeamElement && index != null) {
      if (index < 0 || index >= target.players.length) return;
      replaceElement(target.withPlayer(
          index, target.players[index].copyWith(clearTrack: true)));
      return;
    }
    replaceElement(target.withBase(clearTrack: true));
  }

  /// followerLabel names what a path is attached to, for the settings.
  String followerLabel(PathFollow? follow) {
    if (follow == null) return "Nothing";
    var target = _document.elementById(follow.elementId);
    if (target == null) return "Missing";
    var index = follow.playerIndex;
    if (target is TeamElement &&
        index != null &&
        index < target.players.length) {
      var spot = target.players[index];
      var who = spot.name.isNotEmpty ? spot.name : "#${spot.number}";
      return "$who (${target.name})";
    }
    return target.name;
  }

  /// setPlayerKeyframe writes one player's pose at the current frame.
  void setPlayerKeyframe(String teamId, int index, Keyframe key) {
    var team = _document.elementById(teamId);
    if (team is! TeamElement || index < 0 || index >= team.players.length) {
      return;
    }
    var spot = team.players[index];
    replaceElement(team.withPlayer(index,
        spot.copyWith(track: (spot.track ?? ElementTrack.empty).withKey(key))));
  }

  /// valueAt reads an animatable extra channel at the current frame, falling
  /// back to [orElse] when nothing has been keyed. See KeyframeChannel.
  double valueAt(CanvasElement element, String channel, double orElse) =>
      element.poseAt(_frame).values[channel] ?? orElse;

  /// hasValueKey is whether [channel] is pinned on this exact frame: what its
  /// diamond shows.
  bool hasValueKey(CanvasElement element, String channel) =>
      element.track?.keyAt(_frame)?.values.containsKey(channel) ?? false;

  /// setValueKey pins one extra property at the current frame.
  ///
  /// Seeded at the start like every other first keyframe, so one press makes
  /// a movement rather than a value for the whole document (see
  /// ElementTrack.seededFor). A counter passes [seed] false: the seed is a
  /// resting pose, which marks the element as animated in space (see
  /// ElementTrack.posesAnything), and a count needs none since its first key
  /// holds for every frame before it.
  void setValueKey(CanvasElement element, String channel, double value,
      {bool seed = true}) {
    var track = seed
        ? (element.track ?? ElementTrack.empty).seededFor(_frame)
        : (element.track ?? ElementTrack.empty);
    var at = track.at(_frame);
    replaceElement(element.withBase(
        track: track
            .withKey(at.copyWith(frame: _frame).withValue(channel, value))));
  }

  /// clearValueKey takes one property off this frame's keyframe, and the
  /// keyframe with it when that was all it held.
  void clearValueKey(CanvasElement element, String channel) {
    var track = element.track;
    var at = track?.keyAt(_frame);
    if (track == null || at == null) return;
    var without = at.withoutValue(channel);
    var next = without.isRest && without.frame != 0
        ? track.withoutFrame(_frame)
        : track.withKey(without);
    replaceElement(withTrackOrNone(element, next));
  }

  /// lipSync gives [e] the mouths for what is said on [voice]: from the
  /// words (heard first if they have not been), or with [words] off from the
  /// loudness alone. Mouths it laid before over the same stretch are
  /// replaced. One undo step. Returns what stopped it, or how many mouths it
  /// laid.
  Future<({String? problem, int mouths})> lipSync(
      CanvasElement e, AudioElement voice,
      {bool words = true, LipSyncFeel feel = const LipSyncFeel()}) async {
    var source = voice.clip.playlist.firstOrNull;
    if (source == null) {
      return (problem: "That sound has nothing in it to hear.", mouths: 0);
    }
    var rate = math.max(1, _document.frameRate);
    var length = source.length > 0 ? source.length : 0.0;
    var from = source.start, to = source.end > 0 ? source.end : length;
    // Where the voice starts and stops in the run, and where the
    // character's own frames start.
    var voiceAt = _clipOffset(voice) + voice.clip.at;
    var voiceEnd = voiceAt + ((to - from) * rate).ceil();
    var mine = _clipOffset(e);

    List<MouthKey> keys;
    if (words) {
      var tag = "voice:${voice.id}";
      // A Speech device take knows its words and their timing: read from it
      // rather than heard again.
      var said = _takeWords(voice, voiceAt, rate) ??
          [
            for (var w in this.words)
              if (w.from == tag) w,
          ];
      if (said.isEmpty) {
        var problem = await hearWords(voice);
        if (problem != null) return (problem: problem, mouths: 0);
        said = [
          for (var w in this.words)
            if (w.from == tag) w,
        ];
      }
      keys = mouthsFromWords(said, frameRate: rate, feel: feel);
    } else {
      if (length <= 0) {
        return (
          problem: "That recording's length is not known yet.",
          mouths: 0
        );
      }
      var file =
          await CanvasMedia.existingPath(MediaKind.audio, source.assetId);
      if (file == null) {
        return (
          problem: "The recording is missing from the library.",
          mouths: 0
        );
      }
      // A hundred readings a second: the timeline's own waveform is too thin
      // for a mouth on a long recording.
      var count = math.max(1, (length * 100).ceil());
      var peaks = await audio.engine.peaks(file, count);
      if (peaks == null) {
        return (problem: "That recording could not be read.", mouths: 0);
      }
      var a = (from / length * count).floor().clamp(0, count);
      var b = (to / length * count).ceil().clamp(a, count);
      keys = mouthsFromLoudness(Float32List.sublistView(peaks, a, b), to - from,
          startFrame: voiceAt, frameRate: rate, feel: feel);
    }

    // Read again: the character may have been changed while listening.
    var now = _document.elementById(e.id);
    if (now is Character3dElement) {
      // A 3D character's mouths are in seconds of its own scene.
      var local = [
        for (var k in keys)
          if (k.frame - mine >= 0) (t: (k.frame - mine) / rate, shape: k.shape),
      ];
      replaceElement(now.performing(now.performance.withMouths(local,
          from: math.max(0, voiceAt - mine - feel.lead - 1) / rate,
          to: (voiceEnd - mine + 1) / rate)));
      return (problem: null, mouths: local.length);
    }
    return (problem: null, mouths: 0);
  }

  /// _takeWords are the words of [voice] where it is a Speech device's take,
  /// as run frames from [voiceAt], only those its trim keeps. Null for any
  /// other sound.
  List<SpokenWord>? _takeWords(AudioElement voice, int voiceAt, int rate) {
    var source = voice.clip.playlist.firstOrNull;
    if (source == null) return null;
    var take = voice.clip.mix.speech?.takes
        .where((t) => t.assetId == source.assetId)
        .firstOrNull;
    if (take == null || take.words.isEmpty) return null;
    var end = source.end > 0 ? source.end : take.length;
    return [
      for (var w in take.words)
        if (w.end > source.start && w.start < end)
          SpokenWord(
              text: w.text,
              frame: voiceAt + ((w.start - source.start) * rate).round(),
              end: voiceAt + ((w.end - source.start) * rate).round(),
              from: "voice:${voice.id}"),
    ];
  }

  /// clearLipSync takes every mouth off [e]: from its track, or a 3D
  /// character's scene.
  void clearLipSync(CanvasElement e) => replaceElement(switch (e) {
        Character3dElement c => c.performing(c.performance.withMouths(const [])),
        _ => e,
      });

  /// stageFilmed is [stage] with its camera set to [camera]: its own setting
  /// until the camera has been keyed, and from then on this frame's key (the
  /// rule a character's pose follows).
  StageElement stageFilmed(StageElement stage, StageCamera camera) {
    var keyed = stage.track?.keys
            .any((k) => k.values.keys.any((c) => c.startsWith("cam."))) ??
        false;
    if (!keyed) return stage.copyWith(camera: camera);
    return stage.withBase(
            track: _pinnedAt(stage.track!, _frame, camera.channels))
        as StageElement;
  }

  /// stageOf is the stage called [id] as it is drawn on this canvas: a
  /// Background element showing one, or the background behind the canvas.
  StageElement? stageOf(String id) => stageNamed(id, _document.elements,
      backdrop: _document.drawnBackground, page: _document.size.rect);

  /// putStage writes [stage] back where it lives (see putBackdrop), its
  /// settings and its camera's keys both.
  void putStage(StageElement stage, {bool transient = false}) =>
      putBackdrop(stage, transient: transient);

  /// parallaxOf is the parallax scenery called [id] as it is drawn on this
  /// canvas, the way [stageOf] is the stage.
  ParallaxElement? parallaxOf(String id) {
    if (id == backgroundParallaxId) {
      var bg = _document.drawnBackground;
      return bg.isParallax ? bg.parallaxOn(_document.size.rect) : null;
    }
    if (_document.elementById(id) case BackgroundElement b
        when b.isParallax) {
      return b.parallaxed;
    }
    return null;
  }

  /// parallaxFilmed is [p] with its camera set to [camera], by the rule
  /// [stageFilmed] follows.
  ParallaxElement parallaxFilmed(ParallaxElement p, ParallaxCamera camera) {
    if (!_cameraKeyed(p)) return p.copyWith(camera: camera);
    return p.withBase(track: _pinnedAt(p.track!, _frame, camera.channels))
        as ParallaxElement;
  }

  /// putBackdrop writes a stage or a parallax back where it lives: the
  /// Background element that draws it, or the background behind the
  /// canvas.
  void putBackdrop(CanvasElement backdrop, {bool transient = false}) {
    var bg = _document.editedBackground;
    switch (backdrop) {
      case StageElement s when s.id == backgroundStageId:
        setBackground(bg.copyWith(backdrop: BackdropKind.stage, stage: s),
            transient: transient);
        return;
      case ParallaxElement p when p.id == backgroundParallaxId:
        setBackground(
            bg.copyWith(backdrop: BackdropKind.parallax, parallax: p),
            transient: transient);
        return;
    }
    if (_document.elementById(backdrop.id) case BackgroundElement b) {
      switch (backdrop) {
        case StageElement s:
          replaceElement(b.withStage(s), transient: transient);
          return;
        case ParallaxElement p:
          replaceElement(b.withParallax(p), transient: transient);
          return;
      }
    }
    replaceElement(backdrop, transient: transient);
  }

  /// panAcross keys [p]'s camera to travel [distance] design units across
  /// the scene, from the first frame to the last.
  void panAcross(ParallaxElement p, double distance) {
    var last = math.max(1, _document.frames - 1);
    var from = p.cameraAt(0);
    var track = _pinnedAt(p.track ?? ElementTrack.empty, 0, from.channels);
    track =
        _pinnedAt(track, last, from.copyWith(x: from.x + distance).channels);
    putBackdrop(p.withBase(track: track));
  }

  bool _cameraKeyed(CanvasElement e) =>
      e.track?.keys.any((k) => k.values.keys.any((c) => c.startsWith("cam."))) ??
      false;

  /// _cameraNow and _cameraRest are a filmed backdrop's camera on this frame
  /// and its own setting, as keyframe channels.
  Map<String, double> _cameraNow(CanvasElement e) => switch (e) {
        StageElement s => s.cameraAt(_frame).channels,
        ParallaxElement p => p.cameraAt(_frame).channels,
        _ => const {},
      };
  Map<String, double> _cameraRest(CanvasElement e) => switch (e) {
        StageElement s => s.camera.channels,
        ParallaxElement p => p.camera.channels,
        _ => const {},
      };

  /// keyCamera keys [stage]'s camera as it is on this frame, and on the
  /// first frame too the first time, so the move starts from where the
  /// camera was.
  void keyCamera(CanvasElement stage) {
    var track = stage.track ?? ElementTrack.empty;
    if (!_cameraKeyed(stage) && _frame != 0) {
      track = _pinnedAt(track, 0, _cameraRest(stage));
    }
    putBackdrop(
        stage.withBase(track: _pinnedAt(track, _frame, _cameraNow(stage))));
  }

  /// hasCameraKey is whether the camera is keyed on this frame.
  bool hasCameraKey(CanvasElement stage) =>
      stage.track
          ?.keyAt(_frame)
          ?.values
          .keys
          .any((c) => c.startsWith("cam.")) ??
      false;

  /// clearCameraKey takes the camera off this frame's keyframe.
  void clearCameraKey(CanvasElement stage) {
    var track = stage.track;
    var at = track?.keyAt(_frame);
    if (track == null || at == null) return;
    var without = at.copyWith(values: {
      for (var v in at.values.entries)
        if (!v.key.startsWith("cam.")) v.key: v.value,
    });
    putBackdrop(stage.withBase(
        track: without.isRest && without.frame != 0
            ? track.withoutFrame(_frame)
            : track.withKey(without)));
  }

  /// spotKeyed is whether where [e] stands on its stage is keyed.
  bool spotKeyed(CanvasElement e) =>
      e.track?.keys.any((k) => k.values.keys.any((c) => c.startsWith("spot."))) ??
      false;

  /// spotted is [e] standing at [spot]: its own spot until it has been
  /// keyed, and from then on this frame's key. Which stage it is on and how
  /// it stands are its own, keyed or not.
  CanvasElement spotted(CanvasElement e, StageSpot spot) {
    var own = e.base.spot;
    if (own == null || !spotKeyed(e)) return e.withBase(spot: spot);
    var kept = e.withBase(
        spot: own.copyWith(stage: spot.stage, stand: spot.stand));
    return kept.withBase(track: _pinnedAt(e.track!, _frame, spot.channels));
  }

  /// keySpot keys where [e] stands as it is on this frame, and on the first
  /// frame too the first time, so it moves from where it stood.
  void keySpot(CanvasElement e) {
    var spot = e.spotAt(_frame);
    if (spot == null) return;
    var track = e.track ?? ElementTrack.empty;
    if (!spotKeyed(e) && _frame != 0) {
      track = _pinnedAt(track, 0, e.base.spot!.channels);
    }
    replaceElement(e.withBase(track: _pinnedAt(track, _frame, spot.channels)));
  }

  /// hasSpotKey is whether where [e] stands is keyed on this frame.
  bool hasSpotKey(CanvasElement e) =>
      e.track
          ?.keyAt(_frame)
          ?.values
          .keys
          .any((c) => c.startsWith("spot.")) ??
      false;

  /// clearSpotKey takes where [e] stands off this frame's keyframe.
  void clearSpotKey(CanvasElement e) {
    var track = e.track;
    var at = track?.keyAt(_frame);
    if (track == null || at == null) return;
    var without = at.copyWith(values: {
      for (var v in at.values.entries)
        if (!v.key.startsWith("spot.")) v.key: v.value,
    });
    replaceElement(e.withBase(
        track: without.isRest && without.frame != 0
            ? track.withoutFrame(_frame)
            : track.withKey(without)));
  }

  /// removePlayerKeyframe drops one, and the track with it when it was the
  /// last, so no empty track is saved.
  void removePlayerKeyframe(String teamId, int index, int frame) {
    var team = _document.elementById(teamId);
    if (team is! TeamElement || index < 0 || index >= team.players.length) {
      return;
    }
    var spot = team.players[index];
    var track = spot.track;
    if (track == null) return;
    var next = track.withoutFrame(frame);
    replaceElement(team.withPlayer(
        index,
        next.isEmpty
            ? spot.copyWith(clearTrack: true)
            : spot.copyWith(track: next)));
  }

  // ------------------------------------------------------------------------
  // Selection
  // ------------------------------------------------------------------------

  // ---- picture layers ----------------------------------------------------

  String? _imageEditing;
  String _imageLayerId = baseLayerId;

  /// _alsoPicked are the layers picked with [imageLayer], in the order they
  /// were picked: what the align tools line up and a drag moves together.
  /// The settings are the first one's.
  final List<String> _alsoPicked = [];

  FrameTool? _frameTool = FrameTool.image;

  /// _shutCards are the settings cards under a row of kinds -- an
  /// arrival's, an exit's, a loop's -- shut by pressing the kind chosen
  /// again. For this run of the app; picking another kind opens its card.
  final Set<String> _shutCards = {};

  /// _textLayers is the layer picked in each text element's Layers, by the
  /// element's id: one of its pieces, by the piece's id. A text element not
  /// in here has its own words picked. For this run of the app.
  final Map<String, String> _textLayers = {};

  PositionTool? _positionTool = PositionTool.place;

  String? _warpLayer;

  Set<int> _warpPicks = const {};

  bool _skewHandles = false;

  bool _imageSolo = false;

  ImageTool _imageTool = ImageTool.move;

  // ---- picture masks -----------------------------------------------------

  bool _maskHide = true;

  double _maskBrushSize = 0.03;

  double _maskHardness = 0.6;

  double _maskStrength = 1;

  bool _maskRadial = false;

  MaskView _maskView = MaskView.result;

  String? _maskBusy;
  String? _maskNote;

  // ---- brushwork ----------------------------------------------------------

  Color _paintColour = const Color(0xFFF2B33D);

  double _paintSize = 0.02;

  double _paintHardness = 0.6;

  double _paintStrength = 1;

  BrushTip _paintTip = const BrushTip();

  String _paintBrush = "round";

  bool _burning = false;

  Offset? _cloneFrom;
  Offset? cloneOffset;

  bool _retouchWholeFrame = false;

  // ---- vector editing ----------------------------------------------------

  String? _vectorEditing;
  int _vectorShape = -1;
  Set<VectorPick> _vectorPicks = const {};

  bool _vectorSolo = false;

  VectorTool _vectorTool = VectorTool.select;

  VectorPick? _vectorPenFrom;

  bool _vectorCornerRound = true;

  double _vectorCornerSize = 20;

  /// _corner is the corner the corner tool last made: the drawing before
  /// it, the point it was made at, and the drawing and the two points it
  /// made. Still being made for as long as those two points are what is
  /// picked and nothing else has changed the drawing.
  ({
    VectorElement before,
    VectorPick at,
    VectorElement after,
    Set<VectorPick> picks
  })? _corner;

  VectorHandleDrag _vectorHandleDrag = VectorHandleDrag.any;

  bool _vectorHandleSnap = false;

  /// _copiedShapes is what the last copy of points copied, and _pastes how
  /// many times it has been pasted since -- each paste a step further off,
  /// so pastes do not land on top of one another.
  List<VectorShape> _copiedShapes = const [];
  int _pastes = 0;

  VectorBrush _vectorBrush = builtInBrushes.first;

  bool _vectorPencilPoints = false;

  VectorLanes _vectorLanes = VectorLanes.none;

  int _vectorShapeMade = -1;

  VectorShapeKind _vectorShapeKind = VectorShapeKind.box;

  int _vectorShapeSides = 5;

  double _vectorStarInner = 0.45;

  double _vectorShapeCorner = 0.2;

  Color? _vectorShapeFill = const Color(0xFF8AB4F8);

  Color? _vectorShapeLine = const Color(0xFF202124);

  double _vectorShapeWidth = 3;

  bool _vectorEraseWhole = false;

  double _vectorEraseSize = 20;

  double _vectorEraseSoft = 0;

  bool _vectorEraseLine = true;

  bool _vectorEraseFill = true;

  bool _vectorMirrorAcross = false;

  bool _vectorMirrorDown = false;

  bool _vectorQuickFill = false;

  VectorText _vectorTextStyle = const VectorText();
  Color _vectorTextColour = const Color(0xFF000000);

  int _vectorTyping = -1;

  ValueChanged<Color>? _onSampled;
  Color? _sampled;

  double _vectorKnifeGap = 1;

  double _vectorFillGap = 3;

  Color _vectorPencilFill = const Color(0xFF8AB4F8);

  Color _vectorPencilColour = const Color(0xFF202124);

  List<StylusAction> _stylusButtons = const [
    StylusAction.pickColour,
    StylusAction.pan,
    StylusAction.undo,
  ];

  StylusAction _stylusEraser = StylusAction.erase;

  Set<int> _vectorCombining = const {};

  PaintSpec _vectorTint = const PaintSpec(Color(0xFFE5484D));

  double _vectorBrushSize = 24;

  double _vectorBrushSoft = 0.5;

  bool _vectorTintLine = true;

  bool _vectorTintFill = true;

  SpritePaintSession? _spritePaint;

  TilePaintSession? _tilePaint;

  /// studio3dOpen is whether the Character Studio has the page, in place of
  /// the canvas (character_studio_3d.dart).
  final ValueNotifier<bool> studio3dOpen = ValueNotifier(false);

  /// scoreStudio is the score the Score Studio has the page for, by id, or
  /// null while the canvas has it (score_studio.dart).
  final ValueNotifier<String?> scoreStudio = ValueNotifier(null);

  /// _rangeEnd is the frame a sheet's range of bars stops playing at (see
  /// playSheet), or null.
  int? _rangeEnd;

  /// studio3dElement is the 3D character the Studio was opened to change,
  /// if it was opened for one.
  String? studio3dElement;

  Set<VectorItem> _vectorItems = const {};

  VectorTool _lastSelect = VectorTool.select;

  Set<String> _offCanvas = const {};

  // ---- scenes -------------------------------------------------------------

  bool _playAll = false;

  int? _previewAt;

  /// previewEnd is where the preview stops, so watching a transition does not
  /// run on through the rest of the document.
  int _previewEnd = 0;

  /// _previewFrom is the scene the preview was started on, so that watching a
  /// join leaves the editor where it was found.
  int? _previewFrom;

  /// _previewFromMaster is whether the shared canvas was the one open when
  /// the preview started, so stopping puts it back.
  bool _previewFromMaster = false;

  // ------------------------------------------------------------------------
  // Cues -- see model/canvas_cues.dart.

  /// wordQuery is what is being looked for among the words, from an
  /// element's cue card -- this sitting's, never the document's.
  String _wordQuery = "";

  /// _sceneFrames is where the playhead was on each scene when it was last
  /// left, by scene id. Not in the document: it is where somebody is, not
  /// something they made.
  final Map<String, int> _sceneFrames = {};

  /// _sceneClipboard is the scene last copied, held as an element's copy is
  /// (see [_clipboard]): static, so a scene copied from one canvas pastes into
  /// another.
  static CanvasScene? _sceneClipboard;

  /// hasCopiedScene is whether there is a scene waiting to be pasted.
  static bool get hasCopiedScene => _sceneClipboard != null;

  /// forgetCopiedScene empties it. For a test that needs to start from
  /// nothing copied, since the clipboard is deliberately static.
  @visibleForTesting
  static void forgetCopiedScene() => _sceneClipboard = null;

  bool _cameraView = false;

  // ------------------------------------------------------------------------
  // View
  // ------------------------------------------------------------------------

  set zoom(double value) {
    var next = value.clamp(minZoom, maxZoom);
    if (next == _zoom) return;
    // About the middle of what is looked at: the view scaled with the page,
    // so the point in the middle of the window stays there.
    var f = next / _zoom;
    _pan = Offset2(_pan.dx * f, _pan.dy * f);
    _zoom = next;
    // Coming back to the whole canvas re-centres it, or a pan made while
    // zoomed in would leave the fitted canvas off to one side.
    if ((_zoom - 1).abs() < 0.001) _pan = const Offset2(0, 0);
    _notifyView();
  }

  set pan(Offset2 value) {
    _pan = value;
    _notifyView();
  }

  // ------------------------------------------------------------------------
  // Playback
  // ------------------------------------------------------------------------

  set frame(int value) {
    var next = value.clamp(0, math.max(0, _document.frames - 1)).toInt();
    // A playhead put somewhere by hand is no longer showing a transition it
    // was stepped into -- see goToRunFrame.
    if (_playAll && _previewFrom == null && !playing && _previewAt != null) {
      _previewAt = null;
      notifyListeners();
    }
    if (next == _frame) return;
    _frame = next;
    _syncTimeline();
    notifyListeners();
  }

  /// _clockFrames is how many frames the playhead has been moved on since
  /// playback started. The playhead keeps time by the clock, not by counting
  /// ticks, which come late whenever the app is busy and would leave it
  /// behind the sound.
  int _clockFrames = 0;

  /// _playWatch is the time since Play, read between ticks: see
  /// betweenFrames.
  Stopwatch _playWatch = Stopwatch();

  /// _clockShift is how far, in seconds, the playhead's clock has been moved
  /// to keep with the sound -- see _followSound.
  double _clockShift = 0;

  /// _playedFrom is the scene and frame the last Play started from.
  (int, int)? _playedFrom;

  // ------------------------------------------------------------------------
  // The control bar's switches
  // ------------------------------------------------------------------------

  bool _metronome = false;

  final Map<MixerSection, BandState> _bandStates = {
    for (var s in MixerSection.values) s: BandState.shown,
  };

  /// _mainBands are the bands one of which always shows: a mixer of send
  /// dials alone, or of nothing, is only its names.
  static const _mainBands = [
    MixerSection.clips,
    MixerSection.devices,
    MixerSection.mixer,
  ];

  final Set<String> _narrowStrips = {};

  final Set<String> _flippedRows = {};
  Object? _flippedRowsAt;

  bool _returnsShown = true;

  bool _followPlayhead = true;

  bool _looping = false;

  (int, int)? _loop;

  /// clockForTest stands in for the playback clock, in microseconds since
  /// Play, and tickClockForTest is a tick of the timer against it -- so a
  /// test can make a tick late without waiting for one to be.
  @visibleForTesting
  int Function()? clockForTest;

  // ------------------------------------------------------------------------
  // Live counters
  // ------------------------------------------------------------------------

  /// _counters is what each live counter is showing, by element id. Held here
  /// rather than on the element: writing every tick into the document would
  /// make a clock an unsaved change once a second and flood the undo history.
  /// It goes when the window does.
  final Map<String, double> _counters = {};

  /// _countersRunning is which of them are counting, and _countersSince when
  /// each was last read, so a tick advances by the time actually passed.
  final Set<String> _countersRunning = {};
  final Map<String, DateTime> _countersSince = {};

  Timer? _counterTimer;

  int _counterTicks = 0;

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

  /// _held is each instrument's keys held down live, by element id.
  final Map<String, Set<int>> _held = {};

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

  /// _pressedOn is each instrument with keys held, as it was when they were
  /// pressed: let go through it whatever has changed since -- the scene
  /// turned, the element deleted -- so no note is left ringing.
  final Map<String, AudioElement> _pressedOn = {};

  static String _channelOf(AudioElement e) =>
      e.clip.channel.isEmpty ? e.id : e.clip.channel;

  final Set<String> _armed = {};

  /// _controlTake is each instrument's controllers moved while recording.
  final Map<String, Map<MidiControl, List<ControlPoint>>> _controlTake = {};

  /// _sounded is what each key held sounds as, through the channel's MIDI
  /// effects -- a chord's keys, kept to a scale -- and _soundCount how many
  /// held keys sound each, so one let go does not stop another's.
  final Map<String, Map<int, List<int>>> _sounded = {};
  final Map<String, Map<int, int>> _soundCount = {};

  /// _arps are the arpeggiators playing live, by element id.
  final Map<String, _LiveArp> _arps = {};

  bool _recording = false;

  /// _take is each instrument's notes being held while recording, as when
  /// each started and how hard; _taken the notes finished.
  final Map<String, Map<int, (double, int)>> _take = {};
  final Map<String, List<MidiNote>> _taken = {};

  // ------------------------------------------------------------------------
  // The elements' slots: their clips launched live -- see motion_player.dart
  // ------------------------------------------------------------------------

  /// motionPlayer is what the elements' slots are playing.
  final MotionPlayer motionPlayer = MotionPlayer();

  /// _motionPainted is the frame of the slots' clock last painted, playing
  /// only the slots.
  int _motionPainted = -1;

  /// _triggeredOff are the elements a trigger -- the scene starting, a
  /// click, a key -- took off their timelines while this Play ran. Stop
  /// puts them back, so the next Play starts as the canvas does; what was
  /// launched from a slot stays off until Back, as it always has.
  final Set<String> _triggeredOff = {};

  /// _slotPressed is the slot being pressed, whose sound the press sees to
  /// (see _soundsWithTheirMotion).
  (String, String)? _slotPressed;

  // ------------------------------------------------------------------------
  // The session view: clips launched live
  // ------------------------------------------------------------------------

  Quantise _launchQuantise = Quantise.bar;

  /// _clipChannels is what each channel is playing from its slots, and what
  /// it is about to.
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

  /// _sessionClock is the session's clock while the timeline plays: where
  /// the playhead was as Play was pressed, moved on a frame at every frame
  /// played -- not sent back with the playhead by a Loop or a Jump, or to
  /// nought at each scene of a run (Ken's systems review, 2026-11-08: a clip
  /// waiting for the loop's end never came, and one playing never ended).
  double _sessionClock = 0;

  /// _offTimeline are the channels that have left the timeline for their
  /// slots, as Ableton's tracks do: a clip launched there while the
  /// timeline plays silences the channel's timeline -- and it stays silent,
  /// its clip stopped or not, until Back to the timeline.
  final Set<String> _offTimeline = {};

  /// launchLevel is how loud [clip] plays launched at [velocity]: its
  /// Velocity's share of the way from full to the pad's.
  static double launchLevel(SessionClip clip, int velocity) =>
      1 - clip.velocity * (1 - velocity.clamp(0, 127) / 127);

  /// _repeats are the Repeat clips held down, by channel.
  final Map<String, _Repeat> _repeats = {};

  int? _sceneLaunched;

  /// _cueLaunchedMaster is whether the cue last launched was the master's,
  /// on a scene with cues of its own (see CanvasSession.cuesApart).
  bool _cueLaunchedMaster = false;

  final math.Random _followDice = math.Random();

  // ---- Recording into a slot

  // ---- What is in the slots

  // ------------------------------------------------------------------------
  // Played as a game
  // ------------------------------------------------------------------------

  GameRun? _game;
  CanvasDocument? _gameView;

  /// _stagePointer and the two after it: see stagePointer.
  Offset? _stagePointer;
  CanvasDocument? _facesPointerOf;
  bool _facesPointerWas = false;

  /// _gameLeft is the scene a game has just left -- as it was last seen,
  /// on its frame -- with the transition after it and when it began, on
  /// the game's clock: drawn giving way to the one arrived at. See
  /// gameChange.
  (CanvasDocument, int, SceneTransition, double, LiveMotion)? _gameLeft;
  Timer? _gameTimer;
  final Stopwatch _gameWatch = Stopwatch();

  bool _gameTabOpen = false;

  bool _gamePaused = false;

  String? _waitingFor;
  StreamSubscription<NormalizedGamepadEvent>? _waitPads;

  /// _sceneBeforeGame is the scene showing when the game was started, to go
  /// back to when it stops.
  int? _sceneBeforeGame;

  /// _mouthsOfSlots are each slot's mouths, once worked out: see
  /// _slotMouths.
  final Map<String, List<MouthKey>?> _mouthsOfSlots = {};

  /// _gameSounded are the sounds on the canvas a game has played, stopped
  /// when it ends -- one still opening its file would be heard after.
  final Set<String> _gameSounded = {};

  /// escStopsGame is whether Escape ends the game -- as it does in the
  /// editor -- or is left to whatever holds the game: a published game's
  /// player, where Escape leaves.
  bool escStopsGame = true;

  // ------------------------------------------------------------------------
  // Practising
  // ------------------------------------------------------------------------

  /// _practice is the Sheet music being practised, by id, while a take is
  /// going; the rest is how the take is going.
  String? _practice;
  final Map<int, NoteMark> _marks = {};
  final Map<int, int> _wrongKeys = {};
  final Set<int> _waiting = {};

  /// _found are the notes Wait for me has had played, this time round: it
  /// goes on past them, whatever they were marked.
  final Set<int> _found = {};

  /// _accompanying is the keys the hand not practised has sounding.
  final Set<int> _accompanying = {};

  /// _mine is whether note [i] is the player's to play: of the hand being
  /// practised -- the right hand from middle C up -- and not in Listen.
  static bool _mine(SheetElement sheet, MidiNote n) =>
      sheet.mode != PracticeMode.listen &&
      switch (sheet.hands) {
        PracticeHands.right => n.key >= splitKey,
        PracticeHands.left => n.key < splitKey,
        PracticeHands.both => true,
      };

  /// partRenderer plays a part into the bytes of a WAV, and partStore keeps
  /// them, returning the stored file's id -- see part_render.dart. Both
  /// stand-ins for tests.
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
  final Set<String> _rendering = {};
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

  /// _speakingNow is the lines each channel's engine is speaking now: the
  /// first waiting, or every one, where it speaks them together.
  final Map<String, Set<String>> _speakingNow = {};

  /// _speechStops is Stop, for each channel speaking now.
  final Map<String, SpeechStop> _speechStops = {};

  /// _speechInto is the slot each waiting line is to be spoken into, by
  /// channel and line -- a slot being replaced -- where it is not the
  /// line's first free one.
  final Map<String, Map<String, int>> _speechInto = {};

  final _seeds = math.Random();

  static String _firstWords(String text) {
    var words = text.split(RegExp(r"\s+"));
    return words.length <= 6 ? text : "${words.take(6).join(" ")}…";
  }

  /// speechLibrary lists a spoken take in the Audio library as [name], and
  /// speechUnlist takes one off the list, its file kept: stand-ins for
  /// tests.
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

  /// keepRecording keeps a recording made from another -- [wav]'s bytes --
  /// as a take is kept (see speechTakeStore), answering its id: a voice's
  /// notes moved in the Pitch editor.
  static Future<String?> keepRecording(Uint8List wav) => speechTakeStore(wav);

  /// speechTakeStore keeps a line's take -- [wav]'s bytes -- apart from the
  /// library, with the canvases that have it, answering its id: in the
  /// Audio library only once it is saved or put on the timeline, and
  /// deleted by a tidy once no canvas has it. A stand-in for tests.
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

  // Not transient by default: a take put in a slot with no gesture open
  // would otherwise be removed by the next Undo of anything.

  // ---- Phrasing: a take's words shaped after it is spoken

  ({String channel, int line, int slot})? _phrasing;

  /// phrasingPicked are the words picked, by their place in the take as
  /// spoken: what a drag or a setting changes. The first is the one its
  /// settings show.
  Set<int> phrasingPicked = const {0};

  final Map<String, TakeReading> _readings = {};

  /// _readingTakes are the takes being read now, and _unreadTakes those
  /// whose sound could not be read: said so, rather than "Reading…" for
  /// ever (Ken's Phrasing that did nothing).
  final Set<String> _readingTakes = {}, _unreadTakes = {};

  Timer? _shapeTimer;

  final Map<String, Future<SpeechTake?>> _shaping = {};

  /// speechSplitAt is where section [text] is split: at the sentence's
  /// end nearest its middle -- or, one sentence, the comma -- or null for
  /// none.
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

  /// _joinAway joins [sounds] -- the takes [takes] chosen, a pause between
  /// each two -- gives them the finish, and makes the WAV, in an isolate of
  /// its own.
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

  String? _speechHeard;
  String? speechPreviewing;
  AudioTrack? _heardTrack;
  AudioVoice? _heardVoice;
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

  /// _previews are the voices previewed, by everything that changes how they
  /// sound, each its file: heard again at once.
  final Map<String, String> _previews = {};
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

  static bool _sameChannelKey((CanvasDocument, int, bool, int?, List<String>) a,
          (CanvasDocument, int, bool, int?, List<String>) b) =>
      identical(a.$1, b.$1) &&
      a.$2 == b.$2 &&
      a.$3 == b.$3 &&
      a.$4 == b.$4 &&
      identical(a.$5, b.$5);

  /// _channelOrder is the order channels have been dragged into, by key.
  /// Where somebody is working, not what they made, so it is not saved.
  List<String> _channelOrder = const [];

  // ------------------------------------------------------------------------
  // Replacing a colour everywhere -- see canvas_palette.dart.

  // ------------------------------------------------------------------------
  // Reuse: text styles, linked copies, staggered arrivals.

  // ------------------------------------------------------------------------
  // Sound tools -- see audio_tools.dart.

  Set<String> _selectedChannels = {};

  bool _snapping = false;

  TimelineTool _timelineTool = TimelineTool.select;

  /// laneHeights is how tall each channel has been dragged, by channel. The
  /// reader's, not the document's: kept for each canvas by the screen -- see
  /// canvasView.
  final Map<String, double> laneHeights = {};

  bool _mixerOpen = false;

  bool _mixerSmallest = false;

  bool _mixerMinimised = false;

  // ---- Kept between visits

  /// timelineView is the stretch the timeline is zoomed to -- null for all
  /// of it -- as the timeline last drew it; timelineViewSet counts the
  /// times it was put back from outside, for the timeline to take up.
  TimelineView? timelineView;
  int timelineViewSet = 0;

  bool _effectsOpen = false;

  /// _speechShown is whether the Chain's sound shows the channel's Speech:
  /// its script, takes and voice, and Sing. Speech makes clips; it is not a
  /// step of the chain, so it shows only when asked for (see showSpeech).
  bool _speechShown = false;

  /// _pitchShown is whether the Chain shows its channel's Pitch editor.
  bool _pitchShown = false;

  /// _instrumentShown is whether the Chain shows its channel's Instrument
  /// editor.
  bool _instrumentShown = false;

  /// _chainFull is whether the Chain fills the window: the canvas put away
  /// for it, as the prototype's full-screen button does.
  bool _chainFull = false;

  /// chainFull: see _chainFull. The screen puts the canvas away while it is
  /// set, and the dock then fills the room.
  bool get chainFull => _chainFull;

  set chainFull(bool full) {
    if (full == _chainFull) return;
    _chainFull = full;
    notifyListeners();
  }

  /// _keysShown is whether the Chain's Keys strip is open over its cards
  /// (Ken, 2026-11-12): kept for the session, as a card's fold is.
  static bool _keysShown = false;

  bool get keysShown => _keysShown;

  /// keysHeight is how tall the Keys strip was dragged, or null for as
  /// tall as it opens: kept for the session.
  static double? _keysHeight;

  double? get keysHeight => _keysHeight;

  set keysHeight(double? height) {
    if (height == _keysHeight) return;
    _keysHeight = height;
    notifyListeners();
  }

  set keysShown(bool shown) {
    if (shown == _keysShown) return;
    _keysShown = shown;
    notifyListeners();
  }

  /// _chainPhase is the Chain's filter: only what plays in one phase -- its
  /// cards and its keys -- or null for all of it.
  MotionPhase? _chainPhase;

  MotionPhase? get chainPhase => _chainPhase;

  set chainPhase(MotionPhase? phase) {
    if (phase == _chainPhase) return;
    _chainPhase = phase;
    notifyListeners();
  }

  /// _hear is which of a surround mix's speakers the editor plays: see
  /// hearSpeakers.
  SpeakerGroup _hear = SpeakerGroup.all;

  /// _motionPreview is the element whose motion chain the stage shows as it
  /// stands at one join, and that join: see previewMotionFrom.
  (String, int)? _motionPreview;

  /// _soundFrom is where a game last set a channel's sound off -- the
  /// instance of an element reused it touched -- by channel: see gameSound.
  final Map<String, Heard> _soundFrom = {};

  /// _previewTicks counts the previews changed, for the stage to repaint.
  int _previewTicks = 0;

  String? _effectsFocus;
  int _effectsFocusCount = 0;

  // ---- The clip editor

  bool _editorWide = true;

  /// _settingsShut is, by editor -- "roll" a part's piano roll, "clip" a
  /// slot's clip -- whether its columns of settings are folded away to a
  /// strip. The roll's start folded, as Ken asked: the notes first.
  final Map<String, bool> _settingsShut = {"roll": true};

  /// _analysing are the devices, as "strip|device", whose displays show
  /// the real sound: off until switched on (Ken, 2026-11-08), as keeping
  /// and drawing it costs.
  final Set<String> _analysing = {};

  /// _learning is the setting waiting for a controller's knob, and
  /// _controlIdle ends a run of turning one as an undo step.
  (String, String)? _learning;
  Timer? _controlIdle;

  /// _listening is the chain heard from a point: see listenAt.
  (String, int)? _listening;

  /// _abOther are each compared device's other settings, by "strip|device",
  /// and _abB those heard with their B: see toggleAB.
  final Map<String, Map<String, double>> _abOther = {};
  final Set<String> _abB = {};

  /// _abSets are the other sets of the cards whose settings are not one
  /// device's knobs -- an EQ's bands, a compressor's, a limiter's: see
  /// toggleABOf.
  final Map<String, Object> _abSets = {};

  /// _motionCurves is whether the Motion view shows its Curves.
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

  /// _presetNames are the presets last put on devices, by "strip|device".
  final Map<String, String> _presetNames = {};

  double? _editorWidth;

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

  /// keysHeld ticks when a key is pressed or let go live: what the stage
  /// draws held keys by. A key played is heard at once -- the sound sent
  /// before anything else -- and only the stage is redrawn for it, not the
  /// whole editor (Ken: 200ms between a key and its note).
  final ValueNotifier<int> keysHeld = ValueNotifier(0);

  /// playheadMoved goes up each time the playhead moves on as it plays: what
  /// draws the playhead alone listens to it (the piano roll's line), rather
  /// than being built again with everything else.
  final ValueNotifier<int> playheadMoved = ValueNotifier(0);

  /// _freezing are the channels being frozen now: see freezeChain.
  final Set<String> _freezing = {};
  double _rollStepGrid = 0.25;
  double? _stepAt;
  final Set<int> _stepHeld = {};

  (String, int)? _selectedSlot;

  int _noteToolPresses = 1;

  /// clipAudio is the whole of a stored sound, both sides at the mix's
  /// rate, for Reverse and Crop to make a new file from -- or null. A
  /// stand-in for tests.
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

  bool _cuesShown = true;

  /// foldedDevices is which of the mixer's devices are folded down to their
  /// switch and a meter, by the device's id ("eq", "comp", "meter" ...).
  /// The reader's, for this session, and the same on every strip.
  final Set<String> foldedDevices = {};

  // M, as the approved design opens (Ken, 2026-11-08): S is the overview,
  // an element's motion alone.
  int _laneSize = 1;

  double _headerWidth = 240;

  bool _allFolded = false;

  /// _keyClipboard is the keyframes copied in the Chain's Keyframes card,
  /// each relative to the first: see copyTargetKeys.
  List<(int, Keyframe)> _keyClipboard = const [];

  BandState _motionSlots = BandState.shown;
  bool _mixerRailFolded = false;
  double _cueColumnWidth = 96;
  double _slotsCueWidth = 120;

  /// The master's cue columns, on a scene with cues of its own: each its
  /// own width (Ken, 2026-11-10: resized, both cue columns went together).
  double _masterCueColumnWidth = 96;
  double _slotsMasterCueWidth = 120;
  int _slotsPanelSize = 1;
  bool _slotsPanelNarrow = false;

  /// cueColumnLeast and cueColumnMost are how narrow and wide the mixer's
  /// cue column goes.
  static const double cueColumnLeast = 40;
  static const double cueColumnMost = 240;

  /// allFolded is whether the All group -- the master canvas's rows, there
  /// in every scene -- is folded away under its heading, on the timeline as
  /// in the mixer (Ken, 2026-11-08). The reader's, for this session.
  bool get allFolded => _allFolded;
  set allFolded(bool folded) {
    if (folded == _allFolded) return;
    _allFolded = folded;
    notifyListeners();
  }

  /// _waveforms is each stored sound's shape, read once and kept -- see
  /// waveformOf.
  static final Map<String, Float32List?> _waveforms = {};
  static final Set<String> _readingWaveform = {};

  /// seedWaveform gives [assetId] a shape without reading it, for tests.
  @visibleForTesting
  static void seedWaveform(String assetId, Float32List peaks) =>
      _waveforms[assetId] = peaks;

  bool _disposedForWaveform = false;

  CanvasDocument? _duckFor;
  int _duckWaves = -1;
  Map<String, List<GainPoint>> _ducks = const {};

  // ------------------------------------------------------------------------
  // The mixer
  // ------------------------------------------------------------------------

  final Set<String> _solo = {};

  // ---- Automation: see automation.dart

  final Map<String, Set<String>> _overridden = {};

  bool _automationArmed = false;

  final Set<String> _automationShown = {};

  final Map<String, List<String>> _automationRows = {};

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

  /// elementAnimationOf is [element]'s own arrival, for the kinds that have
  /// one, or an empty animation for the kinds that do not. A switch rather
  /// than a getter on CanvasElement, which would promise every element can be
  /// animated this way.
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
      // A counter arrives and leaves like any box, whatever its number is
      // doing meanwhile.
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

  final Set<String> _anchorsShown = {};

  ({String id, int frame})? _previewing;
  int _previewingEnd = 0;

  // ------------------------------------------------------------------------
  // Loading and saving
  // ------------------------------------------------------------------------

  /// load replaces the whole session with a document from disk.
  void load(CanvasDocument document, {String? folder, String? name}) {
    pause();
    stopAudio();
    // Sounds with nothing in them, on the canvas as elements, are dropped:
    // older versions left them for empty channels. An empty channel made on
    // purpose from the mixer (named, with effects, a Speech device or clips
    // in its slots) stays, since its slots and mix would go with it.
    for (var e in document.elements) {
      if (e is AudioElement &&
          e.clip.timed &&
          e.clip.isEmpty &&
          e.instrument == null &&
          e.clip.channelName.isEmpty &&
          e.clip.mix.isDefault &&
          !document.session.slots
              .containsKey(e.clip.channel.isNotEmpty ? e.clip.channel : e.id)) {
        document = document.removeElement(e.id);
      }
      // A drawing saved while it was being edited, before saving fitted its
      // box: fitted now, so it opens drawn round all of it.
      if (e is VectorElement && e.edited) {
        var fitted = boxedToDrawing(e);
        if (!identical(fitted, e)) document = document.withElement(fitted);
      }
    }
    _document = document;
    this.folder = folder;
    this.name = name;
    _offTimeline.clear();
    motionPlayer.clear();
    _selectedSlot = null;
    _selection = {};
    _backgroundSelected = false;
    _focusedPlayer = null;
    // Opened on the frame everything has arrived by rather than on nought,
    // so a canvas whose elements arrive does not open as an empty page.
    _beforePreview = null;
    _undo.clear();
    _redo.clear();
    _interaction = null;
    _savedEdits = _edits;
    // The zoom and the pan go: both are a position inside the document being
    // replaced. The fit stays, since it is about the reader's screen.
    _zoom = 1;
    _pan = const Offset2(0, 0);
    // A piece of sound opens on what it is made with.
    if (document.kind.isAudio) _openSoundDesk();
    // An element's keyframes stay its own, as they were saved: the Keyframes
    // card edits them. They were once made into clips as a canvas opened,
    // which took the card's keys away from it on every opening (Ken,
    // 2026-11-11).
    _frame = settledFrameOf(_document);
    notifyListeners();
  }

  /// _openSoundDesk opens the mixer and the effects: what an audio document
  /// is worked on with, there being no canvas to look at.
  void _openSoundDesk() {
    _mixerOpen = true;
    _effectsOpen = true;
    // One detail panel: the Chain on its sound.
    _animationOpen = false;
    _chainMotion = false;
  }

  /// _autosave is the pending write, if any.
  Timer? _autosave;

  /// _autosaveDelay is how long the editing has to stop for: long enough
  /// that a drag is one write, short enough to lose nothing.
  static const Duration _autosaveDelay = Duration(seconds: 3);

  /// scheduleAutosave writes the document out shortly, once the editing
  /// stops. Only for a document saved at least once: until then there is
  /// nowhere to write, and inventing a file would fill the library with
  /// documents nobody asked to keep. Debounced, so a burst of edits costs one
  /// write.
  void scheduleAutosave() {
    if (name == null || !_dirty) return;
    _autosave?.cancel();
    _autosave = Timer(_autosaveDelay, () {
      _autosave = null;
      if (name != null && _dirty) save();
    });
  }

  /// _toSave is the document as it is written out: a drawing still being
  /// edited is written with its box fitted round it, as leaving the editing
  /// would fit it (not done live, as that would move the pencil's mirror
  /// lines). See _fitEditedVector.
  CanvasDocument get _toSave {
    // Never a look that is only being tried. See tryElement.
    var document = _beforePreview ?? _document;
    var e = editingVector;
    if (e == null) return document;
    var fitted = boxedToDrawing(e);
    return identical(fitted, e) ? document : document.withElement(fitted);
  }

  /// save writes back to where this document came from, or nowhere when it has
  /// never been saved.
  Future<bool> save() async {
    _autosave?.cancel();
    _autosave = null;
    var f = folder, n = name;
    if (n == null) return false;
    var at = _edits;
    var ok = await CanvasStorage.save(f ?? "", n, _toSave);
    // Tidying the stores is bookkeeping a save need not wait for, and need
    // not do every time: see CanvasLibrary.tidySoon.
    if (ok) {
      CanvasLibrary.tidySoon(
          open: {..._document.assetIds, ..._document.mediaIds});
    }
    if (ok) {
      _savedEdits = at;
      notifyListeners();
    }
    return ok;
  }

  /// saveAs writes to a new place and makes it this document's home.
  Future<bool> saveAs(String folder, String name) async {
    var at = _edits;
    var ok =
        await CanvasStorage.save(folder, name, _toSave.copyWith(title: name));
    if (!ok) return false;
    this.folder = folder;
    this.name = name;
    _document = _document.copyWith(title: name);
    _savedEdits = at;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _endWait();
    slotsScroll.dispose();
    _heardWatch?.cancel();
    _previewDir?.delete(recursive: true).catchError((_) => _previewDir!);
    _disposed = true;
    _partTimer?.cancel();
    _synthTarget?.cancel();
    _synthTick?.cancel();
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
      HardwareKeyboard.instance.removeHandler(_gameKey);
      _gameTimer?.cancel();
      _game?.dispose();
      _game = null;
    }
    if (sheetMarksOf == _sheetMarks) sheetMarksOf = null;
    if (vectorSoloOf == _soloOf) vectorSoloOf = null;
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

/// Offset2 is a pair of doubles, used for the view's pan and converted to
/// an Offset where the stage needs one.
class Offset2 {
  final double dx;
  final double dy;
  const Offset2(this.dx, this.dy);

  Offset2 operator +(Offset2 other) => Offset2(dx + other.dx, dy + other.dy);

  @override
  bool operator ==(Object other) =>
      other is Offset2 && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(dx, dy);
}

/// TimedLane is one clip on the Channels strip.
class TimedLane {
  final CanvasElement element;

  /// offset is how many frames the clip's timeline is ahead of the scene's:
  /// nought for a clip on this scene, the scene's start in the run for one
  /// that follows the run.
  final int offset;

  /// editable is whether it can be changed from here: a transition's sound
  /// is changed on its transition. The master's can be, from any scene, and
  /// are written back to it.
  final bool editable;

  /// scene is which canvas the clip is on: -1 for the master, and otherwise
  /// the scene's place in the list.
  final int scene;

  const TimedLane(this.element,
      {this.offset = 0, this.editable = true, this.scene = -1});

  /// sceneLabel is the scene, as the channel strip names it: M for the
  /// master, S1 for the first scene.
  String get sceneLabel => scene < 0 ? "M" : "S${scene + 1}";

  MediaClip get clip => switch (element) {
        VideoElement v => v.clip,
        AudioElement a => a.clip,
        _ => const MediaClip(),
      };

  /// channelKey is the channel this is on: its own, for a clip with none.
  String get channelKey => clip.channel.isNotEmpty ? clip.channel : element.id;

  /// interactive is whether this is a sound on the canvas that plays when
  /// it is pressed, rather than at a time on the timeline: on a channel all
  /// the same, so it has a strip and effects like every other sound, but
  /// with nothing on its lane to move or cut. See interactiveLanes.
  bool get interactive =>
      (element is AudioElement || element is VideoElement) && !clip.timed;
}

/// TimelineShow is what the timeline and the mixer show: see
/// CanvasController.timelineShow.
enum TimelineShow {
  everything("Everything"),
  animation("Animation only"),
  sound("Sound only");

  final String label;
  const TimelineShow(this.label);
}

/// TimelineChannel is one channel of the timeline and the sounds on it.
class TimelineChannel {
  final String key;
  final List<TimedLane> lanes;
  const TimelineChannel(this.key, this.lanes);

  TimedLane get first => lanes.first;

  String get name {
    var named = first.clip.channelName;
    return named.isNotEmpty ? named : first.element.name;
  }

  /// mix is the channel's strip, which every sound on it carries.
  ChannelMix get mix => first.clip.mix;

  bool get editable => lanes.any((l) => l.editable);
  bool get video => first.element is VideoElement;

  /// interactive is a channel of sounds played by pressing them on the
  /// canvas -- see TimedLane.interactive.
  bool get interactive => lanes.every((l) => l.interactive);

  /// sceneLabel is which canvas the channel's clips are on -- see
  /// TimedLane.sceneLabel.
  String get sceneLabel => first.sceneLabel;

  /// locked is whether every sound on it is locked -- see lockChannel.
  bool get locked => lanes.every((l) => l.element.locked);
}

/// BandState is how one of the mixer's bands is shown.
enum BandState { shown, minimised, hidden }

/// MixerSection is one of the mixer's bands, in the rail's order: the
/// sends, last, are drawn between the devices and the mixer, as Ableton's.
enum MixerSection {
  clips("C", "Clips"),
  devices("D", "Devices"),
  mixer("M", "Mixer"),

  /// sends are the send dials, a band of their own -- shown or hidden,
  /// never minimised: there is nothing smaller to show of a dial.
  sends("S", "Sends");

  final String letter;
  final String label;
  const MixerSection(this.letter, this.label);
}

/// TimelineTool is what a press on a sound does. See timelineTool.
enum TimelineTool { select, knife }

/// timelineHeaderMin and timelineHeaderMax bound the channel strips' column:
/// from the icon alone to everything on it.
const double timelineHeaderMin = 28;
const double timelineHeaderMax = 360;

/// waveformPoints is how finely a sound's shape is read: enough for a lane
/// several screens wide, few enough to draw every frame.
const int waveformPoints = 2400;

/// ClipState is how a clip slot is doing, for the mixer to draw.
enum ClipState {
  empty,
  stopped,
  queued,
  playing,
  stopping,
  recordQueued,
  recording
}

/// _ClipPlay is a clip playing from a slot, or about to: from [from],
/// session seconds, round every [length] -- or once.
class _ClipPlay {
  final String clipId;
  final int row;

  /// from is when it is heard, session seconds.
  final double from;

  /// length is its loop's length; not looping, how long it plays.
  final double length;
  final bool loops;

  /// startAt and loopAt are where it starts, and where its loop starts, in
  /// seconds into what it plays.
  final double startAt, loopAt;

  /// origin is when it would have started from its start: [from], or
  /// earlier where it took over another's place -- legato.
  double origin;

  /// followed is whether its follow action has been done, and followFrom
  /// when its wait for it began: [from], or the clip's it carries on --
  /// played again as it was changed.
  bool followed = false;
  late double followFrom = from;

  /// sound is what it plays: its own sound, or that warped.
  MediaSource? sound;
  AudioVoice? voice;
  double? stopAt;

  /// level is how loud it was launched, nought to one: see launchLevel.
  double level = 1;
  _ClipPlay(this.clipId, this.row, this.from, this.length, this.loops,
      {this.startAt = 0, this.loopAt = 0})
      : origin = from;

  /// into is where it is [t] seconds after its origin, in seconds into what
  /// it plays: on from its start, then round its loop.
  double into(double t) {
    if (!loops) return startAt + t;
    var run = loopAt + length - startAt;
    if (t < run) return startAt + t;
    return loopAt + (t - run) % length;
  }
}

// ---- Work for another isolate
//
// Each started from a top-level function: a closure made inside a
// controller method can capture the controller and its timers, which cannot
// be sent to an isolate.

/// _wavAway is [l] and [r] as a WAV file's bytes, made in another isolate.
Future<Uint8List> _wavAway(Float32List l, Float32List r) =>
    Isolate.run(() => wav16(l, r));

/// _reversedWavAway is [l] and [r] turned round, as a WAV file's bytes.
Future<Uint8List> _reversedWavAway(Float32List l, Float32List r) =>
    Isolate.run(() {
      var n = l.length;
      var rl = Float32List(n), rr = Float32List(n);
      for (var i = 0; i < n; i++) {
        rl[i] = l[n - 1 - i];
        rr[i] = r[n - 1 - i];
      }
      return wav16(rl, rr);
    });

/// _warpedWavAway is a clip's sound warped -- see renderWarp -- as a WAV
/// file's bytes, and how many frames long it is.
Future<(Uint8List, int)> _warpedWavAway(
        Float32List l,
        Float32List r,
        double from,
        double to,
        bool warp,
        WarpMode mode,
        WarpMap map,
        double secondsPerBeat,
        double semitones,
        Map<ClipEnvelope, List<ControlPoint>> envelopes,
        ({
          List<(double, double)> ins,
          List<(double, double)> outs,
          FadeCurve curve
        })? fades) =>
    Isolate.run(() {
      var (wl, wr) = renderWarp(l, r,
          from: from,
          to: to,
          warp: warp,
          mode: mode,
          map: map,
          secondsPerBeat: secondsPerBeat,
          semitones: semitones,
          envelopes: envelopes);
      if (fades != null) {
        fadeEdges(wl, wr,
            ins: fades.ins, outs: fades.outs, curve: fades.curve.level);
      }
      return (wav16(wl, wr), wl.length);
    });

/// _sungAway is [singTake], in another isolate.
Future<Float32List> _sungAway(
        Float32List source, List<SungNote> sung, SingSettings settings) =>
    Isolate.run(() => singTake(source, sung, settings: settings));

/// _tempoAway is [estimateTempo], in another isolate.
Future<double> _tempoAway(
        Float32List l, Float32List r, double near, int beatsPerBar) =>
    Isolate.run(
        () => estimateTempo(l, r, near: near, beatsPerBar: beatsPerBar));

/// clipPieces are what [clip] plays over [seconds] from its start, at
/// [secondsPerBeat] and [secondsPerBar]: each a stretch of it -- from and
/// to, in seconds into what it plays -- and when, from its start, it is
/// heard. From its start on to its loop's end, then round its loop.
List<(double, double, double)> clipPieces(SessionClip clip, double seconds,
    double secondsPerBeat, double secondsPerBar) {
  var length = math.max(0.05, clip.bars * secondsPerBar);
  var loopAt = clip.loopStart * secondsPerBeat, loopEnd = loopAt + length;
  var start = clip.start * secondsPerBeat;
  if (start >= loopEnd) start = loopAt;
  var out = <(double, double, double)>[];
  var heard = 0.0;
  var from = start;
  while (heard < seconds - 0.001) {
    var to = math.min(loopEnd, from + seconds - heard);
    out.add((from, to, heard));
    heard += to - from;
    if (!clip.loop) break;
    from = loopAt;
  }
  return out;
}

/// _ClipChannel is a channel's slots at play: what it plays now, what it is
/// to play next, and when it stops.
class _ClipChannel {
  final String channel;
  _ClipPlay? now, next;
  double? stopAt;
  _ClipChannel(this.channel);
}

/// _ClipRecord is a slot being recorded into: from [from], session seconds,
/// until [until] once it is set; its notes in beats from [from].
class _ClipRecord {
  final String channel;
  final int row;
  final double from;
  double? until;
  bool started = false;
  final Map<int, (double, int)> held = {};
  final List<MidiNote> notes = [];
  _ClipRecord(this.channel, this.row, this.from);
}

/// _Repeat is a Repeat clip held down: its row, when it is launched again,
/// how often, and how loud.
class _Repeat {
  final int row;
  double nextAt;
  final double step;
  final double level;
  _Repeat(this.row, this.nextAt, this.step, this.level);
}

/// _ClipPlayed is a clip played from a slot while Record was on, from and
/// to session seconds.
class _ClipPlayed {
  final String channel;
  final SessionClip clip;
  final double from, to;
  _ClipPlayed(this.channel, this.clip, this.from, this.to);
}

/// _LiveArp is an arpeggiator playing live: the keys held -- each as the
/// keys it sounds through the effects before the arpeggiator -- and the one
/// sounding.
class _LiveArp {
  final Arpeggio player;
  final Map<int, List<int>> pressed = {};

  /// velocities are each key's notes' loudest, through the channel's
  /// Velocity effect: a step is played as loud as the loudest held, as the
  /// rendered arpeggiator plays it.
  final Map<int, int> velocities = {};
  int? sounding;

  /// played is the steps sounded so far: a step's gate lets go of that step
  /// alone, not the same key struck again on the next.
  int played = 0;

  Timer? timer;
  _LiveArp(this.player);

  int get velocity => velocities.values.fold(1, math.max);
}

/// PianoRollTarget is what the piano roll edits: MIDI channel [channel]'s
/// clip in slot [row], or with no row its part.
class PianoRollTarget {
  final String channel;
  final int? row;
  const PianoRollTarget(this.channel, this.row);
}

/// RollContent is what the piano roll shows, in beats -- see
/// CanvasController.rollContent.
class RollContent {
  final List<MidiNote> notes;
  final Map<MidiControl, List<ControlPoint>> controls;
  final double beats;
  final String name;
  final bool clip;
  const RollContent(this.notes, this.controls, this.beats,
      {required this.name, required this.clip});
}
