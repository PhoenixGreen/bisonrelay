package spellcheck

// tokenrules_pronouns.go: "I" or "me", and the forms that do not exist.

const (
	explainSubjectPronoun = "The one doing something is \"I\", \"he\", \"she\", \"we\" or \"they\". \"Me\", \"him\", \"her\", \"us\" and \"them\" are for the one it is done to: \"he saw me\", \"I saw him\"."
	explainObjectPronoun  = "After a preposition -- \"to\", \"for\", \"with\", \"between\" -- the pronoun is \"me\", \"him\", \"her\", \"us\" or \"them\": \"between you and me\", \"she gave it to me\". Try the sentence without the other person: nobody says \"she gave it to I\"."
)

var pronounTokenRules = []TokenRule{
	{
		ID:      "me-as-subject",
		Pattern: `^ ( me|him|them|us ) <=VBZ>|<=VBD>|<MD>|am|is|are|was|were|like|likes|want|wants|need|needs|have|has|go|think|know|love|hate`,
		Flags:   []string{"Him is my brother.", "Me like pizza.", "Them are my friends.", "Us went to the park."},
		Leaves:  []string{"He is my brother.", "Me too.", "Us against them."},
		Message: "Should be \"$1:NOM\"", Suggest: []string{"$1:NOM"},
		Category: catGrammar, Explanation: explainSubjectPronoun,
	},
	{
		ID:      "her-as-subject",
		Pattern: `^ ( her ) is|was|has|does|did|will|can|went|goes|likes|wants|said|doesn't|isn't`,
		Flags:   []string{"Her is my sister."},
		Leaves:  []string{"She is my sister.", "Her car is red."},
		Message: "Should be \"She\"", Suggest: []string{"she"},
		Category: catGrammar, Explanation: explainSubjectPronoun,
	},
	{
		ID:      "me-and-him",
		Pattern: `^ ( me and him|her|them ) =><VB*>|<MD>`,
		Flags:   []string{"Me and him went to the shop."},
		Leaves:  []string{"He and I went to the shop."},
		Message: "Should be \"$3:NOM and I\"", Suggest: []string{"$3:NOM and I"},
		Category: catGrammar, Explanation: explainSubjectPronoun,
	},
	{
		ID:      "me-and-name",
		Pattern: `^ ( me and <NNP>|you ) =><VB*>|<MD>`,
		Flags:   []string{"Me and John went to the shop."},
		Leaves:  []string{"John and I went to the shop."},
		Message: "Should be \"$3 and I\"", Suggest: []string{"$3 and I"},
		Category: catGrammar, Explanation: explainSubjectPronoun,
	},
	{
		ID:      "her-and-me",
		Pattern: `^ ( him|her|them and me|i ) =><VB*>|<MD>`,
		Flags:   []string{"Her and me are friends."},
		Leaves:  []string{"She and I are friends."},
		Message: "Should be \"$1:NOM and I\"", Suggest: []string{"$1:NOM and I"},
		Category: catGrammar, Explanation: explainSubjectPronoun,
	},
	{
		ID:      "to-i",
		Pattern: `to|for|with|from|at|by|about|without|except ( i ) !>#word|<PUNCT>`,
		Flags:   []string{"She gave it to I."},
		Leaves:  []string{"She gave it to me.", "The person I spoke to I think was French."},
		Message: "Should be \"$1 me\"", Suggest: []string{"me"},
		Category: catGrammar, Explanation: explainObjectPronoun,
	},
	{
		ID:      "between-you-and-i",
		Pattern: `between|for|to|with|from <NNP>|you|him|her|them and ( i ) !><VB*>|<MD>|<RB>`,
		Flags:   []string{"Between you and I, it was bad."},
		Leaves:  []string{"Between you and me, it was bad.", "For you and I know it."},
		Message: "Should be \"$2 and me\"", Suggest: []string{"me"},
		Category: catGrammar, Explanation: explainObjectPronoun,
	},
	{
		ID:      "hisself",
		Pattern: `( hisself )`,
		Flags:   []string{"He hurt hisself."},
		Message: "Should be \"himself\"", Suggest: []string{"himself"},
		Category:    catGrammar,
		Explanation: "The forms are \"myself\", \"yourself\", \"himself\", \"herself\", \"itself\", \"ourselves\", \"yourselves\" and \"themselves\". \"Hisself\" follows the pattern of \"myself\" and is not one of them.",
	},
	{
		ID:      "theirselves",
		Pattern: `( theirselves|theirself|themself )`,
		Flags:   []string{"They did it theirselves."},
		Message: "Should be \"themselves\"", Suggest: []string{"themselves"},
		Category:    catGrammar,
		Explanation: "The forms are \"myself\", \"yourself\", \"himself\", \"herself\", \"itself\", \"ourselves\", \"yourselves\" and \"themselves\". \"Theirselves\" follows the pattern of \"ourselves\" and is not one of them.",
	},
	{
		ID:      "is-mines",
		Pattern: `is|are|was|were|it's|that's ( mines ) !>#word`,
		Flags:   []string{"This is mines."},
		Leaves:  []string{"This is mine.", "The coal mines are closed."},
		Message: "Should be \"mine\"", Suggest: []string{"mine"},
		Category:    catGrammar,
		Explanation: "\"Mine\" already means \"belonging to me\" and takes no -s. \"Yours\", \"hers\", \"ours\" and \"theirs\" end in s; \"mine\" does not.",
	},
	{
		ID:      "taller-than-me-am",
		Pattern: `than ( me|him|her|us|them ) am|is|are|was|were|do|does|did|have|has|can|will`,
		Flags:   []string{"He is taller than me am."},
		Leaves:  []string{"He is taller than I am.", "He is taller than me."},
		Message: "Should be \"$2:NOM $3\"", Suggest: []string{"$2:NOM"},
		Category: catGrammar, Explanation: explainSubjectPronoun,
	},
}
