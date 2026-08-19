package spellcheck

// rules_homophones.go holds the word pairs that sound alike and mean nothing
// like each other: brake/break lives next door in rules_confusions.go with the
// pairs a writer confuses for grammatical reasons, and these are the ones
// confused purely by ear.
//
// The positions were chosen against LanguageTool's English rule set, read as a
// checklist of *which* positions are worth covering rather than as a source of
// patterns -- every expression below was written here. Its ngram-driven
// confusion rules are not represented at all; they answer "which word is
// likelier in this context", which needs the corpus this plugin does not ship.
//
// Three shapes do nearly all the work, and they are the same three the rest of
// the plugin uses:
//
//	"to" or a modal before a word that is only ever a noun
//	a determiner or an adjective before a word that is only ever a verb
//	a fixed compound where only one spelling has ever appeared
//
// The discipline is the same too. Every rule fires on writing that is wrong
// whatever the sentence is about, each carries the example it must catch and
// the reading it must leave, and the corpus in spellcheck_test.go holds the
// correct uses that an over-eager version of each one flagged.
//
// Deliberately absent: practice/practise and draft/draught. Both are decidable
// -- and both are decidable *differently* in British and American English,
// while Rules is one list shipped to every locale. A rule that is right in
// Cardiff and wrong in Chicago has no place in a list that cannot tell them
// apart.

const (
	explainHearHere     = "\"Hear\" is what your ears do. \"Here\" is this place."
	explainThrewThrough = "\"Threw\" is the past tense of \"throw\". " +
		"\"Through\" means from one side to the other."
	explainWaitWeight = "\"Wait\" means to stay until something happens. " +
		"\"Weight\" is how heavy something is."
	explainWayWeigh = "\"Way\" is a route or a method. \"Weigh\" means to " +
		"measure how heavy something is."
	explainSeamSeem = "A \"seam\" is where two pieces of fabric are joined. " +
		"\"Seem\" means to appear."
	explainStairStare = "A \"stair\" is a step. To \"stare\" is to look " +
		"fixedly at something."
	explainTailTale = "A \"tail\" is the back end of an animal. A \"tale\" " +
		"is a story."
	explainThroneThrown = "A \"throne\" is what a monarch sits on. " +
		"\"Thrown\" is the past participle of \"throw\"."
	explainHerdHeard = "A \"herd\" is a group of animals. \"Heard\" is the " +
		"past tense of \"hear\"."
	explainLoanLone = "A \"loan\" is money lent. \"Lone\" means single or " +
		"alone."
	explainLessenLesson = "\"Lessen\" is the verb -- to reduce. A \"lesson\" " +
		"is something taught or learned."
	explainDecentDescent = "\"Decent\" means acceptable or good. A " +
		"\"descent\" is a movement downward."
	explainAltarAlter = "An \"altar\" is a table in a place of worship. To " +
		"\"alter\" is to change something."
	explainCouncilCounsel = "A \"council\" is a governing group. \"Counsel\" " +
		"is advice, or the lawyer giving it."
	explainDeviceDevise = "A \"device\" is an object. To \"devise\" is to " +
		"come up with something."
	explainElicitIllicit = "To \"elicit\" is to draw something out. " +
		"\"Illicit\" means illegal."
	explainDiscreetDiscrete = "\"Discreet\" means careful or private. " +
		"\"Discrete\" means separate and distinct."
	explainEnsureInsure = "\"Ensure\" means to make certain. \"Insure\" " +
		"means to take out insurance."
	explainBoardBored = "A \"board\" is a flat surface or a group of people. " +
		"\"Bored\" is what you are when nothing is interesting."
	explainBandBanned = "A \"band\" is a group. \"Banned\" means prohibited."
	explainPolePoll   = "A \"pole\" is a long post. A \"poll\" is a vote or a " +
		"survey."
	explainPorePour = "To \"pore\" over something is to study it closely. To " +
		"\"pour\" is to tip a liquid out."
	explainHoardHorde = "To \"hoard\" is to store things away. A \"horde\" " +
		"is a large crowd."
	explainVainVein = "\"Vain\" means conceited, or fruitless. A \"vein\" " +
		"carries blood."
	explainSoarSore        = "To \"soar\" is to fly high. \"Sore\" means painful."
	explainMorningMourning = "\"Morning\" is the early part of the day. " +
		"\"Mourning\" is grief."
	explainMedalMeddle = "A \"medal\" is an award. To \"meddle\" is to " +
		"interfere."
)

