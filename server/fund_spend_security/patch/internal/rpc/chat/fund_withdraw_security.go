package chat

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"time"

	chatdb "github.com/openimsdk/chat/pkg/common/db/table/chat"
	"github.com/openimsdk/chat/pkg/common/fundsecurity"
	"github.com/openimsdk/chat/pkg/common/mctx"
	"github.com/openimsdk/chat/pkg/eerrs"
	pb "github.com/openimsdk/chat/pkg/protocol/chat"
	"github.com/openimsdk/chat/pkg/sms"
	"github.com/openimsdk/tools/errs"
)

func fundWithdrawalSecurityError(err error) error {
	cause := errs.Unwrap(err)
	is := func(target error) bool { return errors.Is(err, target) || errors.Is(cause, target) }
	switch {
	case err == nil:
		return nil
	case is(fundsecurity.ErrCooldown):
		return eerrs.ErrFundWithdrawalCooldown.Wrap()
	case is(fundsecurity.ErrSMSRequired):
		return eerrs.ErrFundWithdrawalSMSRequired.Wrap()
	case is(fundsecurity.ErrInvalidCode), is(fundsecurity.ErrCodeExpired),
		is(fundsecurity.ErrCodeAttempts), is(fundsecurity.ErrCodeUsed), is(fundsecurity.ErrChallengeMismatch):
		return eerrs.ErrFundWithdrawalSMSInvalid.Wrap()
	case is(fundsecurity.ErrRateLimit):
		return eerrs.ErrFundWithdrawalSMSSendFrequently.Wrap()
	case is(fundsecurity.ErrDeviceUnknown):
		return eerrs.ErrFundWithdrawalDeviceUnknown.Wrap()
	case is(fundsecurity.ErrInvalidConfig):
		return errs.ErrArgs.WrapMsg("提现短信门槛配置无效，请完整设置三个币种的非负金额")
	case is(fundsecurity.ErrInvalidSubject):
		return errs.ErrArgs.WrapMsg("提现安全验证参数无效")
	default:
		return err
	}
}

func (o *chatSvr) recoverRejectedFundRequest(ctx context.Context, request *chatdb.FundOrder, compareReceiver bool, rejection error) (*chatdb.FundOrder, error) {
	// A matching request can commit between the first idempotency lookup
	// and any password, security, or transaction check. Return that accepted
	// order without another financial operation.
	accepted, err := o.findFundRequest(ctx, request, compareReceiver)
	if err != nil {
		if errors.Is(err, eerrs.ErrIdempotencyConflict) {
			return nil, err
		}
		return nil, fundWithdrawalSecurityError(rejection)
	}
	if accepted != nil {
		return accepted, nil
	}
	return nil, fundWithdrawalSecurityError(rejection)
}

func fundSecurityMillis(t time.Time) int64 {
	if t.IsZero() {
		return 0
	}
	return t.UnixMilli()
}

func fundWithdrawalFingerprint(order *chatdb.FundOrder) string {
	// Keep business identity separate from mutable fees, passwords, and SMS
	// proof. Resolve aliases before hashing so the proof authorizes one user.
	values := struct {
		UserID, ClientOrderID, Biz, Scene, Currency                                              string
		Amount                                                                                   int64
		RecvID, GroupID, RecipientType, Recipient, RecipientAreaCode, ToAddress, Network, Remark string
	}{order.SenderID, order.ClientOrderID, order.Biz, order.Scene, order.Currency, order.Amount,
		order.RecvID, order.GroupID, order.RecipientType, order.Recipient, order.RecipientAreaCode,
		order.ToAddress, order.Network, order.Remark}
	encoded, _ := json.Marshal(values)
	if order.Biz != chatdb.FundBizTransfer && order.Biz != chatdb.FundBizGroupTransfer && order.Biz != chatdb.FundBizWithdraw {
		encoded, _ = json.Marshal(struct {
			Base                    string
			ShareAmount             int64
			ShareCount              int32
			TargetCurrency, QuoteID string
		}{string(encoded), order.ShareAmount, order.ShareCount, order.TargetCurrency, order.QuoteID})
	}
	sum := sha256.Sum256(encoded)
	return hex.EncodeToString(sum[:])
}

