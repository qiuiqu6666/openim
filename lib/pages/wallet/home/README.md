# Wallet home

The wallet overview follows the supplied asset-value reference: a white
surface, visibility toggle, two document-outline shortcuts, an amount with
fixed CNY valuation, a daily-change row and three equally sized text actions.
Deposit is dark in the light theme; withdrawal and transfer use neutral fills.
Every screen width keeps the same reading order, with content centered at up
to 680 logical pixels.
The main-tab title and background are plain, without decorative effects.

## Ownership

- `../wallet_screen.dart`: compatibility entry and existing tab/route lifecycle;
  creates and disposes the single `WalletController`. Activation, 10-second
  reload interval and deferred refresh behavior are retained.
- `wallet_home_view.dart`: adaptive gutters, pull-to-refresh, local trend expansion and the existing
  deposit-coin-picker/withdraw/exchange/record routes. Deposit coin selection
  owns its authenticated capabilities and opens the address route afterwards.
- `widgets/wallet_balance_overview.dart`: exact total strings with fixed CNY valuation, the temporary
  inspected trend balance and a visibility toggle. Visibility is owned by the
  controller and used by the list.
- `widgets/wallet_daily_profit_row.dart`: non-interactive daily-profit text,
  without a disclosure arrow or popup. The current data contract provides no
  account-profit figures;
  coin-price changes are not used as account returns.
- `widgets/wallet_overview_icon.dart`: matching vector document icons for
  expanding/collapsing asset history and opening transaction records.
- `trend/wallet_asset_trend_panel.dart`: asset-trend display with 40 evenly spaced scrub points;
  no time controls. The selected shortcut is green. Hiding balances also hides the chart contents.
- `widgets/wallet_asset_list.dart`: a flat themed token section with a collapsible
  header, icon-only small-asset filter, name/quantity versus value columns and
  thin themed separators between adjacent tokens.
  Rows retain their coin-record route, stable platform-coin ordering and adaptive
  layout. Quantity uses `bal`, value preserves `fiat` and its currency symbol;
  the single-coin price in `sub` is not shown as a quantity. Unknown valuations
  are never treated as confirmed small balances.
- `widgets/wallet_home_action.dart`: one shared shortcut implementation whose
  Material clips ink to the same rounded shape as its background.
- `../widgets/wallet_coin_logo.dart`: shared currency artwork used directly by
  the asset list; bundled user-provided TRX/USDT artwork,
  with optional platform-coin network artwork and its local fallback.
- `wallet_home_tokens.dart`: home-only layout values and readable brand shades;
  existing wallet tokens/colors remain the source for core theme values.

## Data and compatibility

The production repository uses the authenticated Chat fund balance API.
USDT, TRX and BI99 (displayed as 99) come from its three real balances. Available
units remain exact, including negative rollback balances; frozen units are kept
separately and never added to spendable money. Token quantities display two
decimals, while `availableRaw` and minor units retain operation precision.
Display values remain strings; this view does not calculate balances or rates.
The repository has no annual-yield or spot-earnings values. The reference's yield
badges and sample token values are not injected into the account list, and 24-hour
coin-price changes are not presented as annual returns. CNY/USD overview selection
does not convert individual token estimates without corresponding supplied data.
The production controller defaults to `WalletFundRepository`. No valuation API
is provided, so total assets, token fiat values and profit remain `--`; USD is
absent until a repository actually supplies a valuation. Test unavailable states
explicitly inject `UnavailableWalletRepository`; no sample account values are
injected into production. The user requested no load-failure
banner or retry button. Pull-to-refresh still retries; failed refreshes keep
the last available snapshot without replacing it with zero assets.
The existing subpages remain responsible for their own unavailable/error states.
The historical asset series comes from `/chat/fund/trend`. See the event-driven
trend contract below for fixed 40-slot padding and temporary header inspection.
Deposit opens the independent authenticated deposit-address page, with scoped
pending allocation polling and a real address QR. The old aggregate `/wallet/me`
contract is not used to obtain an address, minimum, quote or password flag.
Withdrawal first opens a type-selection bottom sheet. On-chain withdrawal
selects a coin then starts with the wallet-address tab; internal transfer starts
with contacts. P2P is visible as unavailable until a real trading flow exists.
Existing callers of the withdrawal
picker/address pages retain their friend-transfer default. Per the user's
explicit choice, the action labelled 划转 continues to open currency exchange.

