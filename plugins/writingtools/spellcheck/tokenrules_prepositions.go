package spellcheck

// tokenrules_prepositions.go: the preposition a word takes, where it takes
// only one.
//
// These are facts about particular words rather than about grammar, and
// there is no rule to them -- "interested in", "good at", "depends on" are
// simply how it is said, which is why they are the mistakes a second
// language leaves longest. Each is written out.

const catPrepositions = "Prepositions"

func explainTakes(word, right string) string {
	return "\"" + word + "\" takes \"" + right + "\". Which preposition a word takes is not something a rule predicts; it is learned with the word."
}

var prepositionTokenRules = []TokenRule{
	{
		ID:      "good-in",
		Pattern: `good|bad|great|terrible|excellent|brilliant|hopeless ( in ) maths|math|mathematics|english|science|sports|sport|languages|cooking|<=VBG>`,
		Flags:   []string{"I am good in maths."},
		Leaves:  []string{"I am good at maths.", "Good in parts"},
		Message: "Should be \"$1 at\"", Suggest: []string{"at"},
		Category: catPrepositions, Explanation: explainTakes("good", "at"),
	},
	{
		ID:      "arrive-to",
		Pattern: `arrive|arrives|arrived|arriving ( to ) =>the|a|an|my|our|his|her|their|<NNP>`,
		Flags:   []string{"She arrived to the station."},
		Leaves:  []string{"She arrived at the station.", "She arrived to find it gone."},
		Message: "Should be \"$1 at\" or \"$1 in\"", Suggest: []string{"at", "in"},
		Category:    catPrepositions,
		Explanation: "One arrives at a place or in a city or country, never to one: \"arrived at the station\", \"arrived in London\".",
	},
	{
		ID:      "interested-on",
		Pattern: `interested ( on ) =><NN*>|<VBG>|<DT>|<PRP$>`,
		Flags:   []string{"I am interested on music."},
		Leaves:  []string{"I am interested in music."},
		Message: "Should be \"interested in\"", Suggest: []string{"in"},
		Category: catPrepositions, Explanation: explainTakes("Interested", "in"),
	},
	{
		ID:      "depend-of",
		Pattern: `depend|depends|depended|depending ( of|from )`,
		Flags:   []string{"It depends of the weather."},
		Leaves:  []string{"It depends on the weather."},
		Message: "Should be \"$1 on\"", Suggest: []string{"on"},
		Category: catPrepositions, Explanation: explainTakes("Depend", "on"),
	},
	{
		ID:      "waiting-you",
		Pattern: `am|is|are|was|were|'m|'re|'s|been|keep|kept ( waiting ) =>me|you|him|her|us|them`,
		Flags:   []string{"I am waiting you."},
		Leaves:  []string{"I am waiting for you."},
		Message: "Should be \"waiting for $3\"", Suggest: []string{"waiting for"},
		Category: catPrepositions, Explanation: explainTakes("Wait", "for"),
	},
	{
		ID:      "listen-me",
		Pattern: `( listen|listens|listened|listening ) =>me|him|her|us|them|music`,
		Flags:   []string{"Listen me carefully."},
		Leaves:  []string{"Listen to me carefully."},
		Message: "Should be \"$1 to\"", Suggest: []string{"$1 to"},
		Category: catPrepositions, Explanation: explainTakes("Listen", "to"),
	},
	{
		ID:      "afraid-from",
		Pattern: `afraid|scared|frightened|terrified ( from )`,
		Flags:   []string{"She is afraid from spiders."},
		Leaves:  []string{"She is afraid of spiders."},
		Message: "Should be \"$1 of\"", Suggest: []string{"of"},
		Category: catPrepositions, Explanation: explainTakes("Afraid", "of"),
	},
	{
		ID:      "in-weekday",
		Pattern: `( in ) {weekday} !><POS>|<~NN*>`,
		Flags:   []string{"We arrived in Monday."},
		Leaves:  []string{"We arrived on Monday.", "In Monday's game"},
		Message: "Should be \"on $2\"", Suggest: []string{"on"},
		Category:    catPrepositions,
		Explanation: "A day takes \"on\": \"on Monday\", \"on 5 May\". \"In\" is for a month, a year or a season -- \"in May\", \"in 2020\" -- and \"at\" for a time of day.",
	},
	{
		ID:      "in-date",
		Pattern: `( in ) /\d{1,2}(st|nd|rd|th)?/ {month}`,
		Flags:   []string{"I was born in 5 May."},
		Leaves:  []string{"I was born on 5 May.", "I was born in May."},
		Message: "Should be \"on $2 $3\"", Suggest: []string{"on"},
		Category:    catPrepositions,
		Explanation: "A day takes \"on\": \"on Monday\", \"on 5 May\". \"In\" is for a month, a year or a season -- \"in May\", \"in 2020\" -- and \"at\" for a time of day.",
	},
	{
		ID:      "responsible-of",
		Pattern: `responsible ( of )`,
		Flags:   []string{"He is responsible of the project."},
		Leaves:  []string{"He is responsible for the project."},
		Message: "Should be \"responsible for\"", Suggest: []string{"for"},
		Category: catPrepositions, Explanation: explainTakes("Responsible", "for"),
	},
	{
		ID:      "agree-to-you",
		Pattern: `agree|agrees|agreed ( to ) you|him|her|me|us !>#word`,
		Flags:   []string{"I agree to you."},
		Leaves:  []string{"I agree with you.", "I agree to the terms."},
		Message: "Should be \"$1 with $3\"", Suggest: []string{"with"},
		Category:    catPrepositions,
		Explanation: "One agrees with a person and to a proposal: \"I agree with you\", \"I agree to the terms\".",
	},
	{
		ID:      "angry-on",
		Pattern: `angry|mad|upset|annoyed|furious|cross ( on ) me|you|him|her|us|them`,
		Flags:   []string{"She is angry on me."},
		Leaves:  []string{"She is angry with me."},
		Message: "Should be \"$1 with\"", Suggest: []string{"with", "at"},
		Category: catPrepositions, Explanation: explainTakes("Angry", "with"),
	},
	{
		ID:      "forward-for",
		Pattern: `look|looks|looked|looking forward ( for )`,
		Flags:   []string{"I am looking forward for it."},
		Leaves:  []string{"I am looking forward to it."},
		Message: "Should be \"forward to\"", Suggest: []string{"to"},
		Category: catPrepositions, Explanation: explainTakes("Look forward", "to"),
	},
	{
		ID:      "according-with",
		Pattern: `according ( with )`,
		Flags:   []string{"According with the report, sales rose."},
		Leaves:  []string{"According to the report, sales rose.", "In accordance with the report"},
		Message: "Should be \"according to\"", Suggest: []string{"to"},
		Category: catPrepositions, Explanation: explainTakes("According", "to"),
	},
	{
		ID:      "in-the-other-hand",
		Pattern: `( in ) the other hand`,
		Flags:   []string{"In the other hand, it is cheap."},
		Leaves:  []string{"On the other hand, it is cheap."},
		Message: "Should be \"on the other hand\"", Suggest: []string{"on"},
		Category:    catPrepositions,
		Explanation: "The phrase is \"on the one hand ... on the other hand\".",
	},
	{
		ID:      "in-the-phone",
		Pattern: `( in ) the phone|telephone|internet|radio|tv|television|weekend !><~NN*>|<POS>`,
		Flags:   []string{"She was in the phone.", "I will see you in the weekend."},
		Leaves:  []string{"She was on the phone.", "In the phone book", "In the internet age"},
		Message: "Should be \"on the $3\"", Suggest: []string{"on"},
		Category:    catPrepositions,
		Explanation: "Things heard, seen or said through a device are \"on\" it: \"on the phone\", \"on the radio\", \"on the internet\".",
	},
}
