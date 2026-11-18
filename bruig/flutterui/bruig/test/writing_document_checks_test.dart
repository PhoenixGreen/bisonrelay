import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/plugin_test_support.dart';

// writing_document_checks_test.dart covers turning a check off in one
// document rather than everywhere.
//
// Some rules are right for one piece of writing and wrong for the next: two
// spaces after a full stop is a slip in a post and the house style of
// somebody's manuscript. "Off" that could only mean everywhere made those a
// setting to be changed back and forth by hand.

const _spaces = r"[ ]{2,}";
const _dictionary = ["the", "payment", "cleared"];
final _rules = [GrammarRule(_spaces, "Multiple spaces", " ")];

Future<SpellcheckCapability> _capability(WritingPreferences prefs) async {
  var capability = SpellcheckCapability(
      fetch: (_) async => SpellcheckData(_dictionary, const [], _rules),
      prefs: prefs);
  await capability.update(FakePlugins({PluginCapability.spellcheckData}));
  return capability;
}

const _text = "The payment  cleared";

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test("a check turned off in one document is still on in the next", () async {
    var prefs = WritingPreferences();
    var capability = await _capability(prefs);

    prefs.document = "Drafts/Manuscript";
    expect(capability.review(_text), hasLength(1));
    await prefs.disableCheckHere(_spaces, description: "Multiple spaces");
    expect(capability.review(_text), isEmpty,
        reason: "off here, and the field re-checks without being asked");

    prefs.document = "Drafts/Blog post";
    expect(capability.review(_text), hasLength(1),
        reason: "another document never made that choice");

    prefs.document = null;
    expect(capability.review(_text), hasLength(1),
        reason: "nor did a chat message, which is no document at all");

    prefs.document = "Drafts/Manuscript";
    expect(capability.review(_text), isEmpty);
    expect(prefs.disabledChecks, isEmpty,
        reason: "nothing was turned off everywhere");
  });

  test("off everywhere is off in every document", () async {
    var prefs = WritingPreferences();
    var capability = await _capability(prefs);
    await prefs.disableCheck(_spaces);
    prefs.document = "Drafts/Manuscript";
    expect(capability.review(_text), isEmpty);
    prefs.document = null;
    expect(capability.review(_text), isEmpty);
  });

  test("with no document open there is no \"here\" to turn it off in",
      () async {
    var prefs = WritingPreferences();
    var capability = await _capability(prefs);
    await prefs.disableCheckHere(_spaces);
    expect(capability.review(_text), hasLength(1));
    expect(prefs.allDocumentChecks, isEmpty);
  });

  test("it can be turned back on, here or from the settings page", () async {
    var prefs = WritingPreferences()..document = "Drafts/Manuscript";
    var capability = await _capability(prefs);
    await prefs.disableCheckHere(_spaces, description: "Multiple spaces");
    expect(prefs.documentDisabledChecks, {_spaces: "Multiple spaces"});

    await prefs.enableCheckHere(_spaces);
    expect(capability.review(_text), hasLength(1));
    expect(prefs.allDocumentChecks, isEmpty,
        reason: "a document with nothing left turned off is not listed");

    // From Settings, where no document is open and the one meant is named.
    await prefs.disableCheckHere(_spaces);
    prefs.document = null;
    await prefs.enableCheckHere(_spaces, document: "Drafts/Manuscript");
    expect(prefs.allDocumentChecks, isEmpty);
  });

  test("the choice survives a restart", () async {
    var prefs = WritingPreferences()..document = "Drafts/Manuscript";
    await prefs.disableCheckHere(_spaces, description: "Multiple spaces");

    var restarted = WritingPreferences();
    await restarted.load();
    expect(restarted.allDocumentChecks, {
      "Drafts/Manuscript": {_spaces: "Multiple spaces"},
    });
    var capability = await _capability(restarted);
    expect(capability.review(_text), hasLength(1),
        reason: "which document is open is not remembered, only its choices");
    restarted.document = "Drafts/Manuscript";
    expect(capability.review(_text), isEmpty);
  });

  test("the choice follows a document that is renamed or moved", () async {
    var prefs = WritingPreferences()..document = "Drafts/Manuscript";
    var capability = await _capability(prefs);
    await prefs.disableCheckHere(_spaces);

    await prefs.documentMoved("Drafts/Manuscript", "Drafts/Novel");
    expect(prefs.document, "Drafts/Novel",
        reason: "the open document is the one that was renamed");
    expect(capability.review(_text), isEmpty);
    expect(prefs.allDocumentChecks.keys, ["Drafts/Novel"]);

    // A folder renamed takes everything in it along.
    await prefs.documentMoved("Drafts/", "Books/");
    expect(prefs.allDocumentChecks.keys, ["Books/Novel"]);
    expect(prefs.document, "Books/Novel");
    expect(capability.review(_text), isEmpty);
  });

  test("a deleted document's choices go with it", () async {
    var prefs = WritingPreferences()..document = "Drafts/Manuscript";
    await prefs.disableCheckHere(_spaces);
    prefs.document = "Drafts/Other";
    await prefs.disableCheckHere(_spaces);

    await prefs.documentDeleted("Drafts/Manuscript");
    expect(prefs.allDocumentChecks.keys, ["Drafts/Other"]);
    // A new document under the old name starts with none.
    var capability = await _capability(prefs);
    prefs.document = "Drafts/Manuscript";
    expect(capability.review(_text), hasLength(1));

    await prefs.documentDeleted("Drafts/");
    expect(prefs.allDocumentChecks, isEmpty);
  });
}
