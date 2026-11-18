package spellcheck

// tokenrules_structure.go: words in the wrong order, words missing, and
// words that should not be there.

const (
	catStructure = "Sentence structure"

	explainQuestionOrder = "In a question the verb comes before its subject: \"What are you doing?\", \"Where is he going?\". With the subject first it reads as a statement with a question mark on the end."
	explainMissingBe     = "The sentence has no verb. Between a subject and what is said about it there is a form of \"be\": \"she is happy\", \"they are tired\", \"he is a doctor\"."
	explainNotOrder      = "\"Not\" follows the verb it negates when that verb is \"be\" or a helper -- \"is not\", \"cannot\" -- and other verbs take \"do not\" or \"does not\" in front of them: \"I do not like it\"."
	explainNoTo          = "\"$1\" takes what it acts on directly, with no preposition in between."
)

var structureTokenRules = []TokenRule{
	// --- questions ---
	{
		ID:      "question-not-inverted",
		Pattern: `^ what|where|why|how|when|who ( {subj} am|is|are|was|were|will|would|can|could|should ) <_>{0,12} /\?+/ $`,
		Flags:   []string{"What you are doing?", "Where you are going?", "Why he is angry?", "How you are?", "When she will come?"},
		Leaves:  []string{"What are you doing?", "What you are doing is wrong."},
		Message: "Should be \"$3 $2\"", Suggest: []string{"$3 $2"},
		Category: catStructure, Explanation: explainQuestionOrder,
	},
	{
		ID:      "where-you-from",
		Pattern: `^ ( where you|they|we from ) /\?+/`,
		Flags:   []string{"Where you from?"},
		Leaves:  []string{"Where are you from?"},
		Message: "Should be \"Where are $2 from\"", Suggest: []string{"where are $2 from"},
		Category: catStructure, Explanation: explainMissingBe,
	},
	{
		ID:      "what-your-name",
		Pattern: `^ ( what ) your|his|her|their|its|the <NN> /\?+/ $`,
		Flags:   []string{"What your name?"},
		Leaves:  []string{"What is your name?"},
		Message: "Should be \"What is $2 $3\"", Suggest: []string{"what is"},
		Category: catStructure, Explanation: explainMissingBe,
	},
	{
		ID:      "question-full-stop",
		Pattern: `^ what|where|when|why|who|how am|is|are|was|were|do|does|did|can|could|will|would|should|have|has {subj}|your|the|this|that|there !<COMMA>{0,10} ( . ) $`,
		Flags:   []string{"What is your name.", "Where are you going."},
		Leaves:  []string{"What is your name?", "What I do is my business.", "How are you, I asked him."},
		Message: "Should this end with a question mark?", Suggest: []string{"?"},
		Category: "Punctuation", Severity: SeverityCheck,
		Explanation: "This is worded as a question -- it opens with a question word and its verb comes before its subject -- and ends with a full stop.",
	},
	{
		ID:      "embedded-question-order",
		Pattern: `know|tell|wonder|ask|asked|sure|idea|understand|remember|explain <PRP>? what|where|who|why|how ( is|are|was|were <DT>|<PRP$> <JJ>? <NN*>&!matter|problem|point|difference|use ) !>#word`,
		Flags:   []string{"I don't know what is his name.", "Can you tell me where is the station?"},
		Leaves:  []string{"I don't know what his name is.", "Tell me what is the matter."},
		Message: "Should be \"$5 $6 $7 $4\"", Suggest: []string{"$5 $6 $7 $4"},
		Category: catStructure, Severity: SeveritySuggestion,
		Explanation: "A question inside a sentence keeps the order of a statement: the subject, then the verb. \"Where is the station?\" on its own, and \"Can you tell me where the station is?\" inside another question.",
	},

	// --- word order ---
	{
		ID:      "very-like",
		Pattern: `{subj} ( very ) like|love|enjoy|want|need|hate|appreciate|hope|miss|agree|think|wish`,
		Flags:   []string{"I very like this song."},
		Leaves:  []string{"I very much like this song.", "I really like this song."},
		Message: "\"Very\" does not go before a verb", Suggest: []string{"really", "very much"},
		Category:    catStructure,
		Explanation: "\"Very\" strengthens an adjective or an adverb -- \"very good\", \"very quickly\" -- and not a verb. Before a verb the word is \"really\", or \"very much\".",
	},
	{
		ID:      "like-very-much-noun",
		Pattern: `like|love|enjoy|want|need|hate ( very much <DT>? <NN*>|<PRP> ) !>#word`,
		Flags:   []string{"I like very much pizza."},
		Leaves:  []string{"I like pizza very much.", "I like very much the idea of leaving early."},
		Message: "Should be \"$1 $4 $5 very much\"", Suggest: []string{"$4 $5 very much"},
		Category: catStructure, Severity: SeveritySuggestion,
		Explanation: "English keeps a verb and the thing it acts on together. \"Very much\" goes after them: \"I like pizza very much\".",
	},
	{
		ID:      "speaks-well-english",
		Pattern: `speak|speaks|spoke|speaking ( <RB>{1,2} {language} ) !>#word`,
		Flags:   []string{"He speaks very well English."},
		Leaves:  []string{"He speaks English very well."},
		Message: "Should be \"$1 $3 $2\"", Suggest: []string{"$3 $2"},
		Category: catStructure, Severity: SeveritySuggestion,
		Explanation: "English keeps a verb and the thing it acts on together. How well it is done goes after them: \"speaks English very well\".",
	},
	{
		ID:      "gave-to-me-a",
		Pattern: `gave|give|gives|giving|send|sends|sent|show|shows|showed|tell|tells|told|bring|brings|brought|buy|bought ( to me|you|him|her|us|them ) =>a|an|the|some|my|your|his|our|their|<CD>`,
		Flags:   []string{"She gave to me a book."},
		Leaves:  []string{"She gave me a book.", "She gave a book to me."},
		Message: "Should be \"$1 $3\"", Suggest: []string{"$3"},
		Category:    catStructure,
		Explanation: "When the person comes straight after \"give\", \"send\", \"show\" or \"tell\", there is no \"to\": \"gave me a book\". \"To\" is for when the person comes last: \"gave a book to me\".",
	},
	{
		ID:      "enough-big",
		Pattern: `( enough <=JJ>&!<~NN*> ) =>to|for`,
		Flags:   []string{"Enough big to fit."},
		Leaves:  []string{"Big enough to fit.", "Enough good people to help"},
		Message: "Should be \"$2 enough\"", Suggest: []string{"$2 enough"},
		Category:    catStructure,
		Explanation: "\"Enough\" comes after an adjective and before a noun: \"big enough\", \"enough room\".",
	},
	{
		ID:      "car-red",
		Pattern: `have|has|had|got|bought|own|owns|want|wants|see|saw a|an ( <=NN> red|blue|green|yellow|black|white|brown|pink|grey|gray|orange|purple|big|small|new|old ) !>#word`,
		Flags:   []string{"I have a car red."},
		Leaves:  []string{"I have a red car.", "Paint the car red."},
		Message: "Should be \"$2 $4 $3\"", Suggest: []string{"$4 $3"},
		Category: catStructure, Severity: SeveritySuggestion,
		Explanation: "In English an adjective comes before the noun it describes: \"a red car\".",
	},

	// --- not, no ---
	{
		ID:      "i-not-verb",
		Pattern: `i|we|they|you&#clause ( not ) like|want|know|need|have|understand|think|agree|care|see|go|believe|remember|<=VB>`,
		Flags:   []string{"I not like it."},
		Leaves:  []string{"I do not like it.", "I not only like it but love it."},
		Message: "Should be \"$1 do not $3\"", Suggest: []string{"do not", "don't"},
		Category: catStructure, Explanation: explainNotOrder,
	},
	{
		ID:      "he-not-verb",
		Pattern: `he|she|it&#clause ( not ) like|likes|want|wants|know|knows|need|needs|have|has|understand|understands|care|cares|<=VB>`,
		Flags:   []string{"She not like fish."},
		Leaves:  []string{"She does not like fish."},
		Message: "Should be \"$1 does not $3:VB\"", Suggest: []string{"does not", "doesn't"},
		Category: catStructure, Explanation: explainNotOrder,
	},
	{
		ID:      "not-is",
		Pattern: `{subj} ( not is|are|am|was|were )`,
		Flags:   []string{"He not is here."},
		Leaves:  []string{"He is not here."},
		Message: "Should be \"$3 not\"", Suggest: []string{"$3 not"},
		Category: catStructure, Explanation: explainNotOrder,
	},
	{
		ID:      "i-no-have",
		Pattern: `i|we|they|you&#clause ( no ) have|like|want|know|need|understand|speak|go|see|can|think|care|eat|work`,
		Flags:   []string{"I no have money."},
		Leaves:  []string{"I have no money.", "I no longer have it."},
		Message: "Should be \"$1 don't $3\"", Suggest: []string{"don't", "do not"},
		Category: catStructure, Explanation: explainNotOrder,
	},
	{
		ID:      "she-no-like",
		Pattern: `he|she|it&#clause ( no ) have|like|want|know|need|understand|speak|go|see|can|think|care|eat|work`,
		Flags:   []string{"She no like fish."},
		Leaves:  []string{"She doesn't like fish."},
		Message: "Should be \"$1 doesn't $3\"", Suggest: []string{"doesn't", "does not"},
		Category: catStructure, Explanation: explainNotOrder,
	},

	// --- no verb ---
	{
		ID:      "pronoun-adjective",
		Pattern: `^ ( i|he|she|we|they ) <=JJ>&!<~VB*>&!<~NN*>&!<~RB*>&!<~IN>&!<~DT>&!<~CD>&!<~MD>&#lower !><VB*>|<MD>`,
		Flags:   []string{"She happy today."},
		Leaves:  []string{"She is happy today.", "He alone knows.", "I first met him in May."},
		Message: "Should be \"$1 $1:BE $2\"", Suggest: []string{"$1 $1:BE"},
		Category: catStructure, Explanation: explainMissingBe,
	},
	{
		ID:      "pronoun-very-adjective",
		Pattern: `^ ( i|he|she|we|they ) very|extremely <JJ>|<VBN>`,
		Flags:   []string{"They very tired."},
		Leaves:  []string{"They are very tired."},
		Message: "Should be \"$1 $1:BE $2 $3\"", Suggest: []string{"$1 $1:BE"},
		Category: catStructure, Explanation: explainMissingBe,
	},
	{
		ID:      "pronoun-a-noun",
		Pattern: `^ ( i|he|she|we|they ) =>a|an`,
		Flags:   []string{"He a doctor."},
		Leaves:  []string{"He is a doctor."},
		Message: "Should be \"$1 $1:BE\"", Suggest: []string{"$1 $1:BE"},
		Category: catStructure, Explanation: explainMissingBe,
	},

	// --- words that should not be there ---
	{
		ID:      "been-to-there",
		Pattern: `been|go|goes|went|going|gone|come|came|get|got ( to there|here )`,
		Flags:   []string{"I have been to there."},
		Leaves:  []string{"I have been there.", "From here to there"},
		Message: "No \"to\" before \"$3\"", Suggest: []string{"$3"},
		Category:    catStructure,
		Explanation: "\"Here\" and \"there\" already mean \"to this place\" and \"to that place\", so they take no \"to\": \"I have been there\", \"come here\".",
	},
	{
		ID:      "going-to-home",
		Pattern: `go|goes|going|went|gone|come|comes|came|coming|get|got|return|returned|arrive|arrived ( to home ) !><~NN*>`,
		Flags:   []string{"I am going to home."},
		Leaves:  []string{"I am going home.", "Go to home page."},
		Message: "No \"to\" before \"home\"", Suggest: []string{"home"},
		Category:    catStructure,
		Explanation: "After a verb of movement, \"home\" means \"to my home\" on its own and takes no \"to\": \"going home\", \"came home\".",
	},
	{
		ID:      "discuss-about",
		Pattern: `( discuss|discusses|discussed|discussing about ) =>the|a|an|this|that|it|how|what|my|our|their|your|his|her`,
		Flags:   []string{"We discussed about the problem."},
		Leaves:  []string{"We discussed the problem.", "A discussion about the problem"},
		Message: "No \"about\" after \"$1\"", Suggest: []string{"$1"},
		Category: catStructure, Explanation: explainNoTo,
	},
	{
		ID:      "married-with",
		Pattern: `{subj}|<NNP> ( married with ) =>a|an|the|my|his|her|me|him|them|you|<NNP>`,
		Flags:   []string{"She married with a doctor."},
		Leaves:  []string{"She married a doctor."},
		Message: "No \"with\" after \"married\"", Suggest: []string{"married"},
		Category: catStructure, Explanation: explainNoTo,
	},
	{
		ID:      "is-married-with",
		Pattern: `am|is|are|was|were|got|get|getting married ( with ) =>a|an|the|my|his|her|me|him|them|you|<NNP>`,
		Flags:   []string{"He is married with her."},
		Leaves:  []string{"He is married to her.", "He is married with two children."},
		Message: "Should be \"married to\"", Suggest: []string{"to"},
		Category:    "Prepositions",
		Explanation: "A person is married to another: \"married to her\". \"Married with\" is for what a couple has -- \"married with two children\".",
	},
	{
		ID:      "entered-into-room",
		Pattern: `( enter|enters|entered|entering into ) the|a room|house|building|office|kitchen|hall|shop|store|car|classroom|church|garden|city|town|country`,
		Flags:   []string{"He entered into the room."},
		Leaves:  []string{"He entered the room.", "They entered into an agreement."},
		Message: "No \"into\" after \"$1\"", Suggest: []string{"$1"},
		Category: catStructure, Explanation: explainNoTo,
	},
	{
		ID:      "where-at",
		Pattern: `^ where <_>{0,3} ( <_> at ) /\?+/ $`,
		Flags:   []string{"Where are you at?"},
		Leaves:  []string{"Where are you?"},
		Message: "\"At\" adds nothing after \"where\"", Suggest: []string{"$3"},
		Category: "Style", Severity: SeveritySuggestion,
		Explanation: "\"Where\" already asks for a place, so the \"at\" on the end says it twice.",
	},
	{
		ID:      "although-but",
		Pattern: `^ although|though <_>{2,14} ( , but|yet )`,
		Flags:   []string{"Although he was tired, but he kept working."},
		Leaves:  []string{"Although he was tired, he kept working.", "He was tired, but he kept working."},
		Message: "\"$1\" and \"$4\" say the same thing twice", Suggest: []string{","},
		Category:    catStructure,
		Explanation: "\"Although\" already sets the two halves of the sentence against each other. A \"but\" as well does it a second time; one or the other is enough.",
	},
	{
		ID:      "no-money",
		Pattern: `don't|doesn't|didn't|haven't|hasn't|hadn't have|got|want|need|see ( no ) <NN*>`,
		Flags:   []string{"I don't have no money."},
		Leaves:  []string{"I don't have any money."},
		Message: "Two negatives: should be \"any\"", Suggest: []string{"any"},
		Category:    catStructure,
		Explanation: "Two negatives in one clause cancel in standard English. One is enough -- \"don't have any money\" or \"have no money\".",
	},
}

