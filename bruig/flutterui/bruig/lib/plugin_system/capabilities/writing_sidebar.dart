import 'package:bruig/plugin_system/capabilities/spellcheck.dart';
import 'package:bruig/plugin_system/capabilities/thesaurus.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:bruig/plugin_system/capabilities/writing_prefs.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

// writing_sidebar.dart is the post editor's writing tools, laid out as a
// sidebar rather than a strip under the text.
//
// A list of everything wrong with a post is a tall, narrow thing: it wants
// the height a column has and almost none of the width. Underneath the
// editor it competed with the text for vertical room and had to be capped;
// beside it, it can simply be as long as it needs to be, and the post keeps
// its full height.

/// WritingSidebarController connects a composer to the screen that owns the
/// sidebar slot beside it.
///
/// The two are far apart: the text being checked belongs to the composer,
/// while the slot the results go in belongs to the screen hosting it, and
/// neither can reach the other. A composer [attach]es while it is on screen,
/// the screen watches this to know whether it has anything to show, and the
/// slot goes back to its normal contents the moment either the composer
/// leaves or the sidebar is closed.
class WritingSidebarController extends ChangeNotifier {
  bool _open = false;
  TextEditingController? _editor;

  // _disposed guards the deferred notification in detach: by the time the
  // frame ends, this controller may itself be gone.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// editor is the composer currently offering itself for review, or null
  /// when none is on screen.
  TextEditingController? get editor => _editor;

  /// visible is the single question a host screen asks: should the sidebar
  /// slot show writing tools right now.
  ///
  /// It turns on whether a composer is currently attached, deliberately.
  /// Making it wait for one is a feedback loop: showing the sidebar changes
  /// the layout, which rebuilds the composer beneath it, which withdraws
  /// while it does so -- so the answer flips back to false, the layout
  /// reverts, the composer rebuilds again, and the two never settle. The
  /// sidebar copes with a moment of having nothing to show; the loop cannot
  /// be coped with at all.
  bool get visible => _open;

  /// attach offers a composer's text for review. Called as the composer
  /// mounts; it does not open the sidebar by itself, since arriving at a
  /// post editor should not rearrange the screen.
  void attach(TextEditingController editor) {
    if (identical(_editor, editor)) return;
    _editor = editor;
    notifyListeners();
  }

  /// detach withdraws a composer. Ignored if some other composer has since
  /// attached, so a screen being torn down cannot cancel its replacement.
  ///
  /// Deliberately leaves the sidebar open. Whether it is open is the user's
  /// decision, not the composer's, and a composer is torn down and rebuilt
  /// for reasons that have nothing to do with that -- including, awkwardly,
  /// opening the sidebar itself, which changes the layout enough to rebuild
  /// the editor underneath it. Clearing the flag here made the sidebar close
  /// in the same frame it opened.
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

  void show() {
    if (_open) return;
    _open = true;
    notifyListeners();
  }

  void close() {
    if (!_open) return;
    _open = false;
    notifyListeners();
  }
}

/// WritingSidebar lists every spelling and style issue in [controller]'s
/// text, each fixable in place, with the thesaurus for the current
/// selection underneath.
class WritingSidebar extends StatefulWidget {
  /// The composer under review, or null for the frame or two while one is
  /// being rebuilt -- see WritingSidebarController.visible.
  final TextEditingController? controller;

  /// onClose returns the slot to whatever the screen normally shows there.
  final VoidCallback onClose;

  const WritingSidebar({
    required this.controller,
    required this.onClose,
    super.key,
  });

  @override
  State<WritingSidebar> createState() => _WritingSidebarState();
}

class _WritingSidebarState extends State<WritingSidebar> {
  TextEditingController? get _editor => widget.controller;

  // _lastText is what the list was last built from. The controller notifies
  // on selection changes too, and rebuilding the whole list every time the
  // caret moves is both wasted work and -- while a context menu is open --
  // enough to tear it down. Selection changes still matter for the thesaurus
  // row, so they rebuild that alone.
  late String _lastText = _editor?.text ?? "";
  late TextSelection _lastSelection =
      _editor?.selection ?? const TextSelection.collapsed(offset: -1);

