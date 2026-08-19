package spellcheck

// rules_compounds.go catches words written as two.
//
// These need a rule rather than the dictionary, and that is the whole point
// of the file: "my self" is two perfectly good words, so no wordlist can
// object to it however large. Only something that looks at the pair can.
//
// The risk runs the other way from most of this plugin's rules. There is no
// question that the joined form is a word -- the danger is that the split
// form is *also* a phrase somewhere, so each rule below is either a pair
// that has no valid reading apart, or is guarded against the readings it
// does have.

const explainCompound = "This is one word. Written as two it means " +
	"something else, or nothing at all."

// runTogether are two-word phrases people write as one. The dictionary
// cannot help: it can say "atleast" is not a word, but a speller offers
// single words and the answer here is two, so it reaches for "atlas" and
// "least" never appears.
//
// Each of these has no reading as one word at all, which is what makes them
// safe. Words that are genuinely both -- "everyday" as an adjective and
// "every day" as an adverb, "alright" as an accepted variant of "all right"
// -- are not here; the first has its own rule that looks at what follows,
// and the second is a fight about usage rather than a mistake.
var runTogether = [][2]string{
	{"atleast", "at least"},
	{"aswell", "as well"},
	{"infact", "in fact"},
	{"ofcourse", "of course"},
	{"incase", "in case"},
	{"atall", "at all"},
	{"inspite", "in spite"},
	{"aslong", "as long"},
	{"eachother", "each other"},
	{"anyways", "anyway"},
}

func buildRunTogetherRules() []GrammarRule {
	rules := make([]GrammarRule, 0, len(runTogether))
	for _, pair := range runTogether {
		one, two := pair[0], pair[1]
		rules = append(rules, GrammarRule{
			Pattern:  `\b` + eitherCase(one) + `\b`,
			Message:  "Should be \"" + two + "\"",
			Suggest:  two,
			Flags:    []string{"we wrote " + one + " today"},
			Category: "Grammar",
			Explanation: "\"" + one + "\" is two words: \"" + two +
				"\". The speller cannot offer this on its own, because a " +
				"dictionary answers with one word and this needs two.",
		})
	}
	return rules
}

