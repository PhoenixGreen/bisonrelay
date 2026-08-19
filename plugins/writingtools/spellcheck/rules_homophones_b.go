package spellcheck

// rules_homophones_b.go is the second pass over the homophones, and the harder
// half.
//
// The pairs in rules_homophones.go divide by part of speech: one of the two is
// a noun and the other a verb, so "to" or a determiner settles it. The pairs
// here do not. Sun and son are both nouns, night and knight are both nouns,
// flower and flour are both nouns -- nothing about the grammar of the sentence
// can tell them apart, and no amount of looking at the words around them will
// either, unless those words are specific.
//
// So these are collocation rules almost throughout: not "a noun cannot follow
// a modal" but "nobody has ever written a bag of flower". That makes them
// narrower than the rules next door -- each catches one phrasing rather than a
// position -- and it is why there are more of them per pair and why they say
// nothing at all about the general case.
//
// The corresponding risk is different too. A position rule goes wrong by being
// too broad; a collocation rule goes wrong by naming a collocation that has a
// second reading. "The son rose" is a sunrise or a boy standing up. "Free rein"
// and "free reign" are one of them a mistake and the other a mistake people
// have made so often it is now in dictionaries. Where a second reading exists
// and is ordinary, the pair is simply absent.

const (
	explainSeeSea    = "\"See\" is what your eyes do. The \"sea\" is the ocean."
	explainWhereWear = "\"Where\" asks about a place. \"Wear\" is what you do with clothes."
	explainWhereWere = "\"Where\" asks about a place. \"Were\" is the " +
		"past tense of \"are\"."
	explainWeatherWhether  = "\"Whether\" introduces a choice. \"Weather\" is rain and sunshine."
	explainRightWrite      = "\"Write\" is what you do with a pen. \"Right\" means correct, or the opposite of left."
	explainBuyBy           = "\"Buy\" means to purchase. \"By\" is the preposition."
	explainSunSon          = "The \"sun\" is the star. A \"son\" is a male child."
	explainNightKnight     = "\"Night\" is when it is dark. A \"knight\" is a medieval warrior."
	explainFlowerFlour     = "A \"flower\" is a blossom. \"Flour\" is what bread is made from."
	explainCellSell        = "A \"cell\" is a small compartment or unit. To \"sell\" is to exchange for money."
	explainFairFare        = "\"Fair\" means reasonable. A \"fare\" is the price of a journey."
	explainGreatGrate      = "\"Great\" means excellent or large. A \"grate\" is a metal framework."
	explainHealHeel        = "To \"heal\" is to recover. Your \"heel\" is the back of your foot."
	explainIdleIdol        = "\"Idle\" means not active. An \"idol\" is someone admired."
	explainMailMale        = "\"Mail\" is letters and parcels. \"Male\" is the sex."
	explainMainMane        = "\"Main\" means chief. A \"mane\" is the hair around an animal's neck."
	explainPairPear        = "A \"pair\" is two of something. A \"pear\" is the fruit."
	explainPlainPlane      = "A \"plane\" is an aircraft. \"Plain\" means flat or simple."
	explainPrincipal       = "A \"principal\" is the head of something, or the main one. A \"principle\" is a rule or belief."
	explainRainReign       = "\"Rain\" falls from clouds. A \"reign\" is a monarch's rule. A \"rein\" controls a horse."
	explainRoadRode        = "A \"road\" is a route. \"Rode\" is the past tense of \"ride\"."
	explainRoleRoll        = "A \"role\" is a part or a job. A \"roll\" is a movement, or bread."
	explainCoarseCourse    = "\"Coarse\" means rough. A \"course\" is a route or a class."
	explainCueQueue        = "A \"cue\" is a signal. A \"queue\" is a line of people."
	explainCurrantCurrent  = "A \"currant\" is a small dried fruit. A \"current\" is a flow."
	explainDualDuel        = "\"Dual\" means two. A \"duel\" is a fight between two people."
	explainForewordForward = "A \"foreword\" is an introduction to a book. \"Forward\" means ahead."
	explainGaitGate        = "A \"gait\" is a manner of walking. A \"gate\" is a barrier."
	explainHoarseHorse     = "\"Hoarse\" describes a rough voice. A \"horse\" is the animal."
	explainMinerMinor      = "A \"miner\" digs. \"Minor\" means lesser or underage."
	explainPeakPeek        = "A \"peak\" is the highest point. A \"peek\" is a quick look."
	explainPedalPeddle     = "A \"pedal\" is a foot lever. To \"peddle\" is to sell."
	explainPrayPrey        = "To \"pray\" is to worship. \"Prey\" is a hunted animal."
	explainRealReel        = "\"Real\" means genuine. A \"reel\" is a spool."
	explainRootRoute       = "A \"root\" is the underground part of a plant. A \"route\" is a path."
	explainShearSheer      = "To \"shear\" is to cut. \"Sheer\" means utter, or very steep."
	explainSiteSight       = "A \"site\" is a location. A \"sight\" is something seen. To \"cite\" is to quote a source."
	explainSuiteSweet      = "A \"suite\" is a set of rooms. \"Sweet\" means sugary."
	explainTeamTeem        = "A \"team\" is a group. To \"teem\" is to be full of something."
	explainWaiveWave       = "To \"waive\" is to give up a right. A \"wave\" is a movement of the hand."
	explainBeachBeech      = "A \"beach\" is the shore. A \"beech\" is a kind of tree."
	explainClawsClause     = "\"Claws\" are an animal's nails. A \"clause\" is a section of a document."
	explainEarnUrn         = "To \"earn\" is to be paid for work. An \"urn\" is a container."
	explainGuiltGilt       = "\"Guilt\" is the feeling of having done wrong. \"Gilt\" is a thin layer of gold."
	explainHairHare        = "\"Hair\" grows on your head. A \"hare\" is the animal."
	explainHallHaul        = "A \"hall\" is a passage or large room. A \"haul\" is what has been carried off."
	explainHimHymn         = "\"Him\" is the pronoun. A \"hymn\" is a religious song."
	explainLeakLeek        = "A \"leak\" is escaping liquid. A \"leek\" is the vegetable."
	explainMadeMaid        = "\"Made\" is the past tense of \"make\". A \"maid\" is a domestic worker."
	explainOarOre          = "An \"oar\" rows a boat. \"Ore\" is rock containing metal."
	explainPailPale        = "A \"pail\" is a bucket. \"Pale\" means light in colour."
	explainPealPeel        = "A \"peal\" is a loud ringing. To \"peel\" is to remove the skin."
	explainRestWrest       = "To \"rest\" is to relax. To \"wrest\" is to take by force."
	explainTenseTents      = "\"Tense\" means nervous. \"Tents\" are what you camp in."
	explainTideTied        = "The \"tide\" is the sea rising and falling. \"Tied\" means fastened."
	explainClothesCloths   = "\"Clothes\" are garments. \"Cloths\" are pieces of fabric."
	explainImminentEminent = "\"Imminent\" means about to happen. \"Eminent\" means distinguished."
	explainInciteInsight   = "To \"incite\" is to stir up. An \"insight\" is an understanding."
)

