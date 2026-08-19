package spellcheck

import "strings"

// rules_checks.go holds the rules that ask rather than tell.
//
// Every other family in this package answers "is this wrong?" and only fires
// when it can say yes. This one covers the far larger set of cases where the
// honest answer is "it depends what you meant": the word is real, spelled
// correctly and in a position it can legitimately occupy, and it belongs to a
// pair people confuse. "It would brake the system" is the case that prompted
// the file -- a sentence with nothing whatever wrong with it, unless "brake"
// was meant to be "break", which it almost always was.
//
// Why these could not go in rules_confusions.go: an error rule there must
// never fire on correct writing, and there is no expression that catches "it
// would brake the system" and leaves "you would brake hard into the corner".
// Both are a modal and then "brake". Held to the error standard the pair is
// unwritable, which is why most confusable pairs are absent from this plugin
// entirely. Marked SeverityCheck they can be written at all.
//
// What a check owes its reader, enforced by TestCheckRulesAskAQuestion:
//
//	Severity SeverityCheck, so the app underlines it in amber and lists it
//	under Suggestions and Checks rather than among the mistakes.
//
//	A Message phrased as a question. A check that says "Should be \"break\""
//	is claiming what it does not know, and the reader who did mean "brake" is
//	being told they made a mistake they did not make.
//
//	A Suggest. The other spelling is the whole content of the question, and a
//	check with no answer to offer is a rule that interrupts and then asks the
//	reader to work it out.
//
//	Category "Possible confusion", which is what heads the row.
//
// The standard that has not been relaxed is noise. A check is allowed to be
// wrong; it is not allowed to be frequent. Every rule here matches a
// *position* and never a bare word -- flagging each "brake" in a post about
// cycling would teach the reader to ignore the amber mark, and then the tier
// is worth nothing to anybody. Three positions carry all of them, and they
// are the three the rest of the plugin already uses:
//
//	a modal or "to" before a word that is usually a noun    ("would brake")
//	a determiner or adjective before a word that is not one ("wise council")
//	"the ___ of", where what follows settles nothing        ("a peace of")
//
// So the rules are written as data over those three shapes rather than as
// rule literals. Seventeen literals differing in two words each would bury
// the one thing worth reading, which is the pair and the readings it must
// leave alone.
//
// The other half of not being frequent is direction. Only the rarer word of
// a pair is ever flagged: "the tail of two cities" is asked about and "the
// tale of the dog" is not, because a check on the commoner spelling fires
// constantly and is right almost never.

// The explanations for the pairs no error rule already needed a sentence
// for. The rest are shared with rules_confusions.go and the two homophone
// files -- a check and an error about the same pair are teaching the same
// distinction, and saying it twice in two different ways would leave the
// reader wondering whether they are two different rules.
const (
	explainBareBear = "\"Bare\" means uncovered, or to uncover. To \"bear\" " +
		"something is to carry or endure it."
	explainComplimentComplement = "A \"compliment\" is praise. To " +
		"\"complement\" something is to go well with it."
	explainMoralMorale = "A \"moral\" is the lesson of a story, and \"moral\" " +
		"is also an adjective. \"Morale\" is how good the mood is."
	explainStationaryStationery = "\"Stationary\" means not moving. " +
		"\"Stationery\" is paper and envelopes."
	explainPeacePiece = "\"Peace\" is the absence of war or noise. A " +
		"\"piece\" is a part of something."
	explainWaistWaste = "A \"waist\" is the middle of the body. \"Waste\" " +
		"is something used up for nothing."
)

// slotCheck is one confusable pair in one position.
//
// after and before are the readings that settle it -- the words that, when
// they turn up next to the match, mean the spelling as written was right.
// They become antipatterns, and TestAntipatternsAreReachable insists each has
// an example among leaves, so an exception cannot quietly stop matching.
type slotCheck struct {
	// lead is what may stand before the word, as pattern stems. Each is
	// matched in either case, since every one of these positions occurs at
	// the start of a sentence.
	lead []string

	// written is the spelling that appears; meant is the one being asked
	// about.
	written, meant string

	// after are words following the match that mean written was right.
	after []string

	// before are words standing before the lead that mean the same.
	before []string

	// flags must be caught and leaves must not, as everywhere else.
	flags, leaves []string

	explain string
}

