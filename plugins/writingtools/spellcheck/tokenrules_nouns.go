package spellcheck

// tokenrules_nouns.go: how many of a thing there are, and the words that say.

const (
	explainPluralAfterNumber = "After a number above one, and after \"many\", \"several\" or \"a few\", a noun is plural: \"two dogs\", \"several books\", \"a few minutes\"."
	explainOneOf             = "\"One of\" picks one out of several, so the noun after it is plural: \"one of my friends\"."
	explainUncountable       = "\"$2\" is not something English counts, so it takes neither \"a\" nor a plural. Say \"some $2\" or \"a piece of $2\", or just \"$2\"."
	explainEvery             = "\"Every\" and \"each\" take things one at a time, so the noun after them is singular: \"every student\", \"each player\"."
	explainAPlural           = "\"A\" and \"an\" mean one, so the noun they go with is singular. Either the noun should be, or the \"a\" should go."
	explainNeedsArticle      = "A noun for one person or thing needs \"a\", \"an\", \"the\" or a word like \"my\" in front of it: \"I am a student\", \"it is a good idea\", \"he went to the shop\"."
)

var numberTokenRules = []TokenRule{
	{
		ID:      "number-singular",
		Pattern: `two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|twenty|thirty|fifty|many|several|few|numerous|multiple&!#proper ( <=NN>|minute|second|hour|day|week|month|year|time|dollar|pound|mile|metre|meter|person|thing|way|kind&!{invariant}&!<~NNS>&#lower ) !><~NN*>|old|long|high|wide|deep|tall|thick|'s|'|<VBG>|<CD>|-|and|or|,|/`,
		Except:  []string{`{numbered} <_> <_>`},
		Flags: []string{"I have two dog.", "She has three brother.", "There are many car on the road.",
			"He has several book.", "A few minute later he left."},
		Leaves: []string{"I have two dogs.", "A two bedroom house", "He caught two fish.",
			"See page 2 section b.", "A ten year old boy"},
		Message: "Should be \"$1 $2:NNS\"", Suggest: []string{"$2:NNS"},
		Category: catGrammar, Explanation: explainPluralAfterNumber,
	},
	{
		ID:      "one-of-singular",
		Pattern: `one of the|my|your|his|her|our|their|these|those <JJ>? ( <=NN>&!{collective}&!{invariant}&!<~NNS>&!age|kind|sort|type|size|generation|rank|calibre|caliber|stature|standing|background&#lower ) !><~NN*>|'s|'|<~JJ>|<VBG>`,
		Flags:   []string{"One of my friend is a doctor."},
		Leaves:  []string{"One of my friends is a doctor.", "One of the family", "One of the country's best"},
		Message: "Should be \"$5:NNS\"", Suggest: []string{"$5:NNS"},
		Category: catGrammar, Explanation: explainOneOf,
	},
	{
		ID:      "a-uncountable",
		Pattern: `( a|an&!#proper {uncountable} ) !><~NN*>|<~JJ>|<VBG>|'s|'|-`,
		Flags:   []string{"She gave me a advice.", "He has an information."},
		Leaves:  []string{"She gave me advice.", "A news report", "A software company"},
		Message: "\"$2\" does not take \"$1\"", Suggest: []string{"$2", "some $2", "a piece of $2"},
		Category: catGrammar, Explanation: explainUncountable,
	},
	{
		ID:      "how-many-uncountable",
		Pattern: `how ( many ) {uncountable}|time|water|work|space`,
		Flags:   []string{"How many money do you have?"},
		Leaves:  []string{"How much money do you have?", "How many times?"},
		Message: "Should be \"how much $3\"", Suggest: []string{"much"},
		Category:    catGrammar,
		Explanation: "\"Many\" is for things that can be counted and \"much\" for things that cannot: \"how many coins\", \"how much money\".",
	},
	{
		ID:      "much-plural",
		Pattern: `( much ) <=NNS>&#lower !><~NN*>`,
		Flags:   []string{"I have much friends."},
		Leaves:  []string{"I have many friends.", "Much depends on it.", "Not much happens here."},
		Message: "Should this be \"many $2\"?", Suggest: []string{"many"},
		Category: "Possible confusion", Severity: SeverityCheck,
		Explanation: "\"Much\" is for things that cannot be counted and \"many\" for things that can: \"much time\", \"many friends\".",
	},
	{
		ID:      "less-plural",
		Pattern: `( less ) <=NNS>&#lower`,
		Flags:   []string{"There are less people today."},
		Leaves:  []string{"There are fewer people today.", "There is less time."},
		Message: "\"Fewer\" is the usual word before a plural", Suggest: []string{"fewer"},
		Category: "Style", Severity: SeveritySuggestion,
		Explanation: "\"Less\" is for an amount and \"fewer\" for a number: \"less water\", \"fewer people\". \"Less\" before a plural is common in speech, and is still the thing an editor changes.",
	},
	{
		ID:      "every-plural",
		Pattern: `every|each ( <=NNS>&#lower ) !><~NN*>|'s|'`,
		Flags:   []string{"Every students passed.", "Each players gets a card."},
		Leaves:  []string{"Every student passed.", "Every two weeks", "Each sports club"},
		Message: "Should be \"$1 $2:NN\"", Suggest: []string{"$2:NN"},
		Category: catGrammar, Explanation: explainEvery,
	},
	{
		ID:      "a-plural",
		Pattern: `( a|an&!#proper <=NNS>&!people|peoples|thumbs|means|species|series&#lower ) !><~NN*>|'s|'|<~JJ>|<VBG>|up`,
		Flags:   []string{"This is a apples."},
		Leaves:  []string{"These are apples.", "A sports car", "A means to an end"},
		Message: "\"$1\" is for one, and \"$2\" is more than one", Suggest: []string{"$1 $2:NN", "$2"},
		Category: catGrammar, Explanation: explainAPlural,
	},
	{
		ID:      "a-adjective-plural",
		Pattern: `( a|an&!#proper <JJ>&!few|many|good|great|mere|further|additional|record|whopping|full|extra|estimated|staggering|total|couple|dozen|hundred|thousand|million|half|/.*-.*/ <=NNS>&#lower ) !><~NN*>|'s|'|<~JJ>`,
		Flags:   []string{"I bought a new shoes."},
		Leaves:  []string{"I bought new shoes.", "A few minutes", "A further 20 days"},
		Message: "\"$1\" is for one, and \"$3\" is more than one", Suggest: []string{"$2 $3", "$1 $2 $3:NN"},
		Category: catGrammar, Explanation: explainAPlural,
	},
	{
		ID:      "a-two",
		Pattern: `( a|an two|three|four|five|six|seven|eight|nine|ten <NNS> ) !><~NN*>|'s|'|<~JJ>`,
		Flags:   []string{"I have a two cats."},
		Leaves:  []string{"I have two cats.", "A two weeks' holiday"},
		Message: "No \"$1\" before a number", Suggest: []string{"$2 $3"},
		Category: catGrammar, Explanation: explainAPlural,
	},
	{
		ID:      "the-my",
		Pattern: `( the|a|an my|your|his|her|our|their&#lower ) <~NN*>|<JJ>`,
		Flags:   []string{"The my car is red.", "He is the my brother."},
		Leaves:  []string{"My car is red."},
		Message: "\"$1\" and \"$2\" cannot both come before a noun", Suggest: []string{"$2", "$1"},
		Category:    catGrammar,
		Explanation: "A noun takes one word of this kind in front of it. \"The\" and \"my\" each do the same job -- saying which one is meant -- so it is one or the other.",
	},
	{
		ID:      "two-articles",
		Pattern: `( a|an&!#proper the|a|an|this|that&#lower ) !>few|lot|little|bit|couple|-`,
		Flags:   []string{"I read a the book.", "It is a an old story."},
		Leaves:  []string{"I read the book.", "From A an arrow points to B."},
		Except:  []string{`#cap <_>`},
		Message: "\"$1\" and \"$2\" cannot both come before a noun", Suggest: []string{"$2", "$1"},
		Category:    catGrammar,
		Explanation: "A noun takes one word of this kind in front of it. One of these two is left over from an edit.",
	},
	{
		ID:      "dogs-apostrophe-are",
		Pattern: `the|my|your|his|her|our|their|these|those ( <NN>&#lower 's ) =>are|were`,
		Flags:   []string{"The dog's are barking."},
		Leaves:  []string{"The dogs are barking.", "The dog's owner is here."},
		Message: "Should be \"$2:NNS\"", Suggest: []string{"$2:NNS"},
		Category:    catGrammar,
		Explanation: "An apostrophe before the s marks something that belongs to the noun -- \"the dog's bowl\". More than one of something has no apostrophe: \"the dogs are barking\".",
	},
	{
		ID:      "two-cats-apostrophe",
		Pattern: `two|three|four|five|six|seven|eight|nine|ten|many|several|few ( <NN>&#lower 's ) !>#word`,
		Flags:   []string{"I have two cat's."},
		Leaves:  []string{"I have two cats.", "Many people's lives"},
		Message: "Should be \"$2:NNS\"", Suggest: []string{"$2:NNS"},
		Category:    catGrammar,
		Explanation: "An apostrophe before the s marks something that belongs to the noun -- \"the cat's bowl\". More than one of something has no apostrophe: \"two cats\".",
	},

	// --- a noun with no article ---
	{
		ID:      "is-noun-no-article",
		Pattern: `i|he|she|it|this|that am|is|was|'m ( {needs-article}&<=NN>&!way|kind|sort|bit|lot|part|couple&#lower ) !><~NN*>|'s|'|<~JJ>|<VBG>|<CD>|-`,
		Flags:   []string{"I am student.", "She is teacher."},
		Leaves:  []string{"I am a student.", "She is president.", "It is time."},
		Message: "\"$3\" needs \"a\" or \"the\" before it", Suggest: []string{"a(n) $3", "the $3"},
		Category: catGrammar, Explanation: explainNeedsArticle,
	},
	{
		ID:      "is-adjective-noun-no-article",
		Pattern: `i|he|she|it|this|that am|is|was|'m ( <=JJ>&#lower {needs-article}&<=NN>&!way|kind|sort|bit|lot|part|couple&#lower ) !><~NN*>|'s|'|<~JJ>|<VBG>|<CD>|-`,
		Flags:   []string{"It is good idea."},
		Leaves:  []string{"It is a good idea.", "It is good news."},
		Message: "\"$3 $4\" needs \"a\" or \"the\" before it", Suggest: []string{"a(n) $3 $4", "the $3 $4"},
		Category: catGrammar, Explanation: explainNeedsArticle,
	},
	{
		ID:      "place-noun-no-article",
		Pattern: `in|at|from|into|near ( <=JJ>&!<~NN*>&!<~DT>&#lower? {needs-article-place}&<=NN>&#lower ) !><~NN*>|'s|'|<~JJ>|<VBG>|<CD>|-`,
		Flags:   []string{"I live in big apartment."},
		Leaves:  []string{"I live in a big house.", "He went to school.", "She is at home."},
		Message: "Is \"a\" or \"the\" missing before \"$2 $3\"?", Suggest: []string{"a(n) $2 $3", "the $2 $3"},
		Category: "Possible confusion", Severity: SeverityCheck,
		Explanation: explainNeedsArticle,
	},
}

