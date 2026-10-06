# Wallet records

This module presents wallet balance changes using the supplied history-page
reference. It preserves the existing record DTO, repository boundary and detail
route. Production uses the authenticated cursor-based
`GET /chat/fund/journals` ledger. Presentation, pagination and filtering are
maintained in separate files.

## Ownership and files

- `wallet_record_screen.dart`: public route, optional initial coin and repository
  injection, request lifecycle, refresh/retry, direction and month selection,
  and detail navigation.
- `wallet_record_models.dart`: existing record types, statuses and DTO fields;
  transaction-type classifications remain shared with the detail page.
- `wallet_record_tokens.dart`: record-specific dimensions and readable colors,
  using the existing wallet theme for shared surfaces and text.
- `filters/wallet_record_filters.dart`: immutable `WalletRecordSelection`, coin
  normalization, direction/type/date matching, shared timestamp parsing and
  immutable calendar-month groups. The screen keeps its compatibility export
  of `walletRecordNormalizeCoin` for existing callers.
- `filters/wallet_record_filter_sheet.dart`: local coin/type/date draft with
  explicit confirmation and reset. The sheet scrolls, respects safe areas and
  adapts its options and actions to narrow screens and large text.
- `widgets/wallet_record_direction_tabs.dart`: All, Expenses and Income controls,
  with selected-state semantics and the existing themed tab indicator.
- `widgets/wallet_record_month_section.dart`: month picker, themed record surface
  and separators between adjacent records.
- `wallet_record_amount.dart`: exact original-currency journal display, plus the
  legacy two-decimal formatter; large values never pass through floating point.
- `widgets/wallet_record_amount_text.dart`: optional invisible digit wrap points
  for long numbers, with the complete formatted value retained for semantics.
- `widgets/wallet_record_row.dart`: formatted amount strings, timestamp and status,
  existing avatar/product-image fallbacks, unknown historical balance and
  responsive row layout. Long values can wrap or move below the identity rather
  than losing monetary digits.
- `wallet_record_detail_screen.dart`: existing record details, opened through
  `openWalletPage`; detail behavior and wallet back-navigation remain intact.

`journals/wallet_journal_controller.dart` owns one head and one next-page future.
Refresh/retry calls coalesce, requests have a six-second timeout, and results are
checked against the filter generation and login session. Refresh and pagination
failures retain loaded records and permit retry. Closing the page invalidates
pending results. `journals/widgets/wallet_journal_list.dart` builds individual rows
lazily. Existing injected repositories without `WalletJournalSource` retain the
legacy local record path for compatibility.

## Filters and calendar grouping

The default view includes all directions and all dates. A caller-supplied
`initialCoin` keeps its existing coin filter; otherwise all coins are included.
Coin matching trims and normalizes case, with `99` and `元` sharing the platform
coin identity; the API receives `BI99`. Switching direction retains other
selected conditions and clears any advanced direction override.

Production filters cover the contract's business types, event types, currency,
five asset directions and calendar ranges. Filtering sends a fresh server query
and clears the cursor. Next pages retain identical filters and use only
`nextCursor`; no total, page, pageSize or offset is invented. The
sheet edits an immutable draft: canceling commits nothing, confirming applies
it, and resetting clears coin, type, date preset and month while preserving
direction. Choosing a date preset clears a previous month restriction. Choosing
a month clears the date preset; selecting all months clears both date conditions.

Records are sorted by their actual local timestamp, newest first, then grouped
by **year and month**. Group keys use `yyyy-MM`; an `unknown` group follows all
dated groups. Equal timestamps and unknown timestamps preserve source input
order. The grouping function does not mutate the original records.

Date presets use a half-open range ending at tomorrow's local midnight, so the
last fractional second of today remains included. A week includes today and
the preceding six calendar days. Month/year shifts clamp the day to the target
month's final day instead of overflowing into another month. All dates has no
arbitrary year cutoff. Records with unknown timestamps remain visible only
when no date or month restriction is selected.

Journal `createdAt` is always Unix milliseconds, including epoch zero and dates
before 2001. It is converted to device local time for grouping and display. The
legacy path retains `parseWalletApiTimeToLocal` for its older timestamp forms.

## Production data boundary

`createWalletRepository()` returns `WalletFundRepository`, implementing
`WalletJournalSource`. Requests reuse the wallet Chat API address, `token` and a
unique `operationID`; they never send userID. The server determines the current
login user. Rows are deduplicated by journal `id`, preserving distinct events
with the same orderID and server ordering for equal timestamps. The obsolete
100-deposit limitation notice is suppressed on this production path. Existing
deposit and withdrawal routes use journal business filters.

Journal rows and details display `afterAvailable` when provided. Null historical
balances display `--`; current account balances never reconstruct history.

Amounts remain backend strings. Journal USDT/TRX retain up to six decimals and
BI99 up to two, without floating point or conversion to today's RMB price.
Income and expense use `assetDelta`; withdrawal application/return and packet
send/return events retain their original ledger direction and operation amount.
Their rows and compact receipts use business titles without freeze/unfreeze
labels or balance movement explanations. No events are dropped or merged, and
these events do not become duplicated expenses or fabricated refund income.
The DTO retains available/frozen/asset deltas and historical balances; the compact
receipt shows the transaction type, original amount, time, ID, address and remark,
with the existing link to the real order. Current order status cannot rewrite
the posted event.
Counterparty IM userID is not presented as an account. Test fixtures and preview account values
stay in the test tree and are never injected into production wiring. The
headset action opens the application's real customer-service sheet; it does
not create a replacement support flow.

