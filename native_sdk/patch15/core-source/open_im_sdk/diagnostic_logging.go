package open_im_sdk

import (
	"context"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/logpolicy"
	"github.com/openimsdk/tools/log"
	"runtime"
)

// SetDiagnosticLogging enables metadata-only routine diagnostics for up to 900
// seconds. Pass zero to stop. Returns the accepted duration. The logger must
// be configured at Info or more verbose. This does not enable raw Debug/SQL logs.
func SetDiagnosticLogging(seconds int) int {
	accepted := logpolicy.Configure(seconds)
	log.ZInfo(context.Background(), "diagnostic logging configured", "durationSeconds", accepted, "goroutines", runtime.NumGoroutine())
	return accepted
}

// GetDiagnosticLoggingSeconds returns the remaining window, or zero when off.
func GetDiagnosticLoggingSeconds() int { return logpolicy.RemainingSeconds() }
