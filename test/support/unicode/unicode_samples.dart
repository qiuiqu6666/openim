/// Representative structures, never a production Emoji support list.
const unicodeSamples = <({String name, String text})>[
  (name: 'single supplementary emoji', text: '\u{1F602}'),
  (name: 'emoji presentation VS16', text: '\u2B07\uFE0F'),
  (name: 'text presentation VS15', text: '\u2764\uFE0E'),
  (name: 'ZWJ sequence', text: '\u{1F3F3}\uFE0F\u200D\u{1F308}'),
  (name: 'skin tone modifier', text: '\u{1F44D}\u{1F3FD}'),
  (
    name: 'family',
    text: '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}'
  ),
  (name: 'couple', text: '\u{1F469}\u200D\u2764\uFE0F\u200D\u{1F469}'),
  (name: 'gender', text: '\u{1F3C3}\u{1F3FE}\u200D\u2640\uFE0F'),
  (name: 'profession', text: '\u{1F469}\u{1F3FF}\u200D\u{1F680}'),
  (name: 'regional indicator flag', text: '\u{1F1FA}\u{1F1F3}'),
  (name: 'single regional indicator', text: '\u{1F1FA}'),
  (name: 'keycap', text: '1\uFE0F\u20E3'),
  (
    name: 'tag sequence',
    text: '\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}'
  ),
  (name: 'combining accents', text: 'e\u0301\u0327'),
  (name: 'whitespace base with combining mark', text: ' \u0301'),
  (name: 'supplementary CJK', text: '\u{20000}'),
  (name: 'Indic conjunct', text: '\u0915\u094D\u0937'),
  (name: 'CJK and Latin mixed', text: '中文 A\u0301 \u{1F469}\u200D\u{1F4BB}'),
  (name: 'RTL mixed', text: 'العربية עברית \u{1F44D}\u{1F3FB}'),
  (name: 'multilingual', text: '日本語 한국어 हिन्दी café \u{1F1E8}\u{1F1F3}'),
  (name: 'supplementary raw future value', text: '\u{1FAEA}\uFE0F'),
];
