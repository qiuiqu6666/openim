package database

import (
	"context"
	"github.com/openimsdk/chat/pkg/common/fundsecurity"
	"time"

	"github.com/openimsdk/chat/pkg/common/db/dbutil"
	chatdb "github.com/openimsdk/chat/pkg/common/db/table/chat"
	"github.com/openimsdk/chat/pkg/eerrs"
	"github.com/openimsdk/chat/pkg/grouplive"
	"github.com/openimsdk/tools/errs"
	"go.mongodb.org/mongo-driver/mongo"
)

func (o *ChatDatabase) ApplyLiveCallback(ctx context.Context, eventID, streamID, channelID, app string, eventType int, eventTime int64, now time.Time, grace time.Duration) (*chatdb.LiveSession, *chatdb.GroupFeature, bool, error) {
	session, err := o.findCallbackSession(ctx, streamID, channelID, app)
	if err != nil {
		return nil, nil, false, err
	}
	if session == nil {
		err = o.live.InsertCallback(ctx, &chatdb.LiveCallback{EventID: eventID, StreamID: streamID, Result: "ignored", EventTime: eventTime, CreatedAt: now})
		if err != nil && !liveDup(err) {
			return nil, nil, false, err
		}
		return nil, nil, false, nil
	}
	var feature *chatdb.GroupFeature
	changed := false
	err = o.tx.Transaction(ctx, func(ctx context.Context) error {
		if err = o.live.InsertCallback(ctx, &chatdb.LiveCallback{EventID: eventID, StreamID: streamID, SessionID: session.SessionID, Result: "accepted", EventTime: eventTime, CreatedAt: now}); err != nil {
			return err
		}
		row, err := o.live.TakeSession(ctx, session.SessionID)
		if err != nil {
			return err
		}
		if eventTime > 0 && row.LastEventTime > 0 && eventTime < row.LastEventTime {
			return nil
		}
		if eventTime > 0 {
			row.LastEventTime = eventTime
		}
		public := false
		switch eventType {
		case 1:
			if grouplive.TerminalBiz(row.Status) {
				row.UpdatedAt = now
				return o.live.SaveSession(ctx, row)
			}
			row.DisconnectAt = nil
			if row.Status != chatdb.LiveStatusLive {
				row.Status = chatdb.LiveStatusLive
				if row.StartedAt == nil {
					row.StartedAt = &now
				}
				row.Version++
				public = true
			}
		case 0:
			if row.Status != chatdb.LiveStatusLive {
				row.UpdatedAt = now
				return o.live.SaveSession(ctx, row)
			}
			if grace <= 0 {
				row.Status = chatdb.LiveStatusEnded
				row.EndedAt = &now
				row.EndReason = "disconnect"
				row.Active = false
				row.DisconnectAt = nil
				row.Version++
				public = true
			} else if row.DisconnectAt == nil {
				row.DisconnectAt = &now
			}
		default:
			row.UpdatedAt = now
			return o.live.SaveSession(ctx, row)
		}
		row.UpdatedAt = now
		if err = o.live.SaveSession(ctx, row); err != nil {
			return err
		}
		session = row
		if !public {
			return nil
		}
		feature, err = o.prepareFeature(ctx, row.GroupID)
		if err != nil {
			return err
		}
		applyLiveFeature(feature, row, now, grouplive.TerminalBiz(row.Status))
		if err = o.live.SaveFeature(ctx, feature); err != nil {
			return err
		}
		changed = true
		return o.queueLiveSync(ctx, row.GroupID, feature.Revision, now)
	})
	if err != nil {
		if liveDup(err) {
			return session, feature, false, nil
		}
		return nil, nil, false, err
	}
	if feature == nil && session != nil {
		feature, err = o.TakeGroupFeature(ctx, session.GroupID)
		if err != nil {
			return nil, nil, false, err
		}
	}
	return session, feature, changed, nil
}

func (o *ChatDatabase) PromoteDueLives(ctx context.Context, now time.Time, limit int64) ([]string, error) {
	rows, err := o.live.ListPromote(ctx, now, limit)
	if err != nil {
		return nil, err
	}
	var groups []string
	for _, row := range rows {
		ok, err := o.promoteLive(ctx, row.SessionID, now)
		if err != nil {
			return groups, err
		}
		if ok {
			groups = append(groups, row.GroupID)
		}
	}
	return groups, nil
}

func (o *ChatDatabase) FinishDisconnectedLives(ctx context.Context, now time.Time, grace time.Duration, limit int64) ([]string, error) {
	if grace < 0 {
		grace = 0
	}
	rows, err := o.live.ListDisconnect(ctx, now.Add(-grace), limit)
	if err != nil {
		return nil, err
	}
	var groups []string
	for _, row := range rows {
		_, _, changed, err := o.finishDisconnect(ctx, row.SessionID, now, grace)
		if err != nil {
			return groups, err
		}
		if changed {
			groups = append(groups, row.GroupID)
		}
	}
	return groups, nil
}

