# Platform text fonts

`PlatformTextFonts` centralizes the existing desktop CJK preferences used by the
message body, composer and wallet. Android and iOS leave `fontFamily` and `fontFamilyFallback`
unset, matching the app theme and 99chat's native typography. The browser also
uses available platform fonts: this project does not register a `NotoSansSC`
font asset, so it must not depend on that unregistered family name.

Flutter resolves the primary family, optional fallback families, then system
fallback. System Emoji remain ordinary Unicode text; no Emoji inventory, font
asset, normalization, presentation-selector modification, or image substitution
is involved. Desktop preferences remain unchanged. Native Chinese text keeps
its current system typography, size, weight, and line height.

Font fallback cannot provide glyphs absent from the device, and Dart/Flutter's
Unicode segmentation data may need a runtime update for newly defined rules.
Future Emoji supported by the installed system fonts do not require per-Emoji
business-code changes. Widget tests preserve input sequences and font policy;
they do not prove Android/iOS font coverage or native keyboard behavior.

User text must not force the strut's line height when fallback fonts or combining
marks need larger metrics. Profile signatures reserve the existing minimum
space but allow those metrics to expand. Contact-card public accounts also use
minimum strut metrics rather than forcing the run height. Fixed application
status text keeps its established geometry.

Tests: `test/theme/typography/platform_text_fonts_test.dart` and
`test/pages/contacts/user_profile_panel/identity/user_profile_unicode_test.dart`.

`chat_message_typography.dart` provides the shared message-body style, matching
99chat's `MessageBubbleTextColor.messageBodyBaseStyle`: 16px, w400, height 1.3,
alphabetic baseline and `inherit: false`. Plain text, mentions, reply bodies,
custom Markdown and formatted entities use this style without inheriting a
page's Material font, letter/word spacing or weight. Explicit caller styles and
message formatting remain supported; no fixed strut truncates fallback glyphs.
The rendering comparison in `test/widgets/chat/typography/` checks line boxes
and pixels against an independent reference style under unrelated page themes.

References: [Flutter TextStyle](https://api.flutter.dev/flutter/painting/TextStyle-class.html)
and [Flutter StrutStyle](https://api.flutter.dev/flutter/painting/StrutStyle-class.html).