func fundWithdrawalPhoneMasked(phone string) string {
	area, number, ok := strings.Cut(phone, " ")
	if !ok || number == "" {
		return ""
	}
	if len(number) > 7 {
		return area + " " + number[:3] + "****" + number[len(number)-4:]
	}
	if len(number) > 2 {
		return area + " " + strings.Repeat("*", len(number)-2) + number[len(number)-2:]
	}
	return area + " **"
}

func (o *chatSvr) fundWithdrawalSecuritySubject(ctx context.Context, userID string, order *chatdb.FundOrder) (fundsecurity.Subject, error) {
	if o.FundSecurity == nil {
		return fundsecurity.Subject{}, errs.ErrInternalServer.WrapMsg("提现安全服务暂不可用，请稍后重试")
	}
	token := chatTokenFromCtx(ctx)
	if token == "" {
		return fundsecurity.Subject{}, eerrs.ErrFundWithdrawalDeviceUnknown.Wrap()
	}
	records, err := o.Database.ListLoginRecords(ctx, userID)
	if err != nil {
		return fundsecurity.Subject{}, err
	}
	current := deviceByChatToken(records, token)
	if current == nil || current.UserID != userID || strings.TrimSpace(current.DeviceID) == "" || current.PlatformID <= 0 {
		return fundsecurity.Subject{}, eerrs.ErrFundWithdrawalDeviceUnknown.Wrap()
	}
	area, phone, bound, err := o.fundBoundPhone(ctx, userID)
	if err != nil {
		return fundsecurity.Subject{}, err
	}
	boundPhone := ""
	if bound {
		boundPhone = area + " " + phone
	}
	exempt, err := o.smsVerificationExempt(ctx, userID)
	if err != nil {
		return fundsecurity.Subject{}, err
	}
	return fundsecurity.Subject{
		Transfer:  order.Biz != chatdb.FundBizWithdraw,
		SMSExempt: exempt,
		UserID:    userID, DeviceID: current.DeviceID, PlatformID: current.PlatformID, Phone: boundPhone,
		Fingerprint: fundWithdrawalFingerprint(order), Currency: order.Currency, Amount: order.Amount,
	}, nil
}

func (o *chatSvr) normalizeFundWithdrawalSecurityRequest(ctx context.Context, userID string, req *pb.FundWithdrawalSecurityReq) (*chatdb.FundOrder, error) {
	if req == nil || req.TransactionCount() != 1 {
		return nil, errs.ErrArgs.WrapMsg("请仅提交一笔提现或转账信息")
	}
	if req.Packet != nil {
		return normalizeFundPacketSecurity(userID, req.Packet)
	}
	if req.Swap != nil {
		return normalizeFundSwapSecurity(userID, req.Swap)
	}
	if req.Tip != nil {
		return o.normalizeFundTipSecurity(ctx, userID, req.Tip)
	}
	if req.Transfer != nil {
		order, err := normalizeFundTransfer(userID, req.Transfer)
		if err != nil {
			return nil, err
		}
		if err = o.resolveFundTransfer(ctx, userID, order); err != nil {
			return nil, err
		}
		return order, nil
	}
	order, err := normalizeFundWithdrawal(userID, req.Withdrawal)
	if err != nil {
		return nil, err
	}
	if order.Scene == chatdb.FundSceneInternal {
		attr, err := o.takeFundRecipient(ctx, order.RecipientType, order.Recipient, order.RecipientAreaCode)
		if err != nil {
			return nil, err
		}
		if attr.UserID == userID {
			return nil, errs.ErrArgs.WrapMsg("不能向自己转账")
		}
		order.RecvID = attr.UserID
	}
	return order, nil
}

func (o *chatSvr) GetFundWithdrawalSecurity(ctx context.Context, req *pb.FundWithdrawalSecurityReq) (*pb.FundWithdrawalSecurityResp, error) {
	userID, _, err := mctx.Check(ctx)
	if err != nil {
		return nil, err
	}
	order, err := o.normalizeFundWithdrawalSecurityRequest(ctx, userID, req)
	if err != nil {
		return nil, err
	}
	accepted, err := o.acceptedAdditionalSecurity(ctx, userID, req, order)
	if err != nil {
		return nil, err
	}
	if accepted {
		return &pb.FundWithdrawalSecurityResp{Currency: order.Currency, Reasons: []string{}, CooldownHours: 2}, nil
	}
	subject, err := o.fundWithdrawalSecuritySubject(ctx, userID, order)
	if err != nil {
		return nil, err
	}
	status, err := o.FundSecurity.Check(ctx, subject, time.Now())
	if err != nil {
		return nil, fundWithdrawalSecurityError(err)
	}
	return &pb.FundWithdrawalSecurityResp{
		SmsRequired: status.SMSRequired, Reasons: status.Reasons, BlockedUntil: fundSecurityMillis(status.CooldownUntil),
		PhoneMasked: fundWithdrawalPhoneMasked(subject.Phone), Currency: subject.Currency, SmsThreshold: status.SmsThreshold, CooldownHours: uint32(fundsecurity.Cooldown / time.Hour),
	}, nil
}

