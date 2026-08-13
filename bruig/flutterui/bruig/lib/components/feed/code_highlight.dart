import 'package:flutter/material.dart';

// code_highlight.dart colours the inside of a fenced code block.
//
// Deliberately one small tokenizer rather than a grammar per language. A
// fenced block reaches the renderer as plain text -- whatever was written
// after the opening backticks is consumed by the markdown parser and never
// reaches the builder -- so there is nothing to choose a grammar with, and a
// highlighter that guessed the language would be wrong about as often as it
// was right.
//
// What is left is the part every language in common use agrees on: quoted
// strings, comments, numbers, and a short list of words that are keywords in
// nearly all of them. That is enough for a reader to find their way around a
// snippet, which is what highlighting in a *post* is for. It is not an IDE.

/// _keywords are words that are a keyword in most C-family and scripting
/// languages. Kept short on purpose: a word that is a keyword in one
/// language and an ordinary identifier in another is worse coloured than
/// left alone.
const _keywords = {
  "abstract", "as", "async", "await", "break", "case", "catch", "class",
  "const", "continue", "def", "default", "do", "else", "enum", "export",
  "extends", "final", "finally", "for", "from", "func", "function", "go",
  "if", "implements", "import", "in", "interface", "let", "new", "package",
  "private", "protected", "public", "return", "static", "struct", "switch",
  "this", "throw", "try", "type", "var", "void", "while", "with", "yield",
  "true", "false", "null", "nil", "None", "self", "fn", "impl", "match",
  "pub", "use", "mut", "elif", "lambda", "not", "and", "or", "is",
};

/// CodeInk is the four colours a highlighted block is drawn in.
///
/// Derived from the theme rather than fixed, so a block looks like it
/// belongs to the post it is in -- see markdownCodeInk.
class CodeInk {
  final Color text;
  final Color comment;
  final Color string;
  final Color number;
  final Color keyword;
  const CodeInk({
    required this.text,
    required this.comment,
    required this.string,
    required this.number,
    required this.keyword,
  });
}

/// _Kind is what a run of characters turned out to be.
enum _Kind { text, comment, string, number, keyword }

/// highlightCode splits [code] into coloured runs.
///
/// One pass, left to right, longest match first. Comments and strings are
/// taken whole the moment they open, so a keyword inside a string or a
/// quote inside a comment is left as part of it rather than being coloured
/// on its own -- which is the mistake that makes naive highlighting look
/// broken.
List<TextSpan> highlightCode(String code, CodeInk ink, TextStyle? base) {
  TextStyle styleFor(_Kind kind) {
    var color = switch (kind) {
      _Kind.text => ink.text,
      _Kind.comment => ink.comment,
      _Kind.string => ink.string,
      _Kind.number => ink.number,
      _Kind.keyword => ink.keyword,
    };
    var style = (base ?? const TextStyle()).copyWith(color: color);
    return kind == _Kind.comment
        ? style.copyWith(fontStyle: FontStyle.italic)
        : style;
  }

  var spans = <TextSpan>[];
  var buffer = StringBuffer();
  var i = 0;

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(TextSpan(text: buffer.toString(), style: styleFor(_Kind.text)));
    buffer.clear();
  }

  void emit(String text, _Kind kind) {
    flush();
    spans.add(TextSpan(text: text, style: styleFor(kind)));
  }

  bool startsWith(String s) => code.startsWith(s, i);

  while (i < code.length) {
    var c = code[i];

    // A line comment runs to the end of the line. `#` only at the start of
    // one, so a colour like #ff0000 or a Dart string interpolation is not
    // mistaken for a comment.
    var lineComment = startsWith("//") ||
        startsWith("--") ||
        (c == "#" && (i == 0 || code[i - 1] == "\n"));
    if (lineComment) {
      var end = code.indexOf("\n", i);
      if (end < 0) end = code.length;
      emit(code.substring(i, end), _Kind.comment);
      i = end;
      continue;
    }

    // A block comment runs to its terminator, or to the end if it is never
    // closed -- an unterminated one is still a comment to the reader.
    if (startsWith("/*")) {
      var end = code.indexOf("*/", i + 2);
      end = end < 0 ? code.length : end + 2;
      emit(code.substring(i, end), _Kind.comment);
      i = end;
      continue;
    }

    // A quoted string, up to the matching quote on the same line. Bounded
    // to the line because an unclosed quote should colour one line, not the
    // rest of the block.
    if (c == '"' || c == "'" || c == "`") {
      var j = i + 1;
      while (j < code.length && code[j] != c && code[j] != "\n") {
        if (code[j] == r"\" && j + 1 < code.length) j++;
        j++;
      }
      var end = j < code.length && code[j] == c ? j + 1 : j;
      emit(code.substring(i, end), _Kind.string);
      i = end;
      continue;
    }

    // A number, including a hex literal and a decimal point.
    if (_isDigit(c)) {
      var j = i;
      while (j < code.length && (_isWordChar(code[j]) || code[j] == ".")) {
        j++;
      }
      emit(code.substring(i, j), _Kind.number);
      i = j;
      continue;
    }

    // A word, which is a keyword or is not.
    if (_isWordStart(c)) {
      var j = i;
      while (j < code.length && _isWordChar(code[j])) {
        j++;
      }
      var word = code.substring(i, j);
      if (_keywords.contains(word)) {
        emit(word, _Kind.keyword);
      } else {
        buffer.write(word);
      }
      i = j;
      continue;
    }

    buffer.write(c);
    i++;
  }
  flush();
  return spans;
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

bool _isWordStart(String c) {
  var u = c.codeUnitAt(0);
  return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || c == "_" || c == r"$";
}

bool _isWordChar(String c) => _isWordStart(c) || _isDigit(c);
