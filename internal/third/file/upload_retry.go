package file

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/url"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/sdkerrs"
	"github.com/openimsdk/tools/errs"
)

// Keep signed URLs, credentials and storage response bodies out of errors.
type uploadHTTPError struct{ status int }

func uploadTransportError(err error) error {
	var requestErr *url.Error
	if errors.As(err, &requestErr) {
		return requestErr.Err
	}
	return err
}

func (e *uploadHTTPError) Error() string { return fmt.Sprintf("upload HTTP status %d", e.status) }

func retryableUploadError(err error) bool {
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		return false
	}
	var status *uploadHTTPError
	if errors.As(err, &status) {
		return status.status == 408 || status.status == 429 || status.status == 500 || status.status == 502 || status.status == 503 || status.status == 504
	}
	// ApiPost replaces transport errors with SDK codes, so errors.As(net.OpError)
	// alone misses failures while obtaining part limits, signatures or completion.
	var coded errs.CodeError
	if errors.As(err, &coded) {
		return coded.Code() == 10901 || coded.Code() == sdkerrs.NetworkError || coded.Code() == sdkerrs.NetworkTimeoutError
	}
	var timed net.Error
	if errors.As(err, &timed) && timed.Timeout() {
		return true
	}
	var network *net.OpError
	var dns *net.DNSError
	return errors.As(err, &network) || errors.As(err, &dns) || errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF)
}

// Each attempt reopens the source and reloads committed part bits. Never reuse
// a partially consumed request body, and never retry a message send itself.
func retryUpload(ctx context.Context, delays []time.Duration, attempt func() (*UploadFileResp, error)) (*UploadFileResp, error) {
	for i := 0; ; i++ {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		result, err := attempt()
		if err == nil || !retryableUploadError(err) || i >= len(delays) {
			return result, err
		}
		timer := time.NewTimer(delays[i])
		select {
		case <-ctx.Done():
			timer.Stop()
			return nil, ctx.Err()
		case <-timer.C:
		}
	}
}
