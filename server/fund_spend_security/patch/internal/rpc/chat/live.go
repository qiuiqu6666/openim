package chat

import (
	"context"
	"encoding/json"
	"github.com/openimsdk/chat/pkg/common/db/dbutil"
	"reflect"
	"strconv"
	"time"

	"github.com/google/uuid"
	chatdb "github.com/openimsdk/chat/pkg/common/db/table/chat"
	"github.com/openimsdk/chat/pkg/common/mctx"
	"github.com/openimsdk/chat/pkg/eerrs"
	"github.com/openimsdk/chat/pkg/grouplive"
	livepb "github.com/openimsdk/chat/pkg/protocol/live"
	constantpb "github.com/openimsdk/protocol/constant"
	"github.com/openimsdk/tools/errs"
	"github.com/openimsdk/tools/log"
)

func (o *chatSvr) GetLiveConfig(ctx context.Context, _ *livepb.GetLiveConfigReq) (*livepb.LiveConfig, error) {
	if _, err := mctx.CheckAdmin(ctx); err != nil {
		return nil, err
	}
	cfg, err := o.Database.GetLiveConfig(ctx)
	if err != nil {
		return nil, err
	}
	return liveConfigPB(cfg), nil
}

func (o *chatSvr) PutLiveConfig(ctx context.Context, req *livepb.PutLiveConfigReq) (*livepb.LiveConfig, error) {
	if _, err := mctx.CheckAdmin(ctx); err != nil {
		return nil, err
	}
	push, err := grouplive.NormalizeDomain(req.PushDomain)
	if err != nil {
		return nil, errs.ErrArgs.WrapMsg("push domain invalid")
	}
	play, err := grouplive.NormalizeDomain(req.PlayDomain)
	if err != nil {
		return nil, errs.ErrArgs.WrapMsg("play domain invalid")
	}
	app, err := grouplive.NormalizeApp(req.AppName)
	if err != nil {
		return nil, errs.ErrArgs.WrapMsg("app name invalid")
	}
	if req.AuthTTLSeconds != 0 && (req.AuthTTLSeconds < 60 || req.AuthTTLSeconds > 86400) {
		return nil, errs.ErrArgs.WrapMsg("auth ttl invalid")
	}
	if req.DisconnectGraceSeconds < 0 || req.DisconnectGraceSeconds > 3600 {
		return nil, errs.ErrArgs.WrapMsg("disconnect grace invalid")
	}
	region, err := grouplive.NormalizeRegion(req.Region)
	if err != nil {
		return nil, errs.ErrArgs.WrapMsg("region invalid")
	}
	cfg := &chatdb.LiveConfig{
		PushDomain: push, PlayDomain: play, AppName: app, AuthKey: req.AuthKey,
		PushAuthKey: req.PushAuthKey, PlayAuthKey: req.PlayAuthKey, CallbackKey: req.CallbackKey,
		Region: region, SecretID: req.SecretId, SecretKey: req.SecretKey, AuthTTLSeconds: req.AuthTTLSeconds,
		DisconnectGraceSeconds: req.DisconnectGraceSeconds,
	}
	if err = o.Database.PutLiveConfig(ctx, cfg); err != nil {
		return nil, err
	}
	saved, err := o.Database.GetLiveConfig(ctx)
	if err != nil {
		return nil, err
	}
	return liveConfigPB(saved), nil
}

func (o *chatSvr) FeatureCapabilities(ctx context.Context, req *livepb.GroupReq) (*livepb.LivePayload, error) {
	userID, err := o.liveUser(ctx)
	if err != nil {
		return nil, err
	}
	if err = liveGroupID(req.GroupID); err != nil {
		return nil, err
	}
	member, manager, err := o.liveAccess(ctx, req.GroupID, userID)
	if err != nil {
		return nil, err
	}
	feature, err := o.Database.TakeGroupFeature(ctx, req.GroupID)
	if err != nil {
		return nil, err
	}
	sessionOpen := grouplive.ActiveBiz(feature.Status)
	caps := grouplive.CapsFor(member, manager, sessionOpen, member && feature.AnchorUserID == userID)
	ttl := grouplive.CacheTTL
	version := feature.CapabilityVersion
	if !member {
		caps = grouplive.Caps{}
		ttl = 0
	}
	return payload(grouplive.NewCapability(req.GroupID, version, ttl, caps))
}

