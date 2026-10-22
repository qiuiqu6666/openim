// Copyright © 2023 OpenIM open source community. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package database

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/openimsdk/tools/db/mongoutil"
	"github.com/openimsdk/tools/db/pagination"
	"github.com/openimsdk/tools/db/tx"

	"github.com/openimsdk/chat/pkg/common/avatar"
	"github.com/openimsdk/chat/pkg/common/constant"
	admindb "github.com/openimsdk/chat/pkg/common/db/model/admin"
	"github.com/openimsdk/chat/pkg/common/db/model/chat"
	"github.com/openimsdk/chat/pkg/common/db/table/admin"
	chatdb "github.com/openimsdk/chat/pkg/common/db/table/chat"
	"github.com/openimsdk/chat/pkg/common/fundsecurity"
	"github.com/openimsdk/chat/pkg/common/imidentity"
	"github.com/openimsdk/chat/pkg/common/loginhistory"
)

type ChatDatabaseInterface interface {
	WithdrawalSecurity() fundsecurity.Interface
	GetUser(ctx context.Context, userID string) (account *chatdb.Account, err error)
	UpdateUseInfo(ctx context.Context, userID string, attribute map[string]any, updateCred, delCred []*chatdb.Credential) (err error)
	FindAttribute(ctx context.Context, userIDs []string) ([]*chatdb.Attribute, error)
	FindAttributeMissingAccount(ctx context.Context) ([]*chatdb.Attribute, error)
	FindPlainPublicAccount(ctx context.Context) ([]*chatdb.Attribute, error)
	FindAttributeByAccount(ctx context.Context, accounts []string) ([]*chatdb.Attribute, error)
	TakeAttributeByPhone(ctx context.Context, areaCode string, phoneNumber string) (*chatdb.Attribute, error)
	TakeAttributeByPhoneNumber(ctx context.Context, phoneNumber string) (*chatdb.Attribute, error)
	TakeAttributeByEmail(ctx context.Context, Email string) (*chatdb.Attribute, error)
	TakeAttributeByAccount(ctx context.Context, account string) (*chatdb.Attribute, error)
	TakeAttributeByNickname(ctx context.Context, nickname string) (*chatdb.Attribute, error)
	TakeAttributeByUserID(ctx context.Context, userID string) (*chatdb.Attribute, error)
	TakeAccount(ctx context.Context, userID string) (*chatdb.Account, error)
	UpgradeLegacyPassword(ctx context.Context, userID, previousHash, passwordHash string, bootstrap *chatdb.UserLoginRecord) (bool, error)
	UpdatePayPassword(ctx context.Context, userID, hash, codeID string) (initialSet bool, err error)
	TakeCredentialByAccount(ctx context.Context, account string) (*chatdb.Credential, error)
	TakeCredentialsByUserID(ctx context.Context, userID string) ([]*chatdb.Credential, error)
	TakeLastVerifyCode(ctx context.Context, account string) (*chatdb.VerifyCode, error)
	Search(ctx context.Context, normalUser int32, keyword string, gender int32, pagination pagination.Pagination) (int64, []*chatdb.Attribute, error)
	SearchAdminUsers(ctx context.Context, normalUser int32, keyword string, gender int32, pagination pagination.Pagination) (int64, []*chatdb.Attribute, error)
	SearchFundUsers(ctx context.Context, keyword, currency, field, order string, page pagination.Pagination) (int64, []*chatdb.Attribute, error)
	SearchUser(ctx context.Context, keyword string, userIDs []string, genders []int32, pagination pagination.Pagination) (int64, []*chatdb.Attribute, error)
	CountVerifyCodeRange(ctx context.Context, account string, start time.Time, end time.Time) (int64, error)
	AddVerifyCode(ctx context.Context, verifyCode *chatdb.VerifyCode, fn func() error) error
	UpdateVerifyCodeIncrCount(ctx context.Context, id string) error
	DelVerifyCode(ctx context.Context, id string) error
	RegisterUser(ctx context.Context, register *chatdb.Register, account *chatdb.Account, attribute *chatdb.Attribute, credentials []*chatdb.Credential) error
	TakeIMIdentity(ctx context.Context, imUserID string) (*chatdb.UserIMIdentity, error)
	CreateChatFolder(ctx context.Context, ownerIMID, name string, sortOrder int32) (*chatdb.ChatFolder, error)
	ListChatFolders(ctx context.Context, ownerIMID string) ([]*chatdb.ChatFolder, error)
	UpdateChatFolder(ctx context.Context, ownerIMID, id string, name *string, sortOrder *int32) (*chatdb.ChatFolder, error)
	DeleteChatFolder(ctx context.Context, ownerIMID, id string) (*chatdb.ChatFolder, error)
	ListConversationStates(ctx context.Context, ownerIMID string, updatedAfter, limit int64) ([]*chatdb.ChatConversationState, int64, error)
	PutConversationState(ctx context.Context, ownerIMID, conversationID, folderID string, archived bool, version int64) (*chatdb.ChatConversationState, bool, error)
	ListChatStarFriends(ctx context.Context, ownerIMID string, updatedAfter, limit int64) ([]*chatdb.ChatStarFriend, int64, error)
	PutChatStarFriend(ctx context.Context, ownerIMID, friendUserID string, starred bool, version int64) (*chatdb.ChatStarFriend, bool, bool, error)
	ListCallRecords(ctx context.Context, ownerUserID string, updatedAfter, limit int64) ([]*chatdb.CallRecord, int64, error)
	SaveCallRecords(ctx context.Context, records []*chatdb.CallRecord) error
	ListUserLastSeen(ctx context.Context, userIDs []string) ([]*chatdb.UserLastSeen, error)
	MarkUserOffline(ctx context.Context, userID string, lastSeenAt int64) error
	GetPresenceVisibility(ctx context.Context, userID string) (*chatdb.PresenceVisibility, error)
	PutPresenceVisibility(ctx context.Context, userID string, showLastSeen bool, version int64) (*chatdb.PresenceVisibility, bool, bool, error)
	FindPresenceVisibility(ctx context.Context, userIDs []string) ([]*chatdb.PresenceVisibility, error)
	LoginRecord(ctx context.Context, record *chatdb.UserLoginRecord, verifyCodeID *string) error
	ListLoginRecords(ctx context.Context, userID string) ([]*chatdb.UserLoginRecord, error)
	SetDeviceTrusted(ctx context.Context, userID, deviceID string, trusted bool) error
	DeleteDeviceRecord(ctx context.Context, userID, deviceID string) error
	DeleteDeviceByChatToken(ctx context.Context, userID, token string) error
	UpdatePhoneAndDeleteVerifyCodes(ctx context.Context, userID, areaCode, phoneNumber string, verifyCodeIDs []string) error
	UpdatePassword(ctx context.Context, userID string, password string) error
	UpdatePasswordAndDeleteVerifyCode(ctx context.Context, userID string, password string, codeID string) error
	NewUserCountTotal(ctx context.Context, before *time.Time) (int64, error)
	UserLoginCountTotal(ctx context.Context, before *time.Time) (int64, error)
	UserLoginCountRangeEverydayTotal(ctx context.Context, start *time.Time, end *time.Time) (map[string]int64, int64, error)
	DelUserAccount(ctx context.Context, userIDs []string) error
	CreateFriendInvite(ctx context.Context, invite *chatdb.FriendInvite) error
	TakeFriendInvite(ctx context.Context, code string) (*chatdb.FriendInvite, error)
	DeleteFriendInvite(ctx context.Context, code string, now time.Time) error
	CreateFriendGrant(ctx context.Context, grant *chatdb.FriendGrant) error
	TakeFriendGrant(ctx context.Context, grant string) (*chatdb.FriendGrant, error)
	TakeFriendGrantByOp(ctx context.Context, opID string) (*chatdb.FriendGrant, error)
	ClaimFriendGrant(ctx context.Context, grant, applicant, opID string, now time.Time) (*chatdb.FriendGrant, error)
	SetFriendGrantState(ctx context.Context, grant string, from []string, to string) (bool, error)
	RevokeFriendGrantsByInvite(ctx context.Context, inviteCode string) error
	TakeGroupFriendProtect(ctx context.Context, groupID string) (bool, error)
	PutGroupFriendProtect(ctx context.Context, groupID string, protect bool, now time.Time) error
	ListChatStickers(ctx context.Context, ownerIMID, cursor string, limit int64) ([]*chatdb.ChatSticker, string, error)
	CreateChatSticker(ctx context.Context, ownerIMID, clientRequestID string, incoming *chatdb.ChatSticker, maxCount int, maxBytes int64) (*chatdb.ChatSticker, bool, error)
	DeleteChatSticker(ctx context.Context, ownerIMID, id string) error
	OrderChatStickers(ctx context.Context, ownerIMID string, ids []string) error
	Favorite() chatdb.FavoriteStore
	ScheduleStickerThumbnailPurge(ctx context.Context, name, key string) error
	ListDueStickerPurges(ctx context.Context, now int64, limit int64) ([]*chatdb.ChatStickerPurge, error)
	DeleteStickerPurge(ctx context.Context, id string) error
	StickerThumbnailInUse(ctx context.Context, name string) (bool, error)
	ListFundBalances(ctx context.Context, userID string) ([]*chatdb.FundAccount, error)
	ListFundBalancesForUsers(ctx context.Context, userIDs []string) ([]*chatdb.FundAccount, error)
	AdminSetFundBalance(ctx context.Context, journal *chatdb.FundJournal) error
	TakeFundOrderByClient(ctx context.Context, userID, clientOrderID string) (*chatdb.FundOrder, error)
	TakeFundOrder(ctx context.Context, orderID string) (*chatdb.FundOrder, []*chatdb.FundShare, error)
	CreateDirectFundOrder(ctx context.Context, order *chatdb.FundOrder) (*chatdb.FundOrder, error)
	CreateDirectFundOrderChecked(ctx context.Context, order *chatdb.FundOrder, beforeSpend func(context.Context) error) (*chatdb.FundOrder, error)
	CreateInternalFundOrder(ctx context.Context, order *chatdb.FundOrder, beforeSpend func(context.Context) error) (*chatdb.FundOrder, error)
	CreatePacketFundOrder(ctx context.Context, order *chatdb.FundOrder, shares []int64) (*chatdb.FundOrder, error)
	ClaimFundShare(ctx context.Context, orderID, userID string, now time.Time) (*chatdb.FundOrder, *chatdb.FundShare, error)
	ListExpiredFundOrders(ctx context.Context, now time.Time, limit int64) ([]*chatdb.FundOrder, error)
	ListOpenFundPackets(ctx context.Context, limit int64) ([]*chatdb.FundOrder, error)
	RefundFundRemainder(ctx context.Context, orderID string, amount int64, now time.Time) (bool, error)
	SettleFundClaims(ctx context.Context, items []FundSettleItem) error
	SumFundOutgoing(ctx context.Context, userID, currency string, start, end time.Time) (int64, error)
	GetFundConfig(ctx context.Context) (*chatdb.FundConfig, error)
	PutFundConfig(ctx context.Context, cfg *chatdb.FundConfig) error
	TakeFundPrice(ctx context.Context, pair string) (*chatdb.FundPrice, error)
	UpsertFundPrice(ctx context.Context, pair, price string, fetched time.Time) error
	CreateSwapFundOrder(ctx context.Context, order *chatdb.FundOrder) (*chatdb.FundOrder, error)
	CreateWithdrawFundOrder(ctx context.Context, order *chatdb.FundOrder) (*chatdb.FundOrder, error)
	CreateWithdrawFundOrderChecked(ctx context.Context, order *chatdb.FundOrder, beforeSpend func(context.Context) error) (*chatdb.FundOrder, error)
	AdminListFundWithdrawals(ctx context.Context, status, userID string, skip, limit int64) (int64, []*chatdb.FundOrder, error)
	ReviewFundWithdrawal(ctx context.Context, orderID, actor, action, reason, txID, fromAddress string) (*chatdb.FundOrder, bool, error)
	SettleWithdrawFundOrder(ctx context.Context, orderID, txID string, success bool) error
	GetPlatformInfo(ctx context.Context) (*chatdb.PlatformInfo, error)
	PutPlatformInfo(ctx context.Context, info *chatdb.PlatformInfo) error
	TakeFeedbackByRequest(ctx context.Context, userID, requestID string) (*chatdb.Feedback, error)
	TakeFeedback(ctx context.Context, feedbackID string) (*chatdb.Feedback, error)
	CreateFeedback(ctx context.Context, row *chatdb.Feedback, files []*chatdb.FeedbackAttachment) error
	ListFeedbackAttachments(ctx context.Context, feedbackID string) ([]*chatdb.FeedbackAttachment, error)
	SearchFeedback(ctx context.Context, userID, kind, status string, start, end time.Time, skip, limit int64) (int64, []*chatdb.Feedback, error)
	UpdateFeedbackStatus(ctx context.Context, feedbackID, status, note string, now time.Time) error
	ListFeedbackLogCandidates(ctx context.Context, since time.Time, limit int64) ([]*chatdb.Feedback, error)
	ListUserOpenIMLogs(ctx context.Context, userID string, since time.Time) ([]*chatdb.OpenIMLog, error)
	UpsertFeedbackLogLink(ctx context.Context, row *chatdb.FeedbackLogLink) error
	ListFeedbackLogLinks(ctx context.Context, feedbackID string) ([]*chatdb.FeedbackLogLink, error)
	TakeFeedbackLogLink(ctx context.Context, feedbackID, logID string) (*chatdb.FeedbackLogLink, error)
	MarkFeedbackLogUploaded(ctx context.Context, feedbackID, logID, objectKey string, uploaded time.Time) error
	MarkFeedbackLogFailed(ctx context.Context, feedbackID string, now time.Time) error
	AddFeedbackAudit(ctx context.Context, row *chatdb.FeedbackAudit) error
	CommonGroupStamp(ctx context.Context, self, peer string) (chat.CommonGroupStamp, error)
	CountCommonGroups(ctx context.Context, self, peer string) (int64, error)
	ListCommonGroups(ctx context.Context, self, peer, after string, limit int) ([]chat.CommonGroupItem, bool, error)
	CreditFundDeposit(ctx context.Context, txID, userID, currency string, amount int64) (bool, error)
	GrantFundBalance(ctx context.Context, userID, clientOrderID string, amount int64) error
	ListUnsentFundOrders(ctx context.Context, limit int64) ([]*chatdb.FundOrder, error)
	MarkFundMessageSent(ctx context.Context, orderID string) error
	ListPendingWithdrawals(ctx context.Context, limit int64) ([]*chatdb.FundOrder, error)
	GetLiveConfig(ctx context.Context) (*chatdb.LiveConfig, error)
	PutLiveConfig(ctx context.Context, cfg *chatdb.LiveConfig) error
	TakeGroupFeature(ctx context.Context, groupID string) (*chatdb.GroupFeature, error)
	AuthorizeLiveSession(ctx context.Context, groupID, creator, anchor, room, desc string, scheduled *time.Time, now time.Time) (*chatdb.LiveSession, *chatdb.GroupFeature, error)
	ScheduleLiveSession(ctx context.Context, groupID, room string, scheduled time.Time, now time.Time) (*chatdb.LiveSession, *chatdb.GroupFeature, error)
	FinishLiveSession(ctx context.Context, groupID, status, reason string, now time.Time) (*chatdb.LiveSession, *chatdb.GroupFeature, bool, error)
	ApplyLiveCallback(ctx context.Context, eventID, streamID, channelID, app string, eventType int, eventTime int64, now time.Time, grace time.Duration) (*chatdb.LiveSession, *chatdb.GroupFeature, bool, error)
	PromoteDueLives(ctx context.Context, now time.Time, limit int64) ([]string, error)
	FinishDisconnectedLives(ctx context.Context, now time.Time, grace time.Duration, limit int64) ([]string, error)
	TakeLiveSession(ctx context.Context, sessionID string) (*chatdb.LiveSession, error)
	FinishLiveSync(ctx context.Context, groupID string, revision int64) error
	DelayLiveSync(ctx context.Context, groupID string, now time.Time) error
	ListDueLiveSync(ctx context.Context, now time.Time, limit int64) ([]*chatdb.LiveSyncTask, error)
	TakeLiveTip(ctx context.Context, userID, clientOrderID string) (*chatdb.LiveTip, error)
	CreateLiveTip(ctx context.Context, userID, clientOrderID, sessionID, anchor, currency, memo, paramHash string, amount int64, now time.Time) (*chatdb.LiveTip, error)
}

