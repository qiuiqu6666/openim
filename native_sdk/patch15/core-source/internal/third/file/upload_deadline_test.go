package file

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/third"
)

type deadlineDB struct{ db_interface.DataBase }

func (deadlineDB) DeleteUpload(context.Context, string) error { return nil }

func TestUploadDeadlineReleasesStalledPUTAndAllowsSameImageRetry(t *testing.T) {
	for _, bodyStall := range []bool{false, true} {
		t.Run(map[bool]string{false: "headers", true: "body"}[bodyStall], func(t *testing.T) {
			var puts atomic.Int32
			var server *httptest.Server
			release := make(chan struct{})
			server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				write := func(data any) { _ = json.NewEncoder(w).Encode(map[string]any{"errCode": 0, "data": data}) }
				switch r.URL.Path {
				case "/object/part_limit":
					write(&third.PartLimitResp{MinPartSize: 1024, MaxPartSize: 1024, MaxNumSize: 10})
				case "/object/initiate_multipart_upload":
					write(&third.InitiateMultipartUploadResp{Upload: &third.UploadInfo{
						UploadID: "test-upload", PartSize: 1024,
						Sign: &third.AuthSignParts{Url: server.URL + "/put", Parts: []*third.SignPart{{PartNumber: 1}}},
					}})
				case "/put":
					_, _ = io.Copy(io.Discard, r.Body)
					if puts.Add(1) == 1 {
						if bodyStall {
							w.WriteHeader(http.StatusOK)
							w.(http.Flusher).Flush()
						}
						select {
						case <-r.Context().Done():
						case <-release:
						}
						return
					}
					w.WriteHeader(http.StatusOK)
				case "/object/complete_multipart_upload":
					write(&third.CompleteMultipartUploadResp{Url: server.URL + "/image.jpg"})
				default:
					http.Error(w, "unexpected route", http.StatusNotFound)
				}
			}))
			defer server.Close()
			defer close(release)
			ctx := ccontext.WithInfo(ccontext.WithOperationID(context.Background(), "upload-test"),
				&ccontext.GlobalConfig{UserID: "test", Token: "test", IMConfig: sdk_struct.IMConfig{ApiAddr: server.URL}})
			// Rescue the legacy unbounded implementation without hanging the test.
			ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
			defer cancel()
			f := NewFile(deadlineDB{}, "test")
			f.uploadTimeout = 100 * time.Millisecond
			path := filepath.Join(t.TempDir(), "image.jpg")
			if err := os.WriteFile(path, []byte("image fixture"), 0600); err != nil {
				t.Fatal(err)
			}
			request := &UploadFileReq{Filepath: path, Name: "image.jpg"}
			started := time.Now()
			_, err := f.UploadFile(ctx, request, nil)
			if !errors.Is(err, context.DeadlineExceeded) {
				t.Fatalf("expected deadline, got %v", err)
			}
			if time.Since(started) >= time.Second {
				t.Fatal("native upload ignored its own deadline")
			}
			if len(f.uploading) != 0 {
				t.Fatal("timed-out upload retained content lock")
			}
			f.uploadTimeout = time.Second
			result, err := f.UploadFile(ctx, request, nil)
			if err != nil || result.URL != server.URL+"/image.jpg" {
				t.Fatalf("same image retry: %v, %v", result, err)
			}
		})
	}
}

func TestUploadHashWaitCancellationKeepsOwnerAndReleasesWaiter(t *testing.T) {
	f := NewFile(nil, "test")
	if err := f.lockHash(context.Background(), "image"); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	if err := f.lockHash(ctx, "image"); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("wait result: %v", err)
	}
	if f.uploading["image"].count != 1 {
		t.Fatal("cancelled waiter lost the active owner")
	}
	f.unlockHash("image")
	if len(f.uploading) != 0 {
		t.Fatal("content lock leaked")
	}
	if err := f.lockHash(context.Background(), "image"); err != nil {
		t.Fatal(err)
	}
	f.unlockHash("image")
}

func TestUploadHashSerializesConcurrentRetries(t *testing.T) {
	f := NewFile(nil, "test")
	var active, overlaps atomic.Int32
	var workers sync.WaitGroup
	for i := 0; i < 60; i++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			if err := f.lockHash(context.Background(), "image"); err != nil {
				t.Error(err)
				return
			}
			if active.Add(1) != 1 {
				overlaps.Add(1)
			}
			time.Sleep(time.Millisecond)
			active.Add(-1)
			f.unlockHash("image")
		}()
	}
	workers.Wait()
	if overlaps.Load() != 0 || len(f.uploading) != 0 {
		t.Fatal("concurrent uploads overlap or leaked a lock")
	}
}
