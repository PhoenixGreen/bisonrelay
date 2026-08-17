import 'package:bruig/plugin_system/plugin_capability.dart';
import 'package:bruig/plugin_system/plugin_manager.dart';
import 'package:bruig/plugin_system/writing_tools/notes/note_storage.dart';
import 'package:bruig/plugin_system/writing_tools/notes/notes_model.dart';
import 'package:bruig/plugin_system/writing_tools/notes/notes_settings.dart';
import 'package:bruig/plugin_system/writing_tools/notes/ui/notes_button.dart';
import 'package:bruig/plugin_system/writing_tools/notes/ui/notes_panel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// notes_host.dart is the one place in the app that draws notes.
//
// It wraps the *content area* -- the region beside a page's own sidebar, not
// everything past the main navigation. That distinction is the whole of what
// this file has to get right: on the Chat page the content area is the
// conversation, and the chat list to its left is a sidebar, so a button at the
// foot of "everything past the navigation" lands under the chat list, which is
// not the page.
//
// It gets there through contentAreaOverlay in components/containers.dart,
// registered at startup by registerWritingTools. Every layout in the app
// already funnels its content through contentAreaFrame, so one registration
// puts notes on every screen and no screen has to mention them.
//
// The conditions for notes existing at all are gathered here and nowhere else:
// the providers have to be present, the Writing Tools plugin has to be on, the
// notes setting has to be on, and the area has to be tall enough to hold a
// panel. Any of them failing returns the child completely untouched -- not a
// hidden button, not a zero-height box -- so the hook costs nothing to anyone
// who does not want the feature, and is safe on a screen mounted without the
// notes providers at all.
//
// What is NOT here is the page's target. That arrives through NotesModel,
// which is wired to NoteTargetModel by a proxy provider in main.dart, so this
// widget never has to know how the navigation works.

/// _NotesHostScope marks a subtree that already has a notes host above it.
///
/// The feed nests content areas -- FeedPosts frames its own column, and the
/// screen above frames the tab containing it -- so the hook fires twice on one
/// screen. The outer one wins, being the larger region and the one whose
/// bottom edge is the page's; the inner one draws nothing.
class _NotesHostScope extends InheritedWidget {
  const _NotesHostScope({required super.child});

  @override
  bool updateShouldNotify(_NotesHostScope old) => false;
}

/// NotesHost adds the notes button and panel to the content area.
class NotesHost extends StatelessWidget {
  final Widget child;
  const NotesHost({required this.child, super.key});

  /// _minRoomForPanel is the content height below which notes are not
  /// offered.
  ///
  /// Three lines' worth, because the panel is capped at a third of the content
  /// (see _NotesHostBodyState.build) and a third of anything shorter would be
  /// less than the one line the panel is allowed to shrink to. Below this the
  /// button is not drawn rather than drawn and useless.
  static const double _minRoomForPanel = minNotesPanelHeight * 3;

  @override
  Widget build(BuildContext context) {
    // Already inside one: the feed nests content areas. Not a dependency --
    // this never has to rebuild on the marker changing, because the marker
    // never changes.
    if (context.getInheritedWidgetOfExactType<_NotesHostScope>() != null) {
      return child;
    }

    // Nullable lookups, so this is inert rather than fatal on a screen mounted
    // without the notes providers. The hook now fires inside every content
    // area in the app, including in tests that never heard of notes, and a
    // ProviderNotFoundException thrown from a generic container would take
    // those screens down over a feature they are not using.
    var plugins = context.watch<PluginManagerModel?>();
    var prefs = context.watch<NotesPreferences?>();
    if (plugins == null || prefs == null) return child;

    // Gated on the capability rather than a plugin id, the same question the
    // Writing nav item asks (see writing_nav.dart): notes belong to the
    // writing tools, and whichever plugin provides those has earned them.
    if (!prefs.enabled ||
        !plugins.hasCapability(PluginCapability.spellcheckData)) {
      return child;
    }

    return _NotesHostScope(
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxHeight < _minRoomForPanel) return child;
        return _NotesHostBody(maxHeight: constraints.maxHeight, child: child);
      }),
    );
  }
}

