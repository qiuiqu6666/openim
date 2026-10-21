package file

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/sdkerrs"
	"github.com/openimsdk/tools/errs"
)

func TestUploadRetrySDKNetworkCodes(t *testing.T) {
	for _, err := range []error{sdkerrs.ErrNetwork.WrapMsg("API connection lost"), sdkerrs.ErrNetworkTimeOut.WrapMsg("API timeout")} {
		calls := 0
		_, got := retryUpload(context.Background(), []time.Duration{0}, func() (*UploadFileResp, error) {
			calls++
			if calls == 1 {
				return nil, err
			}
			return &UploadFileResp{URL: "complete"}, nil
		})
		if got != nil || calls != 2 {
			t.Fatalf("API error not retried: %v, calls=%d", got, calls)
		}
	}
	for _, err := range []error{errs.ErrNoPermission.Wrap(), errs.ErrTokenExpired.Wrap(), sdkerrs.ErrArgs.Wrap()} {
		if retryableUploadError(err) {
			t.Fatalf("permanent API error retried: %v", err)
		}
	}
}

func TestUploadRetryRecoveryAndLimit(t *testing.T) {
	for _, recoverAt := range []int{3, 99} {
		calls := 0
		result, err := retryUpload(context.Background(), []time.Duration{0, 0}, func() (*UploadFileResp, error) {
			calls++
			if calls == recoverAt {
				return &UploadFileResp{URL: "done"}, nil
			}
			return nil, &net.OpError{Op: "write", Net: "tcp", Err: io.ErrUnexpectedEOF}
		})
		if calls != 3 {
			t.Fatalf("attempts=%d", calls)
		}
		if recoverAt == 3 && (err != nil || result.URL != "done") {
			t.Fatalf("recovery: %v", err)
		}
		if recoverAt == 99 && err == nil {
			t.Fatal("must stop after retry budget")
		}
	}
}

func TestUploadRetryCancellationAndPermanentFailure(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	calls := 0
	_, err := retryUpload(ctx, []time.Duration{time.Hour}, func() (*UploadFileResp, error) { calls++; cancel(); return nil, io.ErrUnexpectedEOF })
	if !errors.Is(err, context.Canceled) || calls != 1 {
		t.Fatalf("cancel: %v, calls %d", err, calls)
	}
	for _, status := range []int{301, 400, 401, 403, 404} {
		calls = 0
		_, err = retryUpload(context.Background(), []time.Duration{0}, func() (*UploadFileResp, error) { calls++; return nil, &uploadHTTPError{status: status} })
		if err == nil || calls != 1 {
			t.Fatalf("permanent status %d retried", status)
		}
	}
}

func TestUploadPUTRetriesWithFreshBody(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		body, _ := io.ReadAll(r.Body)
		if string(body) != "payload" {
			t.Errorf("body on attempt %d: %q", calls, body)
		}
		if calls == 1 {
			w.WriteHeader(503)
			return
		}
		w.WriteHeader(200)
	}))
	defer server.Close()
	address, _ := url.Parse(server.URL)
	_, err := retryUpload(context.Background(), []time.Duration{0}, func() (*UploadFileResp, error) {
		return nil, (&File{}).doPut(context.Background(), server.Client(), address, nil, strings.NewReader("payload"), 7)
	})
	if err != nil || calls != 2 {
		t.Fatalf("retry: %v, calls %d", err, calls)
	}
}

func TestUploadPUTRejectsRedirect(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(302) }))
	defer server.Close()
	address, _ := url.Parse(server.URL)
	err := (&File{}).doPut(context.Background(), server.Client(), address, nil, strings.NewReader("x"), 1)
	if err == nil {
		t.Fatal("redirect without uploaded content must not mark a part complete")
	}
}
