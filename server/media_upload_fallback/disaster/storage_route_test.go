package third

import (
	"context"
	"errors"
	"github.com/openimsdk/open-im-server/v3/pkg/common/storage/controller"
	"github.com/openimsdk/tools/errs"
	"net"
	"testing"
)

func TestStorageRetryClassification(t *testing.T) {
	for _, failure := range []error{context.DeadlineExceeded, &net.DNSError{Err: "not found"}, &net.OpError{Op: "dial", Err: errors.New("refused")}} {
		var coded errs.CodeError
		if !errors.As(storageAttemptError(failure), &coded) || coded.Code() != 10901 {
			t.Fatal("transient storage error not retryable")
		}
	}
	for _, failure := range []error{context.Canceled, errs.ErrNoPermission.Wrap(), errors.New("invalid input")} {
		if storageAttemptError(failure) != failure {
			t.Fatal("permanent error changed")
		}
	}
}

type routeStore struct{ controller.S3Database }

func TestBackupStorageIsolation(t *testing.T) {
	primary, backup := &routeStore{}, &routeStore{}
	service := &thirdServer{s3dataBase: primary, backupStorage: &backupStorage{store: backup}}
	for _, sample := range []struct {
		name, id    string
		hk, wantErr bool
	}{
		{"user/image", "id", false, false}, {"user/__cos_hk__/image", "hk:id", true, false},
		{"", "hk:id", true, false}, {"user/__cos_hk__/image", "", true, false},
		{"user/image", "hk:id", false, true}, {"user/__cos_hk__/image", "id", false, true},
		{"user/a/__cos_hk__/image", "id", false, false},
	} {
		got, id, err := service.forUploadStorage(sample.name, sample.id)
		if (err != nil) != sample.wantErr {
			t.Fatal("invalid storage validation")
		}
		if err != nil {
			continue
		}
		if (got.s3dataBase == backup) != sample.hk || service.s3dataBase != primary {
			t.Fatal("store isolation failed")
		}
		if sample.id != "" && id != "id" {
			t.Fatal("upload ID not unwrapped")
		}
	}
	if _, _, err := (&thirdServer{}).forUploadStorage("user/__cos_hk__/x", ""); err == nil {
		t.Fatal("missing backup accepted")
	}
}
