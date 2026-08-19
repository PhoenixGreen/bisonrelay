package spellcheck

// analysis.go declares the checks that count instead of matching.
//
// A regex can say "this text contains X". It cannot say "this word appears
// four times in this paragraph", "this sentence runs to fifty words" or
// "these two spellings of one word are both in use" -- each needs to look at
// the whole message and keep a tally, which is not what a pattern does.
//
// So these are declared rather than written: the plugin names a check the app
// knows how to run, and supplies everything else about it. That keeps the
// division this plugin is built on -- the provider decides what is checked,
// the app owns every mechanism -- rather than moving logic into the app under
// the plugin's name. It is the same arrangement the regex rules already have,
// where the plugin writes patterns it never executes.
//
// An app that does not implement one of these ids ignores it, so a check can
// ship here before the app that runs it.

// The check ids the app implements. Named constants because a typo in one is
// silently ignored by design -- the whole point of ignoring unknown ids -- so
// nothing at runtime would report it.
const (
	// CheckRepeatedWord fires when one word is used Threshold or more times
	// in a single paragraph. $1 is the word, $2 the count.
	CheckRepeatedWord = "repeated-word-in-paragraph"

	// CheckLongSentence fires on a sentence of Threshold or more words. $2 is
	// the length.
	CheckLongSentence = "long-sentence"

	// CheckRepeatedOpener fires when Threshold consecutive sentences begin
	// with the same word. $1 is the word, $2 the run length.
	CheckRepeatedOpener = "repeated-sentence-opener"

	// CheckSpellingVariants fires when both spellings of a Values pair appear
	// in one message. $1 is the spelling flagged, $2 the other one.
	CheckSpellingVariants = "spelling-variant-inconsistency"

	// CheckUnpairedBrackets fires on a bracket or quote that is never
	// closed, or a closer with nothing open. $1 is the mark.
	CheckUnpairedBrackets = "unpaired-brackets"

	// CheckDateWeekday fires when a written weekday is not the weekday that
	// date fell on, and the year is written out. $1 is the weekday as typed,
	// $2 the weekday it actually was.
	CheckDateWeekday = "date-weekday-mismatch"

	// CheckDateWeekdayThisYear is the same check where no year was written
	// and the current one is assumed. $1 and $2 are as above.
	//
	// A separate id rather than a flag on the one above, because the two are
	// not equally certain and must not be equally loud. With the year
	// written, a mismatch is a plain error. Without it, "Monday 10 August"
	// may be a date in some other year and perfectly correct, so this one is
	// a suggestion and is worded as an observation rather than a correction.
	// Two ids also means either can be turned off on its own.
	CheckDateWeekdayThisYear = "date-weekday-mismatch-this-year"

	// CheckImpossibleDate fires on a day number that month never has -- "31
	// February", or "29 February" in a year written out and not a leap year.
	// $1 is the date as typed, $2 the number of days that month has.
	CheckImpossibleDate = "impossible-date"

	// CheckApostropheConsistency fires when straight and curly apostrophes
	// are both used inside words in one message. $1 is the odd one out.
	CheckApostropheConsistency = "apostrophe-inconsistency"
)

// AnalysisCheck is one declared check. It mirrors the spellcheck-data
// capability's JSON schema exactly; this plugin is a separate Go module and
// deliberately takes no dependency on Bison Relay to get it.
type AnalysisCheck struct {
	ID          string   `json:"id"`
	Threshold   int      `json:"threshold,omitempty"`
	Message     string   `json:"message"`
	Category    string   `json:"category,omitempty"`
	Explanation string   `json:"explanation,omitempty"`
	Severity    string   `json:"severity,omitempty"`
	Values      []string `json:"values,omitempty"`
}

