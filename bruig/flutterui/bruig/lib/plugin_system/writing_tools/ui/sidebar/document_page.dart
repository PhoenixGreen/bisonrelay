import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/writing_tools/engine/stats.dart';
import 'package:flutter/material.dart';

// document_page.dart is how much there is of it: words, characters, sentences,
// how long it takes to read and how hard it is.
//
// The one page of the sidebar that works with no provider enabled at all.
// Counting words is not a judgement about English and needs no dictionary, so
// this page is never empty and never says the feature is off.

class DocumentPage extends StatelessWidget {
  final String text;
  const DocumentPage({required this.text, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    // Rebuilt from the text on every change rather than cached: everything
    // here is a single pass over a message, which is nothing beside the spell
    // check already running on the same keystroke.
    var stats = WritingStats.of(text);
    var ease = stats.readingEaseLabel;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        _stat(theme, "Words", "${stats.words}"),
        _stat(theme, "Characters", "${stats.characters}"),
        _stat(theme, "Characters (no spaces)", "${stats.charactersNoSpaces}"),
        _stat(theme, "Sentences", "${stats.sentences}"),
        _stat(theme, "Paragraphs", "${stats.paragraphs}"),
        _stat(theme, "Lines", "${stats.lines}"),
        _stat(theme, "Pages", stats.pages.toStringAsFixed(1)),
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 8),
        _stat(theme, "Reading time", _readingTime(stats)),
        // Absent rather than shown as a dash on text too short to score: a
        // reading-ease figure for one sentence is arithmetic, not information,
        // and printing it invites it to be believed.
        if (ease != null)
          _stat(theme, "Reading ease", "$ease (${stats.readingEase!.round()})"),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            ease == null
                ? "Reading ease appears once there is enough text to score."
                : "Reading ease runs 0 to 100; plain English scores 60-70. "
                    "Pages assume $wordsPerPage words; reading time assumes "
                    "$wordsPerMinute words a minute.",
            style: TextStyle(
                fontSize: 10,
                height: 1.4,
                color: theme.colors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  String _readingTime(WritingStats stats) {
    var seconds = stats.readingTime.inSeconds;
    if (seconds < 60) return "$seconds sec";
    return "${stats.readingTime.inMinutes} min";
  }

  Widget _stat(ThemeNotifier theme, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, color: theme.colors.onSurfaceVariant)),
          ),
          Text(value,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}
