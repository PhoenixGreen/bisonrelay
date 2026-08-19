package spellcheck

// rules_ordinals.go checks that a number wears the right ordinal ending:
// "21st" and not "21th", "112th" and not "112nd".
//
// This is the smallest rule set in the plugin and the only one with no
// judgement in it at all. Which ending a number takes is decided entirely by
// its last two digits, so every one of these fires on text that is wrong and
// on nothing else.
//
// It also closes a gap this plugin opened itself. Letters welded to a digit
// are skipped by the spelling pass -- the "th" in "12th" was being offered
// "the", because the wordlist drops two-letter entries that are not common
// words. Skipping them silences the wrong suffixes along with the right
// ones, and nothing has looked at an ordinal since. These rules look at the
// number, which is where the answer was all along.

const explainOrdinal = "The ending of an ordinal follows the last digit: " +
	"1 takes \"st\", 2 takes \"nd\", 3 takes \"rd\" and everything else " +
	"takes \"th\". The teens are the exception in every hundred -- 11th, " +
	"12th and 13th -- which is why 21st and 11th are both right."

// ordinalRules are four rules, one per correct ending.
//
// The teens are handled by the digit classes rather than by an antipattern.
// A number takes "st" when it ends in 1 *and* the digit before it is not a 1,
// which "[02-9]1" says directly; the bare alternative is the single digit,
// where there is no preceding digit to exclude. Written as a lookbehind this
// would be shorter and would put all four rules beyond RE2, where neither
// the corpus nor their own examples could reach them.
var ordinalRules = []GrammarRule{
	{
		Pattern:     `\b(\d*[02-9]1|1)(th|nd|rd)\b`,
		Message:     "Should be \"$1st\"",
		Suggest:     "$1st",
		Flags:       []string{"the 21th of the month", "our 1nd attempt", "the 101rd time"},
		Leaves:      []string{"the 21st of the month", "the 11th hour", "the 111th block"},
		Category:    "Grammar",
		Explanation: explainOrdinal,
	},
	{
		Pattern:     `\b(\d*[02-9]2|2)(th|st|rd)\b`,
		Message:     "Should be \"$1nd\"",
		Suggest:     "$1nd",
		Flags:       []string{"the 22th time", "our 2st attempt", "the 132rd block"},
		Leaves:      []string{"the 22nd time", "the 12th hour", "the 112th block"},
		Category:    "Grammar",
		Explanation: explainOrdinal,
	},
	{
		Pattern:     `\b(\d*[02-9]3|3)(th|st|nd)\b`,
		Message:     "Should be \"$1rd\"",
		Suggest:     "$1rd",
		Flags:       []string{"the 23th time", "our 3st attempt", "the 43nd block"},
		Leaves:      []string{"the 23rd time", "the 13th hour", "the 113th block"},
		Category:    "Grammar",
		Explanation: explainOrdinal,
	},
	{
		// Everything that ends in 0 or 4 through 9, plus the teens in every
		// hundred, which are the reason the three rules above have to name
		// the digit in front.
		Pattern:     `\b(\d*[04-9]|\d*1[123])(st|nd|rd)\b`,
		Message:     "Should be \"$1th\"",
		Suggest:     "$1th",
		Flags:       []string{"the 4st time", "our 11st attempt", "the 13nd block", "the 112rd time"},
		Leaves:      []string{"the 4th time", "the 11th attempt", "the 21st of May", "the 33rd block"},
		Category:    "Grammar",
		Explanation: explainOrdinal,
	},
}
