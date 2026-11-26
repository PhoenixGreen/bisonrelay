part of '../canvas_controller.dart';

// What a button element does when pressed, in the editor's preview, the file
// player and a game. Part of CanvasController.
//
// A published book does the same actions its own way, in the page script of
// export/epub_writer.dart (its buttons gathered by export/epub_media.dart,
// and its links by export/document_export.dart). The two are kept to this
// one table of what each action does:
//
// | Action          | Does                                                    |
// |-----------------|---------------------------------------------------------|
// | goToFrame       | Stops, and puts the playhead on the frame.              |
// | playFrom        | Puts the playhead on the frame, and plays from there.   |
// | playToFrame     | Plays, and stops on the frame.                          |
// | play            | Plays from the playhead.                                |
// | pause           | Stops where it is.                                      |
// | togglePlay      | Plays, or stops where it is.                            |
// | restart         | Plays from the first frame.                             |
// | toggleElement   | Shows the element, or hides it.                         |
// | goToScene       | Turns to the scene, at its first frame, and plays it if |
// |                 | it moves.                                               |
// | openLink        | Asks to open the web address.                           |
// | playSound       | Starts the sound or video, or goes on where it was held.|
// | pauseSound      | Holds it where it is.                                   |
// | toggleSound     | Starts it, or holds it if it is going.                  |
// | stopSound       | Stops it, back at its start.                            |
// | muteSound       | Silences it, or brings it back.                         |
//
// Both hold the frame a button names to the scene's frames: past the end
// is its last frame.
//
// Where the two still differ:
// - Where a button is pressed: here, a selected button, where it is drawn,
//   turned, slanted and moved (the file player presses any button in its
//   moved box, upright); in the book, in the box it rests in, upright,
//   which on a page laid out as layers moves with the button's own move.
// - The playhead's actions (goToFrame, playFrom, playToFrame, play, pause,
//   togglePlay, restart): the book makes their buttons only on a page that
//   moves, so on a still page they are not there; here they act on any
//   scene.
// - The master's buttons: the book makes each on every page that shows the
//   master; here they are not pressed from a scene, the master being edited
//   on its own (the file player presses them on every scene that shows
//   it).
// - playToFrame: here, from the first frame when the playhead is on the
//   frame or past it; the book starts again only from the very end, and
//   from anywhere else past the frame plays on to the end.
// - playFrom and restart, pressed while playing: here, a stop asked for by
//   an earlier playToFrame still stands, and restart keeps the loop
//   markers' counts; the book lets go of both.
// - toggleElement: here, an edit to the canvas (an undo step, saved with
//   it); in the book, for that reading only, and only for an element given
//   a layer of its own (export/epub_layers.dart).
// - goToScene aimed at the scene showing: here, it plays again from its
//   first frame; the book makes no link to its own page.
// - openLink: here the caller opens it, after asking (the file player does
//   not); the book makes a link of a web address and leaves the asking to
//   the reader.
// - The sound and video actions: the book reaches only one on the same
//   page, or the page's backdrop sound; here, one on the scene showing, the
//   master or the background.
// - While a game plays, goToScene, restart and toggleElement here are the
//   game's (see _gamePress), and togglePlay holds the game too; a book has
//   no game.

extension CanvasButtonActions on CanvasController {
  /// runButtonAction is what pressing a button element does, both in the
  /// editor's preview and in a published interactive canvas. Returns the URL
  /// a link button asked to open, if any, so opening it (leaving the app)
  /// stays the caller's decision.
  String? runButtonAction(ButtonAction action) {
    // Clicked while a game plays: what the game does with it, as a key
    // press does (see _gamePress), so a scene gone to starts its sounds and
    // clips, a restart begins the game again, and shown or hidden is the
    // game's.
    if (_game case var run?) {
      switch (action.kind) {
        case ButtonActionKind.goToScene:
          _gameScene(run, action.elementId);
          return null;
        case ButtonActionKind.restart:
          _gameRestart(run);
          return null;
        case ButtonActionKind.toggleElement:
          if (action.elementId.isNotEmpty) run.toggle(action.elementId);
          return null;
        default:
      }
    }
    switch (action.kind) {
      case ButtonActionKind.goToFrame:
        pause();
        frame = action.frame;
      case ButtonActionKind.playFrom:
        frame = action.frame;
        play();
      case ButtonActionKind.playToFrame:
        // Stopping on its frame, as a published canvas does; from the start
        // where the playhead is already there or past it.
        var to =
            action.frame.clamp(0, math.max(0, _document.frames - 1)).toInt();
        if (_frame >= to) frame = 0;
        play();
        if (playing) _setRangeEnd(to + 1);
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
          // A scene that moves plays from its start, as a page turned to in
          // the book does, rather than standing unbuilt.
          if (_document.frames > 1) play();
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
}
