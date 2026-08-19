package spellcheck

import "strings"

// rules_style.go holds the opinions: phrases that could be shorter, phrases
// worn smooth by overuse, and the passive voice.
//
// Every rule here is marked SeveritySuggestion, and that mark is what makes
// the file possible at all. The rest of this plugin holds to a standard of
// firing only on text that is wrong whatever the writer meant, because an
// alarming red underline under correct writing teaches people to stop reading
// underlines. None of these meet that standard -- "in order to" is not an
// error, and sometimes it is the better phrasing.
//
// They are shipped anyway because the app underlines suggestions in a
// different colour and lists them on their own page, so the cost of being
// wrong is a quieter mark in a place the reader went looking for opinions.
// That is a different bargain from the one the error rules make, and these
// rules would not be acceptable under the other one.

// wordy pairs a phrase with what it usually shortens to. Held as data rather
// than as rule literals because there are dozens of them and they differ in
// nothing but the two strings; written out longhand, the shape of each rule
// would bury the list itself.
//
// Long-windedness only. The phrases where one half repeats the other used to
// live at the bottom of this table under a comment, and they are a different
// observation about the writing -- "free gift" is not a long way of saying
// "gift", it is "gift" with a word in front of it that adds nothing. They now
// have their own table, their own wording and their own heading in the panel:
// see rules_redundancy.go.
//
// A pair belongs here only if the replacement is a fair paraphrase in most
// contexts. "Protest against" was tried and dropped: it is standard British
// English, not padding.
var wordy = [][2]string{
	// Phrases that say in several words what one word says.
	{"a large number of", "many"},
	{"a majority of", "most"},
	{"a number of", "several"},
	{"are able to", "can"},
	{"as a matter of fact", "in fact"},
	{"at the present time", "now"},
	{"at this point in time", "now"},
	{"by means of", "by"},
	{"come to the conclusion that", "conclude that"},
	{"despite the fact that", "although"},
	{"during the course of", "during"},
	{"for the purpose of", "for"},
	{"for the reason that", "because"},
	{"has the ability to", "can"},
	{"have the ability to", "can"},
	{"in a timely manner", "promptly"},
	{"in an effort to", "to"},
	{"in close proximity to", "near"},
	{"in excess of", "more than"},
	{"in light of the fact that", "because"},
	{"in regard to", "about"},
	{"in spite of the fact that", "although"},
	{"in the absence of", "without"},
	{"in the event that", "if"},
	{"in order to", "to"},
	{"in the near future", "soon"},
	{"is able to", "can"},
	{"it is important to note that", "note that"},
	{"make a decision", "decide"},
	{"on a daily basis", "daily"},
	{"on a regular basis", "regularly"},
	{"on account of", "because of"},
	{"owing to the fact that", "because"},
	{"prior to", "before"},
	{"subsequent to", "after"},
	{"take into consideration", "consider"},
	{"there is no doubt that", "undoubtedly"},
	{"until such time as", "until"},
	{"with regard to", "about"},
	{"with the exception of", "except"},
}

// cliches are phrases that have been used so often they no longer carry the
// image they were built on, each with the plain phrase that says the same
// thing.
//
// The replacements were left out of the first version of this file on the
// grounds that there is no single rewrite for a cliche. That was true of some
// of them and used as an excuse for all of them: most of these are worn
// precisely because they are a long way of saying one ordinary word, and
// "ultimately" for "at the end of the day" loses nothing at all.
//
// The two with an empty replacement are the ones where it really is true.
// "The tip of the iceberg" and "the elephant in the room" are both carrying
// an argument, not just a word, and the shortest honest replacement is a
// clause that depends on what the sentence is about. Those are flagged and
// left to the writer.
var cliches = [][2]string{
	{"at the end of the day", "ultimately"},
	{"think outside the box", "think differently"},
	{"low-hanging fruit", "the easy wins"},
	{"moving forward", "from now on"},
	{"going forward", "from now on"},
	{"touch base", "talk"},
	{"circle back", "follow up"},
	{"at this juncture", "now"},
	{"needless to say", "obviously"},
	{"last but not least", "finally"},
	{"in this day and age", "today"},
	{"the bottom line is", "in short"},
	{"win-win", "good for both sides"},
	{"take it to the next level", "improve it"},
	{"boots on the ground", "people on site"},
	{"push the envelope", "go further"},
	{"when all is said and done", "ultimately"},
	{"few and far between", "rare"},
	{"tip of the iceberg", ""},
	{"par for the course", "typical"},
	{"back to the drawing board", "start again"},
	{"a level playing field", "fair conditions"},
	{"the elephant in the room", ""},
	{"raise the bar", "set a higher standard"},
	{"move the needle", "make a difference"},
}

