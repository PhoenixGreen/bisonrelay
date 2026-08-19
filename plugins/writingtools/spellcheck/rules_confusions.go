package spellcheck

// rules_confusions.go holds the word pairs people mix up: their/there,
// then/than, lose/loose, affect/effect.
//
// These are the checks a grammar tool is judged on and the ones it most often
// gets wrong. LanguageTool decides the general case with ngram frequency data
// -- given "I have more money then you", it knows "money than you" is the
// commoner trigram -- which is gigabytes and out of the question here.
//
// What is possible without any of that is the decidable slice. Each pair has
// positions where only one of the two words can be right whatever the
// sentence is about: "than" cannot follow "and", a possessive cannot precede
// a verb, "apart of" is never a phrase. The rules below sit only in those
// positions and say nothing at all about the rest, which is why the list is
// so much shorter than the number of pairs it covers.
//
// The temptation throughout is to widen a rule by one more word. The corpus
// in spellcheck_test.go exists because that temptation was acted on several
// times, and every one of them fired on correct writing.

// confusionExplanation is shared by rules for one pair, so a reader gets the
// same account of the difference wherever it is caught.
const (
	explainThenThan = "\"Than\" compares two things (\"bigger than\"). " +
		"\"Then\" is about time or sequence (\"and then we left\")."
	explainLoseLoose = "\"Lose\" is the verb -- to mislay or be beaten. " +
		"\"Loose\" is the adjective, the opposite of tight."
	explainAffectEffect = "\"Affect\" is almost always the verb, meaning to " +
		"influence. \"Effect\" is almost always the noun, the result."
	explainYourYoure = "\"Your\" shows possession (\"your wallet\"). " +
		"\"You're\" is short for \"you are\"."
	explainToToo = "\"Too\" means excessively or also. \"To\" is the " +
		"preposition, as in \"to the shop\"."
	explainTheirTheyre = "\"Their\" shows possession (\"their wallet\"). " +
		"\"They're\" is short for \"they are\"."
	explainWhoseWhos = "\"Whose\" asks who something belongs to. " +
		"\"Who's\" is short for \"who is\" or \"who has\"."
	explainParticiple = "After \"have\", \"has\" or \"had\", a verb takes " +
		"its past participle -- \"have gone\", not \"have went\"."
	explainBrakeBreak = "A \"brake\" is the thing that stops a vehicle. A " +
		"\"break\" is a pause, or what happens when something is damaged."
	explainThereTheyre = "\"There\" is a place. \"Their\" shows possession. " +
		"\"They're\" is short for \"they are\"."
)

// progressiveVerbs are the -ing forms used in this file's "possessive before a
// verb" rules -- "your going", "their taking", "whose bringing".
//
// Curated by hand, and it has to be: WordNet gives almost every -ing form a
// noun sense, so the part-of-speech test that decides advice/advise says
// nothing at all here. The words left out are the ones that really are
// possessed in ordinary writing -- your writing, your thinking, your reading
// list, their training, whose cooking -- because for those the possessive is
// correct and the rule would be arguing with the writer.
const progressiveVerbs = `going|coming|getting|doing|making|taking|trying|` +
	`saying|telling|asking|wearing|kidding|joking|missing|forgetting|` +
	`sending|waiting|watching|leaving|staying|moving|driving|bringing|` +
	`paying|joining|helping|calling|eating|drinking|sleeping|walking|` +
	`sitting|starting|finishing|worrying|guessing|hoping|wondering`

// gerundAsSubject is the reading every one of those rules must not touch: the
// possessive really does own the -ing word, because the whole phrase is the
// subject of the sentence.
//
// "Your talking is distracting", "their leaving was sudden", "your asking
// helps nobody" are all correct English, and all of them are exactly the shape
// the rules look for. What separates them is what comes next -- a verb the
// -ing phrase is the subject of, rather than the object or adverbial that
// follows a progressive.
const gerundAsSubject = `(is|was|has|had|will|would|makes|made|helps|helped|` +
	`means|meant|matters|mattered|surprised|annoys|annoyed|bothers|bothered)`

