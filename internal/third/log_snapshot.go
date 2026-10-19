package third

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/sdkerrs"
	"github.com/openimsdk/tools/errs"
)

// Feedback is a recent excerpt, not an unbounded in-memory copy of today's log.
// Fix the end offset before reading, so concurrent appends cannot extend work.
const maxLogTailBytes = 8 * 1024 * 1024

func readLastNLines(filename string, n int) ([]string, error) {
	if n <= 0 {
		return nil, fmt.Errorf("log line count must be positive")
	}
	f, err := os.Open(filename)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return nil, err
	}
	start := info.Size() - maxLogTailBytes
	if start < 0 {
		start = 0
	}
	data := make([]byte, int(info.Size()-start))
	read, err := f.ReadAt(data, start)
	if err != nil && !errors.Is(err, io.EOF) {
		return nil, err
	}
	data = data[:read]
	truncated := start > 0
	if truncated {
		// Drop a partial oldest line. For a single huge line retain a bounded
		// suffix instead of failing with bufio.Scanner's token-too-long error.
		if end := bytes.IndexByte(data, '\n'); end >= 0 && end < len(data)-1 {
			data = data[end+1:]
		}
	}
	data = bytes.TrimSuffix(data, []byte{'\n'})
	if len(data) == 0 {
		return nil, nil
	}
	// Find the selected suffix before splitting; millions of tiny old lines
	// must not allocate millions of strings just to return the last 10,000.
	remaining := n
	for i := len(data) - 1; i >= 0; i-- {
		if data[i] == '\n' {
			remaining--
			if remaining == 0 {
				data = data[i+1:]
				break
			}
		}
	}
	lines := strings.Split(strings.ToValidUTF8(string(data), "�"), "\n")
	for i := range lines {
		lines[i] = strings.TrimSuffix(lines[i], "\r")
	}
	if truncated {
		lines[0] = "[SDK log excerpt limited to last 8 MiB]\n" + lines[0]
	}
	return lines, nil
}

// Keep the public numeric error code while making the failing step explicit.
// Flutter's report only exports this allowlisted stage, never the raw detail.
func logUploadStageError(stage string, err error) error {
	if err == nil {
		return nil
	}
	code := sdkerrs.UnknownCode
	var coded errs.CodeError
	if errors.As(err, &coded) {
		code = coded.Code()
	}
	return errs.NewCodeError(code, "sdk_log_stage="+stage).WithDetail(err.Error())
}