// verbSlot is what may precede a verb, which is the position a noun of the
// pair has no business in: "it would brake the system", "we should insure
// they are told".
var verbSlot = []string{
	"would", "will", "could", "should", "might", "may", "must", "can",
	"can't", "don't", "doesn't", "won't", "didn't", "to",
}

// nounSlot is the determiners and the possessives, for the pairs where the
// word written is not a noun at all.
var nounSlot = []string{
	"the", "a", "an", "this", "that", "his", "her", "their", "our", "my",
	"your", "its", "some", "any", "no",
}

// tailOf is the third shape: "___ of", where the word after "of" decides
// nothing. "The tail of the comet" and "the tale of two cities" are the same
// five words, and only the exceptions can tell them apart.
const tailOf = `\s+of`

// checkRule builds one rule from a pair and a position. tail is extra pattern
// after the word and tailText is how it reads in the replacement, which are
// the same characters written twice only because one is a pattern and one is
// literal text.
func checkRule(c slotCheck, tail, tailText string) GrammarRule {
	lead := "(" + eitherCaseAlternation(c.lead) + ")"
	pattern := `\b` + lead + `\s+` + c.written + tail + `\b`

	// Both antipattern shapes are written out from the lead rather than from
	// the word, because an exception suppresses only where it *contains* the
	// match -- see GrammarRule.Antipatterns. `brake\s+hard` does not cancel a
	// match that started at "would", and an exception that never suppresses
	// anything is the quietest way to ship a noisy rule.
	var antipatterns []string
	unlead := "(?:" + eitherCaseAlternation(c.lead) + ")"
	if len(c.after) > 0 {
		antipatterns = append(antipatterns, `\b`+unlead+`\s+`+c.written+tail+
			`\s+(?:`+strings.Join(c.after, "|")+`)\b`)
	}
	if len(c.before) > 0 {
		antipatterns = append(antipatterns, `\b(?:`+
			eitherCaseAlternation(c.before)+`)\s+`+unlead+`\s+`+c.written+tail+`\b`)
	}

	return GrammarRule{
		Pattern:      pattern,
		Antipatterns: antipatterns,
		Flags:        c.flags,
		Leaves:       c.leaves,
		Message:      `Did you mean "$1 ` + c.meant + tailText + `"?`,
		Suggest:      `$1 ` + c.meant + tailText,
		Category:     "Possible confusion",
		Severity:     SeverityCheck,
		Explanation:  c.explain,
	}
}

// The three positions, as constructors. Each fills in the lead a pair in that
// position takes, so an entry below carries only what is particular to it.
func verbCheck(c slotCheck) GrammarRule {
	c.lead = verbSlot
	return checkRule(c, "", "")
}

func nounCheck(c slotCheck) GrammarRule {
	if c.lead == nil {
		c.lead = nounSlot
	}
	return checkRule(c, "", "")
}

func ofCheck(c slotCheck) GrammarRule {
	if c.lead == nil {
		c.lead = nounSlot
	}
	return checkRule(c, tailOf, " of")
}

// checkRules are the questions. See the note above before adding one.
var checkRules = concat(verbSlotChecks, nounSlotChecks, ofPhraseChecks)