func (o *chatSvr) SendFundWithdrawalCode(ctx context.Context, req *pb.FundWithdrawalSecurityReq) (*pb.SendFundWithdrawalCodeResp, error) {
	userID, _, err := mctx.Check(ctx)
	if err != nil {
		return nil, err
	}
	order, err := o.normalizeFundWithdrawalSecurityRequest(ctx, userID, req)
	if err != nil {
		return nil, err
	}
	subject, err := o.fundWithdrawalSecuritySubject(ctx, userID, order)
	if err != nil {
		return nil, err
	}
	area, phone, bound := strings.Cut(subject.Phone, " ")
	if !bound || area == "" || phone == "" {
		return nil, eerrs.ErrFundPhoneNotBound.WrapMsg("请先绑定手机号后再进行提现短信验证")
	}
	if o.PhoneCode == nil && o.SMS == nil {
		return nil, errs.ErrInternalServer.WrapMsg("提现短信发送服务暂不可用，请稍后重试")
	}
	challenge, code, err := o.FundSecurity.CreateChallenge(ctx, subject, time.Now())
	if err != nil {
		return nil, fundWithdrawalSecurityError(err)
	}
	ctx = sms.WithMetadata(ctx, sms.Metadata{
		Purpose: "withdrawal", UserID: userID, DeviceID: subject.DeviceID, PlatformID: subject.PlatformID,
		ExpiresAt: fundSecurityMillis(challenge.ExpiresAt),
	})
	if o.usesProviderPhoneCode(area) {
		err = o.PhoneCode.SendSpecified(ctx, area, phone, code)
	} else {
		err = o.SMS.SendCode(ctx, area, phone, code)
	}
	if err != nil {
		_ = o.FundSecurity.CancelChallenge(ctx, challenge.ID)
		if errors.Is(err, eerrs.ErrVerifyCodeSendFrequently) {
			return nil, eerrs.ErrFundWithdrawalSMSSendFrequently.Wrap()
		}
		// Provider error details can contain request data. Do not expose them.
		return nil, errs.ErrInternalServer.WrapMsg("提现验证码发送失败，请稍后重试")
	}
	if err = o.FundSecurity.SetChallengeSent(ctx, challenge.ID); err != nil {
		_ = o.FundSecurity.CancelChallenge(ctx, challenge.ID)
		return nil, fundWithdrawalSecurityError(err)
	}
	return &pb.SendFundWithdrawalCodeResp{
		ChallengeID: challenge.ID, ExpiresAt: fundSecurityMillis(challenge.ExpiresAt), RetryAfterSeconds: 60,
		PhoneMasked: fundWithdrawalPhoneMasked(subject.Phone),
	}, nil
}

func (o *chatSvr) prepareFundWithdrawalSecurity(ctx context.Context, userID string, order *chatdb.FundOrder, challengeID, code string) (fundsecurity.Subject, error) {
	subject, err := o.fundWithdrawalSecuritySubject(ctx, userID, order)
	if err != nil {
		return fundsecurity.Subject{}, err
	}
	status, err := o.FundSecurity.Check(ctx, subject, time.Now())
	if err != nil {
		return fundsecurity.Subject{}, fundWithdrawalSecurityError(err)
	}
	if status.CooldownUntil.After(time.Now()) {
		return fundsecurity.Subject{}, eerrs.ErrFundWithdrawalCooldown.Wrap()
	}
	if status.SMSRequired {
		if subject.Phone == "" {
			return fundsecurity.Subject{}, eerrs.ErrFundPhoneNotBound.WrapMsg("请先绑定手机号后再进行提现短信验证")
		}
		if challengeID == "" || code == "" {
			return fundsecurity.Subject{}, eerrs.ErrFundWithdrawalSMSRequired.Wrap()
		}
		// Wrong attempts must persist even though a rejected withdrawal does
		// not start a balance transaction. Successful verification is consumed
		// exclusively by Guard in that transaction.
		if err = o.FundSecurity.VerifyChallenge(ctx, subject, challengeID, code, time.Now()); err != nil {
			return fundsecurity.Subject{}, fundWithdrawalSecurityError(err)
		}
	}
	return subject, nil
}

