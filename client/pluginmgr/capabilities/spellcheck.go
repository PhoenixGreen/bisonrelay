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

	// Category groups a rule for display -- "Capitalization", "Punctuation",
	// "Spelling". Optional; a provider that sends none leaves the UI to fall
	// back to Message alone.
	Category string `json:"category,omitempty"`

	// Explanation is a sentence saying what is wrong and why, for a reader
	// who does not already know. Message names the problem in a few words
	// and has to fit a menu row; this does not, and can afford to teach.
	Explanation string `json:"explanation,omitempty"`

	// Suggest is a replacement template that may reference Pattern's
	// capture groups as $1, $2, etc. An empty Suggest means the rule is
	// informational only (flagged, but with no proposed replacement).
	Suggest string `json:"suggest"`

	// Antipatterns are patterns that suppress this rule wherever they
	// match over it: the rule fires, and then does not, because the text
	// turned out to be one of the readings it is not about.
	//
	// The alternative is a negative lookahead glued onto Pattern, which
	// works and is worse in two ways. It is unreadable -- the exception
	// becomes punctuation at the end of an already dense expression -- and
	// it cannot be tested on its own, so nothing notices when an exception
	// stops matching what it was written for. It also puts the rule beyond
	// any regex engine without lookaround, which is how a provider's own
	// tests lose sight of exactly the rules that most need watching.
	//
	// Suppression only: an antipattern can take a match away and cannot
	// create one. A rule that needs *context* to fire still has to say so in
	// Pattern.
	Antipatterns []string `json:"antipatterns,omitempty"`

	// Severity separates a mistake from an opinion: "error" (the default when
	// empty) for text that is wrong whatever the writer meant, "suggestion"
	// for a rewrite that is usually an improvement and sometimes not.
	//
	// The UI underlines the two in different colours and lists them apart,
	// which is what makes an opinionated ruleset bearable: wordiness and
	// cliche rules would otherwise put the same alarming mark under correct
	// writing as a misspelling, and teach people to ignore both.
	Severity string `json:"severity,omitempty"`
}

// Language is one language a spellcheck-data provider can check against.
type Language struct {
	Code string `json:"code"`
	Name string `json:"name"`
}

// AnalysisCheck is a check a regex cannot express because it has to count or
// compare across a whole message: how often a word is used, how long a
// sentence runs, whether two spellings of one word are mixed.
//
// Unlike GrammarRule, the provider does not supply the logic -- there is no
// pattern to send. It names one of the checks the client knows how to run and
// supplies everything else about it: the threshold, what to call it, and how
// to explain it. That keeps the ruleset the provider's to decide while the
// mechanics stay client-side, exactly as they already are for the regexes,
// which the provider also writes but never executes.
type AnalysisCheck struct {
	// ID names the check. The client ignores an ID it does not implement,
	// which is what lets a provider ship a check ahead of the client that
	// runs it.
	ID string `json:"id"`

	// Threshold is the number the check fires at, in whatever unit that check
	// counts -- occurrences, words, consecutive sentences.
	Threshold int `json:"threshold,omitempty"`

	// Message names the problem. It may reference $1 (what the check is
	// about, such as the repeated word) and $2 (the count that tripped it).
	Message string `json:"message"`

	Category    string `json:"category,omitempty"`
	Explanation string `json:"explanation,omitempty"`

	// Severity is read as on GrammarRule; these checks are usually
	// suggestions.
	Severity string `json:"severity,omitempty"`

	// Values is data the named check needs, in a form only that check
	// defines. The spelling-variant check reads pairs written "colour|color";
	// the counting checks need none.
	Values []string `json:"values,omitempty"`
}

// SpellcheckData is the wordlist and grammar rules one spellcheck-data
// plugin supplies, and -- once merged across every enabled such plugin --
// what the client hands to the composer UI.
//
// Nothing here is executed on this side. The client hands the whole payload
// to the UI, which owns every mechanism: the regex engine, the edit-distance
// ranking and the counting checks. A provider decides *what* is checked and
// never *how*, which is why a plugin needs no code running in the app.
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

	// Language is the language Words is for, which need not be the one that
	// was asked for: a provider without it answers in whatever it has and
	// says so, rather than returning nothing.
	Language string `json:"language,omitempty"`

	// Languages is every language the providers between them can serve, so
	// the UI can offer the choice without knowing in advance what is on
	// offer. Deduplicated by code across providers.
	Languages []Language `json:"languages,omitempty"`

	GrammarRules []GrammarRule `json:"grammarRules"`

	// AnalysisChecks are the checks that count rather than match. Older
	// providers send none.
	AnalysisChecks []AnalysisCheck `json:"analysisChecks,omitempty"`
}

// MergedSpellcheckData gathers get_spellcheck_data for [language] from every
// enabled spellcheck-data plugin and merges them: words deduplicated (first plugin
// to supply a word wins its casing), grammar rules concatenated in plugin-id
// order. A single plugin's failure -- typically one that hasn't finished
// loading -- is logged and skipped rather than failing the whole result,
// since a partial word list is still useful.
func MergedSpellcheckData(ctx context.Context, mgr Manager, rt Runtime,
	log slog.Logger, language string) SpellcheckData {

	var merged SpellcheckData
	seen := make(map[string]bool)
	seenLanguage := make(map[string]bool)
	for _, manifest := range mgr.PluginsProviding(pluginmgr.ServiceSpellcheckData) {
		export, _ := manifest.ServiceExport(pluginmgr.ServiceSpellcheckData)
		var data SpellcheckData
		arg := []byte(language)
		if err := call(ctx, rt, manifest.ID, export, arg, 0, &data); err != nil {
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
		merged.AnalysisChecks = append(merged.AnalysisChecks, data.AnalysisChecks...)

		// The first provider to answer names the language, since its words
		// are the ones that landed first and set the tone for the merge.
		if merged.Language == "" {
			merged.Language = data.Language
		}
		for _, l := range data.Languages {
			if l.Code == "" || seenLanguage[l.Code] {
				continue
			}
			seenLanguage[l.Code] = true
			merged.Languages = append(merged.Languages, l)
		}
	}
	return merged
}