func NewChatDatabase(cli *mongoutil.Client) (ChatDatabaseInterface, error) {
	register, err := chat.NewRegister(cli.GetDB())
	if err != nil {
		return nil, err
	}
	account, err := chat.NewAccount(cli.GetDB())
	if err != nil {
		return nil, err
	}
	attribute, err := chat.NewAttribute(cli.GetDB())
	if err != nil {
		return nil, err
	}
	credential, err := chat.NewCredential(cli.GetDB())
	if err != nil {
		return nil, err
	}
	userLoginRecord, err := chat.NewUserLoginRecord(cli.GetDB())
	if err != nil {
		return nil, err
	}
	verifyCode, err := chat.NewVerifyCode(cli.GetDB())
	if err != nil {
		return nil, err
	}
	forbiddenAccount, err := admindb.NewForbiddenAccount(cli.GetDB())
	if err != nil {
		return nil, err
	}
	imIdentity, err := chat.NewUserIMIdentity(cli.GetDB())
	if err != nil {
		return nil, err
	}
	chatFolder, err := chat.NewChatFolder(cli.GetDB())
	if err != nil {
		return nil, err
	}
	conversationState, err := chat.NewChatConversationState(cli.GetDB())
	if err != nil {
		return nil, err
	}
	starFriend, err := chat.NewChatStarFriend(cli.GetDB())
	if err != nil {
		return nil, err
	}
	callRecord, err := chat.NewCallRecord(cli.GetDB())
	if err != nil {
		return nil, err
	}
	userLastSeen, err := chat.NewUserLastSeen(cli.GetDB())
	if err != nil {
		return nil, err
	}
	presenceVisibility, err := chat.NewPresenceVisibility(cli.GetDB())
	if err != nil {
		return nil, err
	}
	friendInvite, err := chat.NewFriendInvite(cli.GetDB())
	if err != nil {
		return nil, err
	}
	friendGrant, err := chat.NewFriendGrant(cli.GetDB())
	if err != nil {
		return nil, err
	}
	groupFriendProtect, err := chat.NewGroupFriendProtect(cli.GetDB())
	if err != nil {
		return nil, err
	}
	sticker, err := chat.NewChatSticker(cli.GetDB())
	if err != nil {
		return nil, err
	}
	stickerRequest, err := chat.NewChatStickerRequest(cli.GetDB())
	if err != nil {
		return nil, err
	}
	stickerPurge, err := chat.NewChatStickerPurge(cli.GetDB())
	if err != nil {
		return nil, err
	}
	favorite, err := chat.NewFavoriteMongo(cli.GetDB())
	if err != nil {
		return nil, err
	}
	fund, err := chat.NewFund(cli.GetDB())
	if err != nil {
		return nil, err
	}
	withdrawalSecurity, err := fundsecurity.New(context.Background(), cli.GetDB())
	if err != nil {
		return nil, err
	}
	feedback, err := chat.NewFeedback(cli.GetDB())
	if err != nil {
		return nil, err
	}
	commonGroup, err := chat.NewCommonGroup(cli.GetDB())
	if err != nil {
		return nil, err
	}
	liveStore, err := chat.NewLive(cli.GetDB())
	if err != nil {
		return nil, err
	}
	return &ChatDatabase{
		tx:                 cli.GetTx(),
		register:           register,
		account:            account,
		attribute:          attribute,
		credential:         credential,
		userLoginRecord:    userLoginRecord,
		verifyCode:         verifyCode,
		forbiddenAccount:   forbiddenAccount,
		imIdentity:         imIdentity,
		chatFolder:         chatFolder,
		conversationState:  conversationState,
		starFriend:         starFriend,
		callRecord:         callRecord,
		userLastSeen:       userLastSeen,
		presenceVisibility: presenceVisibility,
		friendInvite:       friendInvite,
		friendGrant:        friendGrant,
		groupFriendProtect: groupFriendProtect,
		sticker:            sticker,
		stickerRequest:     stickerRequest,
		stickerPurge:       stickerPurge,
		favorite:           favorite,
		fund:               fund,
		withdrawalSecurity: withdrawalSecurity,
		platform:           chat.NewPlatform(cli.GetDB()),
		feedback:           feedback,
		commonGroup:        commonGroup,
		live:               liveStore,
	}, nil
}

