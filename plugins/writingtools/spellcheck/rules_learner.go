package spellcheck

// rules_learner.go holds the mistakes that come from learning English rather
// than from typing too fast: a past tense left on a verb that has an
// auxiliary in front of it, an uncountable noun given a plural, "borrow" used
// where "lend" was meant.
//
// They belong with the rest because they are decidable in the same way. An
// auxiliary fixes the form of the verb after it whatever the sentence is
// about, "furniture" has no plural in any context, and "borrow me" is not a
// phrase. None of these needs to know what the sentence means.

const explainAuxiliary = "After \"did\", \"didn't\", \"don't\" or " +
	"\"doesn't\", the verb goes back to its plain form: the auxiliary is " +
	"already carrying the tense."

// baseForms pairs a past tense with the plain form an auxiliary wants in
// front of it, for "we didn't went" and its relatives.
var baseForms = [][2]string{
	{"went", "go"}, {"saw", "see"}, {"ate", "eat"}, {"took", "take"},
	{"came", "come"}, {"gave", "give"}, {"made", "make"}, {"got", "get"},
	{"said", "say"}, {"knew", "know"}, {"thought", "think"},
	{"brought", "bring"}, {"bought", "buy"}, {"found", "find"},
	{"felt", "feel"}, {"left", "leave"}, {"told", "tell"},
	{"forgot", "forget"}, {"wrote", "write"}, {"ran", "run"},
	{"began", "begin"}, {"spoke", "speak"}, {"drank", "drink"},
	{"heard", "hear"}, {"kept", "keep"}, {"lost", "lose"}, {"paid", "pay"},
	{"put", "put"}, {"read", "read"}, {"sent", "send"}, {"slept", "sleep"},
	{"spent", "spend"}, {"stood", "stand"}, {"understood", "understand"},
	{"won", "win"}, {"had", "have"}, {"was", "be"}, {"were", "be"},
}

// comparatives are the -er adjectives, listed rather than matched as `\w+er`
// because that pattern sweeps up "water", "other", "later", "never",
// "number", "member" and half the language besides.
const comparatives = `taller|bigger|better|easier|faster|slower|harder|` +
	`smaller|larger|higher|lower|older|younger|longer|shorter|cheaper|` +
	`worse|nicer|happier|safer|stronger|weaker|richer|poorer|closer|` +
	`darker|brighter|heavier|lighter|warmer|colder|louder|quieter`

// superlatives are the "-est" forms, for the "most biggest" case. Listed
// for the same reason the comparatives are: `\w+est` would match "best",
// "west", "rest", "honest" and "interest".
const superlatives = `tallest|biggest|best|easiest|fastest|slowest|hardest|` +
	`smallest|largest|highest|lowest|oldest|youngest|longest|shortest|` +
	`cheapest|worst|nicest|happiest|safest|strongest|weakest|richest|` +
	`poorest|closest|darkest|brightest|heaviest|lightest|warmest|coldest`

// uncountable are nouns with no plural, paired with the form wanted.
var uncountable = [][2]string{
	{"furnitures", "furniture"}, {"informations", "information"},
	{"advices", "advice"}, {"equipments", "equipment"},
	{"softwares", "software"}, {"luggages", "luggage"},
	{"homeworks", "homework"}, {"knowledges", "knowledge"},
	{"feedbacks", "feedback"}, {"evidences", "evidence"},
	{"machineries", "machinery"}, {"stuffs", "stuff"},
}

// forwardTo are the verbs after "looking forward to", which takes a gerund
// rather than an infinitive because its "to" is a preposition.
var forwardTo = [][2]string{
	{"see", "seeing"}, {"meet", "meeting"}, {"hear", "hearing"},
	{"work", "working"}, {"go", "going"}, {"visit", "visiting"},
	{"start", "starting"}, {"read", "reading"}, {"speak", "speaking"},
	{"talk", "talking"}, {"try", "trying"}, {"get", "getting"},
	{"catch", "catching"}, {"join", "joining"},
}

// negativePronouns pair a negative word with the one wanted after an
// auxiliary that is already negative. "I couldn't find it nowhere" has two
// negatives doing the work of one.
var negativePronouns = [][2]string{
	{"nothing", "anything"}, {"nowhere", "anywhere"},
	{"nobody", "anybody"}, {"no one", "anyone"}, {"none", "any"},
	{"never", "ever"},
}

// negatedAuxiliaries are the contracted negatives, for the rules above and
// below. Spelled with the apostrophe optional so a message that has not been
// through the contraction rules yet is still covered.
const negatedAuxiliaries = `[Cc]ouldn'?t|[Cc]an'?t|[Dd]idn'?t|[Dd]on'?t|` +
	`[Dd]oesn'?t|[Ww]on'?t|[Ww]ouldn'?t|[Ss]houldn'?t|[Ii]sn'?t|[Aa]ren'?t|` +
	`[Ww]asn'?t|[Ww]eren'?t|[Hh]aven'?t|[Hh]asn'?t|[Hh]adn'?t`