func (o *chatSvr) CurrentLive(ctx context.Context, req *livepb.GroupReq) (*livepb.LivePayload, error) {
	userID, err := o.liveUser(ctx)
	if err != nil {
		return nil, err
	}
	if err = liveGroupID(req.GroupID); err != nil {
		return nil, err
	}
	if err = o.requireMember(ctx, req.GroupID, userID); err != nil {
		return nil, err
	}
	feature, err := o.Database.TakeGroupFeature(ctx, req.GroupID)
	if err != nil {
		return nil, err
	}
	raw, err := featureJSON(feature)
	if err != nil {
		return nil, err
	}
	body := grouplive.CurrentDTO{Active: false, GroupFeatures: raw}
	if grouplive.ActiveBiz(feature.Status) && feature.SessionID != "" {
		session, err := o.Database.TakeLiveSession(ctx, feature.SessionID)
		if err != nil {
			return nil, err
		}
		dto := sessionDTO(session)
		body.Active = true
		body.Session = &dto
	}
	return payload(body)
}

func (o *chatSvr) AuthorizeLive(ctx context.Context, req *livepb.AuthorizeLiveReq) (*livepb.LivePayload, error) {
	userID, err := o.liveUser(ctx)
	if err != nil {
		return nil, err
	}
	if err = liveGroupID(req.GroupID); err != nil {
		return nil, err
	}
	room, desc, err := grouplive.NormalizeText(req.RoomName, req.Description)
	if err != nil {
		return nil, errs.ErrArgs.WrapMsg("room name or description invalid")
	}
	if req.AnchorUserId == "" {
		return nil, errs.ErrArgs.WrapMsg("anchor empty")
	}
	scheduled, err := grouplive.ParseScheduled(req.ScheduledStartAt, time.Now())
	if err != nil {
		return nil, errs.ErrArgs.WrapMsg("scheduled start invalid")
	}
	if err = o.requireManager(ctx, req.GroupID, userID); err != nil {
		return nil, err
	}
	anchorMember, _, err := o.liveAccess(ctx, req.GroupID, req.AnchorUserId)
	if err != nil {
		return nil, err
	}
	if !anchorMember {
		return nil, errs.ErrArgs.WrapMsg("anchor is not a group member")
	}
	session, feature, err := o.Database.AuthorizeLiveSession(ctx, req.GroupID, userID, req.AnchorUserId, room, desc, scheduled, time.Now())
	if err != nil {
		return nil, err
	}
	status := o.syncLive(ctx, req.GroupID)
	o.notifyLiveCap(ctx, req.GroupID, req.AnchorUserId, feature.CapabilityVersion)
	return o.liveResult(session, feature, status)
}

func (o *chatSvr) ScheduleLive(ctx context.Context, req *livepb.ScheduleLiveReq) (*livepb.LivePayload, error) {
	userID, err := o.liveUser(ctx)
	if err != nil {
		return nil, err
	}
	if err = liveGroupID(req.GroupID); err != nil {
		return nil, err
	}
	room, _, err := grouplive.NormalizeText(req.RoomName, "")
	if err != nil {
		return nil, errs.ErrArgs.WrapMsg("room name invalid")
	}
	scheduled, err := grouplive.ParseScheduled(req.ScheduledStartAt, time.Now())
	if err != nil || scheduled == nil {
		return nil, errs.ErrArgs.WrapMsg("scheduled start invalid")
	}
	if err = o.requireManager(ctx, req.GroupID, userID); err != nil {
		return nil, err
	}
	session, feature, err := o.Database.ScheduleLiveSession(ctx, req.GroupID, room, *scheduled, time.Now())
	if err != nil {
		return nil, err
	}
	return o.liveResult(session, feature, o.syncLive(ctx, req.GroupID))
}

func (o *chatSvr) StopLive(ctx context.Context, req *livepb.GroupReq) (*livepb.LivePayload, error) {
	return o.finishLive(ctx, req.GroupID, chatdb.LiveStatusEnded, "stopped")
}

func (o *chatSvr) RevokeLive(ctx context.Context, req *livepb.GroupReq) (*livepb.LivePayload, error) {
	return o.finishLive(ctx, req.GroupID, chatdb.LiveStatusBanned, "revoked")
}

func (o *chatSvr) GetLiveSession(ctx context.Context, req *livepb.SessionReq) (*livepb.LivePayload, error) {
	userID, err := o.liveUser(ctx)
	if err != nil {
		return nil, err
	}
	session, err := o.Database.TakeLiveSession(ctx, req.SessionID)
	if err != nil {
		return nil, err
	}
	if err = o.requireMember(ctx, session.GroupID, userID); err != nil {
		return nil, err
	}
	feature, err := o.Database.TakeGroupFeature(ctx, session.GroupID)
	if err != nil {
		return nil, err
	}
	return o.liveResult(session, feature, "")
}

