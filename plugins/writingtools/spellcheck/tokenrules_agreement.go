package spellcheck

// tokenrules_agreement.go: a subject and its verb, and a noun and the word
// that counts it.

const (
	catGrammar = "Grammar"

	explainThirdPerson = "After \"he\", \"she\", \"it\" or one person or thing, a verb in the present takes an -s: \"he goes\", \"she walks\", \"the car needs\". Without it the verb is in the form used after \"I\", \"you\", \"we\" and \"they\"."
	explainNoThirdS    = "The -s form of a verb goes with \"he\", \"she\", \"it\" or one person or thing. After \"I\", \"you\", \"we\", \"they\" or more than one, the verb has no -s: \"they go\", \"we have\"."
	explainBeAgreement = "\"Is\" and \"was\" go with one person or thing; \"are\" and \"were\" go with more than one, and with \"you\". \"I\" takes \"am\" and \"was\"."
	explainThereIs     = "\"There is\" and \"there are\" agree with what follows them: \"there is a reason\", \"there are many reasons\"."
	explainEachOf      = "\"Each\", \"every one\" and \"one of\" are about a single person or thing, whatever plural follows, so the verb is singular: \"each of the students has a book\"."
	explainThisThese   = "\"This\" and \"that\" point at one thing, \"these\" and \"those\" at more than one, and the noun and the verb agree with them: \"this book is\", \"these books are\"."
)

// andBefore is the exception every rule about a singular subject and a
// plural verb needs: "he and she are" has a plural subject, and the rule
// sees only its second half.
const andBefore = `<PRP|NN|NNS|NNP> ,? and|or|nor <_> <_>`

// subjunctive is where "he go" and "she were" are right: after a demand or
// a wish.
const subjunctive = `suggest|suggests|suggested|recommend|recommends|recommended|demand|demands|demanded|insist|insists|insisted|propose|proposed|request|requested|require|requires|required|ask|asks|asked|important|essential|vital|necessary|imperative|crucial|if|wish|wishes|wished|though|suppose|supposing|imagine|whether|unless|lest <_>{0,4} {singular} <_>`

// inverted is a question or a bare infinitive reaching forward over a
// subject: "does he or she go", "let it go and she follow".
const inverted = `do|does|did|can|could|will|would|should|may|might|must|let|lets|make|makes|made|help|helps|helped|see|saw|watch|watched|have|had|hear|heard <_>{0,5} {singular} <_>`

