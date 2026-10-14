package batchread

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/openimsdk/protocol/msg"
	"google.golang.org/grpc"
)

type fakeClient struct {
	msg.MsgClient
	mu           sync.Mutex
	seqs         map[string]*msg.Seqs
	calls        []*msg.MarkConversationAsReadReq
	receipts     [][]int64
	fail         string
	snapshotErr  error
	active, peak int
	delay        time.Duration
}

func (f *fakeClient) MarkMsgsAsRead(ctx context.Context, r *msg.MarkMsgsAsReadReq, _ ...grpc.CallOption) (*msg.MarkMsgsAsReadResp, error) {
	f.mu.Lock()
	f.receipts = append(f.receipts, r.Seqs)
	f.mu.Unlock()
	_, err := f.MarkConversationAsRead(ctx, &msg.MarkConversationAsReadReq{UserID: r.UserID, ConversationID: r.ConversationID, HasReadSeq: r.Seqs[len(r.Seqs)-1]})
	return &msg.MarkMsgsAsReadResp{}, err
}

func TestSingleReadDoesNotExpandDeletedHistory(t *testing.T) {
	f := &fakeClient{seqs: map[string]*msg.Seqs{"si_a_b": {HasReadSeq: 8000000, MaxSeq: 8000005}}}
	out, err := New(f).Apply(context.Background(), "a", []Target{{"si_a_b", 8000005}})
	if err != nil || !out[0].Success || len(f.receipts) != 1 || len(f.receipts[0]) != 5 || f.receipts[0][0] != 8000001 {
		t.Fatalf("unbounded receipt: %v %v", out, err)
	}
}

func (f *fakeClient) GetConversationsHasReadAndMaxSeq(ctx context.Context, r *msg.GetConversationsHasReadAndMaxSeqReq, _ ...grpc.CallOption) (*msg.GetConversationsHasReadAndMaxSeqResp, error) {
	if f.snapshotErr != nil {
		return nil, f.snapshotErr
	}
	return &msg.GetConversationsHasReadAndMaxSeqResp{Seqs: f.seqs}, nil
}
func (f *fakeClient) MarkConversationAsRead(ctx context.Context, r *msg.MarkConversationAsReadReq, _ ...grpc.CallOption) (*msg.MarkConversationAsReadResp, error) {
	f.mu.Lock()
	f.calls = append(f.calls, r)
	f.active++
	if f.active > f.peak {
		f.peak = f.active
	}
	f.mu.Unlock()
	defer func() { f.mu.Lock(); f.active--; f.mu.Unlock() }()
	select {
	case <-time.After(f.delay):
	case <-ctx.Done():
		return nil, ctx.Err()
	}
	if r.ConversationID == f.fail {
		return nil, errors.New("unavailable")
	}
	return &msg.MarkConversationAsReadResp{}, nil
}
func TestPrepareScopesAndUnloadedConversations(t *testing.T) {
	f := &fakeClient{seqs: map[string]*msg.Seqs{
		"si_a_b": {MaxSeq: 5}, "sg_a": {MaxSeq: 8}, "n_a": {MaxSeq: 7}, "sg_read": {MaxSeq: 5, HasReadSeq: 5},
	}}
	s := New(f)
	for _, tc := range []struct {
		scope string
		count int
	}{{"single", 1}, {"group", 1}, {"all", 2}, {"selected", 0}} {
		out, err := s.Prepare(context.Background(), "a", tc.scope, nil)
		if err != nil || len(out) != tc.count {
			t.Fatalf("%s: %v %v", tc.scope, out, err)
		}
	}
	for i := 0; i < 3000; i++ {
		f.seqs[fmt.Sprintf("sg_%d", i)] = &msg.Seqs{MaxSeq: 10}
	}
	out, err := s.Prepare(context.Background(), "a", "group", nil)
	if err != nil || len(out) != 3001 {
		t.Fatalf("full scope: %d %v", len(out), err)
	}
}
func TestApplyFrozenTargetPartialFailureAndBounds(t *testing.T) {
	f := &fakeClient{seqs: map[string]*msg.Seqs{"si_a_b": {MaxSeq: 20}, "sg_fail": {MaxSeq: 10}, "sg_closed": {MaxSeq: 3}}, fail: "sg_fail"}
	out, err := New(f).Apply(context.Background(), "a", []Target{{"si_a_b", 5}, {"sg_fail", 8}, {"sg_closed", 9}})
	if err != nil || !out[0].Success || out[1].Success || out[2].Success {
		t.Fatalf("%v %v", out, err)
	}
	for _, r := range f.calls {
		if r.UserID != "a" || r.ConversationID == "sg_closed" || (r.ConversationID == "si_a_b" && r.HasReadSeq != 5) {
			t.Fatalf("unsafe read: %v", r)
		}
	}
}
func TestReceiptChunksAndConcurrency(t *testing.T) {
	f := &fakeClient{seqs: map[string]*msg.Seqs{}, delay: time.Millisecond}
	targets := []Target{{"si_a_b", 5001}}
	f.seqs["si_a_b"] = &msg.Seqs{MaxSeq: 6000}
	for i := 0; i < 99; i++ {
		id := fmt.Sprintf("sg_%d", i)
		f.seqs[id] = &msg.Seqs{MaxSeq: 10}
		targets = append(targets, Target{id, 10})
	}
	out, err := New(f).Apply(context.Background(), "a", targets)
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range out {
		if !r.Success {
			t.Fatal(r)
		}
	}
	if f.peak > 8 || f.peak < 2 {
		t.Fatalf("peak %d", f.peak)
	}
	var cursors []int64
	for _, r := range f.calls {
		if r.ConversationID == "si_a_b" {
			cursors = append(cursors, r.HasReadSeq)
		}
	}
	if fmt.Sprint(cursors) != "[2000 4000 5001]" {
		t.Fatal(cursors)
	}
}
func TestRejectInvalidOrUnauthorizedBeforeWrites(t *testing.T) {
	f := &fakeClient{snapshotErr: errors.New("denied")}
	s := New(f)
	for _, targets := range [][]Target{nil, {{"sg_a", 0}}, {{"sg_a", 1}, {"sg_a", 1}}, make([]Target, 101), {{"sg_a", 1}}} {
		if _, err := s.Apply(context.Background(), "a", targets); err == nil {
			t.Fatal("accepted invalid batch")
		}
	}
	if _, err := s.Apply(context.Background(), "", []Target{{"sg_a", 1}}); err == nil {
		t.Fatal("anonymous")
	}
	if len(f.calls) != 0 {
		t.Fatal("unauthorized writes")
	}
}
func TestCanceledBatchAndIdempotentRetry(t *testing.T) {
	f := &fakeClient{seqs: map[string]*msg.Seqs{"sg_a": {MaxSeq: 20, HasReadSeq: 10}, "sg_b": {MaxSeq: 20}}}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	out, err := New(f).Apply(ctx, "a", []Target{{"sg_b", 8}})
	if err != nil || out[0].Success {
		t.Fatalf("%v %v", out, err)
	}
	out, err = New(f).Apply(context.Background(), "a", []Target{{"sg_a", 8}})
	if err != nil || !out[0].Success || len(f.calls) != 0 {
		t.Fatalf("retry advanced cursor: %v %v", out, err)
	}
}
