package common

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/logpolicy"
	"github.com/openimsdk/tools/log"
)

func TestCommandLoggingWindowPreservesDeliveryAndErrors(t *testing.T) {
	logpolicy.Configure(0)
	t.Cleanup(func() { logpolicy.Configure(0) })
	// The logger owns an open rotating file with no public Close method.
	// Isolate it so Windows can remove the directory after the child exits.
	dir := os.Getenv("OPENIM_LOG_POLICY_TEST_DIR")
	if dir == "" {
		exe, err := os.Executable()
		if err != nil {
			t.Fatal(err)
		}
		cmd := exec.Command(exe, "-test.run=^TestCommandLoggingWindowPreservesDeliveryAndErrors$")
		cmd.Env = append(os.Environ(), "OPENIM_LOG_POLICY_TEST_DIR="+t.TempDir())
		if output, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("log policy child: %v\n%s", err, output)
		}
		return
	}
	if err := log.InitLoggerFromConfig("policy-test", "", "", "", log.LevelInfo, true, false, dir, 1, 24, "test", true); err != nil {
		t.Fatal(err)
	}
	ch := make(chan Cmd2Value, 3)
	send := func(name string) {
		t.Helper()
		if err := sendCmd(ch, Cmd2Value{Ctx: context.Background(), Cmd: name, Caller: "test"}, time.Second); err != nil {
			t.Fatal(err)
		}
	}
	send("compact-event")
	logpolicy.Configure(60)
	send("detailed-event")
	logpolicy.Configure(0)
	send("disabled-event")
	if len(ch) != 3 {
		t.Fatal("logging policy changed delivery")
	}
	if err := sendCmd(nil, Cmd2Value{Ctx: context.Background(), Cmd: "failure-event", Caller: "test"}, time.Second); err != ErrChanNil {
		t.Fatal("error lost")
	}
	files, err := filepath.Glob(filepath.Join(dir, "policy-test.*"))
	if err != nil || len(files) == 0 {
		t.Fatalf("missing logs: %v", err)
	}
	var output strings.Builder
	for _, f := range files {
		b, e := os.ReadFile(f)
		if e != nil {
			t.Fatal(e)
		}
		output.Write(b)
	}
	got := output.String()
	if strings.Contains(got, "compact-event") || strings.Contains(got, "disabled-event") {
		t.Fatal("routine logs escaped compact mode")
	}
	if !strings.Contains(got, "detailed-event") || !strings.Contains(got, "failure-event") {
		t.Fatal("diagnostic or error evidence missing")
	}
}