class _NotesHostBody extends StatefulWidget {
  final double maxHeight;
  final Widget child;
  const _NotesHostBody({required this.maxHeight, required this.child});

  @override
  State<_NotesHostBody> createState() => _NotesHostBodyState();
}

class _NotesHostBodyState extends State<_NotesHostBody> {
  /// _hasNote is whether the note the button would open has anything in it,
  /// so the button can be drawn filled in.
  ///
  /// Held here and read asynchronously rather than answered during build: the
  /// question ends in a directory listing, and build runs on every frame of a
  /// drag.
  bool _hasNote = false;

  /// _checkedKey is the note [_hasNote] was last asked about.
  ///
  /// The guard matters: didChangeDependencies fires on every NotesModel
  /// notification, and dragging the panel's handle notifies on every frame of
  /// the gesture. Without this, resizing the panel would run a directory
  /// listing sixty times a second to re-answer a question whose answer cannot
  /// have changed.
  String? _checkedKey;

  @override
  void initState() {
    super.initState();
    // Made as soon as notes are on, so the folder is in the post library's
    // sidebar to be found before anything has been written into it.
    NoteStorage.ensureFolder();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    var showing = context.read<NotesModel>().showing;
    if (showing.key == _checkedKey) return;
    _checkedKey = showing.key;
    _refreshHasNote();
  }

  /// _refreshHasNote asks whether the note the button would open has anything
  /// in it. Called unguarded from the button itself, where the answer really
  /// has just changed.
  Future<void> _refreshHasNote() async {
    var has = await NoteStorage.hasNote(context.read<NotesModel>().showing);
    if (mounted && has != _hasNote) setState(() => _hasNote = has);
  }

  @override
  Widget build(BuildContext context) {
    var notes = context.watch<NotesModel>();
    var prefs = context.watch<NotesPreferences>();

    // A third of the content area, at most. The panel is for writing *about*
    // what is on screen, so the thing being written about has to stay the
    // larger part of the page -- a note given half the window has quietly
    // become the window, with the page it refers to as a strip above it.
    var maxPanel = widget.maxHeight / 3;

    return Column(children: [
      Expanded(
        child: Stack(children: [
          Positioned.fill(child: widget.child),
          // Only while the panel is shut. Open, the panel's own close button
          // is the way out, and a second control doing the same thing an inch
          // below it is one the reader has to choose between for no reason.
          if (!notes.open)
            _placed(
              prefs.position,
              NotesButton(
                position: prefs.position,
                hasNote: _hasNote,
                onPressed: () async {
                  await notes.openPanel();
                  _refreshHasNote();
                },
              ),
            ),
        ]),
      ),
      if (notes.open) NotesPanel(maxHeight: maxPanel),
    ]);
  }

  /// _placed puts the button where the reader chose.
  ///
  /// The two triangles sit flush in their corners, with no inset at all: they
  /// are wedges of the corner itself, and a gap would leave them floating
  /// beside the edges they are meant to be part of. Flush left means against
  /// the sidebar, because the content area begins where the sidebar ends.
  ///
  /// The three-dot form has no edge to belong to, so it is stretched across
  /// the content area and centred inside it -- which puts it midway between
  /// the sidebar and the right of the window.
  Widget _placed(NotesButtonPosition position, Widget button) =>
      switch (position) {
        NotesButtonPosition.leftTriangle =>
          Positioned(bottom: 0, left: 0, child: button),
        NotesButtonPosition.rightTriangle =>
          Positioned(bottom: 0, right: 0, child: button),
        NotesButtonPosition.threeDots => Positioned(
            bottom: 0, left: 0, right: 0, child: Center(child: button)),
      };
}