var agreementTokenRules = []TokenRule{
	// --- he go ---
	{
		ID:      "he-base-verb",
		Pattern: `{he}&#clause ( <VB>&<+VB>&!<~VBD>&!<~MD>&![be]&![have]&![do] )`,
		Except:  []string{subjunctive, inverted},
		Flags: []string{"He go to school every day.", "She walk to work.",
			"It seem like a good plan."},
		Leaves: []string{"He goes to school.", "He put it down.", "She can go.",
			"I suggest that he go home.", "Does he or she go first?",
			"Let it go."},
		Message:     "Should be \"$1 $2:VBZ\"",
		Suggest:     []string{"$2:VBZ"},
		Category:    catGrammar,
		Explanation: explainThirdPerson,
	},
	{
		ID:      "he-have",
		Pattern: `{he}&#clause ( have|do )`,
		Except:  []string{subjunctive, inverted, andBefore},
		Flags:   []string{"He have a new car.", "She have two brothers.", "It have been a long day."},
		Leaves: []string{"Does he have a car?", "He and she have a car.",
			"People who use it have said so."},
		Message:     "Should be \"$1 $2:VBZ\"",
		Suggest:     []string{"$2:VBZ"},
		Category:    catGrammar,
		Explanation: explainThirdPerson,
	},
	{
		ID:          "he-dont",
		Pattern:     `{he}&#clause ( don't )`,
		Except:      []string{andBefore},
		Flags:       []string{"He don't like coffee.", "It don't matter anymore."},
		Leaves:      []string{"He doesn't like coffee.", "They don't like it."},
		Message:     "Should be \"$1 doesn't\"",
		Suggest:     []string{"doesn't"},
		Category:    catGrammar,
		Explanation: explainThirdPerson,
	},
	{
		ID:      "he-are",
		Pattern: `{he}&#clause ( are|am )`,
		Except:  []string{andBefore},
		Flags:   []string{"She are my friend."},
		Leaves:  []string{"He and she are friends.", "Neither you nor he are right.", "She is my friend."},
		Message: "Should be \"$1 is\"", Suggest: []string{"is"},
		Category: catGrammar, Explanation: explainBeAgreement,
	},
	{
		ID:      "he-were",
		Pattern: `i|he|she|it&#clause ( were )`,
		Except:  []string{subjunctive, andBefore},
		Flags:   []string{"She were at home yesterday.", "I were at home yesterday.", "He were very kind to me."},
		Leaves: []string{"If she were here, she would say so.", "I wish I were there.",
			"My friends and I were walking.", "She was at home."},
		Message: "Should be \"$1 was\"", Suggest: []string{"was"},
		Category: catGrammar, Explanation: explainBeAgreement,
	},

	// --- they goes ---
	{
		ID:      "they-is",
		Pattern: `we|they|you&#clause ( is )`,
		Flags:   []string{"They is happy with the result."},
		Leaves:  []string{"They are happy.", "The man beside you is my brother."},
		Message: "Should be \"$1 are\"", Suggest: []string{"are"},
		Category: catGrammar, Explanation: explainBeAgreement,
	},
	{
		ID:      "they-was",
		Pattern: `we|they|you&#clause ( was )`,
		Flags:   []string{"They was happy with the result.", "We was late for the meeting.", "You was right about that."},
		Leaves:  []string{"They were happy.", "The man beside you was my brother."},
		Message: "Should be \"$1 were\"", Suggest: []string{"were"},
		Category: catGrammar, Explanation: explainBeAgreement,
	},
	{
		ID:      "they-isnt",
		Pattern: `we|they|you&#clause ( isn't )`,
		Flags:   []string{"They isn't coming."},
		Message: "Should be \"$1 aren't\"", Suggest: []string{"aren't"},
		Category: catGrammar, Explanation: explainBeAgreement,
	},
	{
		ID:      "they-wasnt",
		Pattern: `we|they|you&#clause ( wasn't )`,
		Flags:   []string{"We wasn't ready."},
		Message: "Should be \"$1 weren't\"", Suggest: []string{"weren't"},
		Category: catGrammar, Explanation: explainBeAgreement,
	},
	{
		ID:      "i-is",
		Pattern: `i&#clause ( is|are )`,
		Except:  []string{andBefore},
		Flags:   []string{"I is tired today."},
		Leaves:  []string{"The letter I is a vowel.", "You and I are friends."},
		Message: "Should be \"I am\"", Suggest: []string{"am"},
		Category: catGrammar, Explanation: explainBeAgreement,
	},
	{
		ID:      "they-has",
		Pattern: `{they}&#clause ( has|does )`,
		Flags:   []string{"I has a question.", "They has finished the work.", "We has been waiting for an hour."},
		Leaves:  []string{"They have finished.", "The one with you has finished."},
		Message: "Should be \"$1 $2:VB\"", Suggest: []string{"$2:VB"},
		Category: catGrammar, Explanation: explainNoThirdS,
	},
	{
		ID:      "they-doesnt",
		Pattern: `{they}&#clause ( doesn't )`,
		Flags:   []string{"They doesn't know."},
		Message: "Should be \"$1 don't\"", Suggest: []string{"don't"},
		Category: catGrammar, Explanation: explainNoThirdS,
	},
	{
		ID:      "they-verbs",
		Pattern: `i|we|they&#clause ( <VBZ>&<+VBZ>&![be]&![have]&![do] )`,
		Flags:   []string{"They goes to school."},
		Leaves:  []string{"They go to school.", "We students know this.", "They say he lives in London."},
		Message: "Should be \"$1 $2:VB\"", Suggest: []string{"$2:VB"},
		Category: catGrammar, Explanation: explainNoThirdS,
	},
	{
		// The same, for a word that is as often a plural noun -- "lives",
		// "works" -- where what follows shows it is the verb.
		ID:      "they-verbs-before",
		Pattern: `i|we|they&#clause ( <~VBZ>&![be]&![have]&![do] ) =>in|at|on|to|with|for|the|a|an|my|our|their|his|her`,
		Flags:   []string{"We lives in London."},
		Leaves:  []string{"We live in London.", "We students of history know this."},
		Message: "Should be \"$1 $2:VB\"", Suggest: []string{"$2:VB"},
		Category: catGrammar, Explanation: explainNoThirdS,
	},

	// --- does they, do he ---
	{
		ID:      "does-they",
		Pattern: `( does|doesn't ) {they}`,
		Flags:   []string{"Does they know about it?", "Where does they live?"},
		Leaves:  []string{"Do they know about it?", "What he does they ignore."},
		Except:  []string{`what|whatever|that|which|who|everything|all|anything <_>{0,3} does <_>`},
		Message: "Should be \"$1:VB $2\"", Suggest: []string{"$1:VB"},
		Category: catGrammar, Explanation: explainNoThirdS,
	},
	{
		ID:      "do-he",
		Pattern: `( do|don't&#clause ) he|she`,
		Flags:   []string{"Do he know about it?"},
		Leaves:  []string{"Does he know?", "What they do he ignores.", "As I do she does."},
		Message: "\"$1\" does not go with \"$2\"", Suggest: []string{"does"},
		Category: catGrammar, Explanation: explainThirdPerson,
	},
	{
		ID:      "what-do-he",
		Pattern: `what|where|when|why|how|who ( do ) he|she|it`,
		Flags:   []string{"What do she want?"},
		Leaves:  []string{"What does she want?"},
		Message: "Should be \"does $3\"", Suggest: []string{"does"},
		Category: catGrammar, Explanation: explainThirdPerson,
	},

	// --- a noun and its verb ---
	{
		ID:      "plural-is",
		Pattern: `^ <DT>|<PRP$> <JJ>? <=NNS>&#lower ( is|has|does )`,
		Flags:   []string{"The dogs is barking loudly.", "The people is angry about it."},
		Leaves:  []string{"The dogs are barking.", "The news is good.", "The series is long.", "The dog's owner is here."},
		Message: "Should be \"$3 $4:VBP\"", Suggest: []string{"$4:VBP"},
		Category: catGrammar, Explanation: explainBeAgreement,
	},
	{
		ID:      "plural-was",
		Pattern: `^ <DT>|<PRP$> <JJ>? <=NNS>&#lower ( was )`,
		Flags:   []string{"The dogs was barking."},
		Leaves:  []string{"The dogs were barking."},
		Message: "Should be \"$3 were\"", Suggest: []string{"were"},
		Category: catGrammar, Explanation: explainBeAgreement,
	},
	{
		ID:      "plural-verbs",
		Pattern: `^ <DT>|<PRP$> <JJ>? <=NNS>&#lower ( <~VBZ>&![be]&![have]&![do] ) =><DT>|<IN>|<PRP$>|<RB>|<TO>`,
		Flags:   []string{"My friends lives in London.", "The children plays in the park."},
		Leaves:  []string{"My friends live in London.", "The children play in the park."},
		Message: "Should be \"$3 $4:VB\"", Suggest: []string{"$4:VB"},
		Category: catGrammar, Explanation: explainNoThirdS,
	},
	{
		ID:      "singular-are",
		Pattern: `^ the|a|an|this|that|my|your|his|her|its|our|their <JJ>? <=NN>&!{collective}&!{invariant}&!/\w+s/&#lower ( are|have )`,
		Flags:   []string{"The dog are barking loudly."},
		Leaves: []string{"The dog is barking.", "The team are playing well.", "The rest are here.",
			"The dog and the cat are friends.", "The police are here."},
		Message: "Should be \"$3 $4:VBZ\"", Suggest: []string{"$4:VBZ"},
		Category: catGrammar, Explanation: explainBeAgreement,
	},
	{
		ID:      "singular-were",
		Pattern: `^ the|a|an|this|that|my|your|his|her|its|our|their <JJ>? <=NN>&!{collective}&!{invariant}&!/\w+s/&#lower ( were )`,
		Except:  []string{subjunctive},
		Flags:   []string{"The dog were barking."},
		Leaves:  []string{"The dog was barking.", "The team were playing."},
		Message: "Should be \"$3 was\"", Suggest: []string{"was"},
		Category: catGrammar, Explanation: explainBeAgreement,
	},
	{
		ID:      "singular-verbs",
		Pattern: `^ the|a|an|this|that|my|your|his|her|its|our|their <JJ>? <=NN>&!{collective}&!{invariant}&#lower ( <+VB>&!<~VBD>&!<~MD>&!<~IN>&![be]&![have]&![do] ) =>a|an|the|my|your|his|her|our|their|very`,
		Flags:   []string{"The car need a new battery."},
		Leaves: []string{"The car needs a new battery.", "The school run a tight ship.",
			"The fish need a bigger tank."},
		Message: "Should be \"$3 $4:VBZ\"", Suggest: []string{"$4:VBZ"},
		Category: catGrammar, Explanation: explainThirdPerson,
	},
	{
		ID:      "this-make",
		Pattern: `^ this|that ( <VB>&!<~VBD>&!<~VBN>&!<~MD>&!<~NN*>&!<~JJ>&![be]&![have]&![do] )`,
		Flags:   []string{"This seem wrong."},
		Leaves:  []string{"This makes me happy.", "That will do."},
		Message: "Should be \"$1 $2:VBZ\"", Suggest: []string{"$2:VBZ"},
		Category: catGrammar, Explanation: explainThirdPerson,
	},
	{
		ID:      "this-verb-me",
		Pattern: `^ this|that ( <~VB>&!<~VBD>&!<~VBN>&!<~MD>&!<~IN>&![be]&![have]&![do] ) =>me|us|him|her|them|like`,
		Flags:   []string{"That sound like a good idea."},
		Leaves:  []string{"This makes me very happy.", "That sounds like a good idea."},
		Message: "Should be \"$1 $2:VBZ\"", Suggest: []string{"$2:VBZ"},
		Category: catGrammar, Explanation: explainThirdPerson,
	},

	// --- there is, there are ---
	{
		ID:      "there-is-many",
		Pattern: `there ( is ) many|several|numerous|multiple|various|two|three|four|five|six|seven|eight|nine|ten`,
		Flags:   []string{"There is many reasons for this."},
		Leaves:  []string{"There are many reasons for this.", "There is some milk."},
		Message: "Should be \"there are\"", Suggest: []string{"are"},
		Category: catGrammar, Explanation: explainThereIs,
	},
	{
		ID:      "there-was-many",
		Pattern: `there ( was ) many|several|numerous|multiple|various|two|three|four|five|six|seven|eight|nine|ten`,
		Flags:   []string{"There was many people at the party."},
		Leaves:  []string{"There were many people."},
		Message: "Should be \"there were\"", Suggest: []string{"were"},
		Category: catGrammar, Explanation: explainThereIs,
	},
	{
		ID:      "there-is-plural",
		Pattern: `there ( is ) <JJ>? <=NNS>&!lots|tons|loads|heaps|thanks&#lower !><~NN*>`,
		Flags:   []string{"There is dogs in the garden."},
		Leaves:  []string{"There are dogs in the garden.", "There is lots to do.", "There is news."},
		Message: "Should be \"there are\"", Suggest: []string{"are"},
		Category: catGrammar, Explanation: explainThereIs,
	},
	{
		ID:      "there-are-a",
		Pattern: `there ( are ) a|an|one <JJ>? <=NN>&!{collective}&!{invariant}&#lower`,
		Flags:   []string{"There are a reason for this."},
		Leaves:  []string{"There is a reason for this.", "There are a number of reasons.", "There are a lot of them.", "There are a few left."},
		Message: "Should be \"there is\"", Suggest: []string{"is"},
		Category: catGrammar, Explanation: explainThereIs,
	},

	// --- everyone, each of ---
	{
		ID:      "everyone-are",
		Pattern: `everyone|everybody|someone|somebody|anyone|anybody|nobody|everything|something|nothing|anything&#clause ( are|have )`,
		Except:  []string{andBefore, subjunctive},
		Flags:   []string{"Everyone are welcome to join."},
		Leaves:  []string{"Everyone is welcome.", "Does everyone have a ticket?", "Everyone and everything are ready."},
		Message: "Should be \"$1 $2:VBZ\"", Suggest: []string{"$2:VBZ"},
		Category: catGrammar, Explanation: "\"Everyone\", \"someone\", \"nobody\" and the words like them each mean one person, however many are in the room, so the verb is singular: \"everyone is\", \"nobody has\".",
	},
	{
		ID:      "each-of-have",
		Pattern: `each|one&#clause of the|these|those|my|your|his|her|our|their <JJ>? <NNS> ( have|are )`,
		Flags:   []string{"Each of the students have a book."},
		Leaves:  []string{"Each of the students has a book.", "Does each of the students have a book?"},
		Message: "Should be \"$6:VBZ\"", Suggest: []string{"$6:VBZ"},
		Category: catGrammar, Explanation: explainEachOf,
	},
	{
		ID:      "noun-of-plural-are",
		Pattern: `^ the|this|that|my|your|his|her|its|our|their <JJ>? <=NN>&!{collective}&!{invariant}&#lower of <DT>|<PRP$>? <JJ>? <NNS> ( are|have )`,
		Flags:   []string{"The price of the tickets are too high."},
		Leaves:  []string{"The price of the tickets is too high.", "The majority of the voters are angry.", "The rest of the tickets are gone."},
		Message: "Should this be \"$8:VBZ\", to agree with \"$3\"?", Suggest: []string{"$8:VBZ"},
		Category: "Possible confusion", Severity: SeverityCheck,
		Explanation: "The verb agrees with the thing the sentence is about -- \"$3\" -- and not with the noun nearest to it. \"The price of the tickets is high\": it is the price that is high.",
	},

	// --- this, these ---
	{
		ID:       "this-are",
		Pattern:  `( this&#clause are )`,
		Flags:    []string{"This are my favourite songs."},
		Leaves:   []string{"These are my favourite songs.", "People who do this are wrong."},
		Message:  "\"This\" is one thing and \"are\" is for several",
		Suggest:  []string{"these are", "this is"},
		Category: catGrammar, Explanation: explainThisThese,
	},
	{
		ID:       "these-is",
		Pattern:  `( these|those&#clause is )`,
		Flags:    []string{"These is the best option."},
		Leaves:   []string{"This is the best option.", "One of these is the best."},
		Message:  "\"$1\" is several things and \"is\" is for one",
		Suggest:  []string{"$1 are", "this is"},
		Category: catGrammar, Explanation: explainThisThese,
	},
	{
		ID:      "this-plural-are",
		Pattern: `( this ) <=NNS>&#lower =>are|were|have`,
		Flags:   []string{"This lines are too long."},
		Leaves:  []string{"These lines are too long.", "This lines up with what he said."},
		Message: "Should be \"these $2\"", Suggest: []string{"these"},
		Category: catGrammar, Explanation: explainThisThese,
	},
	{
		ID:      "this-plural",
		Pattern: `( this ) <=NNS>&!<~VBZ>&#lower !><~NN*>|'s|'|<~JJ>`,
		Flags:   []string{"I bought this cars."},
		Leaves:  []string{"I bought these cars.", "This means war.", "This sports car is fast."},
		Message: "Should be \"these $2\"", Suggest: []string{"these"},
		Category: catGrammar, Explanation: explainThisThese,
	},
	{
		ID:      "these-singular",
		Pattern: `these|those ( <=NN>&!{invariant}&!{collective}&!<~NNS>&#lower ) !><~NN*>|'s|'|<~JJ>|<VBG>`,
		Flags:   []string{"These book are mine.", "Those car are fast."},
		Leaves:  []string{"These books are mine.", "Those fish are fresh.", "Those present agreed.", "These car parks are full."},
		Message: "Should be \"$1 $2:NNS\"", Suggest: []string{"$2:NNS"},
		Category: catGrammar, Explanation: explainThisThese,
	},
}
