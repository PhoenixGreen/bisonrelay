package spellcheck

// rules.go is the one place every family of rules is assembled into the list
// the plugin actually ships.
//
// Written out rather than gathered by init(), and the explicitness is the
// point: the order below is the order the rules are applied in, it is
// reviewable at a glance, and a group cannot appear in the shipped list
// without somebody having decided where it goes. The cost of that -- one line
// to add when a file is added -- is covered by TestEveryRuleGroupIsUsed, which
// reads the package's own source and fails if a `*Rules` variable exists that
// nothing here names.

// Rules is every writing check, in the order they are applied.
//
// Only the groups above styleRules fire on text that is wrong whatever the
// writer meant. styleRules, redundancyRules, inclusiveRules and
// typographyRules are marked SeveritySuggestion throughout and hold to a
// different standard -- see the note at the top of rules_style.go --
// and checkRules is marked SeverityCheck and holds to a third, which is that
// it may be wrong as long as it asks rather than asserts.
var Rules = concat(
	errorRules,
	contractionRules,
	confusionRules,
	homophoneRules,
	homophonePairRules,
	compoundRules,
	articleRules,
	pluralArticleRules,
	ordinalRules,
	brandRules,
	agreementRules,
	learnerRules,
	properNounRules,
	punctuationRules,
	styleRules,
	redundancyRules,
	inclusiveRules,
	typographyRules,
	checkRules,
	commaCheckRules,
)
