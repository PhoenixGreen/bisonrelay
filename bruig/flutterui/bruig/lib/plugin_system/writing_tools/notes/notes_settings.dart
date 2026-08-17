import 'package:bruig/components/text.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/theming_system/runtime/theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// notes_settings.dart is what the reader gets to decide about notes: whether
// there are any, and where the button that opens them sits.
//
// Both are persisted, and that is the difference between these and the
// writing tools' own "enabled" switch next door, which deliberately is not:
// that one is "stop correcting me for a minute", a mood. These are decisions
// about the shape of the window, and a button that moved back to the middle
// every time the app restarted would be a bug rather than a default.

/// NotesButtonPosition is where the notes button sits along the bottom edge
/// of the content area.
///
/// Three positions rather than a free choice because the button has to sit
/// over the page's own content, and these are the three corners of it that
/// are reliably empty. Which of them is empty depends on the page and on how
/// the window is arranged, which is why it is the reader's call and not one
/// made here.
enum NotesButtonPosition {
  leftTriangle(
      "Left triangle",
      "A wedge in the bottom-left corner, "
          "against the sidebar"),
  rightTriangle(
      "Right triangle",
      "A wedge in the bottom-right corner, "
          "against the window's edge"),
  threeDots("Three dots", "Centred along the bottom of the content area");

  final String label;
  final String description;
  const NotesButtonPosition(this.label, this.description);
}

/// NotesPreferences is the notes feature's own settings.
class NotesPreferences extends ChangeNotifier {
  static const _enabledKey = "notesEnabled";
  static const _positionKey = "notesButtonPosition";

  /// enabled is whether notes exist at all. On by default: it is a feature of
  /// the writing tools, and somebody who has enabled the writing tools has
  /// said what they want.
  bool get enabled => _enabled;
  bool _enabled = true;

  NotesButtonPosition get position => _position;
  NotesButtonPosition _position = NotesButtonPosition.leftTriangle;

  /// load reads what was saved. Called once at startup; until it returns the
  /// defaults are in force, which is the right way round -- a notes button
  /// that flickered into existence a moment after the window opened would be
  /// worse than one that was simply there.
  Future<void> load() async {
    _enabled = await StorageManager.readBool(_enabledKey, defaultVal: true);
    var saved = await StorageManager.readString(_positionKey);
    _position =
        NotesButtonPosition.values.where((p) => p.name == saved).firstOrNull ??
            NotesButtonPosition.leftTriangle;
    notifyListeners();
  }

  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    StorageManager.saveBool(_enabledKey, value);
    notifyListeners();
  }

  set position(NotesButtonPosition value) {
    if (value == _position) return;
    _position = value;
    StorageManager.saveString(_positionKey, value.name);
    notifyListeners();
  }
}

/// NotesSettingsSection is the notes half of the writing tools' panel in
/// Settings > Plugins.
class NotesSettingsSection extends StatelessWidget {
  const NotesSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    var prefs = context.watch<NotesPreferences>();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: prefs.enabled,
        onChanged: (v) => prefs.enabled = v,
        title: const Txt.M("Notes"),
        subtitle: const Txt.S(
            "A note for whatever you are looking at -- a file, a chat, a post "
            "-- plus one app-wide note, from a button at the foot of the "
            "page. Notes are saved as Markdown in your post library, under "
            "\"Bison Relay Notes\".",
            color: TextColor.onSurfaceVariant),
      ),
      if (prefs.enabled) ...[
        const SizedBox(height: 12),
        const Txt.S("Notes button", color: TextColor.onSurfaceVariant),
        const SizedBox(height: 6),
        DropdownButton<NotesButtonPosition>(
          value: prefs.position,
          items: [
            for (var p in NotesButtonPosition.values)
              DropdownMenuItem(value: p, child: Txt.S(p.label)),
          ],
          onChanged: (p) {
            if (p != null) prefs.position = p;
          },
        ),
        const SizedBox(height: 6),
        Txt.S(prefs.position.description, color: TextColor.onSurfaceVariant),
      ],
      const SizedBox(height: 16),
    ]);
  }
}
