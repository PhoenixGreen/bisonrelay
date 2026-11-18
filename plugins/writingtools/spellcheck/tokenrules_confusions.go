package spellcheck

// tokenrules_confusions.go: the confusable pairs that grammar can settle.
//
// Most pairs are left to the counts -- see data/confusion-sets.txt -- which
// know far more contexts than anyone could write out. These are the cases
// where the position alone decides it and no count is needed: "then" after a
// comparative, "to" before an adjective, "meat" before a person.
//
// Each replaces a regular expression that was retired because it marked
// correct writing. The difference is that these can say what kind of word
// stands next to the one in question, which is what the old ones were
// guessing at with lists.

const catConfused = "Confused words"

var confusionTokenRules = []TokenRule{
	{
		ID:      "comparative-then",
		Pattern: `<=JJR>|more|less|rather|other|better|worse ( then ) =>me|him|her|us|them|you|i|he|she|we|they|ever|usual|expected|before|that|this|<CD>|<NNP>|a|an|the|my|your|his|our|their`,
		Flags:   []string{"He is taller then me.", "She is better then her sister."},
		Leaves:  []string{"He is taller than me.", "It got better, then worse."},
		Message: "Did you mean \"$1 than\"?", Suggest: []string{"than"},
		Category: "Possible confusion", Severity: SeverityCheck,
		Explanation: "\"Than\" compares: \"taller than me\". \"Then\" is about time: \"first this, then that\".",
	},
	{
		ID:      "to-adjective-to",
		Pattern: `am|is|are|was|were|'m|'s|'re|be|been|feel|feels|felt|looks|seems|got ( to ) <~JJ>&!<~VB> =>to|for|and|.|,|!`,
		Flags:   []string{"I am to tired to work."},
		Leaves:  []string{"I am too tired to work.", "He is to listen to it.", "I am to go to London."},
		Message: "Should be \"too $3\"", Suggest: []string{"too"},
		Category:    catConfused,
		Explanation: "\"Too\" means more than is wanted: \"too tired\", \"too late\". \"To\" goes before a verb or a place.",
	},
	{
		ID:      "be-quite",
		Pattern: `be|keep|stay|kept|stayed ( quite ) !>#word`,
		Flags:   []string{"Please be quite."},
		Leaves:  []string{"Please be quiet.", "It can be quite rich."},
		Message: "Should be \"$1 quiet\"", Suggest: []string{"quiet"},
		Category:    catConfused,
		Explanation: "\"Quiet\" means making little noise. \"Quite\" means fairly or completely, and goes before another word: \"quite good\".",
	},
	{
		ID:      "be-quite-in",
		Pattern: `be|keep|stay|kept|stayed ( quite ) in|at|during the|this|that|class library|classroom|class|cinema|theatre|theater|church|hospital|house|room|car|back|meeting|lesson`,
		Flags:   []string{"Please be quite in the library."},
		Leaves:  []string{"Please be quiet in the library.", "He was quite in the dark about it."},
		Message: "Should be \"$1 quiet\"", Suggest: []string{"quiet"},
		Category:    catConfused,
		Explanation: "\"Quiet\" means making little noise. \"Quite\" means fairly or completely, and goes before another word: \"quite good\".",
	},
	{
		ID:      "want-to-by",
		Pattern: `want|wants|wanted|need|needs|needed|going|like|trying|able|plan to ( by ) =>a|an|some|it|them|one|more|this|that|my|your|his|her|our|their|new|<CD>`,
		Flags:   []string{"I need to by some milk."},
		Leaves:  []string{"I need to buy some milk.", "What you need to by Friday is a plan."},
		Message: "Should be \"to buy\"", Suggest: []string{"buy"},
		Category:    catConfused,
		Explanation: "To \"buy\" is to pay for something. \"By\" is the preposition: \"by the door\", \"by Friday\".",
	},
	{
		ID:      "board-with",
		Pattern: `am|is|are|was|were|'m|'re|get|got|getting|so|very|really ( board ) =>with|of|by|.|,|!|and`,
		Flags:   []string{"I am board with this game."},
		Leaves:  []string{"I am bored with this game.", "He was board certified.", "They are board members."},
		Message: "Should be \"bored\"", Suggest: []string{"bored"},
		Category:    catConfused,
		Explanation: "\"Bored\" is how somebody with nothing to do feels. A \"board\" is a plank, or the people who run a company.",
	},
	{
		ID:      "meat-you",
		Pattern: `( meat ) you|me|him|her|us|them|up`,
		Flags:   []string{"I will meat you at noon."},
		Leaves:  []string{"I will meet you at noon.", "A companion to meat dishes"},
		Message: "Should be \"meet\"", Suggest: []string{"meet"},
		Category:    catConfused,
		Explanation: "To \"meet\" is to come together with somebody. \"Meat\" is food.",
	},
	{
		ID:      "an-affect-on",
		Pattern: `a|an|the|no|any|big|huge|major|great|little|negative|positive|significant|same|side|net|lasting|profound ( affect ) =>on|of|upon|.|,`,
		Flags:   []string{"It had a big affect on me."},
		Leaves:  []string{"It had a big effect on me.", "Variants that affect the response"},
		Message: "Should be \"effect\"", Suggest: []string{"effect"},
		Category:    catConfused,
		Explanation: "\"Effect\" is the noun: a result. \"Affect\" is the verb: to have a result on something. \"The rain will affect the game\"; \"the rain had an effect on the game\".",
	},
	{
		ID:      "will-effect",
		Pattern: `will|would|can|could|may|might|won't|doesn't|didn't|don't|not|to|it ( effect ) =>the|a|an|my|your|his|her|our|their|me|you|him|us|them|how|what|everyone`,
		Except:  []string{`to effect change|changes|a`},
		Flags:   []string{"The rain will effect the game."},
		Leaves:  []string{"The rain will affect the game.", "It took effect the next day."},
		Message: "Did you mean \"affect\"?", Suggest: []string{"affect"},
		Category: "Possible confusion", Severity: SeverityCheck,
		Explanation: "\"Affect\" is the verb: to have a result on something. \"Effect\" is the noun, the result itself -- and as a verb only in \"effect a change\", to bring one about.",
	},
	{
		ID:      "their-at-end",
		Pattern: `( their ) =>.|,|!|;`,
		Except:  []string{`than|as|of|like their`},
		Flags:   []string{"Wait for me their."},
		Leaves:  []string{"Wait for me there.", "Their car is red."},
		Message: "Should be \"there\"", Suggest: []string{"there"},
		Category:    catConfused,
		Explanation: "\"Their\" means belonging to them and has to be followed by what belongs: \"their car\". The place is \"there\".",
	},
	{
		ID:      "principle-of-the-school",
		Pattern: `( principle ) of the|a|our|my|his|her school|college|academy|university`,
		Flags:   []string{"The principle of the school spoke."},
		Leaves:  []string{"The principal of the school spoke.", "The principle of the thing"},
		Message: "Should be \"principal\"", Suggest: []string{"principal"},
		Category:    catConfused,
		Explanation: "The \"principal\" is the head of a school. A \"principle\" is a rule or a belief.",
	},
	{
		ID:      "too-lose",
		Pattern: `too|very|quite|bit|little ( lose ) !>the|a|an|my|your|his|her|our|their|it|them|weight|money|track|sight|interest`,
		Flags:   []string{"My shoes are too lose."},
		Leaves:  []string{"My shoes are too loose.", "I have too little to lose."},
		Except:  []string{`to lose`},
		Message: "Should be \"loose\"", Suggest: []string{"loose"},
		Category:    catConfused,
		Explanation: "\"Loose\" is the opposite of tight. To \"lose\" something is to no longer have it.",
	},
	{
		ID:      "have-to-plural",
		Pattern: `have|has|had|got|own|owns|bought ( to ) <=NNS>&#lower`,
		Flags:   []string{"I have to dogs."},
		Leaves:  []string{"I have two dogs.", "I have to go."},
		Message: "Should be \"two $3\"", Suggest: []string{"two"},
		Category:    catConfused,
		Explanation: "The number is \"two\". \"To\" goes before a verb or a place.",
	},
	{
		ID:      "are-write",
		Pattern: `am|is|are|was|were|'re|'m|'s ( write ) =>about|.|,|!|/\?+/`,
		Flags:   []string{"You are write about that."},
		Leaves:  []string{"You are right about that.", "All you do is write about it."},
		Except:  []string{`do|does|did <_>{0,2} write`},
		Message: "Should be \"right\"", Suggest: []string{"right"},
		Category:    catConfused,
		Explanation: "\"Right\" means correct. To \"write\" is to put words down.",
	},
	{
		ID:      "the-hole-thing",
		Pattern: `the|a|my|his|her|our|their|this|that ( hole ) thing|time|day|pizza|cake|family|world|story|point|lot|team|way|night|week|year|life|house|country|city|place|idea|process|situation`,
		Flags:   []string{"I ate the hole pizza.", "He is to blame for the hole thing."},
		Leaves:  []string{"I ate the whole pizza.", "The hole in the wall"},
		Message: "Should be \"whole\"", Suggest: []string{"whole"},
		Category:    catConfused,
		Explanation: "\"Whole\" means all of something. A \"hole\" is a gap or an opening.",
	},
	{
		ID:      "i-except",
		Pattern: `i|we|they|you|please|will|can|cannot|can't|don't|won't ( except ) your|my|the|this|that|his|her|our|their|it|a|an`,
		Flags:   []string{"I except your apology."},
		Leaves:  []string{"I accept your apology.", "Everyone except the driver"},
		Message: "Should be \"accept\"", Suggest: []string{"accept"},
		Category:    catConfused,
		Explanation: "To \"accept\" is to take or agree to something. \"Except\" means leaving something out.",
	},
	{
		ID:      "witch-one",
		Pattern: `( witch ) one|ones`,
		Flags:   []string{"Witch one do you want?"},
		Leaves:  []string{"Which one do you want?", "The witch is dead."},
		Message: "Should be \"which\"", Suggest: []string{"which"},
		Category:    catConfused,
		Explanation: "\"Which\" asks about a choice. A \"witch\" casts spells.",
	},
}
