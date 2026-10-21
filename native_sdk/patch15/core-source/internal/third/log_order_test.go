package third

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"
)

func TestLogUploadChronologicalOrder(t *testing.T) {
	cases := []struct {
		name  string
		files []string
		want  []string
	}{
		{"migration", []string{"chat-sdk-core.2026-10-21", "open-im-sdk-core.2026-10-20"}, []string{"open-im-sdk-core.2026-10-20", "chat-sdk-core.2026-10-21"}},
		{"same_day_latest_write", []string{"open-im-sdk-core.2026-10-21", "chat-sdk-core.2026-10-21"}, []string{"open-im-sdk-core.2026-10-21", "chat-sdk-core.2026-10-21"}},
		{"legacy_still_active", []string{"chat-sdk-core.2026-10-21", "open-im-sdk-core.2026-10-21"}, []string{"chat-sdk-core.2026-10-21", "open-im-sdk-core.2026-10-21"}},
		{"legacy_only", []string{"open-im-sdk-core.2026-10-20", "open-im-sdk-core.2026-10-21"}, []string{"open-im-sdk-core.2026-10-20", "open-im-sdk-core.2026-10-21"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			for i, name := range tc.files {
				path := filepath.Join(dir, name)
				if err := os.WriteFile(path, []byte(name), 0600); err != nil {
					t.Fatal(err)
				}
				stamp := time.Unix(100+int64(i), 0)
				if err := os.Chtimes(path, stamp, stamp); err != nil {
					t.Fatal(err)
				}
			}
			// Temporary archives, malformed dates and directories must never win.
			for _, name := range []string{"chat-sdk-core_temp.2026-10-22", "chat-sdk-core.2026-99-99", "latest.zip"} {
				if err := os.WriteFile(filepath.Join(dir, name), nil, 0600); err != nil {
					t.Fatal(err)
				}
			}
			if err := os.Mkdir(filepath.Join(dir, "chat-sdk-core.2026-10-23"), 0700); err != nil {
				t.Fatal(err)
			}
			entries, err := os.ReadDir(dir)
			if err != nil {
				t.Fatal(err)
			}
			orderLogEntries(entries)
			var got []string
			for _, entry := range entries {
				if !entry.IsDir() && checkLogPath(entry.Name()) {
					got = append(got, entry.Name())
				}
			}
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("got %v, want %v", got, tc.want)
			}
		})
	}
}

func TestLogUploadEqualTimestampPrefersCurrentName(t *testing.T) {
	dir := t.TempDir()
	stamp := time.Unix(100, 0)
	for _, name := range []string{"chat-sdk-core.2026-10-21", "open-im-sdk-core.2026-10-21"} {
		path := filepath.Join(dir, name)
		if err := os.WriteFile(path, []byte("log"), 0600); err != nil {
			t.Fatal(err)
		}
		if err := os.Chtimes(path, stamp, stamp); err != nil {
			t.Fatal(err)
		}
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	orderLogEntries(entries)
	if entries[len(entries)-1].Name() != "chat-sdk-core.2026-10-21" {
		t.Fatal("selected legacy log on equal timestamp")
	}
}