// AnalysisChecks are the counting checks this plugin asks for, with the
// thresholds it thinks are right.
//
// The thresholds are the whole argument in each case, and each is set below
// where a tool would usually put it. A check that fires on ordinary writing
// is worse than no check: the reader learns to skip that page.
var AnalysisChecks = []AnalysisCheck{
	{
		ID: CheckRepeatedWord,
		// Four, not three. Three uses of a word in a paragraph is often just
		// what the paragraph is about -- a paragraph on payments will say
		// "payment" three times and be right to. By four it reads as a rut.
		Threshold:   4,
		Message:     "\"$1\" used $2 times in this paragraph",
		Category:    "Repetition",
		Severity:    SeveritySuggestion,
		Explanation: "Repeating a word in a short space makes writing feel flat. A pronoun or dropping the word altogether often reads better, and the thesaurus offers alternatives beside this -- though a technical term is usually best repeated rather than varied for its own sake.",
	},
	{
		ID: CheckLongSentence,
		// Thirty rather than the forty most tools use. Forty catches only
		// sentences already past saving; thirty catches the ones still worth
		// splitting, which is the point of saying anything.
		Threshold: 30,
		Message:   "Long sentence -- $2 words",
		Category:  "Readability",
		Severity:  SeveritySuggestion,
		// No replacement is offered here or on the opener check, and it
		// is worth being plain about why rather than looking incomplete.
		// Both of these are answered by rewriting a sentence, and a
		// rewrite has to know what the sentence is trying to say. What
		// can be given instead is where to look, which is what the last
		// line below does.
		Explanation: "A sentence this long asks the reader to hold a lot at once. Look for the first \"and\", \"but\", \"which\" or semicolon in it: that is usually where two sentences were joined, and splitting there makes both halves easier to follow.",
	},
	{
		ID:          CheckRepeatedOpener,
		Threshold:   3,
		Message:     "$2 sentences in a row start with \"$1\"",
		Category:    "Repetition",
		Severity:    SeveritySuggestion,
		Explanation: "Consecutive sentences opening the same way give writing a monotonous rhythm. The usual fixes are to join two of them into one sentence, or to start one with what it is about rather than with who did it.",
	},
	{
		ID: CheckUnpairedBrackets,
		// An error rather than a suggestion, unusually for a check that
		// counts: a bracket that is never closed is not a matter of taste.
		// It reads as a mistake because it is one, and the reader of the
		// post sees it too.
		Message:     "Unclosed \"$1\"",
		Category:    "Punctuation",
		Explanation: "This opens something that is never closed. A reader looking for the other half will not find it.",
	},
	{
		ID:          CheckSpellingVariants,
		Threshold:   0,
		Message:     "\"$1\" and \"$2\" are both used here",
		Category:    "Consistency",
		Severity:    SeveritySuggestion,
		Explanation: "Both spellings are correct, but mixing them in one message looks careless. Pick whichever you prefer and use it throughout.",
		Values:      consistencyPairs,
	},
	{
		// The one check here that does arithmetic rather than counting, and
		// the only one that can be certain about something a careful reader
		// would still miss. Nobody proofreads a date against a calendar.
		ID:          CheckDateWeekday,
		Message:     "That date was a $2, not a $1",
		Category:    "Consistency",
		Explanation: "The weekday and the date do not agree. One of the two is wrong, and which one is a question only you can answer -- the correction offered here changes the weekday, on the assumption that the date is the part that was looked up.",
	},
	{
		ID:          CheckDateWeekdayThisYear,
		Message:     "This year that date is a $2, not a $1",
		Category:    "Consistency",
		Severity:    SeveritySuggestion,
		Explanation: "No year was written, so this assumes the current one. If you meant a date in another year the weekday may well be right, which is why this is a suggestion rather than a correction.",
	},
	{
		ID:          CheckImpossibleDate,
		Message:     "\"$1\" is not a date -- that month has $2 days",
		Category:    "Consistency",
		Explanation: "No such day exists in that month. Nothing is offered to replace it because the slip could as easily be the month as the number.",
	},
	{
		ID:          CheckApostropheConsistency,
		Message:     "Mixed apostrophes -- \"$1\" is the odd one out",
		Category:    "Consistency",
		Severity:    SeveritySuggestion,
		Explanation: "This message uses both the straight apostrophe and the curly one inside words. Either is fine; both together looks like text pasted from two places, which is usually what it is.",
	},
}