  @override
  void initState() {
    super.initState();
    _editor?.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant WritingSidebar old) {
    super.didUpdateWidget(old);
    // The composer can be swapped underneath this -- a rebuild of the editor
    // hands over a new controller -- and the listener has to move with it.
    if (!identical(old.controller, widget.controller)) {
      old.controller?.removeListener(_onChanged);
      _editor?.addListener(_onChanged);
      _lastText = _editor?.text ?? "";
    }
  }

  @override
  void dispose() {
    _editor?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    var text = _editor?.text ?? "";
    var selection =
        _editor?.selection ?? const TextSelection.collapsed(offset: -1);
    if (text == _lastText && selection == _lastSelection) return;
    setState(() {
      _lastText = text;
      _lastSelection = selection;
    });
  }

  /// _apply replaces one issue's span.
  ///
  /// The text is re-read here rather than taken from when the list was
  /// built: applying one fix shifts every later issue's offsets, and the
  /// list the user is looking at may already be one edit stale. A span whose
  /// text no longer matches is left alone rather than spliced blindly.
  void _apply(WritingIssue issue, String replacement) {
    var editor = _editor;
    if (editor == null) return;
    var text = editor.text;
    if (issue.range.end > text.length) return;
    if (text.substring(issue.range.start, issue.range.end) != issue.text) {
      return;
    }
    editor.value = TextEditingValue(
      text: text.replaceRange(issue.range.start, issue.range.end, replacement),
      selection: TextSelection.collapsed(
          offset: issue.range.start + replacement.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    var spellcheck = context.watch<SpellcheckCapability>();
    var prefs = context.watch<WritingPreferences>();
    var theme = ThemeNotifier.of(context);
    var issues = spellcheck.review(_editor?.text ?? "");

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(theme, prefs, issues.length),
      const Divider(height: 1),
      Expanded(
        child: !prefs.enabled
            ? _note(theme, "Writing tools are off for this session.")
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                children: [
                  if (issues.isEmpty)
                    _note(theme, "Nothing to flag in this post."),
                  for (var issue in issues) _issueRow(theme, prefs, issue),
                ],
              ),
      ),
      // Pinned rather than last in the list. It answers a question about
      // whatever is selected right now, so it has to be visible at the
      // moment of selecting -- and a post with a dozen issues had pushed it
      // below the fold, where nobody would think to scroll for it.
      if (prefs.enabled)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: _thesaurusRow(context, theme),
        ),
    ]);
  }

  Widget _header(ThemeNotifier theme, WritingPreferences prefs, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(children: [
        Expanded(
          child: Text(
            prefs.enabled && count > 0 ? "Writing ($count)" : "Writing",
            style: const TextStyle(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // The whole feature's switch, where the results of it are: turning
        // it off from here is the obvious move when the underlines are in
        // the way, and it takes the inline ones with it.
        Tooltip(
          message: prefs.enabled ? "Turn writing tools off" : "Turn on",
          child: Switch(
            value: prefs.enabled,
            onChanged: (v) => prefs.enabled = v,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          tooltip: "Close",
          onPressed: widget.onClose,
        ),
      ]),
    );
  }

  Widget _note(ThemeNotifier theme, String text) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text,
            style:
                TextStyle(fontSize: 12, color: theme.colors.onSurfaceVariant)),
      );

  Widget _issueRow(
      ThemeNotifier theme, WritingPreferences prefs, WritingIssue issue) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
            issue.kind == WritingIssueKind.spelling
                ? Icons.spellcheck
                : Icons.edit_note,
            size: 14,
            color: theme.colors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(issue.text,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 20, top: 2),
          child: Text(issue.message,
              style: TextStyle(
                  fontSize: 11, color: theme.colors.onSurfaceVariant)),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20, top: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var suggestion in issue.suggestions)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(suggestion, style: const TextStyle(fontSize: 12)),
                  onPressed: () => _apply(issue, suggestion),
                ),
              // The same two ways out the context menu offers, since the
              // panel is where someone works through a whole post and is
              // exactly where "stop telling me about this" belongs.
              if (issue.checkId != null)
                _dismissChip(
                    theme, "Turn off", () => prefs.disableCheck(issue.checkId!))
              else ...[
                _dismissChip(
                    theme, "Ignore", () => prefs.ignoreOnce(issue.text)),
                _dismissChip(theme, "Add to dictionary",
                    () => prefs.addToDictionary(issue.text)),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  Widget _dismissChip(ThemeNotifier theme, String label, VoidCallback onTap) =>
      ActionChip(
        visualDensity: VisualDensity.compact,
        backgroundColor: Colors.transparent,
        side: BorderSide(color: theme.colors.outlineVariant),
        label: Text(label,
            style:
                TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant)),
        onPressed: onTap,
      );

  /// _thesaurusRow shows the alternatives for whatever word is selected,
  /// laid out in the panel itself.
  ///
  /// Inline rather than behind a button: the sidebar is already the place
  /// where suggestions live, and making the user click through to a sheet
  /// for the one kind of suggestion that isn't listed there was a step for
  /// nothing. The lookup only runs while a word is actually selected, so an
  /// idle panel asks the provider nothing.
  Widget _thesaurusRow(BuildContext context, ThemeNotifier theme) {
    var thesaurus = context.read<ThesaurusCapability?>();
    if (thesaurus == null || !thesaurus.available) return const SizedBox();

    var selection =
        _editor?.selection ?? const TextSelection.collapsed(offset: -1);
    var text = _editor?.text ?? "";
    String? word;
    if (selection.isValid && !selection.isCollapsed) {
      word = ThesaurusCapability.normalizeWord(selection.textInside(text));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Divider(height: 16),
      if (word == null)
        Text("Select a word for alternatives.",
            style:
                TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant))
      else
        // Capped and scrollable in its own right: a common word can have
        // thirty alternatives, and the issue list above must not lose its
        // room to them.
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: SingleChildScrollView(
            child: FutureBuilder<ThesaurusEntry?>(
              // Keyed by the word so a new selection starts a new lookup
              // rather than showing the previous word's answer while it
              // loads.
              key: ValueKey(word),
              future: thesaurus.lookUp(word),
              builder: (context, snapshot) =>
                  _alternatives(theme, word!, selection, snapshot),
            ),
          ),
        ),
    ]);
  }

  Widget _alternatives(ThemeNotifier theme, String word,
      TextSelection selection, AsyncSnapshot<ThesaurusEntry?> snapshot) {
    var muted = TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant);

    if (snapshot.connectionState != ConnectionState.done) {
      return Text('Looking up "$word"...', style: muted);
    }
    var entry = snapshot.data;
    if (entry == null || entry.isEmpty) {
      return Text('No alternatives for "$word".', style: muted);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Alternatives for "$word"',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
      for (var sense in entry.senses) ...[
        if (sense.partOfSpeech.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(sense.partOfSpeech,
                style: muted.copyWith(fontStyle: FontStyle.italic)),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var synonym in sense.synonyms)
              ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(synonym, style: const TextStyle(fontSize: 12)),
                onPressed: () => _replaceSelection(selection, synonym),
              ),
            // Marked, because an opposite is never a like-for-like swap and
            // must not sit unlabelled among words that are.
            for (var antonym in sense.antonyms)
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(Icons.swap_horiz,
                    size: 14, color: theme.colors.onSurfaceVariant),
                label: Text(antonym, style: const TextStyle(fontSize: 12)),
                tooltip: "Opposite meaning",
                onPressed: () => _replaceSelection(selection, antonym),
              ),
          ],
        ),
      ],
    ]);
  }

  void _replaceSelection(TextSelection selection, String replacement) {
    var editor = _editor;
    if (editor == null) return;
    if (!selection.isValid || selection.end > editor.text.length) return;
    editor.value = TextEditingValue(
      text:
          editor.text.replaceRange(selection.start, selection.end, replacement),
      selection:
          TextSelection.collapsed(offset: selection.start + replacement.length),
    );
  }
}
