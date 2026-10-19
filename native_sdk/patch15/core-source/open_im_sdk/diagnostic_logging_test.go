package open_im_sdk

import "testing"

func TestDiagnosticLoggingPublicControl(t *testing.T) {
	defer SetDiagnosticLogging(0)
	if SetDiagnosticLogging(1000000) != 900 {
		t.Fatal("missing cap")
	}
	if n := GetDiagnosticLoggingSeconds(); n < 899 || n > 900 {
		t.Fatalf("remaining=%d", n)
	}
	if SetDiagnosticLogging(0) != 0 || GetDiagnosticLoggingSeconds() != 0 {
		t.Fatal("disable failed")
	}
}