type ChatDatabase struct {
	tx                 tx.Tx
	register           chatdb.RegisterInterface
	account            chatdb.AccountInterface
	attribute          chatdb.AttributeInterface
	credential         chatdb.CredentialInterface
	userLoginRecord    chatdb.UserLoginRecordInterface
	verifyCode         chatdb.VerifyCodeInterface
	forbiddenAccount   admin.ForbiddenAccountInterface
	imIdentity         chatdb.UserIMIdentityInterface
	chatFolder         chatdb.ChatFolderInterface
	conversationState  chatdb.ChatConversationStateInterface
	starFriend         chatdb.ChatStarFriendInterface
	callRecord         chatdb.CallRecordInterface
	userLastSeen       chatdb.UserLastSeenInterface
	presenceVisibility chatdb.PresenceVisibilityInterface
	friendInvite       chatdb.FriendInviteInterface
	friendGrant        chatdb.FriendGrantInterface
	groupFriendProtect chatdb.GroupFriendProtectInterface
	sticker            chatdb.ChatStickerInterface
	stickerRequest     chatdb.ChatStickerRequestInterface
	stickerPurge       chatdb.ChatStickerPurgeInterface
	favorite           chatdb.FavoriteStore
	fund               *chat.Fund
	withdrawalSecurity fundsecurity.Interface
	platform           *chat.Platform
	feedback           *chat.Feedback
	commonGroup        *chat.CommonGroup
	live               *chat.Live
}

