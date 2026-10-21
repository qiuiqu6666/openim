package file

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/third"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"testing"
	"time"
)

type auditResumeDB struct {
	db_interface.DataBase
	row *model_struct.LocalUpload
}

func (d *auditResumeDB) GetUpload(context.Context, string) (*model_struct.LocalUpload, error) {
	if d.row == nil {
		return nil, errors.New("missing")
	}
	r := *d.row
	return &r, nil
}
func (d *auditResumeDB) InsertUpload(_ context.Context, r *model_struct.LocalUpload) error {
	v := *r
	d.row = &v
	return nil
}
func (d *auditResumeDB) UpdateUpload(_ context.Context, r *model_struct.LocalUpload) error {
	v := *r
	d.row = &v
	return nil
}
func (d *auditResumeDB) DeleteUpload(context.Context, string) error { d.row = nil; return nil }
func TestUploadRetryVideoResumesCommittedParts(t *testing.T) {
	counts := map[int]int{}
	inits, completions := 0, 0
	var server *httptest.Server
	signs := func() *third.AuthSignParts {
		parts := []*third.SignPart{}
		for i := 1; i <= 3; i++ {
			parts = append(parts, &third.SignPart{PartNumber: int32(i), Url: server.URL + "/put/" + strconv.Itoa(i)})
		}
		return &third.AuthSignParts{Parts: parts}
	}
	server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		write := func(data any) { json.NewEncoder(w).Encode(map[string]any{"errCode": 0, "data": data}) }
		switch r.URL.Path {
		case "/object/part_limit":
			write(&third.PartLimitResp{MinPartSize: 1024, MaxPartSize: 1024, MaxNumSize: 100})
		case "/object/initiate_multipart_upload":
			inits++
			write(&third.InitiateMultipartUploadResp{Upload: &third.UploadInfo{UploadID: "resume-video", PartSize: 1024, ExpireTime: time.Now().Add(24 * time.Hour).UnixMilli(), Sign: signs()}})
		case "/object/auth_sign":
			s := signs()
			write(&third.AuthSignResp{Parts: s.Parts})
		case "/object/complete_multipart_upload":
			completions++
			write(&third.CompleteMultipartUploadResp{Url: server.URL + "/video.mp4"})
		default:
			n, e := strconv.Atoi(r.URL.Path[len("/put/"):])
			if e != nil {
				t.Error(e)
				w.WriteHeader(404)
				return
			}
			counts[n]++
			io.Copy(io.Discard, r.Body)
			if n == 2 && counts[n] == 1 {
				w.WriteHeader(503)
				return
			}
			w.WriteHeader(200)
		}
	}))
	defer server.Close()
	path := filepath.Join(t.TempDir(), "video.mp4")
	os.WriteFile(path, make([]byte, 2500), 0600)
	ctx := ccontext.WithInfo(ccontext.WithOperationID(context.Background(), "video-audit"), &ccontext.GlobalConfig{UserID: "test", Token: "test", IMConfig: sdk_struct.IMConfig{ApiAddr: server.URL}})
	db := &auditResumeDB{}
	f := NewFile(db, "test")
	req := &UploadFileReq{Filepath: path, Name: "video.mp4", ContentType: "video/mp4"}
	if _, err := f.UploadFile(ctx, req, nil); err != nil {
		t.Fatal(err)
	}
	if counts[1] != 1 || counts[2] != 2 || counts[3] != 1 || inits != 1 || completions != 1 {
		t.Fatalf("resume failed: %v inits=%d completions=%d", counts, inits, completions)
	}
	t.Log("Automatic retry resumes at part 2, preserves part 1 and completes.")
}
