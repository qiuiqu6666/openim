package group

import (
	"context"
	"errors"
	"net/http"
	"sync/atomic"
	"testing"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/common"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
)

type joinedVersionFailureDB struct {
	*joinedResumeDB
	fail bool
}

func (d *joinedVersionFailureDB) SetVersionSync(ctx context.Context, version *model_struct.LocalVersionSync) error {
	if d.fail {
		return errors.New("injected version persistence failure")
	}
	return d.joinedResumeDB.SetVersionSync(ctx, version)
}

func TestJoinedGroupRetainsSnapshotUntilVersionCommit(t *testing.T) {
	var pages, idRequests atomic.Int32
	ctx := groupProfileServer(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/group/get_incremental_join_groups":
			profileResponse(w, map[string]any{"full": true, "versionID": "v", "version": 1})
		case "/group/get_joined_group_list":
			pages.Add(1)
			profileResponse(w, map[string]any{"groups": []any{map[string]any{"groupID": "new"}}})
		case "/group/get_full_join_group_ids":
			idRequests.Add(1)
			profileResponse(w, map[string]any{"groupIDs": []string{"new"}})
		default:
			t.Errorf("unexpected endpoint %s", r.URL.Path)
		}
	})
	g, rows := newJoinedResumeGroup()
	d := &joinedVersionFailureDB{joinedResumeDB: rows, fail: true}
	g.db = d
	base := common.WithMetadataProgress(ctx, &common.MetadataProgress{})
	if _, err := g.IncrSyncJoinGroupAndGetIDs(base); err == nil {
		t.Fatal("version failure hidden")
	}
	d.fail = false
	writes := d.writes
	if _, err := g.IncrSyncJoinGroupAndGetIDs(base); err != nil {
		t.Fatal(err)
	}
	if pages.Load() != 1 || idRequests.Load() != 1 || d.saved != 1 || d.writes != writes {
		t.Fatal("retry discarded snapshot or rewrote committed rows")
	}
	// Even when the parent obligation has other pending work, a completed
	// group refresh releases its snapshot and observes a new full response.
	if _, err := g.IncrSyncJoinGroupAndGetIDs(base); err != nil {
		t.Fatal(err)
	}
	if pages.Load() != 2 || idRequests.Load() != 2 {
		t.Fatal("completed snapshot reused by later refresh")
	}
}
