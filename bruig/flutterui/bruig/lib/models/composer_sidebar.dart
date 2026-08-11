import 'package:bruig/models/feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// composer_sidebar.dart coordinates the one sidebar slot a composer screen
// can lend out, between the panels that want it.
//
// The two are far apart: the text being worked on belongs to the composer,
// while the slot the panel goes in belongs to the screen hosting it, and
// neither can reach the other. A composer [attach]es while it is on screen,
// the screen watches this to know whether it has anything to show, and the
// slot goes back to its normal contents the moment either the composer
// leaves or the panel is closed.
//
// One controller rather than one per panel, because there is one slot. Two
// controllers would each believe they owned it, and the screen would have to
// invent a precedence rule between them that neither knew about -- which is
// the shape of every bug this file's history is made of.

/// ComposerPanel is which panel currently has the slot.
///
/// Declaration order is the order the icons appear in, so the nav is read
/// straight off this rather than repeated beside it.
/// The declaration order is the order the icons appear in, and it is the
/// only place that order is set -- the Feed builds its row by walking this.
/// It runs outwards from the post: where you are (the feed menu), what you
/// have written before (My Posts), the words in front of you (Writing
/// Tools), and what you can put around them (Formatting & Content).
enum ComposerPanel {
  /// The screen's own navigation -- for the Feed, its tab list.
  ///
  /// Not a panel the composer ever rests on. Choosing it is choosing to
  /// leave the composer, and the Feed page opens with it; a composer that
  /// opened on it would be showing the way out instead of the tools.
  none(Icons.list, "Feed menu"),

  /// The saved-post library: folders and documents on disk.
  posts(Icons.folder_outlined, "My Posts"),

  /// The writing tools: spelling, grammar, phrasing, reference.
  writing(Icons.spellcheck, "Writing Tools"),

  /// Formatting and content: embeds, headings, tables, callouts.
  formatting(Icons.text_fields, "Formatting & Content");

  final IconData icon;
  final String label;
  const ComposerPanel(this.icon, this.label);
}

/// ComposerSidebarController connects a composer to the screen that owns the
/// sidebar slot beside it.
class ComposerSidebarController extends ChangeNotifier {
  ComposerPanel _panel = ComposerPanel.none;

  /// _lastWorkingPanel is the panel the composer was last actually working
  /// in, which is where it opens the next time one arrives.
  ///
  /// My Posts to begin with, because the first thing anyone does with a new
  /// post is find or name the document it belongs to. After that it is
  /// wherever they were: going to Chat and coming back should not lose the
  /// panel they had set up any more than switching tabs does.
  ///
  /// Never the feed menu. That one is the way out of the composer rather
  /// than a place in it -- choosing it opens the Feed page -- so opening on
  /// it would mean every new post started by showing the exit.
  ComposerPanel _lastWorkingPanel = ComposerPanel.posts;

  bool _minimized = false;

  /// preview renders the markdown in the composer as it is typed instead of
  /// showing its source.
  ///
  /// Off by default, and deliberately so: the raw view is the one that shows
  /// exactly what will be published, and somebody who has not asked for a
  /// preview has not agreed to be shown an approximation of their own post.
  bool _preview = false;
  bool get preview => _preview;
  set preview(bool value) {
    if (_preview == value) return;
    _preview = value;
    notifyListeners();
  }

  TextEditingController? _editor;

  /// post is the model the composer is writing into, offered so the
  /// formatting panel can read and set the style guide the post carries.
  ///
  /// Registered by the composer rather than reached for, like onAddEmbed
  /// below and for the same reason: the panel is handed what it needs
  /// instead of knowing which screen it is beside.
  NewPostModel? post;

  /// notifyStyleChanged tells the composer to repaint after something that
  /// changes how the text looks but not what it says -- picking a different
  /// style guide, where the text is untouched and every span of it is drawn
  /// differently.
  void notifyStyleChanged() => notifyListeners();