func (o *ChatDatabase) WithdrawalSecurity() fundsecurity.Interface {
	return o.withdrawalSecurity
}

func (o *ChatDatabase) markWithdrawalCredentialChange(ctx context.Context, userID, kind string) error {
	if o.withdrawalSecurity == nil {
		return nil // In-memory database doubles have no persistent security store.
	}
	return o.withdrawalSecurity.MarkCredentialChange(ctx, userID, kind, time.Now())
}

func changedBoundPhone(previous *chatdb.Attribute, areaCode, phoneNumber string) bool {
	return previous.PhoneNumber != "" && (previous.AreaCode != areaCode || previous.PhoneNumber != phoneNumber)
}

func (o *ChatDatabase) GetUser(ctx context.Context, userID string) (account *chatdb.Account, err error) {
	return o.account.Take(ctx, userID)
}

func (o *ChatDatabase) UpdateUseInfo(ctx context.Context, userID string, attribute map[string]any, updateCred, delCred []*chatdb.Credential) (err error) {
	return o.tx.Transaction(ctx, func(ctx context.Context) error {
		// Administrative profile edits share the same cooldown rule as the
		// dedicated phone-change endpoint. An initial phone binding is not a change.
		_, hasAreaCode := attribute["area_code"]
		_, hasPhoneNumber := attribute["phone_number"]
		if hasAreaCode || hasPhoneNumber {
			previous, err := o.attribute.Take(ctx, userID)
			if err != nil {
				return err
			}
			areaCode, phoneNumber := previous.AreaCode, previous.PhoneNumber
			if hasAreaCode {
				areaCode, _ = attribute["area_code"].(string)
			}
			if hasPhoneNumber {
				phoneNumber, _ = attribute["phone_number"].(string)
			}
			if changedBoundPhone(previous, areaCode, phoneNumber) {
				if err := o.markWithdrawalCredentialChange(ctx, userID, fundsecurity.CredentialPhone); err != nil {
					return err
				}
			}
		}
		if err = o.attribute.Update(ctx, userID, attribute); err != nil {
			return err
		}
		for _, credential := range updateCred {
			if err = o.credential.CreateOrUpdateAccount(ctx, credential); err != nil {
				return err
			}
		}
		if err = o.credential.DeleteByUserIDType(ctx, delCred...); err != nil {
			return err
		}
		return nil
	})
}

