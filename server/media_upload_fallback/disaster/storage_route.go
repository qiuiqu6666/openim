package third

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"strings"

	"github.com/openimsdk/open-im-server/v3/pkg/common/storage/controller"
	"github.com/openimsdk/tools/errs"
	"github.com/openimsdk/tools/s3"
	cosapi "github.com/tencentyun/cos-go-sdk-v5"
)

const hongKongUploadPrefix = "hk:"
const hongKongNameSegment = "/__cos_hk__/"

// A dedicated retryable code distinguishes storage transport failure from
// permission, validation and business errors. Never return COS signed URLs.
func storageAttemptError(err error) error {
	if err == nil {
		return nil
	}
	var network net.Error
	var connection *net.OpError
	var dns *net.DNSError
	var response *cosapi.ErrorResponse
	if errors.Is(err, context.Canceled) {
		return err
	}
	if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) || errors.As(err, &connection) || errors.As(err, &dns) || (errors.As(err, &network) && network.Timeout()) ||
		(errors.As(err, &response) && response.Response != nil && (response.Response.StatusCode >= 500 || response.Response.StatusCode == 429 || response.Response.StatusCode == 408)) {
		return errs.NewCodeError(10901, "storage temporarily unavailable")
	}
	return err
}

type backupStorage struct {
	store   controller.S3Database
	backend s3.Interface
}

func hongKongName(name string) bool {
	_, rest, ok := strings.Cut(name, "/")
	return ok && strings.HasPrefix(rest, "__cos_hk__/")
}

// Copy the RPC receiver per request; never change the shared service's store.
// Names persist the bucket choice; upload IDs keep multipart sessions isolated.
func (t *thirdServer) forUploadStorage(name, id string) (*thirdServer, string, error) {
	hkID := strings.HasPrefix(id, hongKongUploadPrefix)
	if name != "" && id != "" && hongKongName(name) != hkID {
		return nil, "", fmt.Errorf("upload storage does not match object name")
	}
	if !hongKongName(name) && !hkID {
		return t, id, nil
	}
	if t.backupStorage == nil {
		return nil, "", fmt.Errorf("backup storage unavailable")
	}
	routed := *t
	routed.s3dataBase = t.backupStorage.store
	routed.s3 = t.backupStorage.backend
	return &routed, strings.TrimPrefix(id, hongKongUploadPrefix), nil
}