// homophoneRules are checks for words confused by sound, each in a position
// where only one spelling has a reading.
var homophoneRules = []GrammarRule{
	// --- hear / here ---
	{
		// A modal or auxiliary forces the verb; "here" is not one.
		Pattern: `\b([cC]an|[cC]an't|[cC]ould|[cC]ouldn't|[dD]id|[dD]idn't|[dD]o|` +
			`[dD]on't|[wW]ill|[wW]on't|[wW]ould)\s+((?:you|I|we|they|he|she|it)\s+)?here\b`,
		Flags:       []string{"I can here something outside", "did you here that"},
		Leaves:      []string{"I can hear something outside", "come over here"},
		Message:     "Should be \"$1 $2hear\"",
		Suggest:     "$1 $2hear",
		Category:    "Confused words",
		Explanation: explainHearHere,
	},
	{
		// A place word before it forces the place.
		Pattern:     `\b([oO]ver|[iI]n|[oO]ut|[uU]p|[dD]own|[rR]ight|[fF]rom)\s+hear\b`,
		Flags:       []string{"come over hear", "it is right hear"},
		Leaves:      []string{"come over here", "I did not hear you"},
		Message:     "Should be \"$1 here\"",
		Suggest:     "$1 here",
		Category:    "Confused words",
		Explanation: explainHearHere,
	},

	// --- new / knew ---
	{
		// A subject pronoun needs a verb, and "new" is an adjective.
		Pattern: `\b([iI]|[wW]e|[yY]ou|[tT]hey|[hH]e|[sS]he)\s+new\s+` +
			`(it|that|this|what|how|why|where|who|when|the|a|I|we|you|they|he|she|about|nothing|something)\b`,
		Flags:    []string{"I new I needed a car", "we new that already"},
		Leaves:   []string{"I knew I needed a car", "I needed a new car"},
		Message:  "Should be \"$1 knew $2\"",
		Suggest:  "$1 knew $2",
		Category: "Confused words",
		Explanation: "\"Knew\" is the past tense of \"know\". \"New\" is the " +
			"opposite of old.",
	},

	// --- one / won ---
	{
		Pattern:     `\b([wW]e|[tT]hey|[iI]|[hH]e|[sS]he|[wW]ho)\s+one\s+(the|a|it|by|again|against)\b`,
		Flags:       []string{"we one the match by a goal"},
		Leaves:      []string{"our team won the match", "we won by one goal"},
		Message:     "Should be \"$1 won $2\"",
		Suggest:     "$1 won $2",
		Category:    "Confused words",
		Explanation: "\"Won\" is the past tense of \"win\". \"One\" is the number.",
	},

	// --- week / weak ---
	{
		// A verb of feeling or seeming forces the adjective.
		Pattern: `\b([fF]elt|[fF]eel|[fF]eels|[fF]eeling|[lL]ooked|[lL]ooks|` +
			`[sS]eemed|[sS]eems|[gG]ot|[gG]etting|[vV]ery|[tT]oo|[sS]o|[rR]eally)\s+week\b`,
		Flags:       []string{"I felt week for days"},
		Leaves:      []string{"I felt weak for days", "I was ill last week"},
		Message:     "Should be \"$1 weak\"",
		Suggest:     "$1 weak",
		Category:    "Confused words",
		Explanation: "\"Weak\" means lacking strength. A \"week\" is seven days.",
	},
	{
		// Only where a length of time is being counted. "A weak signal" is
		// correct and is why the indefinite article is not in this list.
		Pattern:     `\b([nN]ext|[lL]ast|[eE]very|[tT]his\s+past)\s+weak\b`,
		Flags:       []string{"see you next weak"},
		Leaves:      []string{"see you next week", "it was a weak signal"},
		Message:     "Should be \"$1 week\" (seven days)",
		Suggest:     "$1 week",
		Category:    "Confused words",
		Explanation: "A \"week\" is seven days. \"Weak\" means lacking strength.",
	},

	// --- meet / meat ---
	{
		Pattern:     `\b([lL]et's|[tT]o|[wW]ill|[cC]an|[cC]ould|[sS]hall|[sS]hould|[wW]e'll|[iI]'ll)\s+meat\b`,
		Flags:       []string{"let's meat after work"},
		Leaves:      []string{"let's meet after work", "we bought some meat"},
		Message:     "Should be \"$1 meet\"",
		Suggest:     "$1 meet",
		Category:    "Confused words",
		Explanation: "\"Meet\" means to come together. \"Meat\" is food.",
	},
	{
		Pattern:     `\b([sS]ome|[tT]he|[rR]ed|[rR]aw|[cC]ooked|[fF]rozen|[fF]resh|[mM]inced)\s+meet\b`,
		Flags:       []string{"we bought some meet"},
		Leaves:      []string{"we bought some meat", "let's meet later"},
		Message:     "Should be \"$1 meat\"",
		Suggest:     "$1 meat",
		Category:    "Confused words",
		Explanation: "\"Meat\" is food. \"Meet\" means to come together.",
	},

	// --- threw / through ---
	{
		// A subject pronoun needs a verb, and "through" is a preposition.
		Pattern: `\b([iI]|[wW]e|[yY]ou|[tT]hey|[hH]e|[sS]he|[wW]ho)\s+through\s+` +
			`(the|a|an|it|him|her|them|me|us|his|my|your|their|out|away)\b`,
		Flags:       []string{"he through the ball at me"},
		Leaves:      []string{"he threw the ball at me", "he went through the door"},
		Message:     "Should be \"$1 threw $2\"",
		Suggest:     "$1 threw $2",
		Category:    "Confused words",
		Explanation: explainThrewThrough,
	},
	{
		// A verb of motion before it forces the preposition.
		Pattern: `\b([wW]alked|[rR]an|[wW]ent|[dD]rove|[lL]ooked|[gG]ot|[cC]ame|` +
			`[pP]assed|[cC]ut|[bB]roke|[sS]aw|[fF]licked|[sS]ifted)\s+threw\b`,
		Flags:       []string{"we walked threw the park"},
		Leaves:      []string{"we walked through the park", "he threw it away"},
		Message:     "Should be \"$1 through\"",
		Suggest:     "$1 through",
		Category:    "Confused words",
		Explanation: explainThrewThrough,
	},

	// --- waist / waste ---
	{
		Pattern: `\b([dD]on't|[wW]on't|[dD]idn't|[tT]o|[wW]ill|[cC]an't|[nN]ot|` +
			`[sS]uch\s+a|[wW]hat\s+a|[cC]omplete|[tT]otal|[uU]tter)\s+waist\b`,
		Flags:    []string{"don't waist your time", "what a waist"},
		Leaves:   []string{"don't waste your time", "it fits my waist"},
		Message:  "Should be \"$1 waste\"",
		Suggest:  "$1 waste",
		Category: "Confused words",
		Explanation: "\"Waste\" means to use carelessly. Your \"waist\" is " +
			"the middle of your body.",
	},
	{
		// A measurement of the body. "The waste" on its own is rubbish and
		// perfectly correct, which is why only these compounds are matched.
		Pattern:  `\b[wW]aste\s+(size|line|band|measurement|height)\b`,
		Flags:    []string{"what is your waste size"},
		Leaves:   []string{"what is your waist size", "we sort the waste weekly"},
		Message:  "Should be \"waist $1\"",
		Suggest:  "waist $1",
		Category: "Confused words",
		Explanation: "Your \"waist\" is the middle of your body. \"Waste\" is " +
			"rubbish, or using something carelessly.",
	},

	// --- wait / weight ---
	{
		Pattern: `\b([pP]lease|[jJ]ust|[cC]an't|[cC]annot|[wW]ill|[wW]e'll|[iI]'ll|` +
			`[lL]et's|[dD]on't|[gG]oing\s+to|[hH]ad\s+to)\s+weight\b`,
		Flags:       []string{"please weight while I check"},
		Leaves:      []string{"please wait while I check", "check the weight"},
		Message:     "Should be \"$1 wait\"",
		Suggest:     "$1 wait",
		Category:    "Confused words",
		Explanation: explainWaitWeight,
	},
	{
		// "The wait" is correct English -- a period of waiting -- so only the
		// compounds that measure heaviness are matched.
		Pattern:     `\b([bB]ody|[bB]irth|[eE]xtra|[eE]xcess|[lL]ose|[lL]osing|[gG]ain|[gG]aining|[iI]n)\s+wait\b`,
		Flags:       []string{"I need to lose wait"},
		Leaves:      []string{"I need to lose weight", "the wait was worth it"},
		Message:     "Should be \"$1 weight\"",
		Suggest:     "$1 weight",
		Category:    "Confused words",
		Explanation: explainWaitWeight,
	},

	// --- way / weigh ---
	{
		Pattern: `\b([tT]o|[cC]an|[cC]ould|[wW]ill|[wW]ould|[mM]ust|[sS]hould|` +
			`[lL]et's|[pP]lease|[dD]id|[dD]oes)\s+((?:you|we|I|they)\s+)?way\s+(the|a|it|them|him|her|up|in|out)\b`,
		Flags:       []string{"can you way the bags"},
		Leaves:      []string{"can you weigh the bags", "which way should we go"},
		Message:     "Should be \"$1 $2weigh $3\"",
		Suggest:     "$1 $2weigh $3",
		Category:    "Confused words",
		Explanation: explainWayWeigh,
	},
	{
		Pattern:     `\b([wW]hich|[tT]he|[aA]ny|[nN]o|[sS]ome|[tT]his|[tT]hat|[aA]nother|[oO]ther)\s+weigh\s+(to|of|we|you|I|they|it|is|was|out|home|back|around|forward)\b`,
		Flags:       []string{"which weigh to go"},
		Leaves:      []string{"which way to go", "we must weigh the bags"},
		Message:     "Should be \"$1 way $2\"",
		Suggest:     "$1 way $2",
		Category:    "Confused words",
		Explanation: explainWayWeigh,
	},

	// --- wood / would ---
	{
		Pattern: `\b([iI]|[wW]e|[yY]ou|[tT]hey|[hH]e|[sS]he|[iI]t|[wW]ho|[tT]hat)\s+wood\s+` +
			`(be|have|has|had|like|love|want|need|go|do|make|say|take|get|help|build|buy|try|keep|come|prefer|rather|never|always|not|still|only)\b`,
		Flags:    []string{"I wood build the table"},
		Leaves:   []string{"I would build the table", "the table is made of wood"},
		Message:  "Should be \"$1 would $2\"",
		Suggest:  "$1 would $2",
		Category: "Confused words",
		Explanation: "\"Would\" is the conditional verb. \"Wood\" is the " +
			"material trees are made of.",
	},
	{
		Pattern:     `\b([mM]ade\s+of|[oO]ut\s+of|[fF]rom|[sS]olid|[hH]ard|[sS]oft|[fF]ire|[dD]river)\s+would\b`,
		Flags:       []string{"a table made of would"},
		Leaves:      []string{"a table made of wood", "I would build it"},
		Message:     "Should be \"$1 wood\"",
		Suggest:     "$1 wood",
		Category:    "Confused words",
		Explanation: "\"Wood\" is the material. \"Would\" is the conditional verb.",
	},

	// --- seam / seem ---
	{
		Pattern:     `\b([tT]he|[aA]|[tT]his|[tT]hat|[oO]ne|[eE]very|[bB]ack|[sS]ide)\s+seem\s+(came|is|was|split|ripped|tore|has|had|of|on)\b`,
		Flags:       []string{"the seem came loose"},
		Leaves:      []string{"the seam came loose", "they seem fine"},
		Message:     "Should be \"$1 seam $2\"",
		Suggest:     "$1 seam $2",
		Category:    "Confused words",
		Explanation: explainSeamSeem,
	},
	{
		Pattern: `\b([tT]hey|[yY]ou|[wW]e|[tT]hings|[pP]eople|[iI]t|[hH]e|[sS]he|` +
			`[tT]rousers|[sS]hoes)\s+seam\s+(fine|good|ok|okay|happy|sad|to|like|nice|right|wrong|better|worse|odd|strange)\b`,
		Flags:       []string{"the trousers seam fine"},
		Leaves:      []string{"the trousers seem fine", "the seam is damaged"},
		Message:     "Should be \"$1 seem $2\"",
		Suggest:     "$1 seem $2",
		Category:    "Confused words",
		Explanation: explainSeamSeem,
	},

	// --- stair / stare ---
	{
		Pattern:     `\b([tT]o|[dD]on't|[dD]idn't|[wW]ill|[wW]ould|[cC]an't|[sS]top|[sS]topped|[kK]eep|[kK]eeps)\s+stair\b`,
		Flags:       []string{"don't stair at people"},
		Leaves:      []string{"don't stare at people", "the top stair is loose"},
		Message:     "Should be \"$1 stare\"",
		Suggest:     "$1 stare",
		Category:    "Confused words",
		Explanation: explainStairStare,
	},
	{
		// "The stare" is a look and is correct, so a direction of travel has
		// to be there before this fires.
		Pattern:     `\b([dD]own|[uU]p|[cC]limbed|[cC]limb|[fF]ell\s+down)\s+the\s+stares?\b`,
		Flags:       []string{"walking down the stares"},
		Leaves:      []string{"walking down the stairs", "he gave me a hard stare"},
		Message:     "Should be \"$1 the stairs\"",
		Suggest:     "$1 the stairs",
		Category:    "Confused words",
		Explanation: explainStairStare,
	},

	// --- tail / tale ---
	{
		Pattern:     `\b([wW]agged|[wW]agging|[wW]ag|[iI]ts|[hH]is|[hH]er|[tT]he\s+dog's|[tT]he\s+cat's|[tT]he\s+fox's|[bB]ushy|[lL]ong)\s+tale\b`,
		Flags:       []string{"the dog wagged its tale"},
		Leaves:      []string{"the dog wagged its tail", "she told a tale"},
		Message:     "Should be \"$1 tail\"",
		Suggest:     "$1 tail",
		Category:    "Confused words",
		Explanation: explainTailTale,
	},
	{
		Pattern:     `\b([tT]old|[tT]elling|[tT]ell|[fF]airy|[tT]all|[cC]autionary|[cC]hildren's)\s+(a\s+|the\s+)?tail\b`,
		Flags:       []string{"I told a tail", "a fairy tail"},
		Leaves:      []string{"I told a tale", "the dog wagged its tail"},
		Message:     "Should be \"$1 $2tale\"",
		Suggest:     "$1 $2tale",
		Category:    "Confused words",
		Explanation: explainTailTale,
	},

	// --- throne / thrown ---
	{
		Pattern:     `\b([wW]as|[wW]ere|[bB]een|[bB]e|[bB]eing|[hH]ad|[hH]as|[hH]ave|[gG]ot)\s+throne\b`,
		Flags:       []string{"the crown was throne onto the table"},
		Leaves:      []string{"the crown was thrown onto the table", "he sat on the throne"},
		Message:     "Should be \"$1 thrown\"",
		Suggest:     "$1 thrown",
		Category:    "Confused words",
		Explanation: explainThroneThrown,
	},
	{
		Pattern:     `\b([oO]n\s+the|[tT]he|[hH]is|[hH]er|[rR]oyal|[gG]olden|[iI]ron)\s+thrown\b`,
		Flags:       []string{"the king sat on the thrown"},
		Leaves:      []string{"the king sat on the throne", "the ball was thrown"},
		Message:     "Should be \"$1 throne\"",
		Suggest:     "$1 throne",
		Category:    "Confused words",
		Explanation: explainThroneThrown,
	},

	// --- herd / heard ---
	{
		Pattern: `\b([iI]|[wW]e|[yY]ou|[tT]hey|[hH]e|[sS]he|[wW]ho|[nN]obody|[eE]veryone)\s+herd\s+` +
			`(a|an|the|it|that|about|him|her|them|you|me|nothing|something|anything)\b`,
		Flags:       []string{"I herd a noise outside"},
		Leaves:      []string{"I heard a noise outside", "a herd of cows"},
		Message:     "Should be \"$1 heard $2\"",
		Suggest:     "$1 heard $2",
		Category:    "Confused words",
		Explanation: explainHerdHeard,
	},
	{
		Pattern:     `\b([aA]|[tT]he|[wW]hole|[eE]ntire|[lL]arge|[sS]mall)\s+heard\s+of\s+(cows|cattle|sheep|goats|elephants|deer|buffalo|horses|animals|wildebeest)\b`,
		Flags:       []string{"a heard of cows"},
		Leaves:      []string{"a herd of cows", "I heard of it yesterday"},
		Message:     "Should be \"$1 herd of $2\"",
		Suggest:     "$1 herd of $2",
		Category:    "Confused words",
		Explanation: explainHerdHeard,
	},

	// --- guessed / guest ---
	{
		Pattern:  `\b([iI]|[wW]e|[yY]ou|[tT]hey|[hH]e|[sS]he)\s+guest\s+(that|it|the|wrong|right|correctly|at)\b`,
		Flags:    []string{"I guest that he would be early"},
		Leaves:   []string{"I guessed that he would be early", "our guest arrived"},
		Message:  "Should be \"$1 guessed $2\"",
		Suggest:  "$1 guessed $2",
		Category: "Confused words",
		Explanation: "\"Guessed\" is the past tense of \"guess\". A \"guest\" " +
			"is a visitor.",
	},
	{
		Pattern:  `\b([aA]|[tT]he|[oO]ur|[mM]y|[yY]our|[hH]is|[hH]er|[sS]pecial|[hH]ouse|[eE]very)\s+guessed\b`,
		Flags:    []string{"our guessed arrived early"},
		Leaves:   []string{"our guest arrived early", "I guessed the answer"},
		Message:  "Should be \"$1 guest\"",
		Suggest:  "$1 guest",
		Category: "Confused words",
		Explanation: "A \"guest\" is a visitor. \"Guessed\" is the past tense " +
			"of \"guess\".",
	},

	// --- board / bored ---
	{
		Pattern:     `\b([wW]as|[wW]ere|[aA]m|[iI]s|[aA]re|[fF]eel|[fF]elt|[gG]ot|[gG]etting|[sS]o|[vV]ery|[rR]eally|[qQ]uite)\s+board\b`,
		Flags:       []string{"I was board during the meeting"},
		Leaves:      []string{"I was bored during the meeting", "look at the board"},
		Message:     "Should be \"$1 bored\"",
		Suggest:     "$1 bored",
		Category:    "Confused words",
		Explanation: explainBoardBored,
	},
	{
		Pattern:     `\b([tT]he|[aA]|[nN]otice|[wW]hite|[bB]lack|[cC]hess|[dD]iving|[sS]urf|[sS]kirting|[kK]ey)\s+bored\b`,
		Flags:       []string{"stared at the bored"},
		Leaves:      []string{"stared at the board", "I was bored"},
		Message:     "Should be \"$1 board\"",
		Suggest:     "$1 board",
		Category:    "Confused words",
		Explanation: explainBoardBored,
	},

	// --- band / banned ---
	{
		Pattern:     `\b([wW]as|[wW]ere|[bB]een|[bB]e|[bB]eing|[gG]ot|[iI]s|[aA]re)\s+band\s+(from|by)\b`,
		Flags:       []string{"the band was band from playing"},
		Leaves:      []string{"the band was banned from playing"},
		Message:     "Should be \"$1 banned $2\"",
		Suggest:     "$1 banned $2",
		Category:    "Confused words",
		Explanation: explainBandBanned,
	},
	{
		Pattern:     `\b([tT]he|[aA]|[rR]ock|[jJ]azz|[bB]rass|[sS]chool|[lL]ive|[cC]over)\s+banned\s+(was|were|played|plays|playing|is|are|had|has)\b`,
		Flags:       []string{"the banned was playing all night"},
		Leaves:      []string{"the band was playing all night", "he was banned from playing"},
		Message:     "Should be \"$1 band $2\"",
		Suggest:     "$1 band $2",
		Category:    "Confused words",
		Explanation: explainBandBanned,
	},

	// --- altar / alter ---
	{
		// "Alter ego" is the one place "alter" follows a determiner.
		Pattern:      `\b([tT]he|[aA]n?|[hH]igh|[cC]hurch|[sS]tone|[bB]eside\s+the|[aA]t\s+the)\s+alter\b`,
		Antipatterns: []string{`\b(the|The|an?|An?)\s+alter\s+ego\b`},
		Flags:        []string{"they stood beside the alter"},
		Leaves:       []string{"they stood beside the altar", "the alter ego took over"},
		Message:      "Should be \"$1 altar\"",
		Suggest:      "$1 altar",
		Category:     "Confused words",
		Explanation:  explainAltarAlter,
	},
	{
		Pattern:     `\b([tT]o|[wW]ill|[cC]an|[cC]ould|[wW]ould|[mM]ust|[dD]idn't|[dD]on't|[nN]ot\s+to)\s+altar\b`,
		Flags:       []string{"they decided not to altar the ceremony"},
		Leaves:      []string{"they decided not to alter the ceremony", "beside the altar"},
		Message:     "Should be \"$1 alter\"",
		Suggest:     "$1 alter",
		Category:    "Confused words",
		Explanation: explainAltarAlter,
	},

	// --- council / counsel ---
	{
		Pattern:     `\b([lL]egal|[wW]ise|[sS]ound|[gG]ood|[sS]eek|[sS]ought|[gG]ave|[gG]iving|[dD]efence|[dD]efense)\s+council\b`,
		Flags:       []string{"the city sought legal council"},
		Leaves:      []string{"the city sought legal counsel", "the city council met"},
		Message:     "Should be \"$1 counsel\"",
		Suggest:     "$1 counsel",
		Category:    "Confused words",
		Explanation: explainCouncilCounsel,
	},
	{
		Pattern:     `\b([cC]ity|[tT]own|[lL]ocal|[cC]ounty|[dD]istrict|[bB]orough|[pP]arish|[sS]tudent)\s+counsel\b`,
		Flags:       []string{"the city counsel met on Tuesday"},
		Leaves:      []string{"the city council met on Tuesday", "she sought legal counsel"},
		Message:     "Should be \"$1 council\"",
		Suggest:     "$1 council",
		Category:    "Confused words",
		Explanation: explainCouncilCounsel,
	},

	// --- device / devise ---
	{
		Pattern:     `\b([aA]|[tT]he|[cC]lever|[sS]mall|[nN]ew|[mM]obile|[eE]lectronic|[mM]y|[yY]our|[tT]his|[tT]hat|[eE]ach)\s+devise\b`,
		Flags:       []string{"they used a clever devise"},
		Leaves:      []string{"they used a clever device", "they devised a solution"},
		Message:     "Should be \"$1 device\"",
		Suggest:     "$1 device",
		Category:    "Confused words",
		Explanation: explainDeviceDevise,
	},
	{
		Pattern:     `\b([tT]o|[wW]ill|[cC]an|[cC]ould|[mM]ust|[sS]hould|[wW]ould|[hH]elp)\s+device\b`,
		Flags:       []string{"we need to device a new plan"},
		Leaves:      []string{"we need to devise a new plan", "a clever device"},
		Message:     "Should be \"$1 devise\"",
		Suggest:     "$1 devise",
		Category:    "Confused words",
		Explanation: explainDeviceDevise,
	},

	// --- elicit / illicit ---
	{
		Pattern:     `\b([tT]o|[wW]ill|[cC]ould|[mM]ight|[wW]ould|[cC]an|[hH]oped\s+to|[tT]rying\s+to|[dD]esigned\s+to)\s+illicit\b`,
		Flags:       []string{"the question was designed to illicit information"},
		Leaves:      []string{"the question was designed to elicit information", "an illicit trade"},
		Message:     "Should be \"$1 elicit\"",
		Suggest:     "$1 elicit",
		Category:    "Confused words",
		Explanation: explainElicitIllicit,
	},
	{
		Pattern:     `\b([aA]n|[tT]he|[sS]ome|[aA]ny|[sS]uspected)\s+elicit\s+(activity|activities|drugs|trade|affair|behaviour|behavior|substances|goods|relationship|dealings)\b`,
		Flags:       []string{"an elicit activity"},
		Leaves:      []string{"an illicit activity", "designed to elicit information"},
		Message:     "Should be \"$1 illicit $2\"",
		Suggest:     "$1 illicit $2",
		Category:    "Confused words",
		Explanation: explainElicitIllicit,
	},

	// --- discreet / discrete ---
	{
		Pattern:     `\b([bB]e|[bB]eing|[vV]ery|[qQ]uite|[sS]o|[rR]emain|[rR]emained|[sS]tay|[sS]tayed|[wW]as|[wW]ere)\s+discrete\b`,
		Flags:       []string{"she was discrete about the matter"},
		Leaves:      []string{"she was discreet about the matter", "several discrete parts"},
		Message:     "Should be \"$1 discreet\"",
		Suggest:     "$1 discreet",
		Category:    "Confused words",
		Explanation: explainDiscreetDiscrete,
	},
	{
		Pattern:     `\b([sS]everal|[tT]wo|[tT]hree|[fF]our|[fF]ive|[mM]any|[sS]eparate|[iI]ndividual|[dD]istinct|[mM]ultiple)\s+discreet\s+(parts|units|steps|stages|values|items|elements|components|categories|packets|blocks|chunks)\b`,
		Flags:       []string{"several discreet parts"},
		Leaves:      []string{"several discrete parts", "she was discreet about it"},
		Message:     "Should be \"$1 discrete $2\"",
		Suggest:     "$1 discrete $2",
		Category:    "Confused words",
		Explanation: explainDiscreetDiscrete,
	},

	// --- ensure / insure ---
	{
		// Only where what follows cannot be insured. "Insure the car" is
		// correct and is why the object is matched rather than the verb alone.
		Pattern:     `\b([pP]lease|[tT]o|[mM]ust|[wW]ill|[sS]hould|[wW]ould|[cC]an|[hH]elp)\s+insure\s+(that|everyone|everybody|nothing|no\s+one|nobody|all)\b`,
		Flags:       []string{"we must insure everyone is safe"},
		Leaves:      []string{"we must ensure everyone is safe", "we must insure the car"},
		Message:     "Should be \"$1 ensure $2\"",
		Suggest:     "$1 ensure $2",
		Category:    "Confused words",
		Explanation: explainEnsureInsure,
	},
	{
		Pattern:     `\b([tT]o|[wW]ill|[cC]an|[mM]ust|[sS]hould)\s+ensure\s+(the|your|my|his|her|our|their)\s+(car|house|home|property|vehicle|building|business|belongings|contents|jewellery|jewelry)\b`,
		Flags:       []string{"remember to ensure the car"},
		Leaves:      []string{"remember to insure the car", "ensure the door is locked"},
		Message:     "Should be \"$1 insure $2 $3\"",
		Suggest:     "$1 insure $2 $3",
		Category:    "Confused words",
		Explanation: explainEnsureInsure,
	},

	// --- decent / descent ---
	{
		Pattern:     `\b([aA]|[tT]he|[hH]is|[hH]er|[mM]y|[oO]ur|[tT]heir|[sS]teep|[rR]apid|[sS]low|[fF]inal)\s+decent\s+(down|from|into|to|of|towards?|was|began|began\s+at)\b`,
		Flags:       []string{"he began his decent down the mountain"},
		Leaves:      []string{"he began his descent down the mountain", "a decent salary"},
		Message:     "Should be \"$1 descent $2\"",
		Suggest:     "$1 descent $2",
		Category:    "Confused words",
		Explanation: explainDecentDescent,
	},
	{
		Pattern:     `\b([aA]|[qQ]uite|[vV]ery|[pP]retty|[fF]airly|[rR]eally)\s+descent\s+(salary|job|meal|person|guy|bloke|price|wage|income|hotel|place|effort|attempt|chance|amount|number|night|day)\b`,
		Flags:       []string{"he has a descent salary"},
		Leaves:      []string{"he has a decent salary", "his descent down the mountain"},
		Message:     "Should be \"$1 decent $2\"",
		Suggest:     "$1 decent $2",
		Category:    "Confused words",
		Explanation: explainDecentDescent,
	},

	// --- lessen / lesson ---
	{
		Pattern:     `\b([aA]|[tT]he|[iI]mportant|[vV]aluable|[hH]ard|[fF]irst|[pP]iano|[dD]riving|[mM]aths|[eE]nglish|[hH]istory)\s+lessen\b`,
		Flags:       []string{"it taught me an important lessen"},
		Leaves:      []string{"it taught me an important lesson", "to lessen the pain"},
		Message:     "Should be \"$1 lesson\"",
		Suggest:     "$1 lesson",
		Category:    "Confused words",
		Explanation: explainLessenLesson,
	},
	{
		Pattern:     `\b([tT]o|[hH]elp|[hH]elped|[wW]ill|[cC]an|[cC]ould|[wW]ould|[mM]ight)\s+lesson\s+(the|a|my|your|his|her|its|our|their|pain|risk|impact|effect|burden|blow)\b`,
		Flags:       []string{"the medicine helped lesson the pain"},
		Leaves:      []string{"the medicine helped lessen the pain", "an important lesson"},
		Message:     "Should be \"$1 lessen $2\"",
		Suggest:     "$1 lessen $2",
		Category:    "Confused words",
		Explanation: explainLessenLesson,
	},

	// --- loan / lone ---
	{
		Pattern:     `\b([tT]he|[aA]|[oO]ne)\s+loan\s+(student|survivor|figure|wolf|voice|parent|worker|traveller|traveler|rider|gunman|ranger)\b`,
		Flags:       []string{"the loan student applied"},
		Leaves:      []string{"the lone student applied", "he applied for a loan"},
		Message:     "Should be \"$1 lone $2\"",
		Suggest:     "$1 lone $2",
		Category:    "Confused words",
		Explanation: explainLoanLone,
	},
	{
		Pattern:     `\b([bB]ank|[sS]tudent|[pP]ersonal|[hH]ome|[cC]ar|[bB]usiness|[bB]ridging|[pP]ayday)\s+lone\b`,
		Flags:       []string{"he applied for a student lone"},
		Leaves:      []string{"he applied for a student loan", "the lone student"},
		Message:     "Should be \"$1 loan\"",
		Suggest:     "$1 loan",
		Category:    "Confused words",
		Explanation: explainLoanLone,
	},

	// --- pole / poll ---
	{
		Pattern:     `\b([tT]he|[aA]|[fF]lag|[tT]elegraph|[tT]elephone|[lL]amp|[nN]orth|[sS]outh|[wW]ooden|[mM]etal|[tT]ent|[fF]ishing)\s+poll\b`,
		Flags:       []string{"attached to a flag poll"},
		Leaves:      []string{"attached to a flag pole", "the latest poll shows"},
		Message:     "Should be \"$1 pole\"",
		Suggest:     "$1 pole",
		Category:    "Confused words",
		Explanation: explainPolePoll,
	},
	{
		Pattern:     `\b([aA]n?|[tT]he|[oO]pinion|[eE]xit|[nN]ational|[rR]ecent|[lL]atest)\s+pole\s+(of|showed|shows|found|suggests|suggested|said|put)\b`,
		Flags:       []string{"the latest pole showed a lead"},
		Leaves:      []string{"the latest poll showed a lead", "the flag pole fell"},
		Message:     "Should be \"$1 poll $2\"",
		Suggest:     "$1 poll $2",
		Category:    "Confused words",
		Explanation: explainPolePoll,
	},

	// --- pore / pour ---
	{
		Pattern:     `\b([tT]o|[wW]ould|[lL]ike\s+to|[lL]ikes\s+to|[sS]pent|[sS]pend|[hH]ours)\s+pour\s+over\b`,
		Flags:       []string{"I like to pour over books"},
		Leaves:      []string{"I like to pore over books", "please pour the tea"},
		Message:     "Should be \"$1 pore over\"",
		Suggest:     "$1 pore over",
		Category:    "Confused words",
		Explanation: explainPorePour,
	},
	{
		Pattern:     `\b([tT]o|[wW]ill|[cC]an|[pP]lease|[cC]ould\s+you|[sS]hall\s+I)\s+pore\s+(the|a|me|him|her|us|them|some|out|in)\b`,
		Flags:       []string{"please pore the tea"},
		Leaves:      []string{"please pour the tea", "I like to pore over books"},
		Message:     "Should be \"$1 pour $2\"",
		Suggest:     "$1 pour $2",
		Category:    "Confused words",
		Explanation: explainPorePour,
	},

	// --- hoard / horde ---
	{
		Pattern:     `\b([aA]|[tT]he|[wW]hole|[eE]ntire|[hH]uge|[vV]ast)\s+hoard\s+of\s+(people|orcs|zombies|fans|tourists|barbarians|invaders|enemies|shoppers|children)\b`,
		Flags:       []string{"a hoard of people arrived"},
		Leaves:      []string{"a horde of people arrived", "the dragon's hoard of gold"},
		Message:     "Should be \"$1 horde of $2\"",
		Suggest:     "$1 horde of $2",
		Category:    "Confused words",
		Explanation: explainHoardHorde,
	},
	{
		Pattern:     `\b([tT]o|[lL]ikes\s+to|[lL]ike\s+to|[sS]tarted|[bB]egan|[wW]ill|[sS]top|[kK]eeps)\s+horde\b`,
		Flags:       []string{"the dragon likes to horde gold"},
		Leaves:      []string{"the dragon likes to hoard gold", "a horde of people"},
		Message:     "Should be \"$1 hoard\"",
		Suggest:     "$1 hoard",
		Category:    "Confused words",
		Explanation: explainHoardHorde,
	},

	// --- vain / vein ---
	{
		// A determiner is no use here: "the vain man" is correct, and both
		// words are perfectly ordinary after "a" or "the". Only a word that
		// describes a blood vessel decides it.
		Pattern:     `\b([pP]rominent|[bB]lue|[bB]ulging|[vV]aricose|[jJ]ugular|[mM]ain|[sS]wollen)\s+vain\b`,
		Flags:       []string{"the prominent vain on his hand"},
		Leaves:      []string{"the prominent vein on his hand", "he was vain about it", "the vain man noticed it"},
		Message:     "Should be \"$1 vein\"",
		Suggest:     "$1 vein",
		Category:    "Confused words",
		Explanation: explainVainVein,
	},
	{
		Pattern:     `\b([wW]as|[iI]s|[sS]o|[vV]ery|[tT]oo|[qQ]uite|[rR]ather|[bB]eing|[iI]n)\s+vein\b`,
		Flags:       []string{"he was vein about his hair", "it was all in vein"},
		Leaves:      []string{"he was vain about his hair", "it was all in vain", "a prominent vein"},
		Message:     "Should be \"$1 vain\"",
		Suggest:     "$1 vain",
		Category:    "Confused words",
		Explanation: explainVainVein,
	},

	// --- soar / sore ---
	{
		Pattern:     `\b([tT]o|[bB]egan\s+to|[sS]tarted\s+to|[wW]ill|[cC]an|[cC]ould|[wW]ould|[mM]ade\s+prices)\s+sore\b`,
		Flags:       []string{"the eagle began to sore"},
		Leaves:      []string{"the eagle began to soar", "my legs were sore"},
		Message:     "Should be \"$1 soar\"",
		Suggest:     "$1 soar",
		Category:    "Confused words",
		Explanation: explainSoarSore,
	},
	{
		Pattern:     `\b([lL]egs|[aA]rms|[bB]ack|[tT]hroat|[mM]uscles|[fF]eet|[hH]ead|[eE]yes|[sS]houlder|[kK]nee|[nN]eck)\s+(are|were|is|was|feel|felt|still)\s+soar\b`,
		Flags:       []string{"my legs were soar"},
		Leaves:      []string{"my legs were sore", "the eagle began to soar"},
		Message:     "Should be \"$1 $2 sore\"",
		Suggest:     "$1 $2 sore",
		Category:    "Confused words",
		Explanation: explainSoarSore,
	},

	// --- morning / mourning ---
	{
		// "In mourning" is correct; "in *the* mourning" is not.
		Pattern:     `\b([iI]n\s+the|[tT]his|[eE]very|[yY]esterday|[tT]omorrow|[eE]arly|[gG]ood)\s+mourning\b`,
		Flags:       []string{"we met in the mourning"},
		Leaves:      []string{"we met in the morning", "the family was in mourning"},
		Message:     "Should be \"$1 morning\"",
		Suggest:     "$1 morning",
		Category:    "Confused words",
		Explanation: explainMorningMourning,
	},
	{
		Pattern:     `\b([pP]eriod|[dD]ay|[dD]ays|[yY]ear|[tT]ime|[sS]tate)\s+of\s+morning\b`,
		Flags:       []string{"a period of morning"},
		Leaves:      []string{"a period of mourning", "the middle of the morning"},
		Message:     "Should be \"$1 of mourning\"",
		Suggest:     "$1 of mourning",
		Category:    "Confused words",
		Explanation: explainMorningMourning,
	},

	// --- medal / meddle ---
	{
		Pattern:     `\b([tT]o|[nN]ot\s+to|[dD]on't|[wW]on't|[dD]idn't|[sS]top|[sS]topped)\s+medal\s+(in|with)\b`,
		Flags:       []string{"she promised not to medal in the argument"},
		Leaves:      []string{"she promised not to meddle in the argument", "she won a medal"},
		Message:     "Should be \"$1 meddle $2\"",
		Suggest:     "$1 meddle $2",
		Category:    "Confused words",
		Explanation: explainMedalMeddle,
	},
	{
		Pattern:     `\b([aA]|[tT]he|[gG]old|[sS]ilver|[bB]ronze|[oO]lympic|[wW]on\s+a)\s+meddle\b`,
		Flags:       []string{"she won a meddle"},
		Leaves:      []string{"she won a medal", "don't meddle in it"},
		Message:     "Should be \"$1 medal\"",
		Suggest:     "$1 medal",
		Category:    "Confused words",
		Explanation: explainMedalMeddle,
	},

	// --- read / red ---
	{
		Pattern:     `\b([aA]|[tT]he|[bB]right|[dD]ark|[lL]ight|[dD]eep|[bB]lood)\s+read\s+(car|dress|shirt|light|wine|paint|colour|color|hair|flag|carpet|brick|ink|jumper|coat)\b`,
		Flags:       []string{"a book about a read car"},
		Leaves:      []string{"a book about a red car", "I read a book"},
		Message:     "Should be \"$1 red $2\"",
		Suggest:     "$1 red $2",
		Category:    "Confused words",
		Explanation: "\"Red\" is the colour. \"Read\" is what you do with a book.",
	},
	{
		Pattern:     `\b([iI]|[wW]e|[yY]ou|[tT]hey|[hH]e|[sS]he)\s+red\s+(the|a|an|it|that|this|my|your|his|her|about|through)\b`,
		Flags:       []string{"I red the book yesterday"},
		Leaves:      []string{"I read the book yesterday", "the cover was red"},
		Message:     "Should be \"$1 read $2\"",
		Suggest:     "$1 read $2",
		Category:    "Confused words",
		Explanation: "\"Read\" is the verb. \"Red\" is the colour.",
	},

	// --- sole / soul ---
	{
		Pattern:  `\b([tT]he|[aA]|[mM]y|[yY]our|[hH]is|[hH]er|[rR]ubber|[lL]eather)\s+soul\s+of\s+(my|the|your|his|her|a|this|that)\s+(shoe|shoes|boot|boots|foot|feet|trainer|trainers)\b`,
		Flags:    []string{"the soul of my shoe is worn"},
		Leaves:   []string{"the sole of my shoe is worn", "it was good for the soul"},
		Message:  "Should be \"$1 sole of $2 $3\"",
		Suggest:  "$1 sole of $2 $3",
		Category: "Confused words",
		Explanation: "The \"sole\" is the bottom of a shoe or foot. A \"soul\" " +
			"is a person's inner self.",
	},

	// --- profit / prophet ---
	{
		Pattern:  `\b([mM]ade|[tT]urned|[nN]et|[gG]ross|[aA]nnual|[qQ]uarterly|[rR]ecord|[oO]perating)\s+(a\s+)?prophet\b`,
		Flags:    []string{"the company made a prophet"},
		Leaves:   []string{"the company made a profit", "the prophet preached"},
		Message:  "Should be \"$1 $2profit\"",
		Suggest:  "$1 $2profit",
		Category: "Confused words",
		Explanation: "A \"profit\" is financial gain. A \"prophet\" is a " +
			"religious messenger.",
	},

	// --- aisle / isle ---
	{
		Pattern:      `\b([tT]he|[aA]n?|[sS]upermarket|[cC]entre|[cC]enter|[mM]iddle|[fF]rozen|[dD]airy|[bB]read|[wW]edding|[dD]own\s+the)\s+isle\b`,
		Antipatterns: []string{`\b[iI]sle\s+of\b`},
		Flags:        []string{"we walked down the supermarket isle"},
		Leaves:       []string{"we walked down the supermarket aisle", "we visited the Isle of Wight"},
		Message:      "Should be \"$1 aisle\"",
		Suggest:      "$1 aisle",
		Category:     "Confused words",
		Explanation: "An \"aisle\" is a passage between shelves or seats. An " +
			"\"isle\" is an island.",
	},

	// --- blue / blew ---
	{
		Pattern:     `\b([tT]he\s+)?([wW]ind|[bB]reeze|[gG]ale|[sS]torm)\s+blue\b`,
		Flags:       []string{"the wind blue strongly"},
		Leaves:      []string{"the wind blew strongly", "the sky was blue"},
		Message:     "Should be \"$1$2 blew\"",
		Suggest:     "$1$2 blew",
		Category:    "Confused words",
		Explanation: "\"Blew\" is the past tense of \"blow\". \"Blue\" is the colour.",
	},
	{
		Pattern:     `\b([sS]ky|[sS]ea|[eE]yes|[sS]hirt|[dD]ress|[cC]ar|[pP]aint|[cC]olour|[cC]olor)\s+(was|were|is|are|looked)\s+blew\b`,
		Flags:       []string{"the sky was blew"},
		Leaves:      []string{"the sky was blue", "the wind blew"},
		Message:     "Should be \"$1 $2 blue\"",
		Suggest:     "$1 $2 blue",
		Category:    "Confused words",
		Explanation: "\"Blue\" is the colour. \"Blew\" is the past tense of \"blow\".",
	},

	// --- whine / wine ---
	{
		Pattern:     `\b([tT]o|[bB]egan\s+to|[sS]tarted\s+to|[dD]on't|[sS]top|[kK]eeps|[kK]eep)\s+wine\b`,
		Flags:       []string{"the child began to wine"},
		Leaves:      []string{"the child began to whine", "the adults drank wine"},
		Message:     "Should be \"$1 whine\"",
		Suggest:     "$1 whine",
		Category:    "Confused words",
		Explanation: "To \"whine\" is to complain. \"Wine\" is the drink.",
	},
	{
		Pattern:     `\b([gG]lass\s+of|[bB]ottle\s+of|[rR]ed|[wW]hite|[dD]rank|[dD]rink|[dD]rinking|[sS]ipped|[pP]oured)\s+whine\b`,
		Flags:       []string{"a glass of whine"},
		Leaves:      []string{"a glass of wine", "the child began to whine"},
		Message:     "Should be \"$1 wine\"",
		Suggest:     "$1 wine",
		Category:    "Confused words",
		Explanation: "\"Wine\" is the drink. To \"whine\" is to complain.",
	},

	// --- steal / steel ---
	{
		// "Steel yourself" is the reading this must not touch.
		Pattern:      `\b([tT]o|[wW]ill|[cC]an|[cC]ould|[wW]ould|[mM]ight|[dD]idn't|[dD]on't|[tT]ried\s+to)\s+steel\b`,
		Antipatterns: []string{`\b([tT]o|[wW]ill|[cC]an|[cC]ould|[wW]ould|[mM]ight|[dD]idn't|[dD]on't|[tT]ried\s+to)\s+steel\s+(yourself|himself|herself|myself|themselves|ourselves)\b`},
		Flags:        []string{"nobody tried to steel it"},
		Leaves:       []string{"nobody tried to steal it", "he had to steel himself for it"},
		Message:      "Should be \"$1 steal\"",
		Suggest:      "$1 steal",
		Category:     "Confused words",
		Explanation:  "To \"steal\" is to take unlawfully. \"Steel\" is the metal.",
	},
	{
		Pattern:     `\b([sS]tainless|[cC]arbon|[gG]alvanised|[gG]alvanized|[mM]olten|[sS]heet|[sS]crap)\s+steal\b`,
		Flags:       []string{"they used stainless steal"},
		Leaves:      []string{"they used stainless steel", "nobody tried to steal it"},
		Message:     "Should be \"$1 steel\"",
		Suggest:     "$1 steel",
		Category:    "Confused words",
		Explanation: "\"Steel\" is the metal. To \"steal\" is to take unlawfully.",
	},

	// --- sail / sale ---
	{
		Pattern:  `\b([tT]o|[wW]ill|[cC]an|[cC]ould|[wW]ould|[lL]earned\s+to|[lL]earn\s+to|[wW]ent)\s+sale\b`,
		Flags:    []string{"we learned to sale last summer"},
		Leaves:   []string{"we learned to sail last summer", "the shop held a sale"},
		Message:  "Should be \"$1 sail\"",
		Suggest:  "$1 sail",
		Category: "Confused words",
		Explanation: "To \"sail\" is to travel by boat. A \"sale\" is selling " +
			"something at a price.",
	},
	{
		Pattern:  `\b([oO]n|[fF]or)\s+sail\b`,
		Flags:    []string{"the house is for sail"},
		Leaves:   []string{"the house is for sale", "we learned to sail"},
		Message:  "Should be \"$1 sale\"",
		Suggest:  "$1 sale",
		Category: "Confused words",
		Explanation: "A \"sale\" is selling something. To \"sail\" is to " +
			"travel by boat.",
	},

	// --- desert / dessert ---
	{
		Pattern:     `\b([fF]or|[hH]ad|[eE]at|[eE]ating|[oO]rdered|[sS]weet|[cC]hocolate)\s+desert\b`,
		Flags:       []string{"we had desert afterwards"},
		Leaves:      []string{"we had dessert afterwards", "crossing the desert"},
		Message:     "Should be \"$1 dessert\"",
		Suggest:     "$1 dessert",
		Category:    "Confused words",
		Explanation: "A \"dessert\" is the sweet course. A \"desert\" is a dry region.",
	},
	{
		Pattern:     `\b([sS]ahara|[aA]rabian|[gG]obi|[mM]ojave|[hH]ot|[dD]ry|[vV]ast|[bB]arren|[sS]andy|[cC]rossing\s+the|[aA]cross\s+the|[iI]nto\s+the)\s+dessert\b`,
		Flags:       []string{"after crossing the dessert"},
		Leaves:      []string{"after crossing the desert", "we had dessert"},
		Message:     "Should be \"$1 desert\"",
		Suggest:     "$1 desert",
		Category:    "Confused words",
		Explanation: "A \"desert\" is a dry region. A \"dessert\" is the sweet course.",
	},

	// --- forth / fourth ---
	{
		Pattern:     `\b([tT]he|[hH]is|[hH]er|[mM]y|[oO]ur|[tT]heir|[eE]very)\s+forth\s+(day|time|week|month|year|attempt|quarter|floor|place|round|goal|child)\b`,
		Flags:       []string{"on the forth day"},
		Leaves:      []string{"on the fourth day", "she stepped forth"},
		Message:     "Should be \"$1 fourth $2\"",
		Suggest:     "$1 fourth $2",
		Category:    "Confused words",
		Explanation: "\"Fourth\" is the position after third. \"Forth\" means forward.",
	},
	{
		Pattern:     `\b([sS]tepped|[sS]tep|[cC]ame|[cC]ome|[bB]rought|[bB]ring|[sS]et|[pP]ut|[bB]ack\s+and)\s+fourth\b`,
		Flags:       []string{"she stepped fourth", "back and fourth"},
		Leaves:      []string{"she stepped forth", "back and forth", "on the fourth day"},
		Message:     "Should be \"$1 forth\"",
		Suggest:     "$1 forth",
		Category:    "Confused words",
		Explanation: "\"Forth\" means forward. \"Fourth\" is the position after third.",
	},

	// --- manner / manor ---
	{
		Pattern:  `\b([iI]n\s+a|[iI]n\s+this|[iI]n\s+that|[pP]olite|[rR]ude|[fF]riendly|[pP]rofessional|[tT]imely|[oO]rderly|[bB]edside|[gG]ood|[bB]ad)\s+manor\b`,
		Flags:    []string{"he behaved in a polite manor"},
		Leaves:   []string{"he behaved in a polite manner", "the old manor house"},
		Message:  "Should be \"$1 manner\"",
		Suggest:  "$1 manner",
		Category: "Confused words",
		Explanation: "A \"manner\" is a way of behaving. A \"manor\" is a " +
			"large country house.",
	},
	{
		Pattern:  `\b[mM]anner\s+(house|estate|grounds)\b`,
		Flags:    []string{"they visited the old manner house"},
		Leaves:   []string{"they visited the old manor house", "in a polite manner"},
		Message:  "Should be \"manor $1\"",
		Suggest:  "manor $1",
		Category: "Confused words",
		Explanation: "A \"manor\" is a large country house. A \"manner\" is a " +
			"way of behaving.",
	},

	// --- presence / presents ---
	{
		Pattern:     `\b([iI]n\s+the|[hH]is|[hH]er|[mM]y|[yY]our|[oO]ur|[tT]heir)\s+presents\s+of\b`,
		Flags:       []string{"in the presents of the head teacher"},
		Leaves:      []string{"in the presence of the head teacher", "she opened her presents"},
		Message:     "Should be \"$1 presence of\"",
		Suggest:     "$1 presence of",
		Category:    "Confused words",
		Explanation: "\"Presence\" is being somewhere. \"Presents\" are gifts.",
	},

	// --- capital / capitol ---
	{
		Pattern:  `\b[cC]apitol\s+(city|cities)\b`,
		Flags:    []string{"London is the capitol city"},
		Leaves:   []string{"London is the capital city"},
		Message:  "Should be \"capital $1\"",
		Suggest:  "capital $1",
		Category: "Confused words",
		Explanation: "A \"capital\" is a city or wealth. The \"Capitol\" is a " +
			"specific government building in the United States.",
	},

	// --- creak / creek ---
	{
		Pattern:     `\b([fF]loor|[fF]loorboard|[fF]loorboards|[dD]oor|[sS]tairs|[hH]inge|[gG]ate|[bB]ed|[cC]hair|[bB]oard)\s+(began\s+to\s+|started\s+to\s+)?creek\b`,
		Flags:       []string{"we heard the floor creek"},
		Leaves:      []string{"we heard the floor creak", "beside the small creek"},
		Message:     "Should be \"$1 $2creak\"",
		Suggest:     "$1 $2creak",
		Category:    "Confused words",
		Explanation: "A \"creak\" is a squeaking sound. A \"creek\" is a small stream.",
	},
	{
		Pattern:     `\b([sS]mall|[lL]ittle|[nN]earby|[sS]hallow|[mM]uddy|[bB]abbling)\s+creak\b`,
		Flags:       []string{"beside the small creak"},
		Leaves:      []string{"beside the small creek", "the floor began to creak"},
		Message:     "Should be \"$1 creek\"",
		Suggest:     "$1 creek",
		Category:    "Confused words",
		Explanation: "A \"creek\" is a small stream. A \"creak\" is a squeaking sound.",
	},

	// --- formally / formerly ---
	{
		Pattern:     `\b([wW]as|[wW]ere|[iI]s|[aA]re)\s+formally\s+(known\s+as|called|named|a|an|the)\b`,
		Flags:       []string{"the building was formally a school"},
		Leaves:      []string{"the building was formerly a school", "it was formally opened"},
		Message:     "Should be \"$1 formerly $2\"",
		Suggest:     "$1 formerly $2",
		Category:    "Confused words",
		Explanation: "\"Formerly\" means previously. \"Formally\" means officially.",
	},

	// --- toe / tow ---
	{
		Pattern:     `\b([mM]y|[hH]is|[hH]er|[yY]our|[tT]he|[bB]ig|[lL]ittle|[bB]roken|[sS]tubbed\s+my)\s+tow\b`,
		Flags:       []string{"I hurt my tow"},
		Leaves:      []string{"I hurt my toe", "we had to tow the car"},
		Message:     "Should be \"$1 toe\"",
		Suggest:     "$1 toe",
		Category:    "Confused words",
		Explanation: "A \"toe\" is on your foot. To \"tow\" is to pull a vehicle.",
	},
	{
		Pattern:     `\b[tT]oe\s+(truck|trucks|bar|rope|hitch)\b`,
		Flags:       []string{"we called a toe truck"},
		Leaves:      []string{"we called a tow truck", "I hurt my toe"},
		Message:     "Should be \"tow $1\"",
		Suggest:     "tow $1",
		Category:    "Confused words",
		Explanation: "To \"tow\" is to pull a vehicle. A \"toe\" is on your foot.",
	},

	// --- bare / bear ---
	{
		Pattern:  `\b[bB]are\s+in\s+mind\b`,
		Flags:    []string{"bare in mind that it is late"},
		Leaves:   []string{"bear in mind that it is late"},
		Message:  "Should be \"bear in mind\"",
		Suggest:  "bear in mind",
		Category: "Confused words",
		Explanation: "To \"bear\" something in mind is to keep it there. " +
			"\"Bare\" means uncovered.",
	},
	{
		Pattern:     `\b[bB]ear\s+(feet|foot|hands|skin|minimum|essentials|bones|necessities)\b`,
		Flags:       []string{"the bear minimum", "walking in bear feet"},
		Leaves:      []string{"the bare minimum", "walking in bare feet"},
		Message:     "Should be \"bare $1\"",
		Suggest:     "bare $1",
		Category:    "Confused words",
		Explanation: "\"Bare\" means uncovered or minimal. A \"bear\" is the animal.",
	},
}
