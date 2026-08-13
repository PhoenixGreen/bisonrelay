import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/runtime/theme_tokens.dart';
import 'package:bruig/plugin_system/writing_tools/engine/preferences.dart';
import 'package:bruig/plugin_system/writing_tools/spellcheck_capability.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';

// writing_settings.dart is the writing tools' section of Settings > Plugins.
//
// It is registered against the spellcheck-data capability rather than reached
// by the settings page, which knows nothing about it -- see
// plugin_system/plugin_settings.dart. That is what puts it inside the panel of
// whichever plugin happens to provide the data, and what makes it appear on
// its own when no plugin does.

/// WritingOverridesSection lists what the user has told the writing tools to
/// stop reporting, and takes it back.
///
/// The overrides outlive any one plugin -- they are decisions about the user's
/// own app, and a word added to the dictionary must stay ignored across a
/// provider being updated or swapped. Somewhere to undo them matters more than
/// usual: an accidental "Add to dictionary" on a genuine typo is otherwise
/// invisible and permanent.
///
/// Absent entirely until something has been overridden, so the page is
/// unchanged for anyone who has never used it.
class WritingOverridesSection extends StatelessWidget {
  /// inPluginPanel drops the heading and the rule above it. Inside a panel the
  /// plugin's name is already at the top and the panel has its own divider, so
  /// both would be saying a second time what the surroundings already say.
  final bool inPluginPanel;

  const WritingOverridesSection({this.inPluginPanel = false, super.key});

  @override
  Widget build(BuildContext context) {
    var prefs = context.watch<WritingPreferences>();
    var spellcheck = context.watch<SpellcheckCapability?>();
    var languages = spellcheck?.languages ?? const <SpellcheckLanguage>[];

    // Nothing to show at all when no provider offers a choice and nothing has
    // been overridden. A section that is always there but usually empty is a
    // section people learn to skip.
    if (languages.length < 2 &&
        prefs.personalDictionary.isEmpty &&
        prefs.disabledChecks.isEmpty) {
      return const SizedBox.shrink();
    }

    var words = prefs.personalDictionary.toList()..sort();
    var checks = prefs.disabledChecks.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!inPluginPanel) ...[
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 8),
        const Txt.L("Writing tools"),
      ],
      const SizedBox(height: 16),
      if (languages.length > 1) _language(prefs, spellcheck!, languages),
      if (words.isNotEmpty)
        _chips("Words added to your dictionary", [
          for (var word in words)
            InputChip(
              label: Text(word),
              onDeleted: () => prefs.removeFromDictionary(word),
              tooltip: "Check this word again",
            ),
        ]),
      if (checks.isNotEmpty)
        _chips("Checks you turned off", [
          // Shown by the rule's own description. A check is identified by its
          // pattern, which is what makes a rule unique, but a regular
          // expression is not something to put in front of anyone -- it only
          // appears as a fallback for an entry saved before descriptions were
          // recorded.
          for (var check in checks)
            InputChip(
              label: Text(check.value.isEmpty ? check.key : check.value),
              onDeleted: () => prefs.enableCheck(check.key),
              tooltip: "Turn this check back on",
            ),
        ]),
    ]);
  }

  /// _language is offered only when a provider has more than one to offer, and
  /// built from what it says it has rather than from a list held here: the
  /// languages are the provider's, and an app-side list would go stale the
  /// moment one shipped another.
  Widget _language(WritingPreferences prefs, SpellcheckCapability spellcheck,
          List<SpellcheckLanguage> languages) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Txt.S("Language", color: TextColor.onSurfaceVariant),
        const SizedBox(height: 6),
        DropdownButton<String>(
          value: languages.any((l) => l.code == spellcheck.activeLanguage)
              ? spellcheck.activeLanguage
              : null,
          hint: const Txt.S("Choose a language"),
          items: [
            for (var language in languages)
              DropdownMenuItem(
                  value: language.code, child: Txt.S(language.name)),
          ],
          onChanged: (code) {
            if (code != null) prefs.setLanguage(code);
          },
        ),
        const SizedBox(height: 6),
        const Txt.S(
            "Changes which dictionary your writing is checked against. "
            "\"Colour\" and \"color\" are each correct in one and wrong in "
            "the other.",
            color: TextColor.onSurfaceVariant),
        const SizedBox(height: 16),
      ]);

  Widget _chips(String label, List<Widget> chips) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Txt.S(label, color: TextColor.onSurfaceVariant),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: chips),
        const SizedBox(height: 16),
      ]);
}
