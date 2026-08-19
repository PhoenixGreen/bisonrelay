package spellcheck

// rules_articles.go is "a" against "an".
//
// The rule everybody knows -- "an" before a vowel -- is about *sound*, and
// spelling only mostly agrees with it. "A unique opportunity" and "an hour"
// are both correct and both break the rule as usually stated, because
// "unique" opens with a consonant sound and "hour" opens with a vowel one.
//
// Nothing here can hear anything, so the letters decide and the exceptions
// are listed. That makes this the clearest case in the plugin for
// antipatterns: the rule is one line and the interesting part is entirely
// the two lists of words it must not touch. Written as lookaheads they
// would be unreadable, untestable on their own, and invisible to the corpus
// -- which is exactly where a list this long most needs checking.

const explainArticle = "\"An\" goes before a word that starts with a vowel " +
	"sound and \"a\" before one that starts with a consonant sound. It is " +
	"the sound and not the letter, which is why it is \"a unique offer\" " +
	"and \"an hour\"."

// consonantSoundedVowels are the words that open with a vowel letter and a
// consonant sound, so they take "a".
//
// Two families, plus a couple of strays. The "u" words are the ones said
// "yoo" -- unique, uniform, university -- and the trap in them is that "uni"
// is not the test: "unimportant" and "uninteresting" open the same way on
// paper and take "an". So the stems are spelled out rather than shortened.
// The "eu" words are the same sound from the other direction, and "one" and
// "once" open with a "w".
var consonantSoundedVowels = eitherCaseAlternation([]string{
	`uniqu\w*`, `unicorn\w*`, `unicycl\w*`, `unif\w*`, `union\w*`,
	`unit\w*`, `univers\w*`, `use\w*`, `usu\w*`, `usab\w*`, `usag\w*`,
	`usurp\w*`, `util\w*`, `utensil\w*`, `uter\w*`, `utop\w*`, `ubiq\w*`,
	`ukulele`, `ukelele`, `euro\w*`, `europ\w*`, `eulog\w*`, `euph\w*`,
	`eucalypt\w*`, `eunuch`, `one\b`, `one-\w+`, `once\b`, `ewe\b`,
})

// vowelSoundedConsonants are the words that open with a consonant letter and
// a vowel sound, so they take "an": the silent "h" words.
var vowelSoundedConsonants = eitherCaseAlternation([]string{
	`hour\w*`, `honest\w*`, `honour\w*`, `honor\w*`, `heir\w*`,
})

// initialisms are the letters whose *names* open with a vowel -- F is "ef",
// M is "em", X is "ex" -- so "an MBA" and "an X-ray" are right even though
// the letters are consonants.
// The trailing \b is what makes this cover the whole initialism rather
// than its first two letters. An antipattern has to *contain* the match it
// suppresses, and "an MB" does not contain "an MBA" -- which is exactly how
// this first failed.
const initialisms = `[FHLMNRSX][A-Z0-9]*\b`

var articleRules = []GrammarRule{
	{
		Pattern: `\b([Aa])\s+([AaEeIiOoUu]\w*)`,
		Flags:   []string{"that is a odd effect"},
		Leaves:  []string{"a unique offer", "a one-off", "a European utility", "a useful thing"},
		Antipatterns: []string{
			`\b[Aa]\s+(` + consonantSoundedVowels + `)`,
		},
		Message:     "Should be \"$1n $2\"",
		Suggest:     "$1n $2",
		Category:    "Grammar",
		Explanation: explainArticle,
	},
	{
		// The other half of the silent-h rule, and it was missing: the list
		// above only ever suppressed "an", so "a hour" and "a honest answer"
		// went unflagged while "an dog" was caught. Found by reading a test
		// post out loud -- nothing about the rules themselves says one
		// direction is written and the other is not.
		Pattern: `\b([Aa])\s+(` + vowelSoundedConsonants + `)`,
		Flags:   []string{"it was a hour before anybody replied", "a honest answer"},
		Leaves:  []string{"an hour of honest work", "a house on the hill"},
		Message: "Should be \"$1n $2\"",
		Suggest: "$1n $2",
		// A capital in the middle of a sentence is somebody's name or an
		// initialism, and neither is a word this list is about.
		Category:    "Grammar",
		Explanation: explainArticle,
	},
	{
		// "A MBA" for the same reason: the letter is a consonant and its
		// name opens with a vowel.
		Pattern:     `\b([Aa])\s+(` + initialisms + `)`,
		Flags:       []string{"she has a MBA", "a X-ray booked"},
		Leaves:      []string{"an MBA", "a BBC documentary", "a DVD"},
		Message:     "Should be \"$1n $2\"",
		Suggest:     "$1n $2",
		Category:    "Grammar",
		Explanation: explainArticle,
	},
	{
		Pattern: `\b([Aa])n\s+([B-DF-HJ-NP-TV-Zb-df-hj-np-tv-z]\w*)`,
		Flags:   []string{"that is an dog"},
		Leaves:  []string{"an hour of honest work", "an heir to it", "she has an MBA", "an X-ray booked"},
		Antipatterns: []string{
			`\b[Aa]n\s+(` + vowelSoundedConsonants + `)`,
			`\b[Aa]n\s+` + initialisms,
		},
		Message:     "Should be \"$1 $2\"",
		Suggest:     "$1 $2",
		Category:    "Grammar",
		Explanation: explainArticle,
	},
}