func (o *ChatDatabase) FindAttribute(ctx context.Context, userIDs []string) ([]*chatdb.Attribute, error) {
	return o.attribute.Find(ctx, userIDs)
}

func (o *ChatDatabase) FindAttributeMissingAccount(ctx context.Context) ([]*chatdb.Attribute, error) {
	return o.attribute.FindMissingAccount(ctx)
}

func (o *ChatDatabase) FindPlainPublicAccount(ctx context.Context) ([]*chatdb.Attribute, error) {
	return o.attribute.FindPlainPublicAccount(ctx)
}

func (o *ChatDatabase) FindAttributeByAccount(ctx context.Context, accounts []string) ([]*chatdb.Attribute, error) {
	return o.attribute.FindAccount(ctx, accounts)
}

func (o *ChatDatabase) TakeAttributeByPhone(ctx context.Context, areaCode string, phoneNumber string) (*chatdb.Attribute, error) {
	return o.attribute.TakePhone(ctx, areaCode, phoneNumber)
}

func (o *ChatDatabase) TakeAttributeByPhoneNumber(ctx context.Context, phoneNumber string) (*chatdb.Attribute, error) {
	return o.attribute.TakeByPhone(ctx, phoneNumber)
}

func (o *ChatDatabase) TakeAttributeByEmail(ctx context.Context, email string) (*chatdb.Attribute, error) {
	return o.attribute.TakeEmail(ctx, email)
}

