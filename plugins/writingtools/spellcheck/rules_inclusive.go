package spellcheck

// rules_inclusive.go offers the term that covers everybody doing a job.
//
// A category the plugin had nothing in, and one where the writing standard is
// no longer in dispute: every style guide in general use -- the newspapers,
// the wire services, the public bodies -- has moved to these, and a reader who
// wrote "fireman" mostly wrote it out of habit rather than out of a decision.
//
// Suggestions, and never anything stronger, for a reason that has nothing to
// do with politeness. Some of these are somebody's actual title -- a company
// really does have a Chairman, a role really is called Freshman Rep -- and a
// checker that put a red line under a person's job title would be wrong about
// a fact rather than about a style. Blue, on the page for opinions, with
// "Ignore once" and "Turn off" next to it, is the honest strength.
//
// The wording matters as much as the list. Each of these says what the
// alternative *does* -- covers everyone doing the job -- and never that the
// word written was offensive. A checker is in no position to make that claim
// about somebody's sentence, and a reader told off by their text editor stops
// reading the suggestions rather than starting to think about them.
//
// Deliberately absent: "guys", which is a form of address and depends
// entirely on who is being addressed; "actress" and "waitress", which many of
// the people doing those jobs use of themselves; and the verb "to man", which
// needs the sentence to tell staffing from anything else.

// gendered pairs a gendered job word with the term that covers the job.
//
// Plurals are listed rather than derived. "Policemen" is "police officers" and
// "chairmen" is "chairs", and a rule that added an -s to the singular
// suggestion would produce "police officers" correctly and "chairmans"
// disastrously.
var gendered = [][2]string{
	{"chairman", "chair"},
	{"chairmen", "chairs"},
	{"chairwoman", "chair"},
	{"policeman", "police officer"},
	{"policemen", "police officers"},
	{"policewoman", "police officer"},
	{"fireman", "firefighter"},
	{"firemen", "firefighters"},
	{"postman", "postal worker"},
	{"postmen", "postal workers"},
	{"mailman", "mail carrier"},
	{"salesman", "salesperson"},
	{"saleswoman", "salesperson"},
	{"salesmen", "salespeople"},
	{"spokesman", "spokesperson"},
	{"spokeswoman", "spokesperson"},
	{"spokesmen", "spokespeople"},
	{"businessman", "businessperson"},
	{"businessmen", "businesspeople"},
	{"congressman", "member of congress"},
	{"congresswoman", "member of congress"},
	{"foreman", "supervisor"},
	{"workman", "worker"},
	{"workmen", "workers"},
	{"craftsman", "craftsperson"},
	{"craftsmen", "craftspeople"},
	{"draughtsman", "draughtsperson"},
	{"layman", "layperson"},
	{"middleman", "intermediary"},
	{"stewardess", "flight attendant"},
	{"housewife", "homemaker"},
	{"freshman", "first-year student"},
	{"manpower", "staffing"},
	{"man-hours", "work hours"},
	{"manmade", "artificial"},
	{"man-made", "artificial"},
	{"mankind", "humanity"},
	{"forefathers", "ancestors"},
}

// inclusiveRules are the table above, one rule each.
var inclusiveRules = buildInclusiveRules()

func buildInclusiveRules() []GrammarRule {
	rules := make([]GrammarRule, 0, len(gendered))
	for _, pair := range gendered {
		word, neutral := pair[0], pair[1]
		rules = append(rules, GrammarRule{
			Pattern: `\b` + eitherCase(word) + wordBoundary(word),
			Message: "Consider \"" + neutral + "\"",
			Suggest: neutral,
			Flags:   []string{"we asked the " + word + " about it"},
			// Category and heading both: this is the one place in the panel
			// where the rule is about who the writing includes rather than
			// about whether it is correct.
			Category: "Inclusive language",
			Explanation: "\"" + neutral + "\" covers everyone doing the job. " +
				"\"" + word + "\" is right when it is somebody's actual " +
				"title, which is why this is a suggestion rather than a " +
				"correction.",
			Severity: SeveritySuggestion,
		})
	}
	return rules
}