// pluralAfterA pairs a plural with the singular "a" wanted, for the rules
// built below.
//
// A curated list rather than a pattern, because "a" before a word ending in
// "s" is very often correct: a bus, a class, a crisis, a series, a species, a
// means. Those are singular nouns that happen to end in the letter.
//
// Every singular here opens with a consonant, which is not a coincidence --
// it is the condition for being on the list. A vowel-initial singular would
// need the article corrected too, and whether it takes "an" is a question
// about sound rather than spelling: "an update" and "a user" both start with
// a "u". That is the argument the rest of this file exists to have, and there
// is no reason to have it twice.
var pluralAfterA = [][2]string{
	{"years", "year"}, {"days", "day"}, {"weeks", "week"},
	{"months", "month"}, {"minutes", "minute"}, {"seconds", "second"},
	{"decades", "decade"}, {"centuries", "century"}, {"moments", "moment"},
	{"mistakes", "mistake"}, {"reasons", "reason"}, {"results", "result"},
	{"problems", "problem"}, {"questions", "question"}, {"changes", "change"},
	{"versions", "version"}, {"copies", "copy"}, {"files", "file"},
	{"posts", "post"}, {"messages", "message"}, {"comments", "comment"},
	{"users", "user"}, {"wallets", "wallet"}, {"payments", "payment"},
	{"transactions", "transaction"}, {"notes", "note"}, {"lists", "list"},
	{"links", "link"}, {"pages", "page"}, {"words", "word"},
	{"lines", "line"}, {"parts", "part"}, {"places", "place"},
	{"cases", "case"}, {"features", "feature"}, {"projects", "project"},
	{"tools", "tool"}, {"things", "thing"},
}

// pluralHeadFollowers are the words that can follow the plural above, and
// they are the whole of what makes these rules safe.
//
// A plural noun after "a" is usually correct English, because it is
// modifying the noun after it: a sales team, a settings menu, a comments
// section, a payments provider, a results page. Every one of those is right,
// and a rule keyed on "a" plus a plural alone would flag the lot.
//
// What is wrong is a plural that is the head noun itself, and the way to
// know it is the head is that no noun follows it. A preposition, a time
// adverb or the end of the sentence all say so: "a years ago" has nothing
// left for "years" to modify.
const pluralHeadFollowers = `ago|earlier|later|before|after|of|in|on|at|` +
	`for|from|with|to|by|since`

var pluralArticleRules = buildPluralArticleRules()

func buildPluralArticleRules() []GrammarRule {
	rules := make([]GrammarRule, 0, len(pluralAfterA))
	for _, pair := range pluralAfterA {
		plural, singular := pair[0], pair[1]
		rules = append(rules, GrammarRule{
			// The follower is captured and echoed back rather than looked
			// ahead at, so the rule stays inside RE2 and the corpus can run
			// it. The alternative branch is the punctuation that ends a
			// sentence, where there is likewise no noun to modify.
			Pattern: `\b([Aa])\s+` + plural +
				`(\s+(?:` + pluralHeadFollowers + `)\b|[.,;!?])`,
			Message: "Should be \"$1 " + singular + "\"",
			Suggest: "$1 " + singular + "$2",
			Flags: []string{
				"even a " + plural + " ago",
				"it took a " + plural + ".",
			},
			Leaves: []string{
				"we shipped a " + plural + " team",
				"the " + plural + " arrived on time",
			},
			Category: "Grammar",
			Explanation: "\"A\" introduces one of something, so the noun " +
				"after it is singular. \"" + plural + "\" here is the noun " +
				"itself rather than a word describing the next one, which " +
				"is why \"a " + plural + " page\" is fine and this is not.",
		})
	}
	return rules
}
