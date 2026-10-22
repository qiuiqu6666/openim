package chat

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/openimsdk/chat/pkg/common/constant"
	"github.com/openimsdk/chat/pkg/common/riskcontrol"
	"github.com/openimsdk/chat/pkg/common/useractivity"
	adminpb "github.com/openimsdk/chat/pkg/protocol/admin"
	"github.com/openimsdk/tools/log"
	"github.com/redis/go-redis/v9"
)

var riskPaths = map[string]string{
	"/account/code/send": "sms", "/account/register": "register", "/account/login": "login",
	"/account/code/verify": "verify", "/account/password/reset": "password_reset", "/account/password/change": "password_change",
	"/account/phone/bind": "phone_bind", "/account/phone/change": "phone_change",
	"/account/device/remove": "device_remove", "/account/device/remove_others": "device_remove", "/account/device/trust": "device_trust",
	"/chat/fund/pay-password/code": "pay_password_sms", "/chat/fund/withdrawal-security/code": "fund_security_sms",
	"/chat/fund/pay-password": "pay_password_set", "/chat/fund/pay-password/reset": "pay_password_reset",
	"/chat/fund/transfers": "fund_transfer", "/chat/fund/packets": "fund_packet", "/chat/fund/swaps": "fund_swap", "/chat/fund/withdrawals": "fund_withdraw",
	"/chat/fund/packets/:orderID/claim": "fund_claim", "/chat/fund/withdrawal-security/check": "fund_security_check",
	"/chat/fund/swap-quotes": "fund_quote", "/chat/fund/recipients/resolve": "fund_recipient",
	"/group-live/api/v1/live/:sessionID/tip": "fund_tip",
	"/chat/friend-apply":                     "friend", "/chat/friend-grants": "friend_lookup", "/chat/friend-invites": "friend_lookup",
}

type riskRequest struct {
	Scene         string          `json:"scene"`
	Currency      string          `json:"currency"`
	FromCurrency  string          `json:"fromCurrency"`
	ToCurrency    string          `json:"toCurrency"`
	Amount        json.RawMessage `json:"amount"`
	ShareAmount   string          `json:"shareAmount"`
	ShareCount    int32           `json:"shareCount"`
	Biz           string          `json:"biz"`
	ClientOrderID string          `json:"clientOrderID"`
	Withdrawal    *riskRequest    `json:"withdrawal"`
	Transfer      *riskRequest    `json:"transfer"`
	Packet        *riskRequest    `json:"packet"`
	Swap          *riskRequest    `json:"swap"`
	Tip           *riskRequest    `json:"tip"`
	Account       string          `json:"account"`
	AreaCode      string          `json:"areaCode"`
	PhoneNumber   string          `json:"phoneNumber"`
	Email         string          `json:"email"`
	DeviceID      string          `json:"deviceID"`
	DeviceName    string          `json:"deviceName"`
	Platform      int32           `json:"platform"`
	VerifyCode    string          `json:"verifyCode"`
	OldVerifyCode string          `json:"oldVerifyCode"`
	NewVerifyCode string          `json:"newVerifyCode"`
	FriendGrant   string          `json:"friendGrant"`
	User          *riskRequest    `json:"user"`
}
type riskReply struct {
	ErrCode int `json:"errCode"`
	Data    struct {
		UserID    string     `json:"userID"`
		BizResult *bool      `json:"bizResult"`
		Order     *riskOrder `json:"order"`
	} `json:"data"`
}
type riskWriter struct {
	gin.ResponseWriter
	body bytes.Buffer
}

func (w *riskWriter) Write(b []byte) (int, error) {
	if w.body.Len()+len(b) <= 131072 {
		w.body.Write(b)
	}
	return w.ResponseWriter.Write(b)
}
func (w *riskWriter) WriteString(b string) (int, error) { return w.Write([]byte(b)) }

type riskIdentityStore interface {
	User(context.Context, string) (riskcontrol.User, error)
	FindUser(context.Context, string, string, string, string) (riskcontrol.User, error)
	SessionDevice(context.Context, string, string) (riskcontrol.Device, error)
	FriendTarget(context.Context, string, string) (string, error)
}

