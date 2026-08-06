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
enum ComposerPanel {
  /// The screen shows whatever it normally would.
  none,

  /// The writing tools: spelling, grammar, phrasing, reference.
  writing,

  /// The saved-post library: folders and documents on disk.
  posts,
}

/// ComposerSidebarController connects a composer to the screen that owns the
/// sidebar slot beside it.
class ComposerSidebarController extends ChangeNotifier {
  ComposerPanel _panel = ComposerPanel.none;
  TextEditingController? _editor;

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
  bool get visible => _panel != ComposerPanel.none;

  /// attach offers a composer's text. Called as the composer mounts; it does
  /// not open anything by itself, since arriving at an editor should not
  /// rearrange the screen.
  void attach(TextEditingController editor) {
    if (identical(_editor, editor)) return;
    _editor = editor;
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

  /// show hands the slot to [panel]. Asking for the one already showing
  /// closes it, so the button that opened a panel also puts it away.
  void show(ComposerPanel panel) {
    var next = panel == _panel ? ComposerPanel.none : panel;
    if (next == _panel) return;
    _panel = next;
    notifyListeners();
  }

  void close() {
    if (_panel == ComposerPanel.none) return;
    _panel = ComposerPanel.none;
    notifyListeners();
  }
}
