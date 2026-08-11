// PluginCapability names a headless service THIS APP knows how to consume:
// not a screen of its own, but data or behaviour that flows into somewhere
// Bison Relay already draws.
//
// It is emphatically not the set of services a plugin may provide. A plugin
// declares any service name it likes and the host routes to it without
// knowing what it means -- there is no allowlist on either side of the
// boundary any more. This enum is the much smaller list of names the app
// itself asks for, and adding to it is a statement about what the app
// consumes rather than permission for anyone to publish.
//
// Each value is a contract, not a plugin. Any number of plugins may provide
// the same service (their results are combined by the Go side -- see
// client/pluginmgr/capabilities), and the app's own code is written against
// the service, never against whichever plugin happens to be providing it.
// That is what lets a plugin be uninstalled without leaving a dangling
// reference anywhere in the app.
enum PluginCapability {
  // linkCard turns a bare URL into a preview card. See capabilities/
  // link_card.dart for what the app does with one.
  linkCard("link-card"),

  // spellcheckData supplies a wordlist and grammar rules for the text
  // composers. See capabilities/spellcheck.dart.
  spellcheckData("spellcheck-data"),

  // thesaurus answers "what else could I have said here" for one word.
  // Unlike the two above it is asked on demand rather than supplying data up
  // front, because a thesaurus is far too large to hand over wholesale. See
  // capabilities/thesaurus.dart.
  thesaurus("thesaurus");

  // wireName is the string a manifest declares. Kept explicit rather than
  // derived from the enum name so that renaming a value here can never
  // silently stop matching the plugins already installed.
  final String wireName;

  const PluginCapability(this.wireName);
}
