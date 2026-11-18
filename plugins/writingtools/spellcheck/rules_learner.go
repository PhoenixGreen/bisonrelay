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

// uncountable are nouns with no plural, paired with the form wanted.
var uncountable = [][2]string{
	{"furnitures", "furniture"}, {"informations", "information"},
	{"advices", "advice"}, {"equipments", "equipment"},
	{"softwares", "software"}, {"luggages", "luggage"},
	{"homeworks", "homework"}, {"knowledges", "knowledge"},
	{"feedbacks", "feedback"}, {"evidences", "evidence"},
	{"machineries", "machinery"}, {"stuffs", "stuff"},
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

var learnerRules = buildLearnerRules()

func buildLearnerRules() []GrammarRule {
	var rules []GrammarRule

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
