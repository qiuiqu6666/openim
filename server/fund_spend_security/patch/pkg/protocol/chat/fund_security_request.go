package chat

func (r *FundWithdrawalSecurityReq) TransactionCount() int {
	if r == nil {
		return 0
	}
	n := 0
	if r.Withdrawal != nil {
		n++
	}
	if r.Transfer != nil {
		n++
	}
	if r.Packet != nil {
		n++
	}
	if r.Swap != nil {
		n++
	}
	if r.Tip != nil {
		n++
	}
	return n
}
