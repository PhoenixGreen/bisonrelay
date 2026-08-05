import 'package:bruig/plugin_system/capabilities/spellcheck.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// spellcheck_field.dart keeps a text field's underlines in step with what
// the checker currently says, rather than with whatever it happened to say
// when the field was last edited.
//
// Flutter only ever runs a spell check when the *text* changes. That is the
// right trigger for typing and the wrong one for everything else: a field
// created with text already in it -- a draft reopened, a reply being edited
// -- is never checked at all until someone touches it, and turning checking
// on leaves the text unmarked until the next keystroke. In both cases the
// feature looks broken while working exactly as designed.
//
// Wrapping a field in this fixes both. It watches the capability and, after
// each change, recomputes the results and hands them to the field directly,
// which is the same thing Flutter's own check does at the end of its
// asynchronous round trip.

/// SpellcheckedFieldScope refreshes the underlines of the text field beneath
/// it whenever the checker's answer would change.
///
/// It renders [child] unaltered and does nothing at all when no provider is
/// enabled, so a field can be wrapped unconditionally.
class SpellcheckedFieldScope extends StatefulWidget {
  final Widget child;
  const SpellcheckedFieldScope({required this.child, super.key});

  @override
  State<SpellcheckedFieldScope> createState() => _SpellcheckedFieldScopeState();
}

class _SpellcheckedFieldScopeState extends State<SpellcheckedFieldScope> {
  // _lastApplied is a cheap description of what the field was last given.
  // Recomputing is close to free, but assigning and rebuilding on every
  // notification would fight the user's typing, so the work only happens
  // when the answer has actually moved.
  String? _lastApplied;

  @override
  Widget build(BuildContext context) {
    var capability = context.watch<SpellcheckCapability?>();
    if (capability != null) {
      // After the frame: the field below has to exist before it can be
      // found, and on the first build it does not yet.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh(capability);
      });
    }
    return widget.child;
  }

  void _refresh(SpellcheckCapability capability) {
    var editable = _editableBelow(context);
    if (editable == null) return;

    var text = editable.textEditingValue.text;
    var issues = capability.review(text);
    var signature = "${capability.configuration != null}|$text|"
        "${issues.map((i) => "${i.range.start}-${i.range.end}").join(",")}";
    if (signature == _lastApplied) return;
    _lastApplied = signature;

    editable.spellCheckResults = SpellCheckResults(text, [
      for (var issue in issues) SuggestionSpan(issue.range, issue.suggestions),
    ]);
    // Assigning the results does not itself repaint: they are read while the
    // field builds its text, so the field has to be built again.
    setState(() {});
  }

  /// _editableBelow finds the EditableTextState this scope wraps.
  ///
  /// A field's own state is not reachable any other way: TextField builds
  /// the EditableText itself, so there is no key to hold on to. Walking the
  /// element tree is public API, and the walk stops at the first match,
  /// which for a scope wrapped around one field is that field.
  EditableTextState? _editableBelow(BuildContext context) {
    EditableTextState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is EditableTextState) {
        found = element.state as EditableTextState;
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }
}
