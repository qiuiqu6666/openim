package chat

import (
	"context"
	"github.com/gin-gonic/gin"
	"github.com/openimsdk/chat/pkg/common/constant"
	"github.com/openimsdk/chat/pkg/common/mctx"
	"github.com/openimsdk/chat/pkg/complaints"
	"github.com/openimsdk/tools/errs"
)

func (o *Api) validateComplaint(ctx context.Context, owner string, p *complaints.Payload, kind string) error {
	token, err := o.imApiCaller.ImAdminTokenWithDefaultAdmin(ctx)
	if err != nil {
		return err
	}
	ctx = mctx.WithApiToken(ctx, token)
	if kind == "c2c" {
		exists, err := o.imApiCaller.AccountCheckSingle(ctx, p.ReportedUserID)
		if err != nil {
			return err
		}
		if !exists {
			return complaints.ErrUser.Wrap()
		}
		return nil
	}
	groups, err := o.imApiCaller.FindGroupInfo(ctx, []string{p.GroupID})
	if err != nil {
		return err
	}
	if len(groups) != 1 {
		return errs.ErrArgs.WrapMsg("group does not exist")
	}
	roles, err := o.imApiCaller.GroupMemberRoles(ctx, p.GroupID, []string{owner})
	if err != nil {
		return err
	}
	if _, ok := roles[owner]; !ok {
		return complaints.ErrMembership.Wrap()
	}
	// The group settings entry reports the group; bind the current owner server-side.
	p.ReportedUserID = groups[0].OwnerUserID
	return nil
}
func (o *Api) CreateComplaint(c *gin.Context) {
	owner, _ := c.Get(constant.RpcOpUserID)
	id, _ := owner.(string)
	kind := "c2c"
	if c.FullPath() == "/complaints/group" {
		kind = "group"
	}
	o.complaints.Create(c, id, kind)
}
