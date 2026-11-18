package spellcheck

// tokenrules_verbs.go: which form a verb takes after the word before it.

const (
	explainAfterModal     = "After \"can\", \"will\", \"should\", \"must\" and the other verbs like them, the verb that follows is in its plain form, with no ending and no \"to\": \"can go\", \"should have\", \"will be\"."
	explainAfterDo        = "\"Do\", \"does\" and \"did\" carry the tense themselves, so the verb that follows stays in its plain form: \"didn't go\", not \"didn't went\"; \"did you see\", not \"did you saw\"."
	explainParticipleForm = "After \"have\", \"has\" or \"had\", and after \"is\" or \"was\" in the passive, a verb takes its participle. For most verbs that is the same as the past -- \"walked\" -- but some have a form of their own: \"went\" but \"have gone\", \"wrote\" but \"was written\"."
	explainBareParticiple = "\"$2\" is the form that follows \"have\" or \"has\". On its own after a subject it needs one of those in front of it, or it should be the simple past."
	explainAfterTo        = "After \"to\", a verb is in its plain form: \"to go\", \"to buy\", \"to dance\"."
	explainNeedsBe        = "A verb ending in -ing needs a form of \"be\" in front of it to make a sentence: \"I am going\", \"he is waiting\", \"they are playing\"."
	explainNeedsTo        = "\"Want\", \"need\", \"hope\", \"plan\" and the verbs like them are followed by \"to\" and then the next verb: \"want to go\", \"needs to buy\"."
	explainIngAfter       = "After a preposition, and after verbs such as \"enjoy\", \"avoid\" and \"finish\", a verb takes its -ing form: \"look forward to meeting\", \"enjoys swimming\", \"thank you for helping\"."
	explainPastTime       = "The sentence names a time in the past, so the verb is in the past too."
)

// asNoun is where a word that looks like "will" or "can" is the noun: after
// a word that introduces one.
const asNoun = `<DT>|<PRP$>|<JJ>|<POS> will|can|might|must <_>{0,1} <_>`

// relative is a verb that belongs to an earlier noun, with a whole clause
// between: "the car I have broke down".
const relative = `<NN*>|<NNP>|that|which|what|all|everything|whatever <_>{0,3} {subj}|<NNP> <_> <_>{0,1} <_>`

var tenseTokenRules = []TokenRule{
	{
		ID:      "yesterday-present",
		Pattern: `^ yesterday ,? {subj} ( <VB>&!<~VBD>&!<~MD> )`,
		Flags:   []string{"Yesterday I go to the cinema."},
		Leaves:  []string{"Yesterday I went to the cinema.", "Yesterday I put it away."},
		Message: "Should be \"$4:VBD\"", Suggest: []string{"$4:VBD"},
		Category: catGrammar, Explanation: explainPastTime,
	},
	{
		ID:      "last-week-present",
		Pattern: `^ last night|week|month|year|time|summer|winter|{weekday} ,? {subj} ( <VB>&!<~VBD>&!<~MD> )`,
		Flags:   []string{"Last week she visit her mother."},
		Leaves:  []string{"Last week she visited her mother."},
		Message: "Should be \"$5:VBD\"", Suggest: []string{"$5:VBD"},
		Category: catGrammar, Explanation: explainPastTime,
	},
}

