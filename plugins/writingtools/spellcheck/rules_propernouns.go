package spellcheck

// rules_propernouns.go capitalises the words that are always capitalised.
//
// The dictionary cannot help here at all, and not because the words are
// missing: "monday" and "english" are both in it, because the wordlist is
// lowercased when it is built. So the checker sees a word it knows and says
// nothing, which is why a lowercase weekday has been sailing through since
// the first version.
//
// The whole difficulty is which words are safe. A proper noun that is also
// an ordinary word cannot be corrected without knowing what the sentence
// means -- "we march on Friday", "it may rain", "polish the table" -- so
// those are absent, and the ones that survive with a common-noun sense in
// some phrase are guarded by an antipattern instead.

const explainProperNoun = "Days, months, languages and nationalities are " +
	"proper nouns in English and take a capital letter wherever they appear."

// lowercaseCompounds are the phrases where a word from the list below is
// conventionally left lowercase.
//
// Most are dishes and objects that stopped being about the place a long time
// ago. Style guides disagree about several of them, and a checker with an
// opinion on whether "french fries" wants a capital is a checker arguing
// with its user about lunch.
const lowercaseCompounds = `[Ff]rench\s+(fries|toast|press|doors?|windows?|` +
	`braid|kiss|dressing|horn|bread)|` +
	`[Ee]nglish\s+(muffin|horn|ivy|breakfast)|` +
	`[Rr]oman\s+(numerals?|candle|nose)|` +
	`[Aa]rabic\s+numerals?|` +
	`[Ii]ndian\s+(summer|ink|file)|` +
	`[Dd]utch\s+(oven|courage|door|treat)|` +
	`[Ss]wiss\s+(cheese|roll)|` +
	`[Tt]urkish\s+(delight|bath|coffee)|` +
	`[Gg]reek\s+yogh?urt|` +
	`[Ss]cotch\s+(egg|tape|broth)`

var properNounRules = []GrammarRule{
	{
		// Lowercase only, here and below. These rules exist to find the
		// uncapitalised form, so folding their case -- which every other
		// literal rule in the plugin wants -- makes them fire on the very
		// spelling they are asking for. The corpus caught it on "Tuesday".
		//
		// The days have no other meaning at all, which makes them the one
		// group here that needs no guard.
		Pattern:     `\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b`,
		Message:     "Should be \"$U1\"",
		Suggest:     "$U1",
		Category:    "Capitalization",
		Explanation: explainProperNoun,
		Flags:       []string{"see you on monday"},
	},
	{
		// March, May and August are missing on purpose, and they are the
		// three worth naming. "We march on Friday", "it may rain" and "an
		// august institution" are all correct, and no pattern can tell them
		// from the months -- that needs to know what the sentence is doing,
		// which is the line this plugin does not cross.
		Pattern: `\b(january|february|april|june|july|september|october|` +
			`november|december)\b`,
		Message:     "Should be \"$U1\"",
		Suggest:     "$U1",
		Category:    "Capitalization",
		Explanation: explainProperNoun,
		Flags:       []string{"due in september"},
		Leaves:      []string{"we march on friday", "it may rain later"},
	},
	{
		// Languages and the nationalities that share their spelling.
		//
		// Absent by design: polish (to polish), welsh (to welsh on a bet),
		// czech (cheque), thai (tie), and every bare country name, since
		// china, turkey, chile and jersey are all ordinary words too.
		Pattern: `\b(english|french|german|spanish|italian|portuguese|` +
			`russian|japanese|chinese|korean|arabic|hebrew|hindi|dutch|` +
			`swedish|norwegian|danish|finnish|greek|turkish|hungarian|` +
			`romanian|vietnamese|indonesian|swahili|latin|american|british|` +
			`canadian|australian|european|african|asian|irish|scottish|` +
			`mexican|brazilian|indian|roman|swiss|scotch)\b`,
		Antipatterns: []string{lowercaseCompounds},
		Message:      "Should be \"$U1\"",
		Suggest:      "$U1",
		Category:     "Capitalization",
		Explanation:  explainProperNoun,
		Flags:        []string{"she speaks french and german"},
		Leaves: []string{
			"we had french fries and an english muffin",
			"write it in roman numerals",
			"a dutch oven and some turkish delight",
		},
	},
}