func (o *chatSvr) PlayInfo(ctx context.Context, req *livepb.SessionReq) (*livepb.LivePayload, error) {
	userID, err := o.liveUser(ctx)
	if err != nil {
		return nil, err
	}
	session, err := o.Database.TakeLiveSession(ctx, req.SessionID)
	if err != nil {
		return nil, err
	}
	if err = o.requireMember(ctx, session.GroupID, userID); err != nil {
		return nil, err
	}
	if !grouplive.ActiveBiz(session.Status) {
		return nil, eerrs.ErrLiveStateInvalid.Wrap()
	}
	cfg, err := o.Database.GetLiveConfig(ctx)
	if err != nil {
		return nil, err
	}
	expire := time.Now().Add(time.Duration(liveTTL(cfg)) * time.Second)
	urls, err := grouplive.Play(liveEdge(cfg), session.StreamName, expire)
	if err != nil {
		return nil, eerrs.ErrLiveNotConfigured.Wrap()
	}
	return payload(grouplive.PlayDTO{
		LiveSessionID: session.SessionID, RoomName: session.RoomName, AnchorUserID: session.AnchorUserID,
		Protocol: "hls", PlayURL: urls.HLS, FallbackFlvURL: urls.FLV, ExpiresAt: grouplive.ISO(expire),
	})
}

func (o *chatSvr) PushInfo(ctx context.Context, req *livepb.SessionReq) (*livepb.LivePayload, error) {
	userID, err := o.liveUser(ctx)
	if err != nil {
		return nil, err
	}
	session, err := o.Database.TakeLiveSession(ctx, req.SessionID)
	if err != nil {
		return nil, err
	}
	member, manager, err := o.liveAccess(ctx, session.GroupID, userID)
	if err != nil {
		return nil, err
	}
	if !member || !grouplive.ActiveBiz(session.Status) || !(manager || session.AnchorUserID == userID) {
		return nil, eerrs.ErrForbidden.WrapMsg("push forbidden")
	}
	cfg, err := o.Database.GetLiveConfig(ctx)
	if err != nil {
		return nil, err
	}
	expire := time.Now().Add(time.Duration(liveTTL(cfg)) * time.Second)
	server, key, err := grouplive.Push(liveEdge(cfg), session.StreamName, expire)
	if err != nil {
		return nil, eerrs.ErrLiveNotConfigured.Wrap()
	}
	return payload(grouplive.PushDTO{RtmpServer: server, StreamKey: key, ObsHint: grouplive.ObsHint, ExpiresAt: grouplive.ISO(expire)})
}

func (o *chatSvr) TipLive(ctx context.Context, req *livepb.TipLiveReq) (*livepb.LivePayload, error) {
	userID, err := o.liveUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.ClientOrderId == "" || req.Amount < 1 || req.Amount > grouplive.MaxTipAmount || !grouplive.AllowedCurrency(req.Currency) {
		return nil, errs.ErrArgs.WrapMsg("tip invalid")
	}
	memo, err := grouplive.NormalizeMemo(req.Memo)
	if err != nil {
		return nil, errs.ErrArgs.WrapMsg("memo invalid")
	}
	clientID, err := normalizeFundClientOrderID(req.ClientOrderId)
	if err != nil {
		return nil, err
	}
	req.ClientOrderId = clientID
	existing, takeErr := o.Database.TakeLiveTip(ctx, userID, req.ClientOrderId)
	if takeErr == nil && existing != nil {
		if existing.ParamHash != grouplive.TipHash(req.SessionID, req.Currency, memo, req.Amount) {
			return nil, eerrs.ErrIdempotencyConflict.Wrap()
		}
		return payload(grouplive.TipDTO{TipID: existing.TipID, LiveSessionID: existing.SessionID})
	}
	if takeErr != nil && !dbutil.IsDBNotFound(takeErr) {
		return nil, takeErr
	}
	if err = o.verifyFundPayPassword(ctx, userID, req.PayPin); err != nil {
		return nil, err
	}
	session, err := o.Database.TakeLiveSession(ctx, req.SessionID)
	if err != nil {
		return nil, err
	}
	if err = o.requireMember(ctx, session.GroupID, userID); err != nil {
		return nil, err
	}
	if session.Status != chatdb.LiveStatusLive || session.AnchorUserID == "" {
		return nil, eerrs.ErrLiveStateInvalid.Wrap()
	}
	securityOrder, err := o.normalizeFundTipSecurity(ctx, userID, req)
	if err != nil {
		return nil, err
	}
	ctx, err = o.secureFundSpend(ctx, userID, securityOrder, req.VerifyChallengeID, req.VerifyCode)
	if err != nil {
		return nil, err
	}
	tip, err := o.Database.CreateLiveTip(ctx, userID, req.ClientOrderId, session.SessionID, session.AnchorUserID, req.Currency, memo, grouplive.TipHash(session.SessionID, req.Currency, memo, req.Amount), req.Amount, time.Now())
	if err != nil {
		return nil, err
	}
	return payload(grouplive.TipDTO{TipID: tip.TipID, LiveSessionID: tip.SessionID})
}

