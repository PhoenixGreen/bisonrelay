package spellcheck

// rules_agreement.go is subject-verb agreement, in the narrow places where a
// pattern can settle it.
//
// Agreement in general needs to know which noun is the subject, and finding
// that needs a parser: "the list of files was" is right and "the parts of it
// was" is wrong, and the only difference is which noun the verb belongs to.
// That is the wall this plugin does not climb, and most of English agreement
// is behind it.
//
// What is in front of it is the closed classes. A personal pronoun IS the
// subject -- there is no other candidate and no noun for the verb to reach
// past -- so "we was" is wrong in every sentence that contains it. The same
// goes for a handful of quantifiers that are plural whatever follows them.
// Those are the rules here, and the file stops where the guessing starts.

const explainDoubleNegative = "\"Hardly\", \"scarcely\" and \"barely\" " +
	"are already negative, so a \"not\" in front of one reverses the meaning " +
	"of the sentence rather than strengthening it."

const explainAgreement = "The verb has to match its subject in number: " +
	"\"I was\" and \"we were\", \"one part is\" and \"some parts are\"."

// subjunctives are the phrases where a plural "were" after a singular
// subject is correct rather than mistaken -- "if I were you", "I wish it
// were simpler". English keeps the subjunctive alive almost entirely in
// these frames, which is what makes them listable.
// afterPreposition is the reading both pronoun rules below get wrong on
// their own, and it is the same trap the quantifier rule was written to
// climb over.
//
// "It" and "you" are object forms as well as subject ones, so a preposition
// in front of one takes it out of the running entirely: in "a photo of you
// was on the wall" and "some parts of it were exciting" the verb belongs to
// a noun further back, and both sentences are correct. Without this the two
// rules argue with each other -- fixing "some parts of it was" produces
// "some parts of it were", which the second rule then offers to change back.
//
// "I", "he", "she", "we" and "they" need no such guard: they are subject
// forms only, and "of he" is not English.
const afterPreposition = `(of|for|with|to|about|from|at|on|in|by|near|like|` +
	`between|beside|without|against|among|behind|beyond)\s+`

const subjunctives = `([Ii]f|[Ww]hether|[Tt]hough|[Aa]s|[Oo]nly|[Rr]ather|` +
	`[Ww]ish|[Ww]ishes|[Ww]ished|[Ss]uppose|[Ii]magine)\s+` +
	`([Ii]|[Hh]e|[Ss]he|[Ii]t)\s+were\b`

// quantifiers are the words that pin the front of the subject in the rule
// below.
const quantifiers = `[Ss]ome|[Mm]any|[Aa]ll|[Bb]oth|[Ss]everal|[Ff]ew|[Mm]ost`

// massNounsInS are singular nouns ending in "s". The rule below reads the
// word after a quantifier as a plural because it ends in that letter, which
// is true of "parts" and "pieces" and equally true of "business", "series"
// and "analysis" -- so those are named and left alone.
// pluralNouns are common count nouns in the plural, for the existential
// rule below. A list rather than a pattern, because no ending distinguishes
// a plural from a singular noun that happens to end in "s".
const pluralNouns = `receipts|seats|people|persons|things|options|reasons|` +
	`problems|cars|shops|coins|tickets|books|files|users|messages|` +
	`questions|ideas|errors|bugs|places|students|members|players|children|` +
	`men|women|kids|days|weeks|years|hours|minutes|letters|emails|photos|` +
	`chairs|tables|boxes|bags|shoes|clothes|keys|cards|notes|posts`

const massNounsInS = `news|business|progress|glass|class|series|species|` +
	`means|process|access|address|analysis|basis|crisis|status|focus|bonus`

