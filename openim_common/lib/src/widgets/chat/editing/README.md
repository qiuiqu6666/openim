# Composer editing boundary

`chat_text_editing.dart` handles explicit application actions from the Emoji
panel and mention insertion. Flutter/`extended_text_field` and the system IME
continue to own ordinary keyboard editing and composing behavior.

Panel deletion removes whole extended grapheme clusters, including when an
external selection is placed inside a cluster. A selected replacement expands
to whole-cluster boundaries. A collapsed insertion inside a cluster moves to
its end. Cursor positions returned to Flutter retain UTF-16 offset semantics.
After replacement, the returned cursor is aligned against the new text as well:
adjacent regional indicators or other sequences can form a new cluster after an
insertion or deletion.

The helpers preserve all remaining input units and do not normalize Unicode.
They are publicly exported by `openim_common` so the composer does not duplicate
editing logic. Unicode picker catalogs are browsing data only; system keyboard
text, clipboard content and saved favorites are not validated against them.
Custom stickers continue to use their separate assets and message protocol.