func (o *Api) riskInput(c *gin.Context, store riskIdentityStore, action string, r riskRequest, superCode string) (riskcontrol.Input, bool, error) {
	ip, err := o.GetClientIP(c)
	in := riskcontrol.Input{Action: action, DeviceID: strings.TrimSpace(r.DeviceID), DeviceName: strings.TrimSpace(r.DeviceName), Platform: r.Platform, IP: ip}
	if err != nil {
		return in, false, err
	}
	if len(in.DeviceID) > 128 || len(in.DeviceName) > 128 {
		return in, false, riskcontrol.ErrInvalid
	}
	if value := c.GetHeader("X-Activity-Session"); useractivity.ValidID(value) {
		in.SessionID = value
	}
	if value := c.GetHeader("operationID"); useractivity.ValidID(value) {
		in.OperationID = value
	}
	in.Details = riskActivity(action, r)
	in.VerifyAttempt = r.VerifyCode != "" || r.OldVerifyCode != "" || r.NewVerifyCode != ""
	in.SuperCode = superCode != "" && (r.VerifyCode == superCode || r.OldVerifyCode == superCode || r.NewVerifyCode == superCode)
	public := c.Request.URL.Path == "/account/login" || c.Request.URL.Path == "/account/register" || c.Request.URL.Path == "/account/code/send" || c.Request.URL.Path == "/account/code/verify" || c.Request.URL.Path == "/account/password/reset"
	token := c.GetHeader("token")
	if action == "register" && token != "" {
		res, err := o.adminClient.ParseToken(c, &adminpb.ParseTokenReq{Token: token})
		if err == nil && res.UserType == constant.AdminUser {
			return in, true, nil
		}
	}
	if !public {
		res, err := o.adminClient.ParseToken(c, &adminpb.ParseTokenReq{Token: token})
		if err != nil {
			return in, false, err
		}
		if res.UserType != constant.NormalUser {
			return in, false, fmt.Errorf("normal user token required")
		}
		in.UserID = res.UserID
		in.Subject = "user:" + res.UserID
		in.IdentityVerified = true
		user, err := store.User(c, in.UserID)
		if err != nil {
			return in, false, err
		}
		in.Phone = riskcontrol.Phone(user.AreaCode, user.PhoneNumber)
		in.NewAccount = user.CreatedAt.After(time.Now().Add(-24 * time.Hour))
		device, err := store.SessionDevice(c, in.UserID, token)
		if err == nil {
			in.DeviceID = device.DeviceID
			in.DeviceName = device.DeviceName
			in.Platform = device.Platform
			in.DeviceTrusted = device.Trusted
		} else if !riskcontrol.IsMissing(err) {
			return in, false, err
		} else {
			in.DeviceID = ""
			in.DeviceName = ""
			in.Platform = 0
		}
		if action == "friend" && r.FriendGrant != "" {
			target, err := store.FriendTarget(c, in.UserID, r.FriendGrant)
			if err != nil && !riskcontrol.IsMissing(err) {
				return in, false, err
			}
			in.TargetID = target
		}
		return in, false, nil
	}
	identity := r
	if action != "login" {
		identity.Account = ""
	}
	if action == "register" && r.User != nil {
		identity = *r.User
	}
	if len(identity.Account) > 128 || len(identity.PhoneNumber) > 32 || len(identity.AreaCode) > 8 || len(identity.Email) > 254 {
		return in, false, riskcontrol.ErrInvalid
	}
	in.Phone = riskcontrol.Phone(identity.AreaCode, identity.PhoneNumber)
	in.Subject = "identity:" + riskcontrol.Hash(identity.Account+"|"+in.Phone+"|"+identity.Email)
	user, err := store.FindUser(c, identity.Account, identity.AreaCode, identity.PhoneNumber, identity.Email)
	if err == nil {
		in.UserID = user.UserID
		in.Subject = "user:" + user.UserID
		in.NewAccount = user.CreatedAt.After(time.Now().Add(-24 * time.Hour))
	} else if !riskcontrol.IsMissing(err) {
		return in, false, err
	}
	return in, false, nil
}

