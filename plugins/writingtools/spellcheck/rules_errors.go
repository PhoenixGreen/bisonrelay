package spellcheck

// domainTLDs are the endings that mark a dot as part of a web address rather
// than the end of a sentence. Not exhaustive, and cannot be: it is a
// heuristic standing in for "is this a hostname", which no regex can decide.
const domainTLDs = "com|org|net|edu|gov|mil|int|io|dev|app|xyz|info|biz|tv|" +
	"ai|gg|rs|sh|ly|cc|onion|uk|de|fr|ru|au|ca|us|jp|cn|nz|za|eu|ch|nl|se|" +
	"tech|site|online|store|blog|news|wiki|link|page|pro|me|co|gl|fm"

// errorRules are the checks that fire only on text that is wrong.
//
// Every rule here is deliberately conservative, because a false positive
// costs far more than a missed error: a wavy underline under correct writing
// trains people to ignore the feature entirely. So each one fires only on
// text that is wrong regardless of context, and anything needing to know
// what a sentence *means* is left out. That rules out the whole family of
// checks people expect from a word processor -- subject/verb agreement,
// their/there, its/it's, a/an before an acronym -- none of which a regex can
// decide without guessing.
var errorRules = []GrammarRule{
	// --- doubled input: almost always a slip of the hands ---
	{
		Pattern:     `\b(\w+)([ \t]+)\1\b`,
		Flags:       []string{"the the payment"},
		Message:     "Repeated word",
		Suggest:     "$1",
		Category:    "Grammar",
		Explanation: "The same word appears twice in a row. This is nearly always a slip while typing rather than something intended.",
	},
	{
		Pattern:     `[ ]{2,}`,
		Flags:       []string{"hello  world"},
		Message:     "Multiple spaces",
		Suggest:     " ",
		Category:    "Spacing",
		Explanation: "There is more than one space between these words. A single space is standard, and the extra ones show up as an uneven gap.",
	},
	{
		Pattern:     `([,;:])\1+`,
		Flags:       []string{"stop,, and think"},
		Message:     "Repeated punctuation",
		Suggest:     "$1",
		Category:    "Punctuation",
		Explanation: "The same punctuation mark appears more than once in a row. One is enough.",
	},

	// --- spacing around punctuation ---
	{
		Pattern:     `[ \t]+([,.!?;:])`,
		Flags:       []string{"hello , world"},
		Message:     "Space before punctuation",
		Suggest:     "$1",
		Category:    "Spacing",
		Explanation: "In English, punctuation attaches to the word before it with no space in between.",
	},
	{
		// Fires whatever the case of the next letter, and fixes both faults
		// at once: "(if you are free).what's" becomes ". What's". Restricted
		// to a capital, this missed exactly that -- a run-together sentence
		// whose next word was also left lower case fell between this rule and
		// the capitalisation one, since each assumed the other's condition.
		//
		// Two guards keep it off text that is not a sentence boundary. The
		// lookbehind wants two word characters or a closing bracket before
		// the stop, which excludes initialisms ("e.g.", "U.S.A."). The
		// lookahead excludes a domain, either directly ("example.com") or
		// through further labels ("news.ycombinator.com").
		//
		// The domain list deliberately omits ccTLDs that are ordinary English
		// words -- it, is, at, in, so, be, no -- because a sentence starts
		// with one of those far more often than a chat mentions example.it,
		// and a missed flag costs less than a wrong one.
		Pattern: `(?<=\w\w|[)\]"'])([.!?])(?!(?:` + domainTLDs +
			`)\b|[\w-]*\.(?:` + domainTLDs + `)\b)([A-Za-z])`,
		Message: "Missing space after punctuation",
		Suggest: "$1 $U2",
		Flags:   []string{"(if you are free).what's next"},
		Leaves: []string{
			"see example.com for details",
			"news.ycombinator.com is worth a look",
			"e.g. this one, i.e. that one",
		},
		Category:    "Spacing",
		Explanation: "Punctuation is followed by a space, which separates it from the next word. Without one the two run together.",
	},
	{
		Pattern:     `([,;:])([A-Za-z])`,
		Flags:       []string{"stop,and think"},
		Leaves:      []string{"it cost 1,000 today"},
		Message:     "Missing space after punctuation",
		Suggest:     "$1 $2",
		Category:    "Spacing",
		Explanation: "Punctuation is followed by a space, which separates it from the next word. Without one the two run together.",
	},
	{
		Pattern:     `\(\s+`,
		Flags:       []string{"read ( this ) again"},
		Message:     "Space inside bracket",
		Suggest:     "(",
		Category:    "Spacing",
		Explanation: "Brackets sit tight against the text they enclose, with no space just inside them.",
	},
	{
		Pattern:     `\s+\)`,
		Flags:       []string{"read (this ) again"},
		Message:     "Space inside bracket",
		Suggest:     ")",
		Category:    "Spacing",
		Explanation: "Brackets sit tight against the text they enclose, with no space just inside them.",
	},

	// --- capitalisation with one unambiguous answer ---
	{
		// The pronoun is the only single letter that is always capitalised,
		// which is what makes this safe to correct outright.
		//
		// A dot on either side means an initialism -- "i.e." -- and not the
		// pronoun at all. That costs the rule a genuine "i" ending a
		// sentence, which is a sentence hardly anyone writes.
		Pattern:     `(?<!\.)\bi\b(?!\.)`,
		Flags:       []string{"yesterday i left"},
		Leaves:      []string{"see e.g. i.e. for details"},
		Message:     "\"I\" is capitalised",
		Suggest:     "I",
		Category:    "Capitalization",
		Explanation: "The pronoun \"I\" is always written as a capital, wherever it appears in a sentence. It is the only single-letter word in English that is.",
	},
	{
		// Lowercase only: the point is the missing capital, so accepting
		// "I'm" here would flag the correct spelling.
		Pattern:     `\bi'(m|ve|ll|d)\b`,
		Flags:       []string{"i'm going now"},
		Message:     "\"I\" is capitalised",
		Suggest:     "I'$1",
		Category:    "Capitalization",
		Explanation: "The pronoun \"I\" is always written as a capital, wherever it appears in a sentence. It is the only single-letter word in English that is.",
	},

	// --- contractions people reliably mistype ---
	// Each of these is wrong in every context, unlike its/it's, which is
	// exactly why those two are absent.
	{
		Pattern:     `\b[yY]our welcome\b`,
		Flags:       []string{"your welcome to try"},
		Message:     "Should be \"you're welcome\"",
		Suggest:     "you're welcome",
		Category:    "Confused words",
		Explanation: "\"Your\" is a possessive, as in \"your wallet\". The phrase means \"you are welcome\", so it needs \"you're\".",
	},
	{
		Pattern:     `\b([cC]ould|[sS]hould|[wW]ould|[mM]ust|[mM]ight)\s+of\b`,
		Flags:       []string{"we should of gone"},
		Message:     "Should be \"$1 have\"",
		Suggest:     "$1 have",
		Category:    "Confused words",
		Explanation: "\"Could of\" is a misreading of how \"could've\" sounds. The spoken contraction is short for \"could have\".",
	},
	{
		Pattern:     `\b[aA]lot\b`,
		Flags:       []string{"thanks alot for that"},
		Message:     "\"a lot\" is two words",
		Suggest:     "a lot",
		Category:    "Grammar",
		Explanation: "\"A lot\" is always written as two words. \"Alot\" is not a word in English.",
	},
	{
		Pattern:     `\b[eE]veryday (I|you|we|they|he|she|it)\b`,
		Flags:       []string{"everyday I walk there"},
		Leaves:      []string{"an everyday problem"},
		Message:     "\"every day\" is two words as an adverb",
		Suggest:     "every day $1",
		Category:    "Grammar",
		Explanation: "\"Everyday\" as one word is an adjective meaning ordinary, as in \"an everyday problem\". Saying when something happens takes two words.",
	},
	{
		Pattern:     `\b[lL]ets\s+(go|see|say|try|talk|do|get|make)\b`,
		Flags:       []string{"lets go now"},
		Message:     "Missing apostrophe",
		Suggest:     "let's $1",
		Category:    "Punctuation",
		Explanation: "This is a contraction -- two words shortened into one -- and the apostrophe stands in for the letters that were dropped.",
	},

	{
		// The whole word is matched, not just its first letter, so the fix
		// reads as the word it produces: right-clicking "in" at the start of
		// a sentence offers "In", where offering the bare "I" looked like a
		// suggestion to replace the word with the pronoun.
		//
		// The tail keeps apostrophes, so "that's" is flagged and corrected
		// whole. Matching only word characters stopped at the apostrophe and
		// offered "That" for it, which reads as a proposal to drop the "'s".
		//
		// The preceding punctuation is matched in a lookbehind rather than a
		// capture, so the flagged span starts at the word. Written as a
		// capture, the span began at the previous sentence's full stop, which
		// underlined text that was not wrong and -- because a right-click
		// selects the word under the pointer -- meant clicking the offending
		// letter often missed the span entirely while clicking the full stop
		// beside it worked.
		//
		// A newline counts as a sentence break in its own right, not only
		// one preceded by a full stop. A new paragraph is the commonest
		// place for a missing capital and the lookbehind, which sees exactly
		// the characters immediately before the letter, saw only the second
		// of the two newlines between paragraphs and so never fired there.
		//
		// $U1 upper-cases the captured letter; a literal template cannot,
		// since the letter to capitalise is whatever was typed.
		//
		// This is the noisiest rule here by some way: plenty of people write
		// chat entirely in lower case on purpose, and it flags the first word
		// of every sentence they send. It is included because a missing
		// capital is a real error and the fix is unambiguous, but it is the
		// first rule to drop if the underlines become wallpaper.
		Pattern:     `(?<=^|[.!?]\s|\n)([a-z])([a-z0-9']*)`,
		Flags:       []string{"the payment cleared. then we left"},
		Message:     "Sentence should start with a capital",
		Suggest:     "$U1$2",
		Category:    "Capitalization",
		Explanation: "A sentence begins with a capital letter. This applies at the start of a new paragraph as well as after a full stop.",
	},

	// --- confusions with a decidable answer ---
	// their/there/they're normally needs to know what a sentence means, which
	// is why the general case is absent. These are the positions where it
	// does not: "their" is a possessive, so a pronoun or a verb cannot follow
	// it, whatever the sentence is about.
	{
		Pattern:     `\b[tT]heir\s+(is|are|was|were|will|would|has|have|had)\b`,
		Flags:       []string{"their is a problem"},
		Leaves:      []string{"their wallet is empty"},
		Message:     "Should be \"there $1\"",
		Suggest:     "there $1",
		Category:    "Confused words",
		Explanation: "\"Their\" is a possessive and has to own something, as in \"their wallet\". A verb or a pronoun cannot follow it, so this needs \"there\".",
	},
	{
		Pattern:     `\b[tT]heir\s+(he|she|it|we|they|you)\b`,
		Flags:       []string{"their he goes"},
		Message:     "Should be \"there $1\"",
		Suggest:     "there $1",
		Category:    "Confused words",
		Explanation: "\"Their\" is a possessive and has to own something, as in \"their wallet\". A verb or a pronoun cannot follow it, so this needs \"there\".",
	},
	{
		// its/it's needs to know what the sentence means, which is why the
		// general case is absent -- both are real words and either can
		// follow almost anything. These are the positions where it is
		// decidable: "its" is a possessive, so a verb cannot follow it.
		// The leading letter is captured rather than written literally, so
		// the rule fires on "Its" at the start of a sentence -- which is
		// where it most often goes wrong -- and puts the case back.
		//
		// The list is words no possessive can be followed by, whatever the
		// sentence: articles, adverbs, other possessives, and adjectives.
		// Verbs are the tempting addition and mostly unsafe -- see the note
		// below on -ing nouns -- so only weather verbs, which cannot follow
		// a possessive at all, are here.
		// The list is words a possessive genuinely cannot precede -- and it
		// is much shorter than it first appears. Adjectives were tried and
		// removed when the corpus caught "Its true value", "Its cold
		// storage" and "Its best feature": almost any adjective reads fine
		// after a possessive, as does almost any verb used as a noun ("its
		// going rate", "its freezing point").
		//
		// What is left cannot be misread. A determiner never follows a
		// possessive, nor does another possessive; "raining" and "snowing"
		// are not nouns at all; and "going to" as a phrase is unambiguous
		// where the bare "going" is not.
		Pattern: `\b([Ii])ts\s+(a|an|the|not|been|my|your|our|his|her|their|` +
			`raining|snowing|too|going\s+to)\b`,
		Flags:       []string{"its raining outside"},
		Leaves:      []string{"its true value is unclear"},
		Message:     "Should be \"$1t's $2\"",
		Suggest:     "$1t's $2",
		Category:    "Confused words",
		Explanation: "\"Its\" is a possessive, as in \"its balance\". What follows here cannot be owned, so this is the contraction of \"it is\" and needs an apostrophe.",
	},
	{
		// The comparative is the other decidable position, and it is a
		// different shape to the list above: it is not the word straight
		// after "its" that gives it away but the "than" further on.
		//
		// "its worse" on its own could be a possessive before a noun, the
		// way "its value" is. "its worse than I expected" cannot be: a
		// comparative followed by "than" is doing the work of a verb
		// phrase, and a possessive has nothing to own.
		Pattern: `\b([Ii])ts\s+(worse|better|more|less|easier|harder|` +
			`bigger|smaller|faster|slower|cheaper|closer|worth)\s+than\b`,
		Flags: []string{
			"and its worse than I expected",
			"Its better than nothing",
		},
		Leaves:      []string{"its value fell more than expected"},
		Message:     "Should be \"$1t's $2 than\"",
		Suggest:     "$1t's $2 than",
		Category:    "Confused words",
		Explanation: "\"Its\" is a possessive, as in \"its balance\". A comparative followed by \"than\" is not something that can be owned, so this is \"it is\".",
	},
	// A rule for "its" before any -ing word was tried here and removed: it
	// fired on "its funding", and English is full of -ing nouns -- funding,
	// meaning, building, training -- that a possessive precedes perfectly
	// well. Only the listed words above are safe, because each is a word no
	// possessive can be followed by whatever the sentence.
	{
		// The mirror: "it's" is "it is", which cannot precede a noun it owns.
		Pattern:     `\b([Ii])t's\s+(own|owner)\b`,
		Flags:       []string{"it's own fault"},
		Message:     "Should be \"$1ts $2\"",
		Suggest:     "$1ts $2",
		Category:    "Confused words",
		Explanation: "\"It's\" is short for \"it is\", which does not fit before a noun it owns. The possessive \"its\" has no apostrophe.",
	},
	{
		// "There own" is never right: only the possessive can precede it.
		// The nouns beside it are the ones with no reading after a "there"
		// -- "way over there" is the natural order, and "there way" is not a
		// phrase. A general "there + noun" rule would be wrong constantly,
		// since "there is a problem" -- any statement at all -- puts a noun
		// somewhere after it.
		Pattern:     `\b[tT]here\s+(own|self|selves|way|ways|house|home|car|job|turn|fault|parents|kids)\b`,
		Flags:       []string{"they brought there own", "has to find there way home"},
		Message:     "Should be \"their $1\"",
		Suggest:     "their $1",
		Category:    "Confused words",
		Explanation: "\"There\" refers to a place or introduces a statement. Only the possessive \"their\" can precede this word.",
	},
	{
		Pattern:     `\b[tT]here\s+(is|are|was|were)\s+own\b`,
		Flags:       []string{"there is own equipment"},
		Message:     "Should be \"their own\"",
		Suggest:     "their own",
		Category:    "Confused words",
		Explanation: "\"Own\" here belongs to someone, which takes the possessive \"their\" rather than \"there\".",
	},

	// --- style: flagged, but with no replacement proposed ---
	// Suggest is empty because there is no single correct rewrite; the
	// point is to draw the eye, not to make the edit.
	{
		// Captured and back-referenced so the fix keeps whichever mark was
		// used: "!!!" collapses to "!", "???" to "?". A run of mixed marks
		// deliberately does not match -- there is no single right answer for
		// "!?!".
		Pattern:     `([!?])\1{2,}`,
		Flags:       []string{"really!!! yes"},
		Leaves:      []string{"really!! yes"},
		Message:     "Excessive punctuation",
		Suggest:     "$1",
		Category:    "Style",
		Explanation: "A run of exclamation or question marks adds emphasis in a way that reads as shouting. One mark carries the same meaning.",
	},
	// A "filler word" rule (very, really, quite, actually...) was tried here
	// and removed: it fired on "he said quite clearly", which is correct
	// writing. Whether an intensifier is filler depends on the sentence, so
	// the rule cannot help but underline prose that is fine -- the exact
	// failure the note at the top of this list warns about.
	//
	// Three wordiness rules also used to live here -- "in order to", "due to
	// the fact that", "at this point in time". They moved to the table in
	// rules_style.go with the eighty-odd others, and are marked as
	// suggestions there rather than errors, which is what they always were.
}
