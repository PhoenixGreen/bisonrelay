import 'dart:async';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/automation.dart';
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
import 'package:bruig/plugin_system/canvas/media/mix/decode.dart'
    show ffmpegDecode, readWholeAway;
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart' show mixRate;
import 'package:bruig/plugin_system/canvas/ui/character_face_rig_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/plugin_system/canvas/ui/character_rig_editor.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
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
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/team_painter.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/responsive_layout.dart';
import 'package:bruig/plugin_system/canvas/render/scene_sequence.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_motion.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_lipsync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_doll.dart';
import 'package:bruig/plugin_system/canvas/ui/character_doll_pose.dart';
import 'package:bruig/plugin_system/canvas/ui/sprite_painting.dart';
import 'package:bruig/plugin_system/canvas/ui/tile_painting.dart';
import 'package:bruig/plugin_system/canvas/render/tile_map_painter.dart' show tileMapEditingOf;
import 'package:bruig/plugin_system/canvas/render/sprite_painter.dart' show spritePaintingOf;
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart'
    show characterDollLook, characterDollOf, characterSoloOf;
import 'package:bruig/plugin_system/canvas/render/character/character_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character_drawing_settings.dart'
    show showPanel;
import 'package:bruig/plugin_system/canvas/render/character/character_live.dart'
    show rebasedCharacter;
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
import 'package:bruig/plugin_system/canvas/ui/canvas_game.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart' show ControlAction;
import 'package:gamepads/gamepads.dart' show Gamepads, NormalizedGamepadEvent;
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart'
    show newInstrument;
import 'package:bruig/plugin_system/canvas/model/notation.dart' show splitKey;
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/render/sheet_painter.dart';
import 'package:bruig/plugin_system/canvas/media/synth/part_render.dart';
import 'package:path/path.dart' as path;
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
import 'package:bruig/plugin_system/canvas/model/surround.dart' show Heard;
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/render/audio_painter.dart';

import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, KeyRepeatEvent, KeyUpEvent, LogicalKeyboardKey;

// canvas_controller.dart holds everything about the canvas being edited that
// is not the document itself: what is selected, where the playhead is, how far
// in the view is zoomed, what can be undone, and whether any of it has been
// saved.
//
// The document is immutable (see canvas_document.dart), so every edit goes
// through [apply], which is the only place the document is replaced. That one
// funnel is what makes undo a list of past documents rather than a list of
// operations to reverse -- and reversible operations are where an editor like
// this usually goes wrong, because the reverse of "resize" is not "resize
// back" once a rotation has happened in between.
//
// It also means an edit cannot half-happen. There is no state in which the
// selection refers to an element the document no longer has, because both
// change in one assignment.

/// _maxUndo bounds the history.
///
/// Documents are small -- a few kilobytes of value objects, sharing every
/// element that did not change -- so this can be generous. It is bounded at
/// all only because a session spent nudging a slider would otherwise grow
/// without limit.
const int _maxUndo = 120;

/// minZoom and maxZoom bound the view.
///
/// These are multiples of the fitted size, not of the document's own pixels --
/// see [CanvasController.zoom]. So 1 is "the whole canvas, filling the area",
/// 0.25 is a quarter of that with room around it, and 16 is close enough to
/// nudge a single player dot into place.
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
  /// out. The difference matters at the point the stroke is stored, and
  /// nowhere else.
  bool get teaches =>
      this == RetouchBrush.markBackground || this == RetouchBrush.markSubject;

  /// keeps is whether the mark is about the subject rather than the
  /// background.
  bool get keeps =>
      this == RetouchBrush.restore || this == RetouchBrush.markSubject;

  /// fills is whether the stroke is a boundary rather than a mark.
  bool get fills => this == RetouchBrush.cutAround;
}

/// CanvasTool is what dragging on the canvas does.
///
/// Two tools rather than one gesture that guesses. Dragging meant "move what
/// is under the pointer, or sweep a selection over empty space", and panning
/// was on the middle button and the space bar -- both of which are invisible,
/// and one of which most trackpads do not have. With a tool chosen explicitly
/// the reader can also *stop* the view moving, which is what somebody nudging
/// a player into place actually wants.
enum CanvasTool {
  /// select moves and selects elements. The view does not move at all in this
  /// tool -- not by dragging and not by scrolling -- so nothing shifts under a
  /// careful adjustment.
  select("Select", "Move and select elements; the view stays put"),

  /// pan moves the view. Dragging slides the canvas about and the wheel zooms.
  pan("Pan", "Drag to move around the canvas, scroll to zoom");

  final String label;
  final String description;
  const CanvasTool(this.label, this.description);
}

/// CanvasFit is how large the canvas's frame is drawn.
///
/// Two modes, because "as big as it will go" means two different things
/// depending on the shape of the document. A 16:9 banner in a wide window is
/// limited by the height; a 9:16 story is limited by the width, and fitting the
/// whole of it leaves it a narrow strip down the middle with most of the
/// window empty on either side.
enum CanvasFit {
  /// whole shows all of the canvas at once, limited by whichever of the two
  /// dimensions runs out first. Nothing scrolls.
  whole("Show the whole canvas"),

  /// width fills the area's full width and lets the canvas be as tall as it
  /// needs, scrolling if that is taller than the window. What a tall document
  /// wants: readable at the cost of not seeing all of it at once.
  width("Fit to width");

  final String label;
  const CanvasFit(this.label);
}

/// CanvasController is the editing session.
/// _afterEntrance is how far into the timeline an element's entrance reaches.
///
/// The last frame the reveal channel touches, or nothing if it touches none.
/// A closing animation starts after it: overlapping the two bands has an
/// element arriving and leaving at once, which draws as a stutter and reads
/// as a bug.
int _afterEntrance(ElementTrack track) {
  var ends = 0;
  for (var key in track.keys) {
    if (key.values.containsKey(KeyframeChannel.reveal)) {
      ends = math.max(ends, key.frame);
    }
  }
  return ends;
}

/// _withClosingBand is [track] with one closing animation on it, running
/// [from] to [to] and replacing whatever closing keyframes it had.
///
/// Two callers lay this same pair -- the one that puts a closing preset on
/// an element and the one that puts it on a chart -- and they had a copy
/// each of the loop that clears the old keys and the two that write the new
/// ones.
/// _without is [track] with [channel] unpinned everywhere, and with any
/// keyframe that held nothing else dropped.
///
/// Taking the *keyframe* away instead threw out whatever else stood on that
/// frame: a chart moved by hand at frame 0 and then given an arrival had its
/// move deleted by choosing None, which is not what None means. It means no
/// arrival.
ElementTrack? _without(ElementTrack? track, String channel) {
  if (track == null) return null;
  var kept = <Keyframe>[
    for (var key in track.keys)
      if (key.values.containsKey(channel)) key.withoutValue(channel) else key,
  ]..removeWhere((key) => !key.posesElement && key.values.isEmpty);
  return kept.isEmpty ? null : ElementTrack(kept);
}

ElementTrack _withClosingBand(ElementTrack track, int from, int to) {
  for (var key in track.keys) {
    if (key.values.containsKey(KeyframeChannel.close)) {
      track = track.withoutFrame(key.frame);
    }
  }
  return _pinning(_pinning(track, from, KeyframeChannel.close, 0), to,
      KeyframeChannel.close, 1);
}

/// _pinning is [track] with [channel] pinned to [value] at [frame], keeping
/// whatever else that frame already holds.
///
/// A keyframe is a pose *and* whatever channels are pinned there, and laying
/// an animation down writes one key at each end of it. Written as a fresh
/// keyframe, those two ends flattened any pose that happened to be standing
/// on the same frame -- so animating an element that had been moved by hand
/// at the frame the playhead was on silently threw the move away. And a frame
/// with no keyframe on it starts from where the element is there, not from
/// rest -- see ElementTrack.restingAt.
ElementTrack _pinning(
        ElementTrack track, int frame, String channel, double value) =>
    track.withKey((track.keyAt(frame) ?? track.restingAt(frame))
        .withValue(channel, value));

/// _pinnedAt is [track] with [channels] pinned at [frame], keeping
/// whatever else that frame already holds -- see _pinning.
ElementTrack _pinnedAt(
    ElementTrack track, int frame, Map<String, double> channels) {
  var at = track.keyAt(frame) ?? track.restingAt(frame);
  return track.withKey(at.copyWith(values: {...at.values, ...channels}));
}

/// FetchedRows is what one element's last refresh in this sitting returned.
///
/// Kept so the mapping controls can change their mind -- which column is the
/// axis, which one a series is drawn from -- without asking the source again.
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

class CanvasController extends ChangeNotifier {
  CanvasController(CanvasDocument document,
      {AudioEngine? audioEngine, FrameSource? frameSource})
      : _document = document,
        _audioEngine = audioEngine,
        _frameSource = frameSource;

  CanvasDocument _document;
  CanvasDocument get document => _document;

  /// lastFetched is what each element's last refresh returned, by element id.
  ///
  /// Here rather than in the settings panel that runs the refresh, because
  /// two buttons run one -- the Data source section's and the one on the
  /// Table section, which is not inside that panel -- and a refresh from the
  /// second left the mapping controls with no rows in hand. Here rather than
  /// in a global, because a global outlives the document it describes: rows
  /// from a canvas that has been closed, filed under an element id another
  /// canvas may well use.
  ///
  /// Not in the document, deliberately: four thousand rows saved into every
  /// canvas so that a dropdown need not ask again is not a trade worth
  /// making. It is a fact about this sitting.
  final Map<String, FetchedRows> lastFetched = {};

  final CanvasImageStore images = CanvasImageStore();

  final List<CanvasDocument> _undo = [];
  final List<CanvasDocument> _redo = [];

  /// _interaction is the document as it was when a drag began.
  ///
  /// A drag produces dozens of edits a second and every one of them must not
  /// be its own undo step -- otherwise undoing a move means pressing it forty
  /// times. So the whole gesture is one step: the document is remembered when
  /// the gesture starts and pushed onto the history when it ends.
  CanvasDocument? _interaction;

  Set<String> _selection = {};
  Set<String> get selection => _selection;

  bool _backgroundSelected = false;

  /// backgroundSelected is whether the canvas's own background is the thing
  /// being edited.
  ///
  /// Its own flag rather than a sentinel id inside [selection], because the
  /// background is not an element and every operation that walks the selection
  /// -- delete, duplicate, nudge, group into a keyframe -- would have had to
  /// learn to skip it. Missing one of them is silent: the operation finds no
  /// element for the id and quietly does nothing, which looks exactly like a
  /// bug in the operation.
  ///
  /// It is exclusive with the element selection. Both mean "this is what the
  /// settings below the layer list are about", and there is only one of those.
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
  /// drawn in -- not of the document's own pixels.
  ///
  /// That is the difference between this and every other zoom control, and it
  /// is deliberate. A canvas has no natural size on screen: the same document
  /// is 1280 pixels wide or 4096 depending only on what it is going to be
  /// published at, and a zoom measured against that would mean the same design
  /// opened at two different export widths filled the window very differently.
  /// So the canvas always fills the area to begin with, and zoom is how far in
  /// you have gone from there. 1 is the whole canvas; anything above it is a
  /// detail, and pans.
  ///
  /// The fitted size itself is worked out by the stage, which is the only
  /// thing that knows how much room there is. See CanvasStage.
  double get zoom => _zoom;

  /// _fitScale is what the stage last reported: how much the canvas is
  /// shrunk to fill the window before any zoom is applied.
  ///
  /// The stage owns this -- it is the only thing that knows how much room
  /// there is -- and reports it so that the band can say what somebody is
  /// actually looking at. See [viewScale].
  double _fitScale = 1;

  /// viewScale is document pixels to screen pixels: what the percentage on
  /// the band means.
  ///
  /// Not [zoom], which is a multiple of the fitted size and is therefore 1
  /// whenever the whole canvas is showing -- whatever size that turned out to
  /// be. The band said 100% for a 4096-pixel canvas squeezed into a third of
  /// a window, which is a claim about the view that is plainly untrue.
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

  /// atFit is whether the view is showing the whole canvas, untouched -- which
  /// is what the Fit button lights up for.
  bool get atFit => (_zoom - 1).abs() < 0.001 && _pan.dx == 0 && _pan.dy == 0;

  Offset2 _pan = const Offset2(0, 0);
  Offset2 get pan => _pan;

  /// revision counts every change that is about the *document* rather than
  /// about the view of it.
  ///
  /// What the sidebar watches. The controller notifies for everything --
  /// panning, zooming, hovering a button, every pixel of a drag -- and the
  /// settings panel is twenty or thirty text fields; laying those out for a
  /// change they do not show is most of what made clicking around feel slow.
  ///
  /// Safe by default, and that is the whole design: every notification moves
  /// this unless it is one of the handful that deliberately does not, so a
  /// field added later and forgotten costs a rebuild nobody needed rather
  /// than leaving a panel showing something that is no longer true.
  int get revision => _revision;
  int _revision = 0;

  /// _viewOnly is set only while [_notifyView] is running.
  bool _viewOnly = false;

  @override
  void notifyListeners() {
    // A drawing is edited only while it is there and is the one thing
    // selected. Whatever took that away -- an undo, a delete, a click on
    // the background, a selection pruned -- ends the editing, rather than
    // leaving its points drawn beside another element's settings.
    var editing = _vectorEditing;
    if (editing != null &&
        (_backgroundSelected ||
            _selection.length != 1 ||
            _selection.first != editing ||
            _document.elementById(editing) is! VectorElement)) {
      _vectorEditing = null;
      _resetVectorEditing();
    }
    _keepDrawingProxy();
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
    if (!_viewOnly) _revision++;
    super.notifyListeners();
  }

  /// arrived says something the settings draw from has finished loading --
  /// a model their tiles show -- so they are drawn again with it.
  void arrived() => notifyListeners();

  /// restoreFit puts back the frame the reader last chose, without telling
  /// anybody.
  ///
  /// Called from a State's initState, before this screen has built anything,
  /// which is exactly why it must not notify: the controller is handed round
  /// by a Provider, and notifying one during a build marks an inherited widget
  /// dirty while the framework is already building. Flutter catches that and
  /// throws -- and building the exception captures a stack four hundred frames
  /// deep, every time the page is opened, which is a visible stutter for a
  /// setting nobody has to be told about. Nothing has painted yet, so the
  /// first build reads the new value anyway.
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
    // Changing what "all of it" means invalidates a zoom that was chosen
    // against the old frame: a 3x zoom on a whole-canvas frame is a very
    // different amount of magnification once the frame is four times the size.
    _zoom = 1;
    _pan = const Offset2(0, 0);
    _notifyView();
  }

  bool _autoKeyframe = false;

  /// autoKeyframe makes every move record itself.
  ///
  /// With it on, dragging anything while the playhead is on frame N writes a
  /// keyframe at frame N instead of moving the thing. That is how an animation
  /// is actually built: park the playhead, drag one player, move the playhead,
  /// drag the next -- rather than pressing Add keyframe before and after every
  /// single movement and hoping the two ends were captured.
  ///
  /// Off by default, because with it on a document cannot be tidied up without
  /// recording the tidying.
  bool get autoKeyframe => _autoKeyframe;

  set autoKeyframe(bool value) {
    if (_autoKeyframe == value) return;
    _autoKeyframe = value;
    notifyListeners();
  }

  bool _showOverspill = false;

  /// showOverspill draws a margin of the world outside the canvas.
  ///
  /// Off by default, because what the canvas shows is what gets published and
  /// a permanent border of not-the-design around it is a border around every
  /// glance at the work.
  ///
  /// On, it is what makes an entrance possible to build. An element animated
  /// in from off the left starts outside the page, where it is clipped away
  /// entirely -- so its first keyframe cannot be seen, cannot be selected and
  /// cannot be dragged, and the only way to place it was to type coordinates
  /// and scrub until it appeared.
  bool get showOverspill => _showOverspill;

  set showOverspill(bool value) {
    if (_showOverspill == value) return;
    _showOverspill = value;
    notifyListeners();
  }

  bool _showHelpers = true;

  /// showHelpers is whether the editing furniture is drawn: the box around the
  /// selection, the resize handles and the rotation ring.
  ///
  /// On by default -- without it there is no way to resize or rotate anything.
  /// Turned off to see the design as it will actually be published, which
  /// matters most on the work this tool is for: a pitch of twenty-two dots
  /// with a box and eight handles over one of them is a picture of an editor,
  /// not a picture of a formation.
  ///
  /// It hides the handles from the pointer as well as from the eye. A handle
  /// that can be grabbed where nothing is drawn is a click that appears to do
  /// nothing and then resizes something.
  bool get showHelpers => _showHelpers;

  set showHelpers(bool value) {
    if (_showHelpers == value) return;
    _showHelpers = value;
    _notifyView();
  }

  bool _showAllBounds = false;

  /// showAllBounds outlines every element on the canvas, not only the selected
  /// one.
  ///
  /// Editing furniture like the handles, and off by default: a canvas covered
  /// in outlines is a canvas nobody can see. What it is for is working on
  /// elements that have something to do with each other -- a chain of text
  /// boxes above all, where the box being flowed into is somewhere else on
  /// the page and invisible until it is clicked.
  ///
  /// One switch for the whole canvas rather than one per element, which is
  /// what this was: turning them on to line two boxes up meant turning them
  /// off again afterwards, one element at a time.
  bool get showAllBounds => _showAllBounds;

  set showAllBounds(bool value) {
    if (_showAllBounds == value) return;
    _showAllBounds = value;
    _notifyView();
  }

  bool _lockJoins = false;

  /// lockJoins keeps the connectors between text boxes from being changed by
  /// a drag.
  ///
  /// A connector is structural -- the words in several boxes depend on it --
  /// and it is dragged from a dot eight pixels across sitting on the same
  /// outline as the resize handles. Locked, the grips are still drawn, since
  /// they are how a chain is read; they simply do not answer the pointer.
  bool get lockJoins => _lockJoins;

  set lockJoins(bool value) {
    if (_lockJoins == value) return;
    _lockJoins = value;
    _notifyView();
  }

  bool _hideJoins = false;

  /// hideJoins leaves the lines between linked text boxes undrawn.
  ///
  /// The grips stay, and that is the point: the blue and the red dots still
  /// say there is a chain and whether the words all fit, while the lines stop
  /// crossing the design.
  bool get hideJoins => _hideJoins;

  set hideJoins(bool value) {
    if (_hideJoins == value) return;
    _hideJoins = value;
    _notifyView();
  }

  int? _focusedPlayer;

  /// focusedPlayer is which player of the selected team the timeline is about.
  ///
  /// A player is not an element -- it has no id and cannot be selected -- but
  /// it does have its own keyframes, so something has to say which player the
  /// keyframe controls are pointed at. Set by clicking one on the canvas, and
  /// cleared whenever the selection changes, since a player of a team that is
  /// no longer selected is not being edited by anything.
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
  /// out rather than moving things about.
  ///
  /// A mode rather than a modifier key, because retouching is a job somebody
  /// settles into for a minute at a time: a dozen strokes back and forth, each
  /// one wanting both hands free.
  RetouchBrush get retouch => _retouch;

  set retouch(RetouchBrush value) {
    if (_retouch == value) return;
    _retouch = value;
    notifyListeners();
  }

  /// _pendingStroke is a stroke that has been drawn but not yet applied, and
  /// _pendingPicture is the picture it was drawn on.
  ///
  /// A stroke used to land the moment the pointer came up, taking the brush's
  /// settings with it -- so changing hardness or cling afterwards did nothing
  /// at all to the stroke that had just been made, and the only way to try a
  /// setting was to undo, change it, and draw again. Held here instead, the
  /// same stroke is redrawn against whatever the settings currently say and
  /// applied when the reader is satisfied.
  List<Offset>? _pendingStroke;
  String? _pendingPicture;

  /// pendingKeeps and pendingTeaches are what the brush was doing when the
  /// stroke was drawn -- which of the four brushes it came from. Kept with the
  /// stroke rather than read live, because changing brush is choosing to do
  /// something else rather than to adjust this.
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
  /// to it.
  ///
  /// The number cling wants is "how different from the background does a pixel
  /// have to be before it is not the background", and that is not something
  /// anybody can read off a photograph -- so setting it by hand was always
  /// guessing, which is why it never worked. The picture knows it: the stroke
  /// crossed from one thing to another, and the two show up as two clusters of
  /// colour distance with a gap between them. See suggestSnap.
  ///
  /// Returns false when there is no edge to find -- a stroke drawn entirely on
  /// the background has one cluster, and inventing a split in it would cut the
  /// background in half for no reason.
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

  /// _clingFor is how much a stroke should cling, which is not always what the
  /// setting says.
  ///
  /// Never for a hint, which is a sample rather than a mark on the picture and
  /// has to be taken exactly where it was drawn.
  ///
  /// And never for putting something back. Clinging means "spread only through
  /// pixels like the one I started on", which is how you find the edge of a
  /// background -- but what is being put back is the subject, and a subject is
  /// every colour there is. With it on, a stroke over a face brought back the
  /// few pixels nearest whatever was under the pointer and left the rest, so
  /// the brush appeared to do nothing at all.
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

  /// _brushSnap starts at nothing.
  ///
  /// A plain brush does what it is told, which is the behaviour to have by
  /// default; clinging is an aid for following an edge quickly and is worth
  /// reaching for deliberately. On by default it made the brush look broken,
  /// because a stroke that refused most of what it covered is indistinguishable
  /// from one that did not work.
  bool _cutInside = false;

  /// cutInside takes what a boundary encloses rather than what surrounds it.
  ///
  /// Read when the stroke is applied rather than when it is drawn, so it can
  /// be turned over while the stroke is held and the preview redraws -- which
  /// is the point of holding one.
  bool get cutInside => _cutInside;

  set cutInside(bool value) {
    if (_cutInside == value) return;
    _cutInside = value;
    notifyListeners();
  }

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
  /// side, which is how a stroke is stored -- so the brush stays the same size
  /// relative to the picture however far the canvas is zoomed.
  double get brushSize => _brushSize;

  set brushSize(double value) {
    var next = value.clamp(0.005, 0.6);
    if (next == _brushSize) return;
    _brushSize = next;
    notifyListeners();
  }

  CanvasTool _tool = CanvasTool.select;

  /// tool is what dragging on the canvas does. Select to begin with, because
  /// that is what somebody who has just added an element wants to do to it.
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

  bool _opened = false;

  /// opened is whether this session has ever been shown.
  ///
  /// The session outlives the page now, so the page needs to tell its first
  /// visit from its second: on the first it restores whatever was last saved,
  /// and on every one after that the controller already holds the work in
  /// progress and restoring would throw it away.
  bool get opened => _opened;

  /// markOpened is called by the page as it builds.
  void markOpened() => _opened = true;

  /// folder and name are where this document is saved, or null when it has
  /// never been saved. Save writes back to them; Save As changes them.
  String? folder;
  String? name;

  bool _dirty = false;

  /// dirty is whether there are changes the file on disk does not have.
  ///
  /// Set by [apply] rather than by comparing documents, because comparing two
  /// documents deeply on every keystroke is expensive and because an edit that
  /// happens to restore the saved state is still an edit somebody may want to
  /// keep.
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
  /// What the settings bar asks, since it shows one element's controls.
  CanvasElement? get selected =>
      _selection.length == 1 ? _document.elementById(_selection.first) : null;

  // ------------------------------------------------------------------------
  // Editing
  // ------------------------------------------------------------------------

  /// apply replaces the document, pushing the old one onto the undo history.
  ///
  /// [transient] skips the history, for the many small changes inside one
  /// gesture. The gesture's own first document was already remembered by
  /// [beginInteraction], so nothing is lost.
  void apply(CanvasDocument next, {bool transient = false}) {
    _endPreview();
    if (identical(next, _document)) return;

    // A picture's frame takes in what was put past it -- once a change is
    // made, not at every step of a drag, whose sums start from where things
    // were when it began. See endInteraction, and changePaint, which grows
    // it as the stroke goes.
    if (!transient) next = _imagesGrown(next, _document);

    var was = _document;
    if (!transient && _interaction == null) {
      _undo.add(_document);
      if (_undo.length > _maxUndo) _undo.removeAt(0);
      _redo.clear();
    }

    next = _drawnOnCharacter(next);
    _document = next;
    _dirty = true;
    scheduleAutosave();

    // A selection can outlive the elements it names -- deleting, or loading a
    // different document -- and every reader of the selection would then have
    // to cope with an id that resolves to nothing. Pruning here means none of
    // them do.
    _selection = _selection.where((id) => _document.indexOf(id) >= 0).toSet();

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

  /// interacting is whether a gesture is under way -- a drag on the canvas,
  /// a number being scrubbed -- which the canvas draws a little faster for.
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
      _dirty = true;
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
    if (_undo.isEmpty) return;
    _redo.add(_document);
    var before = _document;
    _document = _undo.removeLast();
    _dirty = true;
    scheduleAutosave();
    _selection = _selection.where((id) => _document.indexOf(id) >= 0).toSet();
    if (_frame >= _document.frames) _frame = _document.frames - 1;
    _followEdits(before);
    notifyListeners();
  }

  void redo() {
    _endPreview();
    if (_redo.isEmpty) return;
    _undo.add(_document);
    var before = _document;
    _document = _redo.removeLast();
    _dirty = true;
    scheduleAutosave();
    _selection = _selection.where((id) => _document.indexOf(id) >= 0).toSet();
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
  /// and gone with a null -- or with the next real edit, which starts from the
  /// document as it really is. For a list being looked through, each option
  /// seen on the canvas before one is chosen.
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
  /// start where the playhead is and its finish two seconds on -- or the two
  /// seconds before the end, when the playhead is too near it. Without them
  /// From and To would do nothing until both were pinned by hand, and a
  /// counter that sits still reads as one that is broken.
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

  /// replaceElement is the commonest edit there is: one element changed.
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
    // A rig's point or a face's feature picked goes before anything else.
    if (deleteRigPoint() || putFacePointBack() || deleteHairStroke()) return;
    // While a drawing is being edited, Delete takes out the points picked,
    // or the shape picked -- and with neither, nothing: never the drawing.
    if (editingVector != null) {
      deleteVectorPoint();
      return;
    }
    if (_selection.isEmpty && _offCanvas.isEmpty) return;
    var next = _document;
    for (var id in _selection) {
      next = next.removeElement(id);
    }
    // And the clips picked on the timeline from another canvas -- another
    // scene's, or the master's -- which are as much on the timeline as this
    // scene's and were left behind, so a clip could be seen and picked and
    // not deleted until somebody worked out which scene it was on.
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

  /// placeTimedClip puts [e]'s [clip] at frame [run] of the whole run.
  ///
  /// A clip on a scene goes to the scene [run] falls in: dragged past the
  /// end of its own, it is now the next one's, rather than stopping at the
  /// edge of a scene the reader may not know it was on. A clip on the master
  /// goes where it is put; one on the backdrop as it always was.
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
  /// is visibly a second thing rather than sitting exactly on the original.
  void duplicateSelected() {
    if (_selection.isEmpty) return;
    var next = _document;
    var made = <String>{};
    for (var element in selectedElements) {
      var copy = element
          .withId(newElementId())
          .withBase(x: element.x + 24, y: element.y + 24);
      next = next.addElement(copy);
      made.add(copy.id);
    }
    apply(next);
    _selection = made;
    notifyListeners();
  }

  /// _clipboard is what was last copied.
  ///
  /// Held on the controller rather than in the system clipboard, and only for
  /// as long as the app runs. A canvas element is a tree of colours, specs and
  /// keyframes with no sensible text form, and putting JSON on the system
  /// clipboard would mean every Cmd-C in the editor quietly replacing whatever
  /// the reader had copied from somewhere else.
  ///
  /// Static, so a copy survives the page being left and come back to -- which
  /// is the same reason the session itself outlives the screen.
  static List<CanvasElement> _clipboard = const [];

  /// _pasteOffset is how far each paste is stepped down and right.
  ///
  /// Offset rather than placed exactly on top: an element pasted onto its
  /// original is indistinguishable from nothing having happened, and the
  /// second paste of the same thing has to be visibly a third copy.
  static const double _pasteOffset = 16;

  bool get canPaste => _clipboard.isNotEmpty;

  /// copySelected puts the selection on the clipboard -- and the clips
  /// picked on the timeline from another canvas with it: the master's music,
  /// clicked from a scene, is not in the selection, and copying it copied
  /// nothing.
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

  /// paste drops the clipboard onto the canvas and selects what it added.
  ///
  /// New ids, always. Pasting keeps the elements' order relative to each
  /// other and puts the whole lot on top, which is what pasting anywhere else
  /// does and what makes a pasted group findable.
  void paste() {
    if (_clipboard.isEmpty) return;
    var next = _document;
    var made = <String>{};
    var elsewhere = <String>{};
    for (var element in _clipboard) {
      CanvasElement copy;
      var timed = (element is AudioElement && element.clip.timed) ||
          (element is VideoElement && element.clip.timed);
      // A clip from the master, copied from a scene, goes back onto the
      // master beside the one copied, at the playhead on its clock: the
      // master runs on the whole run's. One from another scene comes here,
      // to the scene the playhead is in -- sent back to its own, at a frame
      // past that scene's end, it was a copy that never played.
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
      next = next.addElement(copy);
    }
    apply(next);
    _backgroundSelected = false;
    _focusedPlayer = null;
    _selection = made;
    // Picked where they went, as a click on them would pick them.
    _offCanvas = elsewhere;
    notifyListeners();
  }

  /// duplicateElement is the layer list's button: copy and paste in one press.
  ///
  /// The row's control was a copy, which did nothing anybody could see -- the
  /// canvas was unchanged and the only evidence was that a paste somewhere
  /// else would now produce this. What the button is actually reached for is a
  /// second one of these, so it makes one.
  ///
  /// The clipboard is deliberately left alone. Duplicating a layer is not a
  /// reason to lose whatever was copied to paste onto another canvas.
  void duplicateElement(String id) {
    var element = _document.elementById(id);
    if (element == null) return;
    var copy = element
        .withId(newElementId())
        .withBase(x: element.x + _pasteOffset, y: element.y + _pasteOffset);
    apply(_document.addElement(copy));
    _backgroundSelected = false;
    _focusedPlayer = null;
    _selection = {copy.id};
    notifyListeners();
  }

  /// nudgeSelected moves everything chosen, which is what the arrow keys do.
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

  /// alignSelected lines every chosen element up on one edge or middle.
  ///
  /// Against the whole selection's own box rather than against the canvas: two
  /// things picked out and aligned left means "put these two at the same
  /// left", and which left is the leftmost of the two. Aligning to the canvas
  /// is what the guides and the snapping are for, and doing both from one
  /// button would make the result depend on how many things were chosen.
  ///
  /// One element chosen is a no-op rather than a jump to the canvas edge --
  /// its own box is itself, so it is already aligned with it. The buttons say
  /// so by being dead until there are two.
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

  /// spreadSelected puts an even gap between the chosen elements.
  ///
  /// The two on the ends stay where they are and everything between them is
  /// moved, which is what makes this "spread these out" rather than "move
  /// everything". Needs three: with two there is nothing between them to
  /// space.
  ///
  /// Even *gaps* rather than even centres. Elements of different sizes spaced
  /// by their centres leave visibly different amounts of white between them,
  /// which is the thing anybody doing this is actually looking at.
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
  /// This is the difference between "put this somewhere else" and "from here,
  /// go there", and getting it wrong is what made animation appear not to work
  /// at all. A keyframe's dx and dy are offsets from the element's *resting*
  /// position, so moving the resting position moves every keyframe with it: a
  /// pose captured at frame 1, a drag at frame 20 and a second pose captured
  /// there recorded two identical offsets of zero, and the element sat
  /// motionless in its new place. Nothing was broken; the drag had answered a
  /// different question from the one being asked.
  ///
  /// So a drag poses when the document is animated and either auto-keyframe is
  /// on, or the element has already been *posed* -- something that has been
  /// animated in space is being posed, not repositioned. To relocate an
  /// animated element wholesale, the X and Y fields in its settings still move
  /// the resting position, and the whole animation travels with it.
  ///
  /// Posed, rather than merely having keyframes. The two are not the same and
  /// the difference was a reported bug: applying one of the chart animation
  /// presets lays two keyframes that say nothing but how much of the chart has
  /// been drawn, and after that every drag of the chart wrote a move keyframe
  /// at the playhead -- with auto-keyframe switched off, which is precisely
  /// the setting that is supposed to mean "do not do that". A chart told how
  /// to arrive has not been animated in space, so dragging it moves it.
  bool posesRatherThanMoves(CanvasElement element) =>
      _document.isAnimated &&
      // Never for something a path is driving. Its poses belong to the route,
      // and one written by a drag would be overwritten the next time a point
      // moved -- so a drag moves where it starts from instead, and the whole
      // run travels with it.
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
  ///
  /// An absolute target rather than a delta, so a drag stays exact over its
  /// whole length. Accumulating deltas drifts, and on a pose it would compound
  /// into the keyframe -- a slow drag and a fast one would end up in different
  /// places.
  CanvasElement movedTo(CanvasElement element, Offset topLeft) {
    // A character standing on a stage is moved across its floor: to the
    // spot under where its feet have been dragged to.
    if (element is CharacterElement && element.onStage != null) {
      var at = stagingIn(_document, element, _frame);
      var stage = stageOf(element.onStage!.stage);
      if (at != null && stage != null) {
        var feet = topLeft + Offset(at.box.width / 2, at.box.height);
        var spot = stageView(stage, _frame).toFloor(feet);
        if (spot == null) return element;
        return element.copyWith(
            onStage: element.onStage!.copyWith(x: spot.dx, z: spot.dy));
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

  /// pathDriving is the path that owns [elementId]'s keyframes, if one does.
  ///
  /// A followed element's track is not its own: it is written by the path and
  /// rewritten whenever the route or its timing changes, so anything the
  /// reader put there by hand would vanish the next time a point moved. Rather
  /// than let them make edits that quietly disappear, the timeline refuses --
  /// it shows the path's points instead, and says where to go.
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
  /// Baked rather than evaluated live, and that is the design. The renderer,
  /// the GIF encoder and a published interactive canvas all already know how
  /// to play a track; none of them needs to learn what a bezier is, and a
  /// document exported on one machine cannot disagree with the same document
  /// replayed on another. The cost is that the follower's own keyframes are
  /// owned by the path and rewritten whenever it changes, which is why the
  /// settings say so.
  ///
  /// One keyframe per frame between the first node and the last, sampled along
  /// the curve by arc length -- see PathElement.positionOnSegment on why by
  /// length rather than by the curve's parameter. Straight lines between the
  /// nodes would be cheaper and would not be a curve.
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
      // pitch's own metres, so a player or the ball sent along a curve
      // follows the curve as it is drawn however the pitch is seen.
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

    // An element is placed by its top-left, so the route -- which describes
    // where the thing *is* -- is measured from its centre and the offset
    // shifted back. Without that a player following a curve runs with the
    // curve passing through his shoulder.
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

  /// clearPathFollow takes the baked keyframes back off, which is what
  /// unlinking a follower has to do -- leaving them would strand the element
  /// on a route it is no longer attached to.
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

  /// hasValueKey is whether [channel] is pinned on this exact frame, which is
  /// what its little diamond shows.
  bool hasValueKey(CanvasElement element, String channel) =>
      element.track?.keyAt(_frame)?.values.containsKey(channel) ?? false;

  /// setValueKey pins one extra property at the current frame.
  ///
  /// Seeded at the start like every other first keyframe, so one press makes a
  /// movement rather than a value that holds for the whole document -- see
  /// ElementTrack.seededFor.
  ///
  /// [seed] is what turns that off, and a counter turns it off. The seed is a
  /// *resting pose* laid at frame 0, and a resting pose laid deliberately is
  /// the clearest way of saying "this element is animated in space" -- see
  /// ElementTrack.posesAnything. That is true of a chart told how much of
  /// itself to draw, and false of a number told what to say: pinning a count
  /// lit the position-size-angle-fade diamond and made every later drag write
  /// a pose, neither of which anybody had asked for. A count needs no seed
  /// anyway, because the first key already holds for every frame before it.
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
    // And with it whatever it was half of: an arrival is a pair, and one of
    // them on its own is not half an arrival. See withoutHalfAnimations.
    replaceElement(withoutHalfAnimations(element, next));
  }

  /// setCharacterPose stands [e] in [pose]: its stance, until any part of
  /// its performance has been keyed, and from then on this frame's
  /// keyframe -- the same rule a drag follows, where moving an element is a
  /// move until it has been animated and a pose after. See
  /// CharacterElement.posedOnTimeline.
  void setCharacterPose(CharacterElement e, CharacterPose pose,
          {bool transient = false}) =>
      replaceElement(characterPosed(e, pose), transient: transient);

  /// characterPosed is [e] stood in [pose] as setCharacterPose would stand
  /// it, without applying it -- for the settings panel, which writes its
  /// own changes.
  CharacterElement characterPosed(CharacterElement e, CharacterPose pose) =>
      e.posedOnTimeline
          ? e.withBase(track: _pinnedAt(e.track!, _frame, pose.channels))
              as CharacterElement
          : e.copyWith(pose: pose);

  /// characterFaced is [e] with its face set to [face], by the same rule
  /// as characterPosed.
  CharacterElement characterFaced(CharacterElement e, CharacterFace face) =>
      e.posedOnTimeline
          ? e.withBase(track: _pinnedAt(e.track!, _frame, face.channels))
              as CharacterElement
          : e.copyWith(face: face);

  /// keyCharacterPose keys the character as it is on this frame, pose and
  /// face, which is how a character starts to move: how it stands is keyed
  /// at the start as well the first time, so the pose is arrived at rather
  /// than held from the first frame.
  void keyCharacterPose(CharacterElement e,
      [CharacterPose? pose, CharacterFace? face]) {
    var track = e.track ?? ElementTrack.empty;
    if (!e.posedOnTimeline && _frame != 0) {
      track = _pinnedAt(track, 0, {...e.pose.channels, ...e.face.channels});
    }
    replaceElement(e.withBase(
        track: _pinnedAt(track, _frame, {
      ...(pose ?? e.poseAtFrame(_frame)).channels,
      ...(face ?? e.faceAtFrame(_frame)).channels,
    })));
  }

  /// characterMouthed is [e] with its mouth set to [shape] here: a mouth
  /// key on this frame once it has any -- lip synced or posed -- and its
  /// stance otherwise.
  CharacterElement characterMouthed(CharacterElement e, MouthShape shape) {
    if (e.mouthKeys.isEmpty && !e.posedOnTimeline) {
      return e.copyWith(face: e.face.withMouth(shape));
    }
    return e.withBase(
        track: _pinnedAt(e.track ?? ElementTrack.empty, _frame,
            {mouthChannel: shape.index.toDouble()})) as CharacterElement;
  }

  /// lipSync gives [e] the mouths for what is said on [voice]: from the
  /// words, heard first if they have not been, or with [words] off from the
  /// loudness alone. Mouths it laid before over the same stretch are
  /// replaced; the rest of the character's keys are left as they are. One
  /// undo step. Says what stopped it, or how many mouths it laid.
  Future<({String? problem, int mouths})> lipSync(
      CharacterElement e, AudioElement voice,
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
      // A take the Speech device spoke knows its words, each to the
      // moment: read from it, rather than heard again.
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
      // A hundred readings a second: the timeline's own waveform is spread
      // over the whole file, too thin for a mouth on a long recording.
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
    if (now is! CharacterElement) return (problem: null, mouths: 0);
    var local = [
      for (var k in keys)
        if (k.frame - mine >= 0) (frame: k.frame - mine, shape: k.shape),
    ];
    replaceElement(now.withMouths(local,
        from: math.max(0, voiceAt - mine - feel.lead - 1),
        to: voiceEnd - mine + 1));
    return (problem: null, mouths: local.length);
  }

  /// _takeWords are the words of [voice] where it is a Speech device's take
  /// -- the take its sound is, kept with its timing -- as run frames from
  /// [voiceAt]; only those its trim keeps. Null for any other sound.
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

  /// clearLipSync takes every mouth off [e]'s track.
  void clearLipSync(CharacterElement e) =>
      replaceElement(e.withMouths(const []));

  /// recordPins is whether dragging a character's pins while the scene
  /// plays records the movement: a pose keyed on each frame the drag passes
  /// through. Off, a drag poses the character where the playhead is.
  bool get recordPins => _recordPins;
  bool _recordPins = false;
  set recordPins(bool on) {
    if (_recordPins == on) return;
    _recordPins = on;
    notifyListeners();
  }

  /// recordCharacterPose keys [pose] on this frame as part of a recording:
  /// the stance keyed at the start the first time, as keyCharacterPose does,
  /// and only the bones -- the face is left to its own keys.
  void recordCharacterPose(CharacterElement e, CharacterPose pose,
      {bool transient = false}) {
    var track = e.track ?? ElementTrack.empty;
    if (!e.posedOnTimeline && _frame != 0) {
      track = _pinnedAt(track, 0, e.pose.channels);
    }
    replaceElement(e.withBase(track: _pinnedAt(track, _frame, pose.channels)),
        transient: transient);
  }

  /// importMotion lays [poses] on [e] as keyframes, one a frame from this
  /// one -- motion capture, read from a BVH file. With [faceReader] the
  /// whole of it is turned so that it starts facing the reader, whichever
  /// way the capture was facing. One undo step. Says how many frames it
  /// laid, which is fewer than it was given where the canvas ends first.
  int importMotion(CharacterElement e, List<CharacterPose> poses,
      {bool faceReader = true}) {
    if (poses.isEmpty) return 0;
    var by = faceReader ? -poses.first.turn : 0.0;
    var track = e.track ?? ElementTrack.empty;
    if (!e.posedOnTimeline && _frame != 0) {
      track = _pinnedAt(track, 0, e.pose.channels);
    }
    var laid = 0;
    for (var (i, p) in poses.indexed) {
      var f = _frame + i;
      if (f >= _document.frames) break;
      track = _pinnedAt(track, f, p.withTurn(p.turn + by).channels);
      laid++;
    }
    replaceElement(e.withBase(track: track));
    return laid;
  }

  /// stageFilmed is [stage] with its camera set to [camera]: its own setting
  /// until the camera has been keyed, and from then on this frame's key --
  /// the rule a character's pose follows.
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

  /// putStage writes [stage] back where it lives: onto the Background
  /// element it is drawn by, or the background behind the canvas -- its
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
  /// the scene, from where it is on the first frame to the last -- the
  /// commonest parallax shot there is, in one press.
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

  /// keyCamera keys [stage]'s camera as it is on this frame -- and on the
  /// first frame too, the first time, so the move starts from where the
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

  /// addMotion lays a clip of [kind] on [e] from this frame: a looping
  /// motion for two of its cycles or two seconds, whichever is longer, and
  /// one that plays once for its own length. Says which clip it made.
  MotionClip addMotion(CharacterElement e, MotionKind kind) {
    var rate = math.max(1, _document.frameRate);
    var seconds = kind.loops ? math.max(2.0, kind.seconds * 2) : kind.seconds;
    var clip = MotionClip(
        id: newElementId(),
        kind: kind,
        layer: kind.layer,
        start: _frame,
        length: math.max(2, (seconds * rate).round()));
    replaceElement(e.copyWith(motions: [...e.motions, clip]));
    return clip;
  }

  /// setMotion writes [clip] back over the clip of [e] with its id.
  void setMotion(CharacterElement e, MotionClip clip,
          {bool transient = false}) =>
      replaceElement(
          e.copyWith(motions: [
            for (var m in e.motions) m.id == clip.id ? clip : m,
          ]),
          transient: transient);

  void removeMotion(CharacterElement e, String id) =>
      replaceElement(e.copyWith(motions: [
        for (var m in e.motions)
          if (m.id != id) m,
      ]));

  /// walkAcross walks or runs [e] across the page for [seconds] from this
  /// frame, the way [direction] says -- -1 to the left, 1 to the right:
  /// it turns to face the way it is going, goes the distance its legs would
  /// take it, and turns back to the reader at the end. One undo step.
  void walkAcross(
      CharacterElement e, MotionKind kind, int direction, double seconds) {
    var rate = math.max(1, _document.frameRate);
    var frames = math.max(4, (seconds * rate).round());
    var start = _frame, end = _frame + frames;
    var turnFrames = math.min(4, frames ~/ 4);
    var clip = MotionClip(
        id: newElementId(),
        kind: kind,
        layer: MotionLayer.body,
        start: start,
        length: frames);
    var distance = kind.travels * e.height * seconds * direction;
    var facing = direction < 0 ? 90.0 : -90.0;
    var turnBack = e.poseAtFrame(start).turn;

    var track = e.track ?? ElementTrack.empty;
    // Where it is: from here, to the distance away. A key that is already
    // there keeps whatever else it says.
    var from = track.keyAt(start) ?? track.restingAt(start);
    var to = track.keyAt(end) ?? track.restingAt(end);
    track = track
        .withKey(from)
        .withKey(to.copyWith(dx: from.dx + distance, dy: from.dy));
    // Which way it faces: round to the side over the first few frames and
    // back to the reader over the last few.
    var posed = e.withBase(track: track) as CharacterElement;
    if (!posed.posedOnTimeline) {
      var stance = {...e.pose.channels, ...e.face.channels}
        ..remove(mouthChannel);
      track = _pinnedAt(track, start, stance);
    }
    track = _pinnedAt(track, start, {turnChannel: turnBack});
    track = _pinnedAt(track, start + turnFrames, {turnChannel: facing});
    track = _pinnedAt(track, end - turnFrames, {turnChannel: facing});
    track = _pinnedAt(track, end, {turnChannel: turnBack});
    replaceElement((e.withBase(track: track) as CharacterElement)
        .copyWith(motions: [...e.motions, clip]));
  }

  /// hasCharacterPoseKey is whether this frame has a pose or a face keyed
  /// on it.
  bool hasCharacterPoseKey(CharacterElement e) =>
      e.track?.keyAt(_frame)?.values.keys.any(posingChannel) ?? false;

  /// clearCharacterPoseKey takes the pose and the face off this frame's
  /// keyframe, and the keyframe with it when that was all it held.
  void clearCharacterPoseKey(CharacterElement e) {
    var track = e.track;
    var at = track?.keyAt(_frame);
    if (track == null || at == null) return;
    var without = at.copyWith(values: {
      for (var v in at.values.entries)
        if (!posingChannel(v.key)) v.key: v.value,
    });
    replaceElement(e.withBase(
        track: without.isRest && without.frame != 0
            ? track.withoutFrame(_frame)
            : track.withKey(without)));
  }

  /// clearElementKeyframes takes every keyframe off one element.
  void clearElementKeyframes(String id) {
    var element = _document.elementById(id);
    if (element == null || element.track == null) return;
    replaceElement(element.withBase(clearTrack: true));
  }

  /// clearPlayerKeyframes takes every keyframe off one player.
  void clearPlayerKeyframes(String teamId, int index) {
    var team = _document.elementById(teamId);
    if (team is! TeamElement || index < 0 || index >= team.players.length) {
      return;
    }
    if (team.players[index].track == null) return;
    replaceElement(
        team.withPlayer(index, team.players[index].copyWith(clearTrack: true)));
  }

  /// clearAllKeyframes takes the animation off the whole document.
  ///
  /// One undo step, deliberately: it is a single decision, and unpicking it
  /// element by element is not something anybody would want to do twenty-two
  /// times. See CanvasDocument.withoutKeyframes on what it leaves behind.
  void clearAllKeyframes() {
    if (!_document.hasKeyframes) return;
    apply(_document.withoutKeyframes());
  }

  /// removePlayerKeyframe drops one, and the track with it when it was the
  /// last -- so a player who no longer moves carries no empty track into the
  /// saved file.
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

  /// imageEditing is the picture whose layers are open for editing, by id,
  /// or null; imageLayer is the layer of it picked, which the tools and the
  /// settings work on. The base layer is picked when nothing else is.
  String? get imageEditing => _imageEditing;
  String? _imageEditing;
  String get imageLayer => _imageLayer;
  String _imageLayerId = baseLayerId;
  String get _imageLayer => _imageLayerId;

  /// Picking one layer is the ordinary case, and every way of doing it --
  /// a click, a new layer, a deletion -- lets go of any others picked with
  /// it. See pickImageLayer for picking several.
  set _imageLayer(String id) {
    _imageLayerId = id;
    _alsoPicked.clear();
  }

  /// _alsoPicked are the layers picked with [imageLayer], in the order they
  /// were picked: what the align tools line up and a drag moves together.
  /// The settings are the first one's.
  final List<String> _alsoPicked = [];

  /// imageLayers is every layer picked, the first one first.
  List<String> get imageLayers => [_imageLayerId, ..._alsoPicked];

  /// pickedLayers is those layers.
  List<ImageLayer> get pickedLayers {
    var e = editingImage;
    if (e == null) return const [];
    return [
      for (var id in imageLayers)
        if (e.layerById(id) case var l?) l
    ];
  }

  /// alignableLayers are the picked layers that have a place of their own
  /// in the frame to line up: picture layers, shown, and not locked. An
  /// adjustment or a texture covers the whole frame and has nowhere to move
  /// to.
  List<ImageLayer> get alignableLayers => [
        for (var l in pickedLayers)
          if (l.kind == LayerKind.picture && l.visible && !layerLocked(l)) l
      ];

  /// frameTool is the Frame section's tool open on its shelf, Image until
  /// another is picked; null with all of them shut.
  FrameTool? get frameTool => _frameTool;
  FrameTool? _frameTool = FrameTool.image;
  set frameTool(FrameTool? v) {
    _frameTool = v;
    notifyListeners();
  }

  /// _shutCards are the settings cards under a row of kinds -- an
  /// arrival's, an exit's, a loop's -- shut by pressing the kind chosen
  /// again. For this run of the app; picking another kind opens its card.
  final Set<String> _shutCards = {};

  /// cardShut is whether the card [key] has been shut -- see _shutCards.
  bool cardShut(String key) => _shutCards.contains(key);

  /// toggleCard shuts the card [key] if it is open, and opens it if shut.
  void toggleCard(String key) {
    if (!_shutCards.remove(key)) _shutCards.add(key);
    notifyListeners();
  }

  /// openCard opens the card [key], without a redraw of its own: it goes
  /// with the change that is about to be made.
  void openCard(String key) => _shutCards.remove(key);

  /// _textLayers is the layer picked in each text element's Layers, by the
  /// element's id: one of its pieces, by the piece's id. A text element not
  /// in here has its own words picked. For this run of the app.
  final Map<String, String> _textLayers = {};

  /// textLayer is the piece of [e] picked in its Layers, or null for its
  /// own words -- which is also what a piece since taken away comes back as.
  TextItem? textLayer(TextElement e) {
    var id = _textLayers[e.id];
    if (id == null) return null;
    for (var item in e.items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// pickTextLayer picks the piece [itemId] of the text element [elementId]
  /// in its Layers, or its own words with null.
  void pickTextLayer(String elementId, String? itemId) {
    if (_textLayers[elementId] == itemId) return;
    if (itemId == null) {
      _textLayers.remove(elementId);
    } else {
      _textLayers[elementId] = itemId;
    }
    notifyListeners();
  }

  /// positionTool is the Position section's tool open on its shelf, Place
  /// until another is picked; null with all of them shut. The Warp tool
  /// shows the picked picture's grid on the canvas while it is open.
  PositionTool? get positionTool => _positionTool;
  PositionTool? _positionTool = PositionTool.place;
  set positionTool(PositionTool? v) {
    _positionTool = v;
    notifyListeners();
  }

  /// warpLayer is the layer of the picture being edited whose warp grid is
  /// shown to be worked on -- see ImageWarp -- or null for none. Only while
  /// that layer is the one picked: picking another puts the grid away.
  String? get warpLayer {
    var e = editingImage, id = _warpLayer;
    if (e == null || id == null || id != _imageLayerId) return null;
    return e.layerById(id) == null ? null : id;
  }

  String? _warpLayer;

  /// warpPicks is the points of the warp grid picked, by their place in it.
  Set<int> get warpPicks => _warpPicks;
  Set<int> _warpPicks = const {};
  set warpPicks(Set<int> v) {
    _warpPicks = Set.unmodifiable(v);
    notifyListeners();
  }

  /// warpOf is the warp of the picture [layerId] of [e] shows.
  ImageWarp warpOf(ImageElement e, String layerId) =>
      lookOf(e, layerId)?.warp ?? const ImageWarp();

  /// editWarp shows the picked layer's warp grid to be worked on, opening
  /// the picture's layers on [layerId] where they are not open -- or, with
  /// [on] false, puts it away.
  void editWarp(String elementId, String layerId, {bool on = true}) {
    if (!on) {
      _warpLayer = null;
      _warpPicks = const {};
      // The Warp tool has nothing to show without its grid.
      if (_positionTool == PositionTool.warp) {
        _positionTool = PositionTool.place;
      }
      notifyListeners();
      return;
    }
    if (imageEditing != elementId || _imageLayerId != layerId) {
      editImage(elementId, layer: layerId);
    }
    _warpLayer = layerId;
    _warpPicks = const {};
    _positionTool = PositionTool.warp;
    imageTool = ImageTool.move;
    notifyListeners();
  }

  /// changeWarp changes the warp of the layer being warped.
  void changeWarp(ImageWarp Function(ImageWarp) edit,
      {bool transient = false}) {
    var e = editingImage, id = warpLayer;
    if (e == null || id == null) return;
    var look = lookOf(e, id);
    if (look == null) return;
    replaceElement(withLook(e, id, look.copyWith(warp: edit(look.warp))),
        transient: transient);
  }

  /// skewHandles is whether an element's side handles slant it rather than
  /// size it, without a key held -- for a touch screen, or a pen. A way of
  /// working, not part of the design: it is not saved.
  bool get skewHandles => _skewHandles;
  bool _skewHandles = false;
  set skewHandles(bool v) {
    if (v == _skewHandles) return;
    _skewHandles = v;
    notifyListeners();
  }

  /// imageSolo is whether only the picked layer of the picture being edited
  /// can be worked on, every other one held as if locked -- following the
  /// pick, so picking another layer in the list solos that one. A way of
  /// working, not part of the picture: it is not saved.
  bool get imageSolo => _imageSolo;
  bool _imageSolo = false;
  set imageSolo(bool v) {
    if (v == _imageSolo) return;
    _imageSolo = v;
    notifyListeners();
  }

  /// layerLocked is whether [layer] of the picture being edited is held
  /// where it is on the canvas: locked, or not the soloed one.
  bool layerLocked(ImageLayer layer) =>
      layer.locked || (_imageSolo && layer.id != _imageLayerId);

  /// aligning is how many things the align tools would line up: picked
  /// picture layers while a picture is open, elements otherwise.
  int get aligning =>
      editingImage != null ? alignableLayers.length : selection.length;

  ImageTool get imageTool => _imageTool;
  ImageTool _imageTool = ImageTool.move;
  set imageTool(ImageTool tool) {
    if (_imageTool == tool) return;
    _imageTool = tool;
    // The old removal brushes and the mask tools both paint on a press;
    // only one of them can have it.
    if (tool.masks) _retouch = RetouchBrush.off;
    notifyListeners();
  }

  /// editingImage is the picture being edited, where there is one.
  ImageElement? get editingImage {
    var id = _imageEditing;
    var e = id == null ? null : _document.elementById(id);
    return e is ImageElement ? e : null;
  }

  /// pickedLayer is the layer of the picture being edited that is picked.
  ImageLayer? get pickedLayer => editingImage?.layerById(_imageLayer);

  /// editImage opens the picture [id]'s layers, picking [layer]; null closes
  /// them. Edited is selected, as a drawing is -- see notifyListeners.
  void editImage(String? id, {String? layer}) {
    if (_imageEditing == id && layer == null) return;
    // Solo is a way of working on one picture; another, or none, starts
    // without it.
    if (_imageEditing != id) _imageSolo = false;
    _imageEditing = id;
    _imageLayer = layer ?? baseLayerId;
    if (id != null) {
      _selection = {id};
      _backgroundSelected = false;
      // A brush left in hand from before belongs to the base picture.
      if (_imageLayer != baseLayerId) _retouch = RetouchBrush.off;
    }
    notifyListeners();
  }

  /// pickImageLayer picks the layer [id] of the picture being edited --
  /// alone, or with [add] (Shift or Command held) as well as those picked
  /// already, or let go of again if it was.
  void pickImageLayer(String id, {bool add = false}) {
    if (add) {
      if (id == _imageLayerId) {
        if (_alsoPicked.isEmpty) return;
        _imageLayerId = _alsoPicked.removeAt(0);
      } else if (!_alsoPicked.remove(id)) {
        _alsoPicked.add(id);
      }
      notifyListeners();
      return;
    }
    if (_imageLayer == id && _alsoPicked.isEmpty) return;
    _imageLayer = id;
    // The removal brushes paint on the base picture, and only there.
    if (id != baseLayerId) _retouch = RetouchBrush.off;
    notifyListeners();
  }

  /// changeImage replaces the picture being edited, as one step unless
  /// [transient].
  void changeImage(ImageElement next, {bool transient = false}) =>
      replaceElement(next, transient: transient);

  /// addImageLayer puts [layer] in just above the one picked, and picks it.
  void addImageLayer(ImageLayer layer, {bool onTop = false}) {
    var e = editingImage;
    if (e == null) return;
    replaceElement(
        withLayerAdded(e, layer, above: onTop ? e.stack.last.id : _imageLayer));
    _imageLayer = layer.id;
    _retouch = RetouchBrush.off;
    notifyListeners();
  }

  /// removeImageLayer takes out the layer [id], picking the one under it.
  void removeImageLayer(String id) {
    var e = editingImage;
    if (e == null || id == baseLayerId) return;
    var at = e.stack.indexWhere((l) => l.id == id);
    if (at < 0) return;
    var next = withoutLayer(e, id);
    _imageLayer = next.stack[(at - 1).clamp(0, next.stack.length - 1)].id;
    replaceElement(next);
  }

  /// duplicateImageLayer copies the layer [id] and picks the copy.
  void duplicateImageLayer(String id) {
    var e = editingImage;
    if (e == null) return;
    var copied = withLayerCopied(e, id);
    if (copied == null) return;
    _imageLayer = copied.$2;
    replaceElement(copied.$1);
  }

  // ---- picture masks -----------------------------------------------------

  /// maskHide is whether the mask tools take the picture away (true) or put
  /// it back. X turns it over; Option held turns it over for one stroke.
  bool get maskHide => _maskHide;
  bool _maskHide = true;
  set maskHide(bool v) {
    if (_maskHide == v) return;
    _maskHide = v;
    notifyListeners();
  }

  /// maskBrushSize is the mask brush's radius, as a fraction of the
  /// picture's shorter side; maskHardness and maskStrength as a MaskMark's.
  double get maskBrushSize => _maskBrushSize;
  double _maskBrushSize = 0.03;
  set maskBrushSize(double v) {
    _maskBrushSize = v.clamp(0.001, 0.5);
    notifyListeners();
  }

  double get maskHardness => _maskHardness;
  double _maskHardness = 0.6;
  set maskHardness(double v) {
    _maskHardness = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  double get maskStrength => _maskStrength;
  double _maskStrength = 1;
  set maskStrength(double v) {
    _maskStrength = v.clamp(0.01, 1.0);
    notifyListeners();
  }

  /// maskRadial makes the gradient tool's fades spread from a middle.
  bool get maskRadial => _maskRadial;
  bool _maskRadial = false;
  set maskRadial(bool v) {
    _maskRadial = v;
    notifyListeners();
  }

  /// maskView is how the mask is shown while a mask tool is in hand.
  MaskView get maskView => _maskView;
  MaskView _maskView = MaskView.result;
  set maskView(MaskView v) {
    _maskView = v;
    notifyListeners();
  }

  /// maskBusy says what is being worked out, while finding a subject takes
  /// its moment; maskNote what the last attempt had to say, where it found
  /// nothing or failed.
  String? get maskBusy => _maskBusy;
  String? _maskBusy;
  String? get maskNote => _maskNote;
  String? _maskNote;

  /// changeMask changes the picked layer's mask by [edit], as one step
  /// unless [transient].
  void changeMask(ImageMask Function(ImageMask) edit,
      {bool transient = false}) {
    var e = editingImage;
    var picked = pickedLayer;
    // A frame-masked layer keeps its mask on itself.
    if (e != null && picked != null && picked.framed) {
      replaceElement(
          e.withLayer(picked.id, (l) => l.copyWith(mask: edit(l.mask))),
          transient: transient);
      return;
    }
    var look = e == null ? null : lookOf(e, _imageLayer);
    if (e == null || look == null) return;
    replaceElement(
        withLook(e, _imageLayer, look.copyWith(mask: edit(look.mask))),
        transient: transient);
  }

  /// findSubject finds the picked layer's subject -- every subject, or the
  /// one at [at], a fraction of its picture -- and puts it in the mask as
  /// [how] says.
  Future<void> findSubject(
      {Offset? at, MaskCombine how = MaskCombine.replace}) async {
    var e = editingImage;
    var layerId = _imageLayer;
    var look = e == null ? null : lookOf(e, layerId);
    if (e == null || look == null || !look.hasImage || _maskBusy != null) {
      return;
    }
    _maskBusy = "Finding the subject…";
    _maskNote = null;
    notifyListeners();
    try {
      // Without the operating system's own finder, a guess from colour and
      // edge -- rougher, and saying so.
      Uint8List? png;
      if (await SubjectFinder.available()) {
        png = await SubjectFinder.find(look.assetId, at: at);
      } else {
        var picture = images.original(look.assetId);
        if (picture != null) png = await guessSubjectMask(picture, at: at);
        _maskNote = "Found by colour and edge — finish it with Quick select "
            "or the brush";
      }
      if (png == null) {
        _maskNote = at == null
            ? "No subject could be found in this picture"
            : "No subject there — try a click on the person or thing itself";
        return;
      }
      var bytes = png;
      if (how != MaskCombine.replace) {
        var size = await _pictureSizeOf(look.assetId);
        var found = await decodeMask(png);
        var current = look.mask.subject.isEmpty
            ? null
            : await _maskImageOf(look.mask.subject);
        bytes = await combinedSubject(
                look.mask,
                current,
                found,
                size ?? Size(found.width.toDouble(), found.height.toDouble()),
                how) ??
            png;
      }
      var id = await CanvasAssets.saveMask(bytes);
      if (id == null) {
        _maskNote = "The subject could not be kept";
        return;
      }
      // Whatever has happened to the picture meanwhile, the mask goes on the
      // picture as it is now.
      var now = _document.elementById(e.id);
      var nowLook = now is ImageElement ? lookOf(now, layerId) : null;
      if (now is! ImageElement || nowLook == null) return;
      var mask = nowLook.mask.copyWith(
          subject: id,
          // A subject found afresh starts the mask afresh: marks made for
          // the last one would land on the wrong thing.
          marks: how == MaskCombine.replace ? const [] : null,
          on: true);
      replaceElement(withLook(now, layerId, nowLook.copyWith(mask: mask)));
    } catch (message) {
      _maskNote = "$message";
    } finally {
      _maskBusy = null;
      notifyListeners();
    }
  }

  /// quickSelect grows a quick-select stroke along [stroke] -- fractions
  /// of the picked layer's picture -- out to the edges near it and keeps
  /// what it finds, or, with [subtract], takes it away. The mask's marks are
  /// worked into its new subject.
  Future<void> quickSelect(List<Offset> stroke, {bool subtract = false}) async {
    var e = editingImage;
    var layerId = _imageLayer;
    var look = e == null ? null : lookOf(e, layerId);
    var picture = look == null ? null : images.original(look.assetId);
    if (e == null || look == null || picture == null || _maskBusy != null) {
      return;
    }
    _maskBusy = "Selecting…";
    _maskNote = null;
    notifyListeners();
    try {
      var subject = look.mask.subject.isEmpty
          ? null
          : await _maskImageOf(look.mask.subject);
      var png = await quickSelectMask(
          picture, look.mask, subject, stroke, _maskBrushSize,
          subtract: subtract);
      var id = png == null ? null : await CanvasAssets.saveMask(png);
      if (id == null) {
        _maskNote = "Nothing could be selected there";
        return;
      }
      var now = _document.elementById(e.id);
      var nowLook = now is ImageElement ? lookOf(now, layerId) : null;
      if (now is! ImageElement || nowLook == null) return;
      replaceElement(withLook(
          now,
          layerId,
          nowLook.copyWith(
              mask: nowLook.mask.copyWith(
                  subject: id, marks: const [], invert: false, on: true))));
    } catch (message) {
      _maskNote = "$message";
    } finally {
      _maskBusy = null;
      notifyListeners();
    }
  }

  /// refineEdge refines the picked layer's mask along [stroke], fractions of
  /// its picture: the edge under it given the alpha its colours say it has.
  Future<void> refineEdge(List<Offset> stroke) async {
    var e = editingImage;
    var layerId = _imageLayer;
    var look = e == null ? null : lookOf(e, layerId);
    var picture = look == null ? null : images.original(look.assetId);
    if (e == null || look == null || picture == null || _maskBusy != null) {
      return;
    }
    if (look.mask.empty) {
      _maskNote = "There is no edge to refine yet: find the subject first";
      notifyListeners();
      return;
    }
    _maskBusy = "Refining the edge…";
    _maskNote = null;
    notifyListeners();
    try {
      var subject = look.mask.subject.isEmpty
          ? null
          : await _maskImageOf(look.mask.subject);
      var png = await refineEdgeMask(
          picture, look.mask, subject, stroke, _maskBrushSize);
      var id = png == null ? null : await CanvasAssets.saveMask(png);
      if (id == null) return;
      var now = _document.elementById(e.id);
      var nowLook = now is ImageElement ? lookOf(now, layerId) : null;
      if (now is! ImageElement || nowLook == null) return;
      replaceElement(withLook(
          now,
          layerId,
          nowLook.copyWith(
              mask: nowLook.mask.copyWith(
                  subject: id, marks: const [], invert: false, on: true))));
    } catch (message) {
      _maskNote = "$message";
    } finally {
      _maskBusy = null;
      notifyListeners();
    }
  }

  /// _maskImageOf is the stored mask [id], decoded.
  Future<ui.Image?> _maskImageOf(String id) async {
    var held = images.resolve(id, const BackgroundRemoval());
    if (held != null) return held;
    var path = await CanvasAssets.pathOf(id);
    if (path == null) return null;
    return decodeMask(await File(path).readAsBytes());
  }

  /// _pictureSizeOf is the picture [id]'s size in pixels.
  Future<Size?> _pictureSizeOf(String id) async {
    var held = images.original(id);
    if (held != null) {
      return Size(held.width.toDouble(), held.height.toDouble());
    }
    return pictureSize(id);
  }

  // ---- brushwork ----------------------------------------------------------

  /// paintColour, paintSize (a fraction of the frame's or the picture's
  /// shorter side), paintHardness and paintStrength are the paint and
  /// retouching brushes' settings, shared between them.
  Color get paintColour => _paintColour;
  Color _paintColour = const Color(0xFFF2B33D);
  set paintColour(Color c) {
    _paintColour = c;
    notifyListeners();
  }

  double get paintSize => _paintSize;
  double _paintSize = 0.02;
  set paintSize(double v) {
    _paintSize = v.clamp(0.001, 0.5);
    notifyListeners();
  }

  double get paintHardness => _paintHardness;
  double _paintHardness = 0.6;
  set paintHardness(double v) {
    _paintHardness = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  double get paintStrength => _paintStrength;
  double _paintStrength = 1;
  set paintStrength(double v) {
    _paintStrength = v.clamp(0.01, 1.0);
    notifyListeners();
  }

  /// paintTip is the paint brush's shape and how the pen drives it -- see
  /// BrushTip -- and paintBrush the brush it was last taken from, by id, or
  /// "" once anything about it has been changed by hand.
  BrushTip get paintTip => _paintTip;
  BrushTip _paintTip = const BrushTip();
  set paintTip(BrushTip v) {
    _paintTip = v;
    _paintBrush = "";
    notifyListeners();
  }

  String get paintBrush => _paintBrush;
  String _paintBrush = "round";

  /// useBrush takes everything about the paint brush from [brush].
  void useBrush(BrushPreset brush) {
    _paintSize = brush.size;
    _paintHardness = brush.hardness;
    _paintStrength = brush.strength;
    _paintTip = brush.tip;
    _paintBrush = brush.id;
    notifyListeners();
  }

  /// currentBrush is the paint brush as it is set now, as a preset that can
  /// be kept under [name].
  BrushPreset currentBrush(String name) => BrushPreset("", name,
      size: _paintSize,
      hardness: _paintHardness,
      strength: _paintStrength,
      tip: _paintTip);

  /// burning makes the dodge tool burn, as Option held does for a stroke.
  bool get burning => _burning;
  bool _burning = false;
  set burning(bool v) {
    _burning = v;
    notifyListeners();
  }

  /// cloneFrom is where the clone tool copies from, a fraction of the
  /// picked picture, chosen with Option-click; cloneOffset how far that is
  /// from where the first stroke after it started -- kept for the strokes
  /// after, so they go on copying from the same place relative to them.
  Offset? get cloneFrom => _cloneFrom;
  Offset? _cloneFrom;
  Offset? cloneOffset;
  set cloneFrom(Offset? at) {
    _cloneFrom = at;
    cloneOffset = null;
    _maskNote = null;
    notifyListeners();
  }

  /// retouchWholeFrame is whether the retouching brushes work on everything
  /// in the frame -- every layer, as one picture -- rather than on the
  /// picture picked. Strokes made so go on a paint layer of their own, over
  /// the layer picked: see retouchesFrame.
  bool get retouchWholeFrame => _retouchWholeFrame;
  bool _retouchWholeFrame = false;
  set retouchWholeFrame(bool v) {
    if (v == _retouchWholeFrame) return;
    _retouchWholeFrame = v;
    // Where to copy from was a fraction of one picture or of the frame.
    cloneFrom = null;
  }

  /// retouchLayerForFrame picks the layer whole-frame retouching goes on:
  /// a paint layer already picked, or the Retouch layer at the top of the
  /// picture -- made there if there is not one. On top, because it works on
  /// what is under it: put over the picture picked, under the layers over
  /// that, it copied from the picture alone and was hidden by the rest -- a
  /// clone from somewhere else entirely, or from nowhere.
  void retouchLayerForFrame() {
    var e = editingImage, picked = pickedLayer;
    if (e == null || picked?.kind == LayerKind.paint) return;
    var top = e.stack.last;
    if (top.kind == LayerKind.paint && top.name == "Retouch") {
      pickImageLayer(top.id);
      return;
    }
    addImageLayer(ImageLayer.painting().copyWith(name: "Retouch"), onTop: true);
  }

  /// retouchesFrame is whether a retouching stroke now works on the whole
  /// frame: asked to, or with a layer picked that has no picture of its own
  /// to work on -- a paint layer, an adjustment, a colour.
  bool get retouchesFrame =>
      _retouchWholeFrame || (pickedLayer?.framed ?? false);

  /// _cloneFollowsFrame keeps where a whole-frame clone copies from on the
  /// same part of the picture when the frame it is measured in changes from
  /// [was]'s to [now]'s.
  void _cloneFollowsFrame(ImageElement was, ImageElement now) {
    if (!retouchesFrame) return;
    var a = was.box.inner(was.bounds), b = now.box.inner(now.bounds);
    if (b.isEmpty) return;
    if (_cloneFrom case var f?) {
      _cloneFrom = Offset((a.left + f.dx * a.width - b.left) / b.width,
          (a.top + f.dy * a.height - b.top) / b.height);
    }
    if (cloneOffset case var o?) {
      cloneOffset =
          Offset(o.dx * a.width / b.width, o.dy * a.height / b.height);
    }
  }

  /// noteForBrush says something about the brush in its settings row.
  void noteForBrush(String? note) {
    _maskNote = note;
    notifyListeners();
  }

  /// changePaint changes the picked paint layer's strokes.
  void changePaint(List<StrokeMark> Function(List<StrokeMark>) edit,
      {bool transient = false}) {
    var e = editingImage, layer = pickedLayer;
    if (e == null || layer == null || layer.kind != LayerKind.paint) return;
    var next =
        e.withLayer(layer.id, (l) => l.copyWith(strokes: edit(l.strokes)));
    // Painted past the frame, the frame grows as the stroke goes, so the
    // stroke is drawn where it is being painted.
    var grown = next.grownToFit();
    if (!identical(grown, next)) _cloneFollowsFrame(next, grown);
    replaceElement(grown, transient: transient);
  }

  /// changeRetouch changes the retouching done to the picked picture.
  void changeRetouch(List<StrokeMark> Function(List<StrokeMark>) edit,
      {bool transient = false}) {
    var e = editingImage;
    var look = e == null ? null : lookOf(e, _imageLayer);
    if (e == null || look == null) return;
    replaceElement(
        withLook(e, _imageLayer, look.copyWith(retouch: edit(look.retouch))),
        transient: transient);
  }

  // ---- vector editing ----------------------------------------------------

  /// vectorEditing is the Vector element being edited point by point, by id,
  /// or null. vectorShape is the shape of it picked, and vectorPicks the
  /// points -- one, several, or none.
  String? get vectorEditing => _vectorEditing;
  String? _vectorEditing;
  int get vectorShape => _vectorShape;
  int _vectorShape = -1;
  Set<VectorPick> get vectorPicks => _vectorPicks;
  Set<VectorPick> _vectorPicks = const {};

  /// vectorPick is the one point picked, where exactly one is: the point
  /// whose handles are shown and can be pulled.
  VectorPick? get vectorPick =>
      _vectorPicks.length == 1 ? _vectorPicks.first : null;

  /// vectorSolo holds every layer of the drawing being edited but the one
  /// picked, as a picture's Solo does: only it can be picked or edited on
  /// the canvas. For this run of the app; off when the drawing is put down.
  bool get vectorSolo => _vectorSolo;
  bool _vectorSolo = false;
  set vectorSolo(bool on) {
    if (_vectorSolo == on) return;
    _vectorSolo = on;
    if (on) {
      vectorSoloOf = _soloOf;
    } else if (vectorSoloOf == _soloOf) {
      vectorSoloOf = null;
    }
    notifyListeners();
  }

  int? _soloOf(VectorElement e) =>
      _vectorSolo && e.id == _vectorEditing && _vectorShape >= 0
          ? groupOf(e, _vectorShape)
          : null;

  /// vectorTool is what a press on the drawing being edited does: pick and
  /// move points, put them down with the pen, scale them, or tint them.
  VectorTool get vectorTool => _vectorTool;
  VectorTool _vectorTool = VectorTool.select;

  set vectorTool(VectorTool tool) {
    if (_vectorTool == tool) return;
    // The align tool lines up what the last of the two select tools picked.
    if (tool == VectorTool.select || tool == VectorTool.selectShapes) {
      _lastSelect = tool;
    }
    if (tool != VectorTool.text) stopVectorTyping();
    _vectorTool = tool;
    // The pen taken out with one point picked carries on from that point.
    _vectorPenFrom = tool == VectorTool.pen && _vectorPicks.length == 1
        ? _vectorPicks.first
        : null;
    // The corner tool taken out with a rounded corner's point picked takes
    // that corner up, to be reshaped.
    if (tool == VectorTool.corner && _vectorPicks.length <= 2) {
      if (_vectorPicks.firstOrNull case var p?) {
        if (editingVector case var e? when cornerAt(e, p) != null) {
          _vectorTool = tool;
          adoptCorner(p);
          return;
        }
      }
    }
    // The Boolean tool taken out with a shape picked starts from that one.
    var e = editingVector;
    _vectorCombining = tool == VectorTool.boolean &&
            e != null &&
            _vectorShape >= 0 &&
            _vectorShape < (e.shapes?.length ?? 0)
        ? {groupOf(e, _vectorShape)}
        : const {};
    notifyListeners();
  }

  /// vectorPen is whether the pen is out. See vectorTool.
  bool get vectorPen => _vectorTool == VectorTool.pen;
  set vectorPen(bool on) =>
      vectorTool = on ? VectorTool.pen : VectorTool.select;

  /// vectorPenFrom is the point the pen's next point joins on from, or null
  /// before it has one -- when the next point starts a new shape.
  VectorPick? get vectorPenFrom => _vectorPenFrom;
  VectorPick? _vectorPenFrom;

  /// vectorPenShape is the shape the pen is drawing, or -1.
  int get vectorPenShape => _vectorPenFrom?.shape ?? -1;

  /// penFrom says where the pen's next point joins on from: the point just
  /// put down, or a point picked to carry on from.
  void penFrom(VectorPick? pick) {
    _vectorPenFrom = pick;
    if (pick != null) _vectorShape = pick.shape;
    notifyListeners();
  }

  /// finishPenShape ends the run the pen is drawing; the pen stays out,
  /// ready to start another.
  void finishPenShape() {
    if (_vectorPenFrom == null) return;
    _vectorPenFrom = null;
    _vectorPicks = const {};
    notifyListeners();
  }

  /// vectorCornerRound is whether the corner tool rounds a corner or cuts
  /// it, and vectorCornerSize how far back along each side it starts, in
  /// canvas units.
  ///
  /// Both reshape the corner the tool last made while it is still picked --
  /// see vectorCornerActive.
  bool get vectorCornerRound => _vectorCornerRound;
  bool _vectorCornerRound = true;
  set vectorCornerRound(bool on) {
    if (_vectorCornerRound == on) return;
    _vectorCornerRound = on;
    if (!reshapeCorner()) notifyListeners();
  }

  double get vectorCornerSize => _vectorCornerSize;
  double _vectorCornerSize = 20;
  set vectorCornerSize(double v) => sizeCorner(v);

  /// sizeCorner sets the corner size and reshapes the corner being made by
  /// it -- [transient] while a drag is still setting it.
  void sizeCorner(double v, {bool transient = false}) {
    if (_vectorCornerSize == v) return;
    _vectorCornerSize = v;
    if (!reshapeCorner(transient: transient)) notifyListeners();
  }

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

  /// vectorCornerActive is whether the corner the tool last made is still
  /// being made: its size and kind reshape it, and a drag on it goes on
  /// shaping it. Picking anything else finishes it.
  bool get vectorCornerActive {
    var c = _corner;
    return c != null &&
        identical(editingVector, c.after) &&
        c.picks.length == _vectorPicks.length &&
        c.picks.containsAll(_vectorPicks);
  }

  /// vectorCornerPoint is where the corner being made was, in the drawing's
  /// units, or null with none.
  Offset? get vectorCornerPoint {
    if (!vectorCornerActive) return null;
    var c = _corner!;
    return vectorNodeAt(c.before, c.at)?.point;
  }

  /// adoptCorner takes up the rounded corner the point at [pick] is one end
  /// of -- one made before, or a rounded box's -- as the corner being made,
  /// so its size and a drag reshape it: the size set to its own. Answers
  /// whether the point was one.
  bool adoptCorner(VectorPick pick) {
    var e = editingVector;
    if (e == null) return false;
    var found = cornerAt(e, pick);
    if (found == null) return false;
    var (before, at, reach, picks) = found;
    _corner = (before: before, at: at, after: e, picks: picks);
    _vectorPicks = picks;
    _vectorShape = pick.shape;
    _vectorCornerRound = true;
    _vectorCornerSize = (reach / VectorSpace(e).unitsPer).roundToDouble();
    notifyListeners();
    return true;
  }

  /// roundCorner rounds -- or cuts -- the corner at [at] as the corner
  /// settings say, picking the two points it makes and keeping it open to
  /// reshaping. Answers whether there was a corner there to round.
  bool roundCorner(VectorPick at, {bool transient = false}) {
    var e = editingVector;
    if (e == null) return false;
    return _shapeCorner(e, at, transient: transient);
  }

  /// reshapeCorner makes the corner being made again from the drawing as it
  /// was before it, at the size and kind now set. Answers whether there was
  /// one being made.
  bool reshapeCorner({bool transient = false}) {
    if (!vectorCornerActive) return false;
    var c = _corner!;
    return _shapeCorner(c.before, c.at, transient: transient);
  }

  bool _shapeCorner(VectorElement before, VectorPick at,
      {bool transient = false}) {
    var done = withCornered(
        before, at, _vectorCornerSize * VectorSpace(before).unitsPer,
        round: _vectorCornerRound);
    if (done == null) return false;
    var (after, picks) = done;
    _corner = (before: before, at: at, after: after, picks: picks);
    _vectorPicks = picks;
    _vectorShape = at.shape;
    replaceElement(after, transient: transient);
    return true;
  }

  /// vectorHandleDrag is what dragging a handle may change, and
  /// vectorHandleSnap whether it turns in fifteen-degree steps.
  VectorHandleDrag get vectorHandleDrag => _vectorHandleDrag;
  VectorHandleDrag _vectorHandleDrag = VectorHandleDrag.any;
  set vectorHandleDrag(VectorHandleDrag d) {
    if (_vectorHandleDrag == d) return;
    _vectorHandleDrag = d;
    notifyListeners();
  }

  bool get vectorHandleSnap => _vectorHandleSnap;
  bool _vectorHandleSnap = false;
  set vectorHandleSnap(bool on) {
    if (_vectorHandleSnap == on) return;
    _vectorHandleSnap = on;
    notifyListeners();
  }

  /// _copiedShapes is what the last copy of points copied, and _pastes how
  /// many times it has been pasted since -- each paste a step further off,
  /// so pastes do not land on top of one another.
  List<VectorShape> _copiedShapes = const [];
  int _pastes = 0;

  /// copyVectorPoints copies the points picked -- see copiedShapes --
  /// answering whether there was anything to copy.
  bool copyVectorPoints() {
    var e = editingVector;
    if (e == null) return false;
    // Shapes picked whole: every point of them.
    var picks = _vectorPicks.isEmpty && _picksShapes
        ? itemPicks(e, vectorItems)
        : _vectorPicks;
    if (picks.isEmpty) return false;
    var copied = copiedShapes(e, picks);
    if (copied.isEmpty) return false;
    _copiedShapes = copied;
    _pastes = 0;
    return true;
  }

  /// cutVectorPoints copies the points picked and takes them out.
  bool cutVectorPoints() {
    if (!copyVectorPoints()) return false;
    if (_vectorPicks.isEmpty && _picksShapes) {
      if (editingVector case var e?) _vectorPicks = itemPicks(e, vectorItems);
      _vectorItems = const {};
    }
    deleteVectorPoint();
    _pastes = -1;
    return true;
  }

  /// pasteVectorPoints puts the points copied into the drawing being
  /// edited, a little down and to the right of where they were, and picks
  /// them -- answering whether there was anything to paste.
  bool pasteVectorPoints() {
    var e = editingVector;
    if (e == null || _copiedShapes.isEmpty) return false;
    _pastes++;
    var step = 10 * VectorSpace(e).unitsPer * _pastes;
    var (next, picks) = withPasted(e, _copiedShapes, Offset(step, step));
    // Picking shapes, what is pasted is picked as shapes -- its box to move
    // it by; picking points, its points.
    if (_picksShapes) {
      _vectorItems = itemsOf(next, picks);
      _vectorPicks = const {};
    } else {
      _vectorPicks = picks;
    }
    _vectorShape = picks.isEmpty ? -1 : picks.first.shape;
    replaceElement(next);
    return true;
  }

  /// pickAllVectorPoints picks every point of the drawing being edited.
  bool pickAllVectorPoints() {
    var e = editingVector;
    if (e == null) return false;
    if (_picksShapes) {
      _vectorItems = allItems(e);
      notifyListeners();
      return true;
    }
    pickVectorPoints(allPicks(e));
    return true;
  }

  /// editPickedPoints replaces the drawing being edited with what [edit]
  /// makes of it and the points picked, as one undo step.
  void editPickedPoints(
      VectorElement Function(VectorElement, Set<VectorPick>) edit) {
    var e = editingVector;
    if (e == null || _vectorPicks.isEmpty) return;
    var next = edit(e, _vectorPicks);
    if (!identical(next, e)) replaceElement(next);
  }

  /// vectorBrush is the pencil's brush as it is now -- one picked, then
  /// changed or not -- and vectorPencilColour the colour it draws in.
  VectorBrush get vectorBrush => _vectorBrush;
  VectorBrush _vectorBrush = builtInBrushes.first;
  set vectorBrush(VectorBrush b) {
    _vectorBrush = b;
    notifyListeners();
  }

  /// vectorPencilPoints is whether the drawing's points are shown while the
  /// pencil is out. Off to start with: drawing, they are in the way.
  bool get vectorPencilPoints => _vectorPencilPoints;
  bool _vectorPencilPoints = false;
  set vectorPencilPoints(bool on) {
    if (_vectorPencilPoints == on) return;
    _vectorPencilPoints = on;
    notifyListeners();
  }

  /// vectorLanes is how much of a drawing's shapes the timeline shows
  /// under the drawing's own keyframes: none of them, the shape picked, or
  /// every one. See VectorShapeLanes.
  VectorLanes get vectorLanes => _vectorLanes;
  VectorLanes _vectorLanes = VectorLanes.none;
  set vectorLanes(VectorLanes l) {
    if (_vectorLanes == l) return;
    _vectorLanes = l;
    notifyListeners();
  }

  /// retimeShapes changes when [e]'s shapes come in by [edit]: the shapes'
  /// timing first written out in the timeline's frames, as it plays now --
  /// see withTimingBaked -- so the change is in frames that can be seen; and
  /// the drawing's arrival then fitted round all of them again, the timeline
  /// lengthened where it has to be to hold it. [transient] while a drag is
  /// still making it.
  void retimeShapes(VectorElement e, VectorElement Function(VectorElement) edit,
      {bool transient = false}) {
    var next = withSpanFitted(edit(withTimingBaked(e)));
    var document = _document;
    if (vectorArrivalSpan(next) case (var at, var span)
        when at + span > document.frames - 1) {
      document = document.copyWith(frames: at + span + 1);
    }
    apply(document.withElement(next), transient: transient);
  }

  /// retimeLayers changes when a picture's layers come in, as [edit] says
  /// -- worked in the timeline's frames, with the arrival fitted round them
  /// all again after, and the scene lengthened where it has to be. See
  /// withLayerTimingBaked.
  void retimeLayers(ImageElement e, ImageElement Function(ImageElement) edit,
      {bool transient = false}) {
    var next = withLayerSpanFitted(edit(withLayerTimingBaked(e)));
    var document = _document;
    if (imageArrivalSpan(next) case (var at, var span)
        when at + span > document.frames - 1) {
      document = document.copyWith(frames: at + span + 1);
    }
    apply(document.withElement(next), transient: transient);
  }

  /// vectorShapeMade is the shape the shapes tool last drew, while it is
  /// still the one picked: the one its box moves and resizes. -1 with none.
  int get vectorShapeMade =>
      _vectorShapeMade >= 0 && _vectorShapeMade == _vectorShape
          ? _vectorShapeMade
          : -1;
  int _vectorShapeMade = -1;
  set vectorShapeMade(int i) => _vectorShapeMade = i;

  /// vectorShapeKind is the shape the shapes tool draws; vectorShapeSides a
  /// polygon's sides and a star's points; vectorStarInner how far in a
  /// star's inner points sit, as a share of its outer ones; and
  /// vectorShapeCorner a rounded box's corners, as a share of its shorter
  /// side.
  VectorShapeKind get vectorShapeKind => _vectorShapeKind;
  VectorShapeKind _vectorShapeKind = VectorShapeKind.box;
  set vectorShapeKind(VectorShapeKind k) {
    if (_vectorShapeKind == k) return;
    _vectorShapeKind = k;
    notifyListeners();
  }

  int get vectorShapeSides => _vectorShapeSides;
  int _vectorShapeSides = 5;
  set vectorShapeSides(int n) {
    if (_vectorShapeSides == n) return;
    _vectorShapeSides = n;
    notifyListeners();
  }

  double get vectorStarInner => _vectorStarInner;
  double _vectorStarInner = 0.45;
  set vectorStarInner(double v) {
    if (_vectorStarInner == v) return;
    _vectorStarInner = v;
    notifyListeners();
  }

  double get vectorShapeCorner => _vectorShapeCorner;
  double _vectorShapeCorner = 0.2;
  set vectorShapeCorner(double v) {
    if (_vectorShapeCorner == v) return;
    _vectorShapeCorner = v;
    notifyListeners();
  }

  /// vectorShapeFill and vectorShapeLine are the colours a new shape is
  /// drawn in, or null for none; vectorShapeWidth its line's width, in
  /// pixels on screen as it is drawn. A line, an arrow or a mark is always
  /// a line, whatever the fill is set to.
  Color? get vectorShapeFill => _vectorShapeFill;
  Color? _vectorShapeFill = const Color(0xFF8AB4F8);
  set vectorShapeFill(Color? c) {
    if (_vectorShapeFill == c) return;
    _vectorShapeFill = c;
    notifyListeners();
  }

  Color? get vectorShapeLine => _vectorShapeLine;
  Color? _vectorShapeLine = const Color(0xFF202124);
  set vectorShapeLine(Color? c) {
    if (_vectorShapeLine == c) return;
    _vectorShapeLine = c;
    notifyListeners();
  }

  double get vectorShapeWidth => _vectorShapeWidth;
  double _vectorShapeWidth = 3;
  set vectorShapeWidth(double v) {
    if (_vectorShapeWidth == v) return;
    _vectorShapeWidth = v;
    notifyListeners();
  }

  /// vectorEraseWhole is whether the eraser takes out whole lines and
  /// shapes, where it touches them, rather than rubbing out what it goes
  /// over; vectorEraseSize and vectorEraseSoft are its size on screen and
  /// how far its edge fades; vectorEraseLine and vectorEraseFill whether it
  /// rubs out lines, fills, or both.
  bool get vectorEraseWhole => _vectorEraseWhole;
  bool _vectorEraseWhole = false;
  set vectorEraseWhole(bool on) {
    if (_vectorEraseWhole == on) return;
    _vectorEraseWhole = on;
    notifyListeners();
  }

  double get vectorEraseSize => _vectorEraseSize;
  double _vectorEraseSize = 20;
  set vectorEraseSize(double v) {
    if (_vectorEraseSize == v) return;
    _vectorEraseSize = v;
    notifyListeners();
  }

  double get vectorEraseSoft => _vectorEraseSoft;
  double _vectorEraseSoft = 0;
  set vectorEraseSoft(double v) {
    if (_vectorEraseSoft == v) return;
    _vectorEraseSoft = v;
    notifyListeners();
  }

  bool get vectorEraseLine => _vectorEraseLine;
  bool _vectorEraseLine = true;
  set vectorEraseLine(bool on) {
    if (_vectorEraseLine == on) return;
    _vectorEraseLine = on;
    notifyListeners();
  }

  bool get vectorEraseFill => _vectorEraseFill;
  bool _vectorEraseFill = true;
  set vectorEraseFill(bool on) {
    if (_vectorEraseFill == on) return;
    _vectorEraseFill = on;
    notifyListeners();
  }

  /// clearVectorErasures takes every rub-out off the drawing being edited.
  void clearVectorErasures() {
    var e = editingVector;
    if (e == null || !hasErasures(e)) return;
    replaceElement(withoutErasures(e));
  }

  /// vectorMirrorAcross and vectorMirrorDown are the pencil's symmetry: a
  /// stroke drawn is mirrored across the drawing's upright middle line, its
  /// level middle line, or both -- left and right, top and bottom, all four.
  bool get vectorMirrorAcross => _vectorMirrorAcross;
  bool _vectorMirrorAcross = false;
  set vectorMirrorAcross(bool on) {
    if (_vectorMirrorAcross == on) return;
    _vectorMirrorAcross = on;
    notifyListeners();
  }

  bool get vectorMirrorDown => _vectorMirrorDown;
  bool _vectorMirrorDown = false;
  set vectorMirrorDown(bool on) {
    if (_vectorMirrorDown == on) return;
    _vectorMirrorDown = on;
    notifyListeners();
  }

  /// vectorQuickFill is whether a click with the pencil fills the area the
  /// lines close round it, rather than drawing -- the paint bucket -- and
  /// vectorFillGap the widest opening, in pixels on screen, it still counts
  /// as closed.
  bool get vectorQuickFill => _vectorQuickFill;
  bool _vectorQuickFill = false;
  set vectorQuickFill(bool on) {
    if (_vectorQuickFill == on) return;
    _vectorQuickFill = on;
    notifyListeners();
  }

  /// vectorTextStyle is the type new text in a drawing is set in -- its
  /// size in the canvas's own pixels -- and vectorTextColour its colour.
  VectorText get vectorTextStyle => _vectorTextStyle;
  VectorText _vectorTextStyle = const VectorText();
  Color get vectorTextColour => _vectorTextColour;
  Color _vectorTextColour = const Color(0xFF000000);
  set vectorTextColour(Color c) {
    _vectorTextColour = c;
    var e = editingVector;
    var i = _vectorTyping >= 0 ? _vectorTyping : _vectorShape;
    if (e?.shapes case var shapes? when i >= 0 && i < shapes.length) {
      if (shapes[i].liveText != null) {
        replaceElement(e!.withShape(i, shapes[i].copyWith(fill: c)),
            transient: _vectorTyping >= 0);
      }
    }
    notifyListeners();
  }

  /// vectorTyping is the shape of the drawing being typed into with the
  /// text tool, or -1.
  int get vectorTyping => _vectorTyping;
  int _vectorTyping = -1;

  /// _typedShape is the drawing, the shape being typed into and its index,
  /// while there is one.
  (VectorElement, int, VectorShape)? _typedShape() {
    var e = editingVector;
    var i = _vectorTyping;
    var shapes = e?.shapes;
    if (e == null || shapes == null || i < 0 || i >= shapes.length) {
      return null;
    }
    return (e, i, shapes[i]);
  }

  /// typedText is the text being typed, or the text of the shape picked
  /// where it is still text: what the text tool's settings show.
  VectorText? get typedText {
    if (_typedShape() case (_, _, var s)?) return s.liveText;
    var e = editingVector;
    var i = _vectorShape;
    if (e?.shapes case var shapes? when i >= 0 && i < shapes.length) {
      return shapes[i].liveText;
    }
    return null;
  }

  /// setVectorTextStyle sets the type new text is set in -- [size] here in
  /// the canvas's pixels -- and the text being typed, or picked, with it.
  void setVectorTextStyle(VectorText style) {
    // The type and nothing else: the words, the place and the signature of
    // whatever text the settings were showing are that text's, and new text
    // started with another's signature was never text at all -- it could
    // not be typed into.
    _vectorTextStyle = VectorText(
        family: style.family,
        weight: style.weight,
        italic: style.italic,
        size: style.size,
        spacing: style.spacing,
        leading: style.leading,
        align: style.align);
    var e = editingVector;
    var i = _vectorTyping >= 0 ? _vectorTyping : _vectorShape;
    var s = e?.shapes != null && i >= 0 && i < e!.shapes!.length
        ? e.shapes![i]
        : null;
    var t = s?.liveText;
    if (e != null && t != null) {
      var px = VectorSpace(e).unitsPer;
      retypeVectorText(
          i,
          t.copyWith(
              family: style.family,
              weight: style.weight,
              italic: style.italic,
              size: style.size * px,
              spacing: style.spacing,
              leading: style.leading,
              align: style.align));
    }
    notifyListeners();
  }

  /// retypeVectorText lays shape [shape] out again as [t] -- once its font
  /// is read, which is at once where it has been already.
  void retypeVectorText(int shape, VectorText t) {
    var pick = FontFiles.instance.cached(t.family, t.weight, t.italic);
    if (pick == null) {
      FontFiles.instance.load(t.family, t.weight, t.italic).then((p) {
        if (p != null) retypeVectorText(shape, t);
      });
      return;
    }
    var e = editingVector;
    var shapes = e?.shapes;
    if (e == null || shapes == null || shape >= shapes.length) return;
    var s = shapes[shape];
    var origin = s.textOrigin ?? s.text?.origin ?? t.origin;
    replaceElement(e.withShape(shape, typed(s, t, origin, pick)),
        transient: true);
  }

  /// newVectorText starts new text in the drawing being edited, its first
  /// line starting at [at] in the drawing's own units, and starts typing
  /// into it.
  Future<void> newVectorText(Offset at) async {
    stopVectorTyping();
    var e = editingVector;
    if (e == null) return;
    var style = _vectorTextStyle;
    var t = VectorText(
        family: style.family,
        weight: style.weight,
        italic: style.italic,
        size: style.size * VectorSpace(e).unitsPer,
        spacing: style.spacing,
        leading: style.leading,
        align: style.align,
        origin: at);
    await FontFiles.instance.load(t.family, t.weight, t.italic);
    e = editingVector;
    if (e == null) return;
    var shapes = e.shapes ?? const <VectorShape>[];
    beginInteraction();
    replaceElement(
        e.copyWith(shapes: [
          ...shapes,
          VectorShape(paths: const [], fill: _vectorTextColour, text: t),
        ]),
        transient: true);
    _vectorTyping = shapes.length;
    _vectorShape = shapes.length;
    _vectorPicks = const {};
    notifyListeners();
  }

  /// startVectorTyping types into shape [shape], text already.
  void startVectorTyping(int shape) {
    if (_vectorTyping == shape) return;
    stopVectorTyping();
    beginInteraction();
    _vectorTyping = shape;
    _vectorShape = shape;
    _vectorPicks = const {};
    notifyListeners();
  }

  /// stopVectorTyping finishes the text being typed: what was typed is one
  /// change, and text left empty is taken away.
  void stopVectorTyping() {
    if (_vectorTyping < 0) return;
    if (_typedShape() case (var e, var i, var s)?
        when (s.liveText?.text.trim() ?? "x").isEmpty) {
      var shapes = [...e.shapes!]..removeAt(i);
      replaceElement(e.copyWith(shapes: shapes), transient: true);
      if (_vectorShape == i) _vectorShape = -1;
    }
    _vectorTyping = -1;
    endInteraction();
    notifyListeners();
  }

  /// sampling is whether the eyedropper is out: the next press on the canvas
  /// takes the colour under it, and gives it to [_onSampled]. sampled is
  /// the colour it last took.
  bool get sampling => _onSampled != null;
  ValueChanged<Color>? _onSampled;
  Color? get sampled => _sampled;
  Color? _sampled;

  void startSampling(ValueChanged<Color> onSampled) {
    _onSampled = onSampled;
    notifyListeners();
  }

  void stopSampling() {
    if (_onSampled == null) return;
    _onSampled = null;
    notifyListeners();
  }

  /// sampledColour hands the eyedropper what it took, and puts it away.
  void sampledColour(Color c) {
    var give = _onSampled;
    _onSampled = null;
    _sampled = c;
    give?.call(c);
    notifyListeners();
  }

  /// vectorKnifeGap is how far apart the knife leaves the two sides of a
  /// cut, in the canvas's own pixels.
  double get vectorKnifeGap => _vectorKnifeGap;
  double _vectorKnifeGap = 1;
  set vectorKnifeGap(double v) {
    if (_vectorKnifeGap == v) return;
    _vectorKnifeGap = v;
    notifyListeners();
  }

  double get vectorFillGap => _vectorFillGap;
  double _vectorFillGap = 3;
  set vectorFillGap(double v) {
    if (_vectorFillGap == v) return;
    _vectorFillGap = v;
    notifyListeners();
  }

  /// vectorPencilFill is the colour a fill brush fills its strokes with, and
  /// the quick fill fills an area with.
  Color get vectorPencilFill => _vectorPencilFill;
  Color _vectorPencilFill = const Color(0xFF8AB4F8);
  set vectorPencilFill(Color c) {
    if (_vectorPencilFill == c) return;
    _vectorPencilFill = c;
    notifyListeners();
  }

  Color get vectorPencilColour => _vectorPencilColour;
  Color _vectorPencilColour = const Color(0xFF202124);
  set vectorPencilColour(Color c) {
    if (_vectorPencilColour == c) return;
    _vectorPencilColour = c;
    notifyListeners();
  }

  /// stylusButtons is what the pen's three buttons do with the pencil out,
  /// in the order the pen reports them -- a right click, a middle click, a
  /// back click, which is what a tablet's driver sends for them -- and
  /// stylusEraser what its other end does.
  List<StylusAction> get stylusButtons => _stylusButtons;
  List<StylusAction> _stylusButtons = const [
    StylusAction.pickColour,
    StylusAction.pan,
    StylusAction.undo,
  ];
  void setStylusButton(int index, StylusAction action) {
    if (index < 0 || index >= _stylusButtons.length) return;
    _stylusButtons = [
      for (var (i, a) in _stylusButtons.indexed) i == index ? action : a,
    ];
    notifyListeners();
  }

  StylusAction get stylusEraser => _stylusEraser;
  StylusAction _stylusEraser = StylusAction.erase;
  set stylusEraser(StylusAction a) {
    if (_stylusEraser == a) return;
    _stylusEraser = a;
    notifyListeners();
  }

  /// vectorCombining is the shapes picked with the Boolean tool, to be
  /// combined -- each the first of its run of combined shapes.
  Set<int> get vectorCombining => _vectorCombining;
  Set<int> _vectorCombining = const {};

  /// toggleCombining picks shape [shape] for combining, or unpicks it.
  void toggleCombining(int shape) {
    var next = {..._vectorCombining};
    if (!next.remove(shape)) next.add(shape);
    _vectorCombining = next;
    notifyListeners();
  }

  /// clearCombining unpicks every shape picked for combining.
  void clearCombining() {
    if (_vectorCombining.isEmpty) return;
    _vectorCombining = const {};
    notifyListeners();
  }

  /// combineVector combines the shapes picked by [op], leaving the result
  /// picked.
  void combineVector(VectorCombine op) {
    var e = editingVector;
    if (e == null || _vectorCombining.length < 2) return;
    var (next, at) = withCombined(e, _vectorCombining, op);
    _vectorCombining = at >= 0 ? {at} : const {};
    _vectorPicks = const {};
    _vectorShape = -1;
    replaceElement(next);
  }

  /// separateVector undoes the combining of every picked result.
  void separateVector() {
    var e = editingVector;
    if (e == null || _vectorCombining.isEmpty) return;
    var next = e;
    for (var base in _vectorCombining) {
      next = withSeparated(next, base);
    }
    _vectorCombining = const {};
    replaceElement(next);
  }

  /// vectorTint is the tint brush's colour -- or gradient, laid across each
  /// stroke as the colour picker sets it.
  PaintSpec get vectorTint => _vectorTint;
  PaintSpec _vectorTint = const PaintSpec(Color(0xFFE5484D));
  set vectorTint(PaintSpec p) {
    if (_vectorTint == p) return;
    _vectorTint = p;
    notifyListeners();
  }

  /// vectorBrushSize is the tint brush's width on screen, in pixels: the
  /// same brush however far in the canvas is zoomed. vectorBrushSoft is how
  /// far its edge fades, 0 to 1.
  double get vectorBrushSize => _vectorBrushSize;
  double _vectorBrushSize = 24;
  set vectorBrushSize(double v) {
    if (_vectorBrushSize == v) return;
    _vectorBrushSize = v;
    notifyListeners();
  }

  double get vectorBrushSoft => _vectorBrushSoft;
  double _vectorBrushSoft = 0.5;
  set vectorBrushSoft(double v) {
    if (_vectorBrushSoft == v) return;
    _vectorBrushSoft = v;
    notifyListeners();
  }

  /// vectorTintLine and vectorTintFill are where the brush's tint shows: on
  /// the drawing's lines, in its fills. Both is both.
  bool get vectorTintLine => _vectorTintLine;
  bool _vectorTintLine = true;
  set vectorTintLine(bool on) {
    if (_vectorTintLine == on) return;
    _vectorTintLine = on;
    notifyListeners();
  }

  bool get vectorTintFill => _vectorTintFill;
  bool _vectorTintFill = true;
  set vectorTintFill(bool on) {
    if (_vectorTintFill == on) return;
    _vectorTintFill = on;
    notifyListeners();
  }

  /// clearVectorTints takes every tint off the drawing being edited.
  void clearVectorTints() {
    var e = editingVector;
    if (e == null || !hasTints(e)) return;
    replaceElement(withoutTints(e));
  }

  // ---- drawing on a character ---------------------------------------------

  /// drawingOn is the character being drawn on, by id, or null. It is drawn
  /// on with the drawing tools, through a drawing laid over it that they
  /// edit as they edit any -- see drawingProxy -- and what is drawn on that
  /// goes into the panel the character is seen from as it is drawn.
  String? get drawingOn => switch (_vectorEditing) {
        var id? => drawnCharacterOf(id),
        null => null,
      };

  /// showPuppet lays the puppet over a sketched character to draw over --
  /// see character_guide.dart. For this run of the app: what it changes is
  /// the character's, and stays when it is put away.
  bool get showPuppet => _showPuppet;
  bool _showPuppet = false;
  set showPuppet(bool on) {
    if (_showPuppet == on) return;
    _showPuppet = on;
    _syncDoll();
    notifyListeners();
  }

  /// puppet3D is whether the puppet is the doll in 3D -- see
  /// character_doll.dart -- to pose and draw over, rather than the guide
  /// drawn flat with its handles. For this run of the app.
  bool get puppet3D => _puppet3D;
  bool _puppet3D = false;
  set puppet3D(bool on) {
    if (_puppet3D == on) return;
    _puppet3D = on;
    _syncDoll();
    notifyListeners();
  }

  /// dollShown is whether the doll is out.
  bool get dollShown => _showPuppet && _puppet3D;

  /// spritePaint is the Sprite element being painted frame by frame on the
  /// canvas, when one is -- see sprite_painting.dart -- and paintSprite
  /// starts painting one, or with null stops.
  SpritePaintSession? get spritePaint => _spritePaint;
  SpritePaintSession? _spritePaint;
  void paintSprite(String? id) {
    if (_spritePaint?.id == id) return;
    _spritePaint?.removeListener(notifyListeners);
    _spritePaint?.dispose();
    _spritePaint = id == null ? null : (SpritePaintSession(this, id)..addListener(notifyListeners));
    spritePaintingOf = _spritePaint == null
        ? null
        : (e) => e.id == _spritePaint?.id ? _spritePaint!.view(e) : null;
    notifyListeners();
  }

  /// tilePaint is the Tile map being painted on the canvas, when one is --
  /// see tile_painting.dart -- and paintTiles starts painting one, or with
  /// null stops.
  TilePaintSession? get tilePaint => _tilePaint;
  TilePaintSession? _tilePaint;
  void paintTiles(String? id) {
    if (_tilePaint?.id == id) return;
    _tilePaint?.removeListener(notifyListeners);
    _tilePaint?.dispose();
    _tilePaint = id == null ? null : (TilePaintSession(this, id)..addListener(notifyListeners));
    tileMapEditingOf =
        _tilePaint == null ? null : (e) => e.id == _tilePaint?.id ? _tilePaint!.view(e) : null;
    notifyListeners();
  }

  /// dollJoint is the doll's joint picked to turn, with its rings round
  /// it on the canvas -- see character_doll_pose.dart. For this run of
  /// the app.
  DollJoint? get dollJoint => dollShown ? _dollJoint : null;
  DollJoint? _dollJoint;
  set dollJoint(DollJoint? j) {
    if (_dollJoint == j) return;
    _dollJoint = j;
    notifyListeners();
  }

  /// dollLens is how strongly the doll is seen in perspective -- nought
  /// for flat, one for a camera close up -- and dollLines whether its
  /// guide lines are drawn. For this run of the app.
  double get dollLens => _dollLook.lens;
  DollLook get dollLook => _dollLook;
  bool get dollLines => _dollLook.lines;
  DollLook _dollLook = const DollLook();
  set dollLens(double lens) => dollLook = _dollLook.copyWith(lens: lens);
  set dollLines(bool on) => dollLook = _dollLook.copyWith(lines: on);

  /// dollLook is everything about how the doll is shown -- see DollLook.
  set dollLook(DollLook look) {
    if (look.lens == _dollLook.lens &&
        look.lines == _dollLook.lines &&
        look.place == _dollLook.place &&
        look.opacity == _dollLook.opacity &&
        look.kind == _dollLook.kind) {
      return;
    }
    _dollLook = look;
    _syncDoll();
    notifyListeners();
  }

  void _syncDoll() {
    if (dollShown) {
      characterDollOf = _dollOf;
      characterDollLook = _dollLook;
    } else if (characterDollOf == _dollOf) {
      characterDollOf = null;
    }
  }

  /// _dollOf is where the doll is drawn for [e]: for the sketch being drawn
  /// on or picked alone, under one drawn from nothing and faintly over any
  /// other.
  DollGuide _dollOf(CharacterElement e) {
    var id = drawingOn ?? (_selection.length == 1 ? _selection.first : null);
    if (!dollShown || e.id != id) return DollGuide.none;
    return _dollLook.place ??
        (e.dna.kind == CharacterType.empty ? DollGuide.under : DollGuide.over);
  }

  /// editRig shows a sketch's limbs point by point, to reshape on the
  /// canvas -- see character_rig_editor.dart. For this run of the app.
  bool get editRig => _editRig;
  bool _editRig = false;
  set editRig(bool on) {
    if (_editRig == on) return;
    _editRig = on;
    _rigPick = null;
    notifyListeners();
  }

  /// rigPick is the limb's point picked while the rig is edited: what
  /// Delete takes away.
  (CharacterLimb, RigPoint)? get rigPick =>
      _rigPickOf != null && rigCharacter?.id == _rigPickOf ? _rigPick : null;
  (CharacterLimb, RigPoint)? _rigPick;

  /// _rigPickOf is whose point is picked: picking another character is not
  /// picking its point at the same spot.
  String? _rigPickOf;
  void pickRigPoint(CharacterLimb? limb, [RigPoint? point]) {
    _rigPick = limb == null || point == null ? null : (limb, point);
    // Its limb's layer picked, for its settings beside it.
    if (limb != null && point != null) _pickedCharacterLayer = limb.name;
    _rigPickOf = _rigPick == null ? null : rigCharacter?.id;
    notifyListeners();
  }

  /// mirrorEdits makes an edit to one side of a sketch -- a point of an arm
  /// or a leg, an eye, a brow, a corner of the mouth -- the same, mirrored,
  /// on the other. On until it is switched off, for this run of the app.
  bool get mirrorEdits => _mirrorEdits;
  bool _mirrorEdits = true;
  set mirrorEdits(bool on) {
    if (_mirrorEdits == on) return;
    _mirrorEdits = on;
    notifyListeners();
  }

  /// rigCharacter is the sketch whose rig is edited: the one drawn on, or
  /// picked alone.
  CharacterElement? get rigCharacter {
    if (!_editRig) return null;
    var id = drawingOn ?? (_selection.length == 1 ? _selection.first : null);
    var e = id == null ? null : _document.elementById(id);
    return e is CharacterElement && !e.body.inThreeD && e.visible ? e : null;
  }

  /// deleteRigPoint takes away the point picked -- or puts the joint
  /// picked back as it was -- returning whether there was one.
  bool deleteRigPoint() {
    var pick = rigPick, e = rigCharacter;
    if (pick == null || e == null) return false;
    replaceElement(withoutRigPoint(e, pick.$1, pick.$2, mirror: _mirrorEdits));
    _rigPick = null;
    notifyListeners();
    return true;
  }

  /// pickedCharacterLayer is the layer of a sketch picked in its Layers
  /// -- see character_layers.dart -- whose settings are shown under them.
  /// For this run of the app.
  String? get pickedCharacterLayer => _pickedCharacterLayer;
  String? _pickedCharacterLayer;
  void pickCharacterLayer(String? layer) {
    if (_pickedCharacterLayer == layer) return;
    _pickedCharacterLayer = layer;
    notifyListeners();
  }

  /// soloLayerOf is the layer of character [id] soloed -- drawn alone over
  /// the rest, faint -- or null.
  String? soloLayerOf(String id) => _layerSoloOf == id ? _layerSolo : null;
  String? _layerSolo;
  String? _layerSoloOf;

  /// soloLayer solos [layer] of character [id], or -- with null, or the
  /// layer already soloed -- stops.
  void soloLayer(String id, String? layer) {
    if (layer == null || (_layerSoloOf == id && _layerSolo == layer)) {
      _layerSoloOf = null;
      _layerSolo = null;
    } else {
      _layerSoloOf = id;
      _layerSolo = layer;
    }
    characterSoloOf = _layerSoloOf == null ? null : (e) => e.id == _layerSoloOf ? _layerSolo : null;
    notifyListeners();
  }

  /// editHair shows a sketch's hair strokes to shape on the canvas -- see
  /// character_hair_editor.dart -- and hairPick is the stroke picked, by
  /// index, for the character it was picked on. For this run of the app.
  bool get editHair => _editHair;
  bool _editHair = false;
  set editHair(bool on) {
    if (_editHair == on) return;
    _editHair = on;
    _hairPick = null;
    notifyListeners();
  }

  /// showTurnaround is whether the sketch drawn on -- or picked alone --
  /// has its other views laid out beside it on the canvas, with lines
  /// across them at the heights a turn keeps: see character_turnaround.dart.
  /// onionSkin is whether the view next round is shown faintly over it.
  bool get showTurnaround => _showTurnaround;
  bool _showTurnaround = false;
  set showTurnaround(bool on) {
    if (_showTurnaround == on) return;
    _showTurnaround = on;
    notifyListeners();
  }

  bool get onionSkin => _onionSkin;
  bool _onionSkin = false;
  set onionSkin(bool on) {
    if (_onionSkin == on) return;
    _onionSkin = on;
    notifyListeners();
  }

  /// turnaroundCharacter is the sketch whose turnaround is shown, or null.
  CharacterElement? get turnaroundCharacter {
    if (!_showTurnaround) return null;
    var id = drawingOn ?? (_selection.length == 1 ? _selection.first : null);
    var e = id == null ? null : _document.elementById(id);
    return e is CharacterElement && !e.body.inThreeD && e.visible ? e : null;
  }

  /// copyCharacterLayerEdits does what was done to [layer] of sketch [id] on
  /// the view it is seen from to it on the view [to] as well -- or on every
  /// other view, with "*" -- as one step to undo. See copyLayerEdits.
  void copyCharacterLayerEdits(String id, String layer, String to) {
    var e = _document.elementById(id);
    if (e is! CharacterElement) return;
    var rate = math.max(1, _document.frameRate);
    var from = drawnKey(e, _frame, rate);
    var targets = to == "*"
        ? [
            for (var v in e.views) ...[
              v.key,
              if (oppositeKey(v.key) case var o?) o,
            ],
          ].where((k) => k != from).toList()
        : [to];
    var next = e;
    for (var k in targets) {
      next = copyLayerEdits(next, layer, from, k, _frame, rate);
    }
    beginInteraction();
    replaceElement(next);
    endInteraction();
  }

  /// mirrorCharacterLayer mirrors [layer] of sketch [id], on the view it is
  /// seen from, onto the view turned the other way. See mirrorLayerEdits.
  void mirrorCharacterLayer(String id, String layer) {
    var e = _document.elementById(id);
    if (e is! CharacterElement) return;
    var from = drawnKey(e, _frame, math.max(1, _document.frameRate));
    beginInteraction();
    replaceElement(mirrorLayerEdits(e, layer, from));
    endInteraction();
  }

  /// showCharacterView turns sketch [id] to the view [key] names -- see
  /// showPanel -- as one step to undo; drawn on, it goes on being drawn on
  /// there, the same layer or garment.
  void showCharacterView(String id, String key) {
    var e = _document.elementById(id);
    if (e is! CharacterElement) return;
    var drawing = drawingOn == id;
    var garment = _drawingGarment, layer = _drawingLayer;
    if (drawing) stopDrawingOnCharacter();
    beginInteraction();
    replaceElement(showPanel(this, _document.elementById(id) as CharacterElement, key));
    endInteraction();
    if (drawing) drawOnCharacter(id, garment: garment, layer: layer);
    notifyListeners();
  }

  CharacterElement? get hairCharacter {
    if (!_editHair) return null;
    var id = drawingOn ?? (_selection.length == 1 ? _selection.first : null);
    var e = id == null ? null : _document.elementById(id);
    return e is CharacterElement && !e.body.inThreeD && e.visible && e.dna.hairRig != null
        ? e
        : null;
  }

  /// hairAddLocks is whether a press on the head while its hair is shaped
  /// grows a new lock there -- dragged out to its tip -- over the hair
  /// already there or not, rather than taking hold of what is under it;
  /// hairLockWidth how wide a lock grown so is at its root, in head heights.
  bool get hairAddLocks => _hairAddLocks;
  bool _hairAddLocks = false;
  set hairAddLocks(bool on) {
    if (_hairAddLocks == on) return;
    _hairAddLocks = on;
    notifyListeners();
  }

  double get hairLockWidth => _hairLockWidth;
  double _hairLockWidth = 0.26;
  set hairLockWidth(double w) {
    if (_hairLockWidth == w) return;
    _hairLockWidth = w;
    notifyListeners();
  }

  int? get hairPick =>
      _hairPickOf != null && hairCharacter?.id == _hairPickOf ? _hairPick : null;
  int? _hairPick;
  String? _hairPickOf;
  void pickHair(int? i) {
    _hairPick = i;
    _hairPickOf = i == null ? null : hairCharacter?.id;
    if (i != null) _pickedCharacterLayer = BodyLayer.hairFront.name;
    notifyListeners();
  }

  /// deleteHairStroke takes the stroke picked away, returning whether there
  /// was one.
  bool deleteHairStroke() {
    var i = hairPick, e = hairCharacter;
    var hair = e?.dna.hairRig;
    if (i == null || e == null || hair == null || i >= hair.strokes.length) return false;
    replaceElement(e.copyWith(dna: e.dna.copyWith(hairRig: hair.without(i))));
    _hairPick = null;
    notifyListeners();
    return true;
  }

  /// editFace shows a sketch's face feature by feature, to set on the
  /// panel it is seen from -- see character_face_rig_editor.dart. For this
  /// run of the app.
  bool get editFace => _editFace;
  bool _editFace = false;
  set editFace(bool on) {
    if (_editFace == on) return;
    _editFace = on;
    _facePick = null;
    notifyListeners();
  }

  /// faceCharacter is the sketch whose face is set: the one drawn on, or
  /// picked alone.
  CharacterElement? get faceCharacter {
    if (!_editFace) return null;
    var id = drawingOn ?? (_selection.length == 1 ? _selection.first : null);
    var e = id == null ? null : _document.elementById(id);
    return e is CharacterElement && !e.body.inThreeD && e.visible ? e : null;
  }

  /// facePick is the feature picked, while the face is set: what Delete
  /// puts back. Picking another character is not picking its feature.
  FacePoint? get facePick =>
      _facePickOf != null && faceCharacter?.id == _facePickOf ? _facePick : null;
  FacePoint? _facePick;
  String? _facePickOf;
  void pickFacePoint(FacePoint? p) {
    _facePick = p;
    _facePickOf = p == null ? null : faceCharacter?.id;
    // Its layer picked, for its settings beside it.
    if (p != null) {
      _pickedCharacterLayer = switch (p) {
        FacePoint.eyeL || FacePoint.eyeR => BodyLayer.eyes.name,
        FacePoint.browL || FacePoint.browR => BodyLayer.brows.name,
        FacePoint.nose => BodyLayer.nose.name,
        _ => BodyLayer.mouth.name,
      };
    }
    notifyListeners();
  }

  /// putFacePointBack puts the feature picked back as it was on the panel
  /// seen, returning whether there was one.
  bool putFacePointBack() {
    var p = facePick, e = faceCharacter;
    if (p == null || e == null) return false;
    replaceElement(withFacePointBack(e, p, _frame, mirror: _mirrorEdits,
        frameRate: math.max(1, _document.frameRate)));
    _facePick = null;
    notifyListeners();
    return true;
  }

  /// puppetHandles is whether the puppet's handles and pins can be taken
  /// hold of: always, but while drawing only with a select tool in hand,
  /// so the pen and pencil draw across them.
  bool get puppetHandles =>
      drawingOn == null ||
      _vectorTool == VectorTool.select ||
      _vectorTool == VectorTool.selectShapes;

  /// _proxyOver and _proxyFrame are the character, as it was, and the frame
  /// the stand-in was laid out for: either changed -- a pose, a turn to
  /// another panel, the playhead moved -- and it is laid out again.
  CharacterElement? _proxyOver;
  int _proxyFrame = -1;

  /// drawingGarment is which of the character's wardrobe is being drawn
  /// on, or null for the character itself.
  int? get drawingGarment => drawingOn == null ? null : _drawingGarment;
  int? _drawingGarment;

  /// drawingLayer is the body layer being drawn on -- its shapes alone on
  /// the drawing laid over the character -- or null for all of them.
  String? get drawingLayer => drawingOn == null ? null : _drawingLayer;
  String? _drawingLayer;

  /// drawOnCharacter starts drawing on the sketched character [id], on the
  /// panel it is seen from where the playhead is -- or, with [garment], on
  /// that garment of its wardrobe: each shape on the part of the body it
  /// covers under it.
  ///
  /// With [layer], a layer of the character: a garment's is that garment;
  /// a body layer's shapes are drawn on alone, as that layer.
  void drawOnCharacter(String id, {int? garment, String? layer}) {
    var c = _document.elementById(id);
    if (c is! CharacterElement || c.body.inThreeD) return;
    if (layer != null) {
      garment ??= garmentOfLayer(layer);
      if (garment != null) layer = null;
    }
    if (garment != null && (garment < 0 || garment >= c.dna.wardrobe.length)) return;
    if (drawingOn == id && _drawingGarment == garment && _drawingLayer == layer) return;
    // From one to the other, the first put down.
    if (drawingOn != null) {
      selectOnly(drawingOn!);
      _keepDrawingProxy();
    }
    stopVectorTyping();
    _fitEditedVector();
    _drawingGarment = garment;
    _drawingLayer = layer;
    // What is drawn on it taken as it is shown -- its edits carried onto
    // the character as it is now -- for the tools to edit what is seen.
    c = rebasedCharacter(c, _frame, math.max(1, _document.frameRate));
    var proxy = drawingProxy(c, _frame, math.max(1, _document.frameRate),
        garment: garment, layer: layer);
    var next = _document.withElement(c).removeElement(proxy.id).addElement(proxy);
    next = next.reorder(next.elements.length - 1, next.indexOf(id) + 1);
    _vectorEditing = proxy.id;
    _resetVectorEditing();
    // Ready to pick: what is drawn there is the thing to work on first.
    _vectorTool = VectorTool.select;
    // The hair's base is one shape: picked, its points out, and the pencil
    // in its colour, so what is drawn adds to it -- a bold lock, a lower
    // hairline -- and the eraser takes from it.
    if (layer == BodyLayer.hairBase.name && proxy.shapes?.length == 1) {
      _vectorShape = 0;
      if (proxy.shapes!.first.fill case var fill?) _vectorPencilColour = fill;
    }
    _selection = {proxy.id};
    _backgroundSelected = false;
    _proxyOver = c;
    _proxyFrame = _frame;
    // Not a change of its own to undo: only what is drawn is.
    apply(next, transient: true);
    notifyListeners();
  }

  /// drawnTakenApart is whether what is drawn on -- the character, or the
  /// garment of it -- is taken apart into shapes on the panel seen, to edit
  /// point by point. See takeApartPanel.
  bool get drawnTakenApart {
    var id = drawingOn;
    var c = id == null ? null : _document.elementById(id);
    if (c is! CharacterElement) return false;
    var key = drawnKey(c, _frame, math.max(1, _document.frameRate));
    if (_drawingLayer case var layer?) return isLayerTakenApart(c, layer, key);
    return isTakenApart(c, key, garment: _drawingGarment);
  }

  /// layerTakenApart is whether [layer] of character [id] is drawn by its
  /// shapes on the panel seen where the playhead is.
  bool layerTakenApart(String id, String layer) {
    var c = _document.elementById(id);
    if (c is! CharacterElement || c.body.inThreeD) return false;
    return isLayerTakenApart(c, layer, drawnKey(c, _frame, math.max(1, _document.frameRate)));
  }

  /// takeApartCharacterLayer takes [layer] of character [id] apart on the
  /// panel seen where the playhead is, alone -- see takeApartLayer -- and
  /// putCharacterLayerBack draws it there as it is made again.
  void takeApartCharacterLayer(String id, String layer) {
    var c = _document.elementById(id);
    if (c is! CharacterElement || c.body.inThreeD) return;
    replaceElement(takeApartLayer(c, layer, _frame, math.max(1, _document.frameRate)));
  }

  /// keyCharacterLayer shapes [layer] of character [id] by slider [look]
  /// through keyforms on the panel seen -- see LayerKeys -- or, with null,
  /// stops. addKeyform keeps one at the slider's value now; removeKeyform
  /// takes the one at [value] away; goToKeyform sets the slider to it.
  void keyCharacterLayer(String id, String layer, String? look) {
    var c = _document.elementById(id);
    if (c is! CharacterElement) return;
    var rate = math.max(1, _document.frameRate);
    replaceElement(look == null
        ? unkeyLayer(c, layer, _frame, rate)
        : keyLayer(unkeyLayer(c, layer, _frame, rate), layer, look, _frame, rate));
  }

  void addKeyform(String id, String layer) {
    var c = _document.elementById(id);
    if (c is! CharacterElement) return;
    replaceElement(withKeyform(c, layer, _frame, math.max(1, _document.frameRate)));
  }

  void removeKeyform(String id, String layer, double value) {
    var c = _document.elementById(id);
    if (c is! CharacterElement) return;
    replaceElement(withoutKeyform(c, layer, value, _frame, math.max(1, _document.frameRate)));
  }

  void goToKeyform(String id, String look, double value) {
    var c = _document.elementById(id);
    var l = Look.fromName(look);
    if (c is! CharacterElement || l == null) return;
    replaceElement(c.copyWith(dna: c.dna.copyWith(look: c.dna.look.withValue(l, value))));
  }

  void putCharacterLayerBack(String id, String layer) {
    var c = _document.elementById(id);
    if (c is! CharacterElement) return;
    replaceElement(putLayerBack(c, layer, _frame, math.max(1, _document.frameRate)));
  }

  /// takeApartCharacter takes the panel of character [id] seen where the
  /// playhead is apart into shapes -- or, with [garment], that garment of
  /// it -- for the drawing tools to edit point by point.
  void takeApartCharacter(String id, {int? garment}) {
    var c = _document.elementById(id);
    if (c is! CharacterElement || c.body.inThreeD) return;
    var rate = math.max(1, _document.frameRate);
    // Drawing on one layer: that layer.
    if (garment == null && drawingOn == id && _drawingLayer != null) {
      replaceElement(takeApartLayer(c, _drawingLayer!, _frame, rate));
      return;
    }
    replaceElement(garment == null
        ? takeApartPanel(c, _frame, rate)
        : takeApartGarment(c, garment, _frame, rate));
  }

  /// putCharacterBack draws the panel of character [id] seen where the
  /// playhead is as it is made again -- or, with [garment], that garment.
  void putCharacterBack(String id, {int? garment}) {
    var c = _document.elementById(id);
    if (c is! CharacterElement) return;
    replaceElement(putPanelBack(c, _frame, math.max(1, _document.frameRate),
        garment: garment));
  }

  /// stopDrawingOnCharacter puts the drawing tools down, the character
  /// picked again.
  void stopDrawingOnCharacter() {
    var id = drawingOn;
    if (id == null) return;
    selectOnly(id);
  }

  /// _drawnOnCharacter is [next] with what was drawn on the stand-in since
  /// the document before it taken into the character.
  CanvasDocument _drawnOnCharacter(CanvasDocument next) {
    var id = _vectorEditing;
    var cid = id == null ? null : drawnCharacterOf(id);
    if (id == null || cid == null) return next;
    var proxy = next.elementById(id), before = _document.elementById(id);
    var c = next.elementById(cid);
    if (proxy is! VectorElement ||
        before is! VectorElement ||
        c is! CharacterElement) {
      return next;
    }
    if (identical(proxy, before) || proxy.shapes == before.shapes) return next;
    var drawn = drawnFromProxy(
        c, proxy, _frame, math.max(1, _document.frameRate),
        before: before, garment: _drawingGarment, layer: _drawingLayer);
    _proxyOver = drawn;
    _proxyFrame = _frame;
    return next.withElement(drawn);
  }

  /// _keepDrawingProxy keeps the stand-in for the character being drawn on
  /// laid over it as it is, and takes away any left with nothing being
  /// drawn: a drawing put down, or an undo back to while it was.
  void _keepDrawingProxy() {
    var id = _vectorEditing;
    var cid = id == null ? null : drawnCharacterOf(id);
    if (cid == null) {
      if (_document.elements.any((e) => isDrawingProxy(e.id))) {
        _document = _document.copyWith(elements: [
          for (var e in _document.elements)
            if (!isDrawingProxy(e.id)) e
        ]);
      }
      _proxyOver = null;
      _drawingGarment = null;
      _drawingLayer = null;
      return;
    }
    var c = _document.elementById(cid);
    if (c is! CharacterElement) return;
    if (identical(c, _proxyOver) && _frame == _proxyFrame) return;
    var at = _document.elementById(id!);
    // A garment taken off while it was drawn on: nothing left to draw on.
    if (_drawingGarment case var g? when g >= c.dna.wardrobe.length) {
      _drawingGarment = null;
    }
    var proxy = drawingProxy(c, _frame, math.max(1, _document.frameRate),
        garment: _drawingGarment, layer: _drawingLayer);
    if (at is VectorElement) {
      _document = _document.withElement(proxy);
    }
    _proxyOver = c;
    _proxyFrame = _frame;
  }

  /// editingVector is the drawing being edited, where there is one and it has
  /// been taken apart -- which editing it always has. See startVectorEditing.
  VectorElement? get editingVector {
    var id = _vectorEditing;
    var e = id == null ? null : _document.elementById(id);
    return e is VectorElement && e.edited ? e : null;
  }

  /// editVector starts editing the drawing [id], or stops with null.
  void editVector(String? id) {
    if (_vectorEditing == id) return;
    // A character's drawing is laid over it to be edited -- see
    // drawOnCharacter -- and put down, the character is picked again.
    var drawn = id == null ? null : drawnCharacterOf(id);
    if (drawn != null && _document.elementById(id!) == null) {
      drawOnCharacter(drawn);
      return;
    }
    var putDown = id == null ? drawingOn : null;
    stopVectorTyping();
    _fitEditedVector();
    _vectorEditing = id;
    _resetVectorEditing();
    // Edited is selected: the drawing being edited is the one thing picked,
    // so the settings beside it are its own. See notifyListeners.
    if (id != null) {
      _selection = {id};
      _backgroundSelected = false;
    } else if (putDown != null && _document.elementById(putDown) != null) {
      _selection = {putDown};
      _backgroundSelected = false;
    }
    notifyListeners();
  }

  void _resetVectorEditing() {
    if (_vectorSolo) {
      _vectorSolo = false;
      if (vectorSoloOf == _soloOf) vectorSoloOf = null;
    }
    _vectorItems = const {};
    _lastSelect = VectorTool.select;
    _vectorShape = -1;
    _vectorPicks = const {};
    _vectorTool = VectorTool.select;
    _vectorPenFrom = null;
    _vectorCombining = const {};
    _vectorShapeMade = -1;
  }

  /// vectorItems is what the select shapes tool has picked: whole shapes,
  /// and pieces of cut ones. See VectorItem.
  Set<VectorItem> get vectorItems {
    var e = editingVector;
    if (e == null) return const {};
    return liveItems(e, _vectorItems);
  }

  Set<VectorItem> _vectorItems = const {};

  /// pickVectorItem picks [item] alone -- or, with [toggle], adds it to
  /// what is picked or takes it out; null lets everything go.
  void pickVectorItem(VectorItem? item, {bool toggle = false}) {
    if (item == null) {
      _vectorItems = const {};
    } else if (toggle) {
      var next = {...vectorItems};
      if (!next.remove(item)) next.add(item);
      _vectorItems = next;
    } else {
      _vectorItems = {item};
    }
    // The shape's own settings follow the last one picked.
    _vectorShape = item?.shape ?? -1;
    _vectorPicks = const {};
    notifyListeners();
  }

  /// vectorAlignsShapes is whether the align tool lines up shapes -- the
  /// select shapes tool was the last select tool used -- or points.
  bool get vectorAlignsShapes => _lastSelect == VectorTool.selectShapes;

  /// _picksShapes is whether what is picked is shapes rather than points:
  /// the select shapes tool, or the align tool after it.
  bool get _picksShapes =>
      _vectorTool == VectorTool.selectShapes ||
      (_vectorTool == VectorTool.align && vectorAlignsShapes);

  /// pickVectorItems picks [items] -- or, with [add], adds them.
  void pickVectorItems(Set<VectorItem> items, {bool add = false}) {
    _vectorItems = add ? {...vectorItems, ...items} : {...items};
    _vectorShape = items.isEmpty ? _vectorShape : items.first.shape;
    _vectorPicks = const {};
    notifyListeners();
  }

  VectorTool _lastSelect = VectorTool.select;

  /// alignVectorItems lines the shapes picked up as [how] says.
  void alignVectorItems(VectorAlign how) {
    var e = editingVector;
    var items = vectorItems.toList();
    if (e == null || items.length < 2) return;
    replaceElement(withItemsAligned(e, items, how));
  }

  /// vectorSelectedShapes is the shapes picked -- each the first of its
  /// run of combined shapes -- whichever select tool picked them: what the
  /// tint, the rub-out and the pencil work on, where any are. Empty for
  /// none, when they work on whatever they go over.
  Set<int> get vectorSelectedShapes {
    var e = editingVector;
    if (e == null) return const {};
    var items = vectorItems;
    if (items.isNotEmpty) return {for (var i in items) groupOf(e, i.shape)};
    if (_vectorShape >= 0 && _vectorShape < (e.shapes?.length ?? 0)) {
      return {groupOf(e, _vectorShape)};
    }
    return const {};
  }

  void pickVectorShape(int shape) {
    if (_vectorShape == shape && _vectorPicks.isEmpty) return;
    _vectorShape = shape;
    _vectorPicks = const {};
    notifyListeners();
  }

  /// pickVectorPoint picks [pick] alone -- or, with [toggle], adds it to the
  /// points picked or takes it out, which is Shift and a click.
  void pickVectorPoint(VectorPick? pick, {bool toggle = false}) {
    Set<VectorPick> next;
    if (pick == null) {
      next = const {};
    } else if (toggle) {
      next = {..._vectorPicks};
      if (!next.remove(pick)) next.add(pick);
    } else {
      next = {pick};
    }
    if (setEquals(next, _vectorPicks)) return;
    _vectorPicks = next;
    if (pick != null) _vectorShape = pick.shape;
    notifyListeners();
  }

  /// pickVectorPoints picks [picks], all at once: a box dragged across the
  /// drawing.
  void pickVectorPoints(Set<VectorPick> picks) {
    _vectorPicks = {...picks};
    if (picks.isNotEmpty) _vectorShape = picks.first.shape;
    notifyListeners();
  }

  /// deleteVectorPoint takes out the points picked in the drawing being
  /// edited, returning whether there were any to take.
  bool deleteVectorPoint() {
    var e = editingVector, picks = _vectorPicks;
    if (e == null) return false;
    // A shape picked whole, with no points: every point of it.
    if (picks.isEmpty && _vectorShape >= 0) {
      var shape = e.shapes?.elementAtOrNull(_vectorShape);
      if (shape != null) {
        picks = {
          for (var (p, run) in shape.paths.indexed)
            for (var n = 0; n < run.nodes.length; n++)
              VectorPick(_vectorShape, p, n),
        };
      }
    }
    if (picks.isEmpty) return false;
    var next = withoutPoints(e, picks);
    _vectorPicks = const {};
    _vectorPenFrom = null;
    if ((next.shapes?.length ?? 0) < (e.shapes?.length ?? 0)) {
      _vectorShape = -1;
    }
    replaceElement(next);
    return true;
  }

  /// _leaveVectorIfUnpicked stops editing a drawing that is no longer the one
  /// selected: picking something else is how editing is finished.
  void _leaveVectorIfUnpicked() {
    var id = _vectorEditing;
    if (id == null) return;
    if (_selection.length == 1 && _selection.first == id) return;
    _fitEditedVector();
    _vectorEditing = null;
    _resetVectorEditing();
  }

  /// _fitEditedVector grows the box of the drawing being left to take in
  /// whatever the editing carried out past it, so the box drawn round it is
  /// round all of it. See boxedToDrawing.
  void _fitEditedVector() {
    var e = editingVector;
    // A character's stand-in is its box exactly, and is thrown away.
    if (e == null || isDrawingProxy(e.id)) return;
    var fitted = boxedToDrawing(e);
    if (identical(fitted, e)) return;
    apply(_document.withElement(fitted));
  }

  void selectOnly(String id) {
    if (_selection.length == 1 &&
        _selection.first == id &&
        !_backgroundSelected &&
        _offCanvas.isEmpty) {
      return;
    }
    _backgroundSelected = false;
    _offCanvas = const {};
    _selection = {id};
    _leaveVectorIfUnpicked();
    _focusedPlayer = null;
    notifyListeners();
  }

  /// selectMany picks out a set at once, for the things that work on several
  /// -- the alignment tools, and a sweep over empty space.
  void selectMany(Set<String> ids) {
    _backgroundSelected = false;
    _offCanvas = const {};
    _selection = {...ids};
    _leaveVectorIfUnpicked();
    _focusedPlayer = null;
    notifyListeners();
  }

  void toggleSelected(String id) {
    _backgroundSelected = false;
    _selection = {..._selection};
    _selection.contains(id) ? _selection.remove(id) : _selection.add(id);
    notifyListeners();
  }

  /// clipSelection is every clip picked on the timeline: the selection, and
  /// the clips picked that are on another canvas -- another scene's, or the
  /// master's seen from a scene -- which the timeline can reach while every
  /// scene plays. They are not in the selection, which is only ever the
  /// canvas in front of the reader; picked, they are lit and moved with the
  /// rest all the same.
  Set<String> get clipSelection =>
      _offCanvas.isEmpty ? _selection : {..._selection, ..._offCanvas};
  Set<String> _offCanvas = const {};

  bool _onCanvas(String id) => _document.indexOf(id) >= 0;

  /// pickClip picks the clip [id] on the timeline, wherever it is -- or,
  /// with [toggle], adds it to what is picked or takes it out.
  void pickClip(String id, {bool toggle = false}) {
    if (_onCanvas(id)) {
      toggle ? toggleSelected(id) : selectOnly(id);
      return;
    }
    if (toggle) {
      var next = {..._offCanvas};
      if (!next.remove(id)) next.add(id);
      _offCanvas = next;
    } else {
      _backgroundSelected = false;
      _focusedPlayer = null;
      _selection = {};
      _offCanvas = {id};
    }
    notifyListeners();
  }

  /// pickedClip is the one clip picked on the timeline from another canvas
  /// -- the master's music, seen from a scene -- when it is the only thing
  /// picked, so its settings can be shown and changed from here.
  CanvasElement? get pickedClip {
    if (_selection.isNotEmpty || _offCanvas.length != 1) return null;
    var id = _offCanvas.single;
    CanvasElement? found;
    _everyElement(_document, (e, _) {
      if (e.id == id) found = e;
      return e;
    });
    return found;
  }

  /// replaceAnywhere changes element [next] wherever it is -- this canvas,
  /// the master or another scene.
  void replaceAnywhere(CanvasElement next, {bool transient = false}) {
    var doc = _replacedAnywhere(_document, next);
    if (doc == null) return;
    apply(doc, transient: transient);
  }

  /// pickClips picks [ids] on the timeline, wherever each one is: a box
  /// dragged across the lanes.
  void pickClips(Set<String> ids) {
    _backgroundSelected = false;
    _focusedPlayer = null;
    _selection = {
      for (var id in ids)
        if (_onCanvas(id)) id
    };
    _offCanvas = {
      for (var id in ids)
        if (!_onCanvas(id)) id
    };
    notifyListeners();
  }

  // ---- scenes -------------------------------------------------------------

  /// playAll is whether Play runs the whole document or the scene in front of
  /// the reader.
  ///
  /// A mode rather than a second button, because it is the same act -- press
  /// play, watch it -- asked of two different things, and the answer is
  /// usually the same for a whole sitting: somebody building a scene plays
  /// the scene, somebody checking the sequence plays the sequence.
  bool get playAll => _playAll;
  bool _playAll = false;

  set playAll(bool value) {
    if (_playAll == value) return;
    _playAll = value;
    // What is picked on other canvases is out of reach again with one scene.
    if (!value) _offCanvas = const {};
    pause();
    stopPreview();
    notifyListeners();
  }

  /// previewAt is the frame of the *whole run* the canvas is showing, or null
  /// when it is showing the scene being edited.
  ///
  /// How a transition is watched: the stage draws the sequence rather than
  /// the scene, so what is seen is what will be published -- the same
  /// function, not a second one that agrees for now. See paintSequenceFrame.
  int? get previewAt => _previewAt;
  int? _previewAt;

  /// previewEnd is where the preview stops. Kept so that watching a
  /// transition does not run on through the rest of the document.
  int _previewEnd = 0;

  /// _previewFrom is the scene the preview was started on, so that watching a
  /// join leaves the editor where it was found. Somebody previewing the same
  /// join twice should not have to walk back to it in between.
  int? _previewFrom;

  /// _previewFromMaster is whether the shared canvas was the one open when
  /// the preview started, so that watching a join puts it back rather than
  /// leaving the reader on whichever scene the playhead stopped in.
  bool _previewFromMaster = false;

  /// previewTransitionAfter plays the join between a scene and the next one:
  /// a little of the scene before it, the transition, and a little of the
  /// scene after.
  void previewTransitionAfter(int index) {
    var document = _document;
    var scenes = document.allScenes;
    if (scenes.length < 2) return;

    // On the shared canvas the bar is editing the default every scene starts
    // from, and there is no "this scene" for it to be after -- so the first
    // join stands for all of them. Asked for the join after whatever scene
    // was last open, the button did nothing at all whenever that was the last
    // scene, which is what made it seem temperamental.
    if (document.editingMaster) index = 0;
    if (index < 0 || index >= scenes.length - 1) return;

    var over = document.transitionAfter(index);
    var start = document.startOfScene(index + 1);
    // A little of the scene being left, then the join, then a little of the
    // one arriving. Started at the join itself, as it was, a short transition
    // began before the eye had anything to compare it with -- which is the
    // one thing a preview is for.
    var lead = math.max(6, (document.frameRate * 0.4).round());
    _previewFrom = document.at;
    _previewFromMaster = document.editingMaster;
    _previewAt = math.max(0, start - over.overlap - lead);
    _previewEnd =
        math.min(document.sequenceFrames - 1, start + over.frames + lead);
    _startTimer();
    notifyListeners();
  }

  /// stopPreview puts the canvas back on the scene being edited.
  void stopPreview() {
    if (_previewAt == null) return;
    _previewAt = null;
    pause();
    // Back to the canvas it was started from. Playing the document walks the
    // editor through the scenes -- see _tick -- so without this, watching a
    // join left the reader two scenes further on than they were.
    var back = _previewFrom;
    var wasMaster = _previewFromMaster;
    _previewFrom = null;
    _previewFromMaster = false;
    if (back != null && back != _document.at) {
      _document = _document.goToScene(back);
      _frame = _frame.clamp(0, math.max(0, _document.frames - 1)).toInt();
      _audioFollowsPage(turned: true);
    }
    // And back onto the shared canvas where that is where it started: the
    // playhead walks the scenes while a join is watched, and returning to a
    // scene would leave somebody editing the master looking at scene one.
    if (wasMaster && !_document.editingMaster) {
      _document = _document.copyWith(onMaster: true);
      _frame = _frame.clamp(0, math.max(0, _document.frames - 1)).toInt();
    }
    notifyListeners();
  }

  /// scenes are the canvases this document plays, in order.
  List<CanvasScene> get scenes => _document.allScenes;

  /// setSceneFrames sets how many frames several scenes have, as one change:
  /// the scene strip's drag between two scenes, which gives one what it takes
  /// from the other. Each is held to at least one frame.
  void setSceneFrames(Map<int, int> lengths, {bool transient = false}) {
    var next = _document;
    for (var entry in lengths.entries) {
      var list = next.allScenes;
      if (entry.key < 0 || entry.key >= list.length) continue;
      var frames = entry.value.clamp(1, maxFrameCount).toInt();
      if (list[entry.key].frames == frames) continue;
      next =
          next.withScene(entry.key, list[entry.key].copyWith(frames: frames));
    }
    apply(next, transient: transient);
  }

  /// setSceneLength sets the length of the scene being edited -- the
  /// timeline's Length field.
  void setSceneLength(int frames, {bool transient = false}) =>
      apply(_document.copyWith(frames: frames), transient: transient);

  // ------------------------------------------------------------------------
  // Cues -- see canvas_cues.dart.

  /// cues are the run's named moments, in order.
  List<TimelineCue> get cues => _document.cues;

  /// runFrame is the playhead as a frame of the whole run.
  int get runFrame => _document.editingMaster
      ? _frame
      : _document.startOfScene(_document.at) + _frame;

  /// addCue puts a cue at [frame] of the run, the playhead's by default.
  TimelineCue addCue({String name = "", int? frame}) {
    var cue = TimelineCue(
        id: newCueId(),
        name: name.isEmpty ? "Cue ${cues.length + 1}" : name,
        frame: math.max(0, frame ?? runFrame));
    apply(_document.copyWith(cues: _sortedCues([...cues, cue])));
    return cue;
  }

  void renameCue(String id, String name) => apply(_document.copyWith(cues: [
        for (var c in cues) c.id == id ? c.copyWith(name: name) : c,
      ]));

  /// moveCue puts cue [id] at [frame] of the run, and every element tied to
  /// it moves by as much -- its keyframes, wherever in the run it is.
  void moveCue(String id, int frame, {bool transient = false}) {
    var cue = cues.where((c) => c.id == id).firstOrNull;
    if (cue == null) return;
    frame = math.max(0, frame);
    var by = frame - cue.frame;
    if (by == 0) return;
    var next = _document.copyWith(
        cues: _sortedCues([
      for (var c in cues) c.id == id ? c.copyWith(frame: frame) : c,
    ]));
    next = _everyElement(next, (e, start) {
      if (e.base.cue != id) return e;
      var track = e.base.track;
      if (track == null || track.isEmpty) return e;
      return e.withBase(track: _shifted(track, by));
    });
    apply(next, transient: transient);
  }

  /// removeCue takes cue [id] away, and lets go of everything tied to it.
  void removeCue(String id) {
    var next = _document.copyWith(cues: [
      for (var c in cues)
        if (c.id != id) c,
    ]);
    apply(_everyElement(
        next, (e, _) => e.base.cue == id ? e.withBase(cue: "") : e));
  }

  /// cueTo ties element [id] to cue [cueId], or lets it go with null.
  ///
  /// Tying moves the element's keyframes so that the first of them lands on
  /// the cue: an arrival laid down anywhere then starts on the line it was
  /// meant for, and stays with it from then on.
  void cueTo(String id, String? cueId) {
    var cue =
        cueId == null ? null : cues.where((c) => c.id == cueId).firstOrNull;
    apply(_everyElement(_document, (e, start) {
      if (e.id != id) return e;
      if (cue == null) return e.withBase(cue: "");
      var track = e.base.track;
      if (track == null || track.isEmpty) return e.withBase(cue: cue.id);
      var by = cue.frame - start - track.keys.first.frame;
      return e.withBase(cue: cue.id, track: _shifted(track, by));
    }));
  }

  /// findCues puts a cue wherever the voice on [clip] starts a line after a
  /// pause, and says how many it found. Cues it found before on the same
  /// clip are replaced; cues added by hand are left alone.
  Future<int> findCues(AudioElement clip) async {
    var source = clip.clip.playlist.firstOrNull;
    if (source == null) return 0;
    var peaks = await _waveformOf(source.assetId);
    if (peaks == null) return 0;
    var rate = math.max(1, _document.frameRate);
    var length = source.length > 0 ? source.length : 0.0;
    if (length <= 0) return 0;
    // Where the clip's own time starts in the run: on the master its frame
    // is the run's; on a scene, it is counted from that scene's start.
    var offset = 0;
    for (var (i, scene) in _document.allScenes.indexed) {
      if (scene.elements.any((e) => e.id == clip.id)) {
        offset = _document.startOfScene(i);
      }
    }
    var from = source.start, to = source.end > 0 ? source.end : length;
    var tag = "voice:${clip.id}";
    var found = [
      for (var t in speechStarts(peaks, length))
        if (t >= from && t < to)
          TimelineCue(
              id: "$tag:${newCueId()}",
              name: "",
              frame: offset + clip.clip.at + ((t - from) * rate).round()),
    ];
    var kept = [
      for (var c in cues)
        if (!c.id.startsWith("$tag:")) c,
    ];
    var named = [
      for (var (i, c) in found.indexed) c.copyWith(name: "Line ${i + 1}"),
    ];
    apply(_document.copyWith(cues: _sortedCues([...kept, ...named])));
    return found.length;
  }

  /// words are what the voice-over says, where -- see SpokenWord.
  List<SpokenWord> get words => _document.words;

  /// hearWords listens to the voice on [clip] and keeps what it says, word
  /// by word, then names the clip's cues by the words they start on -- and
  /// finds those cues first if it has none. Null when it worked; otherwise
  /// what stopped it, said for the reader.
  ///
  /// [model] is where the speech model is, when the caller has just fetched
  /// it somewhere other than its usual place.
  Future<String?> hearWords(AudioElement clip, {String? model}) async {
    var source = clip.clip.playlist.firstOrNull;
    if (source == null) return "That sound has nothing in it to hear.";
    var whisper = await whisperPath();
    if (whisper == null) return speechHelp;
    var ffmpeg = await ffmpegPath();
    if (ffmpeg == null) return ffmpegHelp;
    model ??= await speechModelPath();
    if (!await File(model).exists()) return speechModelMissing;
    var file = await CanvasMedia.existingPath(MediaKind.audio, source.assetId);
    if (file == null) return "The recording is missing from the library.";

    var rate = math.max(1, _document.frameRate);
    var length = source.length > 0 ? source.length : 0.0;
    var from = source.start, to = source.end > 0 ? source.end : length;
    var heard = await listenTo(
        whisper: whisper,
        ffmpeg: ffmpeg,
        model: model,
        audio: file,
        from: from,
        to: to > from ? to : null);
    if (heard == null) return "whisper could not hear that recording.";
    if (heard.isEmpty) return "No words were heard in that recording.";

    var offset = _clipOffset(clip);
    var tag = "voice:${clip.id}";
    var said = [
      for (var w in heard)
        SpokenWord(
            text: w.text,
            frame: offset + clip.clip.at + (w.start * rate).round(),
            end: offset + clip.clip.at + (w.end * rate).round(),
            from: tag),
    ];
    if (!cues.any((c) => c.id.startsWith("$tag:"))) await findCues(clip);
    var all = [
      for (var w in words)
        if (w.from != tag) w,
      ...said,
    ]..sort((a, b) => a.frame.compareTo(b.frame));

    // Each of this clip's cues is named by what is said from it to the next.
    var mine = [
      for (var c in cues)
        if (c.id.startsWith("$tag:")) c,
    ];
    var named = <String, String>{};
    for (var (i, c) in mine.indexed) {
      var until = i + 1 < mine.length ? mine[i + 1].frame : 1 << 30;
      // A third of a second's lead: see saidBetween.
      var name = saidBetween(said, c.frame, until, lead: (rate / 3).round());
      if (name.isNotEmpty) named[c.id] = name;
    }
    apply(_document.copyWith(words: all, cues: [
      for (var c in cues)
        named[c.id] == null ? c : c.copyWith(name: named[c.id]),
    ]));
    return null;
  }

  /// _clipOffset is where [clip]'s own time starts in the run: on the master
  /// its frames are the run's; on a scene, they count from that scene's
  /// start.
  int _clipOffset(CanvasElement clip) {
    for (var (i, scene) in _document.allScenes.indexed) {
      if (scene.elements.any((e) => e.id == clip.id)) {
        return _document.startOfScene(i);
      }
    }
    return 0;
  }

  /// dimOthers fades everything already on the canvas down to [to] of
  /// itself as element [id] arrives, over [over] frames, and leaves it
  /// there: the next beat of an argument taking the light while the last
  /// one stays readable. Says how many it dimmed. One step to undo.
  ///
  /// "Down to", not "by": an element dimmed for the last beat is already
  /// there, and fading it again for this one would sink it out of sight
  /// two beats on. What has not arrived yet, or has gone, is left alone,
  /// and so are the things that are not drawn -- a sound, the backdrop.
  int dimOthers(String id, {double to = 0.3, int over = 12}) {
    var me = _document.elements.where((e) => e.id == id).firstOrNull;
    if (me == null) return 0;
    var arrival = bandsIn(me.base.track)
        .where((b) => b.channel == KeyframeChannel.reveal)
        .firstOrNull;
    var at = arrival?.from ?? me.base.track?.keys.firstOrNull?.frame ?? _frame;

    var dimmed = 0;
    CanvasElement dim(CanvasElement e) {
      if (e.id == id || !e.base.visible) return e;
      if (e is AudioElement || e is BackgroundElement) return e;
      var track = e.base.track ?? ElementTrack.empty;
      var bands = bandsIn(track);
      var comes =
          bands.where((b) => b.channel == KeyframeChannel.reveal).firstOrNull;
      if (comes != null && comes.from >= at) return e;
      var goes =
          bands.where((b) => b.channel == KeyframeChannel.close).firstOrNull;
      if (goes != null && goes.to <= at) return e;
      if (track.at(at).opacity <= to) return e;

      var start = track.keyAt(at) ??
          track.restingAt(at).copyWith(easing: KeyframeEasing.easeInOut);
      var end = track.keyAt(at + over) ?? track.restingAt(at + over);
      var keys = <Keyframe>[
        for (var k in track.keys)
          if (k.frame < at) k,
        start,
        for (var k in track.keys)
          if (k.frame > at && k.frame != at + over)
            k.copyWith(opacity: math.min(k.opacity, to)),
        end.copyWith(opacity: math.min(end.opacity, to)),
      ];
      dimmed++;
      return e.withBase(track: ElementTrack(keys));
    }

    var next = _document;
    for (var e in _document.elements) {
      var changed = dim(e);
      if (!identical(changed, e)) next = next.withElement(changed);
    }
    if (dimmed > 0) apply(next);
    return dimmed;
  }

  /// wordQuery is what is being looked for among the words, from an
  /// element's cue card -- this sitting's, never the document's.
  String _wordQuery = "";
  String get wordQuery => _wordQuery;
  set wordQuery(String v) {
    if (v == _wordQuery) return;
    _wordQuery = v;
    notifyListeners();
  }

  /// wordsMatching are the words that [query] is found in, ignoring case
  /// and punctuation, in the order they are said: at most [most].
  List<SpokenWord> wordsMatching(String query, {int most = 6}) {
    String plain(String s) =>
        s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9$.]+"), "");
    var q = plain(query);
    if (q.isEmpty) return const [];
    return [
      for (var w in words)
        if (plain(w.text).contains(q)) w,
    ].take(most).toList();
  }

  /// wordInContext is [word] with the words either side of it, which is
  /// what tells one "the" from the forty others.
  String wordInContext(SpokenWord word) {
    var i = words.indexOf(word);
    if (i < 0) return word.text;
    return [
      if (i > 0) words[i - 1].text,
      word.text,
      if (i + 1 < words.length) words[i + 1].text,
    ].join(" ");
  }

  /// cueOnWord ties element [id] to the moment [word] is said: to a cue
  /// already there, or to a new one named by the word. One step to undo.
  void cueOnWord(String id, SpokenWord word) {
    beginInteraction();
    var cue = cues.where((c) => c.frame == word.frame).firstOrNull ??
        addCue(name: word.text, frame: word.frame);
    cueTo(id, cue.id);
    endInteraction();
  }

  List<TimelineCue> _sortedCues(List<TimelineCue> list) =>
      [...list]..sort((a, b) => a.frame.compareTo(b.frame));

  /// _shifted is [track] moved [by] frames, never before the first frame.
  ElementTrack _shifted(ElementTrack track, int by) {
    var first = track.keys.first.frame;
    by = math.max(by, -first);
    return ElementTrack([
      for (var k in track.keys) k.copyWith(frame: k.frame + by),
    ]);
  }

  /// _everyElement is [doc] with [f] applied to every element of every
  /// scene and of the master. [f] is told the frame of the run its element's
  /// own frames count from.
  CanvasDocument _everyElement(CanvasDocument doc,
      CanvasElement Function(CanvasElement e, int start) f) {
    var scenes = [
      for (var (i, scene) in doc.allScenes.indexed)
        scene.copyWith(elements: [
          for (var e in scene.elements) f(e, doc.startOfScene(i)),
        ]),
    ];
    var next = doc.scenes.isEmpty
        ? doc
            .copyWith(
              onMaster: false,
              elements: scenes.single.elements,
            )
            .copyWith(onMaster: doc.onMaster)
        : doc.withScenes(scenes, at: doc.at);
    if (doc.master case var master?) {
      next = next.copyWith(
          master: master.copyWith(elements: [
        for (var e in master.elements) f(e, 0),
      ]));
    }
    return next;
  }

  /// _waveformOf is [assetId]'s shape, waited for.
  Future<Float32List?> _waveformOf(String assetId) async {
    for (var i = 0; i < 600; i++) {
      var peaks = waveformOf(assetId);
      if (peaks != null || _waveforms.containsKey(assetId)) return peaks;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }

  /// sceneAt is which one is being edited, and onMaster whether the shared
  /// canvas is showing instead of any of them.
  int get sceneAt => _document.at;
  bool get onMaster => _document.editingMaster;

  /// goToScene shows another canvas.
  ///
  /// Not an undo step: which scene you are looking at is where you are, not
  /// something you did to the document -- undo after moving about should take
  /// back the last edit, not walk backwards through the scenes it was made
  /// in. The selection goes with it, because the elements it names are on the
  /// canvas being left.
  void goToScene(int index) {
    var next = _document.goToScene(index).copyWith(onMaster: false);
    if (identical(next, _document)) return;
    if (!_document.editingMaster) _sceneFrames[_document.scene.id] = _frame;
    apply(next, transient: true);
    // Back where it was left. One playhead clamped to each scene in turn
    // lost a place in a long page to a visit to a short one, and a page
    // left part-way through came back somewhere else.
    if (_sceneFrames[_document.scene.id] case var kept?) _frame = kept;
    _afterSceneChange();
  }

  /// _sceneFrames is where the playhead was on each scene when it was last
  /// left, by scene id. Not in the document: it is where somebody is, not
  /// something they made.
  final Map<String, int> _sceneFrames = {};

  /// frameOn is the frame scene [index] is at: the playhead for the scene
  /// being edited, and for any other the frame it was left on -- or, for one
  /// not visited yet, the frame it would open on, which is the playhead's.
  ///
  /// What the facing page is drawn at. Drawn at a frame of its own choosing,
  /// a page left at the start of its chart's animation showed the chart
  /// finished as soon as the page beside it was opened.
  int frameOn(int index) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return _frame;
    var scene = list[index];
    var at = !_document.editingMaster && index == _document.at
        ? _frame
        : (_sceneFrames[scene.id] ?? _frame);
    return at.clamp(0, math.max(0, scene.frames - 1)).toInt();
  }

  /// showMaster puts the shared canvas in front of the reader, making one if
  /// there is none and switching it on if it is off: asking to edit the
  /// master is asking for a master.
  void showMaster() {
    var next = _document;
    if (next.master == null) {
      next =
          next.copyWith(master: CanvasScene(id: newSceneId(), name: "Master"));
    }
    apply(next.copyWith(masterOn: true, onMaster: true), transient: true);
    _afterSceneChange();
  }

  /// masterOn switches the shared canvas on and off. Off, it is kept: turning
  /// it off is not the same as throwing away what is on it.
  set masterOn(bool value) {
    if (_document.masterOn == value) return;
    var next = _document.copyWith(masterOn: value);
    if (!value && next.onMaster) next = next.copyWith(onMaster: false);
    apply(next);
    _afterSceneChange();
  }

  /// addScene puts a new canvas after the one being edited and goes to it.
  void addScene() {
    apply(_document.copyWith(onMaster: false).addScene(after: _document.at));
    _afterSceneChange();
  }

  void duplicateScene(int index) {
    apply(_document.copyWith(onMaster: false).duplicateScene(index));
    _afterSceneChange();
  }

  /// _sceneClipboard is the scene last copied, held the way an element's copy
  /// is: static, in memory, for as long as the app runs.
  ///
  /// Static is the point -- it is what makes a scene copied from one canvas
  /// paste into another, which is the whole reason the row has a Copy on it.
  /// Not the system clipboard, for the reason given on [_clipboard]: a canvas
  /// scene has no sensible text form, and putting JSON there would replace
  /// whatever the reader had copied from somewhere else.
  static CanvasScene? _sceneClipboard;

  /// hasCopiedScene is whether there is a scene waiting to be pasted.
  static bool get hasCopiedScene => _sceneClipboard != null;

  /// forgetCopiedScene empties it. For a test that needs to start from
  /// nothing copied, since the clipboard is deliberately static.
  @visibleForTesting
  static void forgetCopiedScene() => _sceneClipboard = null;

  /// copyScene takes a copy of one, to be pasted into this canvas or another.
  void copyScene(int index) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    _sceneClipboard = list[index];
    notifyListeners();
  }

  /// pasteScene puts the copied scene in after the one being looked at.
  ///
  /// A fresh scene and fresh elements rather than the copy itself: two
  /// documents sharing an id is two documents whose scenes cannot be told
  /// apart, and a paste into the canvas it was copied from would be a second
  /// row naming the first one's elements.
  void pasteScene() {
    var from = _sceneClipboard;
    if (from == null) return;
    var list = [..._document.allScenes];
    var at = (_document.sceneAt + 1).clamp(0, list.length).toInt();
    list.insert(
        at,
        from.copyWith(
          id: newSceneId(),
          elements: [for (var e in from.elements) e.withId(newElementId())],
        ));
    apply(_document.copyWith(onMaster: false).withScenes(list, at: at));
    _afterSceneChange();
  }

  /// setShape changes the shape of the page, keeping the layout of the shape
  /// being left.
  ///
  /// The one route a ratio change takes. Both shapes join the document's
  /// targets, which is what marks them in the ratio list and what a new
  /// element is laid out for -- a document that has been designed at two
  /// shapes is a responsive document, and there is nothing else it could
  /// mean. A document that has only ever been one shape keeps an empty list,
  /// so nothing is marked and nothing is carried.
  void setShape(CanvasSize next, {int? frameRate}) {
    var was = _document.size;
    if (shapeKey(was) == shapeKey(next) && frameRate == null) {
      apply(_document.copyWith(size: next));
      return;
    }
    var moved = _document.forShape(next);
    if (frameRate != null) moved = moved.copyWith(frameRate: frameRate);

    var targets = [...moved.targets];
    for (var key in [shapeKey(was), shapeKey(next)]) {
      if (!targets.contains(key)) targets.add(key);
    }
    apply(moved.copyWith(targets: targets.length > 1 ? targets : const []));
  }

  /// setKind is whether this document is scenes or pages.
  ///
  /// Not just a flag: choosing pages says what shape the canvas is, how fast
  /// it runs and what happens between two of them, and somebody who has said
  /// "this is a document" should not then have to say "and A4" and "and one
  /// frame a second" and "and a page turn". So the three follow -- but only
  /// where they have not been decided already: a canvas that is on A4 and is
  /// then called a document is a canvas somebody has already shaped, and a
  /// screen ratio chosen on purpose is not an oversight to be corrected.
  ///
  /// Nothing is undone on the way back. Called Scenes again, a document keeps
  /// its paper, its rate and its covers: they are all things that were true
  /// of it, and a switch that threw a layout away would be a switch nobody
  /// dared press twice.
  void setKind(CanvasKind kind) {
    if (_document.kind == kind) return;
    // What the size is estimated as follows what the document now is: a
    // piece of sound as its sound, anything else as its picture.
    var estimate = _document.estimate.copyWith(
        format: kind.isAudio
            ? EstimateAs.audio
            : _document.isAnimated
                ? EstimateAs.video
                : EstimateAs.png);
    if (kind != CanvasKind.pages) {
      if (kind.isAudio) _openSoundDesk();
      // A piece of sound counts its time in small steps, so a beat lands on
      // one -- where nothing is placed in time yet -- and going back to a
      // document of scenes goes back to a picture's rate, the same way. A
      // document with timing keeps its rate: frames are where things are,
      // and changing the rate under them would move them.
      int? rate;
      if (!_document.hasTiming) {
        if (kind.isAudio) {
          rate = audioFrameRate;
        } else if (_document.kind.isAudio &&
            _document.frameRate == audioFrameRate) {
          rate = defaultRateFor(_document.size.ratio, kind);
        }
      }
      var frames = rate == null
          ? null
          : (_document.frames * rate / math.max(1, _document.frameRate))
              .round()
              .clamp(1, maxFrameCount)
              .toInt();
      var next = _document.copyWith(
          kind: kind,
          frameRate: rate,
          frames: frames,
          // A piece of sound starts with no canvas -- Ratio "None" -- and
          // anything else always has one.
          hasCanvas: !kind.isAudio);
      // The estimate from what the document now is.
      apply(next.copyWith(
          estimate: next.estimate.copyWith(
              format: kind.isAudio
                  ? EstimateAs.audio
                  : next.isAnimated
                      ? EstimateAs.video
                      : EstimateAs.png)));
      return;
    }

    // Paper, unless it is on paper already. A4 at 150dpi: the size somebody
    // means by "a page", and small enough that a document of thirty of them
    // is still something the editor can draw.
    var size = _document.size;
    var onPaper = size.ratio.isPaper;
    var next = onPaper
        ? size
        : size.copyWith(ratio: CanvasRatio.a4, width: a4PageWidth);

    // Pages turn, so a document of them runs at film's rate rather than at a
    // printed sheet's one frame a second -- see defaultRateFor. Only where
    // the rate is still whatever the shape gave it: a rate somebody typed is
    // theirs.
    var rate = _document.frameRate == defaultFrameRateFor(size.ratio)
        ? defaultRateFor(next.ratio, kind)
        : null;

    // Through setShape, which is the one place a shape change goes: it puts
    // away the layout of the shape being left and takes out the one being
    // opened. Written straight into the document the elements would keep the
    // numbers they had on a screen.
    //
    // One undo step for the whole of it. Calling this a document and then
    // pressing undo twice -- once for the kind and once for the paper it
    // brought with it -- is two steps for one decision.
    beginInteraction();
    if (!onPaper) setShape(next, frameRate: rate);
    apply(_document.copyWith(
        kind: kind,
        frameRate: onPaper ? rate : null,
        estimate: estimate,
        hasCanvas: true));
    endInteraction();
  }

  /// setAudio changes the document's sound settings: its tempo, metre,
  /// structure, grid and how it is published.
  void setAudio(AudioSettings next, {bool transient = false}) {
    var doc = _document.copyWith(audio: next);
    // A structure longer than the timeline makes the timeline long enough
    // to hold it: the last section is played to its end.
    if (next.sections.isNotEmpty) {
      var need = (next.totalBars * next.secondsPerBar * doc.frameRate)
          .ceil()
          .clamp(1, maxFrameCount)
          .toInt();
      if (need > doc.frames) doc = doc.copyWith(frames: need);
    }
    apply(doc, transient: transient);
  }

  /// addSection adds a section at the end of the structure, named [name].
  void addSection(String name) {
    var a = _document.audio;
    var taken = {for (var s in a.sections) s.id};
    var n = a.sections.length;
    while (taken.contains("section$n")) {
      n++;
    }
    setAudio(a.copyWith(sections: [
      ...a.sections,
      SongSection("section$n",
          name: name,
          bars: a.sections.isEmpty ? 8 : a.sections.last.bars,
          color: a.sections.length % sectionColors.length),
    ]));
  }

  /// goToSection moves the playhead to where section [index] starts.
  void goToSection(int index) {
    var a = _document.audio;
    if (index < 0 || index >= a.sections.length) return;
    frame = (a.startBar(index) * a.secondsPerBar * _document.frameRate)
        .round()
        .clamp(0, math.max(0, _document.frames - 1))
        .toInt();
  }

  /// setHasCanvas gives the document a picture or takes it away -- the
  /// Ratio "None" of a piece of sound. See CanvasDocument.hasCanvas.
  void setHasCanvas(bool has) {
    if (_document.hasCanvas == has) return;
    apply(_document.copyWith(hasCanvas: has));
  }

  /// forgetShape drops a shape from the document's targets, and the layouts
  /// kept for it.
  ///
  /// For a shape looked at once and not wanted: it is marked in the list and
  /// laid out for on every new element until it is said to be over.
  void forgetShape(String key) {
    if (key == shapeKey(_document.size)) return;
    var left = [
      for (var t in _document.targets)
        if (t != key) t
    ];
    CanvasElement dropped(CanvasElement e) => e.base.layouts.containsKey(key)
        ? e.withBase(layouts: {...e.base.layouts}..remove(key))
        : e;
    CanvasScene scene(CanvasScene s) =>
        s.copyWith(elements: [for (var e in s.elements) dropped(e)]);

    var next = _document.master == null
        ? _document
        : _document.copyWith(master: scene(_document.master!));
    apply(next.withScenes([for (var s in next.allScenes) scene(s)],
        at: next.at).copyWith(targets: left.length > 1 ? left : const []));
  }

  /// resetShape lays this shape out again from another one, by scale.
  ///
  /// The way back from an arrangement that has been dragged into a mess: it
  /// is the same seeding the first visit to a shape gets.
  void resetShape(String from) {
    var here = _document.size;
    var was = sizeForShape(from, here);

    CanvasScene scene(CanvasScene s) {
      // Laid out from the other shape exactly as a first visit to this one
      // would have been: the same block, the same measure, the same place.
      // Seeded by the layout's own scale alone it moved the boxes and left
      // the design inside them at this shape's size.
      var had = [
        for (var e in s.elements)
          if (e.base.layouts[from] case var layout?) showing(e, layout) else e,
      ];
      var seed = seedFor(had, was, here);
      return s.copyWith(elements: [
        for (var e in had)
          showing(
              e, seeded(ElementLayout.of(e.base), seed, coversPage(e, was))),
      ]);
    }

    var next = _document.master == null
        ? _document
        : _document.copyWith(master: scene(_document.master!));
    apply(
        next.withScenes([for (var s in next.allScenes) scene(s)], at: next.at));
  }

  /// addScenes puts [scenes] in after the one being looked at, and goes to
  /// the first of them.
  ///
  /// What a saved scene or a saved canvas is dropped into a document with:
  /// one scene from the first, every scene from the second. The ids are the
  /// caller's to make fresh -- see SavedPreset.buildScenes, which does.
  void addScenes(List<CanvasScene> scenes) {
    if (scenes.isEmpty) return;
    var list = [..._document.allScenes];
    var at = (_document.sceneAt + 1).clamp(0, list.length).toInt();
    list.insertAll(at, scenes);
    apply(_document.copyWith(onMaster: false).withScenes(list, at: at));
    _afterSceneChange();
  }

  void removeScene(int index) {
    apply(_document.copyWith(onMaster: false).removeScene(index));
    _afterSceneChange();
  }

  void moveScene(int from, int to) {
    apply(_document.moveScene(from, to));
    _afterSceneChange();
  }

  void renameScene(int index, String name) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    apply(_document.withScene(index, list[index].copyWith(name: name.trim())));
  }

  /// setBackground writes the backdrop being edited.
  ///
  /// The shared canvas's own while that is the one open, and the document's
  /// otherwise. Which of the two an edit lands on is this file's business
  /// rather than the settings panel's: the panel edits "the background", and
  /// there is only ever one of those in front of the reader.
  void setBackground(CanvasBackground next, {bool transient = false}) {
    var document = _document;
    if (document.editingMaster) {
      apply(document.withMaster(document.master!.copyWith(background: next)),
          transient: transient);
      return;
    }
    // The shared canvas's own, where that is the one on screen. A backdrop on
    // the master is drawn in front of every scene's, so writing the scene's
    // from here would change nothing anybody can see -- which is what a dead
    // Background panel was. See CanvasDocument.editedBackground.
    if (document.sharedBackdrop) {
      apply(document.withMaster(document.master!.copyWith(background: next)),
          transient: transient);
      return;
    }
    // This scene's own, where it has one -- that is what is drawn, and the
    // document's underneath it is not -- or where there are several scenes,
    // so that an edit does not leak onto all of them. Writing the shared one
    // is how changing scene one's background changed scene two's.
    //
    // Owning it rather than counting scenes, because a scene can own one
    // while being the only scene left: two scenes, an edit -- which the scene
    // then owns -- and the second scene deleted, and every edit after that
    // went to the document's background underneath a scene background that
    // was still the one on screen. The panel died on removing a scene.
    // A document with no scenes at all cannot answer yes to either: the scene
    // it reports is one it makes up on the spot, and that one owns nothing.
    if (document.scene.background != null || document.hasScenes) {
      apply(
          document.withScene(
              document.at, document.scene.copyWith(background: next)),
          transient: transient);
      return;
    }
    apply(document.copyWith(background: next), transient: transient);
  }

  /// setMasterBackgroundOff leaves every scene its own backdrop, or puts the
  /// shared one back over them.
  ///
  /// The backdrop itself is kept either way: switching it off is a decision
  /// about what covers what, not an instruction to throw a design away.
  void setMasterBackgroundOff(bool off) {
    var master = _document.master;
    if (master == null) return;
    apply(_document.withMaster(master.copyWith(backgroundOff: off)));
  }

  /// setSceneHolds decides whether playback runs on into the next scene.
  void setSceneHolds(int index, bool holds) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    apply(_document.withScene(index, list[index].copyWith(holds: holds)));
  }

  /// setSceneMasterOff leaves the master canvas off scene [index] -- a
  /// game's title screen without its HUD -- or puts it back.
  void setSceneMasterOff(int index, bool off) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    apply(_document.withScene(index, list[index].copyWith(masterOff: off)));
  }

  /// setSceneCover marks a page as the front or the back of the document.
  ///
  /// One of each at most, and each at its own end. A document with two front
  /// covers is not a thing, and a cover in the middle is a page: the marks
  /// are what the numbering and the pairing are read from, so two of them
  /// would give two answers to what number a page carries.
  void setSceneCover(int index, PageCover cover) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    var next = [
      for (var (at, scene) in list.indexed)
        at == index
            ? scene.copyWith(cover: cover)
            // Whoever held this mark before gives it up, which is what makes
            // marking a page the front cover also mean "and not that one".
            : (cover.isCover && scene.cover == cover
                ? scene.copyWith(cover: PageCover.none)
                : scene),
    ];
    apply(_document.withScenes(next, at: _document.at));
  }

  /// setSceneTransition gives a scene its own way of giving way to the next,
  /// or takes it back to the document's default.
  void setSceneTransition(int index, SceneTransition? transition,
      {bool transient = false}) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    apply(
        _timed(_document.withScene(
            index,
            transition == null
                ? list[index].copyWith(clearTransition: true)
                : list[index].copyWith(transition: transition))),
        transient: transient);
  }

  /// cameraView is whether the canvas shows the scene through its camera
  /// while paused -- stepped and scrubbed, as well as played -- so a camera
  /// can be set up by looking. On while a camera is being set, off at the
  /// next press on the canvas, since the page is drawn moved and a press
  /// would land somewhere other than it looks.
  bool get cameraView => _cameraView;
  bool _cameraView = false;
  set cameraView(bool on) {
    if (on == _cameraView) return;
    _cameraView = on;
    notifyListeners();
  }

  /// setSceneCamera gives scene [index] a slow move, or holds it still with
  /// null. See SceneCamera.
  void setSceneCamera(int index, SceneCamera? camera) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    _cameraView = camera != null;
    apply(_document.withScene(
        index,
        camera == null
            ? list[index].copyWith(clearCamera: true)
            : list[index].copyWith(camera: camera)));
  }

  /// soundEveryTransition puts [like]'s sound -- its file, volume and lead
  /// -- on the default transition and on every scene's own, as one change.
  void soundEveryTransition(SceneTransition like) {
    SceneTransition sounded(SceneTransition t) => t.copyWith(
        sound: like.sound,
        soundName: like.soundName,
        soundLength: like.soundLength,
        soundVolume: like.soundVolume,
        soundLead: like.soundLead);
    var master =
        _document.master ?? CanvasScene(id: newSceneId(), name: "Master");
    var next = _document.copyWith(
        master:
            master.copyWith(transition: sounded(_document.defaultTransition)));
    var list = next.allScenes;
    for (var (i, scene) in list.indexed) {
      if (scene.transition case var t?) {
        next = next.withScene(i, scene.copyWith(transition: sounded(t)));
      }
    }
    apply(next);
  }

  /// _timed is [next] with every scene back at its start: a transition made
  /// longer or shorter is taken from, or given to, the scene before it, so
  /// nothing later in the run moves against the master's voice-over. See
  /// CanvasDocument.keepingStarts.
  CanvasDocument _timed(CanvasDocument next) => next.keepingStarts(_document);

  /// setDefaultTransition changes what every scene without one of its own
  /// uses. It lives on the master canvas, which is where the things shared by
  /// every scene live.
  void setDefaultTransition(SceneTransition transition) {
    var master =
        _document.master ?? CanvasScene(id: newSceneId(), name: "Master");
    apply(_timed(
        _document.copyWith(master: master.copyWith(transition: transition))));
  }

  /// _afterSceneChange puts the editor back on solid ground: a selection
  /// naming elements of the canvas that has just been left is a selection of
  /// nothing, and a frame past the end of the new one is a frame that does
  /// not exist.
  void _afterSceneChange() {
    _audioFollowsPage(turned: true);
    _syncTimeline();
    _selection = {};
    _backgroundSelected = false;
    _focusedPlayer = null;
    _frame = _frame.clamp(0, math.max(0, _document.frames - 1)).toInt();
    notifyListeners();
  }

  void clearSelection() {
    if (_selection.isEmpty && !_backgroundSelected && _offCanvas.isEmpty) {
      return;
    }
    _backgroundSelected = false;
    _focusedPlayer = null;
    _offCanvas = const {};
    _selection = {};
    _leaveVectorIfUnpicked();
    notifyListeners();
  }

  void selectAll() {
    _backgroundSelected = false;
    _offCanvas = const {};
    // What is on the canvas: a sound on the timeline is not, and taking it
    // in would put the soundtrack one Delete away.
    _selection = {
      for (var e in _document.elements)
        if (!e.locked && !isTimelineSound(e)) e.id,
    };
    notifyListeners();
  }

  // ------------------------------------------------------------------------
  // View
  // ------------------------------------------------------------------------

  set zoom(double value) {
    _characterZoom = null;
    var next = value.clamp(minZoom, maxZoom);
    if (next == _zoom) return;
    // About the middle of what is looked at: the view scaled with the page,
    // so the point in the middle of the window stays there.
    var f = next / _zoom;
    _pan = Offset2(_pan.dx * f, _pan.dy * f);
    _zoom = next;
    // Coming back to the whole canvas re-centres it. Left alone, a pan made
    // while zoomed in would push the fitted canvas off to one side, where it
    // would sit with empty space beside it and no obvious way to say why.
    if ((_zoom - 1).abs() < 0.001) _pan = const Offset2(0, 0);
    _notifyView();
  }

  void resetZoom() {
    _characterZoom = null;
    _zoom = 1;
    _pan = const Offset2(0, 0);
    _notifyView();
  }

  /// showWhole and fitWidth are the two frame buttons on the band. Each also
  /// clears the zoom, since pressing "show me all of it" while zoomed in and
  /// being shown a corner of it is not what either button says.
  void showWhole() {
    fit = CanvasFit.whole;
    resetZoom();
  }

  void fitWidth() {
    fit = CanvasFit.width;
    resetZoom();
  }

  void zoomBy(double factor) => zoom = _zoom * factor;

  /// characterZoom is the stretch of a character's body last zoomed onto
  /// -- what the bar's zoom steps on from -- until the view is zoomed some
  /// other way.
  CharacterZoom? get characterZoom => _characterZoom;
  CharacterZoom? _characterZoom;

  /// zoomToRect zooms onto [r], a stretch of the canvas, in its middle and
  /// filling most of the view.
  void zoomToRect(Rect r) {
    var size = _document.size.size;
    if (r.width <= 0 || r.height <= 0 || size.width <= 0) return;
    _zoom = (math.min(size.width / r.width, size.height / r.height) * 0.9)
        .clamp(minZoom, maxZoom);
    var scale = _fitScale * _zoom;
    _pan = Offset2(scale * (size.width / 2 - r.center.dx),
        scale * (size.height / 2 - r.center.dy));
    _notifyView();
  }

  /// zoomToCharacter zooms onto the stretch of character [id]'s body that
  /// [zoom] names, as it is where the playhead is.
  void zoomToCharacter(String id, CharacterZoom zoom) {
    var c = _document.elementById(id);
    if (c is! CharacterElement) return;
    _characterZoom = zoom;
    var (rig, _, _) = drawnRig(c, _frame, math.max(1, _document.frameRate));
    var pose = c.poseAt(_frame);
    var box = c.bounds.shift(Offset(pose.dx, pose.dy));
    var local = zoomRect(rig, zoom).shift(box.topLeft);
    // Turned with the character, about its middle.
    var turn = c.rotationAt(_frame) * math.pi / 180;
    var cs = math.cos(turn), sn = math.sin(turn);
    Offset turned(Offset p) {
      var d = p - box.center;
      return box.center + Offset(d.dx * cs - d.dy * sn, d.dx * sn + d.dy * cs);
    }

    var corners = [
      for (var p in [
        local.topLeft,
        local.topRight,
        local.bottomLeft,
        local.bottomRight
      ])
        turned(p)
    ];
    var r = Rect.fromPoints(corners[0], corners[0]);
    for (var p in corners.skip(1)) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    zoomToRect(r);
  }

  set pan(Offset2 value) {
    _pan = value;
    _notifyView();
  }

  /// followPan is the view where the page has been scrolled to by hand --
  /// the scroll bars, two fingers, the wheel -- kept so the zoom zooms about
  /// it. Nothing is drawn again for it: the page has moved already.
  void followPan(Offset2 value) => _pan = value;

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

  /// stepFrame moves the playhead, and stops playback first.
  ///
  /// Stopping is the point: scrubbing while the timer is still running means
  /// the next tick undoes the step, so the key appears to do nothing. Taking
  /// hold of the playhead is saying you want it where you put it.
  ///
  /// While Play runs every scene, a step past either end of a scene goes on
  /// into the next or the previous one, as playing does.
  void stepFrame(int by) {
    pause();
    var document = _document;
    if (!_runsScenes) {
      frame = _frame + by;
      return;
    }
    goToRunFrame(document.startOfScene(document.at) + _frame + by);
  }

  /// goToRunFrame puts the playhead on frame [run] of the whole run, on
  /// whichever scene that is -- and where it is inside a transition, the
  /// canvas shows the transition, as playing does.
  ///
  /// Counted in the run's own frames because scenes overlap where a
  /// transition joins them. Counted scene by scene, as stepping was, the
  /// last frame of one scene was followed by the first of the next -- which
  /// in the run is a transition's length *earlier*, and the playhead jumped
  /// back every time it crossed a join.
  void goToRunFrame(int run) {
    var document = _document;
    run = run.clamp(0, math.max(0, document.playFrames - 1)).toInt();
    var place = placeInSequence(document, run);
    if (place.scene != document.at) goToScene(place.scene);
    frame = place.frame;
    var showing = place.changing ? run : null;
    if (showing != _previewAt) {
      _previewAt = showing;
      notifyListeners();
    }
  }

  /// rewind is the back-to-the-start button: the first frame of the scene,
  /// and -- pressed again there, while Play runs every scene -- the first
  /// frame of the scene before.
  void rewind() {
    var back = _runsScenes && _frame == 0 && _document.at > 0;
    stop();
    if (back) {
      goToScene(_document.at - 1);
      frame = 0;
    }
  }

  /// forward is rewind's mirror, the button after Play: the next scene's
  /// first frame while Play runs every scene, and the last frame of the scene
  /// otherwise.
  void forward() {
    pause();
    // While every scene plays, straight to the next scene's start. The end
    // of this one is inside its transition -- the next scene has already
    // begun there -- so stopping on it first and going on from it was a
    // step forward and then a step back.
    if (_runsScenes && _document.at < _document.allScenes.length - 1) {
      goToScene(_document.at + 1);
      frame = 0;
      return;
    }
    frame = math.max(0, _document.frames - 1);
  }

  /// _runsScenes is whether the transport works across the scenes: Play all
  /// scenes, on a scene rather than the master.
  bool get _runsScenes =>
      _playAll && _document.hasScenes && !_document.editingMaster;

  void play() {
    // A stop waiting for an action is waited for no longer.
    _endWait();
    // Playing only the slots: Play is the timeline's -- the slots stop, and
    // the piece plays from its playhead.
    if (_sessionOnly) {
      _haltClips();
      _playback?.cancel();
      _playback = null;
      _sessionOnly = false;
    }
    if (playing) return;
    _playedFrom = (_document.at, _frame);
    // Sounds that start by themselves start with the canvas -- before the
    // checks below, since a page that is a still is still a page with music
    // on it.
    _autoplayAudio();
    // _playback is set below; the timed media are cued once it is.
    scheduleMicrotask(_syncTimeline);

    // The whole document: the playhead runs through the sequence, and the
    // editor follows it -- the scene showing changes as it reaches each one,
    // so the panel, the timeline and the canvas all say the same thing about
    // where the playback has got to.
    if (_playAll && _document.hasScenes) {
      if (_document.playFrames <= 1) return;
      _previewEnd = _document.playFrames - 1;
      // From the playhead, wherever it has been put: the run's frame under
      // it on the ruler. It was from wherever the last run had been paused,
      // which -- after the playhead had been moved to edit something --
      // looked like a jump to anywhere. At the very end, from the start.
      var from = _document.editingMaster
          ? _frame
          : _document.startOfScene(_document.at) + _frame;
      if (from >= _previewEnd) {
        if (!_document.editingMaster && _document.at != 0) goToScene(0);
        _frame = 0;
        from = 0;
      }
      _previewAt = from;
      _loopCounts.clear();
      _startTimer();
      notifyListeners();
      return;
    }

    if (_document.frames <= 1) return;
    _loopCounts.clear();
    _startTimer();
    notifyListeners();
  }

  void _startTimer() {
    _playback?.cancel();
    // Twice a frame, to notice a frame falling due soon after it does; each
    // tick moves the playhead on by however many frames have actually
    // passed. See _tick.
    var interval = Duration(
        microseconds:
            (500000 / _document.frameRate).round().clamp(4000, 500000));
    _clockFrames = 0;
    _clockShift = 0;
    _playWatch = Stopwatch()..start();
    // A periodic timer's tick counts the intervals that have passed, not the
    // callbacks that ran: a late callback sees every interval it missed. So
    // tick times interval is the time since Play, by the same clock a test's
    // pretend time drives.
    _playback = Timer.periodic(
        interval, (t) => _tick(t.tick * interval.inMicroseconds));
  }

  /// _clockFrames is how many frames the playhead has been moved on since
  /// playback started.
  ///
  /// The playhead keeps time by the clock, not by counting ticks. It was a
  /// frame a tick, and a timer's ticks come late whenever the app is busy --
  /// so the playhead fell behind the sound, which plays on the sound card's
  /// own clock, until the two were far enough apart that the sound was
  /// pulled back to the playhead: heard as a skipped beat, or a jump.
  int _clockFrames = 0;

  /// _tick moves the playhead on to where the clock says it should be: one
  /// frame at a time, so a marker on a frame passed over is still obeyed.
  void _tick(int elapsed) {
    var rate = math.max(1, _document.frameRate);
    // Practising, the clock runs at the tempo set -- see practiceRate.
    var seconds =
        (clockForTest?.call() ?? elapsed) / 1000000 * _clockRate + _clockShift;
    // Only the slots: their clock goes on, the playhead does not.
    if (_sessionOnly) {
      _sessionSeconds = seconds;
      if (_clipChannels.isNotEmpty || _clipRecord != null) {
        _sessionStep(_sessionNow);
      }
      // The clips' envelopes of their channels' settings, moving.
      if (_clipChannels.isNotEmpty) _applyMix();
      return;
    }
    var now = seconds * rate;
    var due = now.floor() - _clockFrames;
    // A long stall -- the window dragged, the machine asleep -- is let go
    // rather than raced through: past a few frames behind, it carries on
    // from the clock without playing out what was missed.
    if (due > 6) {
      _clockFrames += due - 6;
      due = 6;
    }
    for (var i = 0; i < due && _playback != null; i++) {
      _clockFrames++;
      _step();
    }
    if (_playback != null) {
      _followSound(now - _clockFrames);
      if (_clipChannels.isNotEmpty || _clipRecord != null) {
        _sessionStep(_sessionNow);
      }
    }
  }

  /// _playWatch is the time since Play, read between ticks: see
  /// betweenFrames.
  Stopwatch _playWatch = Stopwatch();

  /// betweenFrames is how far past the frame it is on the playhead has
  /// really got, nought to just under one -- nought when it is not playing.
  /// The playhead moves a whole frame at a time; this is for what is drawn
  /// smoothly between them (see scene_renderer's betweenFrames).
  double get betweenFrames {
    // Only the slots playing, the playhead stands still.
    if (_playback == null || clockForTest != null || _sessionOnly) return 0;
    var rate = math.max(1, _document.frameRate);
    var now = (_playWatch.elapsedMicroseconds / 1000000 * _clockRate +
            _clockShift) *
        rate;
    return (now - _clockFrames).clamp(0.0, 0.999);
  }

  /// playsDrift is whether the scene on the stage has a drift in it --
  /// a picture's, or one of its layers' -- and so wants drawing on every
  /// screen refresh while it plays, not only on each new frame.
  bool get playsDrift {
    for (var e in _document.elements) {
      if (e is! ImageElement) continue;
      var loop = e.animation.loop;
      if (loop.on && loop.preset.drifts) return true;
      for (var l in e.layers) {
        if (l.loop.on && l.loop.preset.drifts) return true;
      }
    }
    return false;
  }

  /// _clockShift is how far, in seconds, the playhead's clock has been moved
  /// to keep with the sound -- see _followSound.
  double _clockShift = 0;

  /// _followSound keeps the playhead with the sound it is playing.
  ///
  /// The sound plays by the sound card's clock and the playhead went by the
  /// computer's, and the two do not run at quite the same speed. Over a long
  /// track they drifted apart until the sound was far enough out to be moved
  /// back to the playhead -- heard as a skip part way through. Now the
  /// playhead's clock is eased toward wherever the sound has actually got,
  /// a little each tick, so the two never part and the sound is never moved
  /// for drift. A difference too big to be drift -- a hold, a jump -- is
  /// left alone, for the cue to put right.
  ///
  /// [into] is how far past the frame it is on the playhead has got.
  void _followSound(double into) {
    var a = _audio;
    if (a == null) return;
    var rate = math.max(1, _document.frameRate);
    for (var (e, at) in _joinedCuts(_timedOnScreen.toList())) {
      if (at == null || e is! AudioElement || !a.isPlaying(e.id)) continue;
      var clip = e.clip;
      if (clip.loop != MediaLoop.none) continue;
      var position = a.positionOf(e.id), index = a.indexOf(e.id);
      if (position == null || index == null || index >= clip.playlist.length) {
        continue;
      }
      var before = 0.0;
      for (var s in clip.playlist.take(index)) {
        before += s.span;
      }
      var heard =
          clip.at + (before + position - clip.playlist[index].start) * rate;
      var ahead = (heard - (at + into)) / rate;
      if (ahead.abs() > 0.25) return;
      _clockShift += ahead * 0.1;
      return;
    }
  }

  void pause() {
    if (_practice != null) _endPractice();
    // Stopped, the slots stop with it -- and a recording is kept: what was
    // played is in the part, and what the slots played on the timeline.
    _haltClips();
    if (_recording) {
      _recording = false;
      _keepTake();
    }
    _playback?.cancel();
    _playback = null;
    _sessionOnly = false;
    _previewing = null;
    // A run of every scene, stopped, is the scene it stopped on at the frame
    // it stopped at -- which is where the playhead already is. Holding on to
    // the run's own frame kept the canvas drawing it while the playhead was
    // moved to edit, and the next Play went on from there instead. Watching
    // one join is different: it puts itself back. See stopPreview.
    if (_playAll && _previewFrom == null) _previewAt = null;
    _syncTimeline();
    notifyListeners();
  }

  void togglePlay() => playing ? pause() : play();

  /// _playedFrom is the scene and frame the last Play started from.
  (int, int)? _playedFrom;

  /// stopPlaying is the control bar's Stop: playing, back to where Play
  /// started, as a take is gone over again; stopped already, back to the
  /// very start.
  void stopPlaying() {
    // Only the slots playing: they stop, the playhead stays where it is.
    if (_sessionOnly) {
      pause();
      return;
    }
    var from = _playedFrom;
    if (!playing || from == null) {
      stop();
      return;
    }
    pause();
    var (scene, frame) = from;
    if (scene != _document.at && scene < _document.allScenes.length) {
      goToScene(scene);
    }
    this.frame = frame;
  }

  // ------------------------------------------------------------------------
  // The control bar's switches
  // ------------------------------------------------------------------------

  /// metronome is whether a click sounds on every beat while a piece of
  /// sound plays. The editor's, not the document's: it is never exported.
  bool get metronome => _metronome;
  bool _metronome = false;
  set metronome(bool on) {
    if (_metronome == on) return;
    _metronome = on;
    _syncMetronome();
    notifyListeners();
  }

  /// metronomeAvailable is false where the engine has no click to play --
  /// SoLoud's buses, with the mix engine switched off.
  bool get metronomeAvailable => !(_audio?.metronomeUnavailable ?? false);

  void _syncMetronome() {
    var on = playing &&
        _metronome &&
        _document.kind.isAudio &&
        _previewing == null &&
        _previewAt == null;
    if (!on && _audio == null) return;
    var a = _document.audio;
    audio.metronome(
        on: on,
        // On the slots' own clock, when only they play.
        at: _sessionOnly
            ? _sessionSeconds
            : _frame / math.max(1, _document.frameRate),
        secondsPerBeat: a.secondsPerBeat,
        beatsPerBar: a.beatsPerBar);
  }

  /// bandState is how mixer band [section] is shown: whole, minimised to
  /// its least, or hidden -- each band in turn from the rail at the
  /// mixer's right edge, as Ableton's are.
  BandState bandState(MixerSection section) => _bandStates[section]!;
  final Map<MixerSection, BandState> _bandStates = {
    for (var s in MixerSection.values) s: BandState.shown,
  };

  /// restoreMixer puts the mixer's bands and returns back as they were
  /// left -- see CanvasPreferences.mixerBands -- without notifying, for the
  /// screen to call as it opens. A band left of an unknown name keeps its
  /// own; at least one band is always shown.
  void restoreMixer(List<String> bands, bool returns) {
    for (var (i, s) in MixerSection.values.indexed) {
      if (i >= bands.length) break;
      var state = BandState.values.where((b) => b.name == bands[i]).firstOrNull;
      if (state != null) _bandStates[s] = state;
    }
    if (_mainBands.every((s) => _bandStates[s] == BandState.hidden)) {
      _bandStates[MixerSection.mixer] = BandState.shown;
    }
    _returnsShown = returns;
  }

  /// mixerBandNames are the bands' states by name, in order, for keeping.
  List<String> get mixerBandNames =>
      [for (var s in MixerSection.values) _bandStates[s]!.name];

  /// mixerSections is which bands are showing at all, whole or minimised.
  Set<MixerSection> get mixerSections => {
        for (var e in _bandStates.entries)
          if (e.value != BandState.hidden) e.key,
      };

  /// _mainBands are the bands one of which always shows: a mixer of send
  /// dials alone, or of nothing, is only its names.
  static const _mainBands = [
    MixerSection.clips,
    MixerSection.devices,
    MixerSection.mixer,
  ];

  /// toggleMixerSection is a band's rail button: shown, then minimised,
  /// then hidden, then shown again -- the sends shown and hidden -- never
  /// hiding the last of the clips, devices and mixer showing, which goes
  /// back to shown instead.
  void toggleMixerSection(MixerSection section) {
    var next = switch (_bandStates[section]!) {
      BandState.shown when section == MixerSection.sends => BandState.hidden,
      BandState.shown => BandState.minimised,
      BandState.minimised => BandState.hidden,
      BandState.hidden => BandState.shown,
    };
    if (next == BandState.hidden &&
        _mainBands.contains(section) &&
        _mainBands
            .where((s) => s != section)
            .every((s) => _bandStates[s] == BandState.hidden)) {
      next = BandState.shown;
    }
    _bandStates[section] = next;
    notifyListeners();
  }

  /// narrowStrips is which of the mixer's columns are narrow, by key: each
  /// made narrow or wide by itself, or all together -- see setAllNarrow.
  Set<String> get narrowStrips => Set.unmodifiable(_narrowStrips);
  final Set<String> _narrowStrips = {};

  void toggleNarrow(String key) {
    if (!_narrowStrips.remove(key)) _narrowStrips.add(key);
    notifyListeners();
  }

  /// setAllNarrow makes every column in [keys] narrow, or every one wide.
  void setAllNarrow(Iterable<String> keys, bool narrow) {
    narrow ? _narrowStrips.addAll(keys) : _narrowStrips.removeAll(keys);
    notifyListeners();
  }

  /// returnsShown is whether the mixer shows the returns beside the master:
  /// hidden, for the channels' room. What is sent to them is still heard.
  bool get returnsShown => _returnsShown;
  bool _returnsShown = true;
  set returnsShown(bool on) {
    if (_returnsShown == on) return;
    _returnsShown = on;
    notifyListeners();
  }

  /// followPlayhead is whether the timeline scrolls to keep the playhead in
  /// view while it plays.
  bool get followPlayhead => _followPlayhead;
  bool _followPlayhead = true;
  set followPlayhead(bool on) {
    if (_followPlayhead == on) return;
    _followPlayhead = on;
    notifyListeners();
  }

  /// looping is whether playing goes round between [loopRange]'s ends. For
  /// working on a part: the timeline's own Loop action, which a published
  /// piece obeys, is a different thing and is left alone.
  bool get looping => _looping;
  bool _looping = false;
  set looping(bool on) {
    if (_looping == on) return;
    _looping = on;
    if (on) _loop ??= _defaultLoop();
    notifyListeners();
  }

  (int, int)? _loop;

  /// loopRange is where the loop starts and how long it is, in frames --
  /// the one set, or until one is, where it would start.
  (int, int) get loopRange {
    var (from, length) = _loop ?? _defaultLoop();
    var frames = math.max(1, _document.frames);
    from = from.clamp(0, frames - 1).toInt();
    return (from, length.clamp(1, frames - from).toInt());
  }

  /// setLoop moves the loop: to start at [from], [length] long.
  void setLoop(int from, int length) {
    var frames = math.max(1, _document.frames);
    from = from.clamp(0, frames - 1).toInt();
    _loop = (from, length.clamp(1, frames - from).toInt());
    notifyListeners();
  }

  /// _defaultLoop is the loop a first press makes. A piece of sound: the
  /// section the playhead is in, or four bars from the bar it is in. Scenes:
  /// the whole scene.
  (int, int) _defaultLoop() {
    var doc = _document;
    var rate = math.max(1, doc.frameRate);
    if (!doc.kind.isAudio) return (0, math.max(1, doc.frames));
    var a = doc.audio;
    var barFrames = a.secondsPerBar * rate;
    var bar = (_frame / barFrames + 1e-6).floor();
    for (var i = 0; i < a.sections.length; i++) {
      var start = a.startBar(i);
      if (bar >= start && bar < start + a.sections[i].bars) {
        return (
          (start * barFrames).round(),
          (a.sections[i].bars * barFrames).round()
        );
      }
    }
    return ((bar * barFrames).round(), (4 * barFrames).round());
  }

  /// stepGrid moves the playhead to the next line of the quantise grid --
  /// or, with quantise off, the next beat -- either way, [by] -1 or 1.
  void stepGrid(int by) {
    var a = _document.audio;
    var rate = math.max(1, _document.frameRate);
    var step = (a.gridSeconds() ?? a.secondsPerBeat) * rate;
    if (step <= 0) return;
    var at = _frame / step;
    var line = by > 0 ? (at + 1e-6).floor() + 1 : (at - 1e-6).ceil() - 1;
    stepFrame((line * step).round() - _frame);
  }

  /// markerFrames are the places the marker buttons go between: the
  /// timeline's markers and locators, and each section's start.
  List<int> get markerFrames {
    var doc = _document;
    var rate = math.max(1, doc.frameRate);
    var a = doc.audio;
    return {
      for (var m in doc.actions) m.frame,
      if (doc.kind.isAudio)
        for (var i = 0; i < a.sections.length; i++)
          (a.startBar(i) * a.secondsPerBar * rate).round(),
    }.toList()
      ..sort();
  }

  /// goToMarker moves the playhead to the next marker, locator or section
  /// start after it -- [by] 1 -- or the one before it, -1.
  void goToMarker(int by) {
    var marks = markerFrames;
    int? to = by > 0
        ? marks.where((m) => m > _frame).firstOrNull
        : marks.where((m) => m < _frame).lastOrNull;
    if (to == null) return;
    stepFrame(to - _frame);
  }

  /// addLocator puts a named locator under the playhead -- or, with one
  /// there, leaves it.
  void addLocator() {
    var doc = _document;
    if (doc.actions.any((a) => a.frame == _frame)) return;
    var count = doc.actions
            .where((a) => a.kind == TimelineActionKind.locator)
            .length +
        1;
    apply(doc.copyWith(actions: [
      ...doc.actions,
      TimelineAction(
          frame: _frame,
          kind: TimelineActionKind.locator,
          label: "Locator $count"),
    ]..sort((a, b) => a.frame.compareTo(b.frame))));
  }

  /// engineLoad is how hard the mix engine is working -- the share of each
  /// block's time spent making it, nought to one -- or null where the
  /// editor's sound is not going through it.
  double? get engineLoad => switch (_audio?.engine) {
        DartAudioEngine e => e.load,
        _ => null,
      };

  void stop() {
    pause();
    stopPreview();
    stopAudio();
    frame = 0;
  }

  /// tickForTest advances the playhead one frame, the way the timer does.
  ///
  /// Playback is a real timer, and a test that waited on one would be a test
  /// that takes seconds to say something about arithmetic.
  @visibleForTesting
  void tickForTest() => _step();

  /// clockForTest stands in for the playback clock, in microseconds since
  /// Play, and tickClockForTest is a tick of the timer against it -- so a
  /// test can make a tick late without waiting for one to be.
  @visibleForTesting
  int Function()? clockForTest;

  @visibleForTesting
  void tickClockForTest() => _tick(0);

  /// _step advances one frame and obeys whatever marker is on the new one.
  ///
  /// The markers are applied after the advance rather than before, so a stop
  /// marker on frame 30 means "having reached 30, stop" -- which is what
  /// putting a marker on a frame looks like it should mean.
  void _step() {
    // Previewing one element: it alone moves on, and the playhead stays.
    if (_previewing case var one?) {
      if (one.frame + 1 > _previewingEnd) {
        pause();
        return;
      }
      _previewing = (id: one.id, frame: one.frame + 1);
      notifyListeners();
      return;
    }
    // Watching a transition: the playhead is running through the whole
    // document rather than through the scene, and it stops at the end of the
    // stretch that was asked for rather than looping.
    var preview = _previewAt;
    if (preview != null) {
      var next = preview + 1;
      if (next > _previewEnd) {
        stopPreview();
        return;
      }
      _previewAt = next;

      // Playing the document rather than watching one join: the editor is
      // walked along with the playhead, and a scene that has been told to
      // hold stops it there.
      if (_playAll) {
        var place = placeInSequence(_document, next);
        if (place.scene != _document.at) {
          var last = _document.allScenes[_document.at];
          if (last.holds) {
            stopPreview();
            return;
          }
          _document = _document.goToScene(place.scene);
          _audioFollowsPage(turned: true);
          _autoplayAudio();
        }
        _frame =
            place.frame.clamp(0, math.max(0, _document.frames - 1)).toInt();
      }
      _syncTimeline();
      notifyListeners();
      return;
    }

    // Waiting to be played: the playhead holds on the note.
    if (_practice != null && _practiceHolds(_frame + 1)) {
      notifyListeners();
      return;
    }
    var next = _frame + 1;
    // Round the loop: from its end back to its start -- but only from inside
    // it, so a playhead put past the loop plays on from there.
    if (_looping) {
      var (from, length) = loopRange;
      var end = from + length;
      if (_frame < end && next >= end) next = from;
    }
    if (next >= _document.frames) next = 0;
    var was = _frame;
    _frame = next;
    if (_practice != null) _practiceStep(was, next);

    for (var action in _document.actions) {
      if (action.frame != next) continue;
      switch (action.kind) {
        case TimelineActionKind.stop:
          pause();
          if (action.waitsFor.isNotEmpty) _waitForAction(action.waitsFor);
        case TimelineActionKind.pause:
          // Implemented by stepping the playhead back to where it is, for as
          // many ticks as the hold asks for. Held as a countdown on the action
          // rather than by sleeping, so the window stays responsive and the
          // playhead can still be dragged out of the hold.
          var held =
              _loopCounts.update(action.frame, (v) => v + 1, ifAbsent: () => 1);
          if (held < action.holdFrames) _frame = next - 1 < 0 ? 0 : next;
          if (held >= action.holdFrames) _loopCounts.remove(action.frame);
        case TimelineActionKind.loop:
          var count =
              _loopCounts.update(action.frame, (v) => v + 1, ifAbsent: () => 1);
          if (action.repeats == 0 || count <= action.repeats) {
            _frame = action.target.clamp(0, _document.frames - 1).toInt();
          }
        case TimelineActionKind.jump:
          _frame = action.target.clamp(0, _document.frames - 1).toInt();
        case TimelineActionKind.locator:
          break;
      }
    }
    _syncTimeline();
    notifyListeners();
  }

  // ------------------------------------------------------------------------
  // Live counters
  // ------------------------------------------------------------------------

  /// _counters is what each live counter is showing, by element id.
  ///
  /// Held here rather than on the element, and deliberately: a stopwatch that
  /// has been running for nine seconds is not a *design* that has been running
  /// for nine seconds, and writing every tick into the document would make a
  /// clock an unsaved change once a second and an undo history nobody could
  /// use. The document says how the counter behaves; this says where it has
  /// got to, and it goes when the window does.
  final Map<String, double> _counters = {};

  /// _countersRunning is which of them are counting, and _countersSince when
  /// each was last read, so that a tick advances by the time that has actually
  /// passed rather than by however often the timer happened to fire.
  final Set<String> _countersRunning = {};
  final Map<String, DateTime> _countersSince = {};

  Timer? _counterTimer;

  /// counterTicks counts how many times the running counters have moved.
  ///
  /// So that the stage's painter can tell that something changed: where a
  /// counter has got to is not in the document, so nothing else about the
  /// drawing is different from one tick to the next.
  int get counterTicks => _counterTicks;
  int _counterTicks = 0;

  /// counterValue is what [e] is showing now.
  ///
  /// A clock is the time of day whatever anybody has pressed -- there is
  /// nothing to start or stop about the afternoon -- and everything else is
  /// wherever its own count has got to, which starts at the start.
  double counterValue(CounterElement e) {
    if (!e.live) return e.from;
    if (e.source == CounterSource.clock) return _secondsOfDay();
    // A game's count: where the game has got it, else where it starts.
    if (e.source == CounterSource.game) {
      var count =
          _document.counts.where((c) => c.id == e.gameCount).firstOrNull;
      if (count == null) return e.from;
      return (_game?.countOf(_document, count.id) ?? count.start).toDouble();
    }
    return _counters[e.id] ?? e.from;
  }

  /// counterRunning is whether [e] is counting at this moment.
  ///
  /// The element's own `running` is where it starts; this is where it has got
  /// to. A clock is always running.
  bool counterRunning(CounterElement e) =>
      e.live &&
      (e.source == CounterSource.clock || _countersRunning.contains(e.id));

  /// startCounters gets every counter that says it starts running going, which
  /// is what opening a canvas with a clock on it should do.
  void startCounters() {
    for (var e in _document.elements) {
      if (e is CounterElement && e.live && e.running) _runCounter(e, true);
    }
  }

  /// pressCounterButton is what one of a counter's own buttons does.
  ///
  /// Returns true where the press was handled here. Input is the exception:
  /// asking for a number is a question for whoever has a window, so it comes
  /// back false and the caller puts the box up -- see setCounterValue.
  bool pressCounterButton(CounterElement e, CounterButton button) {
    if (!e.live) return true;
    switch (button) {
      case CounterButton.startStop:
        _runCounter(e, !_countersRunning.contains(e.id));
        return true;
      case CounterButton.reset:
        _counters[e.id] = e.from;
        _countersSince[e.id] = DateTime.now();
        _counterTicks++;
        notifyListeners();
        return true;
      case CounterButton.input:
        return false;
    }
  }

  /// setCounterValue is the answer to the Set button: the number to count on
  /// from. It does not start or stop anything -- typing a value into a
  /// stopwatch that is running should not stop it.
  void setCounterValue(CounterElement e, double value) {
    _counters[e.id] = value;
    _countersSince[e.id] = DateTime.now();
    _counterTicks++;
    notifyListeners();
  }

  void _runCounter(CounterElement e, bool on) {
    if (on) {
      _counters.putIfAbsent(e.id, () => e.from);
      _countersSince[e.id] = DateTime.now();
      _countersRunning.add(e.id);
      _counterTicks++;
      _startCounterTimer();
    } else {
      _countersRunning.remove(e.id);
      if (_countersRunning.isEmpty) {
        _counterTimer?.cancel();
        _counterTimer = null;
      }
    }
    notifyListeners();
  }

  void _startCounterTimer() {
    if (_counterTimer != null) return;
    // Twenty times a second. A counter written to two decimal places wants to
    // be seen changing, and a clock written to the second does not -- but the
    // cost of the faster one is a repaint of a number, and the slower one
    // would make the fast one stutter.
    _counterTimer =
        Timer.periodic(const Duration(milliseconds: 50), (_) => tickCounters());
  }

  /// tickCounters moves every running counter on by the time that has passed.
  ///
  /// By the clock rather than by a fixed step per tick: a timer that loses
  /// time whenever the window is busy is a broken timer, and this is the kind
  /// of element somebody points a camera at.
  @visibleForTesting
  void tickCounters({DateTime? now}) {
    if (_countersRunning.isEmpty) return;
    var at = now ?? DateTime.now();
    var moved = false;
    for (var id in _countersRunning.toList()) {
      var e = _document.elementById(id);
      if (e is! CounterElement || !e.live) {
        _countersRunning.remove(id);
        continue;
      }
      var since = _countersSince[id] ?? at;
      var seconds = at.difference(since).inMicroseconds / 1000000;
      if (seconds <= 0) continue;
      _countersSince[id] = at;

      var value = _counters[id] ?? e.from;
      // Towards the far end, whichever way round the two ends are: 100 to 1
      // is a countdown and 1 to 100 is not, and the rate is how fast, not
      // which way.
      var step = e.rate.abs() * seconds * (e.span < 0 ? -1 : 1);
      value += step;

      // Stopped at the end, or back round to the start -- which is what makes
      // a metronome a metronome rather than a counter that ran out.
      var done = e.span < 0 ? value <= e.to : value >= e.to;
      if (done && e.span != 0) {
        if (e.loop) {
          var over = (value - e.to).abs();
          var span = e.span.abs();
          value = span <= 0 ? e.from : e.from + (over % span) * (e.span.sign);
        } else {
          value = e.to;
          _countersRunning.remove(id);
        }
      }
      _counters[id] = value;
      moved = true;
    }
    if (_countersRunning.isEmpty) {
      _counterTimer?.cancel();
      _counterTimer = null;
    }
    if (moved) {
      _counterTicks++;
      notifyListeners();
    }
  }

  /// _secondsOfDay is the reader's own clock, as a number of seconds.
  double _secondsOfDay() {
    var now = DateTime.now();
    return now.hour * 3600 +
        now.minute * 60 +
        now.second +
        now.millisecond / 1000;
  }

  /// runButtonAction is what pressing a button element does, both in the
  /// editor's preview and in a published interactive canvas.
  ///
  /// Returns the URL a link button asked to open, if any, so that the decision
  /// to actually open it -- which is a decision about leaving the app -- stays
  /// with the caller and never happens down here.
  String? runButtonAction(ButtonAction action) {
    switch (action.kind) {
      case ButtonActionKind.goToFrame:
        pause();
        frame = action.frame;
      case ButtonActionKind.playFrom:
        frame = action.frame;
        play();
      case ButtonActionKind.playToFrame:
        play();
      case ButtonActionKind.play:
        play();
      case ButtonActionKind.pause:
        pause();
      case ButtonActionKind.togglePlay:
        togglePlay();
      case ButtonActionKind.restart:
        frame = 0;
        play();
      case ButtonActionKind.toggleElement:
        var target = _document.elementById(action.elementId);
        if (target != null) {
          replaceElement(target.withBase(visible: !target.visible));
        }
      case ButtonActionKind.goToScene:
        var to = _document.sceneIndexNamed(action.elementId);
        if (to >= 0) {
          pause();
          goToScene(to);
          frame = 0;
        }
      case ButtonActionKind.openLink:
        return action.url;
      // A sound or a video: the same five things done to either.
      case ButtonActionKind.playSound:
        switch (_mediaById(action.elementId)) {
          case AudioElement e:
            _heard();
            unawaited(audio.play(e));
          case VideoElement e:
            _heard();
            unawaited(video.play(e));
        }
      case ButtonActionKind.pauseSound:
        _audio?.pause(action.elementId);
        _video?.pause(action.elementId);
      case ButtonActionKind.toggleSound:
        switch (_mediaById(action.elementId)) {
          case AudioElement e:
            _heard();
            unawaited(audio.toggle(e));
          case VideoElement e:
            _heard();
            unawaited(video.toggle(e));
        }
      case ButtonActionKind.stopSound:
        _audio?.stop(action.elementId);
        _video?.stop(action.elementId);
      case ButtonActionKind.muteSound:
        switch (_mediaById(action.elementId)) {
          case AudioElement e:
            audio.toggleMute(e);
          case VideoElement e:
            video.toggleMute(e);
        }
    }
    return null;
  }

  // ------------------------------------------------------------------------
  // Sound
  // ------------------------------------------------------------------------

  final AudioEngine? _audioEngine;
  AudioRuntime? _audio;

  /// audio is what is playing. Made the first time anything asks, so a
  /// canvas with no sound on it never opens a sound device.
  AudioRuntime get audio => _audio ??= AudioRuntime(
      engine: _audioEngine ??
          (useMixEngine ? sharedMixEngine : SoLoudAudioEngine()),
      locate: (id) => CanvasMedia.existingPath(MediaKind.audio, id))
    ..addListener(notifyListeners);

  /// audioRevision changes whenever any sound's or video's state does, so
  /// the stage's painter knows to draw the speakers and the frames again.
  int get audioRevision => (_audio?.revision ?? 0) + (_video?.revision ?? 0);

  final FrameSource? _frameSource;
  VideoRuntime? _video;

  /// video plays the canvas's videos, through the same sound runtime as
  /// everything else. Made the first time anything asks, like [audio].
  VideoRuntime get video => _video ??= VideoRuntime(
      frames: _frameSource ?? FfmpegFrames(ffmpegPath),
      audio: audio,
      locate: (id) => CanvasMedia.existingPath(MediaKind.video, id))
    ..addListener(notifyListeners);

  /// videoShow is how [e] should be drawn now: its frame and its play bar.
  VideoShow videoShow(VideoElement e) {
    // On the timeline, outside its span, it is not there at all.
    if (e.clip.timed && !e.isLink) {
      var at = _timedFrame(e.id);
      if (at == null || _momentOf(e, at) == null) {
        return const VideoShow(hidden: true);
      }
    }
    var v = _video;
    if (v == null) return VideoShow.idle(e);
    var view = v.view(e);
    return VideoShow(
      playing: view.playing,
      muted: view.muted,
      volume: view.volume,
      position: view.position,
      start: view.start,
      end: view.end,
      frame: view.frame,
      poster: view.poster,
      opacity: view.opacity,
    );
  }

  /// pressVideo is a press on [part] of [e], [along] of the way along it
  /// for the two bars. Returns the address a link video asked to open, for
  /// the caller to ask about -- leaving the app is not decided down here.
  String? pressVideo(VideoElement e, VideoPart part, {double along = 0}) {
    var current = _mediaById(e.id);
    if (current is VideoElement) e = current;
    if (e.isLink) return linkAt(e.link, e.linkStart);
    // On the timeline it is the playhead's, and nothing on it is pressed.
    if (e.clip.timed) return null;
    switch (part) {
      case VideoPart.picture:
      case VideoPart.bigPlay:
      case VideoPart.playPause:
        _heard();
        unawaited(video.toggle(e));
      case VideoPart.track:
        unawaited(video.seekTo(e, along));
      case VideoPart.mute:
        video.toggleMute(e);
      case VideoPart.volume:
        video.setVolume(e, along);
        if (along > 0 && video.view(e).muted) video.setMuted(e, false);
    }
    return null;
  }

  /// audioUnavailable is whether the sound device could not be opened, for
  /// the settings to say so.
  bool get audioUnavailable => _audio?.unavailable ?? false;

  /// stopAudio stops every sound the canvas is playing.
  void stopAudio() {
    _video?.stopAll();
    _audio?.stopAll();
  }

  /// audioState is how [e]'s sound is doing, for the icon to show.
  AudioState audioState(AudioElement e) {
    if (e.instrument case var part?) {
      // An instrument's keys: the notes under the playhead, and any held.
      var seconds = (_frame - e.clip.at) / math.max(1, _document.frameRate);
      var practised = _practised;
      return AudioState(
          playing: playing,
          keys: {...part.sounding(seconds), ...?_held[e.id]},
          recording: _recording && _recordsInto(e),
          next: practised != null && practised.$2.id == e.id
              ? {for (var i in _waiting) part.notes[i].key}
              : const {});
    }
    var a = _audio;
    if (a == null) return AudioState.idle(e);
    var v = a.view(e);
    return AudioState(playing: v.playing, muted: v.muted, volume: v.volume);
  }

  // ------------------------------------------------------------------------
  // Instruments
  // ------------------------------------------------------------------------

  /// _held is each instrument's keys held down live, by element id.
  final Map<String, Set<int>> _held = {};

  /// heldKeys is [id]'s keys held down now.
  Set<int> heldKeys(String id) => Set.unmodifiable(_held[id] ?? const {});

  static String _channelOf(AudioElement e) =>
      e.clip.channel.isEmpty ? e.id : e.clip.channel;

  /// noteOn presses [key] on instrument [e]: heard at once, through its
  /// channel, and written down while recording.
  void noteOn(AudioElement e, int key, {int velocity = 100}) {
    var part = e.instrument;
    if (part == null) return;
    if (!(_held.putIfAbsent(e.id, () => {})).add(key)) return;
    _heard();
    _soundOn(e, part, key, velocity);
    if (_practice != null) _practiceHeard(e, key);
    // Into the slot being recorded, where it is this channel's; otherwise
    // into the part, with Record.
    if (_clipRecord?.channel == _channelOf(e)) {
      _clipNoteOn(e, key, velocity);
    } else if (_recording && playing && _recordsInto(e)) {
      (_take[e.id] ??= {})[key] = (_nowInPart(e), velocity);
    }
    notifyListeners();
  }

  /// armed is which MIDI channels are armed, by channel key: what a MIDI
  /// keyboard plays, and what a recording writes into. The session's, as
  /// solo is.
  Set<String> get armed => Set.unmodifiable(_armed);
  final Set<String> _armed = {};

  /// toggleArm arms or disarms a MIDI channel. One at a time, as a keyboard
  /// plays one instrument: arming another disarms the last.
  void toggleArm(String key) {
    if (!_armed.remove(key)) {
      _armed
        ..clear()
        ..add(key);
    }
    notifyListeners();
  }

  /// midiTarget is the instrument a MIDI keyboard plays: the armed channel's,
  /// else the one selected, or the first there is.
  AudioElement? get midiTarget {
    for (var e in _document.elements) {
      if (e is AudioElement &&
          e.instrument != null &&
          _armed.contains(_channelOf(e))) {
        return e;
      }
    }
    var picked = selected;
    if (picked is AudioElement && picked.instrument != null) return picked;
    for (var e in _document.elements) {
      if (e is AudioElement && e.instrument != null) return e;
    }
    return null;
  }

  /// midiNote is a key on a MIDI keyboard, pressed or -- at a velocity of
  /// nought -- let go: played on every MIDI channel that hears it -- see
  /// midiHearers -- as a key pressed on the canvas is. [from] is the
  /// keyboard's name; null asks for MidiInput's own.
  void midiNote(int key, int velocity, {String? from}) {
    if (velocity <= 0) {
      // Let go wherever it was pressed, whatever has changed since.
      for (var e in [..._document.elements]) {
        if (e is AudioElement && (_held[e.id]?.contains(key) ?? false)) {
          noteOff(e, key);
        }
      }
      return;
    }
    for (var e in midiHearers(from ?? MidiInput.shared.device?.name)) {
      noteOn(e, key, velocity: velocity);
    }
  }

  /// midiHearers are the instruments a note from the keyboard [from] is
  /// played on: each whose input takes it and whose Monitor says to -- In,
  /// always; Auto, while armed. With nothing armed and none on In, the one
  /// picked or the first, unless it is set Off: a keyboard plugged in plays
  /// something without anything being set up first.
  List<AudioElement> midiHearers(String? from) {
    bool takes(InstrumentPart p) =>
        p.input != noInput &&
        (p.input.isEmpty || from == null || p.input == from);
    var out = <AudioElement>[];
    for (var e in _document.elements) {
      if (e is! AudioElement) continue;
      var p = e.instrument;
      if (p == null || !takes(p)) continue;
      var hears = switch (p.monitor) {
        MidiMonitor.input => true,
        MidiMonitor.auto => _armed.contains(_channelOf(e)),
        MidiMonitor.off => false,
      };
      if (hears) out.add(e);
    }
    if (out.isEmpty && _armed.isEmpty) {
      var picked = selected;
      for (var e in [
        if (picked is AudioElement && picked.instrument != null) picked,
        ..._document.elements.whereType<AudioElement>(),
      ]) {
        var p = e.instrument;
        if (p != null && p.monitor != MidiMonitor.off && takes(p)) {
          out.add(e);
          break;
        }
      }
    }
    return out;
  }

  /// midiControl is a keyboard's controller moved -- the mod wheel, the
  /// pitch bend, an expression pedal: heard on every channel that hears
  /// its notes, and written into the part while Record is on.
  void midiControl(MidiControl control, double value, {String? from}) {
    for (var e in midiHearers(from ?? MidiInput.shared.device?.name)) {
      audio.control(_channelOf(e), control, value);
      if (_recording && playing && _recordsInto(e)) {
        (_controlTake[e.id] ??= {})
            .putIfAbsent(control, () => [])
            .add((_nowInPart(e), value));
      }
    }
  }

  /// _controlTake is each instrument's controllers moved while recording.
  final Map<String, Map<MidiControl, List<ControlPoint>>> _controlTake = {};

  /// liveScale is the scale a keyboard plays in -- a Push's pads are laid
  /// out in it: the Scale effect of the channel it plays, or C major.
  (int, List<int>) get liveScale {
    for (var e in midiHearers(MidiInput.shared.device?.name)) {
      var scale = e.instrument!.effects
          .where((m) => m.on && m.kind == MidiEffectKind.scale)
          .firstOrNull;
      if (scale != null) {
        return (
          scale.choice("root"),
          scaleSteps[scale.choice("scale").clamp(0, scaleSteps.length - 1)]
        );
      }
    }
    return (0, scaleSteps[0]);
  }

  /// sustain is the sustain pedal: held down, a key let go goes on sounding
  /// -- and is written down as held -- until the pedal is let up.
  bool get sustained => _sustain;
  bool _sustain = false;
  final Map<String, Set<int>> _sustained = {};
  void sustain(bool down) {
    if (_sustain == down) return;
    _sustain = down;
    if (down) return;
    var let = {..._sustained};
    _sustained.clear();
    for (var entry in let.entries) {
      var e = _document.elementById(entry.key);
      if (e is! AudioElement) continue;
      for (var key in entry.value) {
        noteOff(e, key);
      }
    }
  }

  /// _sounded is what each key held sounds as, through the channel's MIDI
  /// effects -- a chord's keys, kept to a scale -- and _soundCount how many
  /// held keys sound each, so one let go does not stop another's.
  final Map<String, Map<int, List<int>>> _sounded = {};
  final Map<String, Map<int, int>> _soundCount = {};

  /// _arps are the arpeggiators playing live, by element id.
  final Map<String, _LiveArp> _arps = {};

  void _soundOn(AudioElement e, InstrumentPart part, int key, int velocity) {
    var channel = _channelOf(e);
    var keys = liveKeys(part.effects, key, velocity);
    if (arpeggiatorOf(part.effects) case var arp?) {
      var live = _arps[e.id] ??= _LiveArp(Arpeggio(arp));
      live.pressed[key] = [for (var (k, _) in keys) k];
      live.velocity = velocity;
      live.timer ??= _startArp(e, live);
      return;
    }
    var counts = _soundCount.putIfAbsent(channel, () => {});
    _sounded.putIfAbsent(e.id, () => {})[key] = [for (var (k, _) in keys) k];
    for (var (k, v) in keys) {
      var n = counts[k] = (counts[k] ?? 0) + 1;
      if (n == 1) unawaited(audio.noteOn(channel, part, k, v));
    }
  }

  void _soundOff(AudioElement e, int key) {
    var channel = _channelOf(e);
    if (_arps[e.id] case var live?) {
      live.pressed.remove(key);
      if (live.pressed.isEmpty) {
        live.timer?.cancel();
        _arps.remove(e.id);
        if (live.sounding case var k?) audio.noteOff(channel, k);
      }
      return;
    }
    var keys = _sounded[e.id]?.remove(key) ?? [key];
    var counts = _soundCount[channel] ?? {};
    for (var k in keys) {
      var n = (counts[k] ?? 1) - 1;
      if (n <= 0) {
        counts.remove(k);
        audio.noteOff(channel, k);
      } else {
        counts[k] = n;
      }
    }
  }

  /// _startArp plays [live]'s held keys one at a time, a step apart at the
  /// tempo, each for the step's gate.
  Timer _startArp(AudioElement e, _LiveArp live) {
    var part = e.instrument!;
    var arp = arpeggiatorOf(part.effects)!;
    var stepSeconds = arpStepSeconds(arp, _document.audio.secondsPerBeat);
    var step = Duration(microseconds: (stepSeconds * 1e6).round());
    var gate = Duration(
        microseconds:
            (stepSeconds * arp.value("gate").clamp(0.1, 1.0) * 1e6).round());
    var channel = _channelOf(e);
    void play() {
      if (live.sounding case var k?) audio.noteOff(channel, k);
      live.sounding = null;
      var held = [for (var keys in live.pressed.values) ...keys];
      var key = live.player.next(held);
      if (key == null) return;
      live.sounding = key;
      unawaited(audio.noteOn(channel, part, key, live.velocity));
      Timer(gate, () {
        if (live.sounding == key) {
          audio.noteOff(channel, key);
          live.sounding = null;
        }
      });
    }

    play();
    return Timer.periodic(step, (_) => play());
  }

  /// noteOff lets [key] go.
  void noteOff(AudioElement e, int key) {
    if (_sustain && (_held[e.id]?.contains(key) ?? false)) {
      _sustained.putIfAbsent(e.id, () => {}).add(key);
      return;
    }
    if (!(_held[e.id]?.remove(key) ?? false)) return;
    _soundOff(e, key);
    _clipNoteOff(e, key);
    if (_take[e.id]?.remove(key) case (var start, var velocity)?) {
      var length = math.max(0.02, _nowInPart(e) - start);
      (_taken[e.id] ??= []).add(MidiNote(key, start, length, velocity));
    }
    notifyListeners();
  }

  /// _nowInPart is where the playhead is in [e]'s part, in seconds.
  double _nowInPart(AudioElement e) =>
      math.max(0, (_frame + betweenFrames - e.clip.at)) /
      math.max(1, _document.frameRate);

  /// recording is the control bar's Record: while it is on and the canvas
  /// plays, what is played on an instrument is written into its part.
  bool get recording => _recording;
  bool _recording = false;
  set recording(bool on) {
    if (_recording == on) return;
    _recording = on;
    if (on) {
      _take.clear();
      _taken.clear();
      _controlTake.clear();
      if (!playing) play();
    } else {
      _keepTake();
    }
    notifyListeners();
  }

  /// hasInstruments is whether there is anything to record onto.
  bool get hasInstruments => _document.elements
      .any((e) => e is AudioElement && e.instrument != null);

  /// _recordsInto is whether a recording writes into [e]: its channel is
  /// armed, or none is and every instrument played is.
  bool _recordsInto(AudioElement e) =>
      _armed.isEmpty || _armed.contains(_channelOf(e));

  /// _take is each instrument's notes being held while recording, as when
  /// each started and how hard; _taken the notes finished.
  final Map<String, Map<int, (double, int)>> _take = {};
  final Map<String, List<MidiNote>> _taken = {};

  /// _keepTake writes what was recorded into each part -- one change to
  /// undo -- notes still held ending where the playhead is.
  void _keepTake() {
    for (var e in _take.entries) {
      var el = _document.elementById(e.key);
      if (el is! AudioElement) continue;
      for (var k in e.value.entries) {
        var (start, velocity) = k.value;
        (_taken[e.key] ??= []).add(MidiNote(k.key, start,
            math.max(0.02, _nowInPart(el) - start), velocity));
      }
    }
    _take.clear();
    if (_taken.isEmpty && _clipLog.isEmpty && _controlTake.isEmpty) return;
    var next = _writeClipLog(_document);
    // The controllers moved, into each part's curves: over the stretch
    // recorded, what was there before is replaced.
    for (var e in _controlTake.entries) {
      var el = next.elementById(e.key);
      if (el is! AudioElement || el.instrument == null) continue;
      var part = el.instrument!;
      var controls = {...part.controls};
      for (var c in e.value.entries) {
        var took = c.value;
        var from = took.first.$1, to = took.last.$1;
        controls[c.key] = [
          for (var p in controls[c.key] ?? const <ControlPoint>[])
            if (p.$1 < from || p.$1 > to) p,
          ...took,
        ]..sort((a, b) => a.$1.compareTo(b.$1));
      }
      next = next.withElement(
          el.copyWith(instrument: part.copyWith(controls: controls)));
    }
    _controlTake.clear();
    for (var e in _taken.entries) {
      var el = next.elementById(e.key);
      if (el is! AudioElement || el.instrument == null) continue;
      var part = el.instrument!;
      next = next.withElement(el.copyWith(
          instrument: part.copyWith(
              notes: [...part.notes, ...e.value]
                ..sort((a, b) => a.start.compareTo(b.start)))));
    }
    _taken.clear();
    apply(next);
  }

  // ------------------------------------------------------------------------
  // The session view: clips launched live
  // ------------------------------------------------------------------------

  /// session is the clip slots and the scenes -- see session.dart.
  SessionGrid get session => _document.session;

  /// launchQuantise is what a launch waits for: the next bar, as Ableton's
  /// global quantisation does, or a finer grid, or nothing.
  Quantise get launchQuantise => _launchQuantise;
  Quantise _launchQuantise = Quantise.bar;
  set launchQuantise(Quantise q) {
    if (_launchQuantise == q) return;
    _launchQuantise = q;
    notifyListeners();
  }

  /// _clipChannels is what each channel is playing from its slots, and what
  /// it is about to.
  final Map<String, _ClipChannel> _clipChannels = {};

  /// _clipRecord is the clip being recorded into a slot, if one is.
  _ClipRecord? _clipRecord;

  /// _clipLog is what the slots have played since Record was pressed, to be
  /// written onto the timeline when it is let go.
  final List<_ClipPlayed> _clipLog = [];

  /// _sessionNow is where the session's clock is: the playhead, in seconds.
  /// The session keeps time with the timeline, so a clip launched on a bar
  /// is on the timeline's bar.
  double get _sessionNow => _sessionOnly
      ? _sessionSeconds
      : (_frame + betweenFrames) / math.max(1, _document.frameRate);

  /// sessionOnly is whether only the clip slots are playing: launched with
  /// the transport stopped, they run on a clock of their own -- the
  /// timeline silent and its playhead where it was, so a clip can be heard
  /// and edited without the piece going on round it. Play, or Back to the
  /// timeline, goes back to it.
  bool get sessionOnly => _sessionOnly;
  bool _sessionOnly = false;

  /// _sessionSeconds is the slots' own clock, playing on their own.
  double _sessionSeconds = 0;

  /// _offTimeline are the channels that have left the timeline for their
  /// slots, as Ableton's tracks do: a clip launched there while the
  /// timeline plays silences the channel's timeline -- and it stays silent,
  /// its clip stopped or not, until Back to the timeline.
  final Set<String> _offTimeline = {};

  /// offTimeline is whether what is heard is not the timeline: only the
  /// slots playing, or a channel left for its slots -- what Back to the
  /// timeline lights for.
  bool get offTimeline => _sessionOnly || _offTimeline.isNotEmpty;

  /// backToTimeline goes back to the timeline: playing only the slots, they
  /// stop; a channel that left it for its slots plays it again.
  void backToTimeline() {
    if (_sessionOnly) {
      pause();
      return;
    }
    if (_offTimeline.isEmpty) return;
    for (var key in [..._offTimeline]) {
      if (_clipChannels[key]?.now != null) stopChannelClips(key);
    }
    _offTimeline.clear();
    _syncTimeline();
    notifyListeners();
  }

  double get _barSeconds => _document.audio.secondsPerBar;

  /// _nextLaunch is the next moment a launch at [now] waits for: on
  /// [quantise] -- a clip's own -- or the song's.
  double _nextLaunch(double now, [Quantise? quantise]) {
    var g = _document.audio.gridSeconds(quantise ?? _launchQuantise);
    if (g == null || g <= 0) return now;
    // A hair past a boundary is on it, not a whole bar from it.
    return ((now - 0.005) / g).ceil() * g;
  }

  /// _sessionStart starts the transport for the session, from the start of
  /// the bar the playhead is in -- a launch with nothing playing is heard at
  /// once, on a bar -- and is where it started.
  double _sessionStart() {
    // The slots on their own, from nought: the timeline stays where it is,
    // and silent -- see sessionOnly.
    _sessionOnly = true;
    _sessionSeconds = 0;
    _startTimer();
    _syncTimeline();
    notifyListeners();
    return 0;
  }

  /// _launchTime is when a launch now is heard: the next boundary, playing;
  /// at once, from a bar, when it starts the transport.
  double _launchTime([Quantise? quantise]) =>
      playing ? _nextLaunch(_sessionNow, quantise) : _sessionStart();

  /// clipState is how slot [row] of [channel] is doing, for the mixer.
  ClipState clipState(String channel, int row) {
    var rec = _clipRecord;
    if (rec != null && rec.channel == channel && rec.row == row) {
      return rec.started ? ClipState.recording : ClipState.recordQueued;
    }
    var ch = _clipChannels[channel];
    if (ch?.next?.row == row) return ClipState.queued;
    if (ch?.now?.row == row) {
      return ch!.stopAt != null || ch.now!.stopAt != null
          ? ClipState.stopping
          : ClipState.playing;
    }
    return session.at(channel, row) == null
        ? ClipState.empty
        : ClipState.stopped;
  }

  /// clipPlaying is whether [channel] has a clip playing from its slots, or
  /// one about to.
  bool clipPlaying(String channel) {
    var ch = _clipChannels[channel];
    return ch != null && (ch.now != null || ch.next != null);
  }

  /// clipProgress is how far round its loop [channel]'s clip has got,
  /// nought to one, or null where none is playing.
  double? clipProgress(String channel) {
    var now = _clipChannels[channel]?.now;
    if (now == null || now.length <= 0) return null;
    var t = _sessionNow - now.origin;
    if (t < 0) return 0;
    if (!now.loops) return (t / now.length).clamp(0.0, 1.0);
    return ((now.into(t) - now.loopAt) / now.length).clamp(0.0, 1.0);
  }

  /// clipAt is where [channel]'s clip has got to, in beats into what it
  /// plays -- for the clip editor's playhead -- or null where none is
  /// playing.
  double? clipAt(String channel) {
    var now = _clipChannels[channel]?.now;
    if (now == null) return null;
    var t = _sessionNow - now.origin;
    if (t < 0) return null;
    if (!now.loops && t >= now.length) return null;
    return now.into(t) / math.max(0.001, _document.audio.secondsPerBeat);
  }

  /// anyClipPlaying is whether any slot is playing or about to.
  bool get anyClipPlaying => _clipChannels.keys.any(clipPlaying);

  /// sessionActive is whether the slots have anything going on -- playing,
  /// waiting for a bar, recording -- for the mixer to keep drawing them.
  bool get sessionActive => anyClipPlaying || _clipRecord != null;

  /// instrumentChannel is whether [channel] is a MIDI channel.
  bool instrumentChannel(String channel) => _instrumentOf(channel) != null;

  /// pressClip is a press on a clip's slot: what the clip's launch mode says
  /// -- see LaunchMode. On an empty slot, the channel stops; armed, it
  /// records into it. [velocity] is the pad's, nought to 127 -- a click is
  /// a full one -- for the clip's Velocity to set its volume by.
  void pressClip(String channel, int row, {int velocity = 127}) {
    var clip = session.at(channel, row);
    if (_clipRecord case var rec?
        when rec.channel == channel && rec.row == row) {
      _endClipRecord();
      return;
    }
    if (clip == null) {
      if (_armed.contains(channel) && _instrumentOf(channel) != null) {
        recordClip(channel, row);
      } else {
        stopChannelClips(channel);
      }
      return;
    }
    var state = clipState(channel, row);
    if (clip.launch == LaunchMode.toggle &&
        (state == ClipState.playing || state == ClipState.queued)) {
      stopChannelClips(channel);
      return;
    }
    var level = launchLevel(clip, velocity);
    launchClip(channel, row, level: level);
    // Repeat: again on every launch step while it is held -- see
    // _sessionStep.
    if (clip.launch == LaunchMode.repeat) {
      var a = _document.audio;
      var step = a.gridSeconds(clip.quantise ?? _launchQuantise) ?? 0;
      if (step <= 0) step = a.secondsPerBeat;
      _repeats[channel] =
          _Repeat(row, _launchTime(clip.quantise) + step, step, level);
    }
  }

  /// pushClip is a Push's pad in Session mode: slot [row] of the
  /// [column]th channel, as the mixer has them, pressed at [velocity] -- or
  /// let go, at nought.
  void pushClip(int column, int row, int velocity) {
    var lanes = timelineChannels;
    if (column < 0 || column >= lanes.length || row < 0) return;
    var channel = lanes[column].key;
    if (velocity > 0) {
      pressClip(channel, row, velocity: velocity);
    } else {
      releaseClip(channel, row);
    }
  }

  /// pushPad is how slot [row] of the [column]th channel is doing, for its
  /// pad's light.
  PadClip pushPad(int column, int row) {
    var lanes = timelineChannels;
    if (column < 0 || column >= lanes.length || row < 0) return PadClip.empty;
    return switch (clipState(lanes[column].key, row)) {
      ClipState.empty => PadClip.empty,
      ClipState.stopped => PadClip.stopped,
      ClipState.queued || ClipState.recordQueued => PadClip.queued,
      ClipState.playing || ClipState.stopping => PadClip.playing,
      ClipState.recording => PadClip.recording,
    };
  }

  /// launchLevel is how loud [clip] plays launched at [velocity]: its
  /// Velocity's share of the way from full to the pad's.
  static double launchLevel(SessionClip clip, int velocity) =>
      1 - clip.velocity * (1 - velocity.clamp(0, 127) / 127);

  /// _repeats are the Repeat clips held down, by channel.
  final Map<String, _Repeat> _repeats = {};

  /// releaseClip is a press on a clip let go: a gated clip stops, and a
  /// repeating one stops repeating, and playing.
  void releaseClip(String channel, int row) {
    var clip = session.at(channel, row);
    if (clip == null ||
        (clip.launch != LaunchMode.gate && clip.launch != LaunchMode.repeat)) {
      return;
    }
    if (_repeats[channel]?.row == row) _repeats.remove(channel);
    var ch = _clipChannels[channel];
    if (ch == null) return;
    if (ch.next?.row == row) _cancelNext(ch, restore: true);
    if (ch.now?.row == row) {
      _endPlay(channel, ch.now!, _sessionNow);
      if (ch.now!.voice case var v?) audio.engine.stopSoftly(v, 0.01);
      ch.now = null;
    }
    _syncTimeline();
    notifyListeners();
  }

  /// launchClip plays slot [row] of [channel] from the next launch time --
  /// see launchQuantise -- in place of whatever the channel was playing.
  void launchClip(String channel, int row, {double level = 1}) {
    var clip = session.at(channel, row);
    if (clip == null) return;
    var at = _launchTime(clip.quantise);
    unawaited(_startClip(channel, row, clip, at, level: level));
  }

  /// launchScene plays row [row] across every channel, all from the same
  /// moment: a channel with nothing in the row stops.
  void launchScene(int row) {
    var at = _launchTime();
    for (var c in timelineChannels) {
      var clip = session.at(c.key, row);
      if (clip != null) {
        unawaited(_startClip(c.key, row, clip, at));
      } else {
        _stopChannelAt(c.key, at);
      }
    }
    _sceneLaunched = row;
    notifyListeners();
  }

  /// sceneLaunched is the scene last launched, for the master to light.
  int? get sceneLaunched => anyClipPlaying ? _sceneLaunched : null;
  int? _sceneLaunched;

  /// stopChannelClips stops what [channel] plays from its slots, at the
  /// next launch time.
  void stopChannelClips(String channel) {
    _repeats.remove(channel);
    if (!clipPlaying(channel)) return;
    _stopChannelAt(channel, playing ? _nextLaunch(_sessionNow) : _sessionNow);
    notifyListeners();
  }

  /// stopAllClips stops every channel's slots, at the next launch time.
  void stopAllClips() {
    var at = playing ? _nextLaunch(_sessionNow) : _sessionNow;
    for (var key in [..._clipChannels.keys]) {
      _stopChannelAt(key, at);
    }
    if (_clipRecord != null) _endClipRecord();
    notifyListeners();
  }

  void _stopChannelAt(String channel, double at) {
    var ch = _clipChannels[channel];
    if (ch == null) return;
    _cancelNext(ch);
    var now = ch.now;
    if (now == null) return;
    ch.stopAt = at;
    if (now.voice case var v?) {
      audio.engine
          .stopIn(v, math.max(0, at - _sessionNow - audio.engine.latency));
    }
  }

  /// _cancelNext takes back what [ch] was about to launch. With [restore],
  /// what was to have stopped for it plays on: its stop was set for the
  /// launch and cannot be taken back, so it is set going again from where
  /// it is. Without, something else is about to stop it or take over.
  void _cancelNext(_ClipChannel ch, {bool restore = false}) {
    var next = ch.next;
    if (next == null) return;
    ch.next = null;
    if (next.voice case var v?) audio.engine.stop(v);
    if (!restore) return;
    if (ch.now case var now? when ch.stopAt == null) {
      if (now.voice case var v? when now.loops) {
        unawaited(_restart(ch, now));
        audio.engine.stop(v);
      }
    }
  }

  /// _restart sets [play] going again where it has got to: its stop, set
  /// for a launch since taken back, undone.
  Future<void> _restart(_ClipChannel ch, _ClipPlay play) async {
    var clip = session.at(ch.channel, play.row);
    var sound = play.sound ?? clip?.sound;
    if (clip == null || sound == null) return;
    var track = await audio.trackOf(sound.assetId);
    if (track == null || ch.now != play) return;
    var into = play.into(_sessionNow + audio.engine.latency - play.origin);
    play.voice = audio.engine.launch(track,
        volume: _gainOf(clip) * play.level,
        delay: 0,
        at: sound.start + into,
        loop: (
          sound.start + play.loopAt,
          sound.start + play.loopAt + play.length
        ),
        channel: ch.channel);
  }

  /// _startClip plays [clip] on [channel] from [at], session seconds: the
  /// file opened -- a MIDI clip played into one first -- and started by the
  /// engine to the frame, the clip before it stopped on the same frame.
  Future<void> _startClip(String channel, int row, SessionClip clip, double at,
      {double? origin, _ClipPlay? carries, double level = 1}) async {
    var ch = _clipChannels[channel] ??= _ClipChannel(channel);
    _cancelNext(ch);
    ch.stopAt = null;
    var spb = _document.audio.secondsPerBeat;
    var loopLength = math.max(0.05, clip.bars * _barSeconds);
    var loopAt = clip.loopStart * spb;
    // From its start: on into its loop, or -- not looping -- to the loop's
    // end. A start past the loop's end is the loop's start.
    var startAt = clip.start * spb;
    if (clip.loop && startAt >= loopAt + loopLength) startAt = loopAt;
    var play = _ClipPlay(
        clip.id,
        row,
        at,
        clip.loop ? loopLength : math.max(0.05, loopAt + loopLength - startAt),
        clip.loop,
        startAt: startAt,
        loopAt: loopAt)
      ..level = carries?.level ?? level;
    // Legato: on from where the clip it takes over from had got to.
    if (clip.legato) {
      if ((ch.now ?? ch.next) case var was?) play.origin = was.origin;
    }
    if (origin != null) play.origin = origin;
    if (carries != null) {
      play
        ..followed = carries.followed
        ..followFrom = carries.followFrom;
    }
    // What it takes over from: remembered now, because by the time its file
    // is open the clock may already have put it in that one's place, and
    // that one -- still sounding -- must still be stopped.
    var replaced = ch.now;
    ch.next = play;
    notifyListeners();
    // Still the channel's -- about to play, or by now playing: a launch on
    // a bar already reached is moved on to it before its file is open.
    bool still() => ch.next == play || ch.now == play;
    var sound =
        clip.midi ? await _clipSound(channel, clip) : await _playedSound(clip);
    play.sound = sound;
    if (!still()) return;
    var track = sound == null || !await audio.ready()
        ? null
        : await audio.trackOf(sound.assetId);
    if (!still()) return;
    var latency = audio.engine.latency;
    var delay = at - _sessionNow - latency;
    var into = 0.0;
    if (delay < 0) {
      // Late -- the file took a while to open: started where it would have
      // got to, so it is still in time.
      into = -delay;
      delay = 0;
    }
    for (var was in {replaced, ch.now}) {
      if (was == null || identical(was, play)) continue;
      if (was.voice case var v?) audio.engine.stopIn(v, delay);
    }
    if (track != null && sound != null) {
      // How far into it it is when it is heard: late, or taken over.
      var t = at - play.origin + into;
      if (!play.loops && t >= play.length) return;
      var voice = audio.engine.launch(track,
          volume: _gainOf(clip) * play.level,
          delay: delay,
          at: sound.start + play.into(t),
          loop: play.loops
              ? (
                  sound.start + play.loopAt,
                  sound.start + play.loopAt + play.length
                )
              : null,
          channel: channel);
      if (voice != null && !play.loops) {
        audio.engine.stopIn(voice, delay + play.length - t);
      }
      play.voice = voice;
    }
  }

  /// _playKey is what [clip] sounds like, for telling an edit that changes
  /// it -- its sound, where it starts and goes round, how loud, how it is
  /// warped, its notes -- from one that does not: its name, its colour.
  String _playKey(SessionClip clip) => [
        clip.midi
            ? "${clip.notes.map((n) => n.toJson().join(",")).join(";")}:"
                "${controlsToJson(clip.controls)}"
            : "${clip.sound?.assetId}:${clip.sound?.start}:${clip.sound?.end}",
        clip.start,
        clip.loopStart,
        clip.bars,
        clip.loop,
        clip.gain,
        if (!clip.midi) clip.warpSignature(_document.audio.secondsPerBeat),
      ].join("|");

  /// _followEdits plays each clip that is playing as it now is, where it
  /// was changed since [before]: from where it had got to, so an edit --
  /// reversed, its loop moved, its notes -- is heard at once, not at its
  /// next launch.
  void _followEdits(CanvasDocument before) {
    if (_clipChannels.isEmpty || identical(before.session, session)) return;
    for (var ch in [..._clipChannels.values]) {
      var now = ch.now;
      if (now == null || ch.stopAt != null) continue;
      var clip = _clipById(now.clipId);
      if (clip == null) continue;
      SessionClip? was;
      for (var (_, _, c) in before.session.clips) {
        if (c.id == now.clipId) was = c;
      }
      if (was == null || _playKey(was) == _playKey(clip)) continue;
      unawaited(_startClip(ch.channel, now.row, clip, _sessionNow,
          origin: now.origin, carries: now));
    }
  }

  /// _gainOf is [clip]'s gain as a level.
  double _gainOf(SessionClip clip) => math.pow(10, clip.gain / 20).toDouble();

  final math.Random _followDice = math.Random();

  /// _follow does [clip]'s follow action, played on [ch] as [play], at
  /// [due]: see FollowAction.
  void _follow(_ClipChannel ch, _ClipPlay play, SessionClip clip, double due) {
    // A launch already waiting is what the player chose: it goes ahead.
    if (ch.next != null) return;
    var rows = [
      for (var r = 0; r < session.rows; r++)
        if (session.at(ch.channel, r) != null) r
    ];
    var here = rows.indexOf(play.row);
    if (rows.isEmpty || here < 0) return;
    int? row;
    switch (clip.follow) {
      case FollowAction.none:
        return;
      case FollowAction.stop:
        _stopChannelAt(ch.channel, due);
        return;
      case FollowAction.again:
        row = play.row;
      case FollowAction.next:
        row = rows[(here + 1) % rows.length];
      case FollowAction.previous:
        row = rows[(here - 1 + rows.length) % rows.length];
      case FollowAction.first:
        row = rows.first;
      case FollowAction.last:
        row = rows.last;
      case FollowAction.any:
        row = rows[_followDice.nextInt(rows.length)];
      case FollowAction.other:
        if (rows.length < 2) return;
        var others = [...rows]..remove(play.row);
        row = others[_followDice.nextInt(others.length)];
    }
    var next = session.at(ch.channel, row)!;
    unawaited(_startClip(ch.channel, row, next, due));
  }

  /// _sessionStep moves the slots on to [now]: a launch due starts, a stop
  /// due stops, a clip played once ends, a recording due starts or ends.
  /// Every tick, while playing.
  void _sessionStep(double now) {
    var moved = false;
    // The Repeat clips held: launched again a moment before each step, so
    // they are heard on it.
    for (var MapEntry(key: channel, value: r) in [..._repeats.entries]) {
      // Never so early that it takes the place of the one before, still
      // waiting to be heard: at most half a step ahead.
      if (now + math.min(0.25, r.step / 2) < r.nextAt) continue;
      var clip = session.at(channel, r.row);
      if (clip == null) {
        _repeats.remove(channel);
        continue;
      }
      unawaited(_startClip(channel, r.row, clip, r.nextAt, level: r.level));
      r.nextAt += r.step;
    }
    for (var ch in _clipChannels.values) {
      if (ch.next case var next? when now + 0.001 >= next.from) {
        if (ch.now case var was?) _endPlay(ch.channel, was, next.from);
        // Left the timeline for its slots, until Back to the timeline.
        if (!_sessionOnly) _offTimeline.add(ch.channel);
        ch.now = next;
        ch.next = null;
        ch.stopAt = null;
        moved = true;
      }
      var cur = ch.now;
      if (cur == null) continue;
      // Its follow action, set up a moment before it is due -- so its
      // launch is heard on time.
      if (!cur.followed && ch.stopAt == null) {
        var clip = _clipById(cur.clipId);
        if (clip != null && clip.follow != FollowAction.none) {
          var after = clip.followBars != null
              ? clip.followBars! * _barSeconds
              : cur.length;
          var due = cur.followFrom + math.max(0.05, after);
          if (now + 0.25 >= due) {
            cur.followed = true;
            _follow(ch, cur, clip, due);
          }
        }
      }
      var ends = ch.stopAt ?? (cur.loops ? null : cur.origin + cur.length);
      if (ends != null && now + 0.001 >= ends) {
        _endPlay(ch.channel, cur, ends);
        ch.now = null;
        ch.stopAt = null;
        moved = true;
      }
    }
    if (_clipRecord case var rec?) {
      if (rec.until case var until? when now + 0.001 >= until) {
        _finishClipRecord(rec, until);
        moved = true;
      } else if (!rec.started && now + 0.001 >= rec.from) {
        rec.started = true;
        moved = true;
      }
    }
    if (moved) {
      _syncTimeline();
      notifyListeners();
    }
  }

  /// _endPlay notes [play] as played to [to], for Record to write down.
  void _endPlay(String channel, _ClipPlay play, double to) {
    if (!_recording || to <= play.from) return;
    var clip = _clipById(play.clipId);
    if (clip != null) _clipLog.add(_ClipPlayed(channel, clip, play.from, to));
  }

  SessionClip? _clipById(String id) {
    for (var (_, _, c) in session.clips) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// _haltClips stops everything the slots play, at once: the transport
  /// has stopped.
  void _haltClips() {
    var now = _sessionNow;
    for (var ch in _clipChannels.values) {
      if (ch.next?.voice case var v?) audio.engine.stop(v);
      if (ch.now case var cur?) {
        _endPlay(ch.channel, cur, ch.stopAt ?? now);
        if (cur.voice case var v?) audio.engine.stopSoftly(v, 0.02);
      }
    }
    _clipChannels.clear();
    if (_clipRecord case var rec?) {
      if (rec.started) {
        _finishClipRecord(rec, now, launch: false);
      } else {
        _clipRecord = null;
      }
    }
  }

  /// _sessionSilenced is whether [key]'s timeline is quiet: a channel
  /// playing from its slots is not playing the timeline, as Ableton's is
  /// not -- until its slots are stopped.
  bool _sessionSilenced(String key) =>
      _sessionOnly ||
      _offTimeline.contains(key) ||
      (_clipChannels[key]?.now != null &&
          _clipChannels[key]!.now!.from <= _sessionNow + 0.001);

  // ---- Recording into a slot

  /// recordClip records what is played on [channel]'s instrument into its
  /// empty slot [row], from the next launch time until it is pressed again
  /// -- then rounded up to whole bars, and played round at once.
  void recordClip(String channel, int row) {
    if (_instrumentOf(channel) == null || session.at(channel, row) != null) {
      return;
    }
    if (_clipRecord != null) _endClipRecord();
    if (!_armed.contains(channel)) {
      _armed
        ..clear()
        ..add(channel);
    }
    var at = _launchTime();
    _stopChannelAt(channel, at);
    _clipRecord = _ClipRecord(channel, row, at);
    notifyListeners();
  }

  /// _endClipRecord ends the recording at the end of the bar it is in.
  void _endClipRecord() {
    var rec = _clipRecord;
    if (rec == null) return;
    if (!rec.started || !playing) {
      _clipRecord = null;
      notifyListeners();
      return;
    }
    var bar = math.max(0.05, _barSeconds);
    var bars = math.max(1, ((_sessionNow - rec.from) / bar - 0.02).ceil());
    rec.until = rec.from + bars * bar;
    notifyListeners();
  }

  /// _finishClipRecord makes what was recorded into the slot's clip -- one
  /// change to undo -- and, with [launch], plays it round from [until].
  void _finishClipRecord(_ClipRecord rec, double until, {bool launch = true}) {
    _clipRecord = null;
    var spb = math.max(0.001, _document.audio.secondsPerBeat);
    for (var h in rec.held.entries) {
      var (start, velocity) = h.value;
      rec.notes.add(MidiNote(h.key, start,
          math.max(0.02, (until - rec.from) / spb - start), velocity));
    }
    var bars = math.max(1.0,
        ((until - rec.from) / math.max(0.05, _barSeconds)).roundToDouble());
    var index = timelineChannels.indexWhere((c) => c.key == rec.channel);
    var clip = SessionClip(
      id: newElementId(),
      name: "Recording",
      color: math.max(0, index) % sectionColors.length,
      midi: true,
      notes: rec.notes..sort((a, b) => a.start.compareTo(b.start)),
      bars: bars,
    );
    apply(_document.copyWith(session: session.put(rec.channel, rec.row, clip)));
    if (launch && playing) {
      unawaited(_startClip(rec.channel, rec.row, clip, until));
    }
  }

  /// _clipNoteOn and _clipNoteOff write a key played on [e] into the slot
  /// being recorded, where it is [e]'s channel's.
  void _clipNoteOn(AudioElement e, int key, int velocity) {
    var rec = _clipRecord;
    if (rec == null || !rec.started || rec.channel != _channelOf(e)) return;
    var spb = math.max(0.001, _document.audio.secondsPerBeat);
    rec.held[key] = ((_sessionNow - rec.from) / spb, velocity);
  }

  void _clipNoteOff(AudioElement e, int key) {
    var rec = _clipRecord;
    if (rec == null || rec.channel != _channelOf(e)) return;
    if (rec.held.remove(key) case (var start, var velocity)?) {
      var spb = math.max(0.001, _document.audio.secondsPerBeat);
      var end = (_sessionNow - rec.from) / spb;
      rec.notes
          .add(MidiNote(key, start, math.max(0.02, end - start), velocity));
    }
  }

  // ---- What is in the slots

  /// setSessionClip puts [clip] in slot [row] of [channel], or empties it.
  void setSessionClip(String channel, int row, SessionClip? clip) {
    if (clip == null) {
      var ch = _clipChannels[channel];
      if (ch != null && (ch.now?.row == row || ch.next?.row == row)) {
        _stopChannelAt(channel, _sessionNow);
      }
    }
    apply(_document.copyWith(session: session.put(channel, row, clip)));
  }

  /// soundsOf are the sounds on [channel]'s timeline, each once: what an
  /// audio channel's empty slot offers to hold.
  List<MediaSource> soundsOf(String channel) {
    var seen = <String>{};
    var out = <MediaSource>[];
    for (var c in timelineChannels) {
      if (c.key != channel) continue;
      for (var lane in c.lanes) {
        var e = lane.element;
        if (e is AudioElement && e.instrument != null) continue;
        for (var s in lane.clip.playlist) {
          var id =
              e is VideoElement && s.soundId.isNotEmpty ? s.soundId : s.assetId;
          if (seen.add("$id:${s.start}:${s.end}")) {
            out.add(id == s.assetId ? s : s.copyWith(assetId: id));
          }
        }
      }
    }
    return out;
  }

  /// clipFromSound fills slot [row] of [channel] with [sound], as long in
  /// whole bars as it nearly is.
  void clipFromSound(String channel, int row, MediaSource sound) {
    var bar = math.max(0.05, _barSeconds);
    var span = sound.span;
    var index = timelineChannels.indexWhere((c) => c.key == channel);
    setSessionClip(
        channel,
        row,
        SessionClip(
          id: newElementId(),
          name: sound.name,
          color: math.max(0, index) % sectionColors.length,
          sound: sound,
          bars: span <= 0 ? 4 : math.max(1, (span / bar).round()).toDouble(),
        ));
  }

  /// newMidiClip fills slot [row] of a MIDI channel with an empty clip of
  /// [bars] -- or with the channel's part, with [fromPart].
  void newMidiClip(String channel, int row,
      {double bars = 1, bool fromPart = false}) {
    var e = _instrumentOf(channel);
    if (e == null) return;
    var spb = math.max(0.001, _document.audio.secondsPerBeat);
    var notes = fromPart
        ? [
            for (var n in e.instrument!.notes)
              MidiNote(n.key, n.start / spb, n.length / spb, n.velocity),
          ]
        : <MidiNote>[];
    if (fromPart && notes.isNotEmpty) {
      var end = notes.map((n) => n.end).reduce(math.max);
      bars = math.max(1, (end / _document.audio.beatsPerBar).ceil()).toDouble();
    }
    var index = timelineChannels.indexWhere((c) => c.key == channel);
    setSessionClip(
        channel,
        row,
        SessionClip(
          id: newElementId(),
          name: fromPart ? "${e.name} part" : "MIDI clip",
          color: math.max(0, index) % sectionColors.length,
          midi: true,
          notes: notes,
          // Its controllers' curves with it, in beats as its notes are.
          controls: fromPart
              ? {
                  for (var c in e.instrument!.controls.entries)
                    c.key: [for (var (t, v) in c.value) (t / spb, v)],
                }
              : const {},
          bars: bars,
        ));
  }

  /// emptySlotOf is the first empty slot of [channel], or null when every
  /// one is full.
  int? emptySlotOf(String channel) {
    for (var row = 0; row < session.rows; row++) {
      if (session.at(channel, row) == null) return row;
    }
    return null;
  }

  /// partToSlot copies the piano roll's part into the first empty slot of
  /// its channel and opens it there, in the clip editor: launched from its
  /// slot, with the launch settings a part, playing with the timeline, has
  /// none of.
  void partToSlot() {
    var t = pianoRoll;
    if (t == null || t.row != null) return;
    var row = emptySlotOf(t.channel);
    if (row == null) return;
    newMidiClip(t.channel, row, fromPart: true);
    openClipEditor(t.channel, row);
  }

  /// addClipScene, removeClipScene and renameClipScene change the session
  /// grid's rows -- not the canvas's own scenes.
  void addClipScene({int? after}) =>
      apply(_document.copyWith(session: session.withScene(after: after)));

  void removeClipScene(int row) {
    for (var key in [..._clipChannels.keys]) {
      var ch = _clipChannels[key]!;
      if (ch.now?.row == row || ch.next?.row == row) {
        _stopChannelAt(key, _sessionNow);
      }
    }
    apply(_document.copyWith(session: session.withoutScene(row)));
  }

  void renameClipScene(int row, String name) =>
      apply(_document.copyWith(session: session.renameScene(row, name)));

  /// instrumentOf is [channel]'s instrument, for a MIDI channel, or null.
  AudioElement? instrumentOf(String channel) => _instrumentOf(channel);

  /// setChannelPart changes the part of MIDI channel [channel]'s instrument
  /// -- its input, its Monitor, its MIDI effects -- by [change].
  void setChannelPart(
      String channel, InstrumentPart Function(InstrumentPart part) change,
      {bool transient = false}) {
    var e = _instrumentOf(channel);
    if (e == null) return;
    // A held key let go first: sounding through the old effects, it would
    // never be let go through the new.
    for (var key in [...?_held[e.id]]) {
      noteOff(e, key);
    }
    setInstrument(e, change(e.instrument!), transient: transient);
  }

  /// _instrumentOf is [channel]'s instrument, for a MIDI channel.
  AudioElement? _instrumentOf(String channel) {
    for (var e in _document.elements) {
      if (e is AudioElement &&
          e.instrument != null &&
          _channelOf(e) == channel) {
        return e;
      }
    }
    return null;
  }

  /// _clipSound is a MIDI clip's notes played into a file by [channel]'s
  /// instrument -- once for each way it sounds, and kept on the clip, so it
  /// is played again only when it changes. Null for a clip with nothing in
  /// it, or nothing to play it.
  Future<MediaSource?> _clipSound(String channel, SessionClip clip) async {
    var e = _instrumentOf(channel);
    if (e == null || clip.notes.isEmpty) return null;
    var spb = _document.audio.secondsPerBeat;
    var part = e.instrument!;
    var signature = clip.signature(part, spb);
    if (clip.rendered == signature && clip.sound != null) return clip.sound;
    try {
      var bankHere = part.sound == InstrumentSound.bank && await bankReady();
      var wav = await partRenderer(clip.partOf(part, spb).played(spb),
          bankPath: bankHere ? await soundBankPath() : null);
      var id = await partStore(wav);
      if (id == null || _disposed) return null;
      var sound = MediaSource(assetId: id, name: "${clip.name} (played)");
      // Written onto the clip as it is now, if it is still there: not a
      // change of its own to undo -- the file follows the notes.
      if (session.find(clip.id) case (var ch, var row)?) {
        var now = session.at(ch, row)!;
        if (now.signature(part, spb) == signature) {
          apply(
              _document.copyWith(
                  session: session.put(ch, row,
                      now.copyWith(sound: sound, rendered: signature))),
              transient: true);
        }
      }
      return sound;
    } catch (exception) {
      debugPrint("Unable to play the clip: $exception");
      return null;
    }
  }

  /// _writeClipLog writes what the slots played while Record was on onto
  /// the timeline: an audio clip as its sound, round as many times as it
  /// went, on its channel; a MIDI clip's notes into its channel's part.
  /// Part of the take: one change with it.
  CanvasDocument _writeClipLog(CanvasDocument doc) {
    if (_clipLog.isEmpty) return doc;
    var rate = math.max(1, doc.frameRate);
    var spb = math.max(0.001, doc.audio.secondsPerBeat);
    var next = doc;
    for (var played in _clipLog) {
      var clip = played.clip;
      var pieces = clipPieces(
          clip, played.to - played.from, spb, doc.audio.secondsPerBar);
      if (clip.midi) {
        var e = next.elements
            .whereType<AudioElement>()
            .where(
                (a) => a.instrument != null && _channelOf(a) == played.channel)
            .firstOrNull;
        if (e == null) continue;
        var base = e.clip.at / rate;
        var added = <MidiNote>[];
        for (var (from, to, heard) in pieces) {
          for (var n in clip.notes) {
            var at = n.start * spb;
            if (at < from - 1e-6 || at >= to - 1e-6) continue;
            var start = played.from + heard + at - from;
            var len = math.min(n.length * spb, played.to - start);
            if (start - base < 0 || len <= 0) continue;
            added.add(MidiNote(n.key, start - base, len, n.velocity));
          }
        }
        var part = e.instrument!;
        next = next.withElement(e.copyWith(
            instrument: part.copyWith(
                notes: [...part.notes, ...added]
                  ..sort((a, b) => a.start.compareTo(b.start)))));
      } else if ((clip.needsRender
              ? (clip.warped ?? _clipById(clip.id)?.warped)
              : clip.sound)
          case var sound?) {
        var playlist = <MediaSource>[];
        var full = sound.span > 0 ? sound.span : double.infinity;
        for (var (from, to, _) in pieces) {
          if (from >= full || to - from < 0.01) continue;
          playlist.add(sound.copyWith(
              start: sound.start + from,
              end: sound.start + math.min(to, full)));
        }
        if (playlist.isEmpty) continue;
        next = next.addElement(AudioElement(
          ElementBase(
              id: newElementId(),
              name: clip.name.isEmpty ? "Clip" : clip.name,
              visible: false),
          clip: MediaClip(
              playlist: playlist,
              timed: true,
              at: (played.from * rate).round(),
              channel: played.channel),
          controls: const [],
        ));
      }
    }
    _clipLog.clear();
    return next;
  }

  // ------------------------------------------------------------------------
  // Played as a game
  // ------------------------------------------------------------------------

  GameRun? _game;
  CanvasDocument? _gameView;
  Timer? _gameTimer;
  final Stopwatch _gameWatch = Stopwatch();

  /// gaming is whether the canvas is being played as a game: what is set to
  /// be played answers the keys and the controllers, and the view follows
  /// the player. See canvas_game.dart.
  bool get gaming => _game != null;

  /// game is the game going, or null.
  GameRun? get game => _game;

  /// gameView is the canvas as the game has it now, for the stage to draw
  /// -- or null, not playing.
  CanvasDocument? get gameView => _gameView;

  /// makingGame is whether the canvas is being made into a game -- see
  /// CanvasDocument.game. Stopped being one, it stops being played.
  set makingGame(bool on) {
    if (on == _document.game) return;
    if (!on) gaming = false;
    apply(_document.copyWith(game: on));
  }

  set gaming(bool on) {
    if (on == gaming) return;
    if (on) {
      // On the scene it starts on -- a title screen, a menu -- and back to
      // the one being worked on after.
      _sceneBeforeGame = _document.at;
      var start = _document.gameStart.isEmpty
          ? -1
          : _document.sceneIndexNamed(_document.gameStart);
      if (start >= 0 && start != _document.at) goToScene(start);
      // From its beginning -- a title, a wait for Space -- not wherever the
      // playhead was left while it was being made.
      frame = 0;
      var run = GameRun();
      _game = run;
      unawaited(run.listen());
      HardwareKeyboard.instance.addHandler(_gameKey);
      _gameWatch
        ..reset()
        ..start();
      _gameTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        var dt = _gameWatch.elapsedMicroseconds / 1e6;
        _gameWatch
          ..reset()
          ..start();
        stepGame(math.min(dt, 0.05));
      });
      if (!playing) play();
    } else {
      HardwareKeyboard.instance.removeHandler(_gameKey);
      _gameTimer?.cancel();
      _gameTimer = null;
      _game?.dispose();
      _game = null;
      _gameView = null;
      if (playing) pause();
      if (_sceneBeforeGame case var at? when at != _document.at) {
        goToScene(at);
      }
      _sceneBeforeGame = null;
    }
    notifyListeners();
  }

  /// stepGame moves the game on by [dt] seconds.
  void stepGame(double dt) {
    var run = _game;
    if (run == null) return;
    run.step(_document, _frame, dt);
    // What the game asked for: a sound, another scene, the end.
    var asked = [...run.events];
    run.events.clear();
    for (var event in asked) {
      if (event.sound case var id?) {
        if (_audioById(id) case var sound?) {
          audio.stop(id);
          unawaited(audio.play(sound));
        }
      }
      // Another scene: a chosen one, the next -- the game over after the
      // last -- or, started again, the game's first.
      if (event.scene case var id?) _gameScene(run, id);
      if (event.next) {
        var next = _document.at + 1;
        if (next >= _document.allScenes.length) {
          gaming = false;
          return;
        }
        goToScene(next);
        frame = 0;
        run.newScene();
      }
      if (event.restart && _document.gameStart.isNotEmpty) {
        _gameScene(run, _document.gameStart);
      }
      if (event.press case var id?) _gamePress(run, id);
      if (event.stop) {
        gaming = false;
        return;
      }
    }
    _gameView = run.view(_document, frame: _frame);
    notifyListeners();
  }

  /// waitingFor is the action a stop is waiting for, by id, or null.
  String? get waitingFor => _waitingFor;
  String? _waitingFor;
  StreamSubscription<NormalizedGamepadEvent>? _waitPads;

  /// _waitForAction holds a stop until [id] is pressed -- on the keyboard
  /// or a controller -- and then plays on. Play pressed meanwhile ends the
  /// wait too.
  void _waitForAction(String id) {
    _endWait();
    _waitingFor = id;
    HardwareKeyboard.instance.addHandler(_waitKey);
    var input = GameInput();
    try {
      _waitPads = Gamepads.normalizedEvents.listen((e) {
        input.gamepad(e);
        var action = _waitedAction;
        if (action != null && action.pad.any(input.pad.contains)) {
          _goOnFromWait();
        }
      });
    } catch (exception) {
      debugPrint("Controllers are not available: $exception");
    }
  }

  ControlAction? get _waitedAction =>
      _document.controlsNow.where((a) => a.id == _waitingFor).firstOrNull;

  bool _waitKey(KeyEvent event) => waitKey(event);

  /// waitKey is a key while a stop waits: the waited action's, pressed,
  /// plays on.
  @visibleForTesting
  bool waitKey(KeyEvent event) {
    var action = _waitedAction;
    if (action == null || event is! KeyDownEvent) return false;
    if (!action.keys.contains(event.logicalKey.keyId)) return false;
    _goOnFromWait();
    return true;
  }

  void _goOnFromWait() {
    _endWait();
    play();
  }

  void _endWait() {
    if (_waitingFor == null) return;
    _waitingFor = null;
    HardwareKeyboard.instance.removeHandler(_waitKey);
    unawaited(_waitPads?.cancel());
    _waitPads = null;
  }

  /// _sceneBeforeGame is the scene showing when the game was started, to go
  /// back to when it stops.
  int? _sceneBeforeGame;

  /// _gameScene goes to the scene [id] -- by id or name -- for the game:
  /// its players where they were put, the counts carried on.
  void _gameScene(GameRun run, String id) {
    var to = _document.sceneIndexNamed(id);
    if (to < 0) return;
    goToScene(to);
    // From its beginning, not the frame it was left on while it was made.
    frame = 0;
    run.newScene();
  }

  /// _gamePress is [id] pressed by an action while the game plays: what a
  /// click on it would do -- a Button's own action, else the press it was
  /// given. Shown or hidden is the game's, not the document's: stopped, the
  /// gate is where it was put. A link is not followed mid-game.
  void _gamePress(GameRun run, String id) {
    var e = _document.elementById(id);
    if (e == null) return;
    var action = e is ButtonElement ? e.action : e.base.play.press;
    switch (action.kind) {
      case ButtonActionKind.toggleElement:
        if (action.elementId.isNotEmpty) run.toggle(action.elementId);
      case ButtonActionKind.goToScene:
        _gameScene(run, action.elementId);
      case ButtonActionKind.openLink:
        break;
      default:
        runButtonAction(action);
    }
  }

  /// gameKey is a key while playing: held, let go -- and taken, where it
  /// presses one of the actions, so Space jumps rather than pausing.
  /// Escape stops the game.
  bool _gameKey(KeyEvent event) => gameKey(event);

  @visibleForTesting
  bool gameKey(KeyEvent event) {
    var run = _game;
    if (run == null) return false;
    var id = event.logicalKey.keyId;
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      gaming = false;
      return true;
    }
    var bound = _document.players
        .any((p) => _document.controlsFor(p).any((a) => a.keys.contains(id)));
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      run.input.keys.add(id);
    } else if (event is KeyUpEvent) {
      run.input.keys.remove(id);
    }
    return bound;
  }

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

  /// practising is the Sheet music being practised, or null.
  String? get practising => _practice;

  double get _clockRate {
    var sheet = _practice == null ? null : _document.elementById(_practice!);
    return sheet is SheetElement ? sheet.tempo : 1;
  }

  /// _practised is the sheet being practised, the instrument it follows,
  /// and its part -- or null where one of them has gone.
  (SheetElement, AudioElement, InstrumentPart)? get _practised {
    var sheet = _practice == null ? null : _document.elementById(_practice!);
    if (sheet is! SheetElement) return null;
    var inst = _document.elementById(sheet.follows);
    if (inst is! AudioElement || inst.instrument == null) return null;
    return (sheet, inst, inst.instrument!);
  }

  /// _mine is whether note [i] is the player's to play: of the hand being
  /// practised -- the right hand from middle C up -- and not in Listen.
  static bool _mine(SheetElement sheet, MidiNote n) =>
      sheet.mode != PracticeMode.listen &&
      switch (sheet.hands) {
        PracticeHands.right => n.key >= splitKey,
        PracticeHands.left => n.key < splitKey,
        PracticeHands.both => true,
      };

  int _noteFrame(AudioElement inst, MidiNote n) =>
      inst.clip.at + (n.start * math.max(1, _document.frameRate)).round();

  int _noteEndFrame(AudioElement inst, MidiNote n) =>
      inst.clip.at + (n.end * math.max(1, _document.frameRate)).round();

  /// importScore puts MusicXML [score] into the part of the instrument
  /// [sheet] shows, in place of its notes -- laid on this canvas's tempo,
  /// so its bars are this canvas's bars -- and writes [sheet] in its key.
  /// One change to undo. Answers why not.
  String? importScore(SheetElement sheet, MusicXmlScore score) {
    var e = _document.elementById(sheet.follows);
    if (e is! AudioElement || e.instrument == null) {
      return "Choose the instrument it shows first.";
    }
    var notes = score.played(_document.audio.tempo);
    var next = _document
        .withElement(
            e.copyWith(instrument: e.instrument!.copyWith(notes: notes)))
        .withElement(sheet.copyWith(
            key: score.fifths,
            title: sheet.title.isEmpty ? score.title : null));
    apply(next);
    return null;
  }

  /// exportScore is the part [sheet] shows, as MusicXML -- written as it is
  /// engraved -- or null where it shows none.
  String? exportScore(SheetElement sheet) {
    var e = _document.elementById(sheet.follows);
    if (e is! AudioElement || e.instrument == null) return null;
    var audio = _document.audio;
    return scoreToMusicXml(sheetScore(e.instrument!, audio, fifths: sheet.key),
        title: sheet.title, tempo: audio.tempo);
  }

  /// startPractice starts a take on [sheet]: the marks cleared, playing
  /// from the playhead.
  void startPractice(SheetElement sheet) {
    if (playing) pause();
    _marks.clear();
    _wrongKeys.clear();
    _waiting.clear();
    _found.clear();
    _practice = sheet.id;
    sheetMarksOf = _sheetMarks;
    play();
    notifyListeners();
  }

  /// stopPractice ends the take, its marks left to look at.
  void stopPractice() => pause();

  void _endPractice() {
    var p = _practised;
    if (p != null) {
      for (var k in _accompanying) {
        audio.noteOff(_channelOf(p.$2), k);
      }
    }
    _accompanying.clear();
    _waiting.clear();
    _practice = null;
    // The take's marks stay on the score until the next.
  }

  SheetMarks _sheetMarks(SheetElement e) => SheetMarks(
      marks: Map.of(_marks),
      waiting: _practice == e.id ? Set.of(_waiting) : const {},
      wrongKeys: Map.of(_wrongKeys));

  /// practiceScore is the take so far: how many right, how many wrong.
  (int, int) get practiceScore => (
        _marks.values.where((m) => m == NoteMark.right).length,
        _marks.values.where((m) => m == NoteMark.wrong).length
      );

  /// _practiceHolds is whether the playhead holds before [next], waiting
  /// to be played -- Wait for me, a note of the player's there unplayed.
  bool _practiceHolds(int next) {
    var p = _practised;
    if (p == null) return false;
    var (sheet, inst, part) = p;
    if (sheet.mode != PracticeMode.wait) return false;
    if (_waiting.isNotEmpty) return true;
    for (var (i, n) in part.notes.indexed) {
      if (!_mine(sheet, n) || _found.contains(i)) continue;
      // Due on the frame it is on, or the one it is going to.
      var f = _noteFrame(inst, n);
      if (f >= _frame && f <= next) _waiting.add(i);
    }
    return _waiting.isNotEmpty;
  }

  /// _practiceStep is the playhead gone from [was] to [now]: the other
  /// hand's notes started and stopped, and -- playing along -- the notes
  /// gone by unplayed marked missed.
  void _practiceStep(int was, int now) {
    var p = _practised;
    if (p == null) return;
    var (sheet, inst, part) = p;
    var channel = _channelOf(inst);
    if (now < was) {
      // Round a loop: everything let go, and the take begun again -- the
      // notes from where it starts again marked afresh, each time round.
      for (var k in _accompanying) {
        audio.noteOff(channel, k);
      }
      _accompanying.clear();
      _waiting.clear();
      for (var (i, n) in part.notes.indexed) {
        if (_noteFrame(inst, n) >= now) {
          _marks.remove(i);
          _wrongKeys.remove(i);
          _found.remove(i);
        }
      }
    }
    var rate = math.max(1, _document.frameRate);
    for (var (i, n) in part.notes.indexed) {
      var start = _noteFrame(inst, n), end = _noteEndFrame(inst, n);
      if (!_mine(sheet, n)) {
        // Each stretch from where it was up to where it is, so a note on
        // the very first frame is played, and none twice.
        if (start >= was && start < now) {
          unawaited(audio.noteOn(channel, part, n.key, n.velocity));
          _accompanying.add(n.key);
        }
        if (end >= was && end < now && _accompanying.remove(n.key)) {
          audio.noteOff(channel, n.key);
        }
        continue;
      }
      if (sheet.mode == PracticeMode.along &&
          !_marks.containsKey(i) &&
          now - start > 0.25 * rate &&
          was - start <= 0.25 * rate) {
        _marks[i] = NoteMark.missed;
      }
    }
  }

  /// _practiceHeard is [key] played on [inst]: right, if it is a note of
  /// the player's due now; wrong, if one is due and this is not it.
  void _practiceHeard(AudioElement inst, int key) {
    var p = _practised;
    if (p == null || p.$2.id != inst.id) return;
    var (sheet, followed, part) = p;
    if (sheet.mode == PracticeMode.listen) return;
    if (sheet.mode == PracticeMode.wait) {
      if (_waiting.isEmpty) return;
      var hit = _waiting.where((i) => part.notes[i].key == key).firstOrNull;
      if (hit != null) {
        // Found: it goes on. Right only where it was right the first time
        // -- a wrong key before it stays marked, with the key that was
        // played, so the score says how the take really went.
        _waiting.remove(hit);
        _found.add(hit);
        _marks.putIfAbsent(hit, () => NoteMark.right);
      } else {
        var first = _waiting.first;
        _marks.putIfAbsent(first, () => NoteMark.wrong);
        _wrongKeys[first] = key;
      }
      return;
    }
    // Playing along: the nearest of the player's notes due within a quarter
    // of a second either way.
    var rate = math.max(1, _document.frameRate);
    var now = _frame + betweenFrames;
    int? due;
    var best = double.infinity;
    for (var (i, n) in part.notes.indexed) {
      if (!_mine(sheet, n) || _marks.containsKey(i)) continue;
      var d = (_noteFrame(followed, n) - now).abs() / rate;
      if (d > 0.25) continue;
      if (n.key == key) {
        _marks[i] = NoteMark.right;
        return;
      }
      if (d < best) {
        best = d;
        due = i;
      }
    }
    if (due != null) {
      _marks[due] = NoteMark.wrong;
      _wrongKeys[due] = key;
    }
  }

  /// addMidiChannel adds a MIDI channel: an instrument on a channel of its
  /// own, to be played into -- live, from a MIDI keyboard, with Record. On a
  /// piece of sound with no canvas it lives on the timeline alone; on a
  /// canvas, its keyboard is on the canvas too. Picked, so a MIDI keyboard
  /// plays it and its settings are open.
  ///
  /// [onCanvas] false is an empty MIDI channel: on the timeline alone,
  /// whatever the canvas, its keyboard not put on the page.
  AudioElement addMidiChannel({bool onCanvas = true}) {
    var e = newInstrument(_document);
    // Named for what it plays, numbered where that is taken: Piano, Piano 2.
    var taken = {for (var c in timelineChannels) c.name};
    var name = e.name;
    for (var n = 2; taken.contains(name); n++) {
      name = "${e.name} $n";
    }
    e = e.rebase(e.base.copyWith(
        name: name,
        visible: onCanvas &&
            (_document.hasCanvas || !_document.kind.isAudio))) as AudioElement;
    addElement(e);
    return e;
  }

  /// addEmptyAudioChannel adds an audio channel with nothing on it yet: a
  /// named lane for sounds to be dropped onto, and a strip in the mixer --
  /// its clip slots, its effects -- ready before there is a sound.
  AudioElement addEmptyAudioChannel() {
    var taken = {for (var c in timelineChannels) c.name};
    var name = "Audio";
    for (var n = 2; taken.contains(name); n++) {
      name = "Audio $n";
    }
    var e = AudioElement(
      ElementBase(id: newElementId(), name: name, visible: false),
      clip: MediaClip(timed: true, channelName: name),
      controls: const [],
    );
    addElement(e);
    return e;
  }

  /// setInstrument changes [e]'s part.
  void setInstrument(AudioElement e, InstrumentPart part,
      {bool transient = false}) {
    var current = _document.elementById(e.id);
    if (current is! AudioElement) return;
    replaceElement(current.copyWith(instrument: part), transient: transient);
  }

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

  /// _scheduleParts plays, a moment after the last change, any instrument
  /// whose sound file is not its part any more.
  void _scheduleParts() {
    var waiting = _document.elements.any((e) =>
        e is AudioElement &&
        (e.instrument?.needsPlayingAt(_document.audio.secondsPerBeat) ??
            false));
    if (!waiting) return;
    _partTimer?.cancel();
    _partTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(renderParts());
    });
  }

  // ---- The Speech device

  /// speechOf is channel [channel]'s Speech device, or null for none.
  SpeechSpec? speechOf(String channel) =>
      timelineChannels.where((c) => c.key == channel).firstOrNull?.mix.speech;

  /// setSpeech puts a Speech device on [channel] -- or changes it, or with
  /// null takes it off.
  void setSpeech(String channel, SpeechSpec? spec, {bool transient = false}) {
    var lane = timelineChannels.where((c) => c.key == channel).firstOrNull;
    if (lane == null) return;
    setChannelMix(
        lane,
        spec == null
            ? lane.mix.copyWith(noSpeech: true)
            : lane.mix.copyWith(speech: spec),
        transient: transient);
  }

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

  /// speechLineState is "speaking" or "waiting" for a line in the queue,
  /// or null.
  String? speechLineState(String channel, SpeechLine line) {
    var queue = speechQueue[channel];
    if (queue == null) return null;
    var key = speechLineKey(line);
    if (_speakingNow[channel]?.contains(key) ?? false) return "speaking";
    return queue.contains(key) ? "waiting" : null;
  }

  /// _speakingNow is the lines each channel's engine is speaking now: the
  /// first waiting, or every one, where it speaks them together.
  final Map<String, Set<String>> _speakingNow = {};

  /// _speechStops is Stop, for each channel speaking now.
  final Map<String, SpeechStop> _speechStops = {};

  /// stopSpeaking stops what [channel] is speaking, and lets go of the
  /// sections waiting: the program speaking is ended, and nothing it was
  /// part way through is kept. The takes already made stay.
  void stopSpeaking(String channel) {
    var stop = _speechStops[channel];
    if (stop == null) return;
    speechQueue[channel]?.clear();
    stop.stop();
    notifyListeners();
  }

  /// _lineSpeech is [channel]'s device with its lines set out -- those of
  /// its script, where it has none yet.
  SpeechSpec? _lineSpeech(String channel) {
    var spec = speechOf(channel);
    if (spec == null || spec.lines.isNotEmpty) return spec;
    var lines = spec.shownLines;
    if (lines.isEmpty) return spec;
    spec = spec.copyWith(lines: lines);
    setSpeech(channel, spec, transient: true);
    return spec;
  }

  /// _speechInto is the slot each waiting line is to be spoken into, by
  /// channel and line -- a slot being replaced -- where it is not the
  /// line's first free one.
  final Map<String, Map<String, int>> _speechInto = {};

  /// speakLines speaks [lines] of [channel] -- by default, every line with
  /// no take yet -- in the background, each into a slot of its own: the
  /// one it is to replace, or else its first free one. Nothing is put on
  /// the timeline, nor in the Audio library: see saveTake, addTake and
  /// joinSpeech. Lines asked for while it runs join the queue. Answers why
  /// not, where it could not.
  Future<String?> speakLines(String channel, {List<SpeechLine>? lines}) async {
    var spec = _lineSpeech(channel);
    if (spec == null) return null;
    var wanted = lines ?? [for (var l in spec.lines) if (l.takes.isEmpty) l];
    var queue = speechQueue[channel];
    var running = queue != null;
    queue ??= speechQueue[channel] = [];
    for (var l in wanted) {
      var key = speechLineKey(l);
      if (!queue.contains(key)) queue.add(key);
    }
    notifyListeners();
    if (running) return null;
    String? problem;
    try {
      while (queue.isNotEmpty && !_disposed) {
        var now = speechOf(channel);
        if (now == null) break;
        SpeechLine? lineOf(String k) =>
            now.lines.where((l) => speechLineKey(l) == k).firstOrNull;
        // Lines edited away while they waited are not spoken, nor those
        // with no slot to go into.
        var into = _speechInto[channel] ?? const {};
        queue.removeWhere((k) {
          var l = lineOf(k);
          return l == null || (into[k] == null && l.freeSlot < 0);
        });
        if (queue.isEmpty) break;
        var engine = speechEngineFor(now);
        var stop = engine.stopper = _speechStops[channel] = SpeechStop();
        // Every line waiting, at once, where the engine does better so;
        // else the first.
        var keys = engine.batches ? [...queue] : [queue.first];
        var lines = [for (var k in keys) lineOf(k)!];
        _speakingNow[channel] = {...keys};
        notifyListeners();
        var audios = engine.batches
            ? await engine.speakLines(now, lines)
            // Another seed each time: a take replacing one is not the same.
            : [
                await engine.speakLine(now, lines.single,
                    seed: 1 + _seeds.nextInt(1 << 30))
              ];
        if (_disposed) return null;
        if (stop.stopped) break;
        for (var (i, key) in keys.indexed) {
          if (!await _keepLineTake(channel, key, audios[i])) {
            problem = "The take could not be kept.";
            break;
          }
          queue.remove(key);
          _speechInto[channel]?.remove(key);
          notifyListeners();
        }
        if (problem != null) break;
      }
    } on SpeechException catch (e) {
      // Stopped, it is as asked: nothing to say.
      if (!(_speechStops[channel]?.stopped ?? false)) problem = e.message;
    } catch (e) {
      debugPrint("Unable to speak a line: $e");
      problem = "The voice could not speak: $e";
    } finally {
      _speechStops.remove(channel);
      speechQueue.remove(channel);
      _speechInto.remove(channel);
      _speakingNow.remove(channel);
      if (!_disposed) notifyListeners();
    }
    return problem;
  }

  /// _keepLineTake keeps [audio] as a take of [channel]'s line [key], in
  /// the slot it was to replace or its first free one, picked. Kept apart
  /// from the library -- see speechTakeStore. Whether it could be kept; a
  /// line edited away meanwhile is let go.
  Future<bool> _keepLineTake(
      String channel, String key, SpokenAudio audio) async {
    var id = await speechTakeStore(wav16(audio.l, audio.r));
    if (id == null) return false;
    // Where the line is now: it may have moved while it was spoken.
    var after = speechOf(channel);
    if (after == null) return true;
    var at = after.lines.indexWhere((l) => speechLineKey(l) == key);
    if (at < 0) return true;
    var line = after.lines[at];
    var slot = _speechInto[channel]?[key] ?? line.freeSlot;
    if (slot < 0) return true;
    var l = line.withSlot(
        slot, SpeechTake(id, audio.seconds, audio.words, exact: audio.exact));
    setSpeech(
        channel,
        after.copyWith(lines: [
          for (var (i, x) in after.lines.indexed) i == at ? l : x,
        ]),
        transient: true);
    return true;
  }

  /// anotherTake speaks [line] of [channel] again into slot [slot] -- one
  /// not in use -- or its first free one. With all three in use, it says
  /// so: a take is only replaced by the reader, with replaceTake.
  Future<String?> anotherTake(String channel, SpeechLine line, {int? slot}) {
    var into = slot != null && line.slot(slot) == null ? slot : line.freeSlot;
    if (into < 0) {
      return Future.value(
          "All three slots are in use: pick one, and Replace it.");
    }
    (_speechInto[channel] ??= {})[speechLineKey(line)] = into;
    return speakLines(channel, lines: [line]);
  }

  /// replaceTake speaks line [index] of [channel] again into slot [slot],
  /// in place of the take there.
  Future<String?> replaceTake(String channel, int index, int slot) {
    var spec = _lineSpeech(channel);
    if (spec == null || index < 0 || index >= spec.lines.length) {
      return Future.value(null);
    }
    var line = spec.lines[index];
    (_speechInto[channel] ??= {})[speechLineKey(line)] = slot;
    return speakLines(channel, lines: [line]);
  }

  /// speechReplacing is the slot line [line] of [channel] is being spoken
  /// into, while it waits or is spoken -- or null.
  int? speechReplacing(String channel, SpeechLine line) {
    var key = speechLineKey(line);
    if (!(speechQueue[channel]?.contains(key) ?? false)) return null;
    return _speechInto[channel]?[key] ?? line.freeSlot;
  }

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
      if (!await file.exists()) await file.writeAsBytes(wav, flush: true);
      return id;
    } catch (e) {
      debugPrint("Unable to keep a take: $e");
      return null;
    }
  };

  /// _slotTake is line [index]'s slot [slot] on [channel], with the device
  /// and the line -- or null for none there.
  (SpeechSpec, SpeechLine, SpeechTake)? _slotTake(
      String channel, int index, int slot) {
    var spec = speechOf(channel);
    if (spec == null || index < 0 || index >= spec.lines.length) return null;
    var line = spec.lines[index];
    var take = line.slot(slot);
    return take == null ? null : (spec, line, take);
  }

  void _setSlot(String channel, int index, int slot, SpeechTake? take,
      {bool transient = true}) {
    var spec = speechOf(channel);
    if (spec == null || index >= spec.lines.length) return;
    setSpeech(
        channel,
        spec.copyWith(lines: [
          for (var (i, l) in spec.lines.indexed)
            i == index ? l.withSlot(slot, take) : l
        ]),
        transient: transient);
  }

  /// chooseTake picks slot [slot] of line [index]: the take "Add all
  /// lines" puts on the timeline.
  void chooseTake(String channel, int index, int slot) {
    var spec = speechOf(channel);
    if (spec == null || index < 0 || index >= spec.lines.length) return;
    var line = spec.lines[index];
    if (line.slot(slot) == null || line.chosen == slot) return;
    setSpeech(
        channel,
        spec.copyWith(lines: [
          for (var (i, l) in spec.lines.indexed)
            i == index ? l.copyWith(chosen: slot) : l
        ]),
        transient: true);
  }

  /// removeTake empties slot [slot] of line [index]: one change to undo.
  /// Its file goes at the next tidy, once nothing has it -- unless it was
  /// saved, when the library keeps it.
  void removeTake(String channel, int index, int slot) {
    if (_slotTake(channel, index, slot) == null) return;
    beginInteraction();
    _setSlot(channel, index, slot, null, transient: false);
    endInteraction();
  }

  // ---- Phrasing: a take's words shaped after it is spoken

  /// phrasing is the take the Speech device's Phrasing is open on: a
  /// channel's section, and its slot -- which may have no take yet.
  ({String channel, int line, int slot})? get phrasing => _phrasing;
  ({String channel, int line, int slot})? _phrasing;

  /// phrasingTake is the take Phrasing is open on, as it is now.
  SpeechTake? get phrasingTake {
    var p = _phrasing;
    return p == null ? null : _slotTake(p.channel, p.line, p.slot)?.$3;
  }

  /// openPhrasing opens Phrasing on slot [slot] of [channel]'s section
  /// [line] -- in the Speech device, in place of its sections -- and reads
  /// the take as spoken. Another take, its words picked afresh.
  void openPhrasing(String channel, int line, int slot) {
    var next = (channel: channel, line: line, slot: slot);
    if (next == _phrasing) return;
    _phrasing = next;
    phrasingPicked = const {0};
    notifyListeners();
    if (phrasingTake case var take?) unawaited(_readSpoken(take.asSpoken));
  }

  /// closePhrasing goes back to the device's sections.
  void closePhrasing() {
    if (_phrasing == null) return;
    _phrasing = null;
    notifyListeners();
  }

  /// phrasingPicked are the words picked, by their place in the take as
  /// spoken: what a drag or a setting changes. The first is the one its
  /// settings show.
  Set<int> phrasingPicked = const {0};

  /// pickWords picks [words] -- [adding] them to those picked, or, a word
  /// already picked, taking it off.
  void pickWords(Iterable<int> words, {bool adding = false}) {
    var next = <int>{};
    if (adding) {
      next.addAll(phrasingPicked);
      for (var w in words) {
        if (!next.remove(w)) next.add(w);
      }
      // The last added first: its settings shown.
      var added = words.where(next.contains).toList();
      if (added.isNotEmpty) next = {added.last, ...next};
    } else {
      next.addAll(words);
    }
    if (next.isEmpty) return;
    phrasingPicked = next;
    notifyListeners();
  }

  /// readingOf is what was heard of [take] as spoken -- its pitch, each
  /// word's loudness -- or null until it has been read.
  TakeReading? readingOf(SpeechTake take) => _readings[take.asSpoken.assetId];
  final Map<String, TakeReading> _readings = {};

  /// _readSpoken reads [spoken] -- a take as the voice spoke it -- once:
  /// its sound, or null where its file could not be.
  Future<Float32List?> _readSpoken(SpeechTake spoken) async {
    var pcm = await takeAudio(spoken.assetId);
    if (pcm == null || _disposed) return pcm;
    if (!_readings.containsKey(spoken.assetId)) {
      var words = spoken.words;
      _readings[spoken.assetId] = await Isolate.run(() => readTake(pcm, words));
      if (!_disposed) notifyListeners();
    }
    return pcm;
  }

  /// shapeWord shapes word [word] of the take Phrasing is open on --
  /// [transient], part of a drag that ends with one change to undo.
  void shapeWord(int word, WordShape shape, {bool transient = false}) =>
      shapeWords({word: shape}, transient: transient);

  /// shapeWords shapes several words of the take Phrasing is open on, by
  /// their places in it, as one change. Its sound is made again a moment
  /// after the last change.
  void shapeWords(Map<int, WordShape> next, {bool transient = false}) {
    var p = _phrasing;
    var take = phrasingTake;
    if (p == null || take == null) return;
    var shapes = [
      for (var i = 0; i < take.asSpoken.words.length; i++)
        next[i] ?? take.shapeOf(i)
    ];
    _setSlot(p.channel, p.line, p.slot, take.withShapes(shapes),
        transient: transient);
    _shapeSoon();
  }

  /// resetPhrasing puts every word of the take back as it was spoken: one
  /// change to undo.
  void resetPhrasing() {
    var p = _phrasing;
    var take = phrasingTake;
    if (p == null || take == null || !take.shaped) return;
    _setSlot(p.channel, p.line, p.slot, take.withShapes(const []),
        transient: false);
    _shapeSoon();
  }

  Timer? _shapeTimer;

  /// _shapeSoon makes the open take's sound again, a moment after the last
  /// change: ready to hear by the time it is asked for.
  void _shapeSoon() {
    _shapeTimer?.cancel();
    _shapeTimer = Timer(const Duration(milliseconds: 300), () {
      var p = _phrasing;
      if (p != null) unawaited(shapedTake(p.channel, p.line, p.slot));
    });
  }

  final Map<String, Future<SpeechTake?>> _shaping = {};

  /// shapedTake is slot [slot]'s take of [channel]'s section [index], its
  /// sound made from its shapes first where it is not yet -- what is
  /// heard, saved, put on the timeline or joined.
  Future<SpeechTake?> shapedTake(String channel, int index, int slot) async {
    var key = "$channel/$index/$slot";
    for (var running = _shaping[key];
        running != null;
        running = _shaping[key]) {
      await running;
    }
    var take = _slotTake(channel, index, slot)?.$3;
    if (take == null || !take.needsShaping) return take;
    var job = _shapeTake(channel, index, slot, take);
    _shaping[key] = job;
    try {
      return await job;
    } finally {
      _shaping.remove(key);
    }
  }

  Future<SpeechTake?> _shapeTake(
      String channel, int index, int slot, SpeechTake take) async {
    var spoken = take.asSpoken;
    SpeechTake? made;
    if (!take.shaped) {
      made = spoken;
    } else {
      var pcm = await _readSpoken(spoken);
      var reading = _readings[spoken.assetId];
      if (pcm == null || reading == null || _disposed) return take;
      var words = spoken.words, shapes = take.shapes;
      var shaped =
          await Isolate.run(() => shapeTake(pcm, words, shapes, reading));
      var id = await speechTakeStore(wav16(shaped.sound, shaped.sound));
      if (id == null || _disposed) return take;
      made = take.madeAs(id, shaped.sound.length / mixRate, shaped.words);
    }
    // Shaped again meanwhile: that is made next.
    var now = _slotTake(channel, index, slot)?.$3;
    if (now == null || now.shapesKey != take.shapesKey) return now;
    _setSlot(channel, index, slot, made);
    return made;
  }

  /// hearSlot plays slot [slot]'s take of [channel]'s section [index] --
  /// shaped, or, [spoken], as the voice spoke it -- from [at] seconds into
  /// it; or, playing, stops it.
  Future<String?> hearSlot(String channel, int index, int slot,
      {bool spoken = false, double at = 0}) async {
    var take = spoken
        ? _slotTake(channel, index, slot)?.$3.asSpoken
        : await shapedTake(channel, index, slot);
    if (take == null) return null;
    return hearTake(take.assetId, at: at);
  }

  /// saveTake puts slot [slot]'s take of line [index] in the Audio library,
  /// answering it saved -- or why not.
  Future<(SpeechTake?, String?)> saveTake(
      String channel, int index, int slot) async {
    await shapedTake(channel, index, slot);
    var found = _slotTake(channel, index, slot);
    if (found == null) return (null, null);
    var (spec, line, take) = found;
    if (take.saved) return (take, null);
    var file = await takePath(take.assetId);
    if (file == null) return (null, "The take's file could not be found.");
    var id = await speechStore(file);
    if (id == null || _disposed) return (null, "The take could not be saved.");
    await speechLibrary(
        id,
        "${spec.voiceName.isEmpty ? "Speech" : spec.voiceName} · line "
        "${index + 1} · take ${String.fromCharCode(65 + slot)} · "
        "${_firstWords(line.text)}",
        take.length);
    var saved = take.copyWith(assetId: id, saved: true);
    _setSlot(channel, index, slot, saved);
    return (saved, null);
  }

  /// addTake puts slot [slot]'s take of line [index] on the timeline, in a
  /// clip of its own at the playhead -- saved to the Audio library first,
  /// and kept with the device so a character's lips follow it. One change
  /// to undo.
  Future<String?> addTake(String channel, int index, int slot) async {
    var (take, problem) = await saveTake(channel, index, slot);
    if (take == null) return problem;
    var lane = timelineChannels.where((c) => c.key == channel).firstOrNull;
    var spec = lane?.mix.speech;
    if (lane == null || spec == null || _disposed) return null;
    beginInteraction();
    var mix = lane.mix.copyWith(
        speech: spec.copyWith(takes: [
      for (var t in spec.takes)
        if (t.assetId != take.assetId) t,
      take,
    ]));
    setChannelMix(lane, mix, transient: true);
    addElement(channelClip(_document, _frame,
        source: MediaSource(
            assetId: take.assetId,
            name: "Line ${index + 1} · take ${String.fromCharCode(65 + slot)}",
            length: take.length),
        channel: channel,
        channelName: lane.name,
        mix: mix));
    endInteraction();
    return null;
  }

  /// setSpeechLines changes [channel]'s lines -- a direction, own words, a
  /// join or a split -- the script written from them.
  void setSpeechLines(String channel, List<SpeechLine> lines) {
    var spec = speechOf(channel);
    if (spec == null) return;
    setSpeech(channel, spec.withLines(lines));
  }

  /// joinSpeechLine makes line [index] and the next one line, to be spoken
  /// as one: its direction the first's, its takes none yet.
  void joinSpeechLine(String channel, int index) {
    var lines = _lineSpeech(channel)?.lines;
    if (lines == null || index < 0 || index + 1 >= lines.length) return;
    var a = lines[index], b = lines[index + 1];
    setSpeechLines(channel, [
      ...lines.take(index),
      SpeechLine("${a.text} ${b.text}", direction: a.direction, own: a.own),
      ...lines.skip(index + 2),
    ]);
  }

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

  /// splitSpeechLine cuts line [index] in two at speechSplitAt, each with
  /// its direction and no takes yet.
  void splitSpeechLine(String channel, int index) {
    var lines = _lineSpeech(channel)?.lines;
    if (lines == null || index < 0 || index >= lines.length) return;
    var l = lines[index];
    var at = speechSplitAt(l.text);
    if (at == null) return;
    setSpeechLines(channel, [
      ...lines.take(index),
      SpeechLine(l.text.substring(0, at).trim(),
          direction: l.direction, own: l.own),
      SpeechLine(l.text.substring(at).trim(),
          direction: l.direction, own: l.own),
      ...lines.skip(index + 1),
    ]);
  }

  Future<String?> _keepWav(Uint8List wav, String name) async {
    var dir = await Directory.systemTemp.createTemp("canvas-take");
    try {
      var file = File(path.join(dir.path, "$name.wav"));
      await file.writeAsBytes(wav, flush: true);
      return await speechStore(file.path);
    } finally {
      await dir.delete(recursive: true).catchError((_) => dir);
    }
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

  /// joinSpeech is "Add all lines to the timeline": [channel]'s lines,
  /// each its slot picked, a pause between each two, given the finish --
  /// the room and the speaker boost -- in the channel's clip: the one it
  /// made before, its sound changed, or a new one at the playhead. Saved
  /// to the Audio library; nothing goes on the timeline but by this, or a
  /// slot's own addTake. One change to undo.
  Future<String?> joinSpeech(String channel) async {
    var spec = speechOf(channel);
    if (spec == null || !joining.add(channel)) return null;
    notifyListeners();
    try {
      // Each take as it is shaped.
      for (var (i, l) in spec.lines.indexed) {
        if (l.take != null) await shapedTake(channel, i, l.chosen);
      }
      spec = speechOf(channel);
      if (spec == null) return null;
      var takes = [
        for (var l in spec.lines)
          if (l.take case var t?) t
      ];
      if (takes.isEmpty) return null;
      var sounds = <Float32List>[];
      for (var t in takes) {
        var sound = await takeAudio(t.assetId);
        if (sound == null) return "A take's file could not be read.";
        sounds.add(sound);
      }
      // Joined and finished in an isolate of its own: on the app's, the
      // finish held everything up for seconds on a long script.
      var joined = await _joinAway(sounds, takes, spec.speed,
          room: spec.room, boost: spec.boost);
      if (_disposed) return null;
      var id = await _keepWav(joined.wav, "speech");
      if (id == null || _disposed) return "The clip could not be kept.";
      var lane = timelineChannels.where((c) => c.key == channel).firstOrNull;
      var now = lane?.mix.speech;
      if (lane == null || now == null) return null;
      var old = _document.elements
          .whereType<AudioElement>()
          .where((e) => e.id == now.clip)
          .firstOrNull;
      var oldId = old?.clip.playlist.firstOrNull?.assetId;
      var take =
          SpeechTake(id, joined.seconds, joined.words, exact: joined.exact);
      beginInteraction();
      var kept = now.copyWith(takes: [
        for (var t in now.takes)
          if (t.assetId != oldId) t,
        take,
      ]);
      var source = MediaSource(
          assetId: id, name: "Speech", length: joined.seconds);
      if (old != null) {
        setChannelMix(lane, lane.mix.copyWith(speech: kept), transient: true);
        var e = _document.elements
            .whereType<AudioElement>()
            .where((e) => e.id == old.id)
            .first;
        replaceElement(e.copyWith(
            clip: e.clip.copyWith(playlist: [
          source.copyWith(name: e.clip.playlist.firstOrNull?.name),
          ...e.clip.playlist.skip(1),
        ])));
      } else {
        var clip = channelClip(_document, _frame,
            source: source,
            channel: channel,
            channelName: lane.name,
            mix: lane.mix);
        kept = kept.copyWith(clip: clip.id);
        var mix = lane.mix.copyWith(speech: kept);
        setChannelMix(lane, mix, transient: true);
        addElement(clip.copyWith(clip: clip.clip.copyWith(mix: mix)));
      }
      endInteraction();
      // The clip in the Audio library: this one in place of the last.
      if (oldId != null && oldId != id) await speechUnlist(oldId);
      await speechLibrary(
          id,
          "Speech · ${now.voiceName.isEmpty ? "voice" : now.voiceName} · "
          "${_firstWords(now.lines.map((l) => l.text).join(" "))}",
          joined.seconds);
      return null;
    } catch (e) {
      debugPrint("Unable to join the lines: $e");
      return "The lines could not be joined: $e";
    } finally {
      joining.remove(channel);
      if (!_disposed) notifyListeners();
    }
  }

  // ---- Hearing a take, or a voice, on its own

  /// speechHeard is what is being heard on its own, outside the mix: a
  /// take's asset id, or "voice:" and the voice previewed -- null for
  /// nothing. speechPreviewing is the voice being spoken for its preview.
  String? get speechHeard => _speechHeard;
  String? _speechHeard;
  String? speechPreviewing;
  AudioTrack? _heardTrack;
  AudioVoice? _heardVoice;
  Timer? _heardWatch;

  /// takePath is where a stored take's file is: a stand-in for tests.
  @visibleForTesting
  static Future<String?> Function(String assetId) takePath = (id) async {
    // Saved, in the Audio library; else kept apart -- see speechTakeStore.
    if (await CanvasMedia.existingPath(MediaKind.audio, id) case var p?) {
      return p;
    }
    var kept = path.join(await CanvasStorage.speechTakesDir(), id);
    return await File(kept).exists() ? kept : null;
  };

  /// hearTake plays take [assetId] on its own, from [at] seconds into it
  /// -- or, playing, stops it. Answers why not, where it could not.
  Future<String?> hearTake(String assetId, {double at = 0}) async {
    if (_speechHeard == assetId) {
      stopHearing();
      return null;
    }
    var file = await takePath(assetId);
    if (file == null) return "The take's file could not be found.";
    return _hear(file, assetId, at: at);
  }

  /// heardSeconds is how far into what is being heard on its own it has
  /// played -- or null, with nothing heard.
  double? get heardSeconds {
    var v = _heardVoice;
    if (v == null || _speechHeard == null) return null;
    return audio.engine.position(v);
  }

  Future<String?> _hear(String file, String what, {double at = 0}) async {
    stopHearing();
    var engine = audio.engine;
    if (!await engine.start()) return "There is no sound to play it on.";
    var track = await engine.open(file);
    if (track == null || _disposed) return "It could not be played.";
    _heardTrack = track;
    _heardVoice = engine.play(track, volume: 1, at: at);
    _speechHeard = what;
    _heardWatch = Timer.periodic(const Duration(milliseconds: 250), (_) {
      var v = _heardVoice;
      if (v == null || !engine.alive(v)) stopHearing();
    });
    notifyListeners();
    return null;
  }

  /// stopHearing stops what is being heard on its own.
  void stopHearing() {
    _heardWatch?.cancel();
    _heardWatch = null;
    var voice = _heardVoice, track = _heardTrack;
    _heardVoice = null;
    _heardTrack = null;
    if (voice != null) audio.engine.stop(voice);
    if (track != null) audio.engine.close(track);
    if (_speechHeard != null) {
      _speechHeard = null;
      if (!_disposed) notifyListeners();
    }
  }

  /// speechSample is what a voice says for its preview.
  static const speechSample = "Good evening, everyone. I have some news for you.";

  /// _previews are the voices previewed, by everything that changes how they
  /// sound, each its file: heard again at once.
  final Map<String, String> _previews = {};
  Directory? _previewDir;

  /// previewVoice speaks speechSample in [voice] -- channel [channel]'s
  /// device's engine, language and feel, its finish too -- and plays it; or,
  /// playing, stops it. Not kept: nothing is added to the library.
  Future<String?> previewVoice(String channel, String voice) async {
    var what = "voice:$voice";
    if (_speechHeard == what) {
      stopHearing();
      return null;
    }
    var now = speechOf(channel);
    if (now == null || speechPreviewing != null) return null;
    var spec = now.copyWith(voice: voice);
    var key = [
      spec.engine.name,
      voice,
      spec.language,
      spec.speed.toStringAsFixed(2),
      spec.steadiness.toStringAsFixed(2),
      spec.expression.toStringAsFixed(2),
      spec.room.toStringAsFixed(2),
      spec.boost,
    ].join("|");
    var file = _previews[key];
    if (file == null || !await File(file).exists()) {
      speechPreviewing = voice;
      notifyListeners();
      try {
        var said = await speechEngineFor(spec)
            .speakLine(spec, const SpeechLine(speechSample));
        var finished = await _joinAway([said.l], [
          SpeechTake("", said.seconds, said.words, exact: said.exact)
        ], spec.speed, room: spec.room, boost: spec.boost);
        if (_disposed) return null;
        _previewDir ??= await Directory.systemTemp.createTemp("canvas-voices");
        file = path.join(_previewDir!.path, "voice-${_previews.length}.wav");
        await File(file).writeAsBytes(finished.wav, flush: true);
        _previews[key] = file;
      } on SpeechException catch (e) {
        return e.message;
      } catch (e) {
        debugPrint("Unable to preview a voice: $e");
        return "The voice could not speak: $e";
      } finally {
        speechPreviewing = null;
        if (!_disposed) notifyListeners();
      }
    }
    if (_disposed) return null;
    return _hear(file, what);
  }

  // ---- MIDI files from the library

  /// midiNotesOf reads stored MIDI file [assetId]'s notes, in seconds -- or
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

  /// addMidiChannelFrom makes a MIDI channel playing MIDI file [source],
  /// from [frame] -- the playhead with none -- named after the file.
  Future<AudioElement?> addMidiChannelFrom(MediaSource source,
      {int? frame, bool onCanvas = true}) async {
    var read = await midiOfAsset(source.assetId);
    if (read == null || _disposed) return null;
    var e = newInstrument(_document);
    var part = e.instrument!.copyWith(notes: read.notes);
    e = e
        .copyWith(instrument: part, clip: e.clip.copyWith(at: frame ?? _frame))
        .rebase(e.base.copyWith(
            name: source.name.isEmpty ? "MIDI file" : source.name,
            visible: onCanvas &&
                (_document.hasCanvas ||
                    !_document.kind.isAudio))) as AudioElement;
    addElement(e);
    return e;
  }

  /// putMidiOn adds MIDI file [assetId]'s notes to MIDI channel [channel]'s
  /// part, from [frame]: one change to undo.
  Future<bool> putMidiOn(String channel, String assetId, int frame) async {
    var read = await midiOfAsset(assetId);
    var e = _instrumentOf(channel);
    if (read == null || e == null || _disposed) return false;
    var rate = math.max(1, _document.frameRate);
    var offset = math.max(0, frame - e.clip.at) / rate;
    var part = e.instrument!;
    setInstrument(
        e,
        part.copyWith(
            notes: [
          ...part.notes,
          for (var n in read.notes) n.copyWith(start: n.start + offset),
        ]..sort((a, b) => a.start.compareTo(b.start))));
    return true;
  }

  /// midiClipFromFile fills slot [row] of MIDI channel [channel] with MIDI
  /// file [assetId]'s notes, in beats, as many whole bars long as they are.
  Future<bool> midiClipFromFile(String channel, int row, String assetId,
      {String name = ""}) async {
    var read = await midiOfAsset(assetId);
    if (read == null || _instrumentOf(channel) == null || _disposed) {
      return false;
    }
    var spb = math.max(0.001, _document.audio.secondsPerBeat);
    var notes = [
      for (var n in read.notes)
        MidiNote(n.key, n.start / spb, n.length / spb, n.velocity),
    ];
    var end = notes.isEmpty ? 0.0 : notes.map((n) => n.end).reduce(math.max);
    var index = timelineChannels.indexWhere((c) => c.key == channel);
    setSessionClip(
        channel,
        row,
        SessionClip(
          id: newElementId(),
          name: name.isEmpty ? "MIDI file" : name,
          color: math.max(0, index) % sectionColors.length,
          midi: true,
          notes: notes,
          bars: math
              .max(1, (end / _document.audio.beatsPerBar).ceil())
              .toDouble(),
        ));
    return true;
  }

  // ---- The Vocaliser

  /// vocaliserOf is channel [channel]'s Vocaliser, or null for none.
  VocaliserSpec? vocaliserOf(String channel) => timelineChannels
      .where((c) => c.key == channel)
      .firstOrNull
      ?.mix
      .vocaliser;

  /// setVocaliser puts a Vocaliser on [channel], changes it, or with null
  /// takes it off.
  void setVocaliser(String channel, VocaliserSpec? spec,
      {bool transient = false}) {
    var lane = timelineChannels.where((c) => c.key == channel).firstOrNull;
    if (lane == null) return;
    setChannelMix(
        lane,
        spec == null
            ? lane.mix.copyWith(noVocaliser: true)
            : lane.mix.copyWith(vocaliser: spec),
        transient: transient);
  }

  /// midiChannels are the MIDI channels there are, by key and name: what
  /// a Vocaliser can sing the notes of.
  List<(String, String)> get midiChannels => [
        for (var c in timelineChannels)
          if (instrumentChannel(c.key)) (c.key, c.name),
      ];

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

  /// sing sings [channel]'s latest Speech take to its Vocaliser's melody --
  /// a MIDI channel's notes -- into a new clip on the channel where the
  /// melody starts. One change to undo. Answers why not, where it could
  /// not.
  Future<String?> sing(String channel) async {
    var spec = vocaliserOf(channel);
    if (spec == null) return null;
    var take = speechOf(channel)?.takes.lastOrNull;
    if (take == null) {
      return "Nothing to sing yet: speak a take with this channel's "
          "Speech device first.";
    }
    var melodyKey = spec.melody.isNotEmpty
        ? spec.melody
        : midiChannels.firstOrNull?.$1 ?? "";
    var tune = _instrumentOf(melodyKey);
    if (tune == null || tune.instrument!.notes.isEmpty) {
      return "Nothing to sing to: pick a MIDI channel with notes on it.";
    }
    if (!singing.add(channel)) return null;
    notifyListeners();
    try {
      var source = await takeAudio(take.assetId);
      if (source == null) return "The take's file could not be read.";
      var rate = math.max(1, _document.frameRate);
      var partStart = tune.clip.at / rate;
      var melody = melodyOf(tune.instrument!.notes);
      var sung = assignSyllables(syllablesOf(take.words), melody);
      if (sung.isEmpty) return "The take has no words to sing.";
      var settings =
          SingSettings(vibrato: spec.vibrato, glideSeconds: spec.glide);
      var out = await _sungAway(source, sung, settings);
      if (_disposed) return null;
      var dir = await Directory.systemTemp.createTemp("canvas-sung");
      String? id;
      try {
        var file = File(path.join(dir.path, "sung.wav"));
        await file.writeAsBytes(wav16(out, out), flush: true);
        id = await speechStore(file.path);
      } finally {
        await dir.delete(recursive: true).catchError((_) => dir);
      }
      if (id == null || _disposed) return "The sung take could not be kept.";
      var lane = timelineChannels.where((c) => c.key == channel).firstOrNull;
      if (lane == null) return null;
      var count = _document.elements
              .whereType<AudioElement>()
              .where((e) =>
                  e.clip.playlist.any((s) => s.name.startsWith("Sung take")))
              .length +
          1;
      addElement(channelClip(
          _document, ((partStart + melody.first.start) * rate).round(),
          source: MediaSource(
              assetId: id,
              name: "Sung take $count",
              length: out.length / 48000),
          channel: channel,
          channelName: lane.name,
          mix: lane.mix));
      return null;
    } catch (e) {
      debugPrint("Unable to sing: $e");
      return "It could not be sung: $e";
    } finally {
      singing.remove(channel);
      if (!_disposed) notifyListeners();
    }
  }

  /// speechStore keeps a spoken take's file, answering its id: a stand-in
  /// for tests.
  @visibleForTesting
  static Future<String?> Function(String file) speechStore =
      (file) => CanvasMedia.saveFile(MediaKind.audio, file);

  /// renderParts plays every instrument's part that needs it into its
  /// clip's file, now.
  Future<void> renderParts() async {
    _partTimer?.cancel();
    for (var e in [..._document.elements]) {
      if (e is! AudioElement) continue;
      var part = e.instrument;
      var spb = _document.audio.secondsPerBeat;
      if (part == null || !part.needsPlayingAt(spb)) continue;
      var signature = part.signatureAt(spb);
      // Played on the piano of our own for want of the bank: again only
      // once the bank is here.
      var stood = "$signature~";
      var wantsBank = part.sound == InstrumentSound.bank;
      var bankHere = wantsBank && await bankReady();
      if (part.rendered == stood && !bankHere) continue;
      if (!_rendering.add(signature)) continue;
      try {
        var bank = bankHere ? await soundBankPath() : null;
        // Through its MIDI effects: what is played, not what is written.
        var wav = await partRenderer(part.played(spb), bankPath: bank);
        var id = await partStore(wav);
        if (id == null || _disposed) continue;
        // Written onto the element as it is now -- if it still sounds the
        // same: changed again meanwhile, that change plays next.
        var now = _document.elementById(e.id);
        if (now is! AudioElement ||
            now.instrument?.signatureAt(spb) != signature) {
          continue;
        }
        var clip = now.clip.copyWith(timed: true, playlist: [
          MediaSource(
              assetId: id,
              name: "${part.name} part",
              length: part.played(spb).length),
        ]);
        // Not a change of its own to undo: the file follows the notes.
        apply(
            _document.withElement(now.copyWith(
                clip: clip,
                instrument: now.instrument!.copyWith(
                    rendered: wantsBank && !bankHere ? stood : signature))),
            transient: true);
      } catch (exception) {
        debugPrint("Unable to play the part: $exception");
      } finally {
        _rendering.remove(signature);
      }
    }
  }

  /// pressAudio is a press on one of [e]'s own controls. [volume] is where
  /// on the volume bar, for that one.
  void pressAudio(AudioElement e, AudioControl part, {double? volume}) {
    var current = _audioById(e.id) ?? e;
    switch (part) {
      case AudioControl.playPause:
        _heard();
        unawaited(audio.toggle(current));
      case AudioControl.mute:
        audio.toggleMute(current);
      case AudioControl.volume:
        if (volume == null) return;
        audio.setVolume(current, volume);
        // Turning it up is asking to hear it.
        if (volume > 0 && audio.view(current).muted) {
          audio.setMuted(current, false);
        }
    }
  }

  /// _audioById finds an audio element on the canvas showing or on the
  /// master -- the two places a button on this page could mean.
  /// _mediaById is an Audio or Video element on the canvas showing or on the
  /// master -- what a button's media action is aimed at.
  CanvasElement? _mediaById(String id) {
    for (var e in [
      ..._document.elements,
      ...?_document.masterScene?.elements,
      ..._document.drawnBackground.media,
    ]) {
      if (e.id == id && (e is AudioElement || e is VideoElement)) return e;
    }
    return null;
  }

  AudioElement? _audioById(String id) {
    for (var e in _document.elements) {
      if (e is AudioElement && e.id == id) return e;
    }
    for (var e in _document.masterScene?.elements ?? const <CanvasElement>[]) {
      if (e is AudioElement && e.id == id) return e;
    }
    return null;
  }

  /// _pageAudio is every sound that belongs to what is on screen: the canvas
  /// showing, and the master under it.
  Iterable<AudioElement> get _pageAudio sync* {
    for (var e in _document.elements) {
      if (e is AudioElement) yield e;
    }
    if (!_document.editingMaster) {
      for (var e
          in _document.masterScene?.elements ?? const <CanvasElement>[]) {
        if (e is AudioElement) yield e;
      }
    }
  }

  /// _audioFollowsPage stops whatever does not belong on the canvas now
  /// showing. [turned] is whether the page actually changed: a master sound
  /// set to stop at the join stops then, and not when an unrelated edit is
  /// made.
  void _audioFollowsPage({required bool turned}) {
    var a = _audio;
    if (a == null) return;
    bool media(CanvasElement e) => e is AudioElement || e is VideoElement;
    // On the master's timeline, a clip runs on the run's clock under every
    // scene, so a turn is nothing to it. Stopped at the turn, it was started
    // again at once by the timeline -- heard as a restart, or as itself
    // twice over.
    bool carries(CanvasElement e) => switch (e) {
          AudioElement e => e.clip.acrossPages || e.clip.timed,
          VideoElement e => e.clip.acrossPages || e.clip.timed,
          _ => false,
        };
    // The background's too: what is drawn is what plays. A master's shared
    // backdrop is the master's, and carries on across a turn on the same
    // terms as anything else on the master.
    var fromMaster = _document.editingMaster || _document.sharedBackdrop;
    var keep = <String>{
      for (var e in _document.elements)
        if (media(e)) e.id,
      for (var e in _document.masterScene?.elements ?? const <CanvasElement>[])
        if (media(e) && (!turned || carries(e))) e.id,
      for (var e in _document.drawnBackground.media)
        if (!turned || !fromMaster || carries(e)) e.id,
    };
    _video?.keepOnly(keep.contains);
    // A video's sound goes where its video goes -- see VideoRuntime.
    a.keepOnly((id) => keep.contains(VideoRuntime.videoOfSound(id) ?? id));
  }

  /// _timedOnScreen is every piece of media on the timeline that is on
  /// screen, and the frame of *its* timeline the playhead is at.
  ///
  /// Two timelines: the scene's, which the playhead is on, and the whole
  /// run's, which media on the master and its backdrop follow -- they play
  /// under every scene, so their frame one is the run's frame one.
  Iterable<(CanvasElement, int)> get _timedOnScreen sync* {
    bool timed(CanvasElement e) => switch (e) {
          VideoElement v => v.clip.timed && !v.isLink && !v.clip.isEmpty,
          // An instrument is on its channel before it has a note: a MIDI
          // channel waiting to be played into. So is an empty audio
          // channel, named and waiting for a sound -- see
          // addEmptyAudioChannel.
          AudioElement a => a.clip.timed &&
              (!a.clip.isEmpty ||
                  a.instrument != null ||
                  a.clip.channelName.isNotEmpty),
          _ => false,
        };
    var onMaster = _document.editingMaster;
    var run = onMaster
        ? _frame
        : _previewAt ?? _document.startOfScene(_document.at) + _frame;
    for (var e in _document.elements) {
      if (timed(e)) yield (e, onMaster ? run : _frame);
    }
    if (!onMaster) {
      for (var e
          in _document.masterScene?.elements ?? const <CanvasElement>[]) {
        if (timed(e)) yield (e, run);
      }
    }
    var fromMaster = onMaster || _document.sharedBackdrop;
    for (var e in _document.drawnBackground.media) {
      if (timed(e)) yield (e, fromMaster ? run : _frame);
    }
    // The transitions' own sounds, on the run's timeline like the master's.
    for (var e in _document.transitionSounds) {
      yield (e, run);
    }
  }

  /// timedLanes is the media on the timeline that is on screen, for the
  /// Channels strip: each clip, how far its timeline is ahead of the scene's
  /// (the start of this scene in the run, for media that follows the run),
  /// and whether it can be changed from here.
  List<TimedLane> get timedLanes {
    var document = _document;
    var here = {for (var e in document.elements) e.id};
    var backdrop = {for (var e in document.drawnBackground.media) e.id};
    var onMaster = document.editingMaster;
    var fromMaster = onMaster || document.sharedBackdrop;
    // Which canvas each clip is on, for the strip's label: the master, or the
    // scene being edited.
    int sceneOf(CanvasElement e) => onMaster ||
            (!here.contains(e.id) && !backdrop.contains(e.id)) ||
            (backdrop.contains(e.id) && fromMaster)
        ? -1
        : document.at;
    // While every scene plays, every clip on the timeline can be moved and
    // trimmed from it -- the master's included, wherever it is seen from.
    var lanes = [
      for (var (e, at) in _timedOnScreen)
        TimedLane(
          e,
          offset: at - _frame,
          // A transition's sound belongs to its transition, and is changed
          // there.
          editable: !e.id.startsWith(transitionSoundPrefix) &&
              (allChannels || here.contains(e.id) || backdrop.contains(e.id)),
          scene: sceneOf(e),
        ),
    ];
    // Every other scene's as well, where that has been asked for: each at its
    // place in the run, to be seen against the rest -- and moved, trimmed
    // and cut from here, held to its own scene. Not played from here: a
    // clip is played on its own scene.
    if (allChannels && document.hasScenes) {
      var base = onMaster ? 0 : document.startOfScene(document.at);
      for (var (i, scene) in document.allScenes.indexed) {
        if (!onMaster && i == document.at) continue;
        var offset = base - document.startOfScene(i);
        for (var e in scene.elements) {
          var clip = switch (e) {
            VideoElement v when !v.isLink => v.clip,
            AudioElement a => a.clip,
            _ => null,
          };
          if (clip == null || !clip.timed || clip.isEmpty) continue;
          lanes.add(TimedLane(e, offset: offset, scene: i));
        }
      }
    }
    return lanes;
  }

  /// allChannels is whether the timeline lists every scene's channels, or
  /// only the scene being edited and the master's. It is Play all scenes:
  /// watching the whole run is when every scene's sound is wanted in view.
  bool get allChannels => _playAll;

  /// timelineReach is how many frames the timeline shows: the scene's, or
  /// further where a clip on it runs on past the scene's end -- so the rest
  /// of a long video or song can be scrolled to, seen and trimmed. The frames
  /// past the scene are drawn as out of it; nothing plays there.
  int get timelineReach {
    var most = _document.frames;
    var rate = math.max(1, _document.frameRate);
    for (var lane in timedLanes) {
      var clip = lane.clip;
      if (clip.isEmpty || clip.runLength <= 0) continue;
      var end = clip.at - lane.offset + (clip.runLength * rate).ceil();
      if (end > most) most = end;
    }
    return most;
  }

  /// timelineChannels is the timeline's channels, each with the sounds on it,
  /// in the order they first appear. A channel is its sounds: one with none
  /// left is gone, and the empty lane under the last is not one -- it is
  /// where a new channel is started.
  /// interactiveLanes are the sounds on the canvas that play when pressed
  /// -- this canvas's, and the master's seen from it. Each is on a channel
  /// so that every sound has the same strip and effects; the timeline shows
  /// the channel greyed, since there is nothing on it to place in time.
  List<TimedLane> get interactiveLanes {
    var document = _document;
    var here = {for (var e in document.elements) e.id};
    var onMaster = document.editingMaster;
    var pressed = <CanvasElement>[
      for (var e in _pageAudio)
        if (!e.clip.timed && !e.clip.isEmpty) e,
      // And a video's sound -- not a link's, which plays on its own site.
      for (var e in [
        ...document.elements,
        if (!onMaster) ...?document.masterScene?.elements,
      ])
        if (e is VideoElement && !e.isLink && !e.clip.timed && !e.clip.isEmpty)
          e,
    ];
    return [
      for (var e in pressed)
        TimedLane(e,
            editable: here.contains(e.id),
            scene: onMaster || !here.contains(e.id) ? -1 : document.at),
    ];
  }

  List<TimelineChannel> get timelineChannels {
    var by = <String, List<TimedLane>>{};
    for (var lane in [...timedLanes, ...interactiveLanes]) {
      (by[lane.channelKey] ??= []).add(lane);
    }
    var found = [
      for (var entry in by.entries) TimelineChannel(entry.key, entry.value),
    ];
    // By scene -- S1, S2, S3, with the master's last -- and in the order
    // each was first met within a scene. The scene being edited used to come
    // first, so the list reshuffled itself at every turn of the page.
    var met = {for (var (i, c) in found.indexed) c.key: i};
    // The sounds played by pressing them after all those on the timeline.
    int rank(TimelineChannel c) {
      var scene = c.first.scene;
      return (c.interactive ? 1 << 22 : 0) + (scene < 0 ? 1 << 20 : scene);
    }

    found.sort((a, b) {
      var by = rank(a).compareTo(rank(b));
      return by != 0 ? by : met[a.key]!.compareTo(met[b.key]!);
    });
    if (_channelOrder.isEmpty) return found;
    // Then as they have been dragged into: the channels that have been
    // placed take the places such channels have in that order, among
    // themselves, and a channel never placed keeps its own.
    var placed = {for (var (i, k) in _channelOrder.indexed) k: i};
    var moved = [
      for (var c in found)
        if (placed.containsKey(c.key)) c
    ]..sort((a, b) => placed[a.key]!.compareTo(placed[b.key]!));
    var next = 0;
    return [
      for (var c in found) placed.containsKey(c.key) ? moved[next++] : c,
    ];
  }

  /// _channelOrder is the order channels have been dragged into, by key.
  /// Where somebody is working, not what they made, so it is not saved.
  List<String> _channelOrder = const [];

  /// moveChannel puts the channel [key] at [to] in the list -- the strip
  /// dragged up or down.
  void moveChannel(String key, int to) {
    var keys = [for (var c in timelineChannels) c.key];
    var from = keys.indexOf(key);
    if (from < 0) return;
    keys.removeAt(from);
    keys.insert(to.clamp(0, keys.length).toInt(), key);
    // The ones not in view now -- another scene's, with every scene off --
    // keep the places they were given.
    _channelOrder = [
      ...keys,
      for (var k in _channelOrder)
        if (!keys.contains(k)) k,
    ];
    notifyListeners();
  }

  /// channelLevels is how loud [channel] is now: what comes out of its
  /// strip, which every sound on it plays through.
  (double, double) channelLevels(TimelineChannel channel) =>
      levels(channel.key);

  /// _setClips writes several clips at once, as one change: every sound on a
  /// channel when its strip is changed, say. Media on the backdrop has a lane
  /// of its own and is written the way it always was.
  void _setClips(List<(CanvasElement, MediaClip)> changes,
      {bool transient = false}) {
    var next = _document;
    for (var (e, clip) in changes) {
      var changed = switch (e) {
        VideoElement v => v.copyWith(clip: clip),
        AudioElement a => a.copyWith(clip: clip),
        _ => null,
      };
      if (changed == null) continue;
      var anywhere = _replacedAnywhere(next, changed);
      if (anywhere != null) {
        next = anywhere;
      } else if (changes.length == 1) {
        setTimedClip(e, clip, transient: transient);
        return;
      }
    }
    apply(next, transient: transient);
  }

  // ------------------------------------------------------------------------
  // Replacing a colour everywhere -- see canvas_palette.dart.

  /// replaceColour makes every use of [from] on the document -- in any
  /// scene, the master, the backgrounds, charts, text and transitions -- [to],
  /// as one change. Opacity is kept: a half-strength shade of [from] becomes
  /// a half-strength shade of [to].
  void replaceColour(Color from, Color to) {
    var next =
        CanvasDocument.fromJson(recoloured(_document.toJson(), from, to));
    apply(next);
  }

  // ------------------------------------------------------------------------
  // Reuse: text styles, linked copies, staggered arrivals.

  /// textStyles are the document's named text styles.
  List<NamedTextStyle> get textStyles => _document.textStyles;

  /// saveTextStyle makes [e]'s type a named style -- the next "Style N" if
  /// no name is given -- and sets [e] in it.
  String saveTextStyle(TextElement e, {String name = ""}) {
    var taken = {for (var t in textStyles) t.name};
    if (name.isEmpty || taken.contains(name)) {
      for (var n = textStyles.length + 1;; n++) {
        if (!taken.contains("Style $n")) {
          name = "Style $n";
          break;
        }
      }
    }
    var next = _document.copyWith(
        textStyles: [...textStyles, NamedTextStyle(name, e.textSpec)]);
    apply(_replacedAnywhere(next, e.copyWith(style: name)) ?? next);
    return name;
  }

  /// useTextStyle sets text [id] in style [name], or lets it keep its own
  /// type with an empty name.
  void useTextStyle(String id, String name) {
    var style = textStyles.where((t) => t.name == name).firstOrNull;
    apply(_everyElement(_document, (e, _) {
      if (e.id != id || e is! TextElement) return e;
      return style == null
          ? e.copyWith(style: "")
          : e.copyWith(style: name, textSpec: style.spec);
    }));
  }

  /// updateTextStyle makes style [name] [spec], and restyles every text set
  /// in it, in every scene and on the master, as one change.
  void updateTextStyle(String name, TextSpec spec) {
    var next = _document.copyWith(textStyles: [
      for (var t in textStyles) t.name == name ? NamedTextStyle(name, spec) : t,
    ]);
    apply(_everyElement(next, (e, _) {
      if (e is CounterElement) {
        return e.copyWith(
            numberSpec: e.numberStyle == name ? spec : null,
            affixSpec: e.wordStyle == name ? spec : null);
      }
      if (e is! TextElement || e.style != name) return e;
      return e.copyWith(textSpec: spec);
    }));
  }

  /// useCounterStyle sets counter [id]'s number -- or its [words] -- in
  /// style [name], or lets it keep its own type with an empty name.
  void useCounterStyle(String id, String name, {bool words = false}) {
    var style = textStyles.where((t) => t.name == name).firstOrNull;
    apply(_everyElement(_document, (e, _) {
      if (e.id != id || e is! CounterElement) return e;
      var link = style == null ? "" : name;
      return words
          ? e.copyWith(wordStyle: link, affixSpec: style?.spec)
          : e.copyWith(numberStyle: link, numberSpec: style?.spec);
    }));
  }

  /// saveCounterStyle makes counter [e]'s number type -- or its [words]'
  /// -- a named style, the next "Style N", and sets it in it.
  String saveCounterStyle(CounterElement e, {bool words = false}) {
    var taken = {for (var t in textStyles) t.name};
    var name = "";
    for (var n = textStyles.length + 1;; n++) {
      if (!taken.contains("Style $n")) {
        name = "Style $n";
        break;
      }
    }
    var spec = words ? e.affixSpec : e.numberSpec;
    var next = _document
        .copyWith(textStyles: [...textStyles, NamedTextStyle(name, spec)]);
    var linked =
        words ? e.copyWith(wordStyle: name) : e.copyWith(numberStyle: name);
    apply(_replacedAnywhere(next, linked) ?? next);
    return name;
  }

  /// renameTextStyle renames a style, and every text set in it with it.
  void renameTextStyle(String from, String to, {bool transient = false}) {
    if (to.isEmpty || textStyles.any((t) => t.name == to)) return;
    var next = _document.copyWith(textStyles: [
      for (var t in textStyles) t.name == from ? NamedTextStyle(to, t.spec) : t,
    ]);
    apply(
        _everyElement(next, (e, _) {
          if (e is CounterElement) {
            return e.copyWith(
                numberStyle: e.numberStyle == from ? to : null,
                wordStyle: e.wordStyle == from ? to : null);
          }
          if (e is! TextElement || e.style != from) return e;
          return e.copyWith(style: to);
        }),
        transient: transient);
  }

  /// removeTextStyle forgets style [name]; the texts set in it keep their
  /// type as their own.
  void removeTextStyle(String name) {
    var next = _document.copyWith(textStyles: [
      for (var t in textStyles)
        if (t.name != name) t,
    ]);
    apply(_everyElement(next, (e, _) {
      if (e is CounterElement) {
        return e.copyWith(
            numberStyle: e.numberStyle == name ? "" : null,
            wordStyle: e.wordStyle == name ? "" : null);
      }
      if (e is! TextElement || e.style != name) return e;
      return e.copyWith(style: "");
    }));
  }

  /// linkedTo is every element linked to [e], [e] included, wherever it is.
  List<CanvasElement> linkedTo(CanvasElement e) {
    if (e.base.link.isEmpty) return [e];
    var found = <CanvasElement>[];
    _everyElement(_document, (x, _) {
      if (x.base.link == e.base.link) found.add(x);
      return x;
    });
    return found;
  }

  /// linkedCopy puts a linked copy of element [id] beside it, on the same
  /// canvas, and selects it. Copied to another scene it stays linked.
  void linkedCopy(String id) {
    var e = _document.elementById(id);
    if (e == null) return;
    var link = e.base.link.isEmpty ? newElementId() : e.base.link;
    var linked = e.withBase(link: link);
    var copy = linked
        .withId(newElementId())
        .withBase(x: e.base.x + 24, y: e.base.y + 24, link: link);
    var next = _document.withElement(linked);
    var list = next.elements;
    var at = list.indexWhere((x) => x.id == id);
    apply(next.copyWith(elements: [
      ...list.take(at + 1),
      copy,
      ...list.skip(at + 1),
    ]));
    selectOnly(copy.id);
  }

  /// pushToLinked gives every element linked to [id] its design -- all of
  /// it but where each copy is, how big, when it moves, and what it is
  /// tied to. Says how many it changed.
  int pushToLinked(String id) {
    var source = _document.elementById(id);
    if (source == null || source.base.link.isEmpty) return 0;
    var changed = 0;
    var next = _everyElement(_document, (e, _) {
      if (e.id == id ||
          e.base.link != source.base.link ||
          e.kind != source.kind) {
        return e;
      }
      changed++;
      return source.rebase(e.base);
    });
    apply(next);
    return changed;
  }

  /// unlink lets element [id] go its own way.
  void unlink(String id) {
    var e = _document.elementById(id);
    if (e == null) return;
    apply(_document.withElement(e.withBase(link: "")));
  }

  /// staggerArrivals has the elements [ids] come in one after another, [gap]
  /// frames apart, in order across the canvas -- left to right, or top to
  /// bottom where [downwards]. The first keeps its timing; each later one's
  /// keyframes move so its arrival starts [gap] after the one before's.
  void staggerArrivals(List<String> ids, int gap, {bool downwards = false}) {
    var picked = [
      for (var id in ids)
        if (_document.elementById(id) case var e?
            when e.base.track?.isEmpty == false)
          e,
    ];
    if (picked.length < 2) return;
    picked.sort((a, b) => downwards
        ? a.base.y.compareTo(b.base.y)
        : a.base.x.compareTo(b.base.x));
    int arrivalOf(CanvasElement e) {
      var keys = e.base.track!.keys;
      return (keys
                  .where((k) => k.values.containsKey(KeyframeChannel.reveal))
                  .firstOrNull ??
              keys.first)
          .frame;
    }

    var first = arrivalOf(picked.first);
    var next = _document;
    for (var (i, e) in picked.indexed) {
      var by = first + i * gap - arrivalOf(e);
      if (by == 0) continue;
      next = next.withElement(e.withBase(track: _shifted(e.base.track!, by)));
    }
    apply(next);
  }

  // ------------------------------------------------------------------------
  // Sound tools -- see audio_tools.dart.

  /// _runStartOf is the frame of the run element [id]'s own frames count
  /// from: its scene's start, or nought on the master.
  int _runStartOf(String id) {
    for (var (i, scene) in _document.allScenes.indexed) {
      if (scene.elements.any((e) => e.id == id)) {
        return _document.hasScenes ? _document.startOfScene(i) : 0;
      }
    }
    return 0;
  }

  /// newChannelName is "Channel" and the next number not already taken. A
  /// channel holds sound, and a video's soundtrack beside it, so it is not
  /// "Audio".
  String newChannelName() {
    var taken = {for (var c in timelineChannels) c.name};
    for (var n = 1;; n++) {
      if (!taken.contains("Channel $n")) return "Channel $n";
    }
  }

  /// newChannelId is an id for a channel not made yet.
  String newChannelId() => "ch${newElementId()}";

  /// moveClipToChannel puts [lane]'s sound on [to] -- taking its name and its
  /// strip -- or, with none, on a channel of its own. The channel it leaves
  /// is gone if it was the last thing on it.
  void moveClipToChannel(TimedLane lane, TimelineChannel? to,
      {bool transient = false}) {
    var e = lane.element;
    if ((e is! AudioElement && e is! VideoElement) || !lane.editable) return;
    // Onto a channel of its own canvas: a channel is the clips on it, and
    // one holding a scene's clip and the master's would be two canvases'.
    if (to != null && to.first.scene != lane.scene) return;
    var clip = lane.clip;
    var moved = to == null
        ? clip.copyWith(
            channel: newChannelId(),
            channelName: newChannelName(),
            mix: const ChannelMix())
        : clip.copyWith(channel: to.key, channelName: to.name, mix: to.mix);
    _setClips([(lane.element, moved)], transient: transient);
  }

  /// splitClip cuts [lane]'s sound in two at [frame] of the scene: what is
  /// before stays, and what is after becomes a sound of its own on the same
  /// channel, starting where the cut was. The knife.
  bool splitClip(TimedLane lane, int frame) {
    var e = lane.element;
    // A sound, or a video -- whose two halves are two videos in the same
    // place on the canvas, each on screen while its half plays.
    if ((e is! AudioElement && e is! VideoElement) ||
        !lane.editable ||
        e.locked) {
      return false;
    }
    var clip = lane.clip;
    CanvasElement withClip(MediaClip c) => switch (e) {
          VideoElement v => v.copyWith(clip: c),
          AudioElement a => a.copyWith(clip: c),
          _ => e,
        };
    // Both halves on one channel. A video put on the timeline from its
    // settings has none of its own -- its lane is keyed by its id -- so it
    // is given one here, or the half after the cut would be a lane apart.
    if (clip.channel.isEmpty) {
      clip = clip.copyWith(
          channel: newChannelId(),
          channelName: clip.channelName.isNotEmpty ? clip.channelName : e.name);
    }
    var rate = math.max(1, _document.frameRate);
    var into = (frame - (clip.at - lane.offset)) / rate;
    if (into <= 0.05 || into >= clip.runLength - 0.05) return false;
    var from = 0.0;
    for (var (i, source) in clip.playlist.indexed) {
      var span = source.span;
      if (into < from + span) {
        var cut = source.start + (into - from);
        var before = [
          ...clip.playlist.take(i),
          source.copyWith(end: cut),
        ];
        var after = [
          source.copyWith(start: cut),
          ...clip.playlist.skip(i + 1),
        ];
        var first = withClip(
            clip.copyWith(playlist: before, fadeOut: 0, loop: MediaLoop.none));
        var second = withClip(clip.copyWith(
                playlist: after,
                fadeIn: 0,
                at: clip.at + (into * rate).round()))
            .withId(newElementId());
        var replaced = _replacedAnywhere(_document, first);
        var both =
            replaced == null ? null : _addedBeside(replaced, first.id, second);
        if (both == null) return false;
        apply(both);
        // Picked where it can be: on the canvas being edited.
        if (_document.elements.any((x) => x.id == second.id)) {
          selectOnly(second.id);
        }
        return true;
      }
      from += span;
    }
    return false;
  }

  /// selectedChannels are the channels picked -- by their strips, by a sound
  /// on them, or by a box dragged across them -- which a cut at the playhead
  /// is made on.
  Set<String> get selectedChannels => _selectedChannels;
  Set<String> _selectedChannels = {};

  /// selectedChannel is the one channel picked, where one is; setting it
  /// picks that alone.
  String? get selectedChannel =>
      _selectedChannels.isEmpty ? null : _selectedChannels.first;
  set selectedChannel(String? key) =>
      selectChannels(key == null ? const {} : {key});

  void selectChannels(Set<String> keys) {
    if (setEquals(keys, _selectedChannels)) return;
    _selectedChannels = {...keys};
    // One channel picked -- on the timeline or in the mixer -- is the one
    // the effects panel shows.
    if (keys.length == 1) _effectsOf = keys.first;
    notifyListeners();
  }

  /// toggleChannel adds [key] to the channels picked, or takes it out.
  void toggleChannel(String key) {
    var next = {..._selectedChannels};
    if (!next.remove(key)) next.add(key);
    selectChannels(next);
  }

  /// cutAtPlayhead cuts the selected channel -- or the channel of the sound
  /// selected -- where the playhead is: every sound on it the playhead is
  /// part way through. The knife's key.
  bool cutAtPlayhead() {
    var keys = {..._selectedChannels};
    if (keys.isEmpty) {
      var picked = clipSelection;
      for (var lane in timedLanes) {
        if (picked.contains(lane.element.id)) keys.add(lane.channelKey);
      }
    }
    var cut = false;
    for (var channel in timelineChannels) {
      if (!keys.contains(channel.key) || channel.locked) continue;
      for (var lane in channel.lanes) {
        // Fresh each time: a cut changes the document the next one reads.
        var now = timedLanes.where((l) => l.element.id == lane.element.id);
        if (now.isEmpty) continue;
        if (splitClip(now.first, _frame)) cut = true;
      }
    }
    return cut;
  }

  /// lockChannel locks or unlocks every sound on [channel]: locked, none of
  /// them is moved, trimmed, faded, cut or dropped onto.
  void lockChannel(TimelineChannel channel, bool locked) {
    var next = _document;
    for (var lane in channel.lanes) {
      if (!lane.editable) continue;
      next = _replacedAnywhere(next, lane.element.withBase(locked: locked)) ??
          next;
    }
    apply(next);
  }

  /// renameChannel names [channel], on every sound it holds.
  void renameChannel(TimelineChannel channel, String name) {
    var named = name.trim();
    if (named.isEmpty) return;
    _setClips([
      for (var lane in channel.lanes)
        if (lane.editable)
          (lane.element, lane.clip.copyWith(channelName: named)),
    ]);
  }

  /// snapping is whether a sound dragged on the timeline lands on the
  /// seconds and the playhead when it comes near them.
  bool get snapping => _snapping;
  bool _snapping = false;
  set snapping(bool value) {
    if (_snapping == value) return;
    _snapping = value;
    notifyListeners();
  }

  /// timelineTool is what a press on a sound on the timeline does: take hold
  /// of it, or cut it in two.
  TimelineTool get timelineTool => _timelineTool;
  TimelineTool _timelineTool = TimelineTool.select;
  set timelineTool(TimelineTool value) {
    if (_timelineTool == value) return;
    _timelineTool = value;
    notifyListeners();
  }

  /// laneHeights is how tall each channel has been dragged, by channel. The
  /// reader's, not the document's: kept for each canvas by the screen -- see
  /// canvasView.
  final Map<String, double> laneHeights = {};

  /// setLaneHeight changes one channel's height.
  void setLaneHeight(String channel, double height) {
    laneHeights[channel] = height;
    notifyListeners();
  }

  /// mixerOpen is whether the mixer is shown, under the canvas. The
  /// reader's, kept by the screen -- see panelState.
  bool get mixerOpen => _mixerOpen;
  bool _mixerOpen = false;
  set mixerOpen(bool open) {
    if (open == _mixerOpen) return;
    _mixerOpen = open;
    if (!open) {
      _mixerMinimised = false;
      _mixerSmallest = false;
    }
    notifyListeners();
  }

  /// mixerSmallest is the mixer smaller still than minimised: its strips
  /// without their names, and without the rail of bands down its right --
  /// only what each channel is doing. Dragged down past its least, or the
  /// Mixer button's step after minimised.
  bool get mixerSmallest => _mixerOpen && _mixerSmallest;
  bool _mixerSmallest = false;
  set mixerSmallest(bool on) {
    if (on == _mixerSmallest) return;
    _mixerSmallest = on;
    if (on) _mixerOpen = true;
    notifyListeners();
  }

  /// mixerMinimised is the mixer folded to its shortest: one line of
  /// channels, each its name over its meter on its side -- as it is dragged
  /// all the way down. Open still.
  bool get mixerMinimised => _mixerOpen && _mixerMinimised;
  bool _mixerMinimised = false;
  set mixerMinimised(bool on) {
    if (on == _mixerMinimised) return;
    _mixerMinimised = on;
    if (on) _mixerOpen = true;
    notifyListeners();
  }

  /// cycleMixer is the timeline's Mixer button: shown, then minimised, then
  /// smallest, then hidden, then shown again.
  void cycleMixer() {
    if (!_mixerOpen) {
      _mixerOpen = true;
      _mixerMinimised = false;
      _mixerSmallest = false;
    } else if (_mixerSmallest) {
      _mixerOpen = false;
      _mixerMinimised = false;
      _mixerSmallest = false;
    } else if (_mixerMinimised) {
      _mixerSmallest = true;
    } else {
      _mixerMinimised = true;
    }
    notifyListeners();
  }

  // ---- Kept between visits

  /// panelState is how the panels under the canvas were left, whatever
  /// canvas is open -- the mixer open, minimised or smallest, the effects
  /// open, the devices folded, the channels' size and the strip column's
  /// width -- for the screen to keep. See restorePanels.
  Map<String, dynamic> get panelState => {
        "mixer": !_mixerOpen
            ? "hidden"
            : _mixerSmallest
                ? "smallest"
                : _mixerMinimised
                    ? "minimised"
                    : "shown",
        "effects": _effectsOpen,
        "folded": [...foldedDevices]..sort(),
        "laneSize": _laneSize,
        "header": _headerWidth,
      };

  /// restorePanels puts the panels back as [state] -- from panelState --
  /// says, without telling anyone: the screen does it as it opens.
  void restorePanels(Map<String, dynamic> state) {
    switch (state["mixer"]) {
      case "shown":
        _mixerOpen = true;
      case "minimised":
        _mixerOpen = _mixerMinimised = true;
      case "smallest":
        _mixerOpen = _mixerMinimised = _mixerSmallest = true;
    }
    if (state["effects"] == true) _effectsOpen = true;
    if (state["folded"] case List folded) {
      foldedDevices
        ..clear()
        ..addAll(folded.whereType<String>());
    }
    if (state["laneSize"] case int size when size >= 0 && size < 3) {
      _laneSize = size;
    }
    if (state["header"] case num width) {
      _headerWidth =
          width.toDouble().clamp(timelineHeaderMin, timelineHeaderMax);
    }
  }

  /// timelineView is the stretch the timeline is zoomed to -- null for all
  /// of it -- as the timeline last drew it; timelineViewSet counts the
  /// times it was put back from outside, for the timeline to take up.
  TimelineView? timelineView;
  int timelineViewSet = 0;

  /// canvasView is how this canvas was being looked at -- its channels'
  /// heights, its narrow strips, the timeline's zoom and the effects'
  /// channel -- for the screen to keep with its name. See restoreCanvasView.
  Map<String, dynamic> get canvasView => {
        if (laneHeights.isNotEmpty)
          "lanes": {
            for (var e in laneHeights.entries)
              e.key: double.parse(e.value.toStringAsFixed(1))
          },
        if (_narrowStrips.isNotEmpty) "narrow": [..._narrowStrips]..sort(),
        if (timelineView case var v?)
          "view": [
            double.parse(v.first.toStringAsFixed(2)),
            double.parse(v.span.toStringAsFixed(2))
          ],
        if (_effectsOf case var e?) "effectsOf": e,
      };

  /// restoreCanvasView looks at this canvas as [state] -- from canvasView
  /// -- says: nothing for one never looked at.
  void restoreCanvasView(Map<String, dynamic> state) {
    laneHeights.clear();
    if (state["lanes"] case Map lanes) {
      for (var e in lanes.entries) {
        if (e.key is String && e.value is num) {
          laneHeights[e.key as String] = (e.value as num).toDouble();
        }
      }
    }
    _narrowStrips
      ..clear()
      ..addAll([
        if (state["narrow"] case List narrow) ...narrow.whereType<String>()
      ]);
    timelineView = switch (state["view"]) {
      [num first, num span] when span > 0 =>
        TimelineView(first.toDouble(), span.toDouble()),
      _ => null,
    };
    timelineViewSet++;
    if (state["effectsOf"] case String e) _effectsOf = e;
    notifyListeners();
  }

  /// effectsChannel is the strip the timeline's effects button opens: the
  /// channel picked -- in the mixer or on the timeline -- or the master
  /// when that is what is picked, or else the channel of the sound picked,
  /// or else the master.
  String get effectsChannel {
    var channels = timelineChannels;
    if (selectedChannel case var k?) {
      if (k == mixerMasterKey ||
          channels.any((c) => c.key == k) ||
          returnOf(k) != null) {
        return k;
      }
    }
    var picked = clipSelection;
    for (var lane in timedLanes) {
      if (picked.contains(lane.element.id)) return lane.channelKey;
    }
    return mixerMasterKey;
  }

  /// effectsOpen is whether the effects panel is shown: the chain of
  /// effectsOf, in a panel of its own over the mixer.
  bool get effectsOpen => _effectsOpen;
  bool _effectsOpen = false;
  set effectsOpen(bool open) {
    if (open == _effectsOpen) return;
    _effectsOpen = open;
    notifyListeners();
  }

  /// effectsFocus is the device the effects panel was last asked to show --
  /// "eq", "comp", "duck" ... -- and effectsFocusCount how many times it has
  /// been asked, so asking for the same one again scrolls to it again.
  String? get effectsFocus => _effectsFocus;
  String? _effectsFocus;
  int get effectsFocusCount => _effectsFocusCount;
  int _effectsFocusCount = 0;

  /// openEffects shows [key]'s chain in the effects panel, unfolded on and
  /// scrolled to [device] where one is given.
  void openEffects(String key, {String? device}) {
    if (device != null) {
      foldedDevices.remove(device);
      _effectsFocus = device;
      _effectsFocusCount++;
    }
    _effectsOf = key;
    _effectsOpen = true;
    notifyListeners();
  }

  // ---- The clip editor

  /// editorWide is whether the editor in the effects strip -- a clip's, or
  /// a part's piano roll -- is widened: every setting, and the most room.
  bool get editorWide => _editorWide;
  bool _editorWide = false;
  void toggleEditorWide() {
    _editorWide = !_editorWide;
    _editorWidth = null;
    _effectsFocus = _clipEditorShown ? "clip" : "roll";
    _effectsFocusCount++;
    notifyListeners();
  }

  /// editorWidth is how wide the editor has been dragged by its right edge
  /// -- or null, as Wider or Narrower has it. Kept while the canvas is open.
  double? get editorWidth => _editorWidth;
  double? _editorWidth;
  set editorWidth(double? width) {
    if (width == _editorWidth) return;
    _editorWidth = width;
    notifyListeners();
  }

  /// closeEditor takes the editor out of the effects strip.
  void closeEditor() {
    _clipEditorShown = false;
    _pianoRollShown = false;
    notifyListeners();
  }

  /// clipEditing is the slot the clip editor is open on -- a channel and a
  /// row -- or null where none is, or its clip has gone. It shares the
  /// effects panel with the chain: [clipEditorShown] says which shows.
  PianoRollTarget? get clipEditing {
    var t = _clipEditing;
    if (t == null || t.row == null) return null;
    if (session.at(t.channel, t.row!) == null) return null;
    return t;
  }

  PianoRollTarget? _clipEditing;
  bool get clipEditorShown => _clipEditorShown && clipEditing != null;
  bool _clipEditorShown = false;
  set clipEditorShown(bool on) {
    if (on == _clipEditorShown) return;
    _clipEditorShown = on;
    notifyListeners();
  }

  /// editedClip is the clip the editor is open on.
  SessionClip? get editedClip {
    var t = clipEditing;
    return t == null ? null : session.at(t.channel, t.row!);
  }

  /// rollSelected are the notes picked in the piano roll, by their place in
  /// its notes: what the Notes tools change.
  final Set<int> rollSelected = {};

  /// openClipEditor opens the clip editor on [channel]'s slot [row], in the
  /// effects panel -- a MIDI clip's notes in the piano roll beside it.
  void openClipEditor(String channel, int row) {
    var clip = session.at(channel, row);
    if (clip == null) return;
    _clipEditing = PianoRollTarget(channel, row);
    if (clip.midi && _instrumentOf(channel) != null) {
      _pianoRoll = PianoRollTarget(channel, row);
    }
    rollSelected.clear();
    _clipCursor = 0;
    _effectsOf = channel;
    _effectsOpen = true;
    _pianoRollShown = false;
    _clipEditorShown = true;
    // First in the strip: scrolled to.
    _effectsFocus = "clip";
    _effectsFocusCount++;
    notifyListeners();
  }

  /// editClip changes the clip the editor is open on: one change to undo
  /// -- or, [transient], part of a drag that is.
  void editClip(SessionClip Function(SessionClip clip) change,
      {bool transient = false}) {
    var t = clipEditing;
    if (t == null) return;
    var clip = session.at(t.channel, t.row!)!;
    apply(
        _document.copyWith(
            session: session.put(t.channel, t.row!, change(clip))),
        transient: transient);
    if (!transient) _warpSoon();
  }

  /// previewClip plays the open clip now -- not on the next bar -- to hear
  /// it while it is edited: with the transport stopped, on its own, the
  /// timeline silent (see sessionOnly). Pressed while it plays, it stops.
  void previewClip() {
    var t = clipEditing;
    var clip = editedClip;
    if (t == null || clip == null) return;
    var state = clipState(t.channel, t.row!);
    if (state == ClipState.playing || state == ClipState.queued) {
      var ch = _clipChannels[t.channel];
      if (ch != null) {
        _cancelNext(ch);
        _stopChannelAt(t.channel, _sessionNow);
      }
      notifyListeners();
      return;
    }
    var at = playing ? _sessionNow : _sessionStart();
    unawaited(_startClip(t.channel, t.row!, clip, at));
  }

  /// clipPreviewing is whether the open clip is playing, for its editor's
  /// Play to show Stop.
  bool get clipPreviewing {
    var t = clipEditing;
    if (t == null) return false;
    var state = clipState(t.channel, t.row!);
    return state == ClipState.playing || state == ClipState.queued;
  }

  /// selectedSlot is the clip slot last clicked: picked out in the mixer,
  /// and -- as Ableton's Clip View always shows the clip selected -- the one
  /// in the clip editor, where that is open.
  (String, int)? get selectedSlot => _selectedSlot;
  (String, int)? _selectedSlot;

  void selectSlot(String channel, int row) {
    _selectedSlot = (channel, row);
    if (_clipEditorShown && session.at(channel, row) != null) {
      openClipEditor(channel, row);
      return;
    }
    notifyListeners();
  }

  /// canMoveClip is whether [channel]'s slots can take clip [clip]: a MIDI
  /// clip on a MIDI channel, a sound on an audio one.
  bool canMoveClip(SessionClip clip, String channel) =>
      clip.midi == instrumentChannel(channel);

  /// moveClip moves the clip in [fromChannel]'s slot [fromRow] to
  /// [toChannel]'s [toRow] -- in place of what was there -- or, with
  /// [copy], puts a copy of it there. One change to undo.
  void moveClip(String fromChannel, int fromRow, String toChannel, int toRow,
      {bool copy = false}) {
    var clip = session.at(fromChannel, fromRow);
    if (clip == null || !canMoveClip(clip, toChannel)) return;
    if (fromChannel == toChannel && fromRow == toRow) return;
    var moved = copy ? clip.copyWith(id: newElementId()) : clip;
    // A clip playing from either slot stops: it is somewhere else now.
    for (var (ch, row) in [(fromChannel, fromRow), (toChannel, toRow)]) {
      var playing = _clipChannels[ch];
      if (playing != null &&
          (playing.now?.row == row || playing.next?.row == row) &&
          !(copy && ch == fromChannel && row == fromRow)) {
        _stopChannelAt(ch, _sessionNow);
      }
    }
    var grid = session.put(toChannel, toRow, moved);
    if (!copy) grid = grid.put(fromChannel, fromRow, null);
    apply(_document.copyWith(session: grid));
    // The editor follows the clip it was showing.
    if (!copy &&
        _clipEditing?.channel == fromChannel &&
        _clipEditing?.row == fromRow) {
      _clipEditing = PianoRollTarget(toChannel, toRow);
      if (moved.midi) _pianoRoll = PianoRollTarget(toChannel, toRow);
    }
    _selectedSlot = (toChannel, toRow);
    notifyListeners();
  }

  /// _editClipById changes clip [id], wherever it is now: for a change
  /// that took a while -- a sound reversed, cropped, its tempo heard --
  /// while the editor may have moved on to another clip.
  void _editClipById(String id, SessionClip Function(SessionClip clip) change) {
    if (session.find(id) case (var channel, var row)?) {
      setSessionClip(channel, row, change(session.at(channel, row)!));
      _warpSoon();
    }
  }

  /// scaleOf is the scale [channel] is in: its Scale effect's, or C major.
  (int, List<int>) scaleOf(String channel) {
    var scale = _instrumentOf(channel)
        ?.instrument
        ?.effects
        .where((m) => m.on && m.kind == MidiEffectKind.scale)
        .firstOrNull;
    if (scale == null) return (0, scaleSteps[0]);
    return (
      scale.choice("root"),
      scaleSteps[scale.choice("scale").clamp(0, scaleSteps.length - 1)]
    );
  }

  /// useNoteTool uses [tool] on the open MIDI clip's picked notes -- or all
  /// of them.
  void useNoteTool(NoteTool tool) {
    var t = clipEditing;
    var clip = editedClip;
    // A part's notes, in its piano roll.
    var roll = pianoRoll;
    if (pianoRollShown && roll != null && roll.row == null) {
      var content = rollContent!;
      setRollContent(
          notes: applyNoteTool(tool, content.notes, rollSelected,
              scale: scaleOf(roll.channel),
              loopEnd: content.beats,
              seed: _noteToolPresses++));
      return;
    }
    if (t == null || clip == null || !clip.midi) return;
    var bpb = _document.audio.beatsPerBar;
    var notes = applyNoteTool(tool, clip.notes, rollSelected,
        scale: scaleOf(t.channel),
        loopEnd: clip.loopEnd(bpb),
        seed: _noteToolPresses++);
    editClip((c) => c.copyWith(notes: notes));
  }

  int _noteToolPresses = 1;

  /// clipAudio is the whole of a stored sound, both sides at the mix's
  /// rate, for Reverse and Crop to make a new file from -- or null. A
  /// stand-in for tests.
  static Future<(Float32List, Float32List)?> Function(String assetId)
      clipAudio = (id) async {
    var file = await CanvasMedia.existingPath(MediaKind.audio, id);
    if (file == null) return null;
    // Read by the mix engine's own decoder, or -- M4A, AAC, Opus, a
    // video's sound, which it has no reader for -- by ffmpeg, as the mixer
    // plays them. Away from the app's own isolate: a whole song read there
    // stopped everything -- the mixer's sound with it -- for a second or
    // more.
    if (await readWholeAway(file) case var sound?) return sound;
    var ffmpeg = await ffmpegPath();
    return ffmpeg == null ? null : ffmpegDecode(ffmpeg, file);
  };

  /// _keepSound stores [wav] -- a WAV file's bytes -- as a new sound in
  /// the library -- see speechStore -- answering its id, or null.
  Future<String?> _keepSound(Uint8List wav) async {
    var dir = await Directory.systemTemp.createTemp("canvas-clip");
    try {
      var file = File(path.join(dir.path, "clip.wav"));
      await file.writeAsBytes(wav, flush: true);
      return await speechStore(file.path);
    } finally {
      await dir.delete(recursive: true).catchError((_) => dir);
    }
  }

  /// reverseClip plays the open audio clip backwards: a reversed copy of
  /// its file, made and kept in the library, the original kept too -- so
  /// pressed again, it is the original once more. Answers why not.
  Future<String?> reverseClip() async {
    var clip = editedClip;
    var sound = clip?.sound;
    if (clip == null || clip.midi || sound == null) return null;
    if (clip.reversedOf case var original?) {
      _editClipById(
          clip.id,
          (c) => _markersMirrored(
              c.copyWith(sound: original, clearReversed: true),
              _spanOf(original)));
      return null;
    }
    var audio = await clipAudio(sound.assetId);
    if (audio == null) return "Its sound could not be read.";
    var (l, r) = audio;
    var n = l.length;
    // Turned round and written out away from the app's own isolate, as it
    // was read.
    var id = await _keepSound(await _reversedWavAway(l, r));
    if (id == null || _disposed) return "The reversed sound could not be kept.";
    var length = n / mixRate;
    var end = sound.end > 0 ? sound.end : length;
    var reversed = MediaSource(
        assetId: id,
        name: "${sound.name.isEmpty ? "Clip" : sound.name} (reversed)",
        start: math.max(0, length - end),
        end: math.max(0, length - sound.start),
        length: length);
    _editClipById(
        clip.id,
        (c) => _markersMirrored(
            c.copyWith(sound: reversed, reversedOf: sound), end - sound.start));
    return null;
  }

  /// _spanOf is how long [sound] plays, in seconds.
  double _spanOf(MediaSource sound) => sound.end > 0
      ? sound.end - sound.start
      : math.max(0, sound.length - sound.start);

  /// _markersMirrored is [clip] with its warp markers turned round with its
  /// sound -- [seconds] of it played: what was a moment from its start is
  /// that moment from its end, on the beat as far from its last.
  ///
  /// Its end pinned too, where its start was: past its last marker a sound
  /// goes at its tempo, so turned round without it, what was its first
  /// stretch would be stretched differently, and twice reversed would not
  /// be as it was.
  SessionClip _markersMirrored(SessionClip clip, double seconds) {
    if (clip.markers.isEmpty || seconds <= 0) return clip;
    var last = clip.warpMap.beatAt(seconds);
    return clip.copyWith(markers: [
      for (var m in clip.markers)
        if (m.seconds > 0 && m.seconds < seconds - 1e-6)
          (seconds: seconds - m.seconds, beat: last - m.beat),
      (seconds: seconds, beat: last),
    ]);
  }

  /// cropClip keeps only what the open clip plays -- from its start, or its
  /// loop's start where that is earlier, to its loop's end -- as a new file
  /// for an audio clip, or the notes there for a MIDI one, and moves its
  /// start and loop to match. Answers why not.
  Future<String?> cropClip() async {
    var clip = editedClip;
    if (clip == null) return null;
    var bpb = _document.audio.beatsPerBar;
    var spb = math.max(0.001, _document.audio.secondsPerBeat);
    var from = clip.loop ? math.min(clip.start, clip.loopStart) : clip.start;
    var to = clip.loopEnd(bpb);
    if (to <= from) return null;
    SessionClip moved(SessionClip c) =>
        c.copyWith(start: c.start - from, loopStart: c.loopStart - from);
    if (clip.midi) {
      _editClipById(
          clip.id,
          (c) => moved(c).copyWith(notes: [
                for (var n in c.notes)
                  if (n.end > from && n.start < to)
                    n.copyWith(
                        start: math.max(0, n.start - from),
                        length: math.min(n.end, to) - math.max(n.start, from)),
              ]));
      return null;
    }
    var sound = clip.sound;
    if (sound == null) return null;
    var audio = await clipAudio(sound.assetId);
    if (audio == null) return "Its sound could not be read.";
    var (l, r) = audio;
    // Where its beats are in its sound: by its warp map, warped; at the
    // song's tempo -- faster with its pitch -- not.
    var speed = math.pow(2, (clip.pitch + clip.cents / 100) / 12).toDouble();
    double sourceOf(double beat) =>
        clip.warp ? clip.warpMap.sourceAt(beat) : beat * spb * speed;
    var s0 = sourceOf(from), s1 = sourceOf(to);
    var a = ((sound.start + s0) * mixRate).round().clamp(0, l.length);
    var b = ((sound.start + s1) * mixRate).round().clamp(a, l.length);
    if (b - a < 1) return "There is no sound there to keep.";
    var id = await _keepSound(await _wavAway(
        Float32List.sublistView(l, a, b), Float32List.sublistView(r, a, b)));
    if (id == null || _disposed) return "The cropped sound could not be kept.";
    var cropped = MediaSource(
        assetId: id,
        name: "${sound.name.isEmpty ? "Clip" : sound.name} (cropped)",
        length: (b - a) / mixRate);
    // Its warp markers moved with it, and its end pinned where it was.
    var markers = [
      for (var m in clip.markers)
        if (m.seconds > s0 + 1e-6 && m.seconds < s1 - 1e-6)
          (seconds: m.seconds - s0, beat: m.beat - from),
      if (clip.warp && clip.markers.isNotEmpty)
        (seconds: s1 - s0, beat: to - from),
    ];
    _editClipById(
        clip.id,
        (c) => moved(c)
            .copyWith(sound: cropped, clearReversed: true, markers: markers));
    return null;
  }

  // ---- Warping

  /// warping are the clips whose sound is being warped now, by id.
  final Set<String> warping = {};
  final Map<String, Future<MediaSource?>> _warpingNow = {};
  Timer? _warpTimer;

  /// _playedSound is what audio [clip] plays: its own sound, or -- warped,
  /// or moved in pitch -- that rendered at the song's tempo, made now where
  /// it has not been. See warp.dart.
  Future<MediaSource?> _playedSound(SessionClip clip) async {
    if (!clip.needsRender || clip.sound == null) return clip.sound;
    var spb = _document.audio.secondsPerBeat;
    var signature = clip.warpSignature(spb);
    // Rendered already -- and still there: a file the library swept away
    // is rendered again, not played as silence.
    if (clip.warpedFor == signature && clip.warped != null) {
      if (await CanvasMedia.existingPath(
              MediaKind.audio, clip.warped!.assetId) !=
          null) {
        return clip.warped;
      }
    }
    return _warpingNow[signature] ??= _warp(clip, signature).whenComplete(() {
      _warpingNow.remove(signature);
    });
  }

  Future<MediaSource?> _warp(SessionClip clip, String signature) async {
    var sound = clip.sound!;
    warping.add(clip.id);
    notifyListeners();
    try {
      var audio = await clipAudio(sound.assetId);
      if (audio == null || _disposed) return null;
      var (l, r) = audio;
      var length = l.length / mixRate;
      var from = sound.start, to = sound.end > 0 ? sound.end : length;
      var spb = _document.audio.secondsPerBeat;
      var map = clip.warpMap;
      var (warp, mode) = (clip.warp, clip.warpMode);
      var semitones = clip.pitch + clip.cents / 100;
      var (wav, frames) = await _warpedWavAway(
          l, r, from, to, warp, mode, map, spb, semitones, clip.envelopes);
      var id = await partStore(wav);
      if (id == null || _disposed) return null;
      var warped = MediaSource(
          assetId: id,
          name: "${sound.name.isEmpty ? "Clip" : sound.name} (warped)",
          length: frames / mixRate);
      // Written onto the clip as it is now, if it is still there and still
      // wants this: not a change of its own to undo -- the file follows
      // the clip.
      if (session.find(clip.id) case (var ch, var row)?) {
        var now = session.at(ch, row)!;
        if (now.warpSignature(spb) == signature) {
          apply(
              _document.copyWith(
                  session: session.put(ch, row,
                      now.copyWith(warped: warped, warpedFor: signature))),
              transient: true);
        }
      }
      return warped;
    } catch (exception) {
      debugPrint("Unable to warp the clip: $exception");
      return null;
    } finally {
      warping.remove(clip.id);
      if (!_disposed) notifyListeners();
    }
  }

  /// _warpSoon warps every clip that needs it, a moment after the last
  /// change -- so a clip is ready before it is launched.
  void _warpSoon() {
    _warpTimer?.cancel();
    _warpTimer = Timer(const Duration(milliseconds: 400), () async {
      for (var (_, _, clip) in session.clips) {
        if (_disposed) return;
        if (clip.needsRender) await _playedSound(clip);
      }
    });
  }

  /// setWarp switches the open audio clip's warping on or off. On for the
  /// first time, its tempo is heard first -- see estimateTempo.
  Future<String?> setWarp(bool on) async {
    var clip = editedClip;
    var sound = clip?.sound;
    if (clip == null || clip.midi || sound == null) return null;
    var bpm = clip.bpm;
    if (on && bpm == 0) {
      var audio = await clipAudio(sound.assetId);
      if (audio == null) return "Its sound could not be read.";
      var (l, r) = audio;
      var from = (sound.start * mixRate).round().clamp(0, l.length);
      var to = sound.end > 0
          ? (sound.end * mixRate).round().clamp(from, l.length)
          : l.length;
      var near = _document.audio.tempo;
      var bpb = _document.audio.beatsPerBar;
      var sl = Float32List.sublistView(l, from, to);
      var sr = Float32List.sublistView(r, from, to);
      bpm = await _tempoAway(sl, sr, near, bpb);
      if (_disposed) return null;
    }
    _editClipById(clip.id, (c) => c.copyWith(warp: on, bpm: bpm));
    return null;
  }

  /// clipPlayhead is where the open clip is playing, in beats into it --
  /// what its Set buttons take -- or null where it is not playing.
  double? get clipPlayhead {
    var t = clipEditing;
    if (t == null) return null;
    var ch = _clipChannels[t.channel]?.now;
    if (ch == null || ch.row != t.row) return null;
    return clipAt(t.channel);
  }

  // ---- The piano roll

  /// pianoRoll is what the piano roll edits: a MIDI clip in a slot, or a
  /// MIDI channel's part -- or null for nothing opened yet. It shares the
  /// effects panel with the chain: [pianoRollShown] says which shows.
  PianoRollTarget? get pianoRoll {
    var t = _pianoRoll;
    if (t == null || _instrumentOf(t.channel) == null) return null;
    if (t.row case var row? when session.at(t.channel, row) == null) {
      return null;
    }
    return t;
  }

  PianoRollTarget? _pianoRoll;
  bool get pianoRollShown => _pianoRollShown && pianoRoll != null;
  bool _pianoRollShown = false;
  set pianoRollShown(bool on) {
    if (on == _pianoRollShown) return;
    _pianoRollShown = on;
    notifyListeners();
  }

  /// openPianoRoll opens the piano roll on MIDI channel [channel]'s part,
  /// or on its clip in slot [row], in the effects panel.
  void openPianoRoll(String channel, {int? row}) {
    // A clip's notes are in its clip editor.
    if (row != null) {
      openClipEditor(channel, row);
      return;
    }
    if (_instrumentOf(channel) == null) return;
    _pianoRoll = PianoRollTarget(channel, row);
    _effectsOf = channel;
    _effectsOpen = true;
    _pianoRollShown = true;
    _clipEditorShown = false;
    _effectsFocus = "roll";
    _effectsFocusCount++;
    rollSelected.clear();
    notifyListeners();
  }

  /// rollContent is what the piano roll shows, in beats: the notes, the
  /// controllers' curves, and how long it is -- a clip's length, or a
  /// part's, to the end of the bar after its last note and never under
  /// four bars.
  RollContent? get rollContent {
    var t = pianoRoll;
    if (t == null) return null;
    var a = _document.audio;
    if (t.row case var row?) {
      // To its loop's end: a loop moved on shows where it starts from.
      var clip = session.at(t.channel, row)!;
      return RollContent(clip.notes, clip.controls, clip.loopEnd(a.beatsPerBar),
          name: clip.name.isEmpty ? "Clip" : clip.name, clip: true);
    }
    var e = _instrumentOf(t.channel)!;
    var part = e.instrument!;
    var spb = math.max(0.001, a.secondsPerBeat);
    var notes = [
      for (var n in part.notes)
        MidiNote(n.key, n.start / spb, n.length / spb, n.velocity),
    ];
    var end = notes.isEmpty ? 0.0 : notes.map((n) => n.end).reduce(math.max);
    var bars = math.max(4, (end / a.beatsPerBar).ceil() + 1);
    return RollContent(
        notes,
        {
          for (var c in part.controls.entries)
            c.key: [for (var (t, v) in c.value) (t / spb, v)],
        },
        bars * a.beatsPerBar.toDouble(),
        name: "${e.name} part",
        clip: false);
  }

  /// setRollContent writes what the piano roll changed: notes and curves in
  /// beats, and -- for a clip -- its length in beats.
  void setRollContent(
      {List<MidiNote>? notes,
      Map<MidiControl, List<ControlPoint>>? controls,
      double? beats,
      bool transient = false}) {
    var t = pianoRoll;
    if (t == null) return;
    var a = _document.audio;
    if (t.row case var row?) {
      var clip = session.at(t.channel, row)!;
      apply(
          _document.copyWith(
              session: session.put(
                  t.channel,
                  row,
                  clip.copyWith(
                      notes: notes,
                      controls: controls,
                      bars: beats == null
                          ? null
                          : (beats - clip.loopStart) / a.beatsPerBar))),
          transient: transient);
      return;
    }
    var e = _instrumentOf(t.channel)!;
    var spb = math.max(0.001, a.secondsPerBeat);
    var part = e.instrument!.copyWith(
      notes: notes == null
          ? null
          : [
              for (var n in notes)
                MidiNote(n.key, n.start * spb, n.length * spb, n.velocity),
            ],
      controls: controls == null
          ? null
          : {
              for (var c in controls.entries)
                c.key: [for (var (t, v) in c.value) (t * spb, v)],
            },
    );
    setInstrument(e, part, transient: transient);
  }

  /// rollCursor is where in what the piano roll shows a paste goes, in
  /// beats: for a part, the playhead's place in it -- set, it moves the
  /// playhead, and Play starts there; for a clip, a marker of its own, its
  /// loop playing on regardless.
  double get rollCursor {
    var t = pianoRoll;
    if (t == null) return 0;
    if (t.row != null) return _clipCursor;
    var e = _instrumentOf(t.channel)!;
    return _nowInPart(e) / math.max(0.001, _document.audio.secondsPerBeat);
  }

  set rollCursor(double beats) {
    var t = pianoRoll;
    if (t == null) return;
    beats = math.max(0, beats);
    if (t.row != null) {
      if (beats == _clipCursor) return;
      _clipCursor = beats;
      notifyListeners();
      return;
    }
    var e = _instrumentOf(t.channel)!;
    frame = e.clip.at +
        (beats * _document.audio.secondsPerBeat * _document.frameRate).round();
  }

  double _clipCursor = 0;

  /// movePart moves the piano roll's part along the timeline by [bars],
  /// never before the start.
  void movePart(int bars) {
    var t = pianoRoll;
    if (t == null || t.row != null) return;
    var e = _instrumentOf(t.channel)!;
    var a = _document.audio;
    var by = (bars * a.beatsPerBar * a.secondsPerBeat * _document.frameRate)
        .round();
    setTimedClip(e, e.clip.copyWith(at: math.max(0, e.clip.at + by)));
  }

  /// rollPlayhead is where playing has got in what the piano roll shows,
  /// in beats, or null where it is not playing.
  double? get rollPlayhead {
    var t = pianoRoll;
    if (t == null || !playing) return null;
    if (t.row case var row?) {
      var ch = _clipChannels[t.channel];
      if (ch?.now?.row != row) return null;
      var p = clipProgress(t.channel);
      var c = rollContent;
      return p == null || c == null ? null : p * c.beats;
    }
    var e = _instrumentOf(t.channel)!;
    return _nowInPart(e) / math.max(0.001, _document.audio.secondsPerBeat);
  }

  /// pickStrip picks the channel [key] -- or the master, mixerMasterKey --
  /// from the mixer: picked on the timeline too, and its chain the one the
  /// effects panel shows.
  void pickStrip(String key) {
    if (selectedChannel == key && _effectsOf == key) return;
    _effectsOf = key;
    selectedChannel = key;
    notifyListeners();
  }

  /// effectsOf is the strip whose chain of effects the effects panel shows,
  /// by key or mixerMasterKey, or null for none chosen yet.
  String? get effectsOf => _effectsOf;
  String? _effectsOf;
  set effectsOf(String? key) {
    if (key == _effectsOf) return;
    _effectsOf = key;
    notifyListeners();
  }

  /// keyframesShown and scenesShown are whether the timeline shows its row
  /// of keyframes and, while every scene plays, its strip of scenes: hidden
  /// for room, the ruler and the channels stay.
  bool get keyframesShown => _keyframesShown;
  bool _keyframesShown = true;
  set keyframesShown(bool shown) {
    if (shown == _keyframesShown) return;
    _keyframesShown = shown;
    notifyListeners();
  }

  bool get scenesShown => _scenesShown;
  bool _scenesShown = true;
  set scenesShown(bool shown) {
    if (shown == _scenesShown) return;
    _scenesShown = shown;
    notifyListeners();
  }

  /// restoreShown puts back which timeline rows were showing, as the
  /// preferences kept them -- without notifying, as restoreFit, because it
  /// runs while the page is being built.
  void restoreShown(
      {required bool keyframes, required bool scenes, required bool cues}) {
    _keyframesShown = keyframes;
    _scenesShown = scenes;
    _cuesShown = cues;
  }

  /// cuesShown is whether the cues are marked on the timeline's ruler.
  bool get cuesShown => _cuesShown;
  bool _cuesShown = true;
  set cuesShown(bool shown) {
    if (shown == _cuesShown) return;
    _cuesShown = shown;
    notifyListeners();
  }

  /// foldedDevices is which of the mixer's devices are folded down to their
  /// switch and a meter, by the device's id ("eq", "comp", "meter" ...).
  /// The reader's, for this session, and the same on every strip.
  final Set<String> foldedDevices = {};

  void foldDevice(String id, bool folded) {
    if (folded ? !foldedDevices.add(id) : !foldedDevices.remove(id)) return;
    notifyListeners();
  }

  /// laneSize is the height every channel is, unless one has been dragged:
  /// see laneSizeHeights.
  int get laneSize => _laneSize;
  int _laneSize = 0;

  /// nextLaneSize steps every channel to the next of laneSizeHeights, round
  /// to the first after the last -- putting back any dragged one, as the
  /// button means all of them.
  void nextLaneSize() {
    // Three: small, medium and large.
    _laneSize = (_laneSize + 1) % 3;
    laneHeights.clear();
    notifyListeners();
  }

  /// headerWidth is the column of channel strips down the left of the
  /// timeline, dragged anywhere from an icon's width to the whole strip.
  double get headerWidth => _headerWidth;
  double _headerWidth = 150;
  set headerWidth(double value) {
    var next = value.clamp(timelineHeaderMin, timelineHeaderMax).toDouble();
    if (next == _headerWidth) return;
    _headerWidth = next;
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

  /// waveformOf is [assetId]'s shape, as peaks from nought to one across the
  /// whole file, or null until it has been read -- it is read on first asking,
  /// off the main thread, and the timeline is told when it arrives.
  Float32List? waveformOf(String assetId) {
    if (_waveforms.containsKey(assetId)) return _waveforms[assetId];
    if (_readingWaveform.add(assetId)) _readWaveform(assetId);
    return null;
  }

  Future<void> _readWaveform(String assetId) async {
    Float32List? peaks;
    try {
      var path = await CanvasMedia.existingPath(MediaKind.audio, assetId);
      if (path != null) peaks = await audio.engine.peaks(path, waveformPoints);
    } catch (exception) {
      debugPrint("Unable to read the shape of $assetId: $exception");
    }
    _waveforms[assetId] = peaks;
    _readingWaveform.remove(assetId);
    if (!_disposedForWaveform) notifyListeners();
  }

  bool _disposedForWaveform = false;

  /// setTimedClip writes a clip moved or trimmed on the Channels strip back
  /// to whatever holds it: an element on this canvas, or the backdrop.
  void setTimedClip(CanvasElement e, MediaClip clip, {bool transient = false}) {
    var next = switch (e) {
      VideoElement v => v.copyWith(clip: clip),
      AudioElement a => a.copyWith(clip: clip),
      _ => null,
    };
    if (next == null) return;
    var anywhere = _replacedAnywhere(_document, next);
    if (anywhere != null) {
      apply(anywhere, transient: transient);
      return;
    }
    var bg = _document.drawnBackground;
    if (bg.video?.id == e.id && next is VideoElement) {
      setBackground(bg.copyWith(video: next), transient: transient);
    } else if (bg.sound?.id == e.id && next is AudioElement) {
      setBackground(bg.copyWith(sound: next), transient: transient);
    }
  }

  /// _replacedAnywhere is [doc] with [next] in place of the element of its
  /// id, wherever that is: the canvas being edited, the master seen from a
  /// scene, or another scene -- or null where it is none of them. What lets
  /// the timeline change any clip on it while every scene plays.
  ///
  /// A clip on a scene is held to that scene: it starts no earlier than the
  /// scene's first frame and no later than its last. The master's runs the
  /// length of the whole run, and goes where it is put.
  CanvasDocument? _replacedAnywhere(CanvasDocument doc, CanvasElement next) {
    List<CanvasElement> swapped(List<CanvasElement> list) =>
        [for (var e in list) e.id == next.id ? next : e];
    CanvasElement held(CanvasElement e, int frames) => switch (e) {
          VideoElement v when v.clip.timed => v.copyWith(
              clip: v.clip.copyWith(
                  at: v.clip.at.clamp(0, math.max(0, frames - 1)).toInt())),
          AudioElement a when a.clip.timed => a.copyWith(
              clip: a.clip.copyWith(
                  at: a.clip.at.clamp(0, math.max(0, frames - 1)).toInt())),
          _ => e,
        };
    var onMaster = doc.editingMaster;
    if (doc.elements.any((x) => x.id == next.id)) {
      return doc.withElement(onMaster ? next : held(next, doc.frames));
    }
    var master = doc.master;
    if (!onMaster &&
        master != null &&
        master.elements.any((x) => x.id == next.id)) {
      return doc.copyWith(
          master: master.copyWith(elements: swapped(master.elements)));
    }
    for (var (i, scene) in doc.allScenes.indexed) {
      if (!onMaster && i == doc.at) continue;
      if (!scene.elements.any((x) => x.id == next.id)) continue;
      next = held(next, scene.frames);
      return doc.withScene(
          i, scene.copyWith(elements: swapped(scene.elements)));
    }
    return null;
  }

  /// _addedBeside is [doc] with [added] put on whichever canvas [besideId]
  /// is on, just after it -- the second half of a clip cut in two.
  CanvasDocument? _addedBeside(
      CanvasDocument doc, String besideId, CanvasElement added) {
    List<CanvasElement> after(List<CanvasElement> list) => [
          for (var e in list) ...[e, if (e.id == besideId) added],
        ];
    if (doc.elements.any((x) => x.id == besideId)) {
      return doc.addElement(added);
    }
    var master = doc.master;
    if (!doc.editingMaster &&
        master != null &&
        master.elements.any((x) => x.id == besideId)) {
      return doc.copyWith(
          master: master.copyWith(elements: after(master.elements)));
    }
    for (var (i, scene) in doc.allScenes.indexed) {
      if (!doc.editingMaster && i == doc.at) continue;
      if (!scene.elements.any((x) => x.id == besideId)) continue;
      return doc.withScene(i, scene.copyWith(elements: after(scene.elements)));
    }
    return null;
  }

  int? _timedFrame(String id) {
    for (var (e, at) in _timedOnScreen) {
      if (e.id == id) return at;
    }
    return null;
  }

  ClipMoment? _momentOf(CanvasElement e, int frame) {
    var clip = switch (e) {
      VideoElement v => v.clip,
      AudioElement a => a.clip,
      _ => null,
    };
    if (clip == null) return null;
    var rate = _document.frameRate <= 0 ? 1 : _document.frameRate;
    return clip.momentAt((frame - clip.at) / rate);
  }

  /// _syncTimeline puts every timed piece of media where the playhead is:
  /// playing if it is playing, held on the frame under it if not, silent and
  /// out of sight outside its span.
  void _syncTimeline() {
    _applyMix();
    _syncMetronome();
    // Playing only the slots, the timeline is not playing.
    var going = playing && !_sessionOnly;
    var ducks = _duckEnvelopes();
    var rate = math.max(1, _document.frameRate);
    for (var (e, at) in _joinedCuts(_timedOnScreen.toList())) {
      // Practising, the timeline's sounds are quiet: the piece is played
      // live -- the hand not being practised -- at the practice tempo.
      var moment = at == null || _practice != null ? null : _momentOf(e, at);
      // A channel playing from its slots is not playing the timeline.
      if (moment != null && (_clipChannels.isNotEmpty || offTimeline)) {
        var clip = switch (e) {
          AudioElement a => a.clip,
          VideoElement v => v.clip,
          _ => null,
        };
        var key = clip == null || clip.channel.isEmpty ? e.id : clip.channel;
        if (_sessionSilenced(key)) moment = null;
      }
      // Turned down while a channel that ducks the others is speaking -- see
      // Ducking.
      if (moment != null && ducks.isNotEmpty) {
        var clip = switch (e) {
          AudioElement a => a.clip,
          VideoElement v => v.clip,
          _ => null,
        };
        var key = clip == null || clip.channel.isEmpty ? e.id : clip.channel;
        if (ducks[key] case var env?) {
          var run = (_runStartOf(e.id) + at!) / rate;
          moment = ClipMoment(
              moment.index, moment.time, moment.gain * envelopeAt(env, run));
        }
      }
      switch (e) {
        case VideoElement v:
          video.cue(v, moment, playing: going);
        case AudioElement a:
          audio.cue(a, moment, playing: going);
      }
    }
  }

  /// _duckEnvelopes is how far each channel is ducked over the run -- see
  /// duckEnvelopes -- worked out again only when the document has changed or
  /// a recording's shape has been read since.
  Map<String, List<GainPoint>> _duckEnvelopes() {
    if (identical(_duckFor, _document) && _duckWaves == _waveforms.length) {
      return _ducks;
    }
    _duckFor = _document;
    _duckWaves = _waveforms.length;
    _ducks = duckEnvelopes(_document, waveformOf);
    return _ducks;
  }

  CanvasDocument? _duckFor;
  int _duckWaves = -1;
  Map<String, List<GainPoint>> _ducks = const {};

  /// duckEnvelopeOf is how far channel [key] is ducked over the run, for the
  /// timeline to draw, or null where nothing ducks it.
  List<GainPoint>? duckEnvelopeOf(String key) => _duckEnvelopes()[key];

  /// _joinedCuts is the timeline's sounds as they are played: a sound cut in
  /// two, its halves still end to end on one channel, is played as the one
  /// sound it was. The second half is cued with nothing, and the first runs
  /// on through the join.
  ///
  /// Played as two, the first half stopped and the second started at the
  /// cut, and neither on the sample: the playhead moves a frame at a time,
  /// so the first ran a little past the cut -- into what the second then
  /// played again -- and the second started a little late. Heard as a skip
  /// in the middle of what had been one clip.
  ///
  /// Only where nothing would be lost by it: the same file, the second
  /// starting in it where the first stops and on the timeline where the
  /// first ends, no fade at the join, neither looping. The level is whichever
  /// half the playhead is in, so each half's volume line still holds.
  List<(CanvasElement, int?)> _joinedCuts(List<(CanvasElement, int)> items) {
    var rate = math.max(1, _document.frameRate);
    bool joins(AudioElement a, AudioElement b) {
      var x = a.clip, y = b.clip;
      if (x.channel.isEmpty || x.channel != y.channel) return false;
      if (x.playlist.length != 1 || y.playlist.length != 1) return false;
      if (x.loop != MediaLoop.none || y.loop != MediaLoop.none) return false;
      if (x.fadeOut > 0 || y.fadeIn > 0 || x.muted != y.muted) return false;
      var s = x.playlist.single, t = y.playlist.single;
      if (s.assetId != t.assetId || s.end <= 0) return false;
      if ((t.start - s.end).abs() > 0.002) return false;
      return (y.at - (x.at + s.span * rate)).abs() <= 1;
    }

    var out = <(CanvasElement, int?)>[];
    var sounds = <int, List<AudioElement>>{};
    for (var (e, at) in items) {
      if (e is AudioElement && e.clip.timed) {
        (sounds[at] ??= []).add(e);
      } else {
        out.add((e, at));
      }
    }
    for (var MapEntry(key: at, value: list) in sounds.entries) {
      list.sort((a, b) => a.clip.at.compareTo(b.clip.at));
      var used = <String>{};
      for (var (i, head) in list.indexed) {
        if (!used.add(head.id)) continue;
        var chain = [head];
        for (var next in list.skip(i + 1)) {
          if (used.contains(next.id) || !joins(chain.last, next)) continue;
          chain.add(next);
          used.add(next.id);
        }
        if (chain.length == 1) {
          out.add((head, at));
          continue;
        }
        var here = chain.lastWhere((c) => c.clip.at <= at, orElse: () => head);
        var whole = head.clip.copyWith(
          playlist: [
            head.clip.playlist.single
                .copyWith(end: chain.last.clip.playlist.single.end),
          ],
          fadeOut: chain.last.clip.fadeOut,
          volume: here.clip.volume,
        );
        out.add((head.copyWith(clip: whole), at));
        for (var rest in chain.skip(1)) {
          out.add((rest, null));
        }
      }
    }
    return out;
  }

  // ------------------------------------------------------------------------
  // The mixer
  // ------------------------------------------------------------------------

  /// solo is which channels are soloed. The session's rather than the
  /// document's: soloing is listening to one thing for a moment, and an
  /// export plays every channel that is not muted.
  Set<String> get solo => _solo;
  final Set<String> _solo = {};

  /// toggleSolo solos or unsolos a channel, by its key.
  void toggleSolo(String id) {
    if (!_solo.remove(id)) _solo.add(id);
    _applyMix();
    notifyListeners();
  }

  // ---- Automation: see automation.dart

  /// automationNow is where the lanes are read: the playhead, in seconds of
  /// its scene, between frames too while it plays.
  double get automationNow =>
      (_frame + betweenFrames) / math.max(1, _document.frameRate);

  /// overridden is what is held by hand on each channel, by its key:
  /// settings moved while their lanes played, left where the hand put them
  /// until backToArrangement, as Ableton does. The session's, not the
  /// document's: opened again, a canvas plays as it was written.
  Map<String, Set<String>> get overridden => _overridden;
  final Map<String, Set<String>> _overridden = {};

  /// anyOverridden is whether anything is held by hand: what lights Back to
  /// arrangement.
  bool get anyOverridden => _overridden.values.any((s) => s.isNotEmpty);

  /// backToArrangement hands every setting held by hand back to its lane.
  void backToArrangement() {
    if (!anyOverridden) return;
    _overridden.clear();
    _applyMix();
    notifyListeners();
  }

  /// automationArmed is the control bar's Arm automation: while it is on
  /// and the timeline plays, a setting moved by hand writes its lane --
  /// starting one, if it has none -- rather than being held.
  bool get automationArmed => _automationArmed;
  bool _automationArmed = false;
  set automationArmed(bool on) {
    if (on == _automationArmed) return;
    _automationArmed = on;
    notifyListeners();
  }

  /// automationShown is the channels whose lanes are open under them on
  /// the timeline, by key -- the reader's view, not the document's.
  Set<String> get automationShown => _automationShown;
  final Set<String> _automationShown = {};

  void toggleAutomation(String channel) {
    if (!_automationShown.remove(channel)) _automationShown.add(channel);
    notifyListeners();
  }

  /// automationRows are the lanes shown under [channel], each the setting
  /// it shows, as Ableton's are: views onto the channel's automation, so a
  /// lane hidden keeps its points and one switched to another setting
  /// shows that setting's. To start with, every setting with points -- or
  /// the volume, with none.
  List<String> automationRows(TimelineChannel channel) =>
      _automationRows[channel.key] ??= () {
        var laned = [
          for (var l in channel.mix.automation)
            if (l.points.isNotEmpty) l.target
        ];
        return laned.isEmpty ? [AutomationTarget.volume.id] : laned;
      }();
  final Map<String, List<String>> _automationRows = {};

  void showAutomationRow(TimelineChannel channel, int index, String target) {
    var rows = automationRows(channel);
    if (index < 0 || index >= rows.length) return;
    rows[index] = target;
    notifyListeners();
  }

  /// addAutomationRow shows another lane under [channel]: the first setting
  /// not shown yet that has points, else the first not shown at all.
  void addAutomationRow(TimelineChannel channel) {
    var rows = automationRows(channel);
    var all = [
      for (var t in automationTargets(channel.mix, _document.returns)) t.id
    ];
    var laned = {
      for (var l in channel.mix.automation)
        if (l.points.isNotEmpty) l.target
    };
    var next = all.where((t) => laned.contains(t) && !rows.contains(t)).firstOrNull ??
        all.where((t) => !rows.contains(t)).firstOrNull;
    if (next == null) return;
    rows.add(next);
    notifyListeners();
  }

  /// hideAutomationRow hides lane [index] under [channel]: its points are
  /// kept, and played. The last one hidden closes the lanes.
  void hideAutomationRow(TimelineChannel channel, int index) {
    var rows = automationRows(channel);
    if (index < 0 || index >= rows.length) return;
    rows.removeAt(index);
    if (rows.isEmpty) {
      _automationRows.remove(channel.key);
      _automationShown.remove(channel.key);
    }
    notifyListeners();
  }

  /// automationLaneOf is [channel]'s lane for [target], or null with none.
  AutomationLane? automationLaneOf(TimelineChannel channel, String target) =>
      channel.mix.automation.where((l) => l.target == target).firstOrNull;

  /// setAutomationPoints sets the points of [channel]'s lane for [target]:
  /// a lane made for the first, and taken away with the last.
  void setAutomationPoints(
      TimelineChannel channel, String target, List<AutomationPoint> points,
      {bool transient = false}) {
    var lanes = [
      for (var l in channel.mix.automation)
        if (l.target != target) l,
      if (points.isNotEmpty) AutomationLane(target).withPoints(points),
    ];
    setAutomation(channel, lanes, transient: transient);
  }

  /// mixNow is [channel]'s mix as it plays now: its own, with each lane's
  /// setting put in but for those held by hand. What its strip shows.
  ChannelMix mixNow(TimelineChannel channel) {
    var held = _overridden[channel.key] ?? const <String>{};
    return _withClipAutomation(channel.key,
        automatedAt(channel.mix, automationNow, except: held), held);
  }

  /// changeChannelMix writes [next] -- the mix as it was shown, [shown],
  /// changed by a hand -- to [channel]. Each setting the hand changed is
  /// the channel's own now; where a lane moves it, it is held by hand -- or,
  /// armed and playing, written into its lane where the playhead is. Every
  /// other setting stays the channel's own, not the lane's value that was
  /// shown for it.
  void changeChannelMix(
      TimelineChannel channel, ChannelMix shown, ChannelMix next,
      {bool transient = false,
      bool anywhere = false,
      List<AutomationLane>? automation}) {
    var own = automation == null
        ? channel.mix
        : channel.mix.copyWith(automation: automation);
    var writing = _automationArmed && playing;
    var launched = _clipChannels[channel.key]?.now;
    var clip = launched == null ? null : session.at(channel.key, launched.row);
    var clipLanes = clip?.automation ?? const <ClipAutomation>[];
    if (own.automation.isEmpty && clipLanes.isEmpty && !writing) {
      setChannelMix(channel, next, transient: transient, anywhere: anywhere);
      return;
    }
    var moved = <String>{};
    var gain = own.gainDb, balance = own.balance;
    if (next.gainDb != shown.gainDb) {
      gain = next.gainDb;
      moved.add(AutomationTarget.volume.id);
    }
    if (next.balance != shown.balance) {
      balance = next.balance;
      moved.add(AutomationTarget.pan.id);
    }
    var sends = {...own.sends};
    for (var id in {...shown.sends.keys, ...next.sends.keys}) {
      if (next.sends[id] == shown.sends[id]) continue;
      moved.add(AutomationTarget.sendTo(id).id);
      if (next.sends[id] case var db?) {
        sends[id] = db;
      } else {
        sends.remove(id);
      }
    }
    // The devices, setting by setting, while the chain is as it was; a
    // device put on or taken off is the chain the hand made.
    var devices = next.devices;
    if (next.devices.length == shown.devices.length &&
        own.devices.length == shown.devices.length) {
      devices = [
        for (var (i, d) in next.devices.indexed)
          if (d.kind != shown.devices[i].kind ||
              d.kind != own.devices[i].kind)
            d
          else
            _mergedDevice(i, own.devices[i], shown.devices[i], d, moved),
      ];
    } else if (shown.devices.length == own.devices.length &&
        next.devices.length == own.devices.length - 1) {
      // One taken out: the rest as the channel had them.
      var gone = 0;
      while (gone < next.devices.length &&
          next.devices[gone].kind == own.devices[gone].kind) {
        gone++;
      }
      devices = [...own.devices]..removeAt(gone);
    } else if (shown.devices.length == own.devices.length &&
        next.devices.length == own.devices.length + 1) {
      // One put on the end.
      devices = [...own.devices, next.devices.last];
    }
    var lanes = own.automation;
    if (writing) {
      var t = automationNow;
      var probe = next.copyWith(
          gainDb: gain, balance: balance, sends: sends, devices: devices);
      lanes = [
        for (var l in lanes)
          if (moved.contains(l.target))
            l.written(t, l.what!.own(probe))
          else
            l,
        // A setting with no lane yet starts one.
        for (var id in moved)
          if (!lanes.any((l) => l.target == id))
            AutomationLane(id, [(t, AutomationTarget.parse(id)!.own(probe))]),
      ];
    } else {
      // What a lane moves -- the timeline's, or the clip's playing.
      var laned = {
        for (var l in lanes)
          if (l.points.isNotEmpty) l.target,
        for (var a in clipLanes)
          if (a.points.isNotEmpty) a.target,
      };
      var held = moved.intersection(laned);
      if (held.isNotEmpty) (_overridden[channel.key] ??= {}).addAll(held);
    }
    setChannelMix(
        channel,
        next.copyWith(
            gainDb: gain,
            balance: balance,
            sends: sends,
            devices: devices,
            automation: lanes),
        transient: transient,
        anywhere: anywhere);
  }

  /// _lanesAfter is [lanes] once the chain [was] is [now]: a device taken
  /// out takes its lanes with it, and the lanes of the devices after it
  /// move up a place with them.
  List<AutomationLane> _lanesAfter(List<AutomationLane> lanes,
      List<MixDevice> was, List<MixDevice> now) {
    if (now.length != was.length - 1) return lanes;
    var gone = 0;
    while (gone < now.length && now[gone].kind == was[gone].kind) {
      gone++;
    }
    return [
      for (var l in lanes)
        if (l.what case var w? when w.kind == AutomationKind.device)
          if (w.device == gone)
            ...[]
          else if (w.device > gone)
            AutomationLane(
                AutomationTarget.deviceSetting(
                        w.device - 1, w.deviceKind!, w.param)
                    .id,
                l.points)
          else
            l
        else
          l,
    ];
  }

  /// _mergedDevice is device [i] as the hand left it: each setting it
  /// changed from what was [shown] taken from [next] -- and noted in
  /// [moved] -- the rest the channel's [own]; switched on or off as the
  /// hand left it.
  MixDevice _mergedDevice(int i, MixDevice own, MixDevice shown,
      MixDevice next, Set<String> moved) {
    var out = MixDevice(own.kind,
        on: next.on, values: own.values, source: next.source);
    for (var p in next.kind.params) {
      if (next.value(p.id) == shown.value(p.id)) continue;
      out = out.withValue(p.id, next.value(p.id));
      moved.add(AutomationTarget.deviceSetting(i, next.kind, p.id).id);
    }
    return out;
  }

  /// setAutomation sets [channel]'s lanes.
  void setAutomation(TimelineChannel channel, List<AutomationLane> lanes,
      {bool transient = false}) {
    // A lane with its points gone is no longer holding anything by hand.
    var targets = {
      for (var l in lanes)
        if (l.points.isNotEmpty) l.target
    };
    _overridden[channel.key]?.removeWhere((t) => !targets.contains(t));
    setChannelMix(channel, channel.mix.copyWith(automation: lanes),
        transient: transient);
  }

  /// setChannelMix changes one strip, as the Channels strip changes a clip --
  /// see setTimedClip.
  ///
  /// [anywhere] writes a clip's channel from wherever it is seen: a master
  /// clip picked from a scene is not editable on that scene's timeline, but
  /// its settings, opened on purpose, are its own.
  void setChannelMix(TimelineChannel channel, ChannelMix mix,
          {bool transient = false, bool anywhere = false}) =>
      _setClips([
        for (var lane in channel.lanes)
          if (lane.editable ||
              (anywhere && !lane.element.id.startsWith(transitionSoundPrefix)))
            (lane.element, lane.clip.copyWith(mix: mix)),
      ], transient: transient);

  void setMasterMix(MasterMix mix, {bool transient = false}) =>
      apply(_document.copyWith(masterMix: mix), transient: transient);

  /// returnOf is the return called [id], or null.
  ReturnChannel? returnOf(String? id) =>
      _document.returns.where((r) => r.id == id).firstOrNull;

  /// devicesOf is strip [key]'s devices -- a return's, or a channel's own --
  /// in order; empty for none, or for a strip that is neither.
  List<MixDevice> devicesOf(String key) {
    if (key == mixerMasterKey) return _document.masterMix.devices;
    if (returnOf(key) case var r?) return r.devices;
    // As they play now: a setting a lane moves, where the lane has it.
    var lane = timelineChannels.where((c) => c.key == key).firstOrNull;
    return lane == null ? const [] : mixNow(lane).devices;
  }

  /// setDevicesOf changes strip [key]'s devices.
  void setDevicesOf(String key, List<MixDevice> devices,
      {bool transient = false}) {
    if (key == mixerMasterKey) {
      setMasterMix(_document.masterMix.copyWith(devices: devices),
          transient: transient);
      return;
    }
    if (returnOf(key) case var r?) {
      setReturn(r.copyWith(devices: devices), transient: transient);
      return;
    }
    var lane = timelineChannels.where((c) => c.key == key).firstOrNull;
    if (lane == null) return;
    var shown = mixNow(lane);
    changeChannelMix(lane, shown, shown.copyWith(devices: devices),
        transient: transient,
        automation: _lanesAfter(lane.mix.automation, shown.devices, devices));
  }

  /// setReturn changes a return -- its name, its devices, its strip.
  void setReturn(ReturnChannel next, {bool transient = false}) => apply(
      _document.copyWith(returns: [
        for (var r in _document.returns) r.id == next.id ? next : r,
      ]),
      transient: transient);

  /// addReturn adds a return at the end, with a reverb on it -- the
  /// commonest reason for one -- and picks it.
  ReturnChannel? addReturn() {
    var returns = _document.returns;
    if (returns.length >= maxReturns) return null;
    var taken = {for (var r in returns) r.id};
    var n = returns.length;
    while (taken.contains("return${returnLetter(n)}")) {
      n++;
    }
    var made = ReturnChannel("return${returnLetter(n)}",
        name: "Reverb", devices: const [MixDevice(DeviceKind.reverb)]);
    apply(_document.copyWith(returns: [...returns, made]));
    pickStrip(made.id);
    return made;
  }

  /// removeReturn takes a return away. What was sent to it is sent nowhere:
  /// the sends are kept on the channels, so putting it back with undo finds
  /// them as they were.
  void removeReturn(String id) {
    apply(_document.copyWith(returns: [
      for (var r in _document.returns)
        if (r.id != id) r,
    ]));
    if (selectedChannel == id) selectedChannel = null;
    if (_effectsOf == id) _effectsOf = null;
  }

  /// levels is how loud a strip -- by its channel's key, or the master with
  /// none -- is coming out now, for the meters.
  (double, double) levels([String? channel]) =>
      _audio?.levels(channel) ?? (0, 0);

  /// spectrum is what a strip -- by its channel's key, or the master with
  /// none -- is playing now, for the EQ to draw. See AudioEngine.spectrum.
  Float32List? spectrum([String? channel]) => _audio?.spectrum(channel);

  /// pitch is what a tuner on strip [channel] hears now -- the master's
  /// with mixerMasterKey -- or null.
  PitchReading? pitch(String channel) =>
      _audio?.pitch(channel == mixerMasterKey ? null : channel);

  /// _heard opens the runtime, where it is not open yet, with the mixer
  /// already in it: a sound pressed on the canvas plays through its strip
  /// from its first note.
  void _heard() {
    audio;
    _applyMix();
  }

  /// _applyMix hands the runtime the mixer as it stands. Cheap when nothing
  /// has changed: the runtime compares before it calls the engine.
  void _applyMix() {
    var timed = timedLanes;
    // A sound pressed on the canvas opens the device when it is pressed --
    // see _heard -- not when the canvas holding it is opened.
    if (timed.isEmpty && _audio == null) return;
    var lanes = [...timed, ...interactiveLanes];
    // One strip per channel, every sound on it routed through it. The strip
    // is the channel's first sound's mix, which setChannelMix copies onto
    // every sound on the channel.
    // Each as it plays now: its lanes' settings put in, but for those held
    // by hand.
    var strips = <String, ChannelMix>{};
    var now = automationNow;
    for (var lane in lanes) {
      strips.putIfAbsent(lane.channelKey, () {
        var held = _overridden[lane.channelKey] ?? const <String>{};
        return _withClipAutomation(lane.channelKey,
            automatedAt(lane.clip.mix, now, except: held), held);
      });
    }
    audio.setMix(strips,
        routes: {for (var lane in lanes) lane.element.id: lane.channelKey},
        solo: {
          for (var key in _solo)
            if (strips.containsKey(key)) key,
        },
        master: _document.masterMix,
        returns: _document.returns,
        speakers: _document.audio.speakers,
        placements: placementsNow);
  }

  /// _withClipAutomation is [mix] with the envelopes of the clip playing on
  /// [channel] put in, over the timeline's lanes -- or as it was, with no
  /// clip playing or none with envelopes of the channel's settings.
  ChannelMix _withClipAutomation(
      String channel, ChannelMix mix, Set<String> held) {
    var play = _clipChannels[channel]?.now;
    if (play == null) return mix;
    var clip = session.at(channel, play.row);
    if (clip == null || clip.id != play.clipId || clip.automation.isEmpty) {
      return mix;
    }
    var beat = clipAt(channel);
    if (beat == null) return mix;
    var elapsed = (_sessionNow - play.origin) /
        math.max(0.001, _document.audio.secondsPerBeat);
    return clipAutomatedAt(mix, clip.automation, beat, elapsed, except: held);
  }

  /// placementsNow is where each placed sound's channel is heard from on
  /// this frame, by channel -- the first placed sound on a channel says,
  /// which is the only one on it unless channels have been shared.
  Map<String, Heard> get placementsNow {
    var out = <String, Heard>{};
    for (var lane in [...timedLanes, ...interactiveLanes]) {
      var place = lane.clip.place;
      if (place.isOff || out.containsKey(lane.channelKey)) continue;
      if (heardAt(_document, lane.element, place, _frame) case var h?) {
        out[lane.channelKey] = h;
      }
    }
    return out;
  }

  /// _autoplayAudio starts the sounds on screen that start by themselves.
  void _autoplayAudio() {
    var starting = [
      for (var e in _pageAudio)
        if (e.clip.autoplay && !e.clip.isEmpty && !e.clip.timed) e,
    ];
    if (starting.isNotEmpty) {
      _heard();
      audio.autoplay(starting);
    }

    var videos = [
      for (var e in [
        ..._document.elements,
        if (!_document.editingMaster) ...?_document.masterScene?.elements,
      ])
        if (e is VideoElement &&
            e.clip.autoplay &&
            !e.clip.isEmpty &&
            !e.clip.timed)
          e,
    ];

    // And the backdrop's, which is where a looping video or a music bed
    // usually is.
    for (var e in _document.drawnBackground.media) {
      switch (e) {
        case VideoElement v when v.clip.autoplay && !v.clip.timed:
          videos.add(v);
        case AudioElement a when a.clip.autoplay && !a.clip.timed:
          audio.autoplay([a]);
      }
    }
    if (videos.isNotEmpty) {
      _heard();
      video.autoplay(videos);
    }
  }

  // ------------------------------------------------------------------------
  // Keyframes
  // ------------------------------------------------------------------------

  /// setKeyframe writes the pose at the current frame for one element.
  void setKeyframe(String id, Keyframe key) {
    var element = _document.elementById(id);
    if (element == null) return;
    // Whatever that frame already pinned is kept. A keyframe holds the pose
    // *and* any channels -- a counter's number, a chart's arrival -- and
    // writing a pose over one wholesale threw the channels away: keying the
    // position on the frame a count starts took the count with it.
    var was = element.track?.keyAt(key.frame);
    var merged = was == null || was.values.isEmpty
        ? key
        : key.copyWith(values: {...was.values, ...key.values});
    var track = (element.track ?? ElementTrack.empty).withKey(merged);
    replaceElement(element.withBase(track: track));
  }

  /// applyChartAnimation puts a preset on a chart and lays the two keyframes
  /// that give it a length.
  ///
  /// One gesture, because it is one decision. A preset with no keyframes draws
  /// nothing different -- the reveal channel would never be pinned, so the
  /// chart would sit at "all of it" for every frame -- and asking somebody to
  /// choose a preset and then separately key a channel they have never heard
  /// of is asking them to know how this is implemented.
  ///
  /// The keyframes are ordinary ones. That is the point: the length of the
  /// animation is the gap between them on the timeline, dragged like anything
  /// else, rather than a duration stored on the chart where the timeline could
  /// not see it.
  ///
  /// A still document is given a second's worth of frames first. An animation
  /// on a one-frame canvas is an animation nobody can watch.
  /// [length] is how many frames it takes, and overrules everything else.
  /// Left out, the length comes from the animation's own Length setting where
  /// one has been asked for, and otherwise from wherever the keyframes already
  /// are -- so trying one preset after another to see how they look leaves the
  /// timing alone instead of resetting it every time. See
  /// applyTextAnimation, whose rules these now are.
  void applyChartAnimation(ChartElement element, ChartAnimationPreset preset,
      {int? length}) {
    beginInteraction();

    if (preset == ChartAnimationPreset.none) {
      // The reveal keyframes go with it and nothing else does. Clearing the
      // whole track took the chart's *pose* with it: a chart that had been
      // moved or faded by hand lost all of that for choosing None on a
      // dropdown, which is not what the word means.
      var without = _without(element.track, KeyframeChannel.reveal);
      replaceElement(element
          .copyWith(animation: element.animation.copyWith(preset: preset))
          .withBase(track: without, clearTrack: without == null));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds));
    }

    // Where it already is, if it is anywhere. From this frame otherwise, so a
    // chart animated while scrubbed to the middle starts where the reader is
    // looking rather than jumping the playhead.
    var (was, wasFor) = elementAnimationSpan(element);
    var from = was ?? _frame.clamp(0, document.frames - 2);
    var span = wasFor ??
        length ??
        (element.animation.length > 0
            ? element.animation.length
            : defaultAnimationFrames);
    span = math.max(1, span);
    if (document.frames - 1 < from + span) {
      document = document.copyWith(frames: from + span + 1);
    }
    var to = from + span;
    if (to <= from) {
      from = 0;
      to = document.frames - 1;
    }

    var track = element.track ?? ElementTrack.empty;
    for (var key in track.keys) {
      if (key.values.containsKey(KeyframeChannel.reveal)) {
        track = track.withoutFrame(key.frame);
      }
    }
    track = _pinning(_pinning(track, from, KeyframeChannel.reveal, 0), to,
        KeyframeChannel.reveal, 1);

    var next = element
        .copyWith(animation: element.animation.copyWith(preset: preset))
        .withBase(track: track);
    apply(document.withElement(next));
    endInteraction();
  }

  /// applyTextAnimation puts a preset on a text element and lays the two
  /// keyframes that give it a length.
  ///
  /// The chart's function with a different element, and deliberately so: the
  /// two animations use the same channels, the same stagger and the same
  /// timeline, so a canvas with a headline and a chart arriving together has
  /// them arriving together. See applyChartAnimation, which this mirrors line
  /// for line -- including the reason the keyframes are ordinary ones.
  /// [length] is how many frames it takes, and overrules everything else:
  /// zero means the usual two seconds, and it is what the Length setting
  /// passes.
  ///
  /// Left out, the length comes from the animation's own Length setting where
  /// one has been asked for, and otherwise from wherever the keyframes
  /// already are -- so trying one preset after another to see how they look
  /// leaves the timing alone instead of resetting it every time.
  void applyTextAnimation(TextElement element, TextAnimationPreset preset,
      {int? length}) {
    beginInteraction();

    if (preset == TextAnimationPreset.none) {
      var without = _without(element.track, KeyframeChannel.reveal);
      replaceElement(element
          .copyWith(animation: element.animation.copyWith(preset: preset))
          .withBase(track: without, clearTrack: without == null));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds));
    }

    // Where it already is, if it is anywhere: choosing a different preset
    // keeps the length that has been set rather than resetting it to the
    // default, which would undo the last thing somebody did every time they
    // tried the next preset in the list.
    var (was, wasFor) = textAnimationSpan(element);
    var from = was ?? _frame.clamp(0, document.frames - 2);
    // Whatever is already on the timeline wins: once an animation has been
    // laid down, its keyframes are where somebody has put them, and trying
    // the next preset in the list must not shove them about. The Length
    // setting is for laying a *new* one down -- which, after the keyframes
    // have been deleted, is what the next preset is.
    var span = wasFor ??
        length ??
        (element.animation.length > 0
            ? element.animation.length
            : defaultAnimationFrames);
    span = math.max(1, span == 0 ? defaultAnimationFrames : span);
    if (document.frames - 1 < from + span) {
      document = document.copyWith(frames: from + span + 1);
    }
    var to = from + span;
    if (to <= from) {
      from = 0;
      to = document.frames - 1;
    }

    var track = (element.track ?? ElementTrack.empty);
    for (var key in track.keys) {
      if (key.values.containsKey(KeyframeChannel.reveal)) {
        track = track.withoutFrame(key.frame);
      }
    }
    track = _pinning(_pinning(track, from, KeyframeChannel.reveal, 0), to,
        KeyframeChannel.reveal, 1);

    apply(document.withElement(element
        .copyWith(
            animation: element.animation.copyWith(
                preset: preset,
                // The curve the preset was designed around, and the way it
                // cuts where it cuts -- and only where the preset is actually
                // changing: re-laying the keyframes for some other reason
                // must not quietly undo numbers somebody chose. See
                // TextAnimationPreset.wants and its effect.
                ease: preset == element.animation.preset ? null : preset.wants,
                effect:
                    preset == element.animation.preset ? null : preset.effect))
        .withBase(track: track)));
    endInteraction();
  }

  /// textAnimationSpan is where [element]'s arrival sits on the timeline: the
  /// frame it starts on and how many frames it takes, or nulls where it has
  /// no keyframes yet.
  ///
  /// Read from the keyframes rather than kept on the animation, because the
  /// keyframes are the truth -- they can be dragged on the timeline, and a
  /// number stored beside them would be a second answer that goes stale the
  /// first time somebody does.
  (int?, int?) textAnimationSpan(TextElement element) {
    int? from;
    int? to;
    for (var key in element.track?.keys ?? const <Keyframe>[]) {
      if (!key.values.containsKey(KeyframeChannel.reveal)) continue;
      from = from == null ? key.frame : math.min(from, key.frame);
      to = to == null ? key.frame : math.max(to, key.frame);
    }
    if (from == null || to == null || to <= from) return (from, null);
    return (from, to - from);
  }

  /// defaultAnimationFrames is how long an animation runs for when nobody
  /// has said: the same two seconds a chart's uses.
  int get defaultAnimationFrames =>
      math.max(2, (_document.frameRate * chartAnimationSeconds).round());

  /// elementAnimationOf is [element]'s own arrival, for the kinds that have
  /// one, or an empty animation for the kinds that do not.
  ///
  /// A switch rather than an interface on CanvasElement: two kinds have this
  /// and nine do not, and a getter on the base class would be a promise that
  /// every element can be animated this way -- which a line, a background or
  /// a chart cannot, each for its own reason.
  /// elementLoopOf is [element]'s loop, whatever kind of element: the words'
  /// and a chart's are in animations of their own.
  static ElementLoop elementLoopOf(CanvasElement element) => switch (element) {
        TextElement e => e.animation.loop,
        ChartElement e => e.animation.loop,
        _ => elementAnimationOf(element).loop,
      };

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
        CharacterElement e => e.animation,
        _ => const ElementAnimation(),
      };

  /// animates is whether [element] is one of the kinds this applies to.
  ///
  /// Not a chart, which has an animation of its own that knows what a bar and
  /// a slice are -- see applyChartAnimation -- and not a text element, whose
  /// presets are scoped to words and letters. Everything else on the canvas
  /// is a thing in a box, and a thing in a box arrives the same way.
  /// loops is whether [element] can loop: everything that animates, and the
  /// words and charts, whose animations are their own.
  static bool loops(CanvasElement element) =>
      animates(element) || element is TextElement || element is ChartElement;

  static bool animates(CanvasElement element) =>
      element is ShapeElement ||
      element is ImageElement ||
      element is VectorElement ||
      element is LineElement ||
      element is PathElement ||
      element is TableElement ||
      // A counter is a thing in a box like the rest of them: it arrives and
      // leaves the same way, whatever its number is doing while it is there.
      element is CounterElement ||
      // And a button. Arriving is not pressing: one is what the canvas does
      // to it, the other what somebody does to the canvas.
      element is ButtonElement ||
      element is AudioElement ||
      element is VideoElement ||
      element is CharacterElement;

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
        CharacterElement e => e.copyWith(animation: animation),
        _ => element,
      };

  /// setElementLoop gives [element] [loop] -- [transient] while a drag on
  /// its bar is still making it. See ElementLoop.
  void setElementLoop(CanvasElement element, ElementLoop loop,
      {bool transient = false}) {
    // Words and charts keep theirs in animations of their own.
    if (element is TextElement) {
      replaceElement(
          element.copyWith(animation: element.animation.copyWith(loop: loop)),
          transient: transient);
      return;
    }
    if (element is ChartElement) {
      replaceElement(
          element.copyWith(animation: element.animation.copyWith(loop: loop)),
          transient: transient);
      return;
    }
    if (!animates(element)) return;
    var was = elementAnimationOf(element);
    replaceElement(_withElementAnimation(element, was.copyWith(loop: loop)),
        transient: transient);
  }

  /// applyElementAnimation puts an arrival on a shape or a picture and lays
  /// the pair of keyframes that runs it.
  ///
  /// The text element's [applyTextAnimation], for the kinds that have no
  /// words -- deliberately the same rules, because they are the same
  /// keyframes on the same timeline: whatever is already laid down wins, the
  /// Length setting is for laying a new one down, and choosing None takes the
  /// keyframes away with it.
  void applyElementAnimation(
      CanvasElement element, ElementAnimationPreset preset,
      {int? length}) {
    if (!animates(element)) return;
    beginInteraction();
    var was = elementAnimationOf(element);

    if (preset == ElementAnimationPreset.none) {
      var without = _without(element.track, KeyframeChannel.reveal);
      replaceElement(
          _withElementAnimation(element, was.copyWith(preset: preset))
              .withBase(track: without, clearTrack: without == null));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds));
    }

    var (wasAt, wasFor) = elementAnimationSpan(element);
    var from = wasAt ?? _frame.clamp(0, document.frames - 2);
    var span = wasFor ??
        length ??
        (was.length > 0 ? was.length : defaultAnimationFrames);
    span = math.max(1, span == 0 ? defaultAnimationFrames : span);
    if (document.frames - 1 < from + span) {
      document = document.copyWith(frames: from + span + 1);
    }
    var to = from + span;
    if (to <= from) {
      from = 0;
      to = document.frames - 1;
    }

    var track = element.track ?? ElementTrack.empty;
    for (var key in track.keys) {
      if (key.values.containsKey(KeyframeChannel.reveal)) {
        track = track.withoutFrame(key.frame);
      }
    }
    track = _pinning(_pinning(track, from, KeyframeChannel.reveal, 0), to,
        KeyframeChannel.reveal, 1);

    // The preset's own curve and its own way of cutting, and only where the
    // preset is actually changing -- re-laying the keyframes for some other
    // reason must not quietly undo numbers somebody has set. Build up and
    // Break apart are the same motion and differ only in these, so a preset
    // that did not carry them would be a name with nothing behind it.
    var changing = preset != was.preset;
    apply(document.withElement(_withElementAnimation(
            element,
            was.copyWith(
                preset: preset,
                ease: changing ? preset.wants : null,
                effect: changing ? preset.effect : null))
        .withBase(track: track)));
    endInteraction();
  }

  /// elementAnimationSpan is where [element]'s arrival sits on the timeline:
  /// the frame it starts on and how many frames it takes. See
  /// textAnimationSpan, which reads the same channel for the same reasons.
  (int?, int?) elementAnimationSpan(CanvasElement element) {
    int? from;
    int? to;
    for (var key in element.track?.keys ?? const <Keyframe>[]) {
      if (!key.values.containsKey(KeyframeChannel.reveal)) continue;
      from = from == null ? key.frame : math.min(from, key.frame);
      to = to == null ? key.frame : math.max(to, key.frame);
    }
    if (from == null || to == null || to <= from) return (from, null);
    return (from, to - from);
  }

  /// anchorShown is whether [id]'s anchor point is drawn on the stage, where
  /// it can be dragged unless it is locked. A way of looking rather than
  /// part of the design: not saved, and not undone.
  bool anchorShown(String id) => _anchorsShown.contains(id);
  final Set<String> _anchorsShown = {};

  void showAnchor(String id, bool shown) {
    if (shown ? !_anchorsShown.add(id) : !_anchorsShown.remove(id)) return;
    notifyListeners();
  }

  /// setElementArrivalTiming moves [element]'s arrival on the timeline: to
  /// start [delay] frames into the scene, and to take [length] frames --
  /// either or both, the other left where it is. The scene grows to hold it.
  /// Part of whatever change is under way: the caller begins and ends it.
  void setElementArrivalTiming(CanvasElement element,
      {int? delay, int? length}) {
    var (at, span) = elementAnimationSpan(element);
    if (at == null || span == null) return;
    var from = math.max(0, delay ?? at);
    var took = math.max(1, length ?? span);
    if (from == at && took == span) return;
    var track =
        _without(element.track, KeyframeChannel.reveal) ?? ElementTrack.empty;
    track = _pinning(_pinning(track, from, KeyframeChannel.reveal, 0),
        from + took, KeyframeChannel.reveal, 1);
    var document = _document;
    if (from + took > document.frames - 1) {
      document = document.copyWith(frames: from + took + 1);
    }
    var next = element.withBase(track: track);
    // And what the next one is laid down with, so that trying another
    // preset keeps the length that was typed.
    if (length != null) {
      next = switch (next) {
        TextElement t =>
          t.copyWith(animation: t.animation.copyWith(length: took)),
        ChartElement c =>
          c.copyWith(animation: c.animation.copyWith(length: took)),
        _ => _withElementAnimation(
            next, elementAnimationOf(element).copyWith(length: took)),
      };
    }
    apply(document.withElement(next), transient: true);
  }

  /// previewSpanOf is the stretch of the scene a Preview of [element] plays:
  /// its arrival, its way out, and its loops -- its own and, for a drawing,
  /// its shapes' -- twice round, with a moment after. Two seconds from the
  /// start where it has none of them.
  (int, int) previewSpanOf(CanvasElement element) {
    var last = math.max(0, _document.frames - 1);
    var rate = math.max(1, _document.frameRate);
    int? start, end;
    void take(int a, int b) {
      start = math.min(start ?? a, a);
      end = math.max(end ?? b, b);
    }

    var (at, span) = elementAnimationSpan(element);
    if (at != null && span != null) take(at, at + span);
    int? closeFrom, closeTo;
    for (var key in element.track?.keys ?? const <Keyframe>[]) {
      if (!key.values.containsKey(KeyframeChannel.close)) continue;
      closeFrom = math.min(closeFrom ?? key.frame, key.frame);
      closeTo = math.max(closeTo ?? key.frame, key.frame);
    }
    if (closeFrom != null && closeTo != null) take(closeFrom, closeTo);
    var arrived = arrivalEnd(element);
    var loops = [
      elementLoopOf(element),
      if (element is VectorElement)
        for (var d in vectorDrawn(element.shapes ?? const []))
          if (d.style.animation case var own?
              when d.style.owns.contains(ShapeAnimationPart.looping))
            own.loop,
    ];
    for (var loop in loops) {
      if (!loop.on) continue;
      var (from, to) = loop.span(arrived: arrived, last: last);
      take(from, math.min(to, from + 2 * (loop.cycle + loop.gap) - loop.gap));
    }
    var a = start ?? 0;
    var b = end ?? a + rate * 2;
    b = math.min(last, b + (rate * 0.3).round());
    if (b <= a) b = math.min(last, a + 1);
    return (math.min(a, last), b);
  }

  /// previewing is the one element being previewed and the frame it is at, while
  /// a Preview plays: that element runs through its animation and everything
  /// else stays as it is at the playhead, which does not move. See
  /// previewElement.
  ({String id, int frame})? get previewing => _previewing;
  ({String id, int frame})? _previewing;
  int _previewingEnd = 0;

  /// previewElement plays [id]'s animation, and nothing else's, once. See
  /// previewing. Anything else playing stops first; pausing stops it.
  void previewElement(String id) {
    var element = _document.elementById(id);
    if (element == null) return;
    pause();
    stopPreview();
    var (from, to) = previewSpanOf(element);
    _previewing = (id: id, frame: from);
    _previewingEnd = to;
    _startTimer();
    notifyListeners();
  }

  /// applyElementExit is the way out for a shape or a picture, on its own
  /// pair of keyframes at the end of the timeline. See applyTextExit.
  void applyElementExit(CanvasElement element, ElementAnimationPreset preset) {
    if (!animates(element)) return;
    beginInteraction();
    var was = elementAnimationOf(element);

    var track = element.track ?? ElementTrack.empty;
    if (preset == ElementAnimationPreset.none) {
      var without = _without(track, KeyframeChannel.close);
      replaceElement(_withElementAnimation(element, was.copyWith(exit: preset))
          .withBase(track: without, clearTrack: without == null));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds * 2));
    }

    int? wasFrom;
    int? wasTo;
    for (var key in track.keys) {
      if (!key.values.containsKey(KeyframeChannel.close)) continue;
      wasFrom = wasFrom == null ? key.frame : math.min(wasFrom, key.frame);
      wasTo = wasTo == null ? key.frame : math.max(wasTo, key.frame);
    }

    var span = was.length > 0 ? was.length : defaultAnimationFrames;
    var to = wasTo ?? document.frames - 1;
    var entranceEnds = _afterEntrance(track);
    var from = wasFrom != null && wasTo != null && wasTo > wasFrom
        ? wasFrom
        : math.max(entranceEnds + 1, to - span);
    if (from >= to) from = math.max(0, to - 1);

    track = _withClosingBand(track, from, to);

    apply(document.withElement(
        _withElementAnimation(element, was.copyWith(exit: preset))
            .withBase(track: track)));
    endInteraction();
  }

  /// applyTextExit is the way out, on its own pair of keyframes at the end of
  /// the timeline. See applyChartExit.
  void applyTextExit(TextElement element, TextAnimationPreset preset) {
    beginInteraction();

    var track = element.track ?? ElementTrack.empty;
    if (preset == TextAnimationPreset.none) {
      var without = _without(track, KeyframeChannel.close);
      replaceElement(element
          .copyWith(animation: element.animation.copyWith(exit: preset))
          .withBase(track: without, clearTrack: without == null));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds * 2));
    }

    // Where the exit already is, if it is anywhere -- the same rule the
    // arrival follows: an exit that has been laid down and dragged stays
    // where it was put, however many presets are tried in it.
    int? wasFrom;
    int? wasTo;
    for (var key in track.keys) {
      if (!key.values.containsKey(KeyframeChannel.close)) continue;
      wasFrom = wasFrom == null ? key.frame : math.min(wasFrom, key.frame);
      wasTo = wasTo == null ? key.frame : math.max(wasTo, key.frame);
    }

    var span = element.animation.length > 0
        ? element.animation.length
        : defaultAnimationFrames;
    var to = wasTo ?? document.frames - 1;
    var entranceEnds = _afterEntrance(track);
    var from = wasFrom != null && wasTo != null && wasTo > wasFrom
        ? wasFrom
        : math.max(entranceEnds + 1, to - span);
    if (from >= to) from = math.max(0, to - 1);

    track = _withClosingBand(track, from, to);

    apply(document.withElement(element
        .copyWith(animation: element.animation.copyWith(exit: preset))
        .withBase(track: track)));
    endInteraction();
  }

  /// applyChartExit puts a closing preset on a chart and lays the pair of
  /// keyframes that runs it.
  ///
  /// At the end of the timeline rather than at the playhead, which is where
  /// the entrance is laid: a closing animation is the thing that happens
  /// last, and a chart that faded out in the middle and stayed gone is not
  /// what anybody choosing one is asking for. It is two ordinary keyframes,
  /// dragged like the others -- see [applyChartAnimation], which lays the
  /// other pair for the same reasons.
  ///
  /// It never starts before the entrance has finished. Overlapping the two
  /// bands would have a chart arriving and leaving at once, which draws as a
  /// stutter and reads as a bug.
  void applyChartExit(ChartElement element, ChartAnimationPreset preset) {
    beginInteraction();

    var track = element.track ?? ElementTrack.empty;
    if (preset == ChartAnimationPreset.none) {
      // The keys go with it. A chart with no closing animation and a pair of
      // close keyframes still on its track would be pinned at "gone" for the
      // end of the timeline.
      var without = _without(track, KeyframeChannel.close);
      replaceElement(element
          .copyWith(animation: element.animation.copyWith(exit: preset))
          .withBase(track: without, clearTrack: without == null));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds * 2));
    }

    var span = element.animation.length > 0
        ? element.animation.length
        : defaultAnimationFrames;
    var to = document.frames - 1;
    // Clear of the entrance, which is whatever the reveal channel already
    // reaches.
    var entranceEnds = _afterEntrance(track);
    var from = math.max(entranceEnds + 1, to - span);
    if (from >= to) from = math.max(0, to - 1);

    track = _withClosingBand(track, from, to);

    apply(document.withElement(element
        .copyWith(animation: element.animation.copyWith(exit: preset))
        .withBase(track: track)));
    endInteraction();
  }

  /// shiftKeyframes moves a whole band of keyframes by [delta] frames.
  ///
  /// The two ends of an animation are one thing, so the timeline drags them
  /// as one -- see KeyframeBand. Refused rather than clamped when either end
  /// would run off the timeline: sliding a band into the end of the canvas
  /// and having it silently squash is worse than it stopping.
  void shiftKeyframes(String id, List<int> frames, int delta) {
    if (delta == 0 || frames.isEmpty) return;
    var element = _document.elementById(id);
    var track = element?.track;
    if (element == null || track == null) return;

    var moving = [
      for (var frame in frames)
        if (track.keyAt(frame) != null) track.keyAt(frame)!,
    ];
    if (moving.length != frames.length) return;
    for (var key in moving) {
      var at = key.frame + delta;
      if (at < 0 || at > _document.frames - 1) return;
    }

    var next = track;
    for (var key in moving) {
      next = next.withoutFrame(key.frame);
    }
    for (var key in moving) {
      next = next.withKey(key.copyWith(frame: key.frame + delta));
    }
    replaceElement(element.withBase(track: next));
  }

  /// removeKeyframe drops the pose at [frame], and drops the track entirely
  /// when it was the last one -- so an element with no animation left carries
  /// no empty track into the saved file.
  void removeKeyframe(String id, int frame) {
    var element = _document.elementById(id);
    var track = element?.track;
    if (element == null || track == null) return;

    replaceElement(withoutHalfAnimations(element, track.withoutFrame(frame)));
  }

  /// setKeyframeEasing writes how the element travels *out* of a keyframe.
  ///
  /// Easing belongs to the keyframe it leaves, which is why this is here and
  /// not on the animation: one arrival can be laid down and then eased, and a
  /// run of keyframes copied and pasted keeps whatever easing each of them
  /// had.
  ///
  /// [all] sets every keyframe on the element at once, and [channel] narrows
  /// that to the keyframes carrying one thing -- a counter's number, say --
  /// so setting the count's easing does not restyle a move somebody laid by
  /// hand on the same element.
  void setKeyframeEasing(
    CanvasElement element,
    KeyframeEasing easing, {
    bool all = false,
    String? channel,
  }) {
    var track = element.track;
    if (track == null) return;
    var next = track;
    for (var key in track.keys) {
      if (!all && key.frame != _frame) continue;
      if (channel != null && !key.values.containsKey(channel)) continue;
      next = next.withKey(key.copyWith(easing: easing));
    }
    if (identical(next, track)) return;
    replaceElement(element.withBase(track: next));
  }

  /// clearPose takes the *pose* off one frame and leaves whatever else that
  /// keyframe pinned.
  ///
  /// What the position-size-angle-fade diamond does, as against deleting the
  /// keyframe: one keyframe holds the pose and the channels together, so
  /// pressing a diamond labelled "position, size, angle and fade" took a
  /// counter's number and a chart's arrival away with them. Deleting the
  /// keyframe itself still deletes all of it -- an animation is a pair, and a
  /// deliberate delete on the timeline means the whole mark.
  void clearPose(String id, int frame) {
    var element = _document.elementById(id);
    var track = element?.track;
    if (element == null || track == null) return;
    var here = track.keyAt(frame);
    if (here == null) return;
    if (here.values.isEmpty) {
      removeKeyframe(id, frame);
      return;
    }
    replaceElement(element.withBase(
        track: track.withKey(Keyframe(frame: frame, values: here.values))));
  }

  /// withoutHalfAnimations takes away any arrival or exit that has lost one
  /// of its two keyframes, and turns the setting off with it.
  ///
  /// An animation is a *pair*: nothing to travel between is not half an
  /// arrival, it is none of one. Left alone, deleting one keyframe left the
  /// other sitting on the timeline, the preset still chosen in the panel, and
  /// nothing to show for either -- and the next preset chosen would then be
  /// laid out against the orphan. Deleting one of them is how somebody says
  /// they are done with it, so the setting goes back to None and the whole
  /// thing is there to be added again.
  CanvasElement withoutHalfAnimations(
      CanvasElement element, ElementTrack next) {
    var lost = <String>{};
    for (var channel in [KeyframeChannel.reveal, KeyframeChannel.close]) {
      var count = 0;
      for (var key in next.keys) {
        if (key.values.containsKey(channel)) count++;
      }
      if (count > 0 && count < 2) lost.add(channel);
    }

    for (var channel in lost) {
      for (var key in next.keys) {
        if (!key.values.containsKey(channel)) continue;
        var without = key.withoutValue(channel);
        next = without.isRest && without.frame != 0
            ? next.withoutFrame(key.frame)
            : next.withKey(without);
      }
    }

    var out = element;
    if (out is TextElement) {
      out = out.copyWith(
          animation: out.animation.copyWith(
        preset: lost.contains(KeyframeChannel.reveal)
            ? TextAnimationPreset.none
            : null,
        exit: lost.contains(KeyframeChannel.close)
            ? TextAnimationPreset.none
            : null,
      ));
    } else if (out is ChartElement) {
      out = out.copyWith(
          animation: out.animation.copyWith(
        preset: lost.contains(KeyframeChannel.reveal)
            ? ChartAnimationPreset.none
            : null,
        exit: lost.contains(KeyframeChannel.close)
            ? ChartAnimationPreset.none
            : null,
      ));
    }

    return next.isEmpty
        ? out.withBase(clearTrack: true)
        : out.withBase(track: next);
  }

  // ------------------------------------------------------------------------
  // Loading and saving
  // ------------------------------------------------------------------------

  /// load replaces the whole session with a document from disk.
  void load(CanvasDocument document, {String? folder, String? name}) {
    pause();
    stopAudio();
    // The empty channels "Add audio" used to leave: a sound with nothing in
    // it, on the canvas as an element. A channel now is only its sounds --
    // or an empty channel made on purpose, from the mixer: named, with its
    // effects or its Speech device, or clips in its slots. Those stay:
    // taken away, a channel's slots and its mix went with it.
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
    _selectedSlot = null;
    _selection = {};
    _backgroundSelected = false;
    _focusedPlayer = null;
    // Opened on the frame everything has arrived by, rather than on nought.
    //
    // A canvas whose elements arrive shows none of them on its first frame,
    // and an empty page reads as a document that has failed to load rather
    // than one that is about to play. Nought for a canvas with no arrivals,
    // which is the same thing said the other way.
    _frame = document.settledFrame;
    _undo.clear();
    _redo.clear();
    _interaction = null;
    _dirty = false;
    // The zoom and the pan go, because both are a position inside the document
    // being replaced and mean nothing in the new one.
    //
    // The fit stays. It is a fact about the reader's screen rather than about
    // any document -- the whole frame on a monitor, the width on a laptop --
    // so resetting it here made "remember how I like the canvas framed" a
    // setting that lasted until the next time a canvas was opened, which is
    // the moment it was most wanted.
    _zoom = 1;
    _pan = const Offset2(0, 0);
    // A piece of sound opens on what it is made with.
    if (document.kind.isAudio) _openSoundDesk();
    notifyListeners();
    unawaited(_repairSlots());
  }

  /// _repairSlots makes again the reversed sounds the clip slots lost: an
  /// earlier tidy of the library deleted every sound only a slot used --
  /// see SessionClip.mediaIds -- and a reversed clip came back silent. Its
  /// original is kept, and is turned round again.
  Future<void> _repairSlots() async {
    for (var (_, _, clip) in [...session.clips]) {
      var sound = clip.sound, original = clip.reversedOf;
      if (sound == null || original == null || _disposed) continue;
      if (await CanvasMedia.existingPath(MediaKind.audio, sound.assetId) !=
          null) {
        continue;
      }
      if (await CanvasMedia.existingPath(MediaKind.audio, original.assetId) ==
          null) {
        continue;
      }
      var audio = await clipAudio(original.assetId);
      if (audio == null || _disposed) continue;
      var id = await _keepSound(await _reversedWavAway(audio.$1, audio.$2));
      if (id == null || _disposed) continue;
      // Not a change to undo: the clip is as it was, its file made again.
      if (session.find(clip.id) case (var ch, var row)?) {
        var now = session.at(ch, row)!;
        apply(
            _document.copyWith(
                session: session.put(ch, row,
                    now.copyWith(sound: now.sound!.copyWith(assetId: id)))),
            transient: true);
      }
    }
  }

  /// _openSoundDesk opens the mixer and the effects: what an audio document
  /// is worked on with, there being no canvas to look at.
  void _openSoundDesk() {
    _mixerOpen = true;
    _effectsOpen = true;
  }

  /// _autosave is the pending write, if any.
  Timer? _autosave;

  /// _autosaveDelay is how long the editing has to stop for.
  ///
  /// Long enough that dragging a player across a pitch is one write rather
  /// than sixty, short enough that walking away from the machine mid-thought
  /// does not lose the thought.
  static const Duration _autosaveDelay = Duration(seconds: 3);

  /// scheduleAutosave writes the document out shortly, once the editing stops.
  ///
  /// Only for a document that has been saved at least once, which is the whole
  /// rule: until then there is nowhere to write to, and inventing a filename
  /// would put documents in the library that the reader never asked to keep.
  /// Somebody who opens a preset, plays with it and navigates away should find
  /// nothing new in their files.
  ///
  /// Debounced rather than throttled: each edit pushes the write further out,
  /// so a burst of edits costs one write at the end instead of one every few
  /// seconds throughout.
  void scheduleAutosave() {
    if (name == null || !_dirty) return;
    _autosave?.cancel();
    _autosave = Timer(_autosaveDelay, () {
      _autosave = null;
      if (name != null && _dirty) save();
    });
  }

  /// _toSave is the document as it is written out: as it is, except that a
  /// drawing still being edited is written with its box fitted round it, as
  /// leaving the editing would fit it. Left alone in the editor -- the box
  /// moving under a drawing while it is drawn would move the pencil's
  /// mirror lines with it -- but a document closed mid-edit must not come
  /// back with a box that cuts through the drawing. See _fitEditedVector.
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
    var ok = await CanvasStorage.save(f ?? "", n, _toSave);
    // Not awaited: tidying the stores is bookkeeping, and a save should not
    // wait on a walk of the whole library to report that it worked. Only what
    // is not an asset goes -- see CanvasLibrary.tidy.
    if (ok) {
      unawaited(CanvasLibrary.tidy(
          open: {..._document.assetIds, ..._document.mediaIds}));
    }
    if (ok) {
      _dirty = false;
      notifyListeners();
    }
    return ok;
  }

  /// saveAs writes to a new place and makes it this document's home.
  Future<bool> saveAs(String folder, String name) async {
    var ok =
        await CanvasStorage.save(folder, name, _toSave.copyWith(title: name));
    if (!ok) return false;
    this.folder = folder;
    this.name = name;
    _document = _document.copyWith(title: name);
    _dirty = false;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _endWait();
    _heardWatch?.cancel();
    _previewDir?.delete(recursive: true).catchError((_) => _previewDir!);
    _disposed = true;
    _partTimer?.cancel();
    _warpTimer?.cancel();
    for (var a in _arps.values) {
      a.timer?.cancel();
    }
    _arps.clear();
    if (gaming) {
      HardwareKeyboard.instance.removeHandler(_gameKey);
      _gameTimer?.cancel();
      _game?.dispose();
      _game = null;
    }
    if (sheetMarksOf == _sheetMarks) sheetMarksOf = null;
    if (vectorSoloOf == _soloOf) vectorSoloOf = null;
    if (characterDollOf == _dollOf) characterDollOf = null;
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

/// Offset2 is a pair of doubles.
///
/// Its own type rather than dart:ui's Offset so that this file -- which is
/// pure session state and is unit tested without a widget binding -- imports
/// nothing from the framework. It converts at the one place the stage needs
/// it.
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

  /// editable is false for a clip on the master seen from a page: it is
  /// changed on the master, where it lives.
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
const double timelineHeaderMax = 240;

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
// Each started from a function of its own, here at the top level: a
// closure handed to Isolate.run inside one of the controller's methods can
// carry the method's whole context with it -- the controller and its
// timers -- and those cannot be sent ("object is unsendable").

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
        Map<ClipEnvelope, List<ControlPoint>> envelopes) =>
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

/// _ClipPlayed is a clip played from a slot while Record was on, from and
/// to session seconds.
/// _Repeat is a Repeat clip held down: its row, when it is launched again,
/// how often, and how loud.
class _Repeat {
  final int row;
  double nextAt;
  final double step;
  final double level;
  _Repeat(this.row, this.nextAt, this.step, this.level);
}

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
  int velocity = 100;
  int? sounding;
  Timer? timer;
  _LiveArp(this.player);
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
