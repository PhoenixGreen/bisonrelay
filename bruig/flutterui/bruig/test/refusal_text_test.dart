import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/screens/pages/browser.dart';
import 'package:flutter_test/flutter_test.dart';

// refusal_text_test.dart covers what a refusing client is allowed to say.
//
// A refusal used to be shown as "could not make sense of the request", which
// is true and useless: the other side often knows exactly what is wrong --
// "something in your cart is no longer sold" -- and that is a thing the
// reader can go and fix.
//
// It is also somebody else's text, arriving over the wire, going straight
// onto the screen. So it is bounded: short and single-line or not shown,
// because a stack trace or half a template where a sentence belongs is worse
// than the plain wording it replaces.

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('a short sentence is shown', () {
    expect(refusalText(bytes("Your cart holds something no longer sold.")),
        "Your cart holds something no longer sold.");
  });

  test('nothing at all is nothing', () {
    expect(refusalText(null), "");
    expect(refusalText(bytes("")), "");
    expect(refusalText(bytes("   ")), "");
  });

  test('many lines are not a sentence', () {
    // A stack trace, or a template that failed halfway.
    expect(refusalText(bytes("panic: nope\n\tat foo.go:12")), "");
  });

  test('a long one is not either', () {
    expect(refusalText(bytes("x" * 500)), "");
  });

  test('the boundary is where it says it is', () {
    expect(refusalText(bytes("y" * 200)), "y" * 200);
    expect(refusalText(bytes("y" * 201)), "");
  });

  test('bytes that are not text are not shown', () {
    expect(refusalText(Uint8List.fromList([0xff, 0xfe, 0xfd])), "");
  });

  test('surrounding space is trimmed rather than shown', () {
    expect(refusalText(bytes("  Out of stock.  ")), "Out of stock.");
  });
}
