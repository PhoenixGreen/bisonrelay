import 'package:bruig/plugin_system/canvas/model/pattern_counts.dart';
import 'package:bruig/plugin_system/canvas/model/code_starters.dart';
import 'package:bruig/plugin_system/canvas/model/code_timing.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart'
    show CodeShow, codeShowOf, codeLineHeight, codeScrollRoom, codeShownScroll;
import 'package:bruig/plugin_system/canvas/render/code_run_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_task_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_task_element.dart';
import 'package:bruig/plugin_system/canvas/media/code_dart_runner.dart';
import 'package:bruig/plugin_system/canvas/model/code_runners.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/render/metronome_painter.dart'
    show MetronomeShow, metronomeShowOf;
import 'package:bruig/plugin_system/canvas/model/fretting.dart'
    show FretPlace, placesAt;
import 'package:bruig/plugin_system/canvas/media/synth/patch_voice.dart'
    show PatchWatch;
import 'package:bruig/plugin_system/canvas/render/synth_module_painter.dart'
    show SynthShow, synthShowOf, synthPanelFor, synthPanelFit, synthPanelOf;
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
import 'package:bruig/plugin_system/canvas/ui/sound/element_sound.dart'
    show ownChannelOf, soundOwnerOf;
import 'package:bruig/plugin_system/canvas/ui/timeline/row_header.dart'
    show givenRowColour;
import 'package:bruig/plugin_system/canvas/ui/timeline/timeline_view.dart';
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
import 'package:bruig/plugin_system/canvas/model/chart_play.dart';
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
import 'package:bruig/plugin_system/canvas/ui/drawing/sprite_painting.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/tile_painting.dart';
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
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/image_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/image_masking.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/asset_elements.dart'
    show channelClip;
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_items.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_shapes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/sheet_reshape.dart';
import 'package:bruig/plugin_system/canvas/model/data_styles.dart';
import 'package:bruig/plugin_system/canvas/model/page_style.dart';
import 'package:bruig/plugin_system/canvas/model/sheet_files.dart';
import 'package:bruig/plugin_system/canvas/model/score_channels.dart';
import 'package:bruig/plugin_system/canvas/model/score_roll.dart';
import 'package:bruig/plugin_system/canvas/render/score_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:bruig/plugin_system/canvas/model/modulation.dart'
    show macroValue;
import 'package:bruig/plugin_system/canvas/ui/game/canvas_game.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart' show
        ControlAction,
        GameSoundElement,
        GameSoundSlot,
        GameSoundStop,
        gameSoundOf,
        gameSoundStop;
import 'package:gamepads/gamepads.dart' show Gamepads, NormalizedGamepadEvent;
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart'
    show newElement, newInstrument, synthRack, synthModule, codeFontFor;
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
import 'package:bruig/plugin_system/canvas/ui/motion/motion_player.dart';
import 'package:bruig/plugin_system/canvas/model/own_motion.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/motion_editing.dart'
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
        designedNow,
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

// The controller's methods live, by area, as extensions in parts of this
// library; its state stays in the class, where every part can reach it.
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

/// minZoom and maxZoom bound the view, as multiples of the fitted size (see
/// [CanvasController.zoom]): 1 is the whole canvas filling the area.
const double minZoom = 0.25;
const double maxZoom = 16;

/// RetouchBrush is what the brush does to a picture's background.
enum RetouchBrush {
  off("Off"),

  /// erase takes the picture away, for a patch the automatic pass missed.
  erase("Rub out"),

  /// cutAround draws a boundary: all outside it goes. See RemovalStroke.fill.
  cutAround("Cut around"),

  /// restore puts it back, for a hand or a shoulder the automatic pass ate.
  restore("Put back"),

  /// markBackground and markSubject leave the picture as it is: they are
  /// hints for RemovalMode.learn (see BackgroundRemoval.hints).
  markBackground("Mark background"),
  markSubject("Mark subject");

  final String label;
  const RetouchBrush(this.label);

  bool get on => this != RetouchBrush.off;

  /// teaches is whether the brush leaves a hint rather than rubbing out.
  bool get teaches =>
      this == RetouchBrush.markBackground || this == RetouchBrush.markSubject;

  /// keeps is whether the mark is about the subject, not the background.
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

/// StageTool is what the gizmo does to an element on a 3D stage: the bar's
/// 3D tools (keys G, R and S), in place of Select and Pan on a stage.
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
  /// whole shows all of the canvas at once; nothing scrolls.
  whole("Show the whole canvas"),

