// Package builtin embeds the manifests of plugins bundled with the app
// itself, so they are installed automatically on first run without
// requiring the user to manually import them.
package builtin

import "embed"

//go:embed prettylinks/manifest.json
var fs embed.FS

//go:embed spellcheck/manifest.json spellcheck/words.txt
var spellcheckFS embed.FS

// PrettyLinksManifestJSON returns the raw manifest.json contents of the
// bundled "Pretty Links" plugin.
func PrettyLinksManifestJSON() ([]byte, error) {
	return fs.ReadFile("prettylinks/manifest.json")
}

// SpellcheckManifestJSON returns the raw manifest.json contents of the
// bundled "Spell Check" plugin.
func SpellcheckManifestJSON() ([]byte, error) {
	return spellcheckFS.ReadFile("spellcheck/manifest.json")
}

// SpellcheckWordsTXT returns the raw wordlist contents of the bundled
// "Spell Check" plugin.
func SpellcheckWordsTXT() ([]byte, error) {
	return spellcheckFS.ReadFile("spellcheck/words.txt")
}