// homophonePairRules are the pairs no grammatical position can separate, each
// caught in a phrase where only one spelling has ever been written.
var homophonePairRules = []GrammarRule{
	// --- see / sea ---
	{
		Pattern:     `\b([cC]an|[cC]an't|[cC]ould|[wW]ill|[wW]ould|[tT]o|[lL]et\s+me|[dD]idn't|[dD]on't|[gG]o\s+and)\s+sea\b`,
		Flags:       []string{"I can sea it from my window"},
		Leaves:      []string{"I can see it from my window", "the sea was calm"},
		Message:     "Should be \"$1 see\"",
		Suggest:     "$1 see",
		Category:    "Confused words",
		Explanation: explainSeeSea,
	},
	{
		Pattern:     `\b([tT]he\s+open|[tT]he\s+deep|[bB]y\s+the|[aA]t|[cC]alm|[rR]ough|[cC]hoppy|[oO]pen)\s+see\b`,
		Flags:       []string{"we live by the see"},
		Leaves:      []string{"we live by the sea", "I can see it"},
		Message:     "Should be \"$1 sea\"",
		Suggest:     "$1 sea",
		Category:    "Confused words",
		Explanation: explainSeeSea,
	},

	// --- where / wear ---
	{
		// A question word takes an auxiliary after it; "wear" cannot.
		Pattern:     `\b[wW]ear\s+(did|do|does|is|are|was|were|can|could|will|would|should|am|have|has)\b`,
		Flags:       []string{"wear did you put it"},
		Leaves:      []string{"where did you put it", "what will you wear"},
		Message:     "Should be \"where $1\"",
		Suggest:     "where $1",
		Category:    "Confused words",
		Explanation: explainWhereWear,
	},
	// --- where / were ---
	//
	// The pair next door, and it was missing entirely: "Were am I going" went
	// unflagged while the identical "Wear did you put it" was caught, because
	// the wear/where rules were written as a pair and nobody wrote the third.
	// Both directions are settled by grammar rather than by meaning, which is
	// why these are errors and not checks -- there is no reading of "were am"
	// that anybody meant.
	{
		// Same shape as the wear rule above: a question word takes an
		// auxiliary, and "were" is one itself, so it cannot precede another.
		// The subject after the auxiliary is matched too, because "were do"
		// and "were can" each turn up inside a hyphenated compound -- "those
		// were do-or-die moments", "the tins were can-shaped" -- where the
		// second word is not an auxiliary at all.
		Pattern: `\b[wW]ere\s+(am|is|was|did|do|does|has|have|can|could|will|` +
			`would|should|must)\s+(I|you|we|they|he|she|it|the|a|an|this|that|` +
			`my|your|his|her|our|their)\b`,
		Flags: []string{
			"Were am I going",
			"were do you live",
			"were can I find the form",
		},
		Leaves: []string{
			"where am I going",
			"they were doing their best",
			"there were the usual complaints",
		},
		Message:     "Should be \"where $1 $2\"",
		Suggest:     "where $1 $2",
		Category:    "Confused words",
		Explanation: explainWhereWere,
	},
	{
		// The other direction. Only the three pronouns that cannot take a
		// relative "where" after them: "there where the road bends" is
		// awkward but correct, and "the place where" is the ordinary use.
		Pattern: `\b([wW]e|[tT]hey|[yY]ou)\s+where\b`,
		Antipatterns: []string{
			// The elliptical "where possible", which introduces a clause
			// rather than standing in for a verb.
			`\b([wW]e|[tT]hey|[yY]ou)\s+where\s+(possible|necessary|appropriate|applicable|available|needed|required)\b`,
		},
		Flags: []string{
			"we where going to leave",
			"they where happy with it",
		},
		Leaves: []string{
			"we were going to leave",
			"we where possible avoid the queue",
			"the place where they met",
		},
		// Names the pair rather than just the fix, because an agreement rule
		// in rules_agreement.go corrects "we was" with the same words -- and
		// a reader told "Should be \"we were\"" about "we where" would be
		// looking for a verb they got wrong rather than a word they confused.
		Message:     "Should be \"$1 were\", not \"where\"",
		Suggest:     "$1 were",
		Category:    "Confused words",
		Explanation: explainWhereWere,
	},
	{
		// "Go to where the road ends" is correct, so an object has to follow.
		Pattern:     `\b([dD]id|[dD]o|[dD]oes|[wW]ill|[cC]an|[cC]ould|[wW]ould|[sS]hould)\s+(?:you|we|they|he|she|I)\s+where\s+(a|an|the|my|your|his|her|our|their|it|them)\b`,
		Flags:       []string{"did you where your new shoes"},
		Leaves:      []string{"did you wear your new shoes", "go to where the road ends"},
		Message:     "Should be \"$1 wear $2\"",
		Suggest:     "$1 wear $2",
		Category:    "Confused words",
		Explanation: explainWhereWear,
	},

	// --- weather / whether ---
	{
		Pattern:     `\b([kK]now|[kK]nows|[kK]new|[wW]onder|[wW]ondered|[aA]sk|[aA]sked|[dD]ecide|[dD]ecided|[uU]nsure|[dD]oubt|[cC]heck|[sS]ee)\s+weather\b`,
		Flags:       []string{"I don't know weather it will improve"},
		Leaves:      []string{"I don't know whether it will improve", "the weather improved"},
		Message:     "Should be \"$1 whether\"",
		Suggest:     "$1 whether",
		Category:    "Confused words",
		Explanation: explainWeatherWhether,
	},
	{
		Pattern:     `\b([tT]he|[gG]ood|[bB]ad|[nN]ice|[cC]old|[wW]arm|[hH]ot|[wW]et|[dD]ry|[sS]tormy|[sS]unny|[aA]wful|[lL]ovely)\s+whether\b`,
		Flags:       []string{"the whether will improve"},
		Leaves:      []string{"the weather will improve", "whether or not it rains"},
		Message:     "Should be \"$1 weather\"",
		Suggest:     "$1 weather",
		Category:    "Confused words",
		Explanation: explainWeatherWhether,
	},

	// --- right / write ---
	{
		// "To right a wrong" is the reading this must not touch.
		Pattern:      `\b([tT]o|[wW]ill|[cC]an|[cC]ould|[pP]lease|[mM]ust|[sS]hould|[wW]ould)\s+right\s+(a|an|the|it|me|to|about|down|back|something)\b`,
		Antipatterns: []string{`\b([tT]o|[wW]ill|[cC]an|[cC]ould|[mM]ust|[sS]hould|[wW]ould)\s+right\s+a\s+wrong\b`},
		Flags:        []string{"please right the answer"},
		Leaves:       []string{"please write the answer", "we must right a wrong"},
		Message:      "Should be \"$1 write $2\"",
		Suggest:      "$1 write $2",
		Category:     "Confused words",
		Explanation:  explainRightWrite,
	},
	{
		Pattern:     `\b([tT]he|[aA]|[mM]y|[yY]our|[iI]s|[wW]as|[tT]hat's|[iI]t's|[nN]ot|[aA]ll)\s+write\s+(answer|thing|way|time|place|person|choice|decision|direction|one|now|here|then|words?)\b`,
		Flags:       []string{"the write answer"},
		Leaves:      []string{"the right answer", "please write it down"},
		Message:     "Should be \"$1 right $2\"",
		Suggest:     "$1 right $2",
		Category:    "Confused words",
		Explanation: explainRightWrite,
	},
	{
		// A rite is a ceremony; a right is an entitlement.
		Pattern:     `\b[rR]ight\s+of\s+passage\b`,
		Flags:       []string{"it was a right of passage"},
		Leaves:      []string{"it was a rite of passage"},
		Message:     "Should be \"rite of passage\"",
		Suggest:     "rite of passage",
		Category:    "Confused words",
		Explanation: "A \"rite\" is a ceremony marking a stage of life. A \"right\" is an entitlement.",
	},

	// --- buy / by ---
	{
		Pattern:     `\b([tT]o|[wW]ill|[cC]an|[cC]ould|[wW]ould|[mM]ust|[sS]hould|[gG]oing\s+to|[nN]eed\s+to|[wW]ant\s+to)\s+by\s+(some|a|an|the|it|them|one|two|more|new|another)\b`,
		Flags:       []string{"I will by some milk"},
		Leaves:      []string{"I will buy some milk", "I will be there by six"},
		Message:     "Should be \"$1 buy $2\"",
		Suggest:     "$1 buy $2",
		Category:    "Confused words",
		Explanation: explainBuyBy,
	},
	{
		Pattern:     `\b[bB]uy\s+(now|then|the\s+way|the\s+time|myself|yourself|himself|herself|accident|mistake|car|train|bus|foot|hand)\b`,
		Flags:       []string{"buy the way, it arrived"},
		Leaves:      []string{"by the way, it arrived", "buy the tickets now"},
		Message:     "Should be \"by $1\"",
		Suggest:     "by $1",
		Category:    "Confused words",
		Explanation: explainBuyBy,
	},

	// --- be / bee ---
	{
		Pattern:     `\b([tT]o|[wW]ill|[cC]an|[cC]ould|[wW]ould|[mM]ust|[sS]hould|[mM]ay|[mM]ight|[wW]on't|[sS]hall)\s+bee\b`,
		Flags:       []string{"I want to bee brave"},
		Leaves:      []string{"I want to be brave", "I saw a bee"},
		Message:     "Should be \"$1 be\"",
		Suggest:     "$1 be",
		Category:    "Confused words",
		Explanation: "\"Be\" is the verb. A \"bee\" is the insect.",
	},
	{
		Pattern:     `\b([aA]|[tT]he|[hH]oney|[bB]umble|[qQ]ueen|[wW]orker|[sS]pelling)\s+be\b`,
		Flags:       []string{"I saw a be on the flower"},
		Leaves:      []string{"I saw a bee on the flower", "I want to be brave"},
		Message:     "Should be \"$1 bee\"",
		Suggest:     "$1 bee",
		Category:    "Confused words",
		Explanation: "A \"bee\" is the insect. \"Be\" is the verb.",
	},

	// --- sun / son ---
	{
		Pattern:     `\b([mM]y|[hH]is|[hH]er|[yY]our|[oO]ur|[tT]heir|[eE]ldest|[yY]oungest|[oO]nly)\s+sun\b`,
		Flags:       []string{"my sun loves football"},
		Leaves:      []string{"my son loves football", "sitting in the sun"},
		Message:     "Should be \"$1 son\"",
		Suggest:     "$1 son",
		Category:    "Confused words",
		Explanation: explainSunSon,
	},
	{
		Pattern:     `\b([iI]n\s+the|[hH]ot|[bB]right|[sS]etting|[rR]ising|[mM]idday|[bB]lazing|[wW]arm)\s+son\b`,
		Flags:       []string{"sitting in the son"},
		Leaves:      []string{"sitting in the sun", "my son loves football"},
		Message:     "Should be \"$1 sun\"",
		Suggest:     "$1 sun",
		Category:    "Confused words",
		Explanation: explainSunSon,
	},

	// --- night / knight ---
	{
		Pattern:     `\b([aA]t|[lL]ast|[tT]his|[eE]very|[tT]omorrow|[gG]ood|[aA]ll|[bB]y|[lL]ate\s+at|[oO]ne)\s+knight\b`,
		Flags:       []string{"we arrived at knight"},
		Leaves:      []string{"we arrived at night", "the knight rode away"},
		Message:     "Should be \"$1 night\"",
		Suggest:     "$1 night",
		Category:    "Confused words",
		Explanation: explainNightKnight,
	},
	{
		Pattern:     `\b([tT]he|[aA]|[bB]lack|[wW]hite|[bB]rave|[mM]edieval|[aA]rmoured|[aA]rmored|[nN]oble)\s+night\s+(rode|fought|drew|wore|carried|knelt|in\s+shining)\b`,
		Flags:       []string{"the night rode through the village"},
		Leaves:      []string{"the knight rode through the village", "we arrived at night"},
		Message:     "Should be \"$1 knight $2\"",
		Suggest:     "$1 knight $2",
		Category:    "Confused words",
		Explanation: explainNightKnight,
	},

	// --- flower / flour ---
	{
		Pattern:     `\b([bB]ag\s+of|[cC]up\s+of|[pP]lain|[sS]elf-raising|[wW]holemeal|[sS]ift|[sS]ifted|[pP]lain\s+white)\s+flower\b`,
		Flags:       []string{"a bag of flower"},
		Leaves:      []string{"a bag of flour", "the flower is growing"},
		Message:     "Should be \"$1 flour\"",
		Suggest:     "$1 flour",
		Category:    "Confused words",
		Explanation: explainFlowerFlour,
	},
	{
		Pattern:     `\b([tT]he|[aA]|[eE]ach|[pP]retty|[bB]eautiful|[wW]ild|[eE]very)\s+flour\s+(is|was|grew|grows|bloomed|blooms|in\s+the)\b`,
		Flags:       []string{"the flour is growing beside the shed"},
		Leaves:      []string{"the flower is growing beside the shed", "a bag of flour"},
		Message:     "Should be \"$1 flower $2\"",
		Suggest:     "$1 flower $2",
		Category:    "Confused words",
		Explanation: explainFlowerFlour,
	},

	// --- hour / our ---
	{
		Pattern:     `\b([aA]n|[eE]very|[hH]alf\s+an|[oO]ne|[tT]wo|[pP]er|[fF]or\s+an|[wW]ithin\s+the)\s+our\b`,
		Flags:       []string{"we waited for an our"},
		Leaves:      []string{"we waited for an hour", "outside our house"},
		Message:     "Should be \"$1 hour\"",
		Suggest:     "$1 hour",
		Category:    "Confused words",
		Explanation: "An \"hour\" is sixty minutes. \"Our\" means belonging to us.",
	},

	// --- ate / eight ---
	{
		Pattern:     `\b([aA]t|[nN]umber|[pP]age|[cC]hapter|[aA]ged|[aA]ll|[tT]op)\s+ate\b`,
		Flags:       []string{"we met at ate"},
		Leaves:      []string{"we met at eight", "she ate the cake"},
		Message:     "Should be \"$1 eight\"",
		Suggest:     "$1 eight",
		Category:    "Confused words",
		Explanation: "\"Eight\" is the number. \"Ate\" is the past tense of \"eat\".",
	},
	{
		Pattern:     `\b([iI]|[wW]e|[yY]ou|[tT]hey|[hH]e|[sS]he)\s+eight\s+(a|an|the|it|them|my|your|his|her|some|all|breakfast|lunch|dinner)\b`,
		Flags:       []string{"she eight the strawberries"},
		Leaves:      []string{"she ate the strawberries", "she ate eight strawberries"},
		Message:     "Should be \"$1 ate $2\"",
		Suggest:     "$1 ate $2",
		Category:    "Confused words",
		Explanation: "\"Ate\" is the past tense of \"eat\". \"Eight\" is the number.",
	},

	// --- bare / bear (the animal) ---
	{
		Pattern:     `\b([gG]rizzly|[pP]olar|[bB]rown|[bB]lack|[tT]eddy)\s+bare\b`,
		Flags:       []string{"a grizzly bare"},
		Leaves:      []string{"a grizzly bear", "the bare minimum"},
		Message:     "Should be \"$1 bear\"",
		Suggest:     "$1 bear",
		Category:    "Confused words",
		Explanation: "A \"bear\" is the animal. \"Bare\" means uncovered.",
	},

	// --- cell / sell ---
	{
		Pattern:     `\b([tT]o|[wW]ill|[cC]an|[cC]ould|[wW]ould|[mM]ust|[tT]rying\s+to|[wW]ants\s+to|[wW]ant\s+to)\s+cell\b`,
		Flags:       []string{"he wants to cell his old phone"},
		Leaves:      []string{"he wants to sell his old phone", "the cell battery is damaged"},
		Message:     "Should be \"$1 sell\"",
		Suggest:     "$1 sell",
		Category:    "Confused words",
		Explanation: explainCellSell,
	},
	{
		Pattern:     `\b([iI]ts|[hH]is|[hH]er|[mM]y|[yY]our|[pP]hone|[pP]rison|[jJ]ail|[bB]lood|[sS]tem|[sS]olar|[mM]emory)\s+sell\b`,
		Flags:       []string{"its sell battery is damaged", "a prison sell"},
		Leaves:      []string{"a prison cell", "he wants to sell it"},
		Message:     "Should be \"$1 cell\"",
		Suggest:     "$1 cell",
		Category:    "Confused words",
		Explanation: explainCellSell,
	},

	// --- fair / fare ---
	{
		Pattern:     `\b([bB]us|[tT]rain|[tT]axi|[aA]ir|[cC]ab|[fF]light|[tT]ram|[rR]eturn|[sS]ingle)\s+fair\b`,
		Flags:       []string{"the bus fair went up"},
		Leaves:      []string{"the bus fare went up", "that seems fair"},
		Message:     "Should be \"$1 fare\"",
		Suggest:     "$1 fare",
		Category:    "Confused words",
		Explanation: explainFairFare,
	},
	{
		Pattern:     `\b([iI]t's|[tT]hat's|[iI]s|[wW]as|[nN]ot|[hH]ardly|[sS]eems|[bB]e)\s+fare\b`,
		Flags:       []string{"the bus fare is fare"},
		Leaves:      []string{"the bus fare is fair"},
		Message:     "Should be \"$1 fair\"",
		Suggest:     "$1 fair",
		Category:    "Confused words",
		Explanation: explainFairFare,
	},

	// --- great / grate ---
	{
		Pattern:     `\b([aA]|[tT]he|[wW]hat\s+a|[sS]uch\s+a|[iI]t's|[tT]hat's|[hH]ow|[sS]o|[rR]eally)\s+grate\b`,
		Flags:       []string{"you did a grate job"},
		Leaves:      []string{"you did a great job", "the fireplace grate"},
		Message:     "Should be \"$1 great\"",
		Suggest:     "$1 great",
		Category:    "Confused words",
		Explanation: explainGreatGrate,
	},
	{
		Pattern:     `\b([oO]ven|[fF]ire|[fF]ireplace|[dD]rain|[iI]ron|[cC]heese)\s+great\b`,
		Flags:       []string{"cleaning the fireplace great"},
		Leaves:      []string{"cleaning the fireplace grate", "you did a great job"},
		Message:     "Should be \"$1 grate\"",
		Suggest:     "$1 grate",
		Category:    "Confused words",
		Explanation: explainGreatGrate,
	},

	// --- heal / heel ---
	{
		Pattern:     `\b([tT]o|[wW]ill|[cC]an|[cC]ould|[wW]ould|[eE]ventually|[hH]elp|[hH]elps|[sS]tart\s+to|[bB]egin\s+to)\s+heel\b`,
		Flags:       []string{"it will eventually heel"},
		Leaves:      []string{"it will eventually heal", "my injured heel"},
		Message:     "Should be \"$1 heal\"",
		Suggest:     "$1 heal",
		Category:    "Confused words",
		Explanation: explainHealHeel,
	},
	{
		Pattern:     `\b([mM]y|[hH]is|[hH]er|[yY]our|[tT]he|[iI]njured|[sS]ore|[lL]eft|[rR]ight|[aA]chilles)\s+heal\b`,
		Flags:       []string{"my injured heal hurts"},
		Leaves:      []string{"my injured heel hurts", "it will heal"},
		Message:     "Should be \"$1 heel\"",
		Suggest:     "$1 heel",
		Category:    "Confused words",
		Explanation: explainHealHeel,
	},

	// --- idle / idol ---
	{
		Pattern:     `\b([rR]emained|[sS]tood|[sS]at|[lL]ay|[wW]as|[wW]ere|[iI]s|[sS]itting|[rR]unning|[lL]eft)\s+idol\b`,
		Flags:       []string{"the machine remained idol"},
		Leaves:      []string{"the machine remained idle", "my childhood idol"},
		Message:     "Should be \"$1 idle\"",
		Suggest:     "$1 idle",
		Category:    "Confused words",
		Explanation: explainIdleIdol,
	},
	{
		Pattern:     `\b([mM]y|[hH]is|[hH]er|[yY]our|[oO]ur|[tT]heir|[pP]op|[tT]een|[cC]hildhood)\s+idle\b`,
		Flags:       []string{"the singer, my idle, performed"},
		Leaves:      []string{"the singer, my idol, performed", "the machine remained idle"},
		Message:     "Should be \"$1 idol\"",
		Suggest:     "$1 idol",
		Category:    "Confused words",
		Explanation: explainIdleIdol,
	},

	// --- mail / male ---
	{
		Pattern:     `\b([eE]lectronic|[sS]nail|[jJ]unk|[fF]an|[rR]oyal|[dD]elivered\s+the|[cC]heck\s+the|[oO]pen\s+the|[sS]ent\s+the)\s+male\b`,
		Flags:       []string{"the postman delivered the male"},
		Leaves:      []string{"the postman delivered the mail", "a male colleague"},
		Message:     "Should be \"$1 mail\"",
		Suggest:     "$1 mail",
		Category:    "Confused words",
		Explanation: explainMailMale,
	},
	{
		Pattern:     `\b([aA]|[tT]he|[yY]oung|[oO]lder|[aA]dult)\s+mail\s+(postman|nurse|doctor|colleague|friend|student|dog|cat|bird|voice|singer)\b`,
		Flags:       []string{"the mail postman arrived"},
		Leaves:      []string{"the male postman arrived", "check the mail"},
		Message:     "Should be \"$1 male $2\"",
		Suggest:     "$1 male $2",
		Category:    "Confused words",
		Explanation: explainMailMale,
	},

	// --- main / mane ---
	{
		Pattern:     `\b([lL]ion's|[hH]orse's|[fF]lowing|[tT]hick|[gG]olden|[sS]haggy)\s+main\b`,
		Flags:       []string{"the lion's main was visible"},
		Leaves:      []string{"the lion's mane was visible", "the main road"},
		Message:     "Should be \"$1 mane\"",
		Suggest:     "$1 mane",
		Category:    "Confused words",
		Explanation: explainMainMane,
	},
	{
		Pattern:     `\b([tT]he|[aA]|[oO]ur|[mM]y|[iI]ts)\s+mane\s+(road|reason|point|issue|problem|thing|course|street|entrance|goal|aim|character|event|difference)\b`,
		Flags:       []string{"visible from the mane road"},
		Leaves:      []string{"visible from the main road", "the lion's mane"},
		Message:     "Should be \"$1 main $2\"",
		Suggest:     "$1 main $2",
		Category:    "Confused words",
		Explanation: explainMainMane,
	},

	// --- pair / pear ---
	{
		Pattern:     `\b([aA]|[tT]he|[oO]ne|[eE]very|[aA]nother)\s+pear\s+of\b`,
		Flags:       []string{"I bought a pear of shoes"},
		Leaves:      []string{"I bought a pair of shoes", "I ate a pear"},
		Message:     "Should be \"$1 pair of\"",
		Suggest:     "$1 pair of",
		Category:    "Confused words",
		Explanation: explainPairPear,
	},
	{
		Pattern:     `\b([aA]te|[eE]at|[eE]ating|[rR]ipe|[jJ]uicy)\s+(a\s+)?pair\b`,
		Flags:       []string{"I ate a pair"},
		Leaves:      []string{"I ate a pear", "a pair of shoes"},
		Message:     "Should be \"$1 $2pear\"",
		Suggest:     "$1 $2pear",
		Category:    "Confused words",
		Explanation: explainPairPear,
	},

	// --- plain / plane ---
	{
		Pattern:     `\b([tT]he|[aA]|[bB]y|[oO]n\s+the|[cC]atch\s+the|[bB]oard\s+the)\s+plain\s+(flew|landed|took\s+off|crashed|departed|arrived|to|from)\b`,
		Flags:       []string{"the plain flew over the fields"},
		Leaves:      []string{"the plane flew over the fields", "the open plain"},
		Message:     "Should be \"$1 plane $2\"",
		Suggest:     "$1 plane $2",
		Category:    "Confused words",
		Explanation: explainPlainPlane,
	},
	{
		Pattern:     `\b([oO]pen|[vV]ast|[gG]rassy|[cC]oastal|[fF]lat|[wW]indswept)\s+plane\b`,
		Flags:       []string{"across the open plane"},
		Leaves:      []string{"across the open plain", "the plane landed"},
		Message:     "Should be \"$1 plain\"",
		Suggest:     "$1 plain",
		Category:    "Confused words",
		Explanation: explainPlainPlane,
	},
	{
		Pattern:     `\bplane\s+(English|text|sailing|clothes|flour|paper)\b`,
		Flags:       []string{"write it in plane English"},
		Leaves:      []string{"write it in plain English"},
		Message:     "Should be \"plain $1\"",
		Suggest:     "plain $1",
		Category:    "Confused words",
		Explanation: explainPlainPlane,
	},

	// --- principal / principle ---
	{
		Pattern:     `\b([tT]he|[aA]|[sS]chool|[cC]ollege|[dD]eputy|[vV]ice|[aA]ssistant)\s+principle\s+(said|explained|announced|met|called|is|was|has|will|of\s+the\s+school)\b`,
		Flags:       []string{"the school principle explained it"},
		Leaves:      []string{"the school principal explained it", "a guiding principle"},
		Message:     "Should be \"$1 principal $2\"",
		Suggest:     "$1 principal $2",
		Category:    "Confused words",
		Explanation: explainPrincipal,
	},
	{
		Pattern:     `\b([bB]asic|[gG]uiding|[fF]undamental|[mM]oral|[cC]ore|[fF]irst|[sS]ame|[gG]eneral|[uU]nderlying)\s+principal\b`,
		Flags:       []string{"a guiding principal"},
		Leaves:      []string{"a guiding principle", "the school principal"},
		Message:     "Should be \"$1 principle\"",
		Suggest:     "$1 principle",
		Category:    "Confused words",
		Explanation: explainPrincipal,
	},

	// --- rain / reign / rein ---
	{
		Pattern:     `\b([tT]he\s+king's|[tT]he\s+queen's|[dD]uring\s+the|[lL]ong|[sS]hort|[hH]is|[hH]er)\s+rain\b`,
		Flags:       []string{"during the king's rain"},
		Leaves:      []string{"during the king's reign", "heavy rain fell"},
		Message:     "Should be \"$1 reign\"",
		Suggest:     "$1 reign",
		Category:    "Confused words",
		Explanation: explainRainReign,
	},
	{
		Pattern:     `\b([hH]eavy|[lL]ight|[tT]orrential|[pP]ouring|[fF]reezing|[dD]riving)\s+reign\b`,
		Flags:       []string{"despite heavy reign"},
		Leaves:      []string{"despite heavy rain", "the king's reign"},
		Message:     "Should be \"$1 rain\"",
		Suggest:     "$1 rain",
		Category:    "Confused words",
		Explanation: explainRainReign,
	},
	{
		Pattern:     `\b[fF]ree\s+(reign|rain)\b`,
		Flags:       []string{"they gave him free reign"},
		Leaves:      []string{"they gave him free rein"},
		Message:     "Should be \"free rein\"",
		Suggest:     "free rein",
		Category:    "Confused words",
		Explanation: "\"Free rein\" comes from loosening a horse's reins, not from ruling or from weather.",
	},

	// --- road / rode ---
	{
		Pattern:     `\b([sS]he|[hH]e|[iI]|[wW]e|[tT]hey|[yY]ou)\s+road\s+(her|his|my|our|their|the|a|an|it|to|home|away|off|along|down|up)\b`,
		Flags:       []string{"she road her bicycle"},
		Leaves:      []string{"she rode her bicycle", "along the road"},
		Message:     "Should be \"$1 rode $2\"",
		Suggest:     "$1 rode $2",
		Category:    "Confused words",
		Explanation: explainRoadRode,
	},
	{
		Pattern:     `\b([tT]he|[aA]|[mM]ain|[nN]arrow|[wW]inding|[cC]ountry|[bB]usy|[aA]long\s+the|[dD]own\s+the)\s+rode\b`,
		Flags:       []string{"along the rode"},
		Leaves:      []string{"along the road", "she rode her bicycle"},
		Message:     "Should be \"$1 road\"",
		Suggest:     "$1 road",
		Category:    "Confused words",
		Explanation: explainRoadRode,
	},

	// --- role / roll ---
	{
		Pattern:     `\b([mM]ain|[lL]eading|[kK]ey|[cC]entral|[vV]ital|[cC]rucial|[sS]tarring|[sS]upporting|[mM]ajor)\s+roll\b`,
		Flags:       []string{"he played the main roll"},
		Leaves:      []string{"he played the main role", "a bread roll"},
		Message:     "Should be \"$1 role\"",
		Suggest:     "$1 role",
		Category:    "Confused words",
		Explanation: explainRoleRoll,
	},
	{
		Pattern:     `\b([bB]read|[sS]ausage|[dD]rum|[tT]oilet|[bB]acon|[cC]heese|[sS]pring)\s+role\b`,
		Flags:       []string{"he ate a bread role"},
		Leaves:      []string{"he ate a bread roll", "the main role"},
		Message:     "Should be \"$1 roll\"",
		Suggest:     "$1 roll",
		Category:    "Confused words",
		Explanation: explainRoleRoll,
	},

	// --- coarse / course ---
	{
		Pattern:     `\b([tT]he|[aA]|[tT]raining|[gG]olf|[cC]rash|[mM]ain|[fF]irst|[sS]econd|[oO]f]?)\s+coarse\b`,
		Flags:       []string{"the training coarse is excellent"},
		Leaves:      []string{"the training course is excellent", "the fabric is coarse"},
		Message:     "Should be \"$1 course\"",
		Suggest:     "$1 course",
		Category:    "Confused words",
		Explanation: explainCoarseCourse,
	},
	{
		Pattern:     `\b([iI]s|[wW]as|[fF]eels|[fF]elt|[vV]ery|[tT]oo|[qQ]uite|[rR]ather|[sS]o)\s+course\b`,
		Flags:       []string{"the fabric is course"},
		Leaves:      []string{"the fabric is coarse", "the training course"},
		Message:     "Should be \"$1 coarse\"",
		Suggest:     "$1 coarse",
		Category:    "Confused words",
		Explanation: explainCoarseCourse,
	},

	// --- cue / queue ---
	{
		Pattern:     `\b([iI]n\s+the|[jJ]oin\s+the|[jJ]oined\s+the|[wW]ait\s+in\s+the|[lL]ong|[tT]he\s+ticket)\s+cue\b`,
		Flags:       []string{"wait in the cue"},
		Leaves:      []string{"wait in the queue", "that was my cue"},
		Message:     "Should be \"$1 queue\"",
		Suggest:     "$1 queue",
		Category:    "Confused words",
		Explanation: explainCueQueue,
	},
	{
		Pattern:     `\b([tT]ake|[tT]ook|[tT]akes|[mM]iss|[mM]issed|[oO]n)\s+(his|her|my|your|their|the|that\s+as\s+a)\s+queue\b`,
		Flags:       []string{"he missed his queue"},
		Leaves:      []string{"he missed his cue", "wait in the queue"},
		Message:     "Should be \"$1 $2 cue\"",
		Suggest:     "$1 $2 cue",
		Category:    "Confused words",
		Explanation: explainCueQueue,
	},

	// --- currant / current ---
	{
		Pattern:     `\b([rR]iver|[oO]cean|[eE]lectric|[sS]trong|[sS]wift|[aA]ir|[tT]idal)\s+currant\b`,
		Flags:       []string{"the river currant carried the boat"},
		Leaves:      []string{"the river current carried the boat", "a currant bush"},
		Message:     "Should be \"$1 current\"",
		Suggest:     "$1 current",
		Category:    "Confused words",
		Explanation: explainCurrantCurrent,
	},
	{
		Pattern:     `\b([bB]lack|[rR]ed|[dD]ried|[aA]|[tT]he)\s+current\s+(bush|bushes|jam|jelly|bun|buns|cake|scone)\b`,
		Flags:       []string{"past a current bush"},
		Leaves:      []string{"past a currant bush", "the river current"},
		Message:     "Should be \"$1 currant $2\"",
		Suggest:     "$1 currant $2",
		Category:    "Confused words",
		Explanation: explainCurrantCurrent,
	},

	// --- dual / duel ---
	{
		Pattern:     `\bduel\s+(airbags|carriageway|purpose|citizenship|control|controls|screen|core|band|fuel|nationality|monitor)\b`,
		Flags:       []string{"the car has duel airbags"},
		Leaves:      []string{"the car has dual airbags", "the story describes a duel"},
		Message:     "Should be \"dual $1\"",
		Suggest:     "dual $1",
		Category:    "Confused words",
		Explanation: explainDualDuel,
	},
	{
		Pattern:     `\b([fF]ought\s+a|[tT]o\s+a|[iI]n\s+a|[pP]istol|[sS]word)\s+dual\b`,
		Flags:       []string{"they fought a dual"},
		Leaves:      []string{"they fought a duel", "dual carriageway"},
		Message:     "Should be \"$1 duel\"",
		Suggest:     "$1 duel",
		Category:    "Confused words",
		Explanation: explainDualDuel,
	},

	// --- foreword / forward ---
	{
		Pattern:     `\b([tT]he|[aA]|[wW]rote\s+a|[wW]riting\s+a|[iI]n\s+the|[hH]is|[hH]er)\s+forward\s+(to|of|by)\b`,
		Flags:       []string{"the author wrote a forward to the book"},
		Leaves:      []string{"the author wrote a foreword to the book", "look forward to it"},
		Message:     "Should be \"$1 foreword $2\"",
		Suggest:     "$1 foreword $2",
		Category:    "Confused words",
		Explanation: explainForewordForward,
	},
	{
		Pattern:     `\b([lL]ook|[lL]ooking|[lL]ooked|[mM]ove|[mM]oving|[sS]tep|[sS]tepped|[gG]o|[wW]ent|[cC]ome|[pP]ut|[bB]rought)\s+foreword\b`,
		Flags:       []string{"telling readers to look foreword"},
		Leaves:      []string{"telling readers to look forward", "wrote a foreword"},
		Message:     "Should be \"$1 forward\"",
		Suggest:     "$1 forward",
		Category:    "Confused words",
		Explanation: explainForewordForward,
	},

	// --- gait / gate ---
	{
		Pattern:     `\b([hH]is|[hH]er|[hH]orse's|[uU]nsteady|[aA]wkward|[nN]ormal|[sS]teady|[rR]olling)\s+gate\s+(changed|was|is|had|became|improved|suggested)\b`,
		Flags:       []string{"the horse's gate changed"},
		Leaves:      []string{"the horse's gait changed", "the garden gate"},
		Message:     "Should be \"$1 gait $2\"",
		Suggest:     "$1 gait $2",
		Category:    "Confused words",
		Explanation: explainGaitGate,
	},
	{
		Pattern:     `\b([tT]he|[aA]|[fF]ront|[bB]ack|[gG]arden|[iI]ron|[wW]ooden|[fF]arm|[dD]eparture|[bB]oarding)\s+gait\b`,
		Flags:       []string{"it reached the garden gait"},
		Leaves:      []string{"it reached the garden gate", "the horse's gait"},
		Message:     "Should be \"$1 gate\"",
		Suggest:     "$1 gate",
		Category:    "Confused words",
		Explanation: explainGaitGate,
	},

	// --- hoarse / horse ---
	{
		Pattern:     `\b([vV]oice|[tT]hroat)\s+(is|was|went|sounds|sounded|felt|got|getting)\s+horse\b`,
		Flags:       []string{"my voice is horse"},
		Leaves:      []string{"my voice is hoarse", "riding a horse"},
		Message:     "Should be \"$1 $2 hoarse\"",
		Suggest:     "$1 $2 hoarse",
		Category:    "Confused words",
		Explanation: explainHoarseHorse,
	},
	{
		Pattern:     `\b([rR]iding\s+a|[rR]ode\s+a|[oO]n\s+a|[wW]hite|[bB]lack|[wW]ild|[rR]acing|[dD]ark)\s+hoarse\b`,
		Flags:       []string{"after riding a hoarse"},
		Leaves:      []string{"after riding a horse", "my voice is hoarse"},
		Message:     "Should be \"$1 horse\"",
		Suggest:     "$1 horse",
		Category:    "Confused words",
		Explanation: explainHoarseHorse,
	},

	// --- miner / minor ---
	{
		Pattern:     `\b([aA]|[tT]he|[sS]uffered\s+a|[oO]nly\s+a|[jJ]ust\s+a)\s+miner\s+(injury|problem|issue|change|detail|setback|delay|role|point|adjustment|inconvenience|offence|offense)\b`,
		Flags:       []string{"he suffered a miner injury"},
		Leaves:      []string{"he suffered a minor injury", "the coal miner"},
		Message:     "Should be \"$1 minor $2\"",
		Suggest:     "$1 minor $2",
		Category:    "Confused words",
		Explanation: explainMinerMinor,
	},
	{
		Pattern:     `\b([tT]he|[aA]|[cC]oal|[gG]old|[tT]rapped)\s+minor\s+(was|were|dug|worked|died|escaped|suffered|climbed)\b`,
		Flags:       []string{"the coal minor was rescued"},
		Leaves:      []string{"the coal miner was rescued", "a minor injury"},
		Message:     "Should be \"$1 miner $2\"",
		Suggest:     "$1 miner $2",
		Category:    "Confused words",
		Explanation: explainMinerMinor,
	},

	// --- peak / peek ---
	{
		Pattern:     `\b([tT]he|[aA]|[mM]ountain's|[hH]ighest|[rR]eached\s+the|[sS]ummit)\s+peek\b`,
		Flags:       []string{"we reached the mountain's peek"},
		Leaves:      []string{"we reached the mountain's peak", "a quick peek"},
		Message:     "Should be \"$1 peak\"",
		Suggest:     "$1 peak",
		Category:    "Confused words",
		Explanation: explainPeakPeek,
	},
	{
		Pattern:     `\b([aA]|[qQ]uick|[lL]ittle|[cC]heeky|[tT]ake\s+a|[hH]ad\s+a|[tT]ook\s+a)\s+peak\s+(at|below|inside|behind|under|around)\b`,
		Flags:       []string{"took a quick peak below"},
		Leaves:      []string{"took a quick peek below", "the mountain's peak"},
		Message:     "Should be \"$1 peek $2\"",
		Suggest:     "$1 peek $2",
		Category:    "Confused words",
		Explanation: explainPeakPeek,
	},

	// --- pedal / peddle ---
	{
		Pattern:     `\b([tT]he|[aA]|[bB]rake|[gG]as|[cC]lutch|[bB]ike|[uU]sed\s+the|[pP]ress\s+the|[pP]ushed\s+the)\s+peddle\b`,
		Flags:       []string{"he used the peddle to cycle"},
		Leaves:      []string{"he used the pedal to cycle", "trying to peddle his products"},
		Message:     "Should be \"$1 pedal\"",
		Suggest:     "$1 pedal",
		Category:    "Confused words",
		Explanation: explainPedalPeddle,
	},
	{
		Pattern:     `\b([tT]o|[tT]rying\s+to|[wW]ill|[cC]an|[cC]ould|[wW]ould)\s+pedal\s+(his|her|my|your|their|the)\s+(products|goods|wares|drugs|stuff|services)\b`,
		Flags:       []string{"trying to pedal his products"},
		Leaves:      []string{"trying to peddle his products", "used the pedal"},
		Message:     "Should be \"$1 peddle $2 $3\"",
		Suggest:     "$1 peddle $2 $3",
		Category:    "Confused words",
		Explanation: explainPedalPeddle,
	},

	// --- pray / prey ---
	{
		Pattern:     `\b([tT]o|[wW]ill|[cC]an|[lL]et\s+us|[lL]et's|[wW]e|[tT]hey|[pP]eople)\s+prey\s+(for|to|that)\b`,
		Flags:       []string{"the people prey to God"},
		Leaves:      []string{"the people pray to God", "the animals hunt their prey"},
		Message:     "Should be \"$1 pray $2\"",
		Suggest:     "$1 pray $2",
		Category:    "Confused words",
		Explanation: explainPrayPrey,
	},
	{
		Pattern:     `\b([tT]heir|[iI]ts|[hH]is|[eE]asy|[fF]air|[hH]unt|[hH]unting|[hH]unts)\s+pray\b`,
		Flags:       []string{"the animals hunt their pray"},
		Leaves:      []string{"the animals hunt their prey", "the people pray"},
		Message:     "Should be \"$1 prey\"",
		Suggest:     "$1 prey",
		Category:    "Confused words",
		Explanation: explainPrayPrey,
	},

	// --- real / reel ---
	{
		Pattern:     `\b([iI]s|[wW]as|[aA]re|[wW]ere|[sS]eems|[fF]eels|[nN]ot|[vV]ery|[qQ]uite)\s+reel\b`,
		Flags:       []string{"the story is reel"},
		Leaves:      []string{"the story is real", "a fishing reel"},
		Message:     "Should be \"$1 real\"",
		Suggest:     "$1 real",
		Category:    "Confused words",
		Explanation: explainRealReel,
	},
	{
		Pattern:     `\b([aA]|[tT]he|[fF]ishing|[tT]ape|[cC]otton)\s+real\b`,
		Flags:       []string{"the line is on a fishing real"},
		Leaves:      []string{"the line is on a fishing reel", "the story is real"},
		Message:     "Should be \"$1 reel\"",
		Suggest:     "$1 reel",
		Category:    "Confused words",
		Explanation: explainRealReel,
	},

	// --- root / route ---
	{
		Pattern:     `\b([tT]he|[aA]|[tT]ree's|[pP]lant's|[dD]eep|[tT]ap)\s+route\s+(grew|grows|system|spread|took\s+hold|of\s+the\s+tree)\b`,
		Flags:       []string{"the tree's route grew across the path"},
		Leaves:      []string{"the tree's root grew across the path", "our chosen route"},
		Message:     "Should be \"$1 root $2\"",
		Suggest:     "$1 root $2",
		Category:    "Confused words",
		Explanation: explainRootRoute,
	},
	{
		Pattern:     `\b([cC]hosen|[sS]cenic|[dD]irect|[qQ]uickest|[bB]est|[aA]lternative|[bB]us|[cC]ycle|[eE]scape)\s+root\b`,
		Flags:       []string{"our chosen root"},
		Leaves:      []string{"our chosen route", "the tree's root"},
		Message:     "Should be \"$1 route\"",
		Suggest:     "$1 route",
		Category:    "Confused words",
		Explanation: explainRootRoute,
	},

	// --- shear / sheer ---
	{
		Pattern:     `\b([tT]o|[wW]ill|[cC]an|[fF]armers|[fF]armer|[wW]e|[tT]hey)\s+sheer\s+(the\s+)?(sheep|wool|hedge)\b`,
		Flags:       []string{"farmers sheer sheep"},
		Leaves:      []string{"farmers shear sheep", "the sheer scale of it"},
		Message:     "Should be \"$1 shear $2$3\"",
		Suggest:     "$1 shear $2$3",
		Category:    "Confused words",
		Explanation: explainShearSheer,
	},
	{
		Pattern:     `\b([tT]he|[bB]y|[iI]n|[oO]f)\s+shear\s+(luck|force|number|numbers|size|scale|volume|joy|terror|determination|will|weight)\b`,
		Flags:       []string{"by shear luck"},
		Leaves:      []string{"by sheer luck", "farmers shear sheep"},
		Message:     "Should be \"$1 sheer $2\"",
		Suggest:     "$1 sheer $2",
		Category:    "Confused words",
		Explanation: explainShearSheer,
	},

	// --- site / sight / cite ---
	{
		Pattern:     `\b([bB]uilding|[cC]onstruction|[wW]eb|[nN]ews|[hH]istoric|[bB]urial|[oO]n|[oO]ff)\s+sight\b`,
		Flags:       []string{"we visited the building sight"},
		Leaves:      []string{"we visited the building site", "an amazing sight"},
		Message:     "Should be \"$1 site\"",
		Suggest:     "$1 site",
		Category:    "Confused words",
		Explanation: explainSiteSight,
	},
	{
		Pattern:     `\b([aA]n?|[tT]he|[aA]mazing|[bB]eautiful|[wW]onderful|[tT]errible|[oO]ut\s+of)\s+cite\b`,
		Flags:       []string{"an amazing cite"},
		Leaves:      []string{"an amazing sight", "how to cite sources"},
		Message:     "Should be \"$1 sight\"",
		Suggest:     "$1 sight",
		Category:    "Confused words",
		Explanation: explainSiteSight,
	},
	{
		Pattern:     `\b([tT]o|[hH]ow\s+to|[wW]ill|[cC]an|[mM]ust|[sS]hould|[pP]lease)\s+(site|sight)\s+(sources|references|evidence|examples|a\s+source|a\s+study|the\s+paper)\b`,
		Flags:       []string{"learned how to site sources"},
		Leaves:      []string{"learned how to cite sources"},
		Message:     "Should be \"$1 cite $3\"",
		Suggest:     "$1 cite $3",
		Category:    "Confused words",
		Explanation: explainSiteSight,
	},

	// --- suite / sweet ---
	{
		Pattern:     `\b([hH]otel|[bB]ridal|[hH]oneymoon|[eE]xecutive|[mM]aster|[eE]n-suite|[pP]enthouse)\s+sweet\b`,
		Flags:       []string{"we booked a hotel sweet"},
		Leaves:      []string{"we booked a hotel suite", "a sweet dessert"},
		Message:     "Should be \"$1 suite\"",
		Suggest:     "$1 suite",
		Category:    "Confused words",
		Explanation: explainSuiteSweet,
	},
	{
		Pattern:     `\b([aA]|[tT]he|[sS]o|[vV]ery|[hH]ow|[sS]uch\s+a)\s+suite\s+(dessert|treat|smile|thing|taste|tooth|dreams|potato)\b`,
		Flags:       []string{"ordered a suite dessert"},
		Leaves:      []string{"ordered a sweet dessert", "a hotel suite"},
		Message:     "Should be \"$1 sweet $2\"",
		Suggest:     "$1 sweet $2",
		Category:    "Confused words",
		Explanation: explainSuiteSweet,
	},

	// --- team / teem ---
	{
		Pattern:     `\b([tT]he|[aA]|[oO]ur|[mM]y|[yY]our|[hH]is|[hH]er|[tT]heir|[wW]hole|[eE]ntire|[fF]ootball|[sS]ales)\s+teem\b`,
		Flags:       []string{"the teem worked hard"},
		Leaves:      []string{"the team worked hard", "the river began to teem with fish"},
		Message:     "Should be \"$1 team\"",
		Suggest:     "$1 team",
		Category:    "Confused words",
		Explanation: explainTeamTeem,
	},
	{
		Pattern:     `\b([bB]egan\s+to|[sS]tart\s+to|[sS]tarted\s+to|[tT]o|[wW]ill|[wW]ould|[sS]eemed\s+to)\s+team\s+with\s+(fish|life|people|insects|activity|ideas|tourists)\b`,
		Flags:       []string{"the river began to team with fish"},
		Leaves:      []string{"the river began to teem with fish", "the team worked hard"},
		Message:     "Should be \"$1 teem with $3\"",
		Suggest:     "$1 teem with $2",
		Category:    "Confused words",
		Explanation: explainTeamTeem,
	},

	// --- waive / wave ---
	{
		Pattern:     `\b([tT]o|[wW]ill|[cC]an|[cC]ould|[wW]ould|[aA]greed\s+to|[dD]ecided\s+to|[mM]ay)\s+wave\s+(the|a|any|all|his|her|their|your|my)\s+(fee|fees|charge|charges|requirement|requirements|right|rights|penalty|deposit|deadline)\b`,
		Flags:       []string{"the company agreed to wave the fee"},
		Leaves:      []string{"the company agreed to waive the fee", "I gave them a wave"},
		Message:     "Should be \"$1 waive $2 $3\"",
		Suggest:     "$1 waive $2 $3",
		Category:    "Confused words",
		Explanation: explainWaiveWave,
	},
	{
		Pattern:     `\b([aA]|[tT]he|[wW]ith\s+a|[bB]ig|[lL]ittle|[fF]riendly)\s+waive\b`,
		Flags:       []string{"I gave them a waive goodbye"},
		Leaves:      []string{"I gave them a wave goodbye", "agreed to waive the fee"},
		Message:     "Should be \"$1 wave\"",
		Suggest:     "$1 wave",
		Category:    "Confused words",
		Explanation: explainWaiveWave,
	},

	// --- yore / your ---
	{
		Pattern:     `\b([dD]ays|[tT]imes|[yY]ears)\s+of\s+your\b`,
		Flags:       []string{"in days of your"},
		Leaves:      []string{"in days of yore"},
		Message:     "Should be \"$1 of yore\"",
		Suggest:     "$1 of yore",
		Category:    "Confused words",
		Explanation: "\"Yore\" means long ago. \"Your\" means belonging to you.",
	},
	{
		Pattern:     `\b[yY]ore\s+(family|friend|friends|house|car|name|money|time|work|help|book|phone|order|account)\b`,
		Flags:       []string{"protected yore family"},
		Leaves:      []string{"protected your family", "in days of yore"},
		Message:     "Should be \"your $1\"",
		Suggest:     "your $1",
		Category:    "Confused words",
		Explanation: "\"Your\" means belonging to you. \"Yore\" means long ago.",
	},

	// --- beach / beech ---
	{
		Pattern:     `\b([oO]n\s+the|[aA]long\s+the|[sS]andy|[pP]ebble|[cC]rowded)\s+beech\b`,
		Flags:       []string{"we walked along the beech"},
		Leaves:      []string{"we walked along the beach", "a beech tree"},
		Message:     "Should be \"$1 beach\"",
		Suggest:     "$1 beach",
		Category:    "Confused words",
		Explanation: explainBeachBeech,
	},
	{
		Pattern:     `\b([aA]|[tT]he|[tT]all|[oO]ld|[cC]opper|[mM]ature)\s+beach\s+(tree|trees|wood|hedge|leaves)\b`,
		Flags:       []string{"we saw a beach tree"},
		Leaves:      []string{"we saw a beech tree", "along the beach"},
		Message:     "Should be \"$1 beech $2\"",
		Suggest:     "$1 beech $2",
		Category:    "Confused words",
		Explanation: explainBeachBeech,
	},

	// --- claws / clause ---
	{
		Pattern:     `\b([sS]harp|[iI]ts|[hH]is|[lL]ong|[cC]urved|[rR]etractable)\s+clause\b`,
		Flags:       []string{"the cat has sharp clause"},
		Leaves:      []string{"the cat has sharp claws", "an important clause"},
		Message:     "Should be \"$1 claws\"",
		Suggest:     "$1 claws",
		Category:    "Confused words",
		Explanation: explainClawsClause,
	},
	{
		Pattern:     `\b([aA]n?|[tT]he|[iI]mportant|[cC]ontract|[eE]scape|[pP]enalty|[sS]pecific|[aA]dditional|[rR]elevant)\s+claws\b`,
		Flags:       []string{"the contract contains an important claws"},
		Leaves:      []string{"the contract contains an important clause", "sharp claws"},
		Message:     "Should be \"$1 clause\"",
		Suggest:     "$1 clause",
		Category:    "Confused words",
		Explanation: explainClawsClause,
	},

	// --- earn / urn ---
	{
		Pattern:     `\b([tT]o|[wW]ill|[cC]an|[cC]ould|[wW]ould|[hH]ope\s+to|[hH]opes\s+to|[wW]ant\s+to|[tT]rying\s+to)\s+urn\b`,
		Flags:       []string{"I hope to urn enough money"},
		Leaves:      []string{"I hope to earn enough money", "buy an urn"},
		Message:     "Should be \"$1 earn\"",
		Suggest:     "$1 earn",
		Category:    "Confused words",
		Explanation: explainEarnUrn,
	},
	{
		Pattern:     `\b([aA]n|[tT]he|[bB]urial|[fF]uneral|[tT]ea|[aA]ncient|[bB]ronze|[cC]remation)\s+earn\b`,
		Flags:       []string{"buy an earn"},
		Leaves:      []string{"buy an urn", "hope to earn money"},
		Message:     "Should be \"$1 urn\"",
		Suggest:     "$1 urn",
		Category:    "Confused words",
		Explanation: explainEarnUrn,
	},

	// --- guilt / gilt ---
	{
		Pattern:     `\b([fF]elt|[fF]eel|[fF]eeling|[oO]verwhelming|[sS]ense\s+of|[nN]o|[wW]ith)\s+gilt\b`,
		Flags:       []string{"he felt gilt afterwards"},
		Leaves:      []string{"he felt guilt afterwards", "the gilt frame"},
		Message:     "Should be \"$1 guilt\"",
		Suggest:     "$1 guilt",
		Category:    "Confused words",
		Explanation: explainGuiltGilt,
	},
	{
		Pattern:     `\b([tT]he|[aA]|[oO]rnate|[gG]olden|[aA]ntique)\s+guilt\s+(frame|frames|edge|edges|mirror|lettering|trim)\b`,
		Flags:       []string{"damaging the guilt frame"},
		Leaves:      []string{"damaging the gilt frame", "he felt guilt"},
		Message:     "Should be \"$1 gilt $2\"",
		Suggest:     "$1 gilt $2",
		Category:    "Confused words",
		Explanation: explainGuiltGilt,
	},

	// --- hair / hare ---
	{
		Pattern:     `\b([mM]y|[hH]is|[hH]er|[yY]our|[lL]ong|[sS]hort|[dD]ark|[bB]londe|[gG]rey|[gG]ray|[tT]hick|[wW]ashed\s+my)\s+hare\b`,
		Flags:       []string{"she has thick hare"},
		Leaves:      []string{"she has thick hair", "the hare ran off"},
		Message:     "Should be \"$1 hair\"",
		Suggest:     "$1 hair",
		Category:    "Confused words",
		Explanation: explainHairHare,
	},
	{
		Pattern:     `\b([aA]|[tT]he|[wW]ild|[bB]rown|[mM]arch|[sS]tartled)\s+hair\s+(ran|hopped|leapt|bounded|darted)\b`,
		Flags:       []string{"the hair ran across the field"},
		Leaves:      []string{"the hare ran across the field", "thick hair"},
		Message:     "Should be \"$1 hare $2\"",
		Suggest:     "$1 hare $2",
		Category:    "Confused words",
		Explanation: explainHairHare,
	},

	// --- hall / haul ---
	{
		Pattern:     `\b([tT]he|[aA]|[eE]ntrance|[cC]ity|[tT]own|[dD]ining|[cC]oncert|[mM]usic|[vV]illage|[dD]own\s+the|[tT]hrough\s+the)\s+haul\b`,
		Flags:       []string{"carried it through the haul"},
		Leaves:      []string{"carried it through the hall", "a large haul"},
		Message:     "Should be \"$1 hall\"",
		Suggest:     "$1 hall",
		Category:    "Confused words",
		Explanation: explainHallHaul,
	},
	{
		Pattern:     `\b([lL]ong|[sS]hort)\s+hall\b`,
		Flags:       []string{"it is a long hall to the coast"},
		Leaves:      []string{"it is a long haul to the coast", "through the hall"},
		Message:     "Should be \"$1 haul\"",
		Suggest:     "$1 haul",
		Category:    "Confused words",
		Explanation: explainHallHaul,
	},

	// --- him / hymn ---
	{
		Pattern:     `\b([tT]o|[fF]or|[wW]ith|[gG]ave|[gG]ive|[tT]old|[tT]ell|[sS]aw|[aA]sked|[aA]sk)\s+hymn\b`,
		Flags:       []string{"I gave the book to hymn"},
		Leaves:      []string{"I gave the book to him", "singing a hymn"},
		Message:     "Should be \"$1 him\"",
		Suggest:     "$1 him",
		Category:    "Confused words",
		Explanation: explainHimHymn,
	},
	{
		Pattern:     `\b([sS]inging\s+a|[sS]ang\s+a|[fF]avourite|[fF]avorite|[oO]pening|[cC]losing)\s+him\b`,
		Flags:       []string{"after singing a him"},
		Leaves:      []string{"after singing a hymn", "gave it to him"},
		Message:     "Should be \"$1 hymn\"",
		Suggest:     "$1 hymn",
		Category:    "Confused words",
		Explanation: explainHimHymn,
	},

	// --- leak / leek ---
	{
		Pattern:     `\b([wW]ater|[gG]as|[oO]il|[fF]uel|[sS]prung\s+a|[hH]as\s+a|[sS]low)\s+leek\b`,
		Flags:       []string{"the pipe has a leek"},
		Leaves:      []string{"the pipe has a leak", "I added a leek to the soup"},
		Message:     "Should be \"$1 leak\"",
		Suggest:     "$1 leak",
		Category:    "Confused words",
		Explanation: explainLeakLeek,
	},
	{
		Pattern:     `\b([pP]otato\s+and|[cC]hopped|[sS]liced|[bB]raised)\s+leak\b`,
		Flags:       []string{"chopped leak in the soup"},
		Leaves:      []string{"chopped leek in the soup", "the pipe has a leak"},
		Message:     "Should be \"$1 leek\"",
		Suggest:     "$1 leek",
		Category:    "Confused words",
		Explanation: explainLeakLeek,
	},

	// --- made / maid ---
	{
		Pattern:     `\b([tT]he|[aA]|[oO]ur|[hH]is|[hH]er|[yY]oung|[hH]otel|[fF]rench)\s+made\s+(cleaned|cleans|arrived|comes|came|will|has|had|was|is)\b`,
		Flags:       []string{"the made cleaned the room"},
		Leaves:      []string{"the maid cleaned the room", "the meal I had made"},
		Message:     "Should be \"$1 maid $2\"",
		Suggest:     "$1 maid $2",
		Category:    "Confused words",
		Explanation: explainMadeMaid,
	},
	{
		Pattern:     `\b([hH]ad|[hH]ave|[hH]as|[wW]as|[wW]ere|[iI]s|[aA]re|[hH]and)\s+maid\b`,
		Flags:       []string{"the meal I had maid"},
		Leaves:      []string{"the meal I had made", "the maid cleaned it"},
		Message:     "Should be \"$1 made\"",
		Suggest:     "$1 made",
		Category:    "Confused words",
		Explanation: explainMadeMaid,
	},

	// --- oar / or / ore ---
	{
		Pattern:     `\b([aA]n|[tT]he|[wW]ooden|[bB]roken|[uU]se\s+an|[wW]ith\s+an)\s+ore\b`,
		Flags:       []string{"would you like to use an ore"},
		Leaves:      []string{"would you like to use an oar", "search for ore"},
		Message:     "Should be \"$1 oar\"",
		Suggest:     "$1 oar",
		Category:    "Confused words",
		Explanation: explainOarOre,
	},
	{
		Pattern:     `\b([iI]ron|[gG]old|[cC]opper|[rR]aw|[mM]ineral|[sS]ilver)\s+oar\b`,
		Flags:       []string{"they mined iron oar"},
		Leaves:      []string{"they mined iron ore", "use an oar"},
		Message:     "Should be \"$1 ore\"",
		Suggest:     "$1 ore",
		Category:    "Confused words",
		Explanation: explainOarOre,
	},

	// --- pail / pale ---
	{
		Pattern:     `\b([wW]ent|[tT]urned|[lL]ooked|[lL]ooks|[lL]ooking|[gG]oing|[sS]o|[vV]ery|[qQ]uite|[dD]eathly)\s+pail\b`,
		Flags:       []string{"her face went pail"},
		Leaves:      []string{"her face went pale", "she dropped the pail"},
		Message:     "Should be \"$1 pale\"",
		Suggest:     "$1 pale",
		Category:    "Confused words",
		Explanation: explainPailPale,
	},
	{
		Pattern:     `\b([aA]|[tT]he|[oO]ne|[wW]ater|[mM]ilk)\s+pale\s+of\b`,
		Flags:       []string{"a pale of water"},
		Leaves:      []string{"a pail of water", "her face went pale"},
		Message:     "Should be \"$1 pail of\"",
		Suggest:     "$1 pail of",
		Category:    "Confused words",
		Explanation: explainPailPale,
	},

	// --- peal / peel ---
	{
		Pattern:     `\b([tT]he|[aA]|[hH]eard\s+the|[lL]oud)\s+peel\s+of\s+(bells|thunder|laughter)\b`,
		Flags:       []string{"we heard the peel of bells"},
		Leaves:      []string{"we heard the peal of bells", "peel an orange"},
		Message:     "Should be \"$1 peal of $2\"",
		Suggest:     "$1 peal of $2",
		Category:    "Confused words",
		Explanation: explainPealPeel,
	},
	{
		Pattern:     `\b([tT]o|[wW]ill|[cC]an|[pP]lease|[hH]elp\s+me)\s+peal\s+(the|a|an|some|potatoes)\b`,
		Flags:       []string{"I will peal an orange"},
		Leaves:      []string{"I will peel an orange", "the peal of bells"},
		Message:     "Should be \"$1 peel $2\"",
		Suggest:     "$1 peel $2",
		Category:    "Confused words",
		Explanation: explainPealPeel,
	},

	// --- rest / wrest ---
	{
		Pattern:     `\b([nN]eed|[nN]eeded|[wW]ant|[wW]anted)\s+to\s+wrest\b`,
		Flags:       []string{"I need to wrest after this"},
		Leaves:      []string{"I need to rest after this", "trying to wrest the door open"},
		Message:     "Should be \"$1 to rest\"",
		Suggest:     "$1 to rest",
		Category:    "Confused words",
		Explanation: explainRestWrest,
	},
	{
		Pattern:     `\b([tT]o|[tT]rying\s+to|[tT]ried\s+to|[wW]ill|[cC]ould)\s+rest\s+(control|power|it\s+from|them\s+from|the\s+door\s+open)\b`,
		Flags:       []string{"trying to rest control from them"},
		Leaves:      []string{"trying to wrest control from them", "I need to rest"},
		Message:     "Should be \"$1 wrest $2\"",
		Suggest:     "$1 wrest $2",
		Category:    "Confused words",
		Explanation: explainRestWrest,
	},

	// --- tense / tents ---
	{
		Pattern:     `\b([bB]ecame|[bB]ecome|[gG]ot|[wW]as|[iI]s|[fF]elt|[sS]eemed|[vV]ery|[sS]o|[qQ]uite)\s+tents\b`,
		Flags:       []string{"the situation became tents"},
		Leaves:      []string{"the situation became tense", "we put up the tents"},
		Message:     "Should be \"$1 tense\"",
		Suggest:     "$1 tense",
		Category:    "Confused words",
		Explanation: explainTenseTents,
	},
	{
		Pattern:     `\b([pP]ut\s+up\s+the|[pP]itched\s+the|[pP]itch\s+the|[tT]wo|[tT]hree|[oO]ur|[cC]amping)\s+tense\b`,
		Flags:       []string{"we put up the tense"},
		Leaves:      []string{"we put up the tents", "the situation became tense"},
		Message:     "Should be \"$1 tents\"",
		Suggest:     "$1 tents",
		Category:    "Confused words",
		Explanation: explainTenseTents,
	},

	// --- tide / tied ---
	{
		Pattern:     `\b([wW]as|[wW]ere|[iI]s|[aA]re|[bB]een|[gG]ot|[hH]ad|[hH]ave)\s+tide\s+(to|up|down|together|back)\b`,
		Flags:       []string{"the boat was tide to the dock"},
		Leaves:      []string{"the boat was tied to the dock", "the tide came in"},
		Message:     "Should be \"$1 tied $2\"",
		Suggest:     "$1 tied $2",
		Category:    "Confused words",
		Explanation: explainTideTied,
	},
	{
		Pattern:     `\b([tT]he|[hH]igh|[lL]ow|[rR]ising|[fF]alling|[iI]ncoming|[oO]utgoing)\s+tied\b`,
		Flags:       []string{"the tied came in"},
		Leaves:      []string{"the tide came in", "the boat was tied up"},
		Message:     "Should be \"$1 tide\"",
		Suggest:     "$1 tide",
		Category:    "Confused words",
		Explanation: explainTideTied,
	},

	// --- vane / vain / vein ---
	{
		Pattern:     `\b([wW]eather|[wW]ind)\s+(vain|vein)\b`,
		Flags:       []string{"watching the weather vain"},
		Leaves:      []string{"watching the weather vane"},
		Message:     "Should be \"$1 vane\"",
		Suggest:     "$1 vane",
		Category:    "Confused words",
		Explanation: "A \"vane\" is the rotating indicator on a roof. \"Vain\" means conceited and a \"vein\" carries blood.",
	},

	// --- whole / hole ---
	{
		Pattern:     `\b([tT]he|[aA]|[oO]ne)\s+hole\s+(wall|house|team|thing|world|family|point|day|week|month|year|time|lot|story|place|lot\s+of)\b`,
		Flags:       []string{"the hole wall came down"},
		Leaves:      []string{"the whole wall came down", "a hole in the wall"},
		Message:     "Should be \"$1 whole $2\"",
		Suggest:     "$1 whole $2",
		Category:    "Confused words",
		Explanation: "\"Whole\" means complete. A \"hole\" is an opening.",
	},

	// --- clothes / cloths ---
	{
		Pattern:     `\b([mM]y|[hH]is|[hH]er|[yY]our|[oO]ur|[tT]heir|[wW]earing|[wW]ear|[wW]ashed\s+my|[cC]hange\s+my)\s+cloths\b`,
		Flags:       []string{"I washed my cloths"},
		Leaves:      []string{"I washed my clothes", "several cleaning cloths"},
		Message:     "Should be \"$1 clothes\"",
		Suggest:     "$1 clothes",
		Category:    "Confused words",
		Explanation: explainClothesCloths,
	},
	{
		Pattern:     `\b([cC]leaning|[dD]usting|[dD]ish|[kK]itchen|[dD]amp|[wW]et|[mM]icrofibre|[mM]icrofiber)\s+clothes\b`,
		Flags:       []string{"several cleaning clothes"},
		Leaves:      []string{"several cleaning cloths", "I washed my clothes"},
		Message:     "Should be \"$1 cloths\"",
		Suggest:     "$1 cloths",
		Category:    "Confused words",
		Explanation: explainClothesCloths,
	},

	// --- imminent / eminent ---
	{
		Pattern:     `\b([aA]n|[tT]he|[mM]ost|[vV]ery)\s+imminent\s+(scientist|professor|lawyer|judge|historian|author|figure|person|academic|surgeon|physician|economist)\b`,
		Flags:       []string{"an imminent scientist warned us"},
		Leaves:      []string{"an eminent scientist warned us", "the danger was imminent"},
		Message:     "Should be \"$1 eminent $2\"",
		Suggest:     "$1 eminent $2",
		Category:    "Confused words",
		Explanation: explainImminentEminent,
	},
	{
		Pattern:     `\b([dD]anger|[tT]hreat|[rR]isk|[aA]ttack|[cC]ollapse|[aA]rrival|[dD]eparture|[sS]torm|[dD]eath)\s+(was|is|were|are|seemed|seems)\s+eminent\b`,
		Flags:       []string{"the danger was eminent"},
		Leaves:      []string{"the danger was imminent", "an eminent scientist"},
		Message:     "Should be \"$1 $2 imminent\"",
		Suggest:     "$1 $2 imminent",
		Category:    "Confused words",
		Explanation: explainImminentEminent,
	},

	// --- incite / insight ---
	{
		Pattern:     `\b([gG]ave|[gG]ives|[gG]iving|[pP]rovided|[pP]rovide|[vV]aluable|[gG]reat|[dD]eep|[nN]ew|[sS]ome|[mM]ore)\s+((?:us|me|him|her|them|you)\s+)?incite\b`,
		Flags:       []string{"her speech gave us incite"},
		Leaves:      []string{"her speech gave us insight", "did not incite violence"},
		Message:     "Should be \"$1 $2insight\"",
		Suggest:     "$1 $2insight",
		Category:    "Confused words",
		Explanation: explainInciteInsight,
	},
	{
		Pattern:     `\b([tT]o|[wW]ill|[cC]ould|[wW]ould|[dD]idn't|[nN]ot)\s+insight\s+(violence|hatred|riots|rebellion|unrest|anger|panic|a\s+riot)\b`,
		Flags:       []string{"did not insight violence"},
		Leaves:      []string{"did not incite violence", "gave us insight"},
		Message:     "Should be \"$1 incite $2\"",
		Suggest:     "$1 incite $2",
		Category:    "Confused words",
		Explanation: explainInciteInsight,
	},

	// --- guise / guys ---
	{
		Pattern:     `\b([iI]n\s+the|[uU]nder\s+the|[tT]he)\s+guys\s+of\b`,
		Flags:       []string{"they arrived in the guys of tourists"},
		Leaves:      []string{"they arrived in the guise of tourists"},
		Message:     "Should be \"$1 guise of\"",
		Suggest:     "$1 guise of",
		Category:    "Confused words",
		Explanation: "A \"guise\" is an outward appearance. \"Guys\" are people.",
	},

	// --- capital / capitol ---
	{
		Pattern:     `\b[cC]apitol\s+of\s+the\s+(UK|United\s+Kingdom|US|USA|United\s+States|world|country|region|nation)\b`,
		Flags:       []string{"London is the capitol of the UK"},
		Leaves:      []string{"London is the capital of the UK"},
		Message:     "Should be \"capital of the $1\"",
		Suggest:     "capital of the $1",
		Category:    "Confused words",
		Explanation: "A \"capital\" is the chief city. The \"Capitol\" is a specific building in the United States.",
	},

	// --- muscle / mussel ---
	{
		Pattern:     `\b([sS]trengthens|[sS]trengthen|[bB]uild|[bB]uilding|[sS]ore|[pP]ulled|[tT]orn|[sS]trained|[fF]lex|[fF]lexed)\s+(your|his|her|my|our|their|the)?\s*mussels?\b`,
		Flags:       []string{"exercise strengthens your mussels"},
		Leaves:      []string{"exercise strengthens your muscles", "a mussel is seafood"},
		Message:     "Should be \"$1 $2muscles\"",
		Suggest:     "$1 $2muscles",
		Category:    "Confused words",
		Explanation: "A \"muscle\" is body tissue. A \"mussel\" is a shellfish.",
	},
	{
		Pattern:     `\b([sS]teamed|[fF]resh|[cC]ooked|[pP]ot\s+of)\s+muscles\b`,
		Flags:       []string{"a pot of steamed muscles"},
		Leaves:      []string{"a pot of steamed mussels", "exercise strengthens your muscles"},
		Message:     "Should be \"$1 mussels\"",
		Suggest:     "$1 mussels",
		Category:    "Confused words",
		Explanation: "A \"mussel\" is a shellfish. A \"muscle\" is body tissue.",
	},

	// --- naval / navel ---
	{
		Pattern:     `\b([tT]he|[aA]|[hH]is|[hH]er|[sS]enior|[rR]oyal|[bB]ritish)\s+navel\s+(officer|base|academy|fleet|battle|warfare|history|power|forces|vessel|ship|command|career)\b`,
		Flags:       []string{"the navel officer arrived"},
		Leaves:      []string{"the naval officer arrived", "a scar near his navel"},
		Message:     "Should be \"$1 naval $2\"",
		Suggest:     "$1 naval $2",
		Category:    "Confused words",
		Explanation: "\"Naval\" relates to a navy. Your \"navel\" is your belly button.",
	},
}