func (o *ChatDatabase) TakeAttributeByAccount(ctx context.Context, account string) (*chatdb.Attribute, error) {
	return o.attribute.TakeAccount(ctx, account)
}

func (o *ChatDatabase) TakeAttributeByNickname(ctx context.Context, nickname string) (*chatdb.Attribute, error) {
	return o.attribute.TakeNickname(ctx, nickname)
}

func (o *ChatDatabase) TakeAttributeByUserID(ctx context.Context, userID string) (*chatdb.Attribute, error) {
	return o.attribute.Take(ctx, userID)
}

func (o *ChatDatabase) TakeLastVerifyCode(ctx context.Context, account string) (*chatdb.VerifyCode, error) {
	return o.verifyCode.TakeLast(ctx, account)
}

func (o *ChatDatabase) TakeAccount(ctx context.Context, userID string) (*chatdb.Account, error) {
	return o.account.Take(ctx, userID)
}

func (o *ChatDatabase) TakeCredentialByAccount(ctx context.Context, account string) (*chatdb.Credential, error) {
	return o.credential.TakeAccount(ctx, account)
}

func (o *ChatDatabase) TakeCredentialsByUserID(ctx context.Context, userID string) ([]*chatdb.Credential, error) {
	return o.credential.Find(ctx, userID)
}

func (o *ChatDatabase) Search(ctx context.Context, normalUser int32, keyword string, genders int32, pagination pagination.Pagination) (total int64, attributes []*chatdb.Attribute, err error) {
	var forbiddenIDs []string
	if int(normalUser) == constant.NormalUser {
		forbiddenIDs, err = o.forbiddenAccount.FindAllIDs(ctx)
		if err != nil {
			return 0, nil, err
		}
	}
	total, totalUser, err := o.attribute.SearchNormalUser(ctx, keyword, forbiddenIDs, genders, pagination)
	if err != nil {
		return 0, nil, err
	}
	return total, totalUser, nil
}

func (o *ChatDatabase) SearchUser(ctx context.Context, keyword string, userIDs []string, genders []int32, pagination pagination.Pagination) (int64, []*chatdb.Attribute, error) {
	return o.attribute.SearchUser(ctx, keyword, userIDs, genders, pagination)
}

func (o *ChatDatabase) SearchAdminUsers(ctx context.Context, normalUser int32, keyword string, gender int32, pagination pagination.Pagination) (int64, []*chatdb.Attribute, error) {
	var forbiddenIDs []string
	if int(normalUser) == constant.NormalUser {
		var err error
		forbiddenIDs, err = o.forbiddenAccount.FindAllIDs(ctx)
		if err != nil {
			return 0, nil, err
		}
	}
	return o.attribute.SearchAdminUsers(ctx, keyword, forbiddenIDs, gender, pagination)
}

func (o *ChatDatabase) CountVerifyCodeRange(ctx context.Context, account string, start time.Time, end time.Time) (int64, error) {
	return o.verifyCode.RangeNum(ctx, account, start, end)
}

func (o *ChatDatabase) AddVerifyCode(ctx context.Context, verifyCode *chatdb.VerifyCode, fn func() error) error {
	return o.tx.Transaction(ctx, func(ctx context.Context) error {
		if err := o.verifyCode.Add(ctx, []*chatdb.VerifyCode{verifyCode}); err != nil {
			return err
		}
		if fn != nil {
			return fn()
		}
		return nil
	})
}

func (o *ChatDatabase) UpdateVerifyCodeIncrCount(ctx context.Context, id string) error {
	return o.verifyCode.Incr(ctx, id)
}

func (o *ChatDatabase) DelVerifyCode(ctx context.Context, id string) error {
	return o.verifyCode.Delete(ctx, id)
}