// verbSlotChecks: a noun of the pair standing where the verb belongs.
var verbSlotChecks = []GrammarRule{
	// The pair the tier was built for. "Brake" after a modal is the driving
	// verb or it is "break", and only the adverbs of braking and the verbs
	// that introduce it settle which.
	verbCheck(slotCheck{
		written: "brake", meant: "break",
		after: []string{"hard", "harder", "sharply", "suddenly", "gently",
			"late", "early", "in\\s+time", "for\\s+the", "before\\s+the"},
		before: []string{"had", "have", "has", "having", "need", "needs",
			"needed", "start", "starts", "started", "begin", "began",
			"about", "going", "forced", "able", "try", "tried"},
		flags: []string{
			"It would brake the system",
			"that could brake the build",
			"we don't want to brake anything",
		},
		leaves: []string{
			"I had to brake hard on the hill",
			"you would brake sharply into that corner",
			"it would break the system",
		},
		explain: explainBrakeBreak,
	}),
	// "Insure" a car is right and "insure that" is not, but the object is
	// often a noun that could be either, so this asks.
	verbCheck(slotCheck{
		written: "insure", meant: "ensure",
		after: []string{"the\\s+car", "your\\s+car", "the\\s+house",
			"your\\s+home", "the\\s+property", "the\\s+van", "the\\s+boat",
			"it\\s+against", "them\\s+against", "against"},
		flags: []string{
			"we must insure the work is finished",
			"to insure a fair result",
		},
		leaves: []string{
			"we should insure the car before driving it",
			"we must ensure the work is finished",
		},
		explain: explainEnsureInsure,
	}),
	// "Effect" is a verb in the narrow sense of bringing something about,
	// and that sense keeps a short and listable company.
	verbCheck(slotCheck{
		written: "effect", meant: "affect",
		// The verb "effect" and its short list of objects, and then the
		// determiners -- not because "will effect the outcome" is right, but
		// because rules_confusions.go already corrects it outright. A check
		// over the same words would report it twice in two colours.
		after: []string{"change", "changes", "a\\s+change", "a\\s+cure",
			"savings", "repairs", "a\\s+rescue", "a\\s+recovery",
			"a\\s+transformation", "reforms?",
			"the", "a", "an", "my", "your", "his", "her", "our", "their",
			"you", "me", "us", "them", "him", "it"},
		flags: []string{
			"this could effect everyone",
			"it might effect performance",
		},
		leaves: []string{
			"they hoped to effect change quickly",
			"it will effect the outcome",
			"this could affect everyone",
		},
		explain: explainAffectEffect,
	}),
	// "Bare" is a verb -- you bare your soul -- and everything it takes is
	// a possessive and a part of the body.
	verbCheck(slotCheck{
		written: "bare", meant: "bear",
		after: []string{"his", "her", "its", "their", "your", "my", "all",
			"the\\s+scars"},
		flags: []string{
			"I can't bare to watch",
			"more than she could bare",
		},
		leaves: []string{
			"he would bare his soul to anyone",
			"I can't bear to watch",
		},
		explain: explainBareBear,
	}),
	// Paying a compliment and completing something are both ordinary, and
	// what separates them is who or what is on the end of it.
	verbCheck(slotCheck{
		written: "compliment", meant: "complement",
		after: []string{"her", "him", "them", "you", "me", "us",
			"the\\s+chef", "the\\s+cook", "the\\s+host", "someone"},
		flags: []string{
			"the sauce will compliment the fish",
			"a colour to compliment the room",
		},
		leaves: []string{
			"I must compliment the chef on that",
			"the sauce will complement the fish",
		},
		explain: explainComplimentComplement,
	}),
}

// nounSlotChecks: a word that is not a noun standing where one belongs.
var nounSlotChecks = []GrammarRule{
	// "Moral" is a noun in exactly one construction -- the moral of the
	// story -- and an adjective everywhere else, where the noun wanted was
	// almost always "morale".
	nounCheck(slotCheck{
		lead: []string{"the", "team", "staff", "troop", "company", "our",
			"their", "his", "her", "low", "high", "poor", "good"},
		written: "moral", meant: "morale",
		after: []string{"of\\s+the\\s+story", "of\\s+this", "compass",
			"high\\s+ground", "obligation", "obligations", "duty", "support",
			"imperative", "panic", "victory", "code", "hazard"},
		flags: []string{
			"the moral in the office is poor",
			"low moral across the team",
		},
		leaves: []string{
			"the moral of the story is patience",
			"the morale in the office is poor",
		},
		explain: explainMoralMorale,
	}),
	// "Stationary" is an adjective and needs its noun; without one, the
	// noun that was wanted is the paper.
	nounCheck(slotCheck{
		lead:    []string{"the", "some", "our", "new", "more", "office", "any"},
		written: "stationary", meant: "stationery",
		after: []string{"car", "cars", "vehicle", "van", "bike", "object",
			"objects", "target", "position", "state", "front", "cycle",
			"engine", "train", "bus", "traffic"},
		flags: []string{
			"we need more stationary for the office",
			"our stationary arrived today",
		},
		leaves: []string{
			"the stationary car blocked the road",
			"we need more stationery for the office",
		},
		explain: explainStationaryStationery,
	}),
	// "Discrete" means separate, and what it separates is countable. Where
	// the noun is a manner or a word, the meaning wanted was the careful one.
	nounCheck(slotCheck{
		lead:    []string{"a", "the", "very", "quite", "more", "being", "was", "is"},
		written: "discrete", meant: "discreet",
		after: []string{"units?", "steps?", "values?", "categor(?:y|ies)",
			"parts?", "components?", "packets?", "chunks?", "intervals?",
			"sets?", "variables?", "events?", "states?", "quantit(?:y|ies)"},
		flags: []string{
			"a discrete word in his ear",
			"the discrete approach worked",
		},
		leaves: []string{
			"a discrete set of values",
			"a discreet word in his ear",
		},
		explain: explainDiscreetDiscrete,
	}),
	// A council is a body of people and counsel is what you are given, and
	// the adjectives that reach for one almost never mean the other.
	nounCheck(slotCheck{
		// Not legal/wise/sound/good, which rules_homophones.go corrects
		// outright -- those adjectives never take the governing body.
		lead: []string{"his", "her", "their", "our", "my", "expert",
			"independent", "impartial", "professional", "the"},
		written: "council", meant: "counsel",
		after: []string{"meeting", "meetings", "member", "members", "chamber",
			"leader", "offices?", "elections?", "workers?", "house", "houses",
			"tax", "estate", "flat", "seat", "seats"},
		flags: []string{
			"his council was worth having",
			"we took expert council on it",
		},
		leaves: []string{
			"the council meeting ran late",
			"his counsel was worth having",
		},
		explain: explainCouncilCounsel,
	}),
}