func (o *ChatDatabase) FinishLiveSync(ctx context.Context, groupID string, revision int64) error {
	return o.tx.Transaction(ctx, func(ctx context.Context) error {
		task, err := o.live.TakeSync(ctx, groupID)
		if err != nil {
			return err
		}
		if task.Revision != revision {
			// A slower earlier OpenIM write may have completed after the newer one.
			// Re-publish the latest canonical version, even if it was marked synced.
			task.Pending = true
			task.NextAt = time.Now()
		} else {
			task.Pending = false
		}
		return o.live.SaveSync(ctx, task)
	})
}

func (o *ChatDatabase) DelayLiveSync(ctx context.Context, groupID string, now time.Time) error {
	return o.tx.Transaction(ctx, func(ctx context.Context) error {
		task, err := o.live.TakeSync(ctx, groupID)
		if err != nil {
			return err
		}
		if !task.Pending {
			return nil
		}
		task.Attempts++
		wait := time.Duration(task.Attempts) * 2 * time.Second
		if wait > time.Minute {
			wait = time.Minute
		}
		task.NextAt = now.Add(wait)
		return o.live.SaveSync(ctx, task)
	})
}

func (o *ChatDatabase) ListDueLiveSync(ctx context.Context, now time.Time, limit int64) ([]*chatdb.LiveSyncTask, error) {
	return o.live.ListDueSync(ctx, now, limit)
}

func (o *ChatDatabase) CreateLiveTip(ctx context.Context, userID, clientOrderID, sessionID, anchor, currency, memo, paramHash string, amount int64, now time.Time) (*chatdb.LiveTip, error) {
	var saved *chatdb.LiveTip
	err := o.tx.Transaction(ctx, func(ctx context.Context) error {
		existing, err := o.live.TakeTip(ctx, userID, clientOrderID)
		if err == nil {
			if existing.ParamHash != paramHash {
				return eerrs.ErrIdempotencyConflict.Wrap()
			}
			saved = existing
			return nil
		}
		if !dbutil.IsDBNotFound(err) {
			return err
		}
		session, err := o.live.TakeSession(ctx, sessionID)
		if err != nil {
			return err
		}
		if session.Status != chatdb.LiveStatusLive || session.AnchorUserID != anchor {
			return eerrs.ErrLiveStateInvalid.Wrap()
		}
		if err = o.fund.DebitAvailable(ctx, userID, currency, amount); err != nil {
			return err
		}
		if err = fundsecurity.RunSpendGuard(ctx); err != nil {
			return err
		}
		if err = o.fund.CreditAvailable(ctx, anchor, currency, amount); err != nil {
			return err
		}
		orderID, err := newFundOrderID()
		if err != nil {
			return err
		}
		tipID, err := o.live.NextTipID(ctx)
		if err != nil {
			return err
		}

		order := &chatdb.FundOrder{
			OrderID: orderID, ClientOrderID: clientOrderID, Biz: chatdb.FundBizLiveTip, Scene: chatdb.FundSceneGroup,
			Currency: currency, SenderID: userID, RecvID: anchor, GroupID: session.GroupID, Amount: amount,
			Status: chatdb.FundStatusDone, CreatedAt: now, MessageSent: true, Remark: memo,
		}
		if err = o.fund.InsertOrder(ctx, order); err != nil {
			return err
		}
		if err = o.writeFundJournal(ctx, userID, currency, chatdb.FundBizLiveTip, orderID+":out", -amount, 0, now); err != nil {
			return err
		}
		if err = o.writeFundJournal(ctx, anchor, currency, chatdb.FundBizLiveTip, orderID+":in", amount, 0, now); err != nil {
			return err
		}
		saved = &chatdb.LiveTip{
			TipID: tipID, UserID: userID, ClientOrder: clientOrderID, SessionID: sessionID, Currency: currency,
			Amount: amount, Memo: memo, ParamHash: paramHash, FundOrderID: orderID, CreatedAt: now,
		}
		return o.live.InsertTip(ctx, saved)
	})
	if err != nil {
		if liveDup(err) {
			existing, takeErr := o.live.TakeTip(ctx, userID, clientOrderID)
			if takeErr != nil {
				return nil, fundErr(err)
			}
			if existing.ParamHash != paramHash {
				return nil, eerrs.ErrIdempotencyConflict.Wrap()
			}
			return existing, nil
		}
		return nil, fundErr(err)
	}
	return saved, nil
}

