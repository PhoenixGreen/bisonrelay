package spellcheck

// rules_typography.go is about the characters rather than the words: the
// dashes, the ellipsis, and the symbols people spell out because their
// keyboard has no key for them.
//
// A category the plugin had nothing in at all, and the cheapest one to be
// right about, because none of it depends on what the sentence means. Three
// dots are an ellipsis wherever they appear.
//
// Suggestions throughout, and that is a judgement about where this text ends
// up rather than about the typography. These composers write Markdown that
// other people read in a chat client, and a writer who typed "--" may have
// meant exactly that -- in code, in a command line, in a flag. Being told is
// useful; being corrected in red would be wrong about half the time in a
// technical post.
//
// Deliberately absent: curly quotes. Straight quotes are correct inside code
// spans and in anything anybody might copy and run, this composer has no way
// to tell prose from code at the point the rules are applied, and the field
// already substitutes typographic apostrophes as you type -- see
// normalizeForMatching on the app side, which exists because that substitution
// broke every contraction rule in this plugin.

// typographyRules are the characters worth naming. Written out rather than
// generated from a table: there are few of them and each has its own shape,
// so a table would be a list of patterns with the pattern column filled in.
var typographyRules = []GrammarRule{
	{
		// Three dots or more. Four is the commonest way to get this wrong,
		// and it is the same fix.
		Pattern:  `\.{3,}`,
		Message:  "Use an ellipsis (…)",
		Suggest:  "…",
		Flags:    []string{"wait... what", "hold on...."},
		Leaves:   []string{"wait… what", "the file is main.go"},
		Category: "Typography",
		Explanation: "Three dots typed separately can break across lines, " +
			"where a single ellipsis character cannot.",
		Severity: SeveritySuggestion,
	},
	{
		// A double hyphen between words is an em dash. Spaced or not: both
		// are how people type one, and the fix keeps whatever spacing was
		// there.
		Pattern:      `(\w)\s*--\s*(\w)`,
		Antipatterns: []string{`\w\s--\w|\w--\s\w`},
		Message:      "Use an em dash (—)",
		Suggest:      "$1—$2",
		Flags:        []string{"the release--which slipped--is out"},
		Leaves: []string{
			"the release—which slipped—is out",
			// A command-line flag, which is the reading this must not
			// rewrite. The uneven spacing is what tells them apart.
			"run it with x --verbose",
		},
		Category: "Typography",
		Explanation: "Two hyphens are how an em dash is typed on a keyboard " +
			"that has no key for one. In running text the dash itself reads " +
			"better; in a command or a code sample it does not.",
		Severity: SeveritySuggestion,
	},
	{
		// A range of numbers takes an en dash, not a hyphen. Kept to two
		// short numbers, which is what a range looks like: the antipatterns
		// take out the strings of digits that are dates, phone numbers and
		// version numbers rather than ranges.
		Pattern: `\b(\d{1,4})\s*-\s*(\d{1,4})\b`,
		Antipatterns: []string{
			`\d{4}-\d{1,2}-\d{1,2}`,
			`\d-\d{1,4}-\d`,
			`\d{1,4}-\d{1,4}-\d`,
		},
		Message: "Use an en dash (–) in a range",
		Suggest: "$1–$2",
		Flags:   []string{"open 9-5 on weekdays", "pages 10 - 12"},
		Leaves: []string{
			"open 9–5 on weekdays",
			"released 2026-08-19",
			"call 555-0134-9 for details",
		},
		Category: "Typography",
		Explanation: "A range takes an en dash, which is longer than a " +
			"hyphen and is what tells \"9–5\" from a subtraction.",
		Severity: SeveritySuggestion,
	},
	{
		Pattern:  `\((?:[cC])\)`,
		Message:  "Use the © character",
		Suggest:  "©",
		Flags:    []string{"(c) 2026 the author"},
		Leaves:   []string{"© 2026 the author", "option (a) or (b)"},
		Category: "Typography",
		Explanation: "The copyright sign has a character of its own, which " +
			"screen readers announce correctly and a bracketed letter does not.",
		Severity: SeveritySuggestion,
	},
	{
		Pattern:  `\((?:[tT][mM])\)`,
		Message:  "Use the ™ character",
		Suggest:  "™",
		Flags:    []string{"the widget(tm) is out"},
		Leaves:   []string{"the widget™ is out"},
		Category: "Typography",
		Explanation: "The trademark sign has a character of its own, and it " +
			"is what the mark is registered as.",
		Severity: SeveritySuggestion,
	},
	{
		// The multiplication sign, in the one place people reach for an x:
		// between two numbers, as dimensions.
		Pattern:  `\b(\d+)\s*[xX]\s*(\d+)\b`,
		Message:  "Use a multiplication sign (×)",
		Suggest:  "$1 × $2",
		Flags:    []string{"the image is 800x600", "a 3 x 4 grid"},
		Leaves:   []string{"the image is 800 × 600"},
		Category: "Typography",
		Explanation: "Dimensions take a multiplication sign rather than the " +
			"letter x, which reads as a word in the middle of the numbers.",
		Severity: SeveritySuggestion,
	},
}
