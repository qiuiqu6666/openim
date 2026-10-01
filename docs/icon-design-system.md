# Icon Design System

The conversation screen and primary navigation use the vector icons in
`openim_common/lib/src/widgets/app_icon.dart`. Use `AppIconKind` for the shape
and `AppIconTokens` for size and color. Do not add a raster variant or switch
between filled and outlined icons to represent selection.

| Role | Canvas | Display | Stroke | Color |
| --- | ---: | ---: | ---: | --- |
| Primary navigation | 24 × 24 | 24 dp | 1.8 dp | `secondary` / `selected` |
| Header action | 24 × 24 | 24 dp | 1.8 dp | `primary` |
| Conversation status | 24 × 24 | 16 dp | 1.5 dp | `secondary` |
| Compact status | 24 × 24 | 12 dp | 1.5 dp | semantic status color |

All icons use rounded caps and joins, a flat monochrome outline, optical
centering, and approximately 2 units of clear space on the 24-unit canvas.
The 16 dp status icons are enlarged optically so their glyphs remain legible.

Color tokens: `primary` #0C1C33, `secondary` #8E9AB0, `selected` #0089FF,
`danger` #E45454, `onColor` #FFFFFF, `disabled` #B8C0CE. State is communicated
by both label/shape and color; color alone is not sufficient.

Keep Android interactive areas at least 48 × 48 dp. The visible icon can be
smaller inside that area. Menu actions and swipe actions include visible text;
standalone icon actions need an accessible name. Avatars, unread badges, and
the native loading spinner are content/status components rather than icon
glyphs.

Conversation swipe actions use centered text only. Their labels describe the
next action (for example, "取消置顶" when the conversation is pinned); the
three actions share the same text size and touch area. The pin and slashed
bell glyphs appear only as compact status indicators in the conversation row.
Bottom navigation selection changes stroke color, never fill style.
