package file

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"strings"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/ccontext"
	"github.com/openimsdk/tools/log"
)

const uploadFallbackHeader = "X-Openim-Upload-Fallback"
const uploadRegionalHost = "gz99chat-1416337673.cos.ap-guangzhou.myqcloud.com"
const uploadAcceleratedHost = "gz99chat-1416337673.cos.accelerate.myqcloud.com"

type uploadRouteKey struct{}
type uploadRouteState struct {
	tier           int
	available      bool
	preferenceSet  bool
	preferRegional bool
	multiBucket    bool
	circuit        *uploadCircuit
	currentKey     string
}
type uploadFallbackTarget struct {
	URL            string      `json:"url"`
	Header         http.Header `json:"header"`
	PreferRegional bool        `json:"preferRegional,omitempty"`
	MultiBucket    bool        `json:"multiBucket,omitempty"`
}

// Only transport/retryable service failures change routes. Auth errors and
// cancellation remain errors. retryUpload reopens files and restores part bits.
func advanceUploadRoute(ctx context.Context, err error) error {
	state, _ := ctx.Value(uploadRouteKey{}).(*uploadRouteState)
	if state != nil && (state.available || state.multiBucket) && retryableUploadError(err) {
		state.circuit.mark(state.currentKey, true)
		state.currentKey = ""
		if state.tier < state.lastTier() {
			state.tier++
		}
		log.ZInfo(ctx, "upload route fallback", "tier", state.tier)
	}
	return err
}

func selectUploadRoute(ctx context.Context, original *url.URL, headers http.Header) (*url.URL, http.Header, error) {
	headers = headers.Clone()
	metadata := headers.Get(uploadFallbackHeader)
	headers.Del(uploadFallbackHeader)
	state, _ := ctx.Value(uploadRouteKey{}).(*uploadRouteState)
	if state == nil || metadata == "" {
		if state != nil && !state.preferenceSet {
			state.multiBucket = false
		}
		return original, headers, nil
	}
	var target uploadFallbackTarget
	if len(metadata) > 16*1024 || json.Unmarshal([]byte(metadata), &target) != nil {
		return nil, nil, errors.New("invalid upload fallback metadata")
	}
	regional, accelerated := uploadRegionalHost, uploadAcceleratedHost
	if state.hongKong() {
		regional, accelerated = uploadHKRegionalHost, uploadHKAcceleratedHost
	}
	u, err := url.Parse(target.URL)
	if err != nil || u.Scheme != "https" || u.Host != regional || u.User != nil || u.Fragment != "" ||
		original.Scheme != "https" || (original.Host != accelerated && original.Host != regional) || u.EscapedPath() != original.EscapedPath() {
		return nil, nil, errors.New("invalid upload fallback target")
	}
	state.available = true
	if !state.preferenceSet {
		state.preferRegional = target.PreferRegional
		state.multiBucket = target.MultiBucket
		state.preferenceSet = true
	}
	if !state.relay() && state.tier%2 == 0 {
		if state.preferRegional {
			return u, target.Header.Clone(), nil
		}
		return original, headers, nil
	}
	if !state.relay() && state.tier%2 == 1 {
		if state.preferRegional {
			return original, headers, nil
		}
		return u, target.Header.Clone(), nil
	}
	info := ccontext.Info(ctx)
	relay, err := url.Parse(strings.TrimRight(info.ApiAddr(), "/") + "/object/upload_relay")
	if err != nil || relay.Host == "" || (relay.Scheme != "https" && relay.Scheme != "http") {
		return nil, nil, errors.New("invalid upload relay API")
	}
	return relay, http.Header{
		"Token": {info.Token()}, "Operationid": {info.OperationID()},
		uploadFallbackHeader: {metadata}, "Content-Type": {"application/octet-stream"},
	}, nil
}