func (o *chatSvr) TencentLiveCallback(ctx context.Context, req *livepb.TencentCallbackReq) (*livepb.LivePayload, error) {
	cb, err := grouplive.ParseCallback(req.Body)
	if err != nil {
		return nil, errs.ErrArgs.WrapMsg("callback invalid")
	}
	cfg, err := o.Database.GetLiveConfig(ctx)
	if err != nil {
		return nil, err
	}
	if err = grouplive.ValidCallback(liveCallbackKey(cfg), cb, time.Now()); err != nil {
		return nil, eerrs.ErrForbidden.WrapMsg("callback sign")
	}
	session, feature, changed, err := o.Database.ApplyLiveCallback(ctx, cb.EventID, cb.StreamID, cb.ChannelID, cfg.AppName, cb.EventType, cb.EventTime, time.Now(), time.Duration(cfg.DisconnectGraceSeconds)*time.Second)
	if err != nil {
		return nil, err
	}
	if changed && feature != nil {
		o.syncLive(ctx, feature.GroupID)
		if session != nil && grouplive.TerminalBiz(session.Status) {
			o.notifyLiveCap(ctx, feature.GroupID, session.AnchorUserID, feature.CapabilityVersion)
			o.dropLiveStream(ctx, cfg, session.StreamName)
		}
	}
	return &livepb.LivePayload{Json: "{}"}, nil
}

func (o *chatSvr) finishLive(ctx context.Context, groupID, status, reason string) (*livepb.LivePayload, error) {
	userID, err := o.liveUser(ctx)
	if err != nil {
		return nil, err
	}
	if err = liveGroupID(groupID); err != nil {
		return nil, err
	}
	if err = o.requireManager(ctx, groupID, userID); err != nil {
		return nil, err
	}
	session, feature, changed, err := o.Database.FinishLiveSession(ctx, groupID, status, reason, time.Now())
	if err != nil {
		return nil, err
	}
	syncStatus := ""
	if changed {
		syncStatus = o.syncLive(ctx, groupID)
		o.notifyLiveCap(ctx, groupID, session.AnchorUserID, feature.CapabilityVersion)
		cfg, cfgErr := o.Database.GetLiveConfig(ctx)
		if cfgErr == nil {
			o.dropLiveStream(ctx, cfg, session.StreamName)
		}
	}
	return o.liveResult(session, feature, syncStatus)
}

func (o *chatSvr) liveResult(session *chatdb.LiveSession, feature *chatdb.GroupFeature, syncStatus string) (*livepb.LivePayload, error) {
	raw, err := featureJSON(feature)
	if err != nil {
		return nil, err
	}
	body := grouplive.WriteDTO{SessionDTO: sessionDTO(session), GroupFeatures: raw}
	if syncStatus != "" {
		body.IMSyncStatus = syncStatus
	}
	return payload(body)
}

