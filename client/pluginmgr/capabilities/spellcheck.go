package capabilities

import (
	"context"

	"github.com/companyzero/bisonrelay/client/pluginmgr"
	"github.com/decred/slog"
)

// spellcheckExport is the function a pluginmgr.CapabilitySpellcheckData
// plugin must export. It takes no arguments and returns SpellcheckData.
const spellcheckExport = "get_spellcheck_data"

// GrammarRule is a single regex-based writing-style check, supplied verbatim
// (never compiled or executed by Go) by a spellcheck-data plugin.
// Pattern/Suggest are executed client-side in Dart, whose regex engine
// (unlike Go's RE2) supports the backreferences needed to express checks
// like "repeated word" (`\b(\w+)\s+\1\b`).
type GrammarRule struct {
	Pattern string `json:"pattern"`
	Message string `json:"message"`
	// Suggest is a replacement template that may reference Pattern's
	// capture groups as $1, $2, etc. An empty Suggest means the rule is
	// informational only (flagged, but with no proposed replacement).
	Suggest string `json:"suggest"`
}

// SpellcheckData is the wordlist and grammar rules one spellcheck-data
// plugin supplies, and -- once merged across every enabled such plugin --
// what the client hands to the composer UI.
type SpellcheckData struct {
	Words []string `json:"words"`

	// CommonWords is a subset of Words ordered most-common-first, used to
	// rank corrections. It may be empty, and older providers will not send
	// it at all.
	//
	// It exists because edit distance cannot rank on its own: "teh" is one
	// typo away from "the", "tech", "meh", "th" and "te" alike, and with only
	// a handful of corrections shown, the word anyone actually meant ends up
	// buried among words nobody writes. Knowing which are common is what
	// separates them.
	CommonWords []string `json:"commonWords,omitempty"`

	GrammarRules []GrammarRule `json:"grammarRules"`
}

// MergedSpellcheckData gathers get_spellcheck_data from every enabled
// spellcheck-data plugin and merges them: words deduplicated (first plugin
// to supply a word wins its casing), grammar rules concatenated in plugin-id
// order. A single plugin's failure -- typically one that hasn't finished
// loading -- is logged and skipped rather than failing the whole result,
// since a partial word list is still useful.
func MergedSpellcheckData(ctx context.Context, mgr Manager, rt Runtime,
	log slog.Logger) SpellcheckData {

	var merged SpellcheckData
	seen := make(map[string]bool)
	for _, manifest := range mgr.PluginsWithCapability(pluginmgr.CapabilitySpellcheckData) {
		var data SpellcheckData
		if err := call(ctx, rt, manifest.ID, spellcheckExport, nil, 0, &data); err != nil {
			logf(log, "capabilities: unable to get spellcheck data from %s: %v",
				manifest.ID, err)
			continue
		}
		for _, w := range data.Words {
			if seen[w] {
				continue
			}
			seen[w] = true
			merged.Words = append(merged.Words, w)
		}
		// Ranked lists are concatenated in plugin-id order rather than
		// interleaved: two providers' rankings are not comparable, so the
		// first one's ordering is kept intact and the next appends behind it.
		merged.CommonWords = append(merged.CommonWords, data.CommonWords...)
		merged.GrammarRules = append(merged.GrammarRules, data.GrammarRules...)
	}
	return merged
}
