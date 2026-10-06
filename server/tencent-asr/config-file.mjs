import { readFileSync } from 'node:fs';

// Resolve from this module, independent of the service manager's working directory.
export const DEFAULT_ASR_ENV_FILE = new URL('./config/asr.env', import.meta.url);

export function loadAsrEnvFile(file = DEFAULT_ASR_ENV_FILE) {
  let contents;
  try {
    contents = readFileSync(file, 'utf8');
  } catch {
    throw new Error('Required ASR configuration file is missing or unreadable: config/asr.env');
  }
  const values = Object.create(null);
  const lines = contents.replace(/^\uFEFF/, '').split(/\r?\n/);
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index].trim();
    if (!line || line.startsWith('#')) continue;
    const match = /^(?:export\s+)?([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$/.exec(line);
    if (!match || Object.hasOwn(values, match[1]) || line.includes('\0')) {
      // Never include file contents or credential values in configuration errors.
      throw new Error(`Invalid or duplicate ASR configuration entry at line ${index + 1}`);
    }
    const [, key, raw] = match;
    let value = raw;
    if (raw.startsWith('"') || raw.startsWith("'")) {
      const quoted = /^(['"])(.*?)\1(?:\s+#.*)?$/.exec(raw);
      if (!quoted) throw new Error(`Invalid ASR configuration quoting at line ${index + 1}`);
      value = quoted[2];
    } else {
      value = raw.replace(/\s+#.*$/, '').trim();
    }
    values[key] = value;
  }
  // Deliberately do not fall back to credentials in the process environment.
  return values;
}
