# Wallet deposits

`../wallet_receive_screen.dart` remains the public compatibility route. It obtains
an address independently from `WalletFundApi.fetchDepositAddress`; a legacy
caller-supplied address is never rendered or shared.

The home deposit action first opens
`coin_picker/wallet_deposit_coin_picker_screen.dart`, matching the supplied
exchange-style reference with search and one popular-coins list. Each enabled
asset appears once; alphabetic sections and the side index are omitted.
It reuses the controller to derive enabled coins and the USDT contract exclusively
from the authenticated deposit endpoint, including pending allocation responses.
Coin codes, names and the actual contract are searchable; unsupported assets are
never inserted. The search draft survives opening and returning from the address
route. That route fetches fresh data with the same API/account dependencies and
rejects a selected currency that has since become unavailable instead of silently
changing the chosen coin. Existing direct compatibility routes retain their
default selection behavior. The picker owns and disposes its controller, search
focus and input; covered/background routes stop pending allocation polling.

The picker was checked against 99chat's `withdraw_coin_picker_screen.dart` and
`wallet_receive_screen.dart`. It reuses wallet navigation, coin artwork, theme
colors, spacing and the existing deposit controller/address route. A separate
deposit row adapter is necessary because the withdrawal picker displays
balances and transfer targets. Both pickers share the list/search widgets; light and
dark themes are supported, with minimum row heights that expand for large text.

- `wallet_deposit_controller.dart` owns account scope, pending allocation and one
  non-overlapping request/timer. Pending responses schedule a four-second retry;
  covered routes, backgrounding and disposal stop it. Late results are discarded
  if the account changed or the route became inactive. Failed requests use the
  wallet-specific safe error mapper and a manual retry.
- `widgets/wallet_deposit_ready_content.dart` arranges the supplied exchange-style
  deposit reference: centered QR, gray network/address card, explanation rows and
  a bottom save/share action. The entire body can scroll on small screens or at
  large text sizes. Light/dark colors come from the existing wallet theme.
- `widgets/wallet_deposit_address_card.dart` shows the actual TRON network, full
  wrapping address. The contract row and its information dialog are omitted.
  Tapping the address heading, text
  or surrounding space copies the full address through the guarded callback and
  public centered toast. Contract metadata remains available to coin search.
- `widgets/wallet_deposit_qr.dart` uses the actual address, high error correction,
  a white quiet zone and a small existing coin mark. The admission threshold is
  displayed separately as a required block count, never as live progress.
- `widgets/wallet_deposit_help_sheet.dart` explains the real network/confirmation
  requirements. Only TRON is available; no alternative networks are fabricated.
  BI99 is explicitly unsupported. `wallet_deposit_rule_details.dart` reads
  `currencyRules` for the selected coin's minimum deposit, arrival estimate,
  receiving account, cumulative withdrawal-unlock threshold and Memo/Tag
  requirement. The help sheet reuses the same values. Missing fields remain
  "Not provided yet" in the current language; unknown Memo/Tag requirements
  are not presented as optional. Address and QR still use `data.address`.
- `widgets/wallet_deposit_share_sheet.dart` displays a floating address card above
  a separate bottom panel with Save image, Share and Cancel. The card includes
  the existing 99Chat brand, the opening timestamp, actual coin/network and full
  address. Both actions capture the same static QR card; system sharing sends a
  PNG through the installed `share_plus` plugin. Account and address checks reject
  stale shares or asynchronous feedback. Small screens and large text scroll the
  card while keeping the actions reachable. Light/dark colors and five languages
  follow the page; layout values live in `share/wallet_deposit_share_tokens.dart`.
  Export fills the capture with the card's opaque background before encoding so
  the Android gallery's JPEG conversion cannot turn transparent rounded corners
  into black edges; system sharing uses the same image treatment.
- `wallet_deposit_tokens.dart` keeps deposit-only layout values separate from
  shared wallet colors and spacing.

