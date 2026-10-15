package complaints

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"github.com/google/uuid"
	"github.com/openimsdk/tools/errs"
	"strings"
	"unicode/utf8"
)

var (
	ErrConflict   = errs.NewCodeError(20110, "ComplaintRequestConflict")
	ErrRate       = errs.NewCodeError(20111, "ComplaintRateLimited")
	ErrMembership = errs.NewCodeError(20112, "ComplaintGroupMembershipRequired")
	ErrUser       = errs.NewCodeError(20113, "ComplaintUserNotFound")
)

type Payload struct {
	ClientRequestID string `json:"clientRequestID" bson:"client_request_id"`
	ReportedUserID  string `json:"reportedUserID" bson:"reported_user_id"`
	GroupID         string `json:"groupID" bson:"group_id"`
	Reason          string `json:"reason" bson:"reason"`
	Content         string `json:"content" bson:"content"`
	ClientVersion   string `json:"clientVersion" bson:"client_version"`
}
type Shot struct {
	Key  string `json:"-" bson:"key"`
	Mime string `json:"mimeType" bson:"mime"`
	Size int64  `json:"size" bson:"size"`
	URL  string `json:"url,omitempty" bson:"-"`
}
type Record struct {
	UserNickname         string `json:"userNickname" bson:"-"`
	ReportedUserNickname string `json:"reportedUserNickname" bson:"-"`
	GroupName            string `json:"groupName" bson:"-"`
	Payload              `bson:",inline"`
	ID                   string `json:"complaintID" bson:"_id"`
	UserID               string `json:"userID" bson:"user_id"`
	ChatType             string `json:"chatType" bson:"chat_type"`
	Digest               string `json:"-" bson:"digest"`
	Screenshots          []Shot `json:"screenshots" bson:"screenshots"`
	Status               string `json:"status" bson:"status"`
	Note                 string `json:"note" bson:"note"`
	CreatedAt            int64  `json:"createdAt" bson:"created_at"`
	UpdatedAt            int64  `json:"updatedAt" bson:"updated_at"`
	ReviewedBy           string `json:"reviewedBy" bson:"reviewed_by"`
}

func Normalize(p Payload, chatType, owner string) (Payload, error) {
	p.ClientRequestID = strings.TrimSpace(p.ClientRequestID)
	p.ReportedUserID = strings.TrimSpace(p.ReportedUserID)
	p.GroupID = strings.TrimSpace(p.GroupID)
	p.Content = strings.TrimSpace(p.Content)
	if _, err := uuid.Parse(p.ClientRequestID); err != nil {
		return p, errs.ErrArgs.WrapMsg("invalid request ID")
	}
	if owner == "" || len(p.ReportedUserID) > 128 || len(p.GroupID) > 128 || len(p.ClientVersion) > 64 || utf8.RuneCountInString(p.Content) > 2000 {
		return p, errs.ErrArgs.WrapMsg("invalid complaint")
	}
	switch p.Reason {
	case "spam", "harassment", "fraud", "pornography", "violence", "illegal", "other":
	default:
		return p, errs.ErrArgs.WrapMsg("invalid complaint reason")
	}
	if chatType == "group" {
		if p.GroupID == "" {
			return p, errs.ErrArgs.WrapMsg("group required")
		}
	} else if chatType != "c2c" || p.GroupID != "" || p.ReportedUserID == "" || p.ReportedUserID == owner {
		return p, errs.ErrArgs.WrapMsg("invalid reported user")
	}
	return p, nil
}
func Digest(p Payload, chatType string, hashes []string) string {
	b, _ := json.Marshal([]any{p, chatType, hashes})
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}
func ValidStatus(s string) bool {
	return s == "received" || s == "processing" || s == "resolved" || s == "rejected"
}
