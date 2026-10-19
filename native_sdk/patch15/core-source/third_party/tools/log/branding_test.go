package log

import (
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
	"strings"
	"testing"
)

func TestDiagnosticBranding(t *testing.T) {
	for _, jsonFormat := range []bool{false, true} {
		config := zap.NewProductionEncoderConfig()
		var encoder zapcore.Encoder = zapcore.NewConsoleEncoder(config)
		if jsonFormat {
			encoder = zapcore.NewJSONEncoder(config)
		}
		encoder = (&alignEncoder{Encoder: encoder}).Clone()
		encoder.AddString("source", "open-im-sdk-core")
		out, err := encoder.EncodeEntry(zapcore.Entry{Level: zapcore.ErrorLevel, Message: "OpenIM failed", Caller: zapcore.EntryCaller{Defined: true, File: "open_im_sdk/caller.go", Line: 123}}, []zapcore.Field{
			zap.String("error", "github.com/openimsdk/tools/errs failed: code=1001"),
			zap.String("operationID", "op-123"), zap.Int("elapsed_ms", 1500),
		})
		if err != nil {
			t.Fatal(err)
		}
		value := out.String()
		out.Free()
		for _, unwanted := range []string{"openim", "open-im", "open_im"} {
			if strings.Contains(strings.ToLower(value), unwanted) {
				t.Fatalf("leaked branding: %s", value)
			}
		}
		for _, required := range []string{"op-123", "1500", "1001", "caller.go:123", "Chat failed"} {
			if !strings.Contains(value, required) {
				t.Fatalf("lost diagnostic %s: %s", required, value)
			}
		}
	}
}