// notReallyPastTense are verbs ending in the letters "ed" that are not past
// tenses at all, so the rule below must not read them as one. Every one of
// them is a plain form ending in "eed" -- which is exactly what an auxiliary
// in front of it is asking for.
const notReallyPastTense = `need|feed|succeed|proceed|exceed|bleed|breed|` +
	`speed|freed|seed|heed|agreed|indeed`

var learnerRules = buildLearnerRules()

func buildLearnerRules() []GrammarRule {
	var rules []GrammarRule

	// An auxiliary in front of a past tense.
	for _, pair := range baseForms {
		past, base := pair[0], pair[1]
		if past == base {
			continue // "put" and "read" look the same either way.
		}
		rules = append(rules, GrammarRule{
			Pattern: `\b([Dd]id|[Dd]idn't|[Dd]idnt|[Dd]on't|[Dd]ont|` +
				`[Dd]oesn't|[Dd]oesnt)\s+` + past + `\b`,
			Message:     "Use the plain form: \"$1 " + base + "\"",
			Suggest:     "$1 " + base,
			Flags:       []string{"we didn't " + past + " today"},
			Leaves:      []string{"we didn't " + base + " today"},
			Category:    "Grammar",
			Explanation: explainAuxiliary,
		})
	}

	for _, pair := range uncountable {
		plural, single := pair[0], pair[1]
		rules = append(rules, GrammarRule{
			Pattern:  `\b` + eitherCase(plural) + `\b`,
			Message:  "Should be \"" + single + "\"",
			Suggest:  single,
			Flags:    []string{"we need new " + plural + " here"},
			Category: "Grammar",
			Explanation: "\"" + single + "\" is uncountable in English and " +
				"has no plural. For a countable amount, say \"pieces of " +
				single + "\" or \"some " + single + "\".",
		})
	}

	for _, pair := range forwardTo {
		infinitive, gerund := pair[0], pair[1]
		rules = append(rules, GrammarRule{
			Pattern:  `\b([Ll]ooking\s+forward\s+to)\s+` + infinitive + `\b`,
			Message:  "Should be \"$1 " + gerund + "\"",
			Suggest:  "$1 " + gerund,
			Flags:    []string{"I am looking forward to " + infinitive + " you"},
			Leaves:   []string{"I am looking forward to " + gerund + " you"},
			Category: "Grammar",
			Explanation: "The \"to\" in \"looking forward to\" is a " +
				"preposition rather than part of an infinitive, so the verb " +
				"after it takes \"-ing\".",
		})
	}

	// A double negative built from a negated auxiliary and a negative
	// pronoun. Unlike the "hardly" family these have a clean fix, because
	// each negative word has a positive twin that means what was intended.
	for _, pair := range negativePronouns {
		negative, positive := pair[0], pair[1]
		rules = append(rules, GrammarRule{
			// Up to three words between the two, which is as far apart as
			// they get before the second belongs to a clause of its own.
			Pattern: `\b(` + negatedAuxiliaries + `)\s+((?:\w+\s+){0,3})` +
				negative + `\b`,
			Message:  "Double negative -- should be \"" + positive + "\"",
			Suggest:  "$1 $2" + positive,
			Flags:    []string{"I couldn't find it " + negative},
			Leaves:   []string{"I couldn't find it " + positive},
			Category: "Grammar",
			Explanation: "The auxiliary is already negative, so \"" +
				negative + "\" after it makes two negatives where one was " +
				"meant. English uses \"" + positive + "\" here.",
		})
	}

	rules = append(rules,
		GrammarRule{
			// "There was hardly no seats." "Hardly" is a negative of its
			// own, so "no" after it is the same doubling as above.
			Pattern:     `\b([Hh]ardly|[Ss]carcely|[Bb]arely)\s+no\b`,
			Message:     "Should be \"$1 any\"",
			Suggest:     "$1 any",
			Flags:       []string{"there was hardly no seats left"},
			Leaves:      []string{"there was hardly any seat left"},
			Category:    "Grammar",
			Explanation: "\"Hardly\" is already negative, so \"no\" after it doubles it. \"Hardly any\" is what was meant.",
		},
		GrammarRule{
			// "I didn't realised." The auxiliary carries the tense, so the
			// verb goes back to its plain form -- but which plain form is
			// not something a pattern can work out: "realised" wants
			// "realise" and "ordered" wants "order", and the difference is
			// whether the verb ended in "e" before the ending was added.
			// So this one names the fault and leaves the fix.
			Pattern:      `\b(` + negatedAuxiliaries + `)\s+(\w+ed)\b`,
			Antipatterns: []string{`\b(` + negatedAuxiliaries + `)\s+(` + notReallyPastTense + `)\b`},
			Message:      "\"$2\" should be the plain form after \"$1\"",
			Suggest:      "",
			Flags:        []string{"I didn't realised until later", "I didn't ordered tuna"},
			Leaves: []string{
				"I didn't realise until later",
				// Plain forms that merely end in the same two letters.
				"I didn't need it", "it doesn't succeed often", "we didn't agreed",
			},
			Category:    "Grammar",
			Explanation: explainAuxiliary,
		},
		GrammarRule{
			// "She dont like coffee." The pronoun decides the form of the
			// auxiliary, and a third-person singular takes "doesn't".
			Pattern:     `\b([Hh]e|[Ss]he|[Ii]t)\s+(?:dont|don't)\b`,
			Message:     "Should be \"$1 doesn't\"",
			Suggest:     "$1 doesn't",
			Flags:       []string{"she dont like coffee", "He don't know"},
			Leaves:      []string{"she doesn't like coffee", "they don't know"},
			Category:    "Grammar",
			Explanation: "\"He\", \"she\" and \"it\" take \"doesn't\". \"Don't\" goes with I, we, you and they.",
		},
		GrammarRule{
			// "I seen him yesterday." "Seen" is the participle and needs
			// "have" in front of it; with a bare pronoun the past tense is
			// what was meant.
			Pattern:     `\b([Ii]|[Ww]e|[Tt]hey|[Yy]ou|[Hh]e|[Ss]he)\s+seen\b`,
			Message:     "Should be \"$1 saw\"",
			Suggest:     "$1 saw",
			Flags:       []string{"I seen him at the bus stop"},
			Leaves:      []string{"I saw him at the bus stop", "I have seen him"},
			Category:    "Grammar",
			Explanation: "\"Seen\" is the past participle and needs \"have\" or \"had\" in front of it. On its own the past tense is \"saw\".",
		},
		GrammarRule{
			// "He is more taller than his brother." The -er ending is
			// already the comparative, so "more" doubles it.
			Pattern:     `\b[Mm]ore\s+(` + comparatives + `)\b`,
			Message:     "Should be \"$1\"",
			Suggest:     "$1",
			Flags:       []string{"he is more taller than his brother"},
			Leaves:      []string{"he is taller than his brother", "it is more important"},
			Category:    "Grammar",
			Explanation: "The \"-er\" ending is already the comparative, so \"more\" in front of it says the same thing twice.",
		},
		GrammarRule{
			// The superlative twin of the rule above.
			Pattern:     `\b[Mm]ost\s+(` + superlatives + `)\b`,
			Message:     "Should be \"$1\"",
			Suggest:     "$1",
			Flags:       []string{"that is the most biggest one"},
			Leaves:      []string{"that is the biggest one", "it is the most important one"},
			Category:    "Grammar",
			Explanation: "The \"-est\" ending is already the superlative, so \"most\" in front of it says the same thing twice.",
		},
		GrammarRule{
			// "Can you borrow me your pen?" Borrowing is what the person
			// receiving does; the person handing it over lends.
			Pattern:     `\b([Bb]orrow)\s+(me|him|her|us|them)\b`,
			Message:     "Should be \"lend $2\"",
			Suggest:     "lend $2",
			Flags:       []string{"can you borrow me your pen"},
			Leaves:      []string{"can you lend me your pen", "can I borrow your pen"},
			Category:    "Confused words",
			Explanation: "You borrow something *from* somebody and lend it *to* them. \"Borrow me\" reverses the direction.",
		},
		GrammarRule{
			// "I have been waiting since two hours." "Since" takes the point
			// something started; a length of time takes "for".
			Pattern: `\b([Ss]ince)\s+(\d+|two|three|four|five|six|seven|` +
				`eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty|` +
				`fifty|sixty|ninety|a\s+few|several|many)\s+` +
				`(seconds|minutes|hours|days|weeks|months|years)\b`,
			Message:     "Should be \"for $2 $3\"",
			Suggest:     "for $2 $3",
			Flags:       []string{"I have been waiting since two hours"},
			Leaves:      []string{"I have been waiting for two hours", "I have been here since Tuesday"},
			Category:    "Grammar",
			Explanation: "\"Since\" takes the moment something started -- since Tuesday, since 2019. A length of time takes \"for\".",
		},
		GrammarRule{
			// "Me and my friend went to the cinema." "Me" is the object
			// form, and here it is the subject.
			//
			// The verb after the pair is what makes this safe: without it,
			// "she told me and my friend" -- where "me" really is an object
			// -- matches just as well. The antipattern covers the verbs that
			// take two objects, where a verb still follows further on.
			Pattern: `\b[Mm]e\s+and\s+((?:my|his|her|their|our|the)\s+\w+)\s+` +
				`(went|was|were|are|have|had|did|saw|got|decided|arrived|` +
				`left|came|will|would|both|always|never)\b`,
			Antipatterns: []string{
				`\b(told|gave|showed|saw|asked|let|made|got|sent|brought|` +
					`between|for|with|to)\s+me\s+and\b`,
			},
			Message: "Should be \"$1 and I\"",
			Suggest: "$1 and I $2",
			Flags:   []string{"Me and my friend went to the cinema"},
			Leaves: []string{
				"my friend and I went to the cinema",
				"she told me and my friend the news was good",
			},
			Category:    "Grammar",
			Explanation: "\"Me\" is the object form. Doing the action makes it the subject, which takes \"I\" -- and the other person goes first.",
		},
	)
	return rules
}