var agreementRules = []GrammarRule{
	{
		// A quantifier, a plural noun, then a prepositional phrase, then the
		// verb. The phrase in the middle is the whole difficulty: it puts a
		// singular noun ("of it") next to the verb, and that is the noun the
		// writer's ear agrees with rather than the real subject further back.
		//
		// Decidable here because the subject is pinned on both sides -- a
		// quantifier in front of it and "of" behind it -- so the plural noun
		// between them can only be the thing the verb belongs to.
		Pattern: `\b(` + quantifiers + `)\s+(\w+s)\s+of\s+` +
			`(it|them|this|that|these|those|us|the\s+\w+|his|her|their|` +
			`our|my|your)\s+was\b`,
		Antipatterns: []string{
			`\b(` + quantifiers + `)\s+(` + massNounsInS + `)\s+of\s+\w+\s+was\b`,
		},
		Flags: []string{
			"Some parts of it was really exciting",
			"many pieces of the puzzle was missing",
		},
		Leaves: []string{
			"some parts of it were really exciting",
			"some of it was really exciting",
			"the list of files was long",
			// The antipattern's own reading: a noun that ends in "s" and is
			// singular anyway.
			"all business of this was handled locally",
			"some progress of it was lost",
		},
		Message:     "Should be \"$1 $2 of $3 were\"",
		Suggest:     "$1 $2 of $3 were",
		Category:    "Grammar",
		Explanation: explainAgreement + " The subject here is the plural noun, not the singular one beside the verb.",
	},
	{
		// "There was" followed by something that cannot be singular. The
		// quantifiers listed are plural whatever noun comes after them, so
		// unlike "lots of" and "plenty of" -- which take mass nouns quite
		// happily, as in "there was plenty of time" -- these need no idea
		// what is being counted.
		Pattern:     `\b([Tt]here)\s+was\s+(many|several|numerous|dozens|hundreds|thousands)\b`,
		Flags:       []string{"there was many people waiting", "There was several problems"},
		Leaves:      []string{"there were many people waiting", "there was plenty of time"},
		Message:     "Should be \"$1 were $2\"",
		Suggest:     "$1 were $2",
		Category:    "Grammar",
		Explanation: explainAgreement,
	},
	{
		// "There was old receipts in my bag." An existential "there was" in
		// front of a plural is the commonest agreement slip there is,
		// because the verb is chosen before the noun it belongs to has been
		// thought of.
		//
		// The nouns are a list rather than `\w+s`, for the same reason as
		// everywhere else in this file: "there was progress", "there was
		// glass everywhere" and "there was a series of delays" are all
		// correct and all end in the same letter.
		Pattern: `\b([Tt]here)\s+was\s+((?:\w+\s+){0,2})(` + pluralNouns + `)\b`,
		Flags: []string{
			"There was old receipts in my bag",
			"there was two people waiting",
		},
		Leaves: []string{
			"there were old receipts in my bag",
			"there was a receipt in my bag",
		},
		Message:     "Should be \"$1 were\"",
		Suggest:     "$1 were $2$3",
		Category:    "Grammar",
		Explanation: explainAgreement,
	},
	{
		// "Loads of" and "lots of" do take mass nouns, so these need the
		// noun named. The list is common plural count nouns; anything not on
		// it is left alone rather than guessed at, because "there was lots
		// of grass" is correct and ends in the same letter as "cars".
		Pattern: `\b([Tt]here)\s+was\s+(loads|lots|plenty|a\s+number)\s+of\s+` +
			`(people|persons|folk|folks|kids|children|men|women|things|` +
			`options|reasons|problems|users|posts|files|cars|shops|places|` +
			`students|members|players|messages|questions|ideas|errors|bugs)\b`,
		Flags:       []string{"when we got inside there was loads of people"},
		Leaves:      []string{"there was lots of time", "there were loads of people"},
		Message:     "Should be \"$1 were $2 of $3\"",
		Suggest:     "$1 were $2 of $3",
		Category:    "Grammar",
		Explanation: explainAgreement,
	},
	{
		// "Your the one". A possessive has to own the noun after it, and a
		// determiner is not a noun -- nothing can be "your the". This is the
		// same argument as the four adjectives above and a good deal safer,
		// because there is no word that is both a determiner and something
		// ownable.
		Pattern:     `\b([Yy])our\s+(the|a|an|my|his|her|our|their|its)\b`,
		Flags:       []string{"your the one", "Your a genius", "your my best mate"},
		Leaves:      []string{"you're the one", "your best mate is here"},
		Message:     "Should be \"$1ou're $2\"",
		Suggest:     "$1ou're $2",
		Category:    "Confused words",
		Explanation: explainYourYoure,
	},
	{
		// "Suppose to" for "supposed to". The auxiliary in front is what
		// makes it certain: "was suppose" cannot be a verb phrase, where a
		// bare "suppose to" might begin one ("I suppose to err is human").
		Pattern:     `\b([Ww]as|[Ww]ere|[Ii]s|[Aa]re|[Aa]m|[Bb]e|[Bb]een|[Bb]eing)\s+suppose\s+to\b`,
		Flags:       []string{"we were suppose to meet at noon"},
		Leaves:      []string{"we were supposed to meet at noon", "I suppose to err is human"},
		Message:     "Should be \"$1 supposed to\"",
		Suggest:     "$1 supposed to",
		Category:    "Grammar",
		Explanation: "The past participle is \"supposed\". The \"d\" is easy to lose because it is not heard before the \"t\" of \"to\".",
	},
	// --- double negatives ---
	//
	// "Hardly", "scarcely" and "barely" are already negative, so a negated
	// auxiliary in front of one reverses the sentence rather than
	// strengthening it. Three rules rather than one, because they are alike
	// in what is wrong and quite different in what fixes it.
	{
		// The modals, "be" and "have": drop the negative and the rest of the
		// sentence stands.
		Pattern:     `\b([Cc]ould|[Ww]ould|[Ss]hould|[Ii]s|[Aa]re|[Ww]as|[Ww]ere|[Hh]ave|[Hh]as|[Hh]ad)n'?t\s+(hardly|scarcely|barely)\b`,
		Flags:       []string{"we couldnt hardly find anywhere to sit", "there wasn't barely a seat"},
		Leaves:      []string{"we could hardly find anywhere to sit"},
		Message:     "Should be \"$1 $2\"",
		Suggest:     "$1 $2",
		Category:    "Grammar",
		Explanation: explainDoubleNegative,
	},
	{
		// "Can't" on its own, because it is not built the way the others
		// are: it is "ca" plus "n't", so the pattern above cannot spell it
		// and would have handed back "can hardly" only by accident.
		Pattern:     `\b([Cc])an'?t\s+(hardly|scarcely|barely)\b`,
		Flags:       []string{"I can't barely see", "we cant hardly move"},
		Leaves:      []string{"I can barely see"},
		Message:     "Should be \"$1an $2\"",
		Suggest:     "$1an $2",
		Category:    "Grammar",
		Explanation: explainDoubleNegative,
	},
	{
		// Do-support, flagged with no fix offered. Dropping the auxiliary is
		// right for the present -- "I don't hardly know" wants "I hardly
		// know" -- but in the past it moves the tense onto the main verb,
		// and "I didn't hardly know" becomes "I hardly knew". That is a
		// change to a word this rule never matched and cannot see.
		Pattern:     `\b[Dd](?:o|oes|id)n'?t\s+(hardly|scarcely|barely)\b`,
		Flags:       []string{"I didnt hardly know", "he doesn't hardly try"},
		Leaves:      []string{"I hardly knew"},
		Message:     "Double negative with \"$1\"",
		Suggest:     "",
		Category:    "Grammar",
		Explanation: explainDoubleNegative + " Drop the \"not\": \"I didn't hardly know\" is \"I hardly knew\". No replacement is offered because the tense moves onto the verb, which is outside what this rule matched.",
	},
}
