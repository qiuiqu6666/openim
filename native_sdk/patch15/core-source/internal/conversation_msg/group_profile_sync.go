package conversation_msg

import (
	"context"

	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/db_interface"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/utils"
)

// Reconcile after both group and conversation sync have completed. Group rows
// may already be current while a previous version left the conversation stale.
// Only profile columns are written; drafts, unread counts and history survive.
func (c *Conversation) reconcileGroupConversationProfiles(ctx context.Context) error {
	if paged, ok := c.db.(db_interface.GroupConversationProfileSync); ok {
		var after string
		for {
			if err := ctx.Err(); err != nil {
				return err
			}
			rows, err := paged.ReconcileGroupConversationProfilePage(ctx, after, 128)
			if err != nil {
				return err
			}
			if len(rows) == 0 {
				return nil
			}
			c.ConversationListener().OnConversationChanged(utils.StructToJsonString(rows))
			after = rows[len(rows)-1].ConversationID
		}
	}
	groups, err := c.db.GetJoinedGroupListDB(ctx)
	if err != nil {
		return err
	}
	byID := make(map[string]*model_struct.LocalGroup, len(groups))
	for _, group := range groups {
		byID[group.GroupID] = group
	}
	rows, err := c.db.GetAllConversationListDB(ctx)
	if err != nil {
		return err
	}
	changed := make([]*model_struct.LocalConversation, 0)
	defer func() {
		// Publish successful rows even if a later row fails. The next attempt
		// sees those rows as current and would otherwise miss their callback.
		if len(changed) > 0 && ctx.Err() == nil {
			c.ConversationListener().OnConversationChanged(utils.StructToJsonString(changed))
		}
	}()
	for _, row := range rows {
		if err := ctx.Err(); err != nil {
			return err
		}
		if row.ConversationType != constant.ReadGroupChatType && row.ConversationType != constant.WriteGroupChatType {
			continue
		}
		group := byID[row.GroupID]
		if group == nil || (row.ShowName == group.GroupName && row.FaceURL == group.FaceURL) {
			continue
		}
		if err := c.db.UpdateColumnsConversation(ctx, row.ConversationID, map[string]interface{}{
			"show_name": group.GroupName, "face_url": group.FaceURL,
		}); err != nil {
			return err
		}
		updated := *row
		updated.ShowName, updated.FaceURL = group.GroupName, group.FaceURL
		changed = append(changed, &updated)
	}
	return nil
}