func (o *Api) riskMiddleware(store *riskcontrol.Store, rdb redis.UniversalClient, superCode string) gin.HandlerFunc {
	return func(c *gin.Context) {
		path := c.FullPath()
		if path == "" {
			path = c.Request.URL.Path
		}
		action, ok := riskPaths[path]
		if !ok || (c.Request.Method != "POST" && c.Request.Method != "PUT") {
			c.Next()
			return
		}
		// The global upstream middleware only binds POST requests. PUT must
		// carry the same operationID into ParseToken before route-level binding.
		if !ensureOperationID(c) {
			return
		}
		raw, err := io.ReadAll(io.LimitReader(c.Request.Body, 65537))
		if err != nil || len(raw) > 65536 {
			riskError(c, 400, 20202, "请求内容过大或无效", 0)
			return
		}
		c.Request.Body = io.NopCloser(bytes.NewReader(raw))
		var req riskRequest
		if len(raw) == 0 && action == "fund_claim" {
			raw = []byte("{}")
		}
		if err = json.Unmarshal(raw, &req); err != nil {
			riskError(c, 400, 20202, "请求格式无效", 0)
			return
		}
		in, skip, err := o.riskInput(c, store, action, req, superCode)
		c.Set("riskClientIP", in.IP)
		if skip {
			c.Next()
			return
		}
		if err != nil {
			riskError(c, 400, 20202, "无法确认请求身份或设备，请检查登录状态后重试", 0)
			return
		}
		if (action == "login" || action == "register") && in.DeviceID == "" {
			riskError(c, 400, 20202, "请提供设备标识后重试", 0)
			return
		}
		cfg, err := store.Config(c)
		if err != nil {
			riskError(c, 503, 20203, "安全校验暂不可用，请稍后重试", 5)
			return
		}
		if action == "login" || riskcontrol.IsSensitive(action) || riskcontrol.IsFundSpend(action) {
			in.Environment, err = store.AssessEnvironment(c, cfg, in.UserID, in.DeviceID, in.IP, time.Now())
			if err != nil {
				riskError(c, 503, 20203, "安全校验暂不可用，请稍后重试", 5)
				return
			}
		}
		if in.Environment != nil {
			in.DeviceTrusted = in.Environment.Current.Trusted
		}
		riskcontrol.ObserveAmount(cfg, &in)
		decision, err := riskcontrol.Evaluate(c, rdb, cfg, in)
		if err != nil {
			riskError(c, 503, 20203, "安全校验暂不可用，请稍后重试", 5)
			return
		}
		riskcontrol.ObserveEnvironment(cfg, in, &decision)
		record := func(outcome string, code int) {
			ctx, cancel := context.WithTimeout(context.WithoutCancel(c.Request.Context()), 2*time.Second)
			defer cancel()
			if err := store.Record(ctx, in, decision, outcome, code); err != nil {
				log.ZWarn(ctx, "risk event persistence failed", err)
			}
		}
		if decision.Blocked {
			riskError(c, 429, riskcontrol.BlockCode, "操作过于频繁，请稍后再试", decision.RetryAfter)
			record("blocked", riskcontrol.BlockCode)
			return
		}
		writer := &riskWriter{ResponseWriter: c.Writer}
		c.Writer = writer
		c.Next()
		var reply riskReply
		outcome := "failed"
		if err = json.Unmarshal(writer.body.Bytes(), &reply); err == nil && reply.ErrCode == 0 && c.Writer.Status() < 400 {
			outcome = "success"
			if reply.Data.BizResult != nil && !*reply.Data.BizResult {
				outcome = "failed"
			}
			if (action == "login" || action == "register") && reply.Data.UserID != "" {
				in.UserID = reply.Data.UserID
				in.IdentityVerified = true
			}
		}
		if outcome == "success" {
			applyRiskOrder(&in, reply.Data.Order)
			riskcontrol.ObserveAmount(cfg, &in)
		}
		if reply.ErrCode == 20081 || reply.ErrCode == 20077 {
			outcome = "challenge"
		}
		// Infrastructure errors and legitimate MFA challenges are not bad passwords.
		if riskCredentialFailure(action, reply.ErrCode) {
			if err := riskcontrol.RecordFailure(c, rdb, cfg, in); err != nil {
				log.ZWarn(c, "risk failure counter unavailable", err)
			}
		}
		record(outcome, reply.ErrCode)
	}
}
func riskError(c *gin.Context, status, code int, message string, retry int64) {
	if retry > 0 {
		c.Header("Retry-After", fmt.Sprint(retry))
	}
	c.AbortWithStatusJSON(status, gin.H{"errCode": code, "errMsg": message, "errDlt": "", "data": gin.H{"retryAfter": retry}})
}
