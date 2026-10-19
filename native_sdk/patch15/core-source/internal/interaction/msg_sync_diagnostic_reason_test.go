package interaction

import (
	"context"
	"errors"
	"fmt"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/sdkerrs"
	"github.com/openimsdk/protocol/sdkws"
	"github.com/openimsdk/tools/errs"
	"testing"
)

func TestSyncRangeFailureReasonsDoNotInventLegalHoles(t *testing.T) {
	cases := []struct {
		packet *sdkws.PullMsgs
		err    error
		want   string
	}{
		{nil, context.Canceled, "cancelled"}, {nil, fmt.Errorf("wrapped: %w", context.DeadlineExceeded), "network_timeout"}, {nil, sdkerrs.ErrCtxDeadline, "network_timeout"}, {nil, errs.ErrNoPermission.Wrap(), "permission_denied"}, {nil, errors.New("unknown server failure"), "request_failure_unclassified"}, {nil, nil, "missing_packet"}, {&sdkws.PullMsgs{}, nil, "empty_unconfirmed"}, {&sdkws.PullMsgs{IsEnd: true}, nil, "boundary_claim_requires_confirmation"}, {&sdkws.PullMsgs{Msgs: []*sdkws.MsgData{nil}}, nil, "malformed_packet"}, {&sdkws.PullMsgs{Msgs: []*sdkws.MsgData{{Seq: 3}}}, nil, "unconfirmed_gap"}}
	for _, tc := range cases {
		if got := syncRangeFailureReason(tc.packet, tc.err); got != tc.want {
			t.Fatalf("got %s, want %s", got, tc.want)
		}
	}
}
