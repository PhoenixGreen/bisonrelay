package spellcheck

// tokenrules_comparison.go: "more", "most", "-er", "-est", and "than".

const explainDoubleComparative = "An adjective is compared once: with \"more\", or with -er, and not with both. \"Taller\" already means \"more tall\"."

var comparisonTokenRules = []TokenRule{
	{
		ID:      "baddest",
		Pattern: `the|my|his|her|our|their|your ( baddest ) !>-`,
		Flags:   []string{"It was the baddest day."},
		Leaves:  []string{"It was the worst day."},
		Message: "Should be \"worst\"", Suggest: []string{"worst"},
		Category:    catGrammar,
		Explanation: "\"Bad\" is compared irregularly: \"bad\", \"worse\", \"worst\".",
	},
	{
		ID:      "more-er",
		Pattern: `( more /\w+er/&<~JJR>|better|worse ) !><NNS>|<NN>|<JJ>`,
		Flags:   []string{"He is more taller than me.", "It is more better now.", "It is more bigger."},
		Leaves:  []string{"He is taller than me.", "More older people are voting.", "A more proper answer"},
		Message: "Should be \"$2\"", Suggest: []string{"$2"},
		Category: catGrammar, Explanation: explainDoubleComparative,
	},
	{
		ID:      "most-est",
		Pattern: `( most /\w+est/&<~JJS>|best|worst )`,
		Flags:   []string{"This is the most best day.", "She is the most tallest girl."},
		Leaves:  []string{"This is the best day.", "The most honest answer", "The most modest house"},
		Message: "Should be \"$2\"", Suggest: []string{"$2"},
		Category:    catGrammar,
		Explanation: "An adjective is compared once: with \"most\", or with -est, and not with both. \"Tallest\" already means \"most tall\".",
	},
	{
		ID:      "more-short-than",
		Pattern: `( more {shortadj} ) =>than`,
		Flags:   []string{"She is more smart than him.", "He runs more fast than me."},
		Leaves:  []string{"She is smarter than him.", "It does more good than harm."},
		Message: "Should be \"$2:JJR\"", Suggest: []string{"$2:JJR"},
		Category:    catGrammar,
		Explanation: "Short adjectives are compared with -er rather than with \"more\": \"smarter\", \"faster\", \"easier\". \"More\" is for the longer ones -- \"more beautiful\", \"more expensive\".",
	},
	{
		ID:      "more-short",
		Pattern: `am|is|are|was|were|'m|'s|'re|feel|feels|felt|get|gets|got|become|becomes|became|seem|seems|seemed|look|looks|looked ( more {shortadj} ) !><~NN*>|<JJ>|than|and|or`,
		Flags:   []string{"This is more easy.", "I am more happy now."},
		Leaves:  []string{"This is easier.", "This is more easy money than I expected."},
		Message: "\"$3:JJR\" is the usual form", Suggest: []string{"$3:JJR"},
		Category: "Style", Severity: SeveritySuggestion,
		Explanation: "Short adjectives are usually compared with -er rather than with \"more\": \"easier\", \"happier\", \"cheaper\".",
	},
	{
		ID:      "the-most-short",
		Pattern: `the ( most {shortadj}&!high|kind|close ) !>and|or|,`,
		Flags:   []string{"This is the most cheap one."},
		Leaves:  []string{"This is the cheapest one."},
		Message: "\"$3:JJS\" is the usual form", Suggest: []string{"$3:JJS"},
		Category: "Style", Severity: SeveritySuggestion,
		Explanation: "Short adjectives are usually compared with -est rather than with \"most\": \"cheapest\", \"fastest\", \"easiest\".",
	},
	{
		ID:      "as-tall-than",
		Pattern: `as <JJ|RB>&!rather|more|less|other|better|worse|well|much|many|soon|long|far ( than )`,
		Flags:   []string{"He is as tall than me."},
		Leaves:  []string{"He is as tall as me.", "He is taller than me."},
		Message: "Should be \"as $2 as\"", Suggest: []string{"as"},
		Category:    catGrammar,
		Explanation: "A comparison that starts with \"as\" finishes with \"as\": \"as tall as\". \"Than\" goes with -er and \"more\": \"taller than\".",
	},
	{
		ID:      "different-than",
		Pattern: `different ( than ) !>{subj}`,
		Flags:   []string{"She is different than her brother."},
		Leaves:  []string{"She is different from her brother.", "It is different than I expected."},
		Message: "\"Different from\" is the usual phrase", Suggest: []string{"from"},
		Category: "Style", Severity: SeveritySuggestion,
		Explanation: "\"Different from\" is right everywhere. \"Different than\" is common in American English and \"different to\" in British, and each sounds wrong to the other's readers.",
	},
}
