package spellcheck

// tokenrules_capitals.go: where a sentence starts, and which words are names.

// lowercaseCompounds are the phrases where a name is conventionally left
// lowercase.
//
// Most are dishes and objects that stopped being about the place a long time
// ago. Style guides disagree about several of them, and a checker with an
// opinion on whether "french fries" wants a capital is a checker arguing
// with its user about lunch.
var lowercaseCompounds = []string{
	`french fries|toast|press|door|doors|window|windows|braid|kiss|dressing|horn|bread`,
	`english muffin|muffins|horn|ivy|breakfast`,
	`roman numeral|numerals|candle|nose`,
	`arabic numeral|numerals`,
	`indian summer|ink|file`,
	`dutch oven|courage|door|treat`,
	`swiss cheese|roll|army`,
	`turkish delight|bath|coffee`,
	`greek yogurt|yoghurt|salad`,
	`scotch egg|tape|broth`,
	`brussels sprout|sprouts`,
	`china cabinet|plate|plates|cup|cups|doll|shop`,
	`turkey <_>`, `<_> turkey`,
}

var capitalTokenRules = []TokenRule{
	{
		// This was a regular expression, and it marked the word after every
		// "U.S." and "St." in the document: a pattern can see a full stop and
		// a space, and cannot see whether the full stop ended anything. The
		// app's reading of the text can.
		ID:      "sentence-capital",
		Pattern: `( #opening&/[a-z][a-z']*/ )`,
		Flags:   []string{"she said hello. he said goodbye."},
		Leaves:  []string{"She said hello.", "The U.S. claims otherwise.", "- milk"},
		Message: "Sentence should start with a capital", Suggest: []string{"$1:Cap"},
		Category:    "Capitalization",
		Explanation: "The first word of a sentence starts with a capital letter.",
	},
	{
		// Which words are names is the lexicon's to say: a word written
		// with a capital nearly every time it is written at all. That leaves
		// out the names that are also words -- "we march on Friday", "it may
		// rain", "polish the table" -- which is the whole difficulty, and
		// the reason an earlier list of days, months and languages could
		// never be finished.
		ID:      "name-capital",
		Pattern: `( <=NNP>&/[a-z]+/ )`,
		Except:  lowercaseCompounds,
		Flags:   []string{"I live in london.", "We met on monday.", "He speaks french and german."},
		Leaves:  []string{"I live in London.", "We may go in march.", "A plate of french fries"},
		Message: "Should be \"$1:Cap\"", Suggest: []string{"$1:Cap"},
		Category:    "Capitalization",
		Explanation: "Names take a capital letter: people, places, days, months, languages and nationalities.",
	},
}
