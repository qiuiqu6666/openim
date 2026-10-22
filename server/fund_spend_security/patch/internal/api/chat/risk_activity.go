package chat

import (
	"encoding/json"
	"math/big"
	"strings"

	"github.com/openimsdk/chat/pkg/common/riskcontrol"
)

type riskOrder struct {
	OrderID        string `json:"orderID"`
	ClientOrderID  string `json:"clientOrderID"`
	Currency       string `json:"currency"`
	Amount         string `json:"amount"`
	Status         string `json:"status"`
	RecvID         string `json:"recvID"`
	TargetCurrency string `json:"targetCurrency"`
	TargetAmount   string `json:"targetAmount"`
}

func riskActivity(action string, r riskRequest) *riskcontrol.ActivityDetails {
	if action == "device_trust" || action == "device_remove" {
		return &riskcontrol.ActivityDetails{TargetDeviceID: r.DeviceID}
	}
	if !strings.HasPrefix(action, "fund_") {
		return nil
	}
	if r.Packet != nil {
		r = *r.Packet
		action = "fund_packet"
	} else if r.Swap != nil {
		r = *r.Swap
		action = "fund_swap"
	} else if r.Tip != nil {
		r = *r.Tip
		action = "fund_tip"
	} else if r.Transfer != nil {
		r = *r.Transfer
	} else if r.Withdrawal != nil {
		r = *r.Withdrawal
	}
	d := &riskcontrol.ActivityDetails{}
	currency := strings.ToUpper(strings.TrimSpace(r.Currency))
	if action == "fund_swap" || action == "fund_quote" {
		currency = strings.ToUpper(strings.TrimSpace(r.FromCurrency))
	}
	var amount string
	_ = json.Unmarshal(r.Amount, &amount)
	n, err := riskcontrol.MinorAmount(amount, currency)
	if action == "fund_tip" {
		// Live tips use integer minor units, unlike the wallet decimal strings.
		var minor int64
		err = json.Unmarshal(r.Amount, &minor)
		n = minor
	}
	if action == "fund_packet" && r.Biz == "packet_normal" && r.Scene == "group" {
		share, e := riskcontrol.MinorAmount(r.ShareAmount, currency)
		total := new(big.Int).Mul(big.NewInt(share), big.NewInt(int64(r.ShareCount)))
		if e == nil && r.ShareCount > 0 && total.IsInt64() {
			n = total.Int64()
			err = nil
		}
	}
	if err == nil && n > 0 {
		d.Amount = riskcontrol.FormatMinor(big.NewInt(n), currency)
		if d.Amount != "" {
			d.Currency = currency
		}
	}
	if len(r.ClientOrderID) <= 128 {
		d.ClientOrderID = r.ClientOrderID
	}
	return d
}
func applyRiskOrder(in *riskcontrol.Input, order *riskOrder) {
	if order == nil || order.OrderID == "" || !riskcontrol.IsFundSpend(in.Action) {
		return
	}
	in.Details = &riskcontrol.ActivityDetails{Currency: order.Currency, Amount: order.Amount, OrderID: order.OrderID, ClientOrderID: order.ClientOrderID, Status: order.Status, TargetCurrency: order.TargetCurrency, TargetAmount: order.TargetAmount, AcceptedOrder: true}
	in.TargetID = order.RecvID
}
func riskCredentialFailure(action string, code int) bool {
	if action == "login" {
		return code == 20001 || code == 20002 || code == 20006 || code == 20007 || code == 20008 || code == 20009
	}
	// Locked responses are not fresh password errors. RPC retains its own
	// account lock; cross-device counters count only confirmed wrong attempts.
	return (riskcontrol.IsFundSpend(action) || action == "pay_password_set") && code == 20035
}
