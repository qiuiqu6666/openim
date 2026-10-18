package conversation_msg

import (
	"github.com/openimsdk/openim-sdk-core/v3/pkg/constant"
	"github.com/openimsdk/openim-sdk-core/v3/pkg/db/model_struct"
	"testing"
)

func TestOptionalAttachedInfoEmptyAndPresent(t *testing.T) {
	for _, raw := range []string{"", " \t\r\n", "{}", "null", `{"isPrivateChat":true,"burnDuration":60}`} {
		t.Run(raw, func(t *testing.T) {
			msg := LocalChatLogToMsgStruct(&model_struct.LocalChatLog{ContentType: constant.Text, Content: `{"content":"hello"}`, AttachedInfo: raw})
			if msg.AttachedInfoElem == nil || msg.TextElem == nil || msg.TextElem.Content != "hello" {
				t.Fatalf("lost message: %+v", msg)
			}
			if raw == `{"isPrivateChat":true,"burnDuration":60}` && (!msg.AttachedInfoElem.IsPrivateChat || msg.AttachedInfoElem.BurnDuration != 60) {
				t.Fatal("lost attached metadata")
			}
		})
	}
}
