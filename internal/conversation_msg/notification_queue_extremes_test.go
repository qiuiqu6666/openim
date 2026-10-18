package conversation_msg

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/openimsdk/openim-sdk-core/v3/internal/group"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/sdk_struct"
	"github.com/openimsdk/protocol/sdkws"
)

// Use the real Conversation scheduling policy with a deterministic notification
// handler. Group notifications can hold the group lock and emit many updates.
type notificationBurstWorker struct {
	Conversation
	queue    chan common.Cmd2Value
	started  chan struct{}
	produced chan error
	finish   chan struct{}
	applied  chan error
}

type expiringGroupNotificationDB struct{ notificationCheckpointDB }

func (d *expiringGroupNotificationDB) GetVersionSync(ctx context.Context, _, _ string) (*model_struct.LocalVersionSync, error) {
	if _, ok := ctx.Deadline(); !ok {
		return nil, errors.New("running notification lost its receipt deadline")
	}
	<-ctx.Done()
	return nil, ctx.Err()
}

func TestRunningGroupNotificationHonorsReceiptDeadline(t *testing.T) {
	d := &expiringGroupNotificationDB{notificationCheckpointDB{seq: 1}}
	c := &Conversation{db: d, group: group.NewGroup("self", d, nil)}
	msg := &sdkws.MsgData{Seq: 2, ContentType: constant.GroupInfoSetNameNotification, Content: []byte(`{"detail":"{\"group\":{\"groupID\":\"g\"},\"groupMemberVersion\":1,\"groupMemberVersionID\":\"friends\"}"}`)}
	cmd := common.Cmd2Value{Ctx: context.Background(), ExpiresAt: time.Now().Add(20 * time.Millisecond), Value: sdk_struct.CmdNewMsgComeToConversation{Msgs: map[string]*sdkws.PullMsgs{"n_group": {Msgs: []*sdkws.MsgData{msg}}}}}
	if err := c.doNotificationManager(cmd); !errors.Is(err, context.DeadlineExceeded) || d.seq != 1 {
		t.Fatalf("expired in-flight notification must remain retryable: err=%v seq=%d", err, d.seq)
	}
}

func (w *notificationBurstWorker) GetCh() chan common.Cmd2Value { return w.queue }
func (w *notificationBurstWorker) Work(cmd common.Cmd2Value) {
	if cmd.Cmd != constant.CmdNotification {
		w.applied <- cmd.Ctx.Err()
		return
	}
	close(w.started)
	for i := 0; i < 1005; i++ {
		select {
		case w.queue <- common.Cmd2Value{Cmd: constant.CmdUpdateConversation, Ctx: cmd.Ctx}:
		case <-cmd.Ctx.Done():
			w.produced <- cmd.Ctx.Err()
			return
		}
	}
	w.produced <- nil
	select {
	case <-w.finish:
	case <-cmd.Ctx.Done():
	}
}

func TestGroupNotificationBurstDrainsWithoutConcurrentWrites(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	w := &notificationBurstWorker{queue: make(chan common.Cmd2Value, 1000), started: make(chan struct{}), produced: make(chan error, 1), finish: make(chan struct{}), applied: make(chan error, 1006)}
	done := make(chan struct{})
	go func() { defer close(done); common.DoListener(ctx, w) }()
	w.queue <- common.Cmd2Value{Cmd: constant.CmdNotification, Ctx: ctx}
	<-w.started
	w.queue <- common.Cmd2Value{Cmd: constant.CmdNewMsgCome, Ctx: ctx}
	if err := <-w.produced; err != nil {
		<-done
		t.Fatalf("notification filled its own queue: %v", err)
	}
	select {
	case <-w.applied:
		t.Error("message applied while notification still running")
	default:
	}
	close(w.finish)
	for i := 0; i < 1006; i++ {
		select {
		case err := <-w.applied:
			if err != nil {
				t.Errorf("follow-up cancelled: %v", err)
			}
		case <-ctx.Done():
			t.Fatal("queued update lost")
		}
	}
	cancel()
	<-done
}

func TestGroupNotificationFailureKeepsCheckpointForReplay(t *testing.T) {
	for _, failure := range []error{errors.New("disk full"), context.DeadlineExceeded, context.Canceled} {
		t.Run(failure.Error(), func(t *testing.T) {
			d := &notificationCheckpointDB{seq: 1, profileErr: failure}
			c := &Conversation{db: d, group: group.NewGroup("self", d, nil)}
			msg := &sdkws.MsgData{Seq: 3, ContentType: constant.GroupInfoSetNameNotification, Content: []byte(`{"detail":"{\"group\":{\"groupID\":\"g\",\"groupName\":\"New\"},\"groupMemberVersion\":1,\"groupMemberVersionID\":\"friends\"}"}`)}
			cmd := common.Cmd2Value{Ctx: context.Background(), Value: sdk_struct.CmdNewMsgComeToConversation{Msgs: map[string]*sdkws.PullMsgs{"n_group": {Msgs: []*sdkws.MsgData{{Seq: 2, Status: constant.MsgStatusHasDeleted}, msg}}}}}
			if err := c.doNotificationManager(cmd); !errors.Is(err, failure) || d.seq != 1 {
				t.Fatalf("failed group notification acknowledged: err=%v seq=%d", err, d.seq)
			}
			d.profileErr = nil
			if err := c.doNotificationManager(cmd); err != nil || d.seq != 3 {
				t.Fatalf("replay failed: err=%v seq=%d", err, d.seq)
			}
		})
	}
}
