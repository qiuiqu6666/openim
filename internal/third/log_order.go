package third

import (
	"os"
	"sort"
	"strings"
	"time"
)

// orderLogEntries uses the rotation date, not the product-name prefix.
// For an upgrade within one day, the last-written file wins; equal timestamps
// prefer the current prefix. Invalid files are still rejected by checkLogPath.
func orderLogEntries(entries []os.DirEntry) {
	modified := make(map[string]time.Time, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() && checkLogPath(entry.Name()) {
			if info, err := entry.Info(); err == nil {
				modified[entry.Name()] = info.ModTime()
			}
		}
	}
	sort.SliceStable(entries, func(i, j int) bool {
		a, b := entries[i].Name(), entries[j].Name()
		validA, validB := !entries[i].IsDir() && checkLogPath(a), !entries[j].IsDir() && checkLogPath(b)
		if validA != validB {
			return !validA
		}
		if !validA {
			return a < b
		}
		dateA, dateB := a[len(a)-10:], b[len(b)-10:]
		if dateA != dateB {
			return dateA < dateB
		}
		if !modified[a].Equal(modified[b]) {
			return modified[a].Before(modified[b])
		}
		currentA, currentB := strings.HasPrefix(a, "chat-sdk-core."), strings.HasPrefix(b, "chat-sdk-core.")
		if currentA != currentB {
			return !currentA
		}
		return a < b
	})
}