// participles are past participles distinctive enough that "was <participle>
// by" cannot be anything but the passive. Irregular forms only: an -ed word
// after "was" is far more often an adjective ("was tired", "was interested")
// than a passive verb.
const participles = `written|taken|given|made|sent|held|chosen|brought|sold|` +
	`spoken|built|driven|seen|done|known|paid|met|kept|left|told|taught|` +
	`understood|won|run|read|put|caught|bought|found|felt|meant|thought|` +
	`said|eaten|broken|shown|worn|torn|drawn|grown|thrown`

// styleRules are the opinions, built from the tables above plus the two
// passive-voice checks.
var styleRules = buildStyleRules()

func buildStyleRules() []GrammarRule {
	rules := make([]GrammarRule, 0, len(wordy)+len(cliches)+2)

	for _, pair := range wordy {
		rules = append(rules, GrammarRule{
			Pattern: `\b` + eitherCase(pair[0]) + `\b`,
			Message: "Wordy -- try \"" + pair[1] + "\"",
			Suggest: pair[1],
			// Generated with the rule, from the phrase it is about. A
			// hand-written example for each of ninety pairs would be ninety
			// chances to paste the wrong phrase beside the wrong pattern.
			Flags:    []string{"we wrote " + pair[0] + " today"},
			Category: "Style",
			Explanation: "\"" + pair[0] + "\" can usually be shortened to \"" +
				pair[1] + "\" without losing anything. Shorter is easier to " +
				"read, though the longer form is sometimes the one you want.",
			Severity: SeveritySuggestion,
		})
	}

	for _, pair := range cliches {
		phrase, plain := pair[0], pair[1]
		message, advice := "Overused phrase", "Saying it plainly usually "+
			"lands better."
		if plain != "" {
			message = "Overused phrase -- try \"" + plain + "\""
			advice = "\"" + plain + "\" says the same thing."
		}
		rules = append(rules, GrammarRule{
			// Hyphens and other punctuation are escaped; the \b at the end is
			// dropped for phrases ending in a non-word character, where it
			// would never match.
			Pattern:  `\b` + eitherCase(phrase) + wordBoundary(phrase),
			Message:  message,
			Suggest:  plain,
			Flags:    []string{"we wrote " + phrase + " today"},
			Category: "Style",
			Explanation: "\"" + phrase + "\" is used so often that it no " +
				"longer carries the picture it was built on. " + advice,
			Severity: SeveritySuggestion,
		})
	}

	rules = append(rules,
		GrammarRule{
			// Passive with a named agent. The "by" is what makes this
			// certain, and requiring it is a deliberate trade: most passive
			// writing names no agent and goes unflagged here, which is the
			// price of never flagging "I was interested" as passive.
			Pattern: `\b([iI]s|[aA]re|[wW]as|[wW]ere|[bB]e|[bB]een|[bB]eing)\s+(` + participles + `)\s+by\b`,
			Message: "Passive voice",
			Suggest: "",
			Flags:   []string{"the post was written by someone else"},
			// The agent is what makes this certain, and the reason most
			// passive writing goes unflagged -- see the note above.
			Leaves:   []string{"I was interested in the result"},
			Category: "Style",
			Explanation: "This sentence puts the thing acted on first " +
				"and the actor last -- \"the post was written by Sam\" " +
				"rather than \"Sam wrote the post\". Turning it round is " +
				"usually shorter and clearer. No replacement is offered " +
				"because the fix moves the words either side of this, " +
				"which only you can do -- and the passive is right when " +
				"the actor is unknown or beside the point.",
			Severity: SeveritySuggestion,
		},
		GrammarRule{
			// "Is being considered" is unambiguously passive with or without
			// an agent: "being" before a participle admits no adjective
			// reading.
			Pattern:  `\b([iI]s|[aA]re|[wW]as|[wW]ere)\s+being\s+(\w+ed|` + participles + `)\b`,
			Message:  "Passive voice",
			Suggest:  "",
			Flags:    []string{"the plan is being considered again"},
			Leaves:   []string{"she was being careful about it"},
			Category: "Style",
			Explanation: "This sentence puts the thing acted on first " +
				"and the actor last -- \"the post was written by Sam\" " +
				"rather than \"Sam wrote the post\". Turning it round is " +
				"usually shorter and clearer. No replacement is offered " +
				"because the fix moves the words either side of this, " +
				"which only you can do -- and the passive is right when " +
				"the actor is unknown or beside the point.",
			Severity: SeveritySuggestion,
		},
	)

	return rules
}

