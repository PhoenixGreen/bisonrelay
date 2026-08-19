package spellcheck

// rules_redundancy.go holds the phrases where one half repeats the other.
//
// Split out of the wordiness table in rules_style.go, where they sat under a
// comment for a long time. They are a different observation and deserve to be
// named as one: "in order to" is a long way of saying "to", where "free gift"
// is not a long way of saying anything -- it is "gift" with a word in front of
// it that adds nothing. A reader shown "Wordy" about "free gift" has to work
// out which word was surplus; a reader shown "Redundant" already knows.
//
// Suggestions, like the wordiness rules, and for the same reason. Every one of
// these is sometimes deliberate -- "advance planning" against planning done
// after the fact, "personal opinion" where the professional one has already
// been given -- and a rule that is usually right and occasionally not belongs
// on the page for opinions rather than under a red line.
//
// The discipline that keeps this list honest is that the shorter form must
// mean the same thing on its own. "Safe haven" was tried and dropped: a haven
// is a refuge, and the safety is not as redundant as it looks once the word is
// used of a tax haven. So was "reason why", which is standard English and only
// redundant to a certain kind of grammarian.

// redundant pairs a phrase with the half of it that carries the meaning.
var redundant = [][2]string{
	{"absolutely essential", "essential"},
	{"actual fact", "fact"},
	{"added bonus", "bonus"},
	{"advance planning", "planning"},
	{"basic fundamentals", "fundamentals"},
	{"brief summary", "summary"},
	{"close proximity", "proximity"},
	{"collaborate together", "collaborate"},
	{"completely eliminate", "eliminate"},
	{"connect together", "connect"},
	{"each and every", "each"},
	{"end result", "result"},
	{"exact same", "same"},
	{"few in number", "few"},
	{"first and foremost", "first"},
	{"free gift", "gift"},
	{"future plans", "plans"},
	{"general consensus", "consensus"},
	{"join together", "join"},
	{"may possibly", "may"},
	{"merge together", "merge"},
	{"mutual cooperation", "cooperation"},
	{"new innovation", "innovation"},
	{"past experience", "experience"},
	{"past history", "history"},
	{"personal opinion", "opinion"},
	{"plan ahead", "plan"},
	{"postpone until later", "postpone"},
	{"repeat again", "repeat"},
	{"return back", "return"},
	{"revert back", "revert"},
	{"rise up", "rise"},
	{"still remains", "remains"},
	{"sum total", "total"},
	{"unexpected surprise", "surprise"},
	{"usual custom", "custom"},
	{"12 midnight", "midnight"},
	{"12 noon", "noon"},
	{"ATM machine", "ATM"},
	{"PIN number", "PIN"},
	{"LCD display", "LCD"},
	// The rest, added when the list was split out. Acronyms whose last letter
	// is the word people then repeat are the most common of these by far, and
	// the ones people are least likely to notice.
	{"true fact", "fact"},
	{"final outcome", "outcome"},
	{"final conclusion", "conclusion"},
	{"end conclusion", "conclusion"},
	{"various different", "various"},
	{"totally unique", "unique"},
	{"completely destroyed", "destroyed"},
	{"consensus of opinion", "consensus"},
	{"advance warning", "warning"},
	{"advance notice", "notice"},
	{"combine together", "combine"},
	{"reply back", "reply"},
	{"could potentially", "could"},
	{"might potentially", "might"},
	{"small in size", "small"},
	{"large in size", "large"},
	{"round in shape", "round"},
	{"time period", "period"},
	{"over exaggerate", "exaggerate"},
	{"old adage", "adage"},
	{"regular routine", "routine"},
	{"HIV virus", "HIV"},
	{"RAM memory", "RAM"},
	{"GPS system", "GPS"},
	{"ISBN number", "ISBN"},
	{"VIN number", "VIN"},
	{"please RSVP", "RSVP"},
}

// redundancyRules are the table above, one rule each.
var redundancyRules = buildRedundancyRules()

func buildRedundancyRules() []GrammarRule {
	rules := make([]GrammarRule, 0, len(redundant))
	for _, pair := range redundant {
		phrase, kept := pair[0], pair[1]
		rules = append(rules, GrammarRule{
			Pattern: `\b` + eitherCase(phrase) + wordBoundary(phrase),
			Message: "Redundant -- \"" + kept + "\" says it",
			Suggest: kept,
			// Generated from the phrase, as the style rules are: a
			// hand-written example beside each of sixty pairs would be sixty
			// chances to paste the wrong phrase next to the wrong pattern.
			Flags:    []string{"it was an " + phrase + " really"},
			Category: "Redundancy",
			Explanation: "\"" + phrase + "\" says the same thing twice -- " +
				"\"" + kept + "\" already covers it. Sometimes the longer " +
				"form is a deliberate contrast, which is why this is a " +
				"suggestion.",
			Severity: SeveritySuggestion,
		})
	}
	return rules
}
