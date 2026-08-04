// PluginCapability is a headless service a plugin can offer the app: not a
// screen of its own, but data or behaviour that flows into somewhere Bison
// Relay already draws.
//
// Each value is a contract, not a plugin. Any number of plugins may declare
// the same capability (their results are combined by the Go side -- see
// client/pluginmgr/capabilities), and the app's own code is written against
// the capability, never against whichever plugin happens to be providing it.
// That is what lets a plugin be uninstalled without leaving a dangling
// reference anywhere in the app.
enum PluginCapability {
  // linkCard turns a bare URL into a preview card. See capabilities/
  // link_card.dart for what the app does with one.
  linkCard("link-card"),

  // spellcheckData supplies a wordlist and grammar rules for the text
  // composers. See capabilities/spellcheck.dart.
  spellcheckData("spellcheck-data");

  // wireName is the string a manifest declares and the Go side validates
  // against. Kept explicit rather than derived from the enum name so that
  // renaming a value here can never silently invalidate installed plugins.
  final String wireName;

  const PluginCapability(this.wireName);
}