func (o *ChatDatabase) RegisterUser(ctx context.Context, register *chatdb.Register, account *chatdb.Account, attribute *chatdb.Attribute, credentials []*chatdb.Credential) error {
	attribute.FaceURL = avatar.User(attribute.FaceURL)
	businessUID, err := imidentity.NewBusinessUID()
	if err != nil {
		return err
	}
	identity := &chatdb.UserIMIdentity{
		BusinessUID: businessUID,
		IMUserID:    attribute.UserID,
		CreatedAt:   time.Now(),
	}
	return o.tx.Transaction(ctx, func(ctx context.Context) error {
		if code, ok := ctx.Value(registrationCodeKey{}).(registrationCode); ok && code.id != "" {
			if err := o.verifyCode.Consume(ctx, code.id, code.maxCount); err != nil {
				return err
			}
		}
		if err := o.register.Create(ctx, register); err != nil {
			return err
		}
		if err := o.account.Create(ctx, account); err != nil {
			return err
		}
		if err := o.attribute.Create(ctx, attribute); err != nil {
			return err
		}
		if err := o.credential.Create(ctx, credentials...); err != nil {
			return err
		}
		if err := o.imIdentity.Create(ctx, identity); err != nil {
			return err
		}
		return nil
	})
}

func (o *ChatDatabase) TakeIMIdentity(ctx context.Context, imUserID string) (*chatdb.UserIMIdentity, error) {
	return o.imIdentity.TakeByIMUserID(ctx, imUserID)
}

func (o *ChatDatabase) LoginRecord(ctx context.Context, record *chatdb.UserLoginRecord, verifyCodeID *string) error {
	return o.tx.Transaction(ctx, func(ctx context.Context) error {
		if err := o.userLoginRecord.UpsertByDevice(ctx, record); err != nil {
			return err
		}
		if verifyCodeID != nil {
			if err := o.verifyCode.Consume(ctx, *verifyCodeID, authenticationCodeLimit(ctx)); err != nil {
				return err
			}
		}
		return nil
	})
}

func (o *ChatDatabase) ListLoginRecords(ctx context.Context, userID string) ([]*chatdb.UserLoginRecord, error) {
	return o.userLoginRecord.ListByUserID(ctx, userID)
}

func (o *ChatDatabase) SetDeviceTrusted(ctx context.Context, userID, deviceID string, trusted bool) error {
	return o.userLoginRecord.SetDeviceTrusted(ctx, userID, deviceID, trusted)
}

func (o *ChatDatabase) DeleteDeviceRecord(ctx context.Context, userID, deviceID string) error {
	return o.userLoginRecord.DeleteByDevice(ctx, userID, deviceID)
}

func (o *ChatDatabase) DeleteDeviceByChatToken(ctx context.Context, userID, token string) error {
	return o.userLoginRecord.DeleteByChatToken(ctx, userID, token)
}

func (o *ChatDatabase) UpdatePhoneAndDeleteVerifyCodes(ctx context.Context, userID, areaCode, phoneNumber string, verifyCodeIDs []string) error {
	return o.tx.Transaction(ctx, func(ctx context.Context) error {
		previous, err := o.attribute.Take(ctx, userID)
		if err != nil {
			return err
		}
		if changedBoundPhone(previous, areaCode, phoneNumber) {
			if err := o.markWithdrawalCredentialChange(ctx, userID, fundsecurity.CredentialPhone); err != nil {
				return err
			}
		}
		if err := o.attribute.Update(ctx, userID, map[string]any{
			"area_code":    areaCode,
			"phone_number": phoneNumber,
		}); err != nil {
			return err
		}
		if err := o.credential.CreateOrUpdateAccount(ctx, &chatdb.Credential{
			UserID:      userID,
			Account:     areaCode + " " + phoneNumber,
			Type:        constant.CredentialPhone,
			AllowChange: true,
		}); err != nil {
			return err
		}
		for _, id := range verifyCodeIDs {
			if id == "" {
				continue
			}
			if err := o.verifyCode.Delete(ctx, id); err != nil {
				return err
			}
		}
		return nil
	})
}

func (o *ChatDatabase) UpdatePassword(ctx context.Context, userID string, password string) error {
	return o.tx.Transaction(ctx, func(ctx context.Context) error {
		previous, err := o.account.Take(ctx, userID)
		if err != nil {
			return err
		}
		if previous.Password != "" && previous.Password != password {
			if err := o.markWithdrawalCredentialChange(ctx, userID, fundsecurity.CredentialLoginPassword); err != nil {
				return err
			}
		}
		return o.account.UpdatePassword(ctx, userID, password)
	})
}

func (o *ChatDatabase) UpgradeLegacyPassword(ctx context.Context, userID, previousHash, passwordHash string, bootstrap *chatdb.UserLoginRecord) (bool, error) {
	if bootstrap == nil {
		return o.account.UpgradeLegacyPassword(ctx, userID, previousHash, passwordHash, false)
	}
	if bootstrap.UserID != userID || strings.TrimSpace(bootstrap.DeviceID) == "" || bootstrap.Trusted || bootstrap.SMSExempt || bootstrap.ChatToken != "" || bootstrap.IMToken != "" {
		return false, errors.New("invalid legacy bootstrap device record")
	}
	updated := false
	err := o.tx.Transaction(ctx, func(ctx context.Context) error {
		updated = false
		attribute, err := o.attribute.Take(ctx, userID)
		if err != nil {
			return err
		}
		if attribute.PhoneNumber != "" || attribute.AreaCode != "" {
			return nil
		}
		updated, err = o.account.UpgradeLegacyPassword(ctx, userID, previousHash, passwordHash, true)
		if err != nil || !updated {
			return err
		}
		// Write the attribute in the same transaction: a simultaneous phone bind
		// conflicts and retries with fresh phone state instead of a stale snapshot.
		if err := o.attribute.Update(ctx, userID, map[string]any{"legacy_password_bootstrap_time": time.Now()}); err != nil {
			return err
		}
		// Persist only this newly password-authenticated device. If token creation
		// fails after commit, the same device can retry without restoring the old
		// password or re-enabling the one-time bridge for another device.
		return o.userLoginRecord.UpsertByDevice(loginhistory.WithEventType(ctx, loginhistory.EventPasswordBootstrap), bootstrap)
	})
	return updated && err == nil, err
}