var verbFormTokenRules = []TokenRule{
	// --- after a modal ---
	{
		ID:      "modal-wrong-form",
		Pattern: `{modal}&!#proper <=RB>? ( <=VBZ|VBD|VBG>&!<~VB>&!<~JJ>&!<~NN*> )`,
		Except:  []string{asNoun, `^ may|will <_>{0,1} <_>`, `might makes`},
		Flags: []string{"I can goes there tomorrow.", "She can sings very well.",
			"You should went to the doctor.", "We will going to the beach.", "She might has forgotten."},
		Leaves: []string{"I can go there.", "Her will stated that everything went to charity.",
			"Will went home.", "Might makes right."},
		Message: "Should be \"$1 $3:VB\"", Suggest: []string{"$3:VB"},
		Category: catGrammar, Explanation: explainAfterModal,
	},
	{
		ID:      "modal-to",
		Pattern: `{subj} can|could|should|would|must|might|will|shall|may ( to <VB> )`,
		Except:  []string{`what|all|everything|whatever|anything|much|best|more <_>{0,2} can|could|should|must|will|would|might|may <_> <_>`},
		Flags:   []string{"He must to finish the report.", "I can to swim.", "She must to go now."},
		Leaves:  []string{"He must finish the report.", "Do what you can to help."},
		Message: "No \"to\" after \"$2\"", Suggest: []string{"$4"},
		Category: catGrammar, Explanation: explainAfterModal,
	},

	// --- after do ---
	{
		ID:      "didnt-past",
		Pattern: `didn't|doesn't|don't <=RB>? ( <=VBD|VBZ>&!<~VB> )`,
		Flags:   []string{"He didn't went to the party.", "She didn't knew the answer.", "I didn't saw anything."},
		Leaves:  []string{"He didn't go.", "He didn't put it back."},
		Message: "Should be \"$1 $3:VB\"", Suggest: []string{"$3:VB"},
		Category: catGrammar, Explanation: explainAfterDo,
	},
	{
		ID:      "did-not-past",
		Pattern: `did|does|do not ( <=VBD|VBZ>&!<~VB> )`,
		Flags:   []string{"He did not went to the party."},
		Leaves:  []string{"He did not go."},
		Message: "Should be \"$1 not $3:VB\"", Suggest: []string{"$3:VB"},
		Category: catGrammar, Explanation: explainAfterDo,
	},
	{
		ID:      "did-you-past",
		Pattern: `did|does|do|didn't|doesn't|don't&!#proper {subj} <=RB>? ( <=VBD|VBZ>&!<~VB> )`,
		Except:  []string{`what|whatever|that|which|everything|all|anything|as|than <_>{0,3} did|does|do <_>{0,2} <_>`},
		Flags:   []string{"Did you saw the news?", "Did he went home?"},
		Leaves:  []string{"Did you see the news?", "What I did you saw for yourself."},
		Message: "Should be \"$4:VB\"", Suggest: []string{"$4:VB"},
		Category: catGrammar, Explanation: explainAfterDo,
	},

	// --- after have and be ---
	{
		ID:      "have-past",
		Pattern: `have|has|had|haven't|hasn't|hadn't|'ve <=RB>? ( <=VBD>&!<~VBN>&!<~JJ>&!was|were|had )`,
		Except:  []string{relative},
		Flags: []string{"I have went to the shop.", "She has ate all the cake.", "He has wrote a long letter.",
			"They have took the money.", "I have saw that film.", "We have did it already."},
		Leaves:  []string{"I have gone to the shop.", "The car I have broke down.", "What I have was lost."},
		Message: "Should be \"$1 $3:VBN\"", Suggest: []string{"$3:VBN"},
		Category: catGrammar, Explanation: explainParticipleForm,
	},
	{
		ID:      "was-broke",
		Pattern: `<NN> was|is|got ( wrote|stole|took|gave|chose|ate|drove|rode|tore|wore|froze|spoke|forgot|hid|bit|drew|threw|flew|grew|knew|shook|sang|rang|swam|drank|began )`,
		Flags:   []string{"The letter was wrote by him."},
		Leaves:  []string{"The letter was written by him."},
		Message: "Should be \"$2 $3:VBN\"", Suggest: []string{"$3:VBN"},
		Category: catGrammar, Explanation: explainParticipleForm,
	},
	{
		ID:      "window-was-broke",
		Pattern: `the|a|this|that|my|your|his|her|our|their window|glass|door|vase|car|phone|machine|chair|table|lock|screen|cup|plate|toy|leg|arm ( was|is|got broke )`,
		Flags:   []string{"The window was broke."},
		Leaves:  []string{"The window was broken.", "He was broke."},
		Message: "Should be \"$3 broken\"", Suggest: []string{"$3 broken"},
		Category: catGrammar, Explanation: explainParticipleForm,
	},
	{
		ID:      "be-past",
		Pattern: `{subj} am|is|are|was|were|'m|'re <=RB>? ( <=VBD>&!<~VBN>&!<~JJ>&!was|were|had|did )`,
		Flags:   []string{"She was went to the market.", "He was ran very fast."},
		Leaves:  []string{"She went to the market.", "She was gone."},
		Message: "\"$4\" cannot follow \"$2\"", Suggest: []string{"$4:VBN"},
		Category:    catGrammar,
		Explanation: "\"$4\" is already the past of its verb, and does not take \"$2\" in front of it. Either the one word is enough -- \"she went\" -- or the form after \"$2\" should be the participle.",
	},

	// --- a participle with nothing in front of it ---
	{
		ID:      "i-seen",
		Pattern: `i|we|they&#clause ( {participle} )`,
		Flags:   []string{"I seen him yesterday.", "I done my homework already."},
		Leaves:  []string{"I have seen him.", "Have they gone?", "The film we seen"},
		Message: "\"$2\" needs \"have\" before it", Suggest: []string{"have $2", "$2:VBD"},
		Category: catGrammar, Explanation: explainBareParticiple,
	},
	{
		ID:      "he-seen",
		Pattern: `he|she&#clause ( {participle} )`,
		Flags:   []string{"He seen it happen."},
		Leaves:  []string{"He has seen it.", "Has she gone?"},
		Message: "\"$2\" needs \"has\" before it", Suggest: []string{"has $2", "$2:VBD"},
		Category: catGrammar, Explanation: explainBareParticiple,
	},
	{
		ID:      "i-been",
		Pattern: `i|we|they|you&#clause ( been )`,
		Flags:   []string{"We been waiting for hours.", "I been there before."},
		Leaves:  []string{"We have been waiting.", "Have you been there?"},
		Message: "Should be \"$1 have been\"", Suggest: []string{"have been"},
		Category: catGrammar, Explanation: explainBareParticiple,
	},
	{
		ID:      "he-been",
		Pattern: `he|she|it&#clause ( been )`,
		Flags:   []string{"He been here all day."},
		Leaves:  []string{"He has been here all day."},
		Message: "Should be \"$1 has been\"", Suggest: []string{"has been"},
		Category: catGrammar, Explanation: explainBareParticiple,
	},

	// --- after to ---
	{
		ID:      "to-past",
		Pattern: `{wantto}|how|order|time|way|chance|right to ( <=VBD|VBZ>&!<~VB> )`,
		Flags:   []string{"I want to went home.", "He wants to buys a house."},
		Leaves:  []string{"I want to go home.", "He wants to buy a house."},
		Message: "Should be \"to $3:VB\"", Suggest: []string{"$3:VB"},
		Category: catGrammar, Explanation: explainAfterTo,
	},
	{
		ID:      "want-to-ing",
		Pattern: `want|wants|wanted|need|needs|needed|like|likes|liked|love|loves|loved|hate|hates|hated|try|tries|tried|decide|decided|hope|hopes|hoped|plan|planned|learn|learned|able|unable|ought to ( <~VBG>&!<~VB> )`,
		Flags:   []string{"She likes to dancing."},
		Leaves:  []string{"She likes to dance.", "I look forward to meeting you.", "He is used to living alone."},
		Message: "Should be \"to $3:VB\"", Suggest: []string{"$3:VB"},
		Category: catGrammar, Explanation: explainAfterTo,
	},
	{
		ID:      "want-go",
		Pattern: `{subj}|<NNP>|to|not|don't|didn't|doesn't|really|just|also|always|never want|wants|wanted|need|needs|needed|decided|hope|hopes|hoped|trying|tried|plan|plans|planned ( <=VB>&!be|do|help|have )`,
		Flags:   []string{"I want go home.", "She needs buy milk."},
		Leaves:  []string{"I want to go home.", "All you need do is ask.", "If need be, we will."},
		Message: "Should be \"$2 to $3\"", Suggest: []string{"to $3"},
		Category: catGrammar, Explanation: explainNeedsTo,
	},
	{
		ID:      "like-listen",
		Pattern: `i|we|they|you like|love|hate|prefer ( <=VB>&!be|do ) =>to|<DT>|<PRP$>|<IN>|<RB>`,
		Flags:   []string{"I like listen to music."},
		Leaves:  []string{"I like to listen to music.", "I like listening to music."},
		Message: "Should be \"$2 to $3\" or \"$2 $3:VBG\"", Suggest: []string{"to $3", "$3:VBG"},
		Category: catGrammar, Explanation: explainNeedsTo,
	},

	// --- is work, I going ---
	{
		ID:      "am-agree",
		Pattern: `i|he|she|we|they|you ( am|is|are|was|were|'m|'re <=VB>&!<~JJ*>&!<~NN*>&!<~VBN>&!<~RB>&!<~IN>&!go|come|become )`,
		Flags:   []string{"I am agree with you."},
		Leaves:  []string{"I agree with you.", "I am happy with you."},
		Message: "\"$2\" does not go before \"$3\"", Suggest: []string{"$3", "$2 $3:VBG"},
		Category:    catGrammar,
		Explanation: "\"$3\" is a verb, and a verb in this form does not take \"$2\" in front of it. Either the verb stands alone -- \"I agree\" -- or it is something in progress and ends in -ing.",
	},
	{
		ID:      "is-work",
		Pattern: `i|he|she|we|they am|is|are|was|were|'m|'re ( {action}&!<~VBN> ) =>at|in|on|with|for|to|the|a|an|my|his|her|our|their|now|here|there|today|football|tennis|music|tv`,
		Flags:   []string{"She is work at a bank.", "They are play football now."},
		Leaves:  []string{"She is working at a bank.", "They are playing football now."},
		Message: "Should be \"$2 $3:VBG\"", Suggest: []string{"$3:VBG"},
		Category: catGrammar, Explanation: explainNeedsBe,
	},
	{
		ID:      "i-going",
		Pattern: `( i|he|she|we|they&#clause ) <RB>? <~VBG>&!<~VB>&!being|having|according|regarding|including|considering|concerning|during|nothing|something|anything|everything`,
		Flags:   []string{"I going to the store.", "He going to be late.", "I looking for my keys.", "We waiting for the bus."},
		Leaves:  []string{"I am going to the store.", "Are they going?", "He being the eldest, he went first."},
		Message: "Should be \"$1 $1:BE $3\"", Suggest: []string{"$1 $1:BE"},
		Category: catGrammar, Explanation: explainNeedsBe,
	},

	// --- -ing after a preposition, and after some verbs ---
	{
		ID:      "forward-to-meet",
		Pattern: `look|looks|looked|looking forward to ( <=VB> )`,
		Flags:   []string{"I look forward to meet you."},
		Leaves:  []string{"I look forward to meeting you.", "I look forward to it."},
		Message: "Should be \"to $4:VBG\"", Suggest: []string{"$4:VBG"},
		Category: catGrammar, Explanation: explainIngAfter,
	},
	{
		ID:      "enjoy-to",
		Pattern: `enjoy|enjoys|enjoyed|enjoying|avoid|avoids|avoided|finish|finished|dislike|dislikes|disliked ( to <VB> )`,
		Flags:   []string{"He enjoys to swim."},
		Leaves:  []string{"He enjoys swimming."},
		Message: "Should be \"$1 $3:VBG\"", Suggest: []string{"$3:VBG"},
		Category: catGrammar, Explanation: explainIngAfter,
	},
	{
		ID:      "thanks-for-help",
		Pattern: `thank|thanks you? for ( <~VB>&!<~VBG>&!<~DT> ) =>me|us|him|her|them`,
		Flags:   []string{"Thank you for help me."},
		Leaves:  []string{"Thank you for helping me.", "Thanks for the help."},
		Message: "Should be \"for $4:VBG\"", Suggest: []string{"$4:VBG"},
		Category: catGrammar, Explanation: explainIngAfter,
	},
	{
		ID:      "good-at-play",
		Pattern: `good|bad|great|better|best|terrible|brilliant|hopeless at ( {action} )`,
		Flags:   []string{"She is good at play piano."},
		Leaves:  []string{"She is good at playing piano.", "She is good at chess."},
		Message: "Should be \"at $3:VBG\"", Suggest: []string{"$3:VBG"},
		Category: catGrammar, Explanation: explainIngAfter,
	},
	{
		ID:      "used-to-get",
		Pattern: `i|we|he|she am|'m|is|'s|are|'re|was|were|got|get used to ( <=VB>&!be|have )`,
		Flags:   []string{"I am used to get up early."},
		Leaves:  []string{"I am used to getting up early.", "I used to get up early."},
		Message: "Should this be \"$5:VBG\"?", Suggest: []string{"$5:VBG"},
		Category: "Possible confusion", Severity: SeverityCheck,
		Explanation: "\"Used to\" means two things. \"I used to get up early\" is something that was once true. \"I am used to getting up early\" is something that no longer feels strange -- and that one, with \"am\" before it, takes the -ing form.",
	},
	{
		ID:      "insist-to",
		Pattern: `insist|insists|insisted ( to <VB> )`,
		Flags:   []string{"He insisted to pay."},
		Leaves:  []string{"He insisted on paying."},
		Message: "Should be \"$1 on $3:VBG\"", Suggest: []string{"on $3:VBG"},
		Category: catGrammar, Explanation: explainIngAfter,
	},

	// --- let, make ---
	{
		ID:      "let-him-goes",
		Pattern: `let|lets|make|makes|made|help|helps|helped me|you|him|her|us|them|it ( <=VBZ>&!is|has )`,
		Flags:   []string{"Let him goes."},
		Leaves:  []string{"Let him go."},
		Message: "Should be \"$1 $2 $3:VB\"", Suggest: []string{"$3:VB"},
		Category:    catGrammar,
		Explanation: "After \"let\", \"make\" or \"help\" and the person they act on, the verb is in its plain form: \"let him go\", \"made me laugh\".",
	},
	{
		ID:      "made-me-to",
		Pattern: `let|lets|made|make|makes me|him|her|us|them ( to <VB> )`,
		Flags:   []string{"She made me to cry."},
		Leaves:  []string{"She made me cry.", "He made it to work on time."},
		Message: "No \"to\" after \"$1 $2\"", Suggest: []string{"$4"},
		Category:    catGrammar,
		Explanation: "After \"let\" or \"make\" and the person they act on, the verb follows directly, with no \"to\": \"made me cry\", \"let us go\".",
	},
}
