package third

import "testing"

func TestBrandedLogPaths(t *testing.T) {
	for name, want := range map[string]bool{
		"chat-sdk-core.2026-10-19":      true,
		"open-im-sdk-core.2026-10-19":   true,
		"chat-sdk-core.2026-99-99":      false,
		"chat-sdk-core_temp.2026-10-19": false,
		"../chat-sdk-core.2026-10-19":   false,
		"other.2026-10-19":              false,
	} {
		if got := checkLogPath(name); got != want {
			t.Errorf("%q: got %v want %v", name, got, want)
		}
	}
}