// confusionRules are checks for the wrong word of a confusable pair, in
// positions where the right one is not a matter of opinion.
var confusionRules = []GrammarRule{
	// --- then / than ---
	{
		// A comparative is the one position where "than" is forced. Written
		// as an explicit list rather than `\w+er`, which would sweep up
		// "never", "however", "either" and "other" -- all of which precede
		// "then" perfectly well.
		Pattern: `\b([mM]ore|[lL]ess|[bB]etter|[wW]orse|[bB]igger|[sS]maller|[lL]arger|[hH]igher|` +
			`[lL]ower|[fF]aster|[sS]lower|[gG]reater|[fF]ewer|[oO]lder|[yY]ounger|[lL]onger|[sS]horter|` +
			`[cC]heaper|[eE]asier|[hH]arder|[rR]ather|[oO]ther)\s+then\b`,
		Flags:       []string{"this is better then that"},
		Leaves:      []string{"better than that"},
		Message:     "Should be \"$1 than\"",
		Suggest:     "$1 than",
		Category:    "Confused words",
		Explanation: explainThenThan,
	},
	{
		// The mirror. A conjunction cannot be followed by a comparison.
		Pattern:     `\b([aA]nd|[bB]ut|[sS]o|[bB]ack|[sS]ince|[rR]ight|[oO]nly|[wW]ay)\s+than\b`,
		Flags:       []string{"we synced and than sent it"},
		Leaves:      []string{"we synced and then sent it"},
		Message:     "Should be \"$1 then\"",
		Suggest:     "$1 then",
		Category:    "Confused words",
		Explanation: explainThenThan,
	},

	// --- lose / loose ---
	{
		// "Loosing" is not a word anyone means: the verb "to loose" exists
		// but its participle is vanishingly rare beside the typo.
		Pattern:     `\b[lL]oosing\b`,
		Flags:       []string{"we are loosing peers"},
		Message:     "Should be \"losing\"",
		Suggest:     "losing",
		Category:    "Confused words",
		Explanation: explainLoseLoose,
	},
	{
		// An adjective cannot take an object, so anything that looks like one
		// after "loose" means the verb was meant.
		Pattern: `\b[lL]oose\s+(the|a|an|my|your|his|her|our|their|it|them|` +
			`money|weight|control|track|interest|everything|access)\b`,
		Flags:       []string{"do not loose the keys"},
		Leaves:      []string{"the screw is loose here"},
		Message:     "Should be \"lose $1\"",
		Suggest:     "lose $1",
		Category:    "Confused words",
		Explanation: explainLoseLoose,
	},
	{
		// A modal or "to" forces the verb.
		Pattern:     `\b([wW]ill|[wW]ould|[cC]an|[cC]ould|[mM]ight|[mM]ay|[tT]o|[dD]on't|[dD]idn't|[dD]oesn't)\s+loose\b`,
		Flags:       []string{"you will loose it"},
		Message:     "Should be \"$1 lose\"",
		Suggest:     "$1 lose",
		Category:    "Confused words",
		Explanation: explainLoseLoose,
	},

	// --- affect / effect ---
	{
		// A determiner forces a noun.
		//
		// The indefinite article is separated out below, because correcting
		// the word changes which article the sentence needs: "a affect"
		// becomes "an effect", not "a effect". A rule that carries the
		// determiner through unchanged hands back a phrase that is still
		// wrong, and this one did.
		Pattern:     `\b([tT]he|[tT]his|[tT]hat|[aA]ny|[nN]o|[sS]ide|[nN]et|[lL]ittle|[gG]reat|[wW]hose)\s+affect\b`,
		Flags:       []string{"it had no affect"},
		Leaves:      []string{"it had no effect"},
		Message:     "Should be \"$1 effect\"",
		Suggest:     "$1 effect",
		Category:    "Confused words",
		Explanation: explainAffectEffect,
	},
	{
		// Both "a affect" and "an affect" become "an effect": the vowel is
		// what decides, and after the correction there is one.
		Pattern:     `\b([Aa])n?\s+affect\b`,
		Flags:       []string{"it had a affect", "it had an affect"},
		Message:     "Should be \"$1n effect\"",
		Suggest:     "$1n effect",
		Category:    "Confused words",
		Explanation: explainAffectEffect,
	},
	{
		Pattern:     `\b([tT]he|[tT]hese|[tT]hose|[iI]ts|[sS]ide|[aA]ny|[nN]o)\s+affects\b`,
		Flags:       []string{"the affects were clear"},
		Message:     "Should be \"$1 effects\"",
		Suggest:     "$1 effects",
		Category:    "Confused words",
		Explanation: explainAffectEffect,
	},
	{
		// A modal forces the verb. "Effect" as a verb exists -- "effect
		// change" -- but not with a pronoun or determiner after it, which is
		// why the object is matched too.
		Pattern: `\b([wW]ill|[wW]ould|[cC]an|[cC]ould|[mM]ight|[mM]ay|[dD]oes|[dD]oesn't|[dD]idn't)\s+` +
			`effect\s+(the|a|an|my|your|his|her|our|their|you|me|us|them|him|it)\b`,
		Flags:       []string{"it will effect the outcome"},
		Leaves:      []string{"it will effect change across the network"},
		Message:     "Should be \"$1 affect $2\"",
		Suggest:     "$1 affect $2",
		Category:    "Confused words",
		Explanation: explainAffectEffect,
	},

	// --- your / you're ---
	{
		// Four words, after a longer list was cut down word by word. Almost
		// everything that reads as an adjective after "you're" also reads as
		// something ownable after "your": your right (to refuse), your correct
		// address, your late payment, your next appointment, your invited
		// guests, your amazing work, your mistaken belief. Only these four
		// cannot follow a possessive at all.
		//
		// "Your welcome" is caught by its own rule among the error checks,
		// which predates this one.
		Pattern:     `\b([yY])our\s+(kidding|joking|probably|definitely)\b`,
		Flags:       []string{"your kidding me", "Your joking"},
		Leaves:      []string{"it is your right to refuse"},
		Message:     "Should be \"$1ou're $2\"",
		Suggest:     "$1ou're $2",
		Category:    "Confused words",
		Explanation: explainYourYoure,
	},
	{
		// "Your on my list." A possessive owns the noun after it, and a
		// preposition or an adverb is not a noun -- there is nothing for
		// "your" to own.
		//
		// The hyphen guard is what makes this safe. English is full of
		// attributive compounds built from exactly these words -- your
		// in-tray, your on-call rota, your out-of-office reply -- and in
		// every one of them the possessive is correct and the word after it
		// is only the first half of an adjective.
		//
		// Words that can begin an ordinary noun phrase are left out for the
		// same reason: "your only friend", "your very own", "your just
		// reward" and "your really good idea" are all correct.
		Pattern: `\b([yY])our\s+(on|in|at|off|out|here|there|not|always|` +
			`never|already|about\s+to|going\s+to)\b`,
		Antipatterns: []string{`[yY]our\s+(on|in|at|off|out)-`},
		Flags: []string{
			"Your on my list",
			"your not ready yet",
			"your going to need an umbrella",
			"your always late",
		},
		Leaves: []string{
			"you're on my list",
			"check your in-tray",
			"your on-call rota is here",
			"your only friend is waiting",
			"it was your very own idea",
		},
		Message:     "Should be \"$1ou're $2\"",
		Suggest:     "$1ou're $2",
		Category:    "Confused words",
		Explanation: explainYourYoure,
	},
	{
		// The mirror: "you are" cannot own a noun.
		Pattern:     `\b[yY]ou're\s+(own|car|house|turn|fault|money|wallet|keys|help|name|job|passport|ticket|order|account|address|password|email|phone|bag|coat|seat|room|turn)\b`,
		Flags:       []string{"that is you're own fault"},
		Message:     "Should be \"your $1\"",
		Suggest:     "your $1",
		Category:    "Confused words",
		Explanation: explainYourYoure,
	},

	{
		// "thanks for you message". The dropped r is a typing slip rather
		// than a confusion, which is why neither rule above catches it:
		// "you" is a perfectly good word and this is a perfectly good
		// sentence shape.
		//
		// What makes it decidable is the noun, not the preposition. "for
		// you" is complete on its own, so anything can follow it -- "I did
		// it for you yesterday" is correct, and a rule keyed on "preposition
		// + you + any noun" would flag it. The nouns below are the ones that
		// cannot stand bare after "you": there is no reading of "for you
		// message" or "with you permission" that works.
		Pattern: `\b([Ff]or|[Ww]ith|[Aa]bout|[Ii]n|[Oo]n)\s+you\s+(message|` +
			`email|reply|response|time|help|support|feedback|patience|` +
			`understanding|interest|advice|input|permission|opinion|` +
			`behalf|order|payment|invoice|account|address|question|` +
			`questions|comments|thoughts|notes|post|work|effort|kindness)\b`,
		Flags: []string{
			"thanks for you message",
			"Hi Sam, thanks for you message",
			"with you permission we will proceed",
		},
		Leaves: []string{
			"I left it for you yesterday",
			"this is for you and nobody else",
			"we are counting on you today",
		},
		Message:     "Should be \"$1 your $2\"",
		Suggest:     "$1 your $2",
		Category:    "Confused words",
		Explanation: "\"You\" is the pronoun and \"your\" is the possessive. The noun after it is being owned, so this needs \"your\".",
	},

	// --- to / too ---
	{
		// The leading verb or intensifier is matched as well as the adjective
		// after it, because "to" before an adjective is fine on its own --
		// "spoke to many people", "went to great lengths".
		//
		// The adjectives are listed rather than matched loosely, and the
		// list is the whole rule. "High" was missing until an example asked
		// for it, which is about as common as this mistake gets. Words that
		// are also verbs stay out: "the plan is to close the door" and "the
		// aim is to narrow the gap" are correct writing that "close" or
		// "narrow" in this list would flag.
		Pattern: `\b([iI]s|[aA]re|[wW]as|[wW]ere|[bB]e|[bB]een|[iI]t's|[tT]hat's|[fF]eel|[fF]eels|[fF]elt|` +
			`[sS]eems|[lL]ooks|[wW]ay|[fF]ar)\s+to\s+(much|many|late|early|big|small|` +
			`hard|easy|expensive|long|short|slow|fast|good|bad|old|young|` +
			`heavy|light|loud|quiet|soon|often|high|low|hot|cold|busy|` +
			`tired|strong|weak|wide|deep|thin|thick|dark|bright|complex|` +
			`simple|risky|similar|different)\b`,
		Flags:       []string{"the fee is to high"},
		Leaves:      []string{"i spoke to many people about it"},
		Message:     "Should be \"$1 too $2\"",
		Suggest:     "$1 too $2",
		Category:    "Confused words",
		Explanation: explainToToo,
	},
	{
		// "Me to." ending a sentence is always "me too". The antipattern is
		// the other reading: a "to" with something after it is the
		// preposition doing its job.
		Pattern:      `\b([mM]e|[hH]im|[hH]er|[uU]s|[tT]hem)\s+to\b`,
		Flags:        []string{"send it to me to."},
		Leaves:       []string{"send it to me to review"},
		Antipatterns: []string{`\b([mM]e|[hH]im|[hH]er|[uU]s|[tT]hem)\s+to\s+\S`},
		Message:      "Should be \"$1 too\"",
		Suggest:      "$1 too",
		Category:     "Confused words",
		Explanation:  explainToToo,
	},

	// --- their / they're ---
	{
		Pattern:     `\b[tT]hey're\s+(own|car|house|turn|fault|money|keys|wallet|names)\b`,
		Flags:       []string{"they're own fault"},
		Message:     "Should be \"their $1\"",
		Suggest:     "their $1",
		Category:    "Confused words",
		Explanation: explainTheirTheyre,
	},

	// --- whose / who's ---
	{
		Pattern: `\b[wW]hose\s+(going|coming|been|gone|got|getting|ready|next|` +
			`there|here|right|wrong|that|this)\b`,
		Flags:       []string{"whose going to test it"},
		Leaves:      []string{"whose keys are these"},
		Message:     "Should be \"who's $1\"",
		Suggest:     "who's $1",
		Category:    "Confused words",
		Explanation: explainWhoseWhos,
	},
	{
		Pattern:     `\b[wW]ho's\s+(turn|fault|idea|name|car|house|job|book|keys|phone)\b`,
		Flags:       []string{"who's turn is it"},
		Leaves:      []string{"who's going to review it"},
		Message:     "Should be \"whose $1\"",
		Suggest:     "whose $1",
		Category:    "Confused words",
		Explanation: explainWhoseWhos,
	},

	// --- past participles after have/has/had ---
	// Each of these is wrong in every context: the participle is fixed by the
	// auxiliary, whatever the sentence is about.
	{
		Pattern:     `\b([hH]ave|[hH]as|[hH]ad|[hH]aving)(\s+(?:also|already|never|just|now|still|only|even|nearly|almost|probably|certainly|definitely|recently|finally|apparently))?\s+went\b`,
		Flags:       []string{"they have went home"},
		Leaves:      []string{"they have gone home"},
		Message:     "Should be \"$1$2 gone\"",
		Suggest:     "$1$2 gone",
		Category:    "Grammar",
		Explanation: explainParticiple,
	},
	{
		Pattern:     `\b([hH]ave|[hH]as|[hH]ad|[hH]aving)(\s+(?:also|already|never|just|now|still|only|even|nearly|almost|probably|certainly|definitely|recently|finally|apparently))?\s+came\b`,
		Flags:       []string{"they have came back"},
		Message:     "Should be \"$1$2 come\"",
		Suggest:     "$1$2 come",
		Category:    "Grammar",
		Explanation: explainParticiple,
	},
	{
		Pattern:     `\b([hH]ave|[hH]as|[hH]ad|[hH]aving)(\s+(?:also|already|never|just|now|still|only|even|nearly|almost|probably|certainly|definitely|recently|finally|apparently))?\s+forgot\b`,
		Flags:       []string{"he had forgot about it completely", "I had also forgot to put my shoes on"},
		Leaves:      []string{"he had forgotten about it", "I had also forgotten"},
		Message:     "Should be \"$1$2 forgotten\"",
		Suggest:     "$1$2 forgotten",
		Category:    "Grammar",
		Explanation: explainParticiple,
	},
	{
		Pattern:     `\b([hH]ave|[hH]as|[hH]ad|[hH]aving)(\s+(?:also|already|never|just|now|still|only|even|nearly|almost|probably|certainly|definitely|recently|finally|apparently))?\s+ate\b`,
		Flags:       []string{"we have ate already"},
		Message:     "Should be \"$1$2 eaten\"",
		Suggest:     "$1$2 eaten",
		Category:    "Grammar",
		Explanation: explainParticiple,
	},
	{
		Pattern:     `\b([hH]ave|[hH]as|[hH]ad|[hH]aving)(\s+(?:also|already|never|just|now|still|only|even|nearly|almost|probably|certainly|definitely|recently|finally|apparently))?\s+saw\b`,
		Flags:       []string{"i have saw it"},
		Message:     "Should be \"$1$2 seen\"",
		Suggest:     "$1$2 seen",
		Category:    "Grammar",
		Explanation: explainParticiple,
	},
	{
		Pattern:     `\b([hH]ave|[hH]as|[hH]ad|[hH]aving)(\s+(?:also|already|never|just|now|still|only|even|nearly|almost|probably|certainly|definitely|recently|finally|apparently))?\s+did\b`,
		Flags:       []string{"i have did that"},
		Message:     "Should be \"$1$2 done\"",
		Suggest:     "$1$2 done",
		Category:    "Grammar",
		Explanation: explainParticiple,
	},
	{
		Pattern:     `\b([hH]ave|[hH]as|[hH]ad|[hH]aving)(\s+(?:also|already|never|just|now|still|only|even|nearly|almost|probably|certainly|definitely|recently|finally|apparently))?\s+wrote\b`,
		Flags:       []string{"i have wrote the post"},
		Message:     "Should be \"$1$2 written\"",
		Suggest:     "$1$2 written",
		Category:    "Grammar",
		Explanation: explainParticiple,
	},
	{
		Pattern:     `\b([hH]ave|[hH]as|[hH]ad|[hH]aving)(\s+(?:also|already|never|just|now|still|only|even|nearly|almost|probably|certainly|definitely|recently|finally|apparently))?\s+took\b`,
		Flags:       []string{"i have took it"},
		Message:     "Should be \"$1$2 taken\"",
		Suggest:     "$1$2 taken",
		Category:    "Grammar",
		Explanation: explainParticiple,
	},
	{
		Pattern:     `\b([hH]ave|[hH]as|[hH]ad|[hH]aving)(\s+(?:also|already|never|just|now|still|only|even|nearly|almost|probably|certainly|definitely|recently|finally|apparently))?\s+gave\b`,
		Flags:       []string{"i have gave it"},
		Message:     "Should be \"$1$2 given\"",
		Suggest:     "$1$2 given",
		Category:    "Grammar",
		Explanation: explainParticiple,
	},
	{
		Pattern:     `\b([hH]ave|[hH]as|[hH]ad|[hH]aving)(\s+(?:also|already|never|just|now|still|only|even|nearly|almost|probably|certainly|definitely|recently|finally|apparently))?\s+broke\b`,
		Flags:       []string{"i have broke it"},
		Message:     "Should be \"$1$2 broken\"",
		Suggest:     "$1$2 broken",
		Category:    "Grammar",
		Explanation: explainParticiple,
	},
	{
		Pattern:     `\b([hH]ave|[hH]as|[hH]ad|[hH]aving)(\s+(?:also|already|never|just|now|still|only|even|nearly|almost|probably|certainly|definitely|recently|finally|apparently))?\s+spoke\b`,
		Flags:       []string{"i have spoke to them"},
		Message:     "Should be \"$1$2 spoken\"",
		Suggest:     "$1$2 spoken",
		Category:    "Grammar",
		Explanation: explainParticiple,
	},
	{
		Pattern:     `\b([hH]ave|[hH]as|[hH]ad|[hH]aving)(\s+(?:also|already|never|just|now|still|only|even|nearly|almost|probably|certainly|definitely|recently|finally|apparently))?\s+chose\b`,
		Flags:       []string{"i have chose one"},
		Message:     "Should be \"$1$2 chosen\"",
		Suggest:     "$1$2 chosen",
		Category:    "Grammar",
		Explanation: explainParticiple,
	},
	{
		Pattern:     `\b([hH]ave|[hH]as|[hH]ad|[hH]aving)(\s+(?:also|already|never|just|now|still|only|even|nearly|almost|probably|certainly|definitely|recently|finally|apparently))?\s+drank\b`,
		Flags:       []string{"i have drank it"},
		Message:     "Should be \"$1$2 drunk\"",
		Suggest:     "$1$2 drunk",
		Category:    "Grammar",
		Explanation: explainParticiple,
	},
	{
		// "Has lead to" is the commonest of these by a distance, because
		// "lead" the metal is spelled like the past tense sounds.
		Pattern:     `\b([hH]ave|[hH]as|[hH]ad|[hH]aving)\s+lead\s+to\b`,
		Flags:       []string{"that has lead to problems"},
		Message:     "Should be \"$1 led to\"",
		Suggest:     "$1 led to",
		Category:    "Grammar",
		Explanation: explainParticiple,
	},

	// --- a possessive before a verb ---
	//
	// The commonest confusion of the lot and the one the earlier rules only
	// half covered: they listed the words that may follow, and the list could
	// never include the whole of English. These key on the *shape* instead --
	// a possessive cannot own an action in progress -- which is one rule per
	// pronoun rather than one per word.
	{
		Pattern:      `\b([yY])our\s+(` + progressiveVerbs + `)\b`,
		Antipatterns: []string{`[yY]our\s+\w+ing\s+` + gerundAsSubject + `\b`},
		Flags: []string{
			"Your wearing you're new jacket",
			"your going home already",
			"I think your missing the point",
		},
		Leaves: []string{
			"you're wearing your new jacket",
			"your talking is distracting me",
			"your asking helps nobody",
		},
		Message:     "Should be \"$1ou're $2\"",
		Suggest:     "$1ou're $2",
		Category:    "Confused words",
		Explanation: explainYourYoure,
	},
	{
		Pattern:      `\b([tT])heir\s+(` + progressiveVerbs + `)\b`,
		Antipatterns: []string{`[tT]heir\s+\w+ing\s+(of\b|` + gerundAsSubject + `\b)`},
		Flags: []string{
			"Their taking they're children to school",
			"their coming over later",
		},
		Leaves: []string{
			"they're taking their children to school",
			"their leaving was sudden",
			"their taking of the city ended it",
		},
		Message:     "Should be \"$1hey're $2\"",
		Suggest:     "$1hey're $2",
		Category:    "Confused words",
		Explanation: explainTheirTheyre,
	},
	{
		// "There going to be late."
		//
		// The antipattern is the reading that makes this rule dangerous rather
		// than merely wrong: "is there going to be a meeting?" is correct,
		// extremely common, and the existential "there" is doing exactly what
		// this pattern looks for.
		Pattern: `\b([tT])here\s+(` + progressiveVerbs + `)\b`,
		Antipatterns: []string{
			`\b(is|Is|was|Was|will|Will|would|Would|isn't|wasn't)\s+there\s+\w+ing\b`,
			`\b(out|over|down|up|back|in)\s+there\s+\w+ing\b`,
		},
		Flags: []string{
			"There going to be late",
			"there coming over later",
		},
		Leaves: []string{
			"they're going to be late",
			"is there going to be a meeting?",
			"the path out there going north is closed",
		},
		Message:     "Should be \"$1hey're $2\"",
		Suggest:     "$1hey're $2",
		Category:    "Confused words",
		Explanation: explainThereTheyre,
	},
	{
		// The mirror of the existing whose/who's rule, which listed fourteen
		// words. A gerund after "whose" is the same shape as the three above.
		//
		// The -ing words that are genuinely possessed are the trap here and a
		// different set from the others: "whose cooking is this?" and "whose
		// writing is on the box?" are correct, and both are excluded by the
		// shared list rather than by an antipattern.
		Pattern: `\b[wW]hose\s+(` + progressiveVerbs + `)\b`,
		Flags: []string{
			"whose bringing the cake",
			"Whose taking the car tomorrow",
		},
		Leaves: []string{
			"who's bringing the cake",
			"whose cake is it",
			"whose cooking is this",
		},
		Message:     "Should be \"who's $1\"",
		Suggest:     "who's $1",
		Category:    "Confused words",
		Explanation: explainWhoseWhos,
	},

	// --- brake / break ---
	//
	// Both words are a noun and a verb, so the pair is not decidable by part
	// of speech the way advice/advise is. What decides it is the company each
	// keeps: the stopping device is named in a handful of fixed compounds and
	// operated by a handful of fixed verbs, and the pause is taken rather than
	// pressed.
	//
	// The trap throughout is "breaks" the ordinary verb. "The disc breaks",
	// "the car breaks down" and "their breaks are too short" are all correct,
	// which is why none of these rules matches a bare possessive before it --
	// the vehicle has to be named, or the verb of pressing has to be there.
	{
		// Only the pause is taken, had or needed. "Press the brake" and "the
		// brake failed" are the device and are left alone, which is why the
		// verb is matched rather than the determiner.
		Pattern: `\b([tT]ake|[tT]akes|[tT]aking|[tT]ook|[hH]ave|[hH]ad|[hH]aving|` +
			`[nN]eed|[nN]eeds|[nN]eeded|[dD]eserve|[dD]eserves|[wW]ant|[wW]ants)\s+` +
			`(a|an|the|another|my|your|his|her|our|their)\s+brake\b`,
		Flags: []string{
			"I'm going to take a brake",
			"we need a brake after this",
			"Take a brake",
		},
		Leaves: []string{
			"I'm going to take a break",
			"press the brake before the corner",
			"the brake failed on the hill",
		},
		Message:     "Should be \"$1 $2 break\"",
		Suggest:     "$1 $2 break",
		Category:    "Confused words",
		Explanation: explainBrakeBreak,
	},
	{
		// Compounds that are only ever the pause. None of these is a part of
		// a vehicle, so there is no reading where the device is meant.
		Pattern: `\b([lL]unch|[cC]offee|[tT]ea|[sS]moke|[cC]igarette|[cC]ommercial|` +
			`[sS]pring|[sS]ummer|[wW]inter|[EeAa]aster|[sS]tudy|[cC]areer|[sS]creen)\s+brakes?\b`,
		Flags:       []string{"I had a lunch brake", "back after the coffee brake"},
		Leaves:      []string{"I had a lunch break", "back after the coffee break"},
		Message:     "Should be \"$1 break\"",
		Suggest:     "$1 break",
		Category:    "Confused words",
		Explanation: explainBrakeBreak,
	},
	{
		// Compounds that are only ever the device.
		//
		// Singular only, and deliberately. Every one of these words can be the
		// subject of the verb "breaks" -- "the disc breaks under load", "the
		// emergency breaks the routine" -- so matching the plural would flag
		// correct writing to catch a mistake that is no commoner than it.
		Pattern:     `\b([hH]and|[fF]oot|[dD]isc|[dD]isk|[eE]mergency|[pP]arking|[hH]andbrake)\s+break\b`,
		Flags:       []string{"the hand break is on", "check the parking break"},
		Leaves:      []string{"the hand brake is on", "the disc breaks under load"},
		Message:     "Should be \"$1 brake\"",
		Suggest:     "$1 brake",
		Category:    "Confused words",
		Explanation: explainBrakeBreak,
	},
	{
		// The verbs of pressing. "Hit the breaks" is the commonest of these by
		// a distance, and none of them has a reading where something is being
		// shattered or paused.
		Pattern: `\b([hH]it|[hH]its|[sS]lam|[sS]lams|[sS]lammed|[pP]ump|[pP]umped|` +
			`[aA]pply|[aA]pplied|[pP]ress|[pP]ressed|[tT]ap|[tT]apped|[rR]elease|[rR]eleased)\s+` +
			`(on\s+)?the\s+(break)(s?)\b`,
		Flags: []string{
			"I hit the breaks",
			"she slammed on the breaks",
			"Press the break before you turn",
		},
		Leaves:      []string{"I hit the brakes", "press the brake before you turn"},
		Message:     "Should be \"$1 $2the brake$4\"",
		Suggest:     "$1 $2the brake$4",
		Category:    "Confused words",
		Explanation: explainBrakeBreak,
	},
	{
		// A named vehicle before it is what makes this safe. "My breaks are
		// not working" is about a car; "their breaks are not working" may
		// perfectly well be about a rota, so the possessive alone is not
		// enough and the vehicle is matched instead.
		//
		// "Breaks down" is excluded by listing what may follow: a car that
		// breaks down is correct writing and is exactly this shape.
		Pattern: `\b([cC]ar|[cC]ar's|[bB]ike|[bB]ike's|[bB]icycle|[vV]an|[tT]ruck|[lL]orry|` +
			`[mM]otorbike|[tT]railer|[wW]heel|[rR]ear|[fF]ront)\s+breaks\s+` +
			`(are|were|aren't|weren't|failed|fail|need|needed|squeak|squeal|feel|felt|` +
			`work|worked|don't|didn't|stopped\s+working)\b`,
		Flags: []string{
			"My car breaks are not working",
			"the bike breaks failed on the hill",
		},
		Leaves: []string{
			"My car brakes are not working",
			"my car breaks down every winter",
			"the front breaks off in transit",
		},
		Message:     "Should be \"$1 brakes $2\"",
		Suggest:     "$1 brakes $2",
		Category:    "Confused words",
		Explanation: explainBrakeBreak,
	},
	{
		// Stopping at a place you stop at. "Break for lunch" is correct and is
		// this shape, so the thing stopped at has to be named and every one
		// of these is a road feature.
		Pattern: `\b[bB]reak\s+(at|before|for)\s+((?:a|an|the)\s+)?` +
			`(stop\s+sign|red\s+light|traffic\s+light|traffic\s+lights|junction|` +
			`roundabout|crossing|zebra\s+crossing|corner|bend)\b`,
		Flags: []string{
			"You need to break at a stop sign",
			"break before the junction",
		},
		Leaves: []string{
			"You need to brake at a stop sign",
			"let's break for lunch",
			"we break for coffee at eleven",
		},
		Message:     "Should be \"brake $1 $2$3\"",
		Suggest:     "brake $1 $2$3",
		Category:    "Confused words",
		Explanation: explainBrakeBreak,
	},
	{
		// The mirror, and the easier direction: none of these is a thing that
		// can be slowed down. You break a law, a record or a promise, and
		// there is no reading where a vehicle's brake is involved.
		Pattern: `\b[bB]rake\s+(the\s+|a\s+|my\s+|your\s+|his\s+|her\s+|their\s+)?` +
			`(law|laws|rules?|record|records|news|ice|silence|deadlock|habit|` +
			`promise|promises|speed\s+limit|cycle|curse|tie|even|ranks|mould|mold)\b`,
		Flags: []string{
			"you brake the speed limit",
			"don't brake the law",
			"that will brake a promise",
		},
		Leaves: []string{
			"you break the speed limit",
			"press the brake at the corner",
		},
		Message:     "Should be \"break $1$2\"",
		Suggest:     "break $1$2",
		Category:    "Confused words",
		Explanation: explainBrakeBreak,
	},

	// --- weather / whether ---
	{
		// "Weather or not" is never the sky.
		Pattern:  `\b[wW]eather\s+or\s+not\b`,
		Flags:    []string{"We will go outside weather or not it rains"},
		Leaves:   []string{"we will go outside whether or not it rains"},
		Message:  "Should be \"whether or not\"",
		Suggest:  "whether or not",
		Category: "Confused words",
		Explanation: "\"Whether\" introduces a choice between possibilities. " +
			"\"Weather\" is rain and sunshine.",
	},

	// --- peace / piece ---
	{
		// "A peace of cake." The antipattern is the one phrase where "peace"
		// really does follow a determiner and precede "of", and it is a common
		// one.
		Pattern: `\b([aA]|[tT]he|[oO]ne|[aA]nother|[eE]very)\s+peace\s+of\b`,
		// The antipattern repeats the determiner because suppression requires
		// the exception to *contain* the match, and the match starts at the
		// determiner rather than at "peace".
		Antipatterns: []string{`\b([aA]|[tT]he|[oO]ne|[aA]nother|[eE]very)\s+peace\s+of\s+mind\b`},
		Flags:        []string{"I want a peace of cake"},
		Leaves: []string{
			"I want a piece of cake",
			"it gave me a peace of mind I had not had for weeks",
		},
		Message:  "Should be \"$1 piece of\"",
		Suggest:  "$1 piece of",
		Category: "Confused words",
		Explanation: "A \"piece\" is a portion of something. \"Peace\" is " +
			"calm, or the absence of war.",
	},

	// --- whole / hole ---
	{
		// "A whole in the wall." "Whole" is an adjective and cannot be what is
		// in something.
		Pattern:  `\b([aA]|[tT]he|[oO]ne|[aA]nother)\s+whole\s+in\s+(the|a|an|my|your|his|her|its|our|their)\b`,
		Flags:    []string{"There is a whole in the wall"},
		Leaves:   []string{"there is a hole in the wall", "the whole wall came down"},
		Message:  "Should be \"$1 hole in $2\"",
		Suggest:  "$1 hole in $2",
		Category: "Confused words",
		Explanation: "A \"hole\" is an opening. \"Whole\" means complete, and " +
			"describes a thing rather than being one.",
	},

	// --- scene / seen ---
	{
		// An auxiliary forces the participle, and "scene" has no verb reading
		// at all.
		Pattern: `\b([iI]'ve|[yY]ou've|[wW]e've|[tT]hey've|[hH]e's|[sS]he's|` +
			`[hH]ave|[hH]as|[hH]ad|[nN]ever|[eE]ver|[bB]een)\s+scene\b`,
		Flags:    []string{"I've scene that movie", "have you ever scene it"},
		Leaves:   []string{"I've seen that movie", "the final scene was excellent"},
		Message:  "Should be \"$1 seen\"",
		Suggest:  "$1 seen",
		Category: "Confused words",
		Explanation: "\"Seen\" is the past participle of \"see\". A \"scene\" " +
			"is a part of a film or an event.",
	},

	// --- allowed / aloud ---
	{
		// "We were aloud to read it." An adverb cannot follow a form of "be"
		// as the thing being permitted. Reading aloud is left alone because
		// nothing here matches it: "read it aloud" has no "be" in front.
		Pattern:  `\b([iI]s|[aA]re|[wW]as|[wW]ere|[aA]m|[bB]e|[bB]een|[nN]ot)\s+aloud\s+to\b`,
		Flags:    []string{"We were aloud to read the story"},
		Leaves:   []string{"we were allowed to read the story", "she read the story aloud to the class"},
		Message:  "Should be \"$1 allowed to\"",
		Suggest:  "$1 allowed to",
		Category: "Confused words",
		Explanation: "\"Allowed\" means permitted. \"Aloud\" means out loud, " +
			"where everyone can hear.",
	},

	// --- breath / breathe ---
	{
		// A determiner or an adjective forces the noun.
		Pattern: `\b([aA]|[tT]he|[mM]y|[yY]our|[hH]is|[hH]er|[oO]ur|[tT]heir|` +
			`[oO]ne|[eE]very|[dD]eep|[lL]ast|[fF]irst|[sS]hort)\s+breathe\b`,
		Flags:    []string{"Take a deep breathe"},
		Leaves:   []string{"take a deep breath", "just breathe slowly"},
		Message:  "Should be \"$1 breath\"",
		Suggest:  "$1 breath",
		Category: "Confused words",
		Explanation: "\"Breath\" is the noun -- the air itself. \"Breathe\" " +
			"is the verb -- what you do with it.",
	},
	{
		// "To" or a modal forces the verb.
		Pattern:     `\b([tT]o|[cC]an|[cC]an't|[cC]ould|[wW]ill|[wW]ould|[mM]ust|[sS]hould|[cC]annot)\s+breath\b`,
		Flags:       []string{"I can't breath in here", "just try to breath slowly"},
		Leaves:      []string{"I can't breathe in here", "take a deep breath"},
		Message:     "Should be \"$1 breathe\"",
		Suggest:     "$1 breathe",
		Category:    "Confused words",
		Explanation: "\"Breathe\" is the verb. \"Breath\" is the noun.",
	},

	// --- faze / phase ---
	{
		// A phase is a stage and cannot be done to a person.
		Pattern:  `\b([dD]idn't|[dD]oesn't|[dD]on't|[wW]on't|[wW]ouldn't|[nN]ever|[dD]id|[dD]oes)\s+phase\s+(me|him|her|us|them|you|anyone|anybody)\b`,
		Flags:    []string{"The criticism didn't phase her"},
		Leaves:   []string{"the criticism didn't faze her", "the next phase of the project"},
		Message:  "Should be \"$1 faze $2\"",
		Suggest:  "$1 faze $2",
		Category: "Confused words",
		Explanation: "\"Faze\" means to disturb or unsettle someone. A " +
			"\"phase\" is a stage in a process.",
	},

	// --- quiet / quite ---
	{
		// An intensifier forces the adjective: nothing is "very quite".
		Pattern:  `\b([vV]ery|[sS]o|[rR]eally|[tT]oo|[pP]retty|[bB]e|[kK]ept|[sS]tayed)\s+quite\b`,
		Flags:    []string{"the room was very quite"},
		Leaves:   []string{"the room was very quiet", "it is quite large"},
		Message:  "Should be \"$1 quiet\"",
		Suggest:  "$1 quiet",
		Category: "Confused words",
		Explanation: "\"Quiet\" means without noise. \"Quite\" means fairly " +
			"or completely, and modifies another word.",
	},
	{
		// The mirror: "quiet" before a determiner or an adjective is the
		// degree word, which is spelled the other way.
		Pattern:  `\b[qQ]uiet\s+(a|an|the|good|bad|big|large|small|nice|often|well|right|sure|different|similar|possible|likely|clear|common|rare|hard|easy|expensive|cheap|late|early|long|short|new|old|a\s+lot)\b`,
		Flags:    []string{"The room is quiet large"},
		Leaves:   []string{"the room is quite large", "be quiet and listen"},
		Message:  "Should be \"quite $1\"",
		Suggest:  "quite $1",
		Category: "Confused words",
		Explanation: "\"Quite\" means fairly or completely. \"Quiet\" means " +
			"without noise.",
	},

	// --- passed / past ---
	{
		// A verb of motion before it makes "past" the preposition, not a verb
		// in its own right -- two verbs cannot sit side by side like this.
		Pattern: `\b([wW]alk|[wW]alked|[wW]alking|[dD]rive|[dD]rove|[dD]riving|` +
			`[rR]an|[rR]unning|[wW]ent|[gG]oing|[cC]ame|[cC]oming|[rR]ode|` +
			`[rR]iding|[fF]lew|[fF]lying|[mM]oved|[mM]oving)\s+passed\b`,
		Flags:    []string{"we walked passed the station"},
		Leaves:   []string{"we walked past the station", "we passed the station"},
		Message:  "Should be \"$1 past\"",
		Suggest:  "$1 past",
		Category: "Confused words",
		Explanation: "\"Past\" is the preposition -- going by something. " +
			"\"Passed\" is the past tense of the verb \"to pass\".",
	},
	{
		// The mirror: a subject pronoun needs a verb, and "past" is not one.
		Pattern:  `\b([iI]|[wW]e|[yY]ou|[tT]hey|[hH]e|[sS]he|[iI]t)\s+past\s+(the|a|an|my|your|his|her|our|their|it|him|them|us|me)\b`,
		Flags:    []string{"We past the shop on the way"},
		Leaves:   []string{"we passed the shop on the way", "in the past we did"},
		Message:  "Should be \"$1 passed $2\"",
		Suggest:  "$1 passed $2",
		Category: "Confused words",
		Explanation: "\"Passed\" is the verb. \"Past\" is a time gone by, or " +
			"the preposition meaning beyond.",
	},

	// --- accept / except ---
	{
		Pattern:  `\b([eE]veryone|[eE]verybody|[aA]nyone|[aA]nybody|[eE]verything|[aA]nything|[aA]ll|[nN]obody|[nN]othing)\s+accept\b`,
		Flags:    []string{"I will invite everyone accept Tom"},
		Leaves:   []string{"I will invite everyone except Tom"},
		Message:  "Should be \"$1 except\"",
		Suggest:  "$1 except",
		Category: "Confused words",
		Explanation: "\"Except\" means excluding. \"Accept\" means to receive " +
			"or agree to something.",
	},
	{
		Pattern:  `\b([wW]ill|[cC]an|[cC]ould|[wW]ould|[mM]ust|[sS]hould|[pP]lease|[dD]idn't|[dD]on't|[dD]oesn't|[wW]on't)\s+except\b`,
		Flags:    []string{"I will except your offer"},
		Leaves:   []string{"I will accept your offer", "everyone except Tom"},
		Message:  "Should be \"$1 accept\"",
		Suggest:  "$1 accept",
		Category: "Confused words",
		Explanation: "\"Accept\" means to receive or agree to. \"Except\" " +
			"means excluding.",
	},

	// --- lead / led ---
	{
		// Third person singular only, and that is the whole rule. "I lead the
		// team" and "we lead the market" are correct present tense; "he lead"
		// is not a tense English has, so it can only be the past.
		Pattern:  `\b([hH]e|[sS]he|[wW]ho|[iI]t)\s+lead\s+(the|a|an|us|them|him|her|me|it|to|us\s+to)\b`,
		Flags:    []string{"She lead the group"},
		Leaves:   []string{"she led the group", "I lead the team every Tuesday", "we lead the market"},
		Message:  "Should be \"$1 led $2\"",
		Suggest:  "$1 led $2",
		Category: "Confused words",
		Explanation: "\"Led\" is the past tense of \"lead\". The spelling " +
			"\"lead\" is either the present tense or the metal.",
	},

	// --- stationary / stationery ---
	{
		Pattern:  `\b([bB]uy|[bB]ought|[oO]rder|[oO]rdered|[sS]ome|[tT]he|[oO]ffice|[sS]chool)\s+stationary\b`,
		Flags:    []string{"I bought some stationary"},
		Leaves:   []string{"I bought some stationery", "the car was stationary"},
		Message:  "Should be \"$1 stationery\"",
		Suggest:  "$1 stationery",
		Category: "Confused words",
		Explanation: "\"Stationery\" is paper and pens. \"Stationary\" means " +
			"not moving.",
	},
	{
		Pattern:  `\b([wW]as|[wW]ere|[iI]s|[aA]re|[rR]emained|[sS]tayed|[sS]tood|[kK]ept|[hH]eld)\s+stationery\b`,
		Flags:    []string{"The car was stationery"},
		Leaves:   []string{"the car was stationary", "I bought some stationery"},
		Message:  "Should be \"$1 stationary\"",
		Suggest:  "$1 stationary",
		Category: "Confused words",
		Explanation: "\"Stationary\" means not moving. \"Stationery\" is " +
			"writing materials.",
	},

	// --- know / no ---
	{
		// A subject pronoun needs a verb, and "no" is not one.
		Pattern:  `\b([iI]|[wW]e|[yY]ou|[tT]hey)\s+no\s+(the|that|what|how|why|where|who|when|it|this|nothing|him|her|them|about)\b`,
		Flags:    []string{"I no the answer"},
		Leaves:   []string{"I know the answer", "the answer is no"},
		Message:  "Should be \"$1 know $2\"",
		Suggest:  "$1 know $2",
		Category: "Confused words",
		Explanation: "\"Know\" is the verb -- to be aware of something. " +
			"\"No\" is the negative.",
	},

	// --- to / too, the other direction ---
	{
		// "I need too go." "Too" is an adverb of degree and cannot introduce a
		// verb; only the infinitive "to" can.
		Pattern: `\b[tT]oo\s+(go|be|get|do|make|see|say|have|take|find|know|` +
			`come|give|work|start|stop|help|use|try|put|keep|leave|call|send|` +
			`check|ask|talk|think|buy|pay|read|write|play|watch|meet)\b`,
		Flags:       []string{"so I need too go early"},
		Leaves:      []string{"so I need to go early", "that is too much"},
		Message:     "Should be \"to $1\"",
		Suggest:     "to $1",
		Category:    "Confused words",
		Explanation: explainToToo,
	},

	// --- phrases that are simply not the phrase ---
	{
		Pattern:  `\b[aA]part\s+of\s+(the|a|an|my|your|our|their|this|that|it)\b`,
		Flags:    []string{"it was apart of the plan"},
		Leaves:   []string{"apart from that it works"},
		Message:  "Should be \"a part of $1\"",
		Suggest:  "a part of $1",
		Category: "Confused words",
		Explanation: "\"Apart\" means separate, which is the opposite of " +
			"what belonging to something means.",
	},
	{
		Pattern:  `\b[bB]are\s+with\s+(me|us)\b`,
		Flags:    []string{"bare with me a moment"},
		Leaves:   []string{"bear with me a moment"},
		Message:  "Should be \"bear with $1\"",
		Suggest:  "bear with $1",
		Category: "Confused words",
		Explanation: "\"Bear\" here means to endure. \"Bare\" means uncovered, " +
			"which is a different request entirely.",
	},
	{
		Pattern:  `\b[cC]ould\s+care\s+less\b`,
		Flags:    []string{"i could care less"},
		Message:  "Should be \"couldn't care less\"",
		Suggest:  "couldn't care less",
		Category: "Confused words",
		Explanation: "The phrase means you care so little that caring less " +
			"is impossible, which needs the negative.",
	},
	{
		Pattern:  `\b[fF]or\s+all\s+intensive\s+purposes\b`,
		Flags:    []string{"for all intensive purposes"},
		Message:  "Should be \"for all intents and purposes\"",
		Suggest:  "for all intents and purposes",
		Category: "Confused words",
		Explanation: "The phrase is \"intents and purposes\"; \"intensive\" " +
			"is a mishearing of it.",
	},
	{
		Pattern:  `\b[iI]rregardless\b`,
		Flags:    []string{"irregardless of the cost"},
		Message:  "Should be \"regardless\"",
		Suggest:  "regardless",
		Category: "Confused words",
		Explanation: "\"Regardless\" already means without regard; the " +
			"\"ir-\" prefix negates it a second time.",
	},
	{
		Pattern:  `\b[sS]neak\s+peak\b`,
		Flags:    []string{"a sneak peak at it"},
		Message:  "Should be \"sneak peek\"",
		Suggest:  "sneak peek",
		Category: "Confused words",
		Explanation: "A \"peek\" is a quick look. A \"peak\" is the top of " +
			"a mountain.",
	},
	{
		Pattern:  `\b([pP]eak|[pP]eek)\s+(your|my|his|her|their|our)\s+interest\b`,
		Flags:    []string{"peak your interest"},
		Message:  "Should be \"pique $2 interest\"",
		Suggest:  "pique $2 interest",
		Category: "Confused words",
		Explanation: "\"Pique\" means to arouse or provoke. The other two " +
			"are a mountain top and a quick look.",
	},
	{
		Pattern:  `\b[iI]n\s+the\s+passed\b`,
		Flags:    []string{"in the passed we did"},
		Leaves:   []string{"in the past we did"},
		Message:  "Should be \"in the past\"",
		Suggest:  "in the past",
		Category: "Confused words",
		Explanation: "\"Past\" is the noun for time gone by. \"Passed\" is " +
			"the past tense of \"to pass\".",
	},
	{
		// Only at the end of a clause. "Principal" is also an adjective, so
		// the antipattern is the reading where a noun follows it: "in
		// principal cities", "on principal amounts".
		Pattern:      `\b([iI]n|[oO]n)\s+principal\b`,
		Flags:        []string{"i agree in principal."},
		Leaves:       []string{"the bank operates in principal cities"},
		Antipatterns: []string{`\b([iI]n|[oO]n)\s+principal\s+\w`},
		Message:      "Should be \"$1 principle\"",
		Suggest:      "$1 principle",
		Category:     "Confused words",
		Explanation: "A \"principle\" is a rule or belief. A \"principal\" " +
			"is the head of something, or the main one.",
	},
	{
		Pattern:  `\b([sS]ome|[gG]ood|[bB]ad|[aA]ny|[mM]y|[yY]our|[hH]is|[hH]er|[tT]heir|[tT]he)\s+advise\b`,
		Flags:    []string{"thanks for the advise"},
		Leaves:   []string{"thanks for the advice"},
		Message:  "Should be \"$1 advice\"",
		Suggest:  "$1 advice",
		Category: "Confused words",
		Explanation: "\"Advice\" is the noun -- the thing given. \"Advise\" " +
			"is the verb -- the act of giving it.",
	},
	{
		Pattern:     `\b([tT]o|[wW]ill|[wW]ould|[cC]an|[cC]ould|[pP]lease)\s+advice\b`,
		Flags:       []string{"please advice us"},
		Leaves:      []string{"please advise us"},
		Message:     "Should be \"$1 advise\"",
		Suggest:     "$1 advise",
		Category:    "Confused words",
		Explanation: "\"Advise\" is the verb -- the act of giving advice.",
	},
}
