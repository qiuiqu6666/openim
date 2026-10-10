# Unicode user text

`unicode_text.dart` owns display and user-visible length boundaries. It uses the
`characters` package's extended grapheme clusters; it never enumerates Emoji,
normalizes text, inserts variation selectors, or converts Unicode into stickers.

- Use `text.characters.length` for a visible-character limit.
- Use `graphemePrefix`/`graphemeSuffix` for display truncation.
- Use `graphemeSafeRange` for search highlights and formatted spans. Supply
  precomputed `graphemeBoundaries` when processing multiple ranges in one string.
- Use `graphemeTrim` only where the product already trims names or display
  summaries. It removes complete whitespace clusters without removing a
  whitespace base carrying a combining mark.
- Use `graphemeCollapseWhitespace` only for derived single-line display. Never
  write a display summary back to message content.
- Save and send user message strings unchanged. `trim().isEmpty` can check
  whether content is blank without assigning the trimmed result to storage.

Flutter selections, IME composing ranges and SDK entity offsets remain UTF-16
offsets. Byte-size guards, documented protocol scalar limits, IDs, numeric
formats and message-list lengths retain their existing units.

Future raw sequences are not filtered by the application. Grapheme rules depend
on the installed `characters`/Flutter versions; glyph coverage and shaping
depend on the device's fonts and engine. Update those foundations when Unicode
changes, rather than adding per-Emoji business rules.