// ofPhraseChecks: "the ___ of", where the words on either side settle
// nothing at all.
var ofPhraseChecks = []GrammarRule{
	// The story direction only. "The tale of the dog" is caught by the error
	// rule in rules_homophones.go, which has the animal to go on; this is the
	// other way round, where what follows "of" decides nothing.
	ofCheck(slotCheck{
		written: "tail", meant: "tale",
		after: []string{"the\\s+dog", "the\\s+cat", "a\\s+dog", "a\\s+cat",
			"dog", "cat", "fish", "horse", "whale", "fox", "the\\s+comet",
			"comet", "the\\s+plane", "plane", "aircraft", "jet", "kite",
			"snake", "lizard", "the\\s+animal", "bird"},
		flags: []string{
			"the tail of two cities",
			"a tail of woe and misfortune",
		},
		leaves: []string{
			"the tail of the comet was visible",
			"she told a tale of two cities",
		},
		explain: explainTailTale,
	}),
	// The one position where both are ordinary English and neither is
	// likelier on the words alone: a school has a principal of its own, and
	// a design has a principle.
	ofCheck(slotCheck{
		written: "principal", meant: "principle",
		after: []string{"the\\s+school", "the\\s+college", "the\\s+academy",
			"the\\s+university", "the\\s+department", "our\\s+school",
			"my\\s+school", "school", "college", "academy", "university"},
		flags: []string{
			"the principal of least surprise",
			"a principal of good design",
		},
		leaves: []string{
			"the principal of the school met us",
			"the principle of least surprise",
		},
		explain: explainPrincipal,
	}),
	// A waist is a part of a garment or a body, and those are what it is
	// ever "of".
	ofCheck(slotCheck{
		written: "waist", meant: "waste",
		after: []string{"the\\s+dress", "her\\s+dress", "his\\s+trousers",
			"the\\s+skirt", "dress", "skirt", "trousers", "jeans", "coat",
			"gown", "garment", "the\\s+jacket"},
		flags: []string{
			"that was a waist of time",
			"a waist of good food",
		},
		leaves: []string{
			"the waist of the dress was taken in",
			"that was a waste of time",
		},
		explain: explainWaistWaste,
	}),
	// A hoard is a store of things and a horde is a crowd, and both are
	// "of" whatever they are made of.
	ofCheck(slotCheck{
		written: "hoard", meant: "horde",
		after: []string{"gold", "treasure", "coins", "silver", "cash",
			"supplies", "food", "weapons", "junk", "stuff", "tinned\\s+food",
			"toilet\\s+paper", "old\\s+\\w+"},
		flags: []string{
			"a hoard of angry customers",
			"a hoard of commuters",
		},
		leaves: []string{
			"a hoard of gold was found",
			"a horde of angry customers",
		},
		explain: explainHoardHorde,
	}),
	// Rain falls and a reign is a period of rule, and each is "of"
	// something the other could be.
	ofCheck(slotCheck{
		written: "rain", meant: "reign",
		after: []string{"arrows", "blows", "bullets", "fire", "ash", "debris",
			"frogs", "sparks", "stones", "confetti"},
		flags: []string{
			"the rain of Queen Victoria",
			"a rain of terror lasting years",
		},
		leaves: []string{
			"a rain of arrows fell on them",
			"the reign of Queen Victoria",
		},
		explain: explainRainReign,
	}),
}
