part of 'speech_device.dart';

// The script: typed as text or read from a Writing document, set out in
// sections, each with its takes' slots, and the palette of direction and cues
// under it. Part of _SpeechDeviceState: its fields, lifecycle and build are in
// speech_device.dart.

extension _SpeechScript on _SpeechDeviceState {
  /// _cue puts [cue] into the script where the text cursor is.
  void _cue(SpeechSpec spec, SpeechCue cue) {
    var text = _script.text;
    var sel = _script.selection;
    var at = sel.isValid ? sel.start : text.length;
    var before = text.substring(0, at);
    var token =
        "${before.isEmpty || before.endsWith(" ") ? "" : " "}${cue.token} ";
    var next = before + token + text.substring(sel.isValid ? sel.end : at);
    _script.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: at + token.length));
    _set(spec.withScript(next));
  }

  /// _pickDocument reads the script from a Writing document ([again]
  /// rereads it), keeping the typed script.
  Future<void> _pickDocument(SpeechSpec spec, {bool again = false}) async {
    var picked = await pickLibraryDocument(context);
    if (picked == null || !mounted) return;
    _set(spec.copyWith(
        document: again
            ? spec.document.copyWith(folder: picked.folder, name: picked.name)
            : picked.copyWith(wasText: spec.script)));
    await refreshTextDocuments(c);
  }

  /// _scriptText is the script as text to edit.
  Widget _scriptText(_SpeechView view) {
    var spec = view.spec, k = view.k, reading = view.reading;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: TextField(
          key: const ValueKey("speechScript"),
          controller: _script,
          focusNode: _scriptFocus,
          // Read from a document: changed there.
          readOnly: reading,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: k.text(12.5, height: 1.5),
          decoration: k.field(
              "What is to be said. Each line is a section, spoken in one go: "
              "start a new line only where it is said another way. A "
              "direction goes first, in [brackets] -- [warm], [sad] -- and "
              "cues anywhere: [pause 0.5], [laugh]."),
          onChanged: (v) {
            _asText ??= true;
            c.beginInteraction();
            _set(spec.withScript(v), transient: true);
          },
        ),
      ),
    ]);
  }

  /// _lineState is what a section says of itself: speaking, waiting, or
  /// its take's length.
  String _lineState(_SpeechView view, SpeechLine l) {
    var needsVoices = view.needsVoices;
    switch (c.speechLineState(widget.channel, l)) {
      case "speaking":
        return "Speaking…";
      case "waiting":
        return "Waiting";
    }
    var t = l.take;
    if (t == null) return needsVoices ? "" : "Not spoken yet";
    return "${t.length.toStringAsFixed(1)} s";
  }

  /// A slot, A to C: picked, its take is the one "Add all lines" uses and
  /// its actions are in the line panel.
  Widget _slotButton(_SpeechView view, int i, SpeechLine l, int t, {Key? key}) {
    var k = view.k;
    var take = l.slot(t);
    var picked = i == _line && (_slot ?? l.chosen) == t;
    return k.take(
        String.fromCharCode(65 + t),
        take != null && t == l.chosen,
        () => setState(() {
              _line = i;
              _slot = t;
              if (take != null) c.chooseTake(widget.channel, i, t);
            }),
        key: key,
        empty: take == null,
        picked: picked,
        working: c.speechReplacing(widget.channel, l) == t);
  }

  /// _lineCard is section [i] in the list: its words, direction, state and
  /// slots; pressed, it is picked.
  Widget _lineCard(_SpeechView view, int i, SpeechLine l) {
    var k = view.k, s = view.s;
    var on = i == _line;
    var state = c.speechLineState(widget.channel, l);
    var direction = l.own.isNotEmpty
        ? "“${l.own}”"
        : l.direction == SpeechDirection.plain
            ? ""
            : l.direction.label;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: on ? s.solo.withValues(alpha: 0.14) : s.strip,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
            side:
                BorderSide(color: on ? s.solo : s.edge.withValues(alpha: 0.6))),
        child: InkWell(
          key: ValueKey("speechLine-$i"),
          borderRadius: BorderRadius.circular(5),
          onTap: () => _pickLine(i),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
            child: Row(children: [
              SizedBox(
                width: 18,
                child: Text("${i + 1}", style: k.mono(10, colour: s.muted)),
              ),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(k.cued(l.text),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: k.text(12.5, height: 1.35)),
                      const SizedBox(height: 3),
                      Row(children: [
                        if (direction.isNotEmpty) ...[
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 1),
                              decoration: BoxDecoration(
                                  color: s.on.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(9)),
                              child: Text(direction,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: k.text(10, colour: s.on)),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(_lineState(view, l),
                            style: k.text(10,
                                colour: state == "speaking" ? s.on : s.muted)),
                      ]),
                    ]),
              ),
              // The slots, A to C, always: greyed while not in use.
              for (var t = 0; t < SpeechLine.speechSlots; t++)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: _slotButton(view, i, l, t,
                      key: ValueKey("speechTake-$i-$t")),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  /// _scriptLines is the script in sections, one card each.
  Widget _scriptLines(_SpeechView view) {
    var k = view.k, s = view.s, lines = view.lines;
    return lines.isEmpty
        ? Center(
            child: Text("No sections yet: Edit as text, and write the script.",
                style: k.text(11, colour: s.muted)))
        : ListView(
            key: const ValueKey("speechLines"),
            padding: EdgeInsets.zero,
            children: [for (var (i, l) in lines.indexed) _lineCard(view, i, l)],
          );
  }

  /// One palette under the script for the direction of the section the
  /// cursor is in, and the cues, put at the cursor.
  Widget _palette(_SpeechView view) {
    var spec = view.spec,
        k = view.k,
        s = view.s,
        engine = view.engine,
        local = view.local,
        line = view.line,
        asText = view.asText,
        reading = view.reading;
    var l = line;
    var editable = l != null && !reading;
    var said = l == null
        ? SpeechDirection.plain
        : l.own.isNotEmpty
            ? null
            : l.direction;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: k.box(s.inset),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(
              width: 78,
              child: k.label(l == null ? "Said" : "Section ${_line + 1}")),
          SizedBox(
            width: 150,
            child: k.dropdown<SpeechDirection?>(
              key: const ValueKey("speechSaid"),
              value: said,
              items: [
                // Those the engine can say, and the section's
                // own as set even if another engine is picked.
                for (var d in SpeechDirection.values)
                  if (engine.directs(d) || d == said) (d, d.label),
                if (said == null) (null, "In your own words"),
              ],
              onChanged: (d) {
                if (d == null || !editable) return;
                _changeLine(spec, _line, l.copyWith(direction: d, own: ""));
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              height: 26,
              child: TextField(
                key: const ValueKey("speechOwn"),
                controller: _own,
                focusNode: _ownFocus,
                readOnly: !editable,
                style: k.text(11.5),
                decoration: k.field(
                    local ? "Own words: Expressive" : "Or own words",
                    lines: 1),
                onSubmitted: (_) => _keepOwn(),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 5),
        Row(children: [
          SizedBox(width: 78, child: k.label("Add here")),
          Expanded(
            // One row, scrolled sideways where it is too long for it.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var cue in engine.cues)
                  Tooltip(
                    message: asText
                        ? "Put in ${cue.token} at the cursor"
                        : "Put in ${cue.token} at the end of the section",
                    child: k.chip(
                        cue.label,
                        false,
                        reading
                            ? null
                            : asText
                                ? () => _cue(spec, cue)
                                : editable
                                    ? () => _changeLine(
                                        spec,
                                        _line,
                                        l.copyWith(
                                            text: "${l.text} ${cue.token}"))
                                    : null,
                        key: ValueKey("speechCue-${cue.name}"),
                        icon: _cueIcons[cue]),
                  ),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  /// Where the script comes from: typed here, or a Writing document.
  Widget _scriptColumn(_SpeechView view,
      {required Widget scriptText, required Widget scriptLines}) {
    var spec = view.spec,
        k = view.k,
        asText = view.asText,
        reading = view.reading;
    var fromItems = <(String, String)>[
      ("typed", "Typed here"),
      if (reading) ("document", spec.document.says),
      ("pick", reading ? "Another document…" : "A Writing document…"),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: k.label(asText ? "Script" : "Sections")),
        // Narrowed, rather than overflowing, where the column is narrow.
        Flexible(
          flex: 2,
          child: k.button(asText ? "Show as sections" : "Edit as text", () {
            _scriptFocus.unfocus();
            setState(() => _asText = !asText);
          }, key: const ValueKey("speechAsText"), small: true),
        ),
        const SizedBox(width: 8),
        Flexible(child: k.label("From")),
        const SizedBox(width: 5),
        Flexible(
          flex: 3,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: k.dropdown<String>(
              key: const ValueKey("speechFromDocument"),
              value: reading ? "document" : "typed",
              items: fromItems,
              itemKeys: {
                if (reading) "document": const ValueKey("speechDocument")
              },
              onChanged: (v) {
                if (v == "typed" && reading) {
                  // What was typed before, given back.
                  _set(spec
                      .withScript(spec.document.wasText)
                      .copyWith(document: const TextDocumentRef()));
                } else if (v == "pick") {
                  _pickDocument(spec, again: reading);
                }
              },
            ),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      Expanded(child: asText ? scriptText : scriptLines),
      const SizedBox(height: 6),
      _palette(view),
    ]);
  }
}