Both the main-tab host's safe-area ownership and standalone navigation are
supported. The main-tab header uses ordinary themed text. Old purely
decorative asset/invite banners and the unsupported asset-protection claim are
not part of this redesigned home. Their bundled resources are left available
for other existing consumers; no asset manifest changes are required.

Balance refresh notifications are scoped to the captured server/account key.
Inactive routes defer a notification until activation, concurrent loads coalesce,
and disposal cancels the subscription. Late data from an old account is rejected.

## Verification

Home UI tests belong in `test/pages/wallet/home/`; existing controller, amount,
navigation and main-tab contracts remain in `test/wallet/`. Test-only repositories
can supply representative balances for rendering without changing production
wiring. Previews use those fixtures, not a live account.

Verified on 2026-10-06: 75 home cases and 16 wallet contract cases passed,
including hidden balances, supplied-currency selection, unknown-profit state,
the three action routes and silent failure with pull-to-refresh retry. Trend
coverage includes inline expansion/collapse, selected periods, privacy and
currency changes, and horizontal period scrolling at 200%/300% text scale.
Daily-profit text remains non-interactive in both themes, including its spoken
semantics; tapping either label or value opens no route or bottom sheet.
Token-list coverage includes raw quantities/valuations, non-interactive column
labels, collapsing while balances are hidden, preserved small-asset filtering,
unknown values and long amounts without truncated digits across five locales.
The contract cases passed during the preceding overview update. Focused
analysis found no issues. Actual light/dark and narrow large-text renders were
inspected, and the Android debug APK build passed. Live wallet account data and
iOS device behavior were not exercised.

## Balance valuation contract

`GET /chat/fund/balances` supplies available/frozen balances for USDT, TRX and BI99 (displayed as 99). CNY is fixed and cannot be switched. Total CNY valuation and USDT row valuation use USDT available × `usdToThisRate`, rounded to two decimals with integer decimal arithmetic. Frozen balances are excluded. TRX/99 valuation remains unknown because this endpoint supplies no prices for them. A missing/null/invalid rate clears valuation to `--` while preserving balances. The rate timestamp is retained in the balance snapshot; no daily change or trend is inferred from it.

The extended balances contract supersedes local USDT-only valuation: total assets use `totalCny`; coin values use `valueCny`/`availableCny`; daily change uses `dailyChange.amountCny` and `percentage` only when status is `ready`. Per-coin changes use `changeAmountCny` and `changePercent`. Values remain decimal strings, percentages are already percent units. All amounts cover available funds only; frozen amounts are retained separately. Missing or invalid display values use 0.00 without changing spendable balances.

Daily change colors follow the validated amount string: positive amounts and their percentage use green; negative amounts use red. Zero (including negative zero), unavailable/invalid values and hidden amounts use the theme's normal text color. Light/dark color shades live in `WalletHomeTokens`; the sign check does not convert amounts to floating point or change their display precision.

## Event-driven CNY trend

The expanded panel loads GET /chat/fund/trend through the existing Chat-token transport with no body or currency query. Trend failures do not fail balance loading. The account-scoped repository rejects late responses after account switches. Reopening, pull-to-refresh and active balance-change refreshes reload the trend, coalescing overlapping requests.

The API retains its actual 0–100 historical records unchanged. The display adapter `trend/wallet_trend_display_points.dart` prepends zero-valued slots so the chart always has exactly 40 equally spaced points. Only the newest 40 records are used, preserving returned order; 20 real records produce 20 leading zero slots followed by those records. A successful empty response produces 40 zero slots, while failed requests retain their error state. These slots belong only to the presentation and never alter account balances, ledger records or stored API data. `currentCny` is not appended as another historical point.

Historical values are used without repricing. Real null-price records remain gaps; they are not zero-padded. Cubic controls stay inside each endpoint rectangle, avoiding artificial peaks. There are no time selectors or timestamp labels.

Touch-down previews the chosen slot in the existing total-assets header. Horizontal drag and long-press scrubbing switch among the 40 slots, sending `HapticFeedback.lightImpact` when the selected slot changes even when both slots have zero value. Moving inside the same slot does not repeat the tick. The cursor snaps to the selected slot. The chart has no separate amount tooltip. Release, pointer cancellation and vertical scrolling clear the preview and restore the latest balance snapshot, rather than the last historical point. Missing historical prices show a missing-price label in the header. Hiding balances, collapsing the chart, deactivating the page, replacing trend data or changing accounts also clear the preview. Actual vibration strength depends on the device and system haptic settings.

Regression coverage is in `test/pages/wallet/home/wallet_event_trend_test.dart`.