func (o *ChatDatabase) promoteLive(ctx context.Context, sessionID string, now time.Time) (bool, error) {
	changed := false
	err := o.tx.Transaction(ctx, func(ctx context.Context) error {
		row, err := o.live.TakeSession(ctx, sessionID)
		if err != nil {
			return err
		}
		if row.Status != chatdb.LiveStatusScheduled || !row.Active || row.ScheduledStartAt == nil || row.ScheduledStartAt.After(now) {
			return nil
		}
		row.Status = chatdb.LiveStatusAuthorized
		row.Version++
		row.UpdatedAt = now
		feature, err := o.prepareFeature(ctx, row.GroupID)
		if err != nil {
			return err
		}
		applyLiveFeature(feature, row, now, false)
		if err = o.live.SaveSession(ctx, row); err != nil {
			return err
		}
		if err = o.live.SaveFeature(ctx, feature); err != nil {
			return err
		}
		changed = true
		return o.queueLiveSync(ctx, row.GroupID, feature.Revision, now)
	})
	return changed, err
}

func (o *ChatDatabase) finishDisconnect(ctx context.Context, sessionID string, now time.Time, grace time.Duration) (*chatdb.LiveSession, *chatdb.GroupFeature, bool, error) {
	var feature *chatdb.GroupFeature
	changed := false
	err := o.tx.Transaction(ctx, func(ctx context.Context) error {
		row, err := o.live.TakeSession(ctx, sessionID)
		if err != nil {
			return err
		}
		if row.Status != chatdb.LiveStatusLive || !row.Active || row.DisconnectAt == nil || row.DisconnectAt.After(now.Add(-grace)) {
			return nil
		}
		row.Status = chatdb.LiveStatusEnded
		row.EndedAt = &now
		row.EndReason = "disconnect"
		row.Active = false
		row.DisconnectAt = nil
		row.Version++
		row.UpdatedAt = now
		feature, err = o.prepareFeature(ctx, row.GroupID)
		if err != nil {
			return err
		}
		applyLiveFeature(feature, row, now, true)
		if err = o.live.SaveSession(ctx, row); err != nil {
			return err
		}
		if err = o.live.SaveFeature(ctx, feature); err != nil {
			return err
		}
		changed = true
		return o.queueLiveSync(ctx, row.GroupID, feature.Revision, now)
	})
	return nil, feature, changed, err
}

func (o *ChatDatabase) findCallbackSession(ctx context.Context, streamID, channelID, app string) (*chatdb.LiveSession, error) {
	names := []string{streamID, channelID}
	if app != "" && streamID != "" {
		names = append(names, app+"_"+streamID, app+"/"+streamID)
	}
	for _, name := range names {
		if name == "" {
			continue
		}
		row, err := o.live.FindStream(ctx, name)
		if err == nil {
			return row, nil
		}
		if !dbutil.IsDBNotFound(err) {
			return nil, err
		}
		row, err = o.live.TakeSession(ctx, name)
		if err == nil {
			return row, nil
		}
		if !dbutil.IsDBNotFound(err) {
			return nil, err
		}
	}
	return nil, nil
}

func (o *ChatDatabase) prepareFeature(ctx context.Context, groupID string) (*chatdb.GroupFeature, error) {
	row, err := o.live.TakeFeature(ctx, groupID)
	if err != nil {
		if dbutil.IsDBNotFound(err) {
			return &chatdb.GroupFeature{GroupID: groupID, Games: string(grouplive.DefaultGames())}, nil
		}
		return nil, err
	}
	if row.Games == "" {
		row.Games = string(grouplive.DefaultGames())
	}
	return row, nil
}

func (o *ChatDatabase) queueLiveSync(ctx context.Context, groupID string, revision int64, now time.Time) error {
	return o.live.SaveSync(ctx, &chatdb.LiveSyncTask{GroupID: groupID, Revision: revision, NextAt: now, Pending: true})
}

func applyLiveFeature(feature *chatdb.GroupFeature, session *chatdb.LiveSession, now time.Time, bumpCapability bool) {
	feature.GroupID = session.GroupID
	feature.Revision++
	if bumpCapability {
		feature.CapabilityVersion++
	}
	feature.Status = session.Status
	feature.SessionID = session.SessionID
	feature.RoomName = session.RoomName
	feature.Description = session.Description
	feature.AnchorUserID = session.AnchorUserID
	feature.ScheduledStartAt = nil
	if session.ScheduledStartAt != nil && !session.ScheduledStartAt.IsZero() {
		ms := session.ScheduledStartAt.UnixMilli()
		feature.ScheduledStartAt = &ms
	}
	feature.UpdatedAt = now
	if feature.Games == "" {
		feature.Games = string(grouplive.DefaultGames())
	}
}

func liveDup(err error) bool {
	return mongo.IsDuplicateKeyError(err) || mongo.IsDuplicateKeyError(errs.Unwrap(err))
}

func (o *ChatDatabase) TakeLiveTip(ctx context.Context, userID, clientOrderID string) (*chatdb.LiveTip, error) {
	return o.live.TakeTip(ctx, userID, clientOrderID)
}