The single popular-coins list, search input and geometry are shared with
the withdrawal picker under `../widgets/coin_picker/`. Deposit-specific wrappers
retain their public inputs, keys, currency metadata and row-selection behavior;
the deposit controller continues to own all requests and account checks.

The history shortcut opens the shared deposit-record route with the same injected
API and account provider. Each event is preserved; missing time and historical
balance remain unknown, and rollback events retain their status.

Tests live under `test/pages/wallet/deposit/` and inject fake API values only in
the test tree. Optional actual-widget exports use `WALLET_DEPOSIT_PREVIEW_DIR` and
cover pending/ready and unknown-time deposit records in light and dark themes.
The integration does not change already-connected chat payment, packet or
password pages. Live-device verification is owned by the integration task.

Coin picker verification on 2026-10-06: 58 focused deposit, home-navigation and
wallet-contract cases passed; the new picker contributes 25 cases. Six actual
widget previews passed and were inspected across light/dark, normal/search and
320px large-text keyboard states. Focused analysis and the Android debug build
passed. The broader existing home suite has 27 failures concerning valuation
placeholders, the currency control and associated layout/state/ink expectations;
those components were not changed by this deposit-entry work. Live-account API
and physical Android/iOS device behavior were not exercised.

Deposit-detail reference verification on 2026-10-06: 82 focused deposit,
home-navigation and wallet-contract cases passed; 12 actual widget exports
cover pending, USDT/TRX, large text, sharing and records in both themes. Every
one of the eight ready/share PNGs was decoded from the exact exported bytes by
Dart ZXing and independently from the saved file by ZXing-C++; all decoded the
injected endpoint address, including the center coin mark. Focused analysis and
the Android debug build passed. Fixtures never contact a live account or save to
the real gallery. Physical-device gallery access and sharing remain unverified.

Tap-to-copy verification on 2026-10-06: 83 focused deposit, home-navigation and
wallet-contract cases passed. Heading, full-address text and blank-space taps
each copy once and show the public centered toast once; stale-account callbacks
remain blocked. Ten deposit/share widget exports passed across both themes and
large text, retaining the exported-PNG QR checks. Focused analysis and the
Android debug build passed. The navigation fixture uses an empty journal page
for the current records endpoint instead of calling a live service.

Popular-only/contract-removal verification on 2026-10-06: 112 focused wallet
cases passed. Twenty-two actual widget exports passed, covering both pickers,
deposit details and sharing in light/dark and large-text states; ready/share
exports retained their exact-PNG QR decode checks. The shared list omits duplicate
rows, alphabetic sections and the side index. The address card omits contract
details while actual-contract search and guarded full-address copy remain intact.
Focused analysis and the Android debug build passed. Live-account transactions
and physical-device display were not exercised.

Currency-rule integration verification on 2026-10-06: 242 focused wallet cases
passed, including exact decimal limits/fees, refreshed configuration and pending
order recovery. Twenty actual deposit/withdrawal widget exports passed across
both themes and large text; the ready/share QR exports retained their exact-PNG
decode checks. Focused analysis and the Android debug build passed. Live-account
transactions and physical-device display were not exercised.

Deposit-share reference and export verification on 2026-10-06: 134 focused
deposit, coin-picker and deposit-history cases passed; 24 unrelated optional
preview exports were skipped. Four additional light/dark, large-text and
landscape exports used the actual gallery-save service. Each full card PNG was
opaque with the expected corner color, and both its PNG and simulated gallery
JPEG decoded to the exact fixture address. Small-screen scrolling reached the
complete address while the action panel stayed fixed. The 20 sharing-service
cases also cover cancellation, stale-account/disposed contexts, permission
waits, native plugin failures and image transparency. Focused analysis and the
Android debug build passed. The generated package is
`app-deposit-share-fix-debug-20261006.apk`; native sharing and gallery writes
were verified at the mocked plugin boundary rather than on a physical device.
