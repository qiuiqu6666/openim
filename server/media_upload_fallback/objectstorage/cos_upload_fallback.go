package objectstorage

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/openimsdk/tools/s3"
	"github.com/openimsdk/tools/s3/cos"
)

const fallbackHeader = "X-Openim-Upload-Fallback"
const acceleratedOrigin = "https://gz99chat-1416337673.cos.accelerate.myqcloud.com"
const regionalOrigin = "https://gz99chat-1416337673.cos.ap-guangzhou.myqcloud.com"

type fallbackTarget struct {
	URL    string      `json:"url"`
	Header http.Header `json:"header"`
}

// Initiation/completion/verification must work even when acceleration is down.
// Client signatures remain acceleration-first; server storage IO uses origin.
func (c *COS) metadataClient() *cos.Cos {
	if c.regional != nil {
		return c.regional
	}
	return c.Cos
}

func (c *COS) InitiateMultipartUpload(ctx context.Context, name string, opt *s3.PutOption) (*s3.InitiateMultipartUploadResult, error) {
	ctx, cancel := context.WithTimeout(ctx, time.Duration(c.config.OperationTimeoutMS)*time.Millisecond)
	defer cancel()
	return c.metadataClient().InitiateMultipartUpload(ctx, name, opt)
}

func newRegionalUploader(conf cos.Config) (*cos.Cos, error) {
	switch strings.TrimRight(conf.BucketURL, "/") {
	case acceleratedOrigin:
		conf.BucketURL = regionalOrigin
	case "https://99chat-1416337673.cos.accelerate.myqcloud.com":
		conf.BucketURL = "https://99chat-1416337673.cos.ap-hongkong.myqcloud.com"
	default:
		return nil, nil
	}
	conf.CDN = ""
	return cos.NewCos(conf)
}

func (c *COS) PresignedPutObject(ctx context.Context, name string, expiry time.Duration, opt *s3.PutOption) (*s3.PresignedPutResult, error) {
	primary, err := c.Cos.PresignedPutObject(ctx, name, expiry, opt)
	if err != nil || c.regional == nil {
		return primary, err
	}
	backup, err := c.regional.PresignedPutObject(ctx, name, expiry, opt)
	if err != nil {
		return nil, err
	}
	if primary.Header == nil {
		primary.Header = make(http.Header)
	}
	metadata, err := json.Marshal(fallbackTarget{backup.URL, backup.Header})
	if err != nil {
		return nil, err
	}
	primary.Header.Set(fallbackHeader, string(metadata))
	return primary, nil
}

// Every part carries a separately signed origin URL. This keeps the protobuf
// protocol compatible and never rewrites the host of an existing signature.
func (c *COS) AuthSign(ctx context.Context, uploadID, name string, expiry time.Duration, parts []int) (*s3.AuthSignResult, error) {
	primary, err := c.Cos.AuthSign(ctx, uploadID, name, expiry, parts)
	if err != nil || c.regional == nil {
		return primary, err
	}
	backup, err := c.regional.AuthSign(ctx, uploadID, name, expiry, parts)
	if err != nil {
		return nil, err
	}
	for i, part := range backup.Parts {
		raw := part.URL
		if raw == "" {
			raw = backup.URL
		}
		u, err := url.Parse(raw)
		if err != nil {
			return nil, err
		}
		query := u.Query()
		for k, v := range backup.Query {
			query[k] = v
		}
		for k, v := range part.Query {
			query[k] = v
		}
		u.RawQuery = query.Encode()
		header := backup.Header.Clone()
		if header == nil {
			header = make(http.Header)
		}
		for k, v := range part.Header {
			header[k] = v
		}
		metadata, err := json.Marshal(fallbackTarget{u.String(), header})
		if err != nil {
			return nil, err
		}
		if primary.Parts[i].Header == nil {
			primary.Parts[i].Header = make(http.Header)
		}
		primary.Parts[i].Header.Set(fallbackHeader, string(metadata))
	}
	return primary, nil
}
