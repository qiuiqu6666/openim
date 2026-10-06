# Withdrawal currency picker

`../../withdraw_coin_picker_screen.dart` keeps the existing public import and
exports `WithdrawCoinPickerScreen` from this directory. The constructor still
defaults to friend transfers; the wallet withdrawal type sheet selects the
chain or internal transfer mode. Chain selection opens
`../form/WalletChainWithdrawalScreen` with its original coin and payment method.
The address, network and amount now share one page before the existing PIN flow.
Internal selection opens `FundSendPage(internalWithdrawal: true)` with the
exact selected currency. Its account/amount form, recipient resolution and
single-friend picker live in `../../../fund/internal_transfer/`.

The layout was checked against 99chat's `withdraw_coin_picker_screen.dart` and
the supplied exchange-style coin-list reference used by the deposit picker.
Search and the single popular-coins list use the same
`../../widgets/coin_picker/` components as deposits. The deposit wrappers keep
their existing keys and request ownership. Shared geometry and theme colors
avoid maintaining two copies of the same list/search interface. Each enabled
asset appears once; alphabetic sections and the side index are omitted.

- `wallet_withdraw_coin_picker_screen.dart` owns the existing wallet controller,
  search draft, focus, route visibility and app lifecycle. It pauses balance
  refreshes while covered/backgrounded and consumes deferred updates on return.
  Loading, empty, retry and account-change states do not expose selectable
  fallback rows. Account changes invalidate the display on return/resume even
  without a balance event. Captured callbacks cannot navigate after disposal.
- `wallet_withdraw_coin_labels.dart` provides display metadata for the existing
  USDT/TRX/platform assets without changing their DTOs. Search matches the code,
  original backend name and displayed name. Coin balances do not contain a
  contract address, so the withdrawal search does not advertise that capability.
- `widgets/wallet_withdraw_coin_row.dart` reuses the existing coin artwork and
  presents the server's available-balance text and fiat valuation. Narrow or
  large-text layouts stack those values and wrap instead of truncating them.

Production balances still come from `WalletFundRepository` and
`GET /chat/fund/balances`. Chain mode retains the existing enabled USDT/TRX filter;
friend mode keeps enabled platform coins. Tapping checks the account and looks
up the latest enabled DTO before navigation. Chain mode preserves its
`balMinor`, `scale`, `availableRaw` and `frozen`, including after a balance
refresh. Internal mode loads fresh precise available quantities from FundApi.
Neither flow builds payment amounts from rounded display strings.

Tests live in `test/pages/wallet/withdrawal/coin_picker/` and use injected wallet
fixtures only. They inspect real navigation destinations and remove those
routes before mounting SDK contacts or making payment requests. Optional actual
widget exports use `WALLET_WITHDRAW_PICKER_PREVIEW_DIR` and show the chain entry
in light/dark normal, search and 320px large-text keyboard states. The previews
do not draw the native keyboard or represent a real account.

Verification on 2026-10-06: 112 focused withdrawal/deposit, home-navigation,
payment-unit and wallet-contract cases passed, including 27 picker cases. Six
actual widget exports were inspected across both themes, search and 320px
large-text keyboard states. Focused analysis and the Android debug build
passed. No real payment was submitted; physical-device display and live
withdrawal execution remain unverified.

Popular-only verification on 2026-10-06: the shared picker now displays each
enabled asset once in the popular list without alphabetic sections or a side
index. All 112 focused wallet cases and 22 combined picker/deposit/share exports
passed. Both themes and 320px large-text keyboard states were inspected; focused
analysis and the Android debug build passed. Live withdrawal was not exercised.