func (o *ChatDatabase) UpdatePayPassword(ctx context.Context, userID, hash, codeID string) (initialSet bool, err error) {
	err = o.tx.Transaction(ctx, func(ctx context.Context) error {
		// Transaction callbacks may run again after a concurrent credential write.
		// Classify the successful attempt's previous state, never an aborted one.
		initialSet = false
		previous, err := o.account.Take(ctx, userID)
		if err != nil {
			return err
		}
		initialSet = previous.PayPassword == ""
		if previous.PayPassword != "" && previous.PayPassword != hash {
			if err := o.markWithdrawalCredentialChange(ctx, userID, fundsecurity.CredentialPayPassword); err != nil {
				return err
			}
		}
		if err := o.account.Update(ctx, userID, map[string]any{"pay_password": hash}); err != nil {
			return err
		}
		if codeID == "" {
			return nil
		}
		return o.verifyCode.Delete(ctx, codeID)
	})
	if err != nil {
		return false, err
	}
	return initialSet, nil
}

func (o *ChatDatabase) UpdatePasswordAndDeleteVerifyCode(ctx context.Context, userID string, password string, codeID string) error {
	return o.tx.Transaction(ctx, func(ctx context.Context) error {
		previous, err := o.account.Take(ctx, userID)
		if err != nil {
			return err
		}
		if previous.Password != "" && previous.Password != password {
			if err := o.markWithdrawalCredentialChange(ctx, userID, fundsecurity.CredentialLoginPassword); err != nil {
				return err
			}
		}
		if err := o.account.UpdatePassword(ctx, userID, password); err != nil {
			return err
		}
		if codeID == "" {
			return nil
		}
		if err := o.verifyCode.Consume(ctx, codeID, authenticationCodeLimit(ctx)); err != nil {
			return err
		}
		return nil
	})
}

func (o *ChatDatabase) NewUserCountTotal(ctx context.Context, before *time.Time) (int64, error) {
	return o.register.CountTotal(ctx, before)
}

func (o *ChatDatabase) UserLoginCountTotal(ctx context.Context, before *time.Time) (int64, error) {
	return o.userLoginRecord.CountTotal(ctx, before)
}

func (o *ChatDatabase) UserLoginCountRangeEverydayTotal(ctx context.Context, start *time.Time, end *time.Time) (map[string]int64, int64, error) {
	return o.userLoginRecord.CountRangeEverydayTotal(ctx, start, end)
}

func (o *ChatDatabase) DelUserAccount(ctx context.Context, userIDs []string) error {
	return o.tx.Transaction(ctx, func(ctx context.Context) error {
		if err := o.register.Delete(ctx, userIDs); err != nil {
			return err
		}
		if err := o.account.Delete(ctx, userIDs); err != nil {
			return err
		}
		if err := o.attribute.Delete(ctx, userIDs); err != nil {
			return err
		}
		if err := o.credential.Delete(ctx, userIDs); err != nil {
			return err
		}
		if err := o.imIdentity.Delete(ctx, userIDs); err != nil {
			return err
		}
		if err := o.chatFolder.DeleteByOwner(ctx, userIDs); err != nil {
			return err
		}
		if err := o.conversationState.DeleteByOwner(ctx, userIDs); err != nil {
			return err
		}
		if err := o.starFriend.DeleteByOwner(ctx, userIDs); err != nil {
			return err
		}
		if err := o.callRecord.DeleteByOwner(ctx, userIDs); err != nil {
			return err
		}
		if err := o.presenceVisibility.DeleteByUser(ctx, userIDs); err != nil {
			return err
		}
		if err := o.deleteStickersByOwner(ctx, userIDs); err != nil {
			return err
		}
		return o.favorite.DeleteByOwner(ctx, userIDs)
	})
}

func (o *ChatDatabase) Favorite() chatdb.FavoriteStore {
	return o.favorite
}

func (o *ChatDatabase) deleteStickersByOwner(ctx context.Context, userIDs []string) error {
	items, err := o.sticker.ListByOwners(ctx, userIDs)
	if err != nil {
		return err
	}
	for _, item := range items {
		if item.ThumbnailName == "" {
			continue
		}
		if err := o.scheduleStickerPurge(ctx, item.ThumbnailName, item.ThumbnailKey); err != nil {
			return err
		}
	}
	if err := o.sticker.DeleteByOwner(ctx, userIDs); err != nil {
		return err
	}
	return o.stickerRequest.DeleteByOwner(ctx, userIDs)
}