  /// width fills the area's width, scrolling if the canvas is taller.
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
    // Follow sound reads the recordings this canvas reads.
    motionSoundPeaks = (id) => waveformOf(id);
    // An instrument of slices plays a stored sound.
    sliceAudioReader = (id) => CanvasController.clipAudio(id);
    // A sheet's playbar shows pause while this canvas plays.
    sheetPlaying = () => playing;
    // The synth modules on the stage: their keys held, their time.
    synthShowOf = synthShowFor;
    // A task card's pattern counted off the UI isolate: drawn again.
    PatternCounts.counted.addListener(_patternCounted);
    metronomeShowOf = metronomeShowFor;
    codeShowOf = codeShowFor;
    codeRunShowOf = codeRunShowFor;
    codeTaskShowOf = codeTaskShowFor;
  }

  CanvasDocument _document;
  CanvasDocument get document => _document;

  /// lastFetched is what each element's last refresh returned, by element id.
  /// Held here because two panel sections run a refresh; not a global, which
  /// would outlive its canvas and mix up ids. Not saved: it is about this
  /// sitting.
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

  Offset2 _pan = const Offset2(0, 0);
  Offset2 get pan => _pan;

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
  /// called from initState, and notifying during a build throws.
  void restoreFit(CanvasFit value) {
    _fit = value;
    _zoom = 1;
    _pan = const Offset2(0, 0);
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

  /// fit is how large the frame is drawn. See [CanvasFit].
  CanvasFit get fit => _fit;

  set fit(CanvasFit value) {
    if (_fit == value) return;
    _fit = value;
    // A zoom chosen against the old frame means something else in the new.
    _zoom = 1;
    _pan = const Offset2(0, 0);
    _notifyView();
  }

  bool _autoKeyframe = false;

  /// autoKeyframe makes dragging anything on frame N write a keyframe at N
  /// instead of moving it. Off by default, so tidying is not recorded.
  bool get autoKeyframe => _autoKeyframe;

  set autoKeyframe(bool value) {
    if (_autoKeyframe == value) return;
    _autoKeyframe = value;
    notifyListeners();
  }

  bool _showOverspill = false;

  /// showOverspill draws a margin of the world outside the canvas, so an
  /// element entering from off the page can be seen and dragged there.
  bool get showOverspill => _showOverspill;

  set showOverspill(bool value) {
    if (_showOverspill == value) return;
    _showOverspill = value;
    notifyListeners();
  }

  bool _showHelpers = true;

  /// showHelpers draws the selection box, resize handles and rotation ring.
  /// Off, the handles stop answering too, so nothing unseen can be grabbed.
  bool get showHelpers => _showHelpers;

  set showHelpers(bool value) {
    if (_showHelpers == value) return;
    _showHelpers = value;
    _notifyView();
  }

  bool _showAllBounds = false;

  /// showAllBounds outlines every element, not only the selected one, for
  /// elements that relate to each other, such as a chain of text boxes.
  bool get showAllBounds => _showAllBounds;

  set showAllBounds(bool value) {
    if (_showAllBounds == value) return;
    _showAllBounds = value;
    _notifyView();
  }

  bool _lockJoins = false;

  /// lockJoins stops a drag changing the connectors between text boxes,
  /// whose grips sit on the resize handles' outline; locked, they ignore
  /// the pointer.
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

  /// focusedPlayer is which player of the selected team the keyframe
  /// controls point at, since a player cannot be selected. Set by clicking
  /// one on the canvas; cleared when the selection changes.
  int? get focusedPlayer => _focusedPlayer;

  set focusedPlayer(int? value) {
    if (_focusedPlayer == value) return;
    _focusedPlayer = value;
    notifyListeners();
  }

  /// focusedTeam is the selected element when it is a team, else null.
  TeamElement? get focusedTeam {
    var element = selected;
    return element is TeamElement ? element : null;
  }

  RetouchBrush _retouch = RetouchBrush.off;

  /// retouch is the brush painting a picture's background in or out. A mode
  /// rather than a modifier key, since retouching takes a run of strokes.
  RetouchBrush get retouch => _retouch;

  set retouch(RetouchBrush value) {
    if (_retouch == value) return;
    _retouch = value;
    notifyListeners();
  }

  /// _pendingStroke is a stroke drawn but not applied, on _pendingPicture.
  /// Held so it redraws as the brush settings change until it is applied.
  List<Offset>? _pendingStroke;
  String? _pendingPicture;

  /// _pendingKeeps, _pendingTeaches and _pendingFills are what the brush was
  /// doing when the stroke was drawn: changing brush starts something else.
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

  void discardStroke() {
    if (_pendingStroke == null) return;
    _pendingStroke = null;
    _pendingPicture = null;
    notifyListeners();
  }

  /// applyStroke writes the held stroke onto its picture, brush as it is.
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
      // A hint is a sample, not a mark, so it is taken exactly where drawn:
      // softening or snapping it would collect colours not pointed at.
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

  /// magnetiseCling sets the cling to the edge the held stroke crossed, where
  /// its colour distances split into two clusters (see suggestSnap). False
  /// when there is no edge.
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

  /// pendingAsStroke is the held stroke as it would apply now: the preview.
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

  /// _clingFor is how much a stroke clings. Never for a hint, sampled exactly
  /// where drawn, nor for putting back: the subject is every colour, so
  /// clinging would restore only pixels like the first.
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

  /// cutInside takes what a boundary encloses rather than what surrounds it,
  /// read when the stroke is applied so it can be flipped while one is held.
  bool get cutInside => _cutInside;

  set cutInside(bool value) {
    if (_cutInside == value) return;
    _cutInside = value;
    notifyListeners();
  }

  /// _brushSnap starts at nothing: clinging is an aid to reach for on
  /// purpose, and on by default it makes the brush look broken.
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

  /// pageLocked stops the page scrolling or zooming. On a 3D stage those
  /// gestures steer the stage's camera instead: drag orbits, shift-drag
  /// pans, pinch zooms.
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

  Set<(String, String)> _motionPicks = const {};

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

  /// _ownTab is the Motion clips card's Arrive, Loop or Leave picked where
  /// it has no clip (unset, or the loop, which plays without one); its
  /// Preset is set there. Picking a clip lets it go.
  MotionKind? _ownTab;

  MotionKind? get ownTab => _ownTab;

  /// _clipSettings are the elements whose preset shows its clip's own
  /// settings (speed, layer, mix, name) on the Motion clips card.
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

  bool _animationOpen = false;

  /// _chainMotion is the view the Chain reopens on: the one it was last on.
  bool _chainMotion = false;

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

  String? _chainFocus;

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

  /// motionTrail shows the trail (the path its middle takes) and onion skin
  /// of the element whose motion the Chain is open on. On by default.
  bool get motionTrail => _motionTrail;
  bool _motionTrail = true;
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

  bool _rowsShown = true;

  /// rowsShown is the Timeline panel, open in its place (see dock).
  bool get rowsShown => _rowsShown;

  set rowsShown(bool value) {
    if (_rowsShown == value) return;
    _rowsShown = value;
    if (value) _dockOpening(DockPanel.timeline);
    _notifyView();
  }

  bool _barBelow = false;

  /// barBelow puts the play bar under the panels: kept by CanvasPlayBar.
  bool get barBelow => _barBelow;
  set barBelow(bool value) {
    if (_barBelow == value) return;
    _barBelow = value;
    _notifyView();
  }

  bool _trackpadScrolls = false;

  /// trackpadScrolls lets a sideways swipe or the wheel move the timeline.
  /// Off by default, so swiping through the channels does not slide frames.
  bool get trackpadScrolls => _trackpadScrolls;
  set trackpadScrolls(bool value) {
    if (_trackpadScrolls == value) return;
    _trackpadScrolls = value;
    _notifyView();
  }

  /// timelineZoomAsked counts the play bar's requests to zoom the timeline
  /// by timelineZoomFactor (0: to the whole scene). With no timeline open,
  /// a request is dropped.
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

  /// dock is where each panel under the canvas opens and how the places are
  /// switched, saved in preferences. Changing it leaves one panel per place.
  DockLayout get dock => _dock;

  set dock(DockLayout next) {
    if (next == _dock) return;
    _dock = next;
    _dockSettle();
    _notifyView();
  }

  /// restoreDock puts back [layout] as the screen opens, without notifying.
  void restoreDock(DockLayout layout) {
    _dock = layout;
    _dockSettle();
  }

  bool dockOpen(DockPanel panel) => switch (panel) {
        DockPanel.timeline => _rowsShown,
        DockPanel.slots => _slotsBeside,
        DockPanel.mixer => _mixerOpen,
        DockPanel.chain => _animationOpen || _effectsOpen,
      };

  /// setDockOpen opens or closes [panel], displacing what shares its place.
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

  /// toggleDock is [panel]'s button; [beside] opens it on the left, if any.
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

  /// moveDockPanel makes [place] the home of [panel] and opens it there.
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

  /// dockArrangement is the layout last chosen, until anything changes.
  String? get dockArrangement => _arrangementChosen;
  String? _arrangementChosen;

  /// arrange shows [layout]'s panel in each place (with one place, its one).
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

  /// saveArrangement saves what is showing as a layout called [name].
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

  void removeArrangement(String name) {
    _dock = _dock.copyWith(
        saved: [..._dock.saved.where((a) => a.name != name)]);
    if (_arrangementChosen == name) _arrangementChosen = null;
    _notifyView();
  }

  /// _dockOpening closes whatever else shows in [panel]'s place, silently.
  void _dockOpening(DockPanel panel) {
    var place = _dock.placeOf(panel);
    for (var other in DockPanel.values) {
      if (other != panel && dockOpen(other) && _dock.placeOf(other) == place) {
        _setDockRaw(other, false);
      }
    }
    _arrangementChosen = null;
  }

  /// _dockSettle leaves one open panel per place, the first in button order.
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

  /// timelineShow is the ⋯ menu's Show, for the timeline and the mixer.
  TimelineShow get timelineShow => _timelineShow;
  set timelineShow(TimelineShow value) {
    if (_timelineShow == value) return;
    _timelineShow = value;
    _notifyView();
  }

  bool _slotsBeside = false;

  /// slotsBeside is the Slots panel, open in its place (see dock); level
  /// with the timeline's rows when it is on the left and they are in main.
  bool get slotsBeside => _slotsBeside;
  set slotsBeside(bool value) {
    if (_slotsBeside == value) return;
    _slotsBeside = value;
    if (value) _dockOpening(DockPanel.slots);
    _notifyView();
  }

  /// slotsWithRows is the slots drawn level with the timeline's rows.
  bool get slotsWithRows =>
      _slotsBeside &&
      _rowsShown &&
      _dock.placeOf(DockPanel.slots) == DockPlace.left &&
      _dock.placeOf(DockPanel.timeline) == DockPlace.main;

  /// slotCellWidth and slotCellHeight are a slot's fixed size by the rows.
  static const double slotCellWidth = 72, slotCellHeight = 22;

  /// slotsShown is how many slots each row has: at least two, and one past
  /// the last used (by any clip or named cue), never more than the cues.
  /// See _slotRowsGrown.
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

  /// _slotRowsGrown adds a cue to [next] when its last is used (slotsShown).
  static CanvasDocument _slotRowsGrown(CanvasDocument next) {
    var rows = next.session.rows;
    if (rows >= 256 || lastSlotUsed(next) < rows - 1) return next;
    return next.copyWith(session: next.session.withScene());
  }

  /// slotsColumn is the widest the slots beside the rows grow as they fill,
  /// set by dragging the grip; past it they scroll (see slotsScroll).
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

  /// slotsScroll is how far all the slots beside the rows are scrolled: its
  /// own notifier, so a scroll redraws the slots and nothing else.
  final ValueNotifier<double> slotsScroll = ValueNotifier(0);

  /// scrollSlots scrolls the slots by [by] pixels, within what overflows the
  /// [shown] column (the slots beside the rows by default).
  void scrollSlots(double by, {double? shown}) {
    slotsScroll.value = (slotsScroll.value + by)
        .clamp(0.0, math.max(0.0, slotsContent - (shown ?? slotsWidth)))
        .toDouble();
  }

  void _clampSlotsScroll() => scrollSlots(0);

  /// slotsWidth is the slots beside the rows, or 0 when they are not shown;
  /// leftWidth is everything left of the lanes, where the time starts.
  double get slotsWidth =>
      slotsWithRows ? math.min(_slotsColumn, slotsContent) : 0;
  double get leftWidth => headerWidth + slotsWidth;

  /// canvasSnap is the bar's Snap: the page's snap, or on a 3D stage the
  /// stage's own, which starts off. Not [snapping], which is the timeline's.
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

  /// steeredStage is the 3D stage the view controls steer: the selected
  /// element's, else the scene's first (background, then a Background
  /// element). Null where there is none, and the bar shows the page tools.
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

  bool get onStage3d => steeredStage != null;

  /// steer moves the steered stage's camera to [to] of its setting on this
  /// frame (its key where keyed). Nothing without a stage, or if locked.
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

  /// panCameraBy slides the steered camera by [by] page units, with the
  /// pointer.
  void panCameraBy(Offset by, {bool transient = false}) {
    var s = steeredStage;
    if (s == null) return;
    var view = stageView(s, _frame);
    steer((c) => view.panned(by), transient: transient);
  }

  /// dollyBy scales the steered camera's distance by [factor]: below 1 nearer.
  void dollyBy(double factor, {bool transient = false}) =>
      steer((c) => c.copyWith(distance: c.distance * factor),
          transient: transient);

  /// frameSelected turns the steered camera to fill the view with the one
  /// selected element, if it stands on a stage.
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

  /// resetCamera puts the steered camera back to its start, keeping its lens.
  void resetCamera() => steer((c) => StageCamera(lens: c.lens));

  CanvasTool _tool = CanvasTool.select;

  /// tool is what dragging on the canvas does. Select to begin with.
  CanvasTool get tool => _tool;

  set tool(CanvasTool value) {
    if (_tool == value) return;
    _tool = value;
    _notifyView();
  }

  /// hoveredButton is the button under the pointer, so hover colours show.
  String? hoveredButton;

  Timer? _playback;
  bool get playing => _playback != null;

  bool _opened = false;

  /// opened is whether this session has been shown. The session outlives
  /// the page, so only the first visit restores the last save.
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
    var designing = next;
    next = synthSynced(next,
        designedAt: (e, f) => designedNow(e, f, designing));
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

  bool get trying => _beforePreview != null;

  /// tryElement previews [element] in place of the one it replaces, outside
  /// the history and unsaved, until a null or the next real edit: for
  /// previewing a list's options before one is chosen.
  void tryElement(CanvasElement? element) {
    if (element == null) {
      if (_endPreview()) notifyListeners();
      return;
    }
    _beforePreview ??= _document;
    _document = _beforePreview!.withElement(element);
    notifyListeners();
  }

  /// _endPreview restores the real document; false if there was no preview.
  bool _endPreview() {
    var before = _beforePreview;
    if (before == null) return false;
    _beforePreview = null;
    _document = before;
    return true;
  }

  /// withCountLaidOut pins a new keyframed counter's count from the playhead
  /// to two seconds on (or the last two seconds near the end), so From and
  /// To work without pinning both by hand.
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
    // And clips picked on the timeline from another scene or the master.
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

  /// placeTimedClip puts [e]'s [clip] at frame [run] of the whole run. A
  /// clip on a scene moves to the scene [run] falls in; one on the master or
  /// the backdrop stays on it.
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
    // Keep it picked, in the selection here or among clips picked elsewhere.
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

  /// deleteElement takes out element [id], for a layers row's delete,
  /// ending its editing first.
  void deleteElement(String id) {
    if (_document.elementById(id) == null) return;
    if (_vectorEditing == id) editVector(null);
    if (editingImage?.id == id) editImage(null);
    _selection = {..._selection}..remove(id);
    apply(_document.removeElement(id));
  }

  /// duplicateSelected copies the chosen elements, offset a little.
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
    // Synth modules copied together are patched to each other.
    apply(synthCopied(next, ids));
    _selection = made;
    notifyListeners();
  }

  /// _clipboard is what was last copied. Not the system clipboard: an
  /// element has no sensible text form, and JSON would replace what the
  /// reader copied elsewhere. Static, so a copy survives leaving the page.
  static List<CanvasElement> _clipboard = const [];

  /// _pasteOffset steps each paste down and right, so it is visibly a copy.
  static const double _pasteOffset = 16;

  bool get canPaste => _clipboard.isNotEmpty;

  /// copySelected copies the selection and the clips picked on the timeline
  /// from another canvas, such as the master's music picked from a scene.
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
  /// run's clock (0 for the master), or null when it is on none.
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
      // A master clip copied from a scene goes back onto the master at the
      // playhead on the run's clock. One from another scene comes to the
      // playhead's scene: sent back past its own end, it would never play.
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
        // A timed video likewise: at the playhead, in the same place.
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

  /// alignSelected lines the chosen elements up on one edge or middle of the
  /// selection's own box, not the canvas, so it needs two.
  void alignSelected(CanvasAlign align, {bool transient = false}) {
    // With a picture's layers open, its picked layers, against their box.
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

  /// spreadSelected puts an even gap between the chosen elements; the end
  /// two stay, so it needs three. Gaps rather than centres, since spacing
  /// different sizes by centre leaves visibly different gaps.
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

  /// posesRatherThanMoves is whether dragging [element] records a keyframe
  /// instead of moving it. Keyframes are offsets from the resting position,
  /// so moving the rest moves them all and a pose would record nothing.
  /// A drag poses when the document is animated and auto-keyframe is on or
  /// the element is already posed (not merely keyed: a chart's arrival keys
  /// say only how much is drawn). The X and Y fields still move the rest.
  bool posesRatherThanMoves(CanvasElement element) =>
      _document.isAnimated &&
      // Never for an element a path drives: the next point moved would
      // overwrite the pose, so the drag moves its start instead.
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
  /// Absolute rather than a delta, since deltas drift and compound on a pose.
  CanvasElement movedTo(CanvasElement element, Offset topLeft) {
    // An element on a stage moves across its floor, or along its back wall.
    if (element.base.spot != null) {
      var at = stagedIn(_document, element, _frame);
      if (at != null) {
        // Where it stands on this frame; keyed, the move is a key here.
        var spot = at.spot;
        var by = topLeft - at.box.topLeft;
        var view = at.view;
        // Snapping lands on the 3D steps: a stage has no lines to snap to.
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
            // The floor point under the pointer follows it, on the level
            // the element is lifted to.
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

  /// cameraShifted is [start], a camera as a drag began, looking [by]
  /// further across and down: a key on this frame where it is animated,
  /// else its box moved. Kept to what the framing allows, so a drag past
  /// the edge leaves no pose the frame cannot follow.
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

  /// cameraZoomed is [start], a camera as a drag began, [factor] times
  /// closer about the middle of its view: a key's size where animated, else
  /// its box. Between the whole page and eight times.
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

  /// pathDriving is the path that owns [elementId]'s keyframes, if any. Its
  /// track is rewritten when the route changes, so the timeline refuses hand
  /// edits and shows the path's points.
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

  /// applyPathFollow bakes [path]'s route into its follower's keyframes, one
  /// per frame from the first node to the last, sampled by arc length.
  /// Baked rather than live, so the renderer, the GIF encoder and a
  /// published canvas play it like any track and cannot disagree.
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
      // On a pitch the route is carried onto the pitch's own metres, so the
      // follower keeps to the curve however the pitch is seen.
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

  /// _bakeOnPitch is [_bake] for a player on a pitch, in the units a run on
  /// a pitch is kept in (see playerPlace).
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

  /// clearPathFollow takes the baked keys off, or the follower is stranded.
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

  /// valueAt is extra [channel] on this frame, or [orElse] if never keyed.
  double valueAt(CanvasElement element, String channel, double orElse) =>
      element.poseAt(_frame).values[channel] ?? orElse;

  /// hasValueKey is whether [channel] is pinned on this frame: its diamond.
  bool hasValueKey(CanvasElement element, String channel) =>
      element.track?.keyAt(_frame)?.values.containsKey(channel) ?? false;

  /// setValueKey pins one extra property at the current frame, seeded at the
  /// start so one press makes a movement (see ElementTrack.seededFor). A
  /// counter passes [seed] false: a seed marks the element as moving in
  /// space, and a count's first key holds for every frame before it anyway.
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

  /// clearValueKey unpins [channel] here, and the key if that was all of it.
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

  /// lipSync gives [e] mouths for what [voice] says: from the words (heard
  /// first if need be), or from loudness alone with [words] off. Replaces
  /// its earlier mouths over the stretch, as one undo step. Returns what
  /// stopped it, or how many mouths it laid.
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
    // Where the voice starts and stops in the run, and the character's frames.
    var voiceAt = _clipOffset(voice) + voice.clip.at;
    var voiceEnd = voiceAt + ((to - from) * rate).ceil();
    var mine = _clipOffset(e);

    List<MouthKey> keys;
    if (words) {
      var tag = "voice:${voice.id}";
      // A Speech take knows its words and timing: read, not heard again.
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

  /// _takeWords are [voice]'s words where it is a Speech device's take, as
  /// run frames from [voiceAt], kept by its trim; null for any other sound.
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

  /// clearLipSync takes every mouth off [e], a 3D character.
  void clearLipSync(CanvasElement e) => replaceElement(switch (e) {
        Character3dElement c => c.performing(c.performance.withMouths(const [])),
        _ => e,
      });

  /// stageFilmed is [stage] with its camera at [camera]: its own setting
  /// until the camera is keyed, then this frame's key.
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

  /// parallaxOf is the parallax scenery [id] as drawn, as [stageOf] is.
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

  /// parallaxFilmed is [p] with its camera at [camera], as [stageFilmed].
  ParallaxElement parallaxFilmed(ParallaxElement p, ParallaxCamera camera) {
    if (!_cameraKeyed(p)) return p.copyWith(camera: camera);
    return p.withBase(track: _pinnedAt(p.track!, _frame, camera.channels))
        as ParallaxElement;
  }

  /// putBackdrop writes a stage or a parallax back where it lives: its
  /// Background element, or the background behind the canvas.
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

  /// keyCamera keys [stage]'s camera on this frame, and on the first frame
  /// the first time, so the move starts where the camera was.
  void keyCamera(CanvasElement stage) {
    var track = stage.track ?? ElementTrack.empty;
    if (!_cameraKeyed(stage) && _frame != 0) {
      track = _pinnedAt(track, 0, _cameraRest(stage));
    }
    putBackdrop(
        stage.withBase(track: _pinnedAt(track, _frame, _cameraNow(stage))));
  }

  bool hasCameraKey(CanvasElement stage) =>
      stage.track
          ?.keyAt(_frame)
          ?.values
          .keys
          .any((c) => c.startsWith("cam.")) ??
      false;

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

  bool spotKeyed(CanvasElement e) =>
      e.track?.keys.any((k) => k.values.keys.any((c) => c.startsWith("spot."))) ??
      false;

  /// spotted is [e] standing at [spot]: its own spot until keyed, then this
  /// frame's key. Its stage and how it stands are never keyed.
  CanvasElement spotted(CanvasElement e, StageSpot spot) {
    var own = e.base.spot;
    if (own == null || !spotKeyed(e)) return e.withBase(spot: spot);
    var kept = e.withBase(
        spot: own.copyWith(stage: spot.stage, stand: spot.stand));
    return kept.withBase(track: _pinnedAt(e.track!, _frame, spot.channels));
  }

  /// keySpot keys [e]'s spot here, and the first time frame 0 too.
  void keySpot(CanvasElement e) {
    var spot = e.spotAt(_frame);
    if (spot == null) return;
    var track = e.track ?? ElementTrack.empty;
    if (!spotKeyed(e) && _frame != 0) {
      track = _pinnedAt(track, 0, e.base.spot!.channels);
    }
    replaceElement(e.withBase(track: _pinnedAt(track, _frame, spot.channels)));
  }

  bool hasSpotKey(CanvasElement e) =>
      e.track
          ?.keyAt(_frame)
          ?.values
          .keys
          .any((c) => c.startsWith("spot.")) ??
      false;

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
    _pan = Offset2(_pan.dx * f, _pan.dy * f);
    _zoom = next;
    // Back at the fit, re-centre, or an earlier pan leaves it off-centre.
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

  bool _mixerOpen = false;

  bool _mixerSmallest = false;

  bool _mixerMinimised = false;

  // ---- Kept between visits

  /// timelineView is the stretch the timeline is zoomed to (null for all),
  /// as last drawn; timelineViewSet counts restores from outside.
  TimelineView? timelineView;
  int timelineViewSet = 0;

  bool _effectsOpen = false;

  /// _speechShown is whether the Chain's sound shows the channel's Speech.
  /// Speech makes clips rather than being a chain step, so it shows on ask.
  bool _speechShown = false;

  /// _pitchShown is whether the Chain shows its channel's Pitch editor.
  bool _pitchShown = false;

  /// _instrumentShown is whether the Chain shows its Instrument editor.
  bool _instrumentShown = false;

  /// _chainFull is whether the Chain fills the window, the canvas put away.
  bool _chainFull = false;

  /// chainFull: see _chainFull. While set, the dock fills the canvas's room.
  bool get chainFull => _chainFull;

  set chainFull(bool full) {
    if (full == _chainFull) return;
    _chainFull = full;
    notifyListeners();
  }

  /// _keysShown is whether the Chain's Keys strip is open: for the session.
  static bool _keysShown = false;

  bool get keysShown => _keysShown;

  /// _keysHeight is the Keys strip's dragged height, or null for its own.
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
  final ValueNotifier<int> keysHeld = ValueNotifier(0);

  /// playheadMoved ticks each time the playhead moves on in play, so what
  /// draws only the playhead (the piano roll's line) need not rebuild.
  final ValueNotifier<int> playheadMoved = ValueNotifier(0);

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

  /// allFolded is whether the All group (the master's rows, in every scene)
  /// is folded under its heading, on the timeline and in the mixer.
  bool get allFolded => _allFolded;
  set allFolded(bool folded) {
    if (folded == _allFolded) return;
    _allFolded = folded;
    notifyListeners();
  }

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

  /// load replaces the whole session with a document from disk.
  void load(CanvasDocument document, {String? folder, String? name}) {
    pause();
    stopAudio();
    // Empty sounds left as elements are dropped. An empty channel made on
    // purpose (named, with effects, Speech or slot clips) stays, since its
    // slots and mix would go with it.
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
      // A drawing saved mid-edit opens with its box fitted round it.
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
    // Opened on the frame everything has arrived by, so a canvas whose
    // elements arrive does not open as an empty page.
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

  Timer? _autosave;

  /// _autosaveDelay is how long the editing has to stop for: long enough
  /// that a drag is one write, short enough to lose nothing.
  static const Duration _autosaveDelay = Duration(seconds: 3);

  /// scheduleAutosave writes the document out once editing stops for a
  /// moment, so a burst of edits is one write. Only once saved: until then
  /// there is nowhere to write, and inventing a file would fill the library.
  void scheduleAutosave() {
    if (name == null || !_dirty) return;
    _autosave?.cancel();
    _autosave = Timer(_autosaveDelay, () {
      _autosave = null;
      if (name != null && _dirty) save();
    });
  }

  /// _toSave is the document as written: a drawing still being edited gets
  /// its box fitted, as leaving editing would (not live, which would move
  /// the pencil's mirror lines). See _fitEditedVector.
  CanvasDocument get _toSave {
    // Never a look that is only being tried. See tryElement.
    var document = _beforePreview ?? _document;
    var e = editingVector;
    if (e == null) return document;
    var fitted = boxedToDrawing(e);
    return identical(fitted, e) ? document : document.withElement(fitted);
  }

  /// save writes back to where the document came from, if it has been saved.
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
    PatternCounts.counted.removeListener(_patternCounted);
    _endWait();
    chartGlideBeat.removeListener(_glideBeat);
    chartGlides.clear();
    slotsScroll.dispose();
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
      HardwareKeyboard.instance.removeHandler(_gameKey);
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
  /// 0 on this scene, the scene's run start for a clip following the run.
  final int offset;

  /// editable is whether it can be changed here: a transition's sound is
  /// changed on its transition; the master's, from any scene.
  final bool editable;

  /// scene is the clip's canvas: -1 for the master, else the scene's index.
  final int scene;

  const TimedLane(this.element,
      {this.offset = 0, this.editable = true, this.scene = -1});

  /// sceneLabel names the scene on the channel strip: M, or S1 for the first.
  String get sceneLabel => scene < 0 ? "M" : "S${scene + 1}";

  MediaClip get clip => switch (element) {
        VideoElement v => v.clip,
        AudioElement a => a.clip,
        _ => const MediaClip(),
      };

  /// channelKey is the channel this is on: its own, for a clip with none.
  String get channelKey => clip.channel.isNotEmpty ? clip.channel : element.id;

  /// interactive is whether this sounds when pressed on the canvas rather
  /// than at a time: it has a strip and effects like any sound, but nothing
  /// on its lane to move or cut. See interactiveLanes.
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

  /// interactive is a channel of sounds pressed on the canvas (TimedLane).
  bool get interactive => lanes.every((l) => l.interactive);

  /// sceneLabel is which canvas its clips are on (TimedLane.sceneLabel).
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

  /// startAt and loopAt are where it and its loop start, seconds into it.
  final double startAt, loopAt;

  /// origin is when it would have started from its start: [from], or
  /// earlier where it took over another's place -- legato.
  double origin;

  /// followed is whether its follow action is done, and followFrom when its
  /// wait began: [from], or that of the clip it carries on from.
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
// Each starts from a top-level function: a closure made in a controller
// method can capture the controller and its timers, which cannot be sent.

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

/// clipPieces are what [clip] plays over [seconds] from its start: each a
/// stretch (from and to, seconds into what it plays) and when it is heard,
/// from the start on to the loop's end, then round the loop.
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

/// _LiveArp is an arpeggiator playing live: the keys held, each as the keys
/// it sounds through the effects before it, and the one sounding.
class _LiveArp {
  final Arpeggio player;
  final Map<int, List<int>> pressed = {};

  /// velocities are each key's loudest note through the Velocity effect: a
  /// step plays as loud as the loudest held, as the rendered one does.
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

/// _Chrome is the notifier behind [CanvasController.chrome].
class _Chrome extends ChangeNotifier {
  void tell() => notifyListeners();
}