var compoundRules = append(buildRunTogetherRules(), []GrammarRule{
	// --- the -self family ---
	// The antipattern is what keeps these off "my self-esteem", where
	// "self" is the start of a hyphenated word and the split is not a
	// mistake.
	//
	// An adjective between the two -- "my true self", "her better self" --
	// does not match either, which is what makes the bare pair safe to
	// correct: "my self" with nothing in between is not a phrase anybody
	// writes on purpose.
	{
		Pattern:      `\b([Mm])y\s+self\b`,
		Flags:        []string{"i did it my self"},
		Leaves:       []string{"my self-esteem took a knock"},
		Antipatterns: []string{`[Mm]y\s+self-`},
		Message:      "Should be \"$1yself\"",
		Suggest:      "$1yself",
		Category:     "Grammar",
		Explanation:  explainCompound,
	},
	{
		Pattern:      `\b([Yy])our\s+self\b`,
		Flags:        []string{"you did it your self"},
		Leaves:       []string{"your self-esteem matters"},
		Antipatterns: []string{`[Yy]our\s+self-`},
		Message:      "Should be \"$1ourself\"",
		Suggest:      "$1ourself",
		Category:     "Grammar",
		Explanation:  explainCompound,
	},
	{
		Pattern:      `\b([Hh])im\s+self\b`,
		Flags:        []string{"he did it him self"},
		Leaves:       []string{"it gave him self-confidence"},
		Antipatterns: []string{`[Hh]im\s+self-`},
		Message:      "Should be \"$1imself\"",
		Suggest:      "$1imself",
		Category:     "Grammar",
		Explanation:  explainCompound,
	},
	{
		Pattern:      `\b([Hh])er\s+self\b`,
		Flags:        []string{"she did it her self"},
		Leaves:       []string{"her self-control is good"},
		Antipatterns: []string{`[Hh]er\s+self-`},
		Message:      "Should be \"$1erself\"",
		Suggest:      "$1erself",
		Category:     "Grammar",
		Explanation:  explainCompound,
	},
	{
		Pattern:      `\b([Ii])t\s+self\b`,
		Flags:        []string{"the code writes it self"},
		Leaves:       []string{"we watched it self-destruct"},
		Antipatterns: []string{`[Ii]t\s+self-`},
		Message:      "Should be \"$1tself\"",
		Suggest:      "$1tself",
		Category:     "Grammar",
		Explanation:  explainCompound,
	},
	{
		Pattern:     `\b([Oo])ur\s+selves\b`,
		Flags:       []string{"we did it our selves"},
		Message:     "Should be \"$1urselves\"",
		Suggest:     "$1urselves",
		Category:    "Grammar",
		Explanation: explainCompound,
	},
	{
		Pattern:     `\b([Tt])hem\s+selves\b`,
		Flags:       []string{"they did it them selves"},
		Message:     "Should be \"$1hemselves\"",
		Suggest:     "$1hemselves",
		Category:    "Grammar",
		Explanation: explainCompound,
	},
	{
		Pattern:     `\b([Yy])our\s+selves\b`,
		Flags:       []string{"you did it your selves"},
		Message:     "Should be \"$1ourselves\"",
		Suggest:     "$1ourselves",
		Category:    "Grammar",
		Explanation: explainCompound,
	},

	// --- any/some/every + where ---
	// "No where" is here and "no thing" is not: the first has no reading as
	// two words, while the second is a real if uncommon philosophical usage.
	{
		Pattern:     `\b([Aa])ny\s+where\b`,
		Flags:       []string{"is it any where here"},
		Message:     "Should be \"$1nywhere\"",
		Suggest:     "$1nywhere",
		Category:    "Grammar",
		Explanation: explainCompound,
	},
	{
		Pattern:     `\b([Ss])ome\s+where\b`,
		Flags:       []string{"it is some where here"},
		Message:     "Should be \"$1omewhere\"",
		Suggest:     "$1omewhere",
		Category:    "Grammar",
		Explanation: explainCompound,
	},
	{
		Pattern:     `\b([Ee])very\s+where\b`,
		Flags:       []string{"it is every where now"},
		Message:     "Should be \"$1verywhere\"",
		Suggest:     "$1verywhere",
		Category:    "Grammar",
		Explanation: explainCompound,
	},
	{
		Pattern:     `\b([Nn])o\s+where\b`,
		Flags:       []string{"there is no where to go"},
		Message:     "Should be \"$1owhere\"",
		Suggest:     "$1owhere",
		Category:    "Grammar",
		Explanation: explainCompound,
	},

	// --- any/some/every + thing ---
	{
		Pattern:     `\b([Aa])ny\s+thing\b`,
		Flags:       []string{"is there any thing else"},
		Message:     "Should be \"$1nything\"",
		Suggest:     "$1nything",
		Category:    "Grammar",
		Explanation: explainCompound,
	},
	{
		Pattern:     `\b([Ss])ome\s+thing\b`,
		Flags:       []string{"there is some thing wrong"},
		Message:     "Should be \"$1omething\"",
		Suggest:     "$1omething",
		Category:    "Grammar",
		Explanation: explainCompound,
	},
	{
		Pattern:     `\b([Ee])very\s+thing\b`,
		Flags:       []string{"every thing is ready"},
		Message:     "Should be \"$1verything\"",
		Suggest:     "$1verything",
		Category:    "Grammar",
		Explanation: explainCompound,
	},
	{
		// "every body" was left out of this file for a long time on the
		// grounds that a body is a countable thing, and "every body in the
		// room" is correct writing. That was right about the exception and
		// wrong about the rule: the exception is narrow enough to name.
		//
		// A literal body is nearly always followed by "of" (every body of
		// water, of work, of evidence) or by a preposition placing it
		// somewhere (in the room, on the field). Those are the antipatterns.
		// Everywhere else, "every body" is "everybody" typed with a space.
		Pattern: `\b([Ee])very\s+body\b`,
		Antipatterns: []string{
			`[Ee]very\s+body\s+(of|in|on|at|was|were|had|found|recovered)\b`,
		},
		Flags: []string{
			"every body should know this",
			"Every body agreed with the plan",
		},
		Leaves: []string{
			"every body of water was tested",
			"every body in the room agreed",
			"every body of evidence points the same way",
		},
		Message:     "Should be \"$1verybody\"",
		Suggest:     "$1verybody",
		Category:    "Grammar",
		Explanation: explainCompound,
	},

	// --- the rest, each guarded against the phrase it collides with ---
	{
		// "with out of date information" is the real reading of the pair,
		// and "with out-of-date information" is the same thing hyphenated.
		//
		// The second was missed while this was a lookahead, and the corpus
		// could not say so: RE2 cannot compile a lookahead, so the rule was
		// skipped by the very test that would have caught it. Moving the
		// guard into an antipattern is what surfaced it.
		Pattern:      `\b([Ww])ith\s+out\b`,
		Flags:        []string{"we did it with out help"},
		Leaves:       []string{"with out of date info", "with out-of-date info"},
		Antipatterns: []string{`[Ww]ith\s+out\s+of\b`, `[Ww]ith\s+out-`},
		Message:      "Should be \"$1ithout\"",
		Suggest:      "$1ithout",
		Category:     "Grammar",
		Explanation:  explainCompound,
	},
	{
		// "would be cause for concern" is correct, and common enough to be
		// worth the guard.
		Pattern: `\b([Bb])e\s+cause\b`,
		// Not "be cause of", which the antipattern is for.
		Flags:        []string{"i left be cause it rained"},
		Leaves:       []string{"that would be cause for concern"},
		Antipatterns: []string{`[Bb]e\s+cause\s+(for|of)\b`},
		Message:      "Should be \"$1ecause\"",
		Suggest:      "$1ecause",
		Category:     "Grammar",
		Explanation:  explainCompound,
	},
	{
		// "in side" is absent, unlike this one: "parked in side streets" is
		// ordinary English and "the way out side" is not.
		Pattern:     `\b([Oo])ut\s+side\b`,
		Flags:       []string{"we waited out side"},
		Leaves:      []string{"we parked in side streets"},
		Message:     "Should be \"$1utside\"",
		Suggest:     "$1utside",
		Category:    "Grammar",
		Explanation: explainCompound,
	},
	{
		Pattern:     `\b([Aa])\s+part\s+from\b`,
		Flags:       []string{"a part from that it works"},
		Message:     "Should be \"$1part from\"",
		Suggest:     "$1part from",
		Category:    "Grammar",
		Explanation: "\"Apart from\" means except for. \"A part\" is a piece of something.",
	},
}...)