Packet sent/received titles identify normal, lucky and exclusive packets.
Packet return events display `Red packet returned`; withdrawal application and
return events display `Withdrawal request` / `Withdrawal returned`, even when
the server title contains a freeze annotation. The receipt transaction type
uses the same business label. These presentation labels support all five app
languages; other ledger business types retain their existing explanations.
Settlement events retain their own meaning. Transfer titles use `Transfer-<public nickname>` resolved
through the existing batched OpenIM user-profile method. Profile lookup does not
block journal paging, shares names across pages in the current query generation,
and rejects stale session/filter results. Missing profiles fall back to the
generic transfer title. Open details observe the same records for late nicknames.
See `journals/wallet_journal_counterparty_source.dart` and the matching controller,
source, title and actual-screen tests under `test/pages/wallet/record/journals/`.

Record-refresh notifications use the captured server/account key, defer while a
route is covered or the app is backgrounded, and coalesce with an active request.
Old-account responses are rejected and subscriptions are canceled on disposal.

Both light and dark themes are supported through the shared wallet colors.
Month groups, direction controls, filter selections and row buttons keep
accessible names/selected states and minimum tap areas. Screen request ownership
is independent of responsive layout changes; filter changes own a new generation.

## Verification

2026-10-06 business label follow-up: withdrawal and packet rows/receipts no longer
show freeze/unfreeze text or balance-state explanation paragraphs. Existing
posted events, amount signs, asset-delta accounting, cursor paging and real-order
links remain intact. The journals module plus wallet API/repository and FundApi
regressions passed 224 tests; 14 optional preview tests were skipped in that run.
The changed presentation and tests passed scoped analysis, and Android debug
APK construction succeeded. Real widget previews cover all five locales and
both themes with test-only data. Physical-device and live-account verification
have not been performed.

Tests are organized under `test/pages/wallet/record/`:

- `journals/`: API headers/query/page parsing, exact-decimal ledger rules,
  presentation, controller races and cursor failures, and full screen paging
  with 300 entries across 15 pages. Optional journal previews use
  `WALLET_JOURNAL_PREVIEW_DIR` and test fixtures.

- `filters/wallet_record_filters_test.dart`: 14 filter/time/grouping cases.
- `wallet_record_screen_test.dart`: 8 screen and navigation cases.
- `wallet_record_state_test.dart`: 8 request, lifecycle and filter-state cases.
- `wallet_record_layout_test.dart`: 12 layout, theme and monetary-precision cases.
- `filters/wallet_record_filter_sheet_test.dart`: 10 confirmation, cancellation,
  reset, locale and narrow large-text filter interactions.
- `wallet_record_amount_test.dart`: 7 exact decimal rounding and unknown-value
  cases, including values larger than floating-point integers can preserve.
- `wallet_record_detail_amount_test.dart`: 12 actual-route cases for two-decimal
  display, rounding, unchanged DTO values and long amounts in both coin types
  and themes.
- `wallet_record_preview_test.dart`: 6 optional actual-widget preview exports;
  enable them with the `WALLET_RECORD_PREVIEW_DIR` Dart define. These exports use
  test-only records, including empty and narrow large-text states.

Verified on 2026-10-06: 193 combined record and relevant API/repository/FundApi
cases passed; six legacy optional preview exports were skipped. Focused analysis
of this module, its data transport and the corresponding tests found no issues.
The Android debug APK build passed. See
`docs/wallet-fund-journals-integration-2026-10-06.md` for integration details.
Live wallet account data and iOS device behavior remain unverified.

Journal details now use the supplied receipt reference: a single themed round
card with the counterparty avatar, event title, exact original-currency amount
and compact, left-aligned fields. Transfer profile enrichment obtains nickname
and faceURL in the same existing SDK batch; missing artwork falls back to a
nickname avatar. The SDK does not expose the public account here, so the main
row says “对方用户” and uses the real nickname. Internal user IDs stay in “更多明细”.

The current compact card shows the event time, direction, counterparty,
transaction ID and remark. Per the user's follow-up, payment method,
description, balance and the “更多明细” expander are absent. Ledger data remains
available to the models without being rendered in this receipt. The associated
bill link loads `GET /chat/fund/orders/:orderID` through WalletFundApi and shows
the actual order amount; it never substitutes the journal operation amount.
Its read-only screen guards late replies, retry coalescing and login changes.
Detail widgets and tokens live in `journals/detail/`; navigation remains in
WalletRecordDetailScreen.

Transfer journal rows now show the same real counterparty faceURL as the
receipt, including group transfers with an identified recipient/sender. Missing
or failed images use the nickname's first grapheme in a circular placeholder.
Profile updates refresh both the list and an already-open detail route without
additional SDK requests. Other event icons and legacy history avatars retain
their existing rules. `journals/widgets/wallet_journal_header.dart` owns the
journal title. The current shared history contract uses “历史记录” or the
selected currency's change title, without filters, support actions or a filter
summary. Direction tabs, month selection and cursor pagination remain active.

Run the focused journal suite from the application root with
`flutter test test/pages/wallet/record/journals/`. Set
`WALLET_JOURNAL_PREVIEW_DIR` and `WALLET_JOURNAL_DETAIL_PREVIEW_DIR` to local
output directories to include the current journal list and receipt previews.