// The words a second negative turns up as, and what each should have been.
var negativeWords = [][2]string{
	{"nothing", "anything"}, {"nobody", "anybody"}, {"nowhere", "anywhere"},
}

// doubleNegativeTokenRules is one rule for each of negativeWords: a
// replacement cannot be worked out from what matched, only named.
var doubleNegativeTokenRules = func() []TokenRule {
	var rules []TokenRule
	for _, pair := range negativeWords {
		rules = append(rules, TokenRule{
			ID:      "double-negative-" + pair[0],
			Pattern: `don't|doesn't|didn't|can't|couldn't|won't|wouldn't|haven't|hasn't|hadn't|isn't|aren't|wasn't|weren't <VB*>? <RB>? ( ` + pair[0] + ` )`,
			Flags:   []string{"She didn't say " + pair[0] + "."},
			Leaves:  []string{"She didn't say " + pair[1] + ".", "I didn't go, but " + pair[0] + " happened."},
			Message: "Two negatives: should be \"" + pair[1] + "\"", Suggest: []string{pair[1]},
			Category:    catStructure,
			Explanation: "Two negatives in one clause cancel in standard English: \"didn't say nothing\" says that something was said. One negative is enough -- \"didn't say anything\" or \"said nothing\".",
		})
	}
	return rules
}()
