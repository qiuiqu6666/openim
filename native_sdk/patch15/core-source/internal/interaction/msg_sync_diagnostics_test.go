package interaction

import (
	"github.com/openimsdk/protocol/sdkws"
	"testing"
)

func TestSyncDiagnosticDistinguishesMissingEmptyAndDeleted(t *testing.T) {
	if describeSyncPacket(nil).Present {
		t.Fatal("missing packet reported present")
	}
	empty := describeSyncPacket(&sdkws.PullMsgs{IsEnd: true, EndSeq: 9})
	if !empty.Present || empty.Count != 0 || !empty.IsEnd || empty.EndSeq != 9 {
		t.Fatalf("lost empty boundary: %+v", empty)
	}
	packet := &sdkws.PullMsgs{Msgs: []*sdkws.MsgData{{Seq: 12, Status: 4}, nil, {Seq: 10, Status: 2}}}
	s := describeSyncPacket(packet)
	if s.Count != 3 || s.MinSeq != 10 || s.MaxSeq != 12 || s.Deleted != 1 || s.NilRows != 1 {
		t.Fatalf("wrong summary: %+v", s)
	}
	if packet.Msgs[0].Seq != 12 || packet.Msgs[1] != nil {
		t.Fatal("diagnostics mutated response")
	}
}
