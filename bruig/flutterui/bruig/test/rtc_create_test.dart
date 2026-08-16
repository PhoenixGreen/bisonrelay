import 'package:bruig/screens/realtimechat/creatertc.dart';
import 'package:flutter_test/flutter_test.dart';

// rtc_create_test.dart covers the Create Realtime Chat Session screen
// refusing to make a session with no description.
//
// The rule and not the screen, because building the screen means building a
// ClientModel and a RealtimeChatModel, and constructing either loads
// golib.dylib -- the same reason header_label_test.dart keeps away from them.
// So the rule is a function of its own that the button, the message under the
// field and the check made on Create all ask, and it is that single answer
// which is pinned here.

void main() {
  test("a session must be named", () {
    expect(sessionDescriptionError("", isInstant: false),
        "A description is required");
    expect(sessionDescriptionError("Weekly call", isInstant: false), isNull);
  });

  // A name of three spaces is no name: the session list would show a blank
  // where the description goes.
  test("whitespace is not a name", () {
    expect(sessionDescriptionError("   ", isInstant: false),
        "A description is required");
    expect(sessionDescriptionError("\t\n ", isInstant: false),
        "A description is required");
  });

  test("surrounding space does not make a name valid on its own", () {
    expect(
        sessionDescriptionError("  Weekly call  ", isInstant: false), isNull);
  });

  // An instant call is one call to one person, removed as soon as everybody
  // leaves, and the screen shows it no description field at all -- so
  // requiring one would make the Call button permanently dead.
  test("an instant call needs no description", () {
    expect(sessionDescriptionError("", isInstant: true), isNull);
    expect(sessionDescriptionError("   ", isInstant: true), isNull);
  });
}
