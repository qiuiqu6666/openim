package interaction

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

type startupSnapshotDB struct {
	*recoveryVersionDB
	ids           []string
	reads, legacy int
	failure       error
}

func (d *startupSnapshotDB) GetAllConversationIDList(context.Context) ([]string, error) {
	return d.ids, nil
}
func (d *startupSnapshotDB) GetMessageRecoveryVersions(context.Context, string) ([]*model_struct.LocalVersionSync, error) {
	d.reads++
	if d.failure != nil {
		return nil, d.failure
	}
	var rows []*model_struct.LocalVersionSync
	for _, row := range d.journal {
		rows = append(rows, row)
	}
	return rows, nil
}
func (d *startupSnapshotDB) CheckConversationNormalMsgSeq(_ context.Context, id string) (int64, error) {
	if id != "legacy" {
		panic("persisted coverage queried MAX(seq)")
	}
	d.legacy++
	return 99, nil
}
func (d *startupSnapshotDB) GetVersionSync(context.Context, string, string) (*model_struct.LocalVersionSync, error) {
	panic("snapshot performed per-record checkpoint reads")
}

func TestStartupUsesOneCheckpointSnapshotAndPreservesLegacyGaps(t *testing.T) {
	ctx := recoveryContext(t)
	d := &startupSnapshotDB{recoveryVersionDB: &recoveryVersionDB{installed: true, journal: make(map[string]*model_struct.LocalVersionSync)}}
	for n := 0; n < 1000; n++ {
		id := fmt.Sprintf("sg_%04d", n)
		d.ids = append(d.ids, id)
		d.journal[id] = &model_struct.LocalVersionSync{EntityID: "conversation:" + id, VersionID: `{"completed":5,"target":1000,"covered":[[901,1000]]}`}
	}
	d.ids = append(d.ids, "legacy")
	m, err := NewMsgSyncer(ctx, nil, nil, "self", nil, d, 0)
	if err != nil {
		t.Fatal(err)
	}
	if d.reads != 1 || d.legacy != 1 {
		t.Fatalf("startup reads=%d legacy=%d", d.reads, d.legacy)
	}
	if m.syncedMaxSeqs["sg_0000"] != 5 || m.checkpoints["sg_0000"].Target != 1000 || !m.messageAlreadyCovered("sg_0000", 999) {
		t.Fatal("durable sparse coverage changed")
	}
	if m.syncedMaxSeqs["legacy"] != 0 || m.checkpoints["legacy"].Target != 99 {
		t.Fatal("legacy MAX(seq) was mistaken for coverage")
	}
}

func TestStartupSnapshotFailureDoesNotPretendCoverageWasLoaded(t *testing.T) {
	d := &startupSnapshotDB{recoveryVersionDB: &recoveryVersionDB{installed: true}, failure: errors.New("disk read failed")}
	if _, err := NewMsgSyncer(recoveryContext(t), nil, nil, "self", nil, d, 0); err == nil {
		t.Fatal("snapshot failure was swallowed")
	}
}
