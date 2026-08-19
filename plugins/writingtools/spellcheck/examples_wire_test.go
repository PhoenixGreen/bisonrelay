package spellcheck

import (
	"encoding/json"
	"strings"
	"testing"
)

// The examples are how a rule is developed, not what it does. Sending them
// would put a test fixture in every host's memory and on the capability's
// contract, where it would have to be reviewed and versioned like a feature.
func TestExamplesNeverLeaveThePlugin(t *testing.T) {
	b, err := json.Marshal(Data{GrammarRules: Rules})
	if err != nil {
		t.Fatal(err)
	}
	for _, field := range []string{`"flags"`, `"leaves"`, `"Flags"`, `"Leaves"`} {
		if strings.Contains(string(b), field) {
			t.Errorf("%s crossed to the host", field)
		}
	}
	// And a distinctive example string, in case the field is ever renamed.
	if strings.Contains(string(b), "the the payment") {
		t.Error("an example's text crossed to the host")
	}
}