func (o *chatSvr) syncLive(ctx context.Context, groupID string) string {
	sctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 3*time.Second)
	defer cancel()
	// Background outbox retries have no HTTP/RPC trace. Native OpenIM rejects
	// requests without operationID, so give the whole sync one stable trace.
	if operationID, _ := sctx.Value(constantpb.OperationID).(string); operationID == "" {
		sctx = context.WithValue(sctx, constantpb.OperationID, "group-feature-sync-"+uuid.NewString())
	}
	feature, err := o.Database.TakeGroupFeature(sctx, groupID)
	if err != nil {
		_ = o.Database.DelayLiveSync(context.WithoutCancel(ctx), groupID, time.Now())
		return chatdb.LiveSyncPending
	}
	summary, err := featureJSON(feature)
	if err != nil {
		return chatdb.LiveSyncPending
	}
	imCtx, err := o.withIMAdmin(sctx)
	if err != nil {
		_ = o.Database.DelayLiveSync(context.WithoutCancel(ctx), groupID, time.Now())
		return chatdb.LiveSyncPending
	}
	old := ""
	groups, err := o.IM.FindGroupInfo(imCtx, []string{groupID})
	if err != nil {
		_ = o.Database.DelayLiveSync(context.WithoutCancel(ctx), groupID, time.Now())
		return chatdb.LiveSyncPending
	}
	if len(groups) == 0 || groups[0] == nil {
		// A successful lookup with no result confirms deletion. Complete only
		// this revision; a concurrent new revision must remain pending.
		if err = o.Database.FinishLiveSync(sctx, groupID, feature.Revision); err != nil {
			log.ZWarn(ctx, "live missing group completion failed", err, "groupID", groupID)
			return chatdb.LiveSyncPending
		}
		return chatdb.LiveSyncSynced
	}
	if len(groups) > 0 && groups[0] != nil {
		old = groups[0].Ex
	}
	merge := grouplive.MergeEx
	if feature.SangongProjectionVersion > 0 {
		merge = grouplive.MergeSangongEx
	}
	merged, err := merge(old, summary)
	if err != nil {
		log.ZWarn(ctx, "live ex merge skipped", err, "groupID", groupID)
		_ = o.Database.DelayLiveSync(context.WithoutCancel(ctx), groupID, time.Now())
		return chatdb.LiveSyncPending
	}
	var oldValue, mergedValue any
	unchanged := json.Unmarshal([]byte(old), &oldValue) == nil && json.Unmarshal([]byte(merged), &mergedValue) == nil && reflect.DeepEqual(oldValue, mergedValue)
	if !unchanged {
		err = o.IM.SetGroupEx(imCtx, groupID, merged)
	}
	if err != nil {
		log.ZWarn(ctx, "live ex sync failed", err, "groupID", groupID, "revision", feature.Revision)
		_ = o.Database.DelayLiveSync(context.WithoutCancel(ctx), groupID, time.Now())
		return chatdb.LiveSyncPending
	}
	if err = o.Database.FinishLiveSync(context.WithoutCancel(ctx), groupID, feature.Revision); err != nil {
		log.ZWarn(ctx, "live sync mark failed", err, "groupID", groupID)
	}
	return chatdb.LiveSyncSynced
}

func (o *chatSvr) notifyLiveCap(ctx context.Context, groupID, userID string, version int64) {
	if userID == "" || o.openIMAdmin == "" {
		return
	}
	raw, err := json.Marshal(map[string]any{"eventId": groupID + ":" + strconv.FormatInt(version, 10) + ":" + userID, "groupID": groupID, "capabilityVersion": version})
	if err != nil {
		return
	}
	imCtx, err := o.withIMAdmin(context.WithoutCancel(ctx))
	if err != nil {
		return
	}
	if err = o.IM.SendBusinessNotification(imCtx, "groupFeatureCapabilitiesChanged", string(raw), o.openIMAdmin, userID); err != nil {
		log.ZWarn(ctx, "live capability notify failed", err, "groupID", groupID)
	}
}

func (o *chatSvr) dropLiveStream(ctx context.Context, cfg *chatdb.LiveConfig, stream string) {
	if cfg == nil {
		return
	}
	dctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
	defer cancel()
	if err := grouplive.DropStream(dctx, cfg.SecretID, cfg.SecretKey, cfg.Region, cfg.PushDomain, cfg.AppName, stream); err != nil {
		log.ZWarn(ctx, "drop live stream failed", err, "stream", stream)
	}
}

func (o *chatSvr) liveUser(ctx context.Context) (string, error) {
	userID, _, err := mctx.Check(ctx)
	return userID, err
}

func (o *chatSvr) liveAccess(ctx context.Context, groupID, userID string) (bool, bool, error) {
	imCtx, err := o.withIMAdmin(ctx)
	if err != nil {
		return false, false, err
	}
	roles, err := o.IM.GroupMemberRoles(imCtx, groupID, []string{userID})
	if err != nil {
		return false, false, err
	}
	role, ok := roles[userID]
	if !ok {
		return false, false, nil
	}
	return true, role == constantpb.GroupOwner || role == constantpb.GroupAdmin, nil
}

