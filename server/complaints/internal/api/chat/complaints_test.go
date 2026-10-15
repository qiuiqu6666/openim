package chat

import (
	"context"
	"github.com/openimsdk/chat/pkg/common/imapi"
	"github.com/openimsdk/chat/pkg/complaints"
	"github.com/openimsdk/protocol/sdkws"
	"testing"
)

type complaintIM struct {
	imapi.CallerInterface
	member, exists bool
}

func (i complaintIM) ImAdminTokenWithDefaultAdmin(context.Context) (string, error) {
	return "test", nil
}
func (i complaintIM) AccountCheckSingle(context.Context, string) (bool, error) { return i.exists, nil }
func (i complaintIM) FindGroupInfo(context.Context, []string) ([]*sdkws.GroupInfo, error) {
	return []*sdkws.GroupInfo{{GroupID: "g", OwnerUserID: "real-owner"}}, nil
}
func (i complaintIM) GroupMemberRoles(context.Context, string, []string) (map[string]int32, error) {
	if i.member {
		return map[string]int32{"reporter": 20}, nil
	}
	return map[string]int32{}, nil
}
func TestComplaintGroupMembershipAndServerTarget(t *testing.T) {
	p := complaints.Payload{GroupID: "g", ReportedUserID: "forged"}
	a := &Api{imApiCaller: complaintIM{member: true}}
	if err := a.validateComplaint(context.Background(), "reporter", &p, "group"); err != nil {
		t.Fatal(err)
	}
	if p.ReportedUserID != "real-owner" {
		t.Fatal("client selected the group owner")
	}
	a.imApiCaller = complaintIM{}
	if err := a.validateComplaint(context.Background(), "reporter", &p, "group"); err == nil {
		t.Fatal("nonmember accepted")
	}
}
func TestComplaintC2CRequiresExistingUser(t *testing.T) {
	p := complaints.Payload{ReportedUserID: "peer"}
	a := &Api{imApiCaller: complaintIM{exists: false}}
	if err := a.validateComplaint(context.Background(), "reporter", &p, "c2c"); err == nil {
		t.Fatal("nonexistent user accepted")
	}
	a.imApiCaller = complaintIM{exists: true}
	if err := a.validateComplaint(context.Background(), "reporter", &p, "c2c"); err != nil {
		t.Fatal(err)
	}
}
