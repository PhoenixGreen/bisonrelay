package spellcheck

// schema.go is the spellcheck-data capability's wire format, and nothing else.
//
// Every type here mirrors the JSON the app decodes exactly. This plugin is a
// separate Go module and deliberately takes no dependency on Bison Relay to
// get them, so the two definitions are kept in step by hand -- which is much
// easier to do when they are in one short file rather than spread through the
// rules that happen to use them.

// SeveritySuggestion marks a rule or a check as an opinion rather than a
// mistake. Spelled out here rather than as a bare string at every rule so a
// typo in it -- which would silently promote a suggestion to an error -- cannot
// happen.
const SeveritySuggestion = "suggestion"

// SeverityCheck marks a rule as a question rather than a finding: the text is
// spelled correctly and reads correctly, and the rule's claim is only that
// this is one of the pairs people confuse and the sentence does not settle
// which was meant.
//
// The third severity exists because the other two could not carry these. An
// error must never fire on correct writing, which is why "It would brake the
// system" goes unflagged today -- no rule can catch it without also catching
// "he had to brake". A suggestion says the writing could be better, which is
// not the claim either: nothing about the phrasing is at fault if "brake" was
// the word meant.
//
// What the app does with it: lists the issue on the Suggestions and Checks
// page beside the style rules, underlines it in amber rather than red or
// blue, and offers "Correct Usage" -- the answer that only makes sense for a
// question, and the one that makes a check tolerable to a writer who had it
// right. See rules_checks.go for what a rule in this tier owes its reader.
const SeverityCheck = "check"

// GrammarRule is one regex-based writing check. It mirrors the
// spellcheck-data capability's JSON schema exactly; this plugin is a
// separate Go module and deliberately takes no dependency on Bison Relay to
// get it.
type GrammarRule struct {
	// Pattern is a regular expression in Dart's dialect.
	Pattern string `json:"pattern"`
	// Message names the problem, for the suggestion menu.
	Message string `json:"message"`
	// Suggest is the replacement, which may reference Pattern's capture
	// groups as $1, $2 and so on. Empty means the rule only flags the text
	// and proposes nothing -- correct when there is no single right fix.
	Suggest string `json:"suggest"`

	// Alternatives are further replacements, offered after Suggest and in
	// this order. Empty for the rules with one answer, which is nearly all of
	// them.
	//
	// Added for the questions with two right answers, which the check tier
	// is full of. "Hi Sarah thanks for the notes" wants either "Hi Sarah,"
	// or "Hi, Sarah," depending on how formal the writer is being, and a
	// checker that picks one of those for the reader is wrong half the time
	// while looking certain. The same is true of a bare "which", where the
	// choice is a comma or a "that".
	//
	// Not a replacement for Suggest: the first answer is the one the rule
	// leads with, and keeping it a field of its own means every rule that
	// has one answer says so by having nothing here.
	Alternatives []string `json:"alternatives,omitempty"`

	// Category groups the rule for display: "Spacing", "Punctuation",
	// "Capitalization", "Grammar", "Confused words", "Style".
	Category string `json:"category,omitempty"`

	// Explanation says what is wrong and why, for a reader who does not
	// already know -- which is the point of showing it. Message has to fit a
	// menu row and can only name the problem; this does not, and so is where
	// the rule earns its keep for anyone still learning the distinction.
	//
	// Written for the reader, not the implementer: it explains the English,
	// never the regex.
	Explanation string `json:"explanation,omitempty"`

	// Antipatterns suppress this rule wherever they match over it: the rule
	// fires, and then does not, because the text turned out to be one of the
	// readings it is not about.
	//
	// Preferred to a negative lookahead on Pattern, which works and is worse
	// in three ways. It is unreadable -- the exception becomes punctuation
	// on the end of an already dense expression. It cannot be tested on its
	// own, so nothing notices when it stops matching what it was written
	// for. And it puts the rule beyond Go's RE2, which is how the corpus in
	// spellcheck_test.go loses sight of exactly the rules whose exceptions
	// most need watching.
	//
	// Suppression only: an antipattern takes a match away and cannot create
	// one, so a rule needing *context* to fire still says so in Pattern.
	Antipatterns []string `json:"antipatterns,omitempty"`

	// Flags and Leaves are the rule's own proof: text it must catch, and
	// text it must not. TestRuleExamples runs every one of them.
	//
	// Attached to the rule rather than kept in a list somewhere else,
	// because the failure this plugin actually suffers is not a missing
	// rule -- it is a rule that was wrong from the day it was written and
	// went unnoticed for weeks. Three of those were found in a single
	// afternoon of real use: a message that showed its own template, a
	// pattern that flagged "12th", and a guard that missed
	// "with out-of-date". Each would have failed here the moment it was
	// typed, and pointed at the rule rather than at a line of shared corpus.
	//
	// Never sent to the host: this is how the rule is developed, not what
	// it does. The corpus in spellcheck_test.go stays as well and answers a
	// different question -- these say a rule works, and the corpus says it
	// does not fire on writing that is nobody's business but the writer's.
	Flags  []string `json:"-"`
	Leaves []string `json:"-"`

	// Severity separates a mistake from an opinion: empty (meaning "error")
	// for text that is wrong whatever the writer meant, SeveritySuggestion
	// for a rewrite that is usually an improvement and sometimes not.
	//
	// The distinction is what lets this plugin ship opinions at all. Every
	// error rule holds to a standard of never firing on correct writing; the
	// style rules cannot meet it and are not asked to, because the app marks
	// them in a different colour and lists them apart.
	Severity string `json:"severity,omitempty"`
}

// Language is one of the languages this plugin can check against.
type Language struct {
	Code string `json:"code"`
	Name string `json:"name"`
}

// Languages are every language this plugin ships a dictionary for. Adding
// one is only data: SCOWL publishes Canadian and Australian lists in exactly
// the shape tools/mkwords already reads.
var Languages = []Language{
	{Code: "en-US", Name: "English (US)"},
	{Code: "en-GB", Name: "English (UK)"},
}

// DefaultLanguage is what an unrecognised or empty request falls back to.
const DefaultLanguage = "en-US"

// Data is the whole payload the capability returns.
type Data struct {
	Words []string `json:"words"`

	// Language is the language Words is for, which need not be the one that
	// was asked for -- a host asking for something this plugin does not have
	// gets the default and is told which it got, rather than nothing.
	Language string `json:"language,omitempty"`

	// Languages is every language this provider can serve, so a host can
	// offer the choice without knowing in advance what is on offer.
	Languages []Language `json:"languages,omitempty"`

	// CommonWords is a subset of Words ordered most-common-first, used by the
	// app to rank corrections. Edit distance cannot rank on its own: "teh" is
	// one typo from "the", "tech", "meh" and "te" alike, and without knowing
	// which of those people write, the intended word is as likely to be
	// missing from the handful shown as not.
	CommonWords []string `json:"commonWords,omitempty"`

	GrammarRules []GrammarRule `json:"grammarRules"`

	// AnalysisChecks are the checks that count rather than match -- see
	// analysis.go.
	AnalysisChecks []AnalysisCheck `json:"analysisChecks,omitempty"`
}
