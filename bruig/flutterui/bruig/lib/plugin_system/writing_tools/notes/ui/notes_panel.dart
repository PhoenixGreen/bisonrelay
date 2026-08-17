import 'package:bruig/components/containers.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/writing_tools/notes/note_target.dart';
import 'package:bruig/plugin_system/writing_tools/notes/notes_model.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// notes_panel.dart is the note itself: a strip at the foot of the content
// area, under whatever the page is showing.
//
// A panel and not a dialog, and that is the entire point of the feature. Notes
// taken while reading, watching or talking are taken *about* what is on
// screen, and a dialog covers the thing you are writing about. Everything else
// here follows from that: it is short by default, it can be dragged to any
// height up to the whole page when the note is the work rather than the
// margin, and it saves as it is written so there is no step between having
// written something and it being kept.

/// NotesPanel draws the open note.
class NotesPanel extends StatelessWidget {
  /// maxHeight is the content area, which the panel may take all of.
  final double maxHeight;

  const NotesPanel({required this.maxHeight, super.key});

  @override
  Widget build(BuildContext context) {
    var notes = context.watch<NotesModel>();
    var theme = ThemeNotifier.of(context);

    var height = notes.height.clamp(minNotesPanelHeight, maxHeight);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.colors.surface,
        border: Border(top: BorderSide(color: theme.colors.outlineVariant)),
      ),
      child: Column(children: [
        _Handle(notes: notes, maxHeight: maxHeight),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: _header(context, notes, theme),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: notes.loading
                ? const Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                // No Save button: the note is saved as it is written, like the
                // composer's drafts are. A button here would be one more thing
                // to forget to press.
                : TextField(
                    controller: notes.editor,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      isDense: true,
                      hintText: notes.showing.isGlobal
                          ? "An app-wide note. Saved as you type."
                          : "Notes about ${notes.showing.label}. Saved as "
                              "you type.",
                    ),
                  ),
          ),
        ),
      ]),
    );
  }

  Widget _header(BuildContext context, NotesModel notes, ThemeNotifier theme) =>
      Row(children: [
        _ScopeSwitch(notes: notes),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            notes.showing.title,
            overflow: TextOverflow.ellipsis,
            style:
                TextStyle(fontSize: 12, color: theme.colors.onSurfaceVariant),
          ),
        ),
        if (notes.saveFailed)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Txt.S("Could not save this note",
                color: TextColor.onErrorContainer),
          ),
        IconButton(
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close),
          tooltip: "Close notes",
          onPressed: notes.close,
        ),
      ]);
}

/// _ScopeSwitch is the Local / Global pair.
///
/// Local is disabled rather than hidden on a page that has no note of its own.
/// Hiding it would make the control change shape as you walk around the app,
/// and the greyed-out half is what says "this page cannot have its own note",
/// which is worth knowing.
class _ScopeSwitch extends StatelessWidget {
  final NotesModel notes;
  const _ScopeSwitch({required this.notes});

  @override
  Widget build(BuildContext context) => SegmentedButton<NoteScope>(
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: [
          ButtonSegment(
            value: NoteScope.local,
            label: const Text("Local", style: TextStyle(fontSize: 11)),
            enabled: notes.hasLocal,
            tooltip: notes.hasLocal
                ? "A note for this page alone"
                : "This page has no note of its own",
          ),
          const ButtonSegment(
            value: NoteScope.global,
            label: Text("Global", style: TextStyle(fontSize: 11)),
            tooltip: "One note, the same everywhere",
          ),
        ],
        // The switch follows what is actually being shown rather than what was
        // asked for, so a page with no local note shows Global selected
        // instead of a Local button that is lit but displaying something else.
        selected: {notes.showing.isGlobal ? NoteScope.global : NoteScope.local},
        onSelectionChanged: (s) => notes.setScope(s.first),
      );
}

/// _Handle is the grab strip along the panel's top edge.
///
/// The vertical twin of ResizableSidebar's, down to the double-tap reset and
/// the colours, because it is the same gesture on a different axis and there
/// is no reason for the two to feel different. What it adds is the bottom
/// stop: dragged below one line of writing, the panel closes rather than
/// bottoming out, since a note squashed to nothing is somebody putting it
/// away.
class _Handle extends StatelessWidget {
  final NotesModel notes;
  final double maxHeight;
  const _Handle({required this.notes, required this.maxHeight});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Dragging up makes the panel taller, so the delta is subtracted.
        onVerticalDragUpdate: (d) {
          var wanted = notes.height - d.delta.dy;
          if (wanted < minNotesPanelHeight - 24) {
            notes.close();
            return;
          }
          notes.setHeight(wanted.clamp(minNotesPanelHeight, maxHeight));
        },
        onVerticalDragEnd: (_) => notes.saveHeight(),
        onDoubleTap: () {
          notes.setHeight(
              defaultNotesPanelHeight.clamp(minNotesPanelHeight, maxHeight));
          notes.saveHeight();
        },
        child: SizedBox(
          height: 8,
          width: double.infinity,
          child: Center(
            child: SizedBox(
              height: sidebarEdgeWidth(theme),
              width: 48,
              child: ColoredBox(color: sidebarEdgeColor(theme)),
            ),
          ),
        ),
      ),
    );
  }
}