func (o *chatSvr) requireMember(ctx context.Context, groupID, userID string) error {
	member, _, err := o.liveAccess(ctx, groupID, userID)
	if err != nil {
		return err
	}
	if !member {
		return eerrs.ErrForbidden.WrapMsg("not a group member")
	}
	return nil
}

func (o *chatSvr) requireManager(ctx context.Context, groupID, userID string) error {
	member, manager, err := o.liveAccess(ctx, groupID, userID)
	if err != nil {
		return err
	}
	if !member || !manager {
		return eerrs.ErrForbidden.WrapMsg("live manage forbidden")
	}
	return nil
}

func liveGroupID(groupID string) error {
	if groupID == "" || len(groupID) > 128 {
		return errs.ErrArgs.WrapMsg("groupID invalid")
	}
	return nil
}

func liveTTL(cfg *chatdb.LiveConfig) int64 {
	if cfg == nil || cfg.AuthTTLSeconds <= 0 {
		return 3600
	}
	return cfg.AuthTTLSeconds
}

func liveEdge(cfg *chatdb.LiveConfig) grouplive.Edge {
	app := cfg.AppName
	if app == "" {
		app = "live"
	}
	return grouplive.Edge{
		PushDomain: cfg.PushDomain, PlayDomain: cfg.PlayDomain, AppName: app,
		PushKey: livePushKey(cfg), PlayKey: livePlayKey(cfg),
	}
}

func livePushKey(cfg *chatdb.LiveConfig) string {
	if cfg.PushAuthKey != "" {
		return cfg.PushAuthKey
	}
	return cfg.AuthKey
}

func livePlayKey(cfg *chatdb.LiveConfig) string {
	if cfg.PlayAuthKey != "" {
		return cfg.PlayAuthKey
	}
	return cfg.AuthKey
}

func liveCallbackKey(cfg *chatdb.LiveConfig) string {
	if cfg.CallbackKey != "" {
		return cfg.CallbackKey
	}
	return cfg.AuthKey
}

func liveConfigPB(cfg *chatdb.LiveConfig) *livepb.LiveConfig {
	pushSet := livePushKey(cfg) != ""
	playSet := livePlayKey(cfg) != ""
	callbackSet := liveCallbackKey(cfg) != ""
	return &livepb.LiveConfig{
		PushDomain: cfg.PushDomain, PlayDomain: cfg.PlayDomain, AppName: cfg.AppName,
		AuthTTLSeconds: cfg.AuthTTLSeconds, DisconnectGraceSeconds: cfg.DisconnectGraceSeconds,
		AuthKeySet: pushSet || playSet || callbackSet, SecretIdSet: cfg.SecretID != "", SecretKeySet: cfg.SecretKey != "",
		PushAuthKeySet: pushSet, PlayAuthKeySet: playSet, CallbackKeySet: callbackSet, Region: cfg.Region,
	}
}

func featureJSON(row *chatdb.GroupFeature) ([]byte, error) {
	if row == nil {
		return (grouplive.Summary{Live: grouplive.NoneLive(), Games: grouplive.DefaultGames()}).Marshal()
	}
	var scheduled *time.Time
	if row.ScheduledStartAt != nil {
		at := time.UnixMilli(*row.ScheduledStartAt).UTC()
		scheduled = &at
	}
	live := grouplive.NoneLive()
	if row.SessionID != "" {
		live = grouplive.LiveFrom(row.Status, row.SessionID, row.RoomName, row.Description, row.AnchorUserID, scheduled)
	}
	return (grouplive.Summary{Revision: row.Revision, CapabilityVersion: row.CapabilityVersion, Live: live, Games: json.RawMessage(row.Games)}).Marshal()
}

func sessionDTO(row *chatdb.LiveSession) grouplive.SessionDTO {
	return grouplive.SessionDTO{
		LiveSessionID: row.SessionID, GroupID: row.GroupID, Status: row.Status, RoomName: row.RoomName,
		Description: row.Description, AnchorUserID: row.AnchorUserID, Version: row.Version,
		ScheduledStartAt: grouplive.ISOPtr(row.ScheduledStartAt), ExpireAt: grouplive.ISO(row.ExpireAt), EndReason: row.EndReason,
	}
}

func payload(v any) (*livepb.LivePayload, error) {
	raw, err := json.Marshal(v)
	if err != nil {
		return nil, err
	}
	return &livepb.LivePayload{Json: string(raw)}, nil
}