func (o *chatSvr) guardFundWithdrawalSecurity(ctx context.Context, subject fundsecurity.Subject, order *chatdb.FundOrder, challengeID, code string) error {
	current, err := o.fundWithdrawalSecuritySubject(ctx, subject.UserID, order)
	if err != nil {
		return err
	}
	if current.DeviceID != subject.DeviceID || current.PlatformID != subject.PlatformID {
		return eerrs.ErrFundWithdrawalDeviceUnknown.Wrap()
	}
	if current.Phone != subject.Phone || current.Fingerprint != subject.Fingerprint {
		return eerrs.ErrFundWithdrawalSMSInvalid.Wrap()
	}
	if order.RecipientType != "" {
		attr, err := o.takeFundRecipient(ctx, order.RecipientType, order.Recipient, order.RecipientAreaCode)
		if err != nil {
			return err
		}
		if attr.UserID != order.RecvID {
			return eerrs.ErrFundWithdrawalSMSInvalid.WrapMsg("收款人信息发生变化，请重新验证后提交")
		}
	}
	return fundWithdrawalSecurityError(o.FundSecurity.Guard(ctx, current, challengeID, code, time.Now()))
}

func fundWithdrawalSecurityConfigPB(config *fundsecurity.Config) *pb.GetFundWithdrawalSecurityConfigResp {
	value := &pb.FundWithdrawalSecurityConfig{
		Thresholds: []*pb.FundWithdrawalThreshold{}, CooldownHours: uint32(fundsecurity.Cooldown / time.Hour), NewDeviceSMS: true, ApplyToInternal: true,
		UpdatedAt: fundSecurityMillis(config.UpdatedAt), UpdatedBy: config.UpdatedBy,
	}
	for _, threshold := range config.Thresholds {
		value.Thresholds = append(value.Thresholds, &pb.FundWithdrawalThreshold{Currency: threshold.Currency, SmsThreshold: threshold.SmsThreshold})
	}
	return &pb.GetFundWithdrawalSecurityConfigResp{Config: value}
}

func (o *chatSvr) GetFundWithdrawalSecurityConfig(ctx context.Context, _ *pb.GetFundWithdrawalSecurityConfigReq) (*pb.GetFundWithdrawalSecurityConfigResp, error) {
	if _, err := mctx.CheckAdmin(ctx); err != nil {
		return nil, err
	}
	if o.FundSecurity == nil {
		return nil, errs.ErrInternalServer.WrapMsg("提现安全服务暂不可用，请稍后重试")
	}
	config, err := o.FundSecurity.GetConfig(ctx)
	if err != nil {
		return nil, fundWithdrawalSecurityError(err)
	}
	return fundWithdrawalSecurityConfigPB(config), nil
}

func (o *chatSvr) PutFundWithdrawalSecurityConfig(ctx context.Context, req *pb.PutFundWithdrawalSecurityConfigReq) (*pb.GetFundWithdrawalSecurityConfigResp, error) {
	actor, err := mctx.CheckAdmin(ctx)
	if err != nil {
		return nil, err
	}
	if o.FundSecurity == nil {
		return nil, errs.ErrInternalServer.WrapMsg("提现安全服务暂不可用，请稍后重试")
	}
	config := &fundsecurity.Config{Thresholds: []fundsecurity.Threshold{}, UpdatedAt: time.Now(), UpdatedBy: actor}
	for _, item := range req.GetThresholds() {
		if item == nil {
			return nil, errs.ErrArgs.WrapMsg("提现短信门槛配置无效")
		}
		config.Thresholds = append(config.Thresholds, fundsecurity.Threshold{Currency: item.Currency, SmsThreshold: item.SmsThreshold})
	}
	if err = o.FundSecurity.PutConfig(ctx, config); err != nil {
		return nil, fundWithdrawalSecurityError(err)
	}
	config, err = o.FundSecurity.GetConfig(ctx)
	if err != nil {
		return nil, fundWithdrawalSecurityError(err)
	}
	return fundWithdrawalSecurityConfigPB(config), nil
}