  /// onAddEmbed is the composer's own file picker, offered by the
  /// formatting panel.
  ///
  /// Registered by the composer rather than reached for, because picking a
  /// file is the composer's business: it tracks the embed, re-estimates the
  /// post's size and knows what it will accept. The panel only needs
  /// somewhere to send a button press.
  VoidCallback? onAddEmbed;

  // _disposed guards the deferred notification in detach: by the time the
  // frame ends, this controller may itself be gone.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// editor is the composer currently offering its text, or null when none
  /// is on screen.
  TextEditingController? get editor => _editor;

  /// panel is which panel to show, for a host deciding what to put in the
  /// slot.
  ComposerPanel get panel => _panel;

  /// minimized hides the sidebar altogether, for writing with nothing else
  /// on screen.
  ///
  /// Separate from the panel rather than another value of it, so restoring
  /// comes back to whatever was showing. Somebody who minimized while
  /// reading their library did not ask to be returned to the feed menu.
  bool get minimized => _minimized;

  void toggleMinimized() {
    _minimized = !_minimized;
    notifyListeners();
  }

  /// visible is the single question a host screen asks: is the slot lent out
  /// right now.
  ///
  /// It turns on the panel alone and not on whether a composer is attached,
  /// deliberately. Making it wait for one is a feedback loop: showing a
  /// panel changes the layout, which rebuilds the composer beneath it, which
  /// withdraws while it does so -- so the answer flips back to false, the
  /// layout reverts, the composer rebuilds again, and the two never settle.
  /// A panel copes with a moment of having nothing to show; the loop cannot
  /// be coped with at all.
  ///
  /// Always true while a composer is on screen, because the nav that
  /// switches panels lives in the slot too -- including on the panel that
  /// shows the screen's own menu. Minimizing is the only thing that gives
  /// the slot back.
  bool get visible => !_minimized;

  /// attach offers a composer's text. Called as the composer mounts; it does
  /// not open anything by itself, since arriving at an editor should not
  /// rearrange the screen.
  void attach(TextEditingController editor) {
    if (identical(_editor, editor)) return;
    _editor = editor;
    // A composer has arrived, so the slot goes back to something a composer
    // can use. Left on the feed menu -- which is where leaving the composer
    // puts it -- the panel beside a new post would be the list of ways to go
    // somewhere else.
    //
    // Minimized is left exactly as it was: hiding the sidebar is a decision
    // about the screen, and arriving at a composer is not a reason to
    // overturn it.
    if (_panel == ComposerPanel.none) _panel = _lastWorkingPanel;
    notifyListeners();
  }

  /// detach withdraws a composer. Ignored if some other composer has since
  /// attached, so a screen being torn down cannot cancel its replacement.
  ///
  /// Deliberately leaves the panel open. Which panel is showing is the
  /// user's decision, not the composer's, and a composer is torn down and
  /// rebuilt for reasons that have nothing to do with it -- including,
  /// awkwardly, opening a panel, which changes the layout enough to rebuild
  /// the editor underneath. Clearing the flag here made the sidebar close in
  /// the same frame it opened.
  void detach(TextEditingController editor) {
    if (!identical(_editor, editor)) return;
    _editor = null;
    // Deferred past the current frame. A composer detaches from its
    // dispose(), which runs while Flutter is unmounting elements, and
    // notifying there rebuilds widgets mid-teardown -- which the framework
    // refuses outright.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      notifyListeners();
    });
  }

  /// show puts [panel] in the slot, and un-minimizes if it was hidden --
  /// asking for a panel is asking to see it.
  void show(ComposerPanel panel) {
    if (panel == _panel && !_minimized) return;
    _panel = panel;
    // Remembered so the next composer opens here. The feed menu is not one
    // of these: see _lastWorkingPanel.
    if (panel != ComposerPanel.none) _lastWorkingPanel = panel;
    _minimized = false;
    notifyListeners();
  }

  /// close leaves the composer's panels for the screen's own menu, which is
  /// also what opens the Feed page. The panel that was open is remembered --
  /// see _lastWorkingPanel -- so coming back finds it again.
  void close() => show(ComposerPanel.none);
}