// regularisedPlurals are plurals built by rule for nouns that do not follow
// it, where the result happens to be a word: "mans" is what somebody does to
// a desk, and "foots" to a bill. So the dictionary passes them, and only
// what stands in front shows they were meant as plurals.
var regularisedPlurals = [][2]string{
	{"mans", "men"}, {"mens", "men"}, {"womens", "women"}, {"foots", "feet"},
	{"feets", "feet"}, {"tooths", "teeth"}, {"mouses", "mice"},
	{"mices", "mice"}, {"gooses", "geese"}, {"sheeps", "sheep"},
	{"childrens", "children"}, {"peoples", "people"},
}

var regularisedPluralTokenRules = func() []TokenRule {
	var rules []TokenRule
	for _, pair := range regularisedPlurals {
		wrong, right := pair[0], pair[1]
		before := `two|three|four|five|six|seven|eight|nine|ten|many|several|few|some|these|those|both|my|his|her|our|their|your`
		if wrong == "peoples" {
			// "The peoples of Europe" is right; after a count it is not.
			before = `two|three|four|five|six|seven|eight|nine|ten|twenty|many|several|few`
		}
		rules = append(rules, TokenRule{
			ID:      "plural-" + wrong,
			Pattern: before + ` ( ` + wrong + ` ) !>'s|'`,
			Flags:   []string{"I saw three " + wrong + "."},
			Leaves:  []string{"I saw three " + right + "."},
			Message: "Should be \"" + right + "\"", Suggest: []string{right},
			Category:    catGrammar,
			Explanation: "The plural of this noun is not made with -s: it is \"" + right + "\".",
		})
	}
	return rules
}()