var VariantPairs = []string{
	"organise|organize",
	"organised|organized",
	"organisation|organization",
	"realise|realize",
	"recognise|recognize",
	"analyse|analyze",
	"apologise|apologize",
	"summarise|summarize",
	"prioritise|prioritize",
	"customise|customize",
	"optimise|optimize",
	"utilise|utilize",
	"emphasise|emphasize",
	"criticise|criticize",
	"specialise|specialize",
	"minimise|minimize",
	"maximise|maximize",
	"colour|color",
	"colours|colors",
	"favourite|favorite",
	"behaviour|behavior",
	"honour|honor",
	"labour|labor",
	"neighbour|neighbor",
	"centre|center",
	"defence|defense",
	"grey|gray",
	"theatre|theater",
	"fibre|fiber",
	"litre|liter",
	"travelled|traveled",
	"cancelled|canceled",
	"catalogue|catalog",
	"dialogue|dialog",
	"aluminium|aluminum",
	"judgement|judgment",
	"acknowledgement|acknowledgment",
	"focussed|focused",
	"modelling|modeling",
	"labelled|labeled",
	"fulfil|fulfill",
	"enrol|enroll",
	"instil|instill",
	"skilful|skillful",
}

// coherencyPairs are forms that are both correct in the same English, and
// still should not be mixed inside one message.
//
// Kept apart from variantPairs, which is a list of British against American
// and is also what the thesaurus reduces a British spelling through to reach
// WordNet. Adding "email|e-mail" there would have told that lookup the two
// were a locale pair, which they are not.
var coherencyPairs = []string{
	"email|e-mail",
	"emails|e-mails",
	"cooperate|co-operate",
	"cooperation|co-operation",
	"coordinate|co-ordinate",
	"coordination|co-ordination",
	"online|on-line",
	"ebook|e-book",
	"percent|per cent",
	"okay|ok",
	"benefited|benefitted",
	"focused|focussed",
}

// consistencyPairs is everything the spelling-consistency check compares.
//
// Deliberately not the same thing as either list on its own: one is about
// which English somebody writes and the other about which of two accepted
// forms they picked, and the check does not care about the difference --
// it only reports that a message used both.
var consistencyPairs = append(append([]string{}, VariantPairs...),
	coherencyPairs...)

// SplitVariant is here so the pair format has exactly one reader; the app
// parses the same strings and the two must agree on the separator.
//
// Exported alongside VariantPairs because the thesaurus needs the same list:
// WordNet is American, so a British spelling has no entry of its own and has
// to be reduced to its pair before it can be looked up. Two copies of this
// list would drift, and the two features would then disagree about which
// spellings are the same word.
func SplitVariant(pair string) (string, string, bool) {
	british, american, found := strings.Cut(pair, "|")
	if !found || british == "" || american == "" {
		return "", "", false
	}
	return british, american, true
}
