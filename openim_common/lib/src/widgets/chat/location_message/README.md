# Location messages

`ChatLocationMessageCard` renders the location name, optional address, real map
thumbnail, and existing message time/delivery status. `ChatItemView` owns the
surrounding message actions; the card does not add a second colored bubble.

Tapping opens `ChatLocationDetailPage` inside the app. The map can pan and zoom,
but cannot change the shared coordinate. Recenter returns to that coordinate;
viewing a message does not request the recipient's GPS location.

Android reuses the existing AMap privacy consent gate. Before consent, the card
shows a location placeholder without creating an AMap view. The detail page
offers the existing consent flow. Returning refreshes the thumbnail consent.
Android uses AMap snapshots; iOS retains MapKit with MKMapSnapshotter. Mobile
thumbnail map views are released after capture or timeout. An in-memory cache
retains at most 32 snapshots, keyed by coordinate and theme. Failed snapshots
show a placeholder; no street map or address is fabricated. Desktop retains
the existing map implementation.

Descriptions remain plain text: name followed by an optional newline and
provider address. Legacy single-line and `/////` descriptions are readable.
Raw coordinates remain message data and are not printed in the card.

Validation: location message/picker widget tests cover theme, narrow/large-text
layouts, in-app navigation, read-only points, privacy gating and snapshot
release/cache reuse. Preview tests use a clearly marked local map fixture,
not production map imagery. Android compilation is verified; live map/network
rendering and iOS native execution still require device validation.
