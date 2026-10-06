import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, copyFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { DEFAULT_ASR_ENV_FILE, loadAsrEnvFile } from '../config-file.mjs';
import { readConfig } from '../server.mjs';

const valid = 'TENCENT_ASR_APP_ID=123\nTENCENT_ASR_SECRET_ID=test-id\nTENCENT_ASR_SECRET_KEY=test-secret\nAUTH_VALIDATE_URL=http://127.0.0.1:10008/internal/validate-session\nAUTH_ALLOW_INSECURE_HTTP=true\n';
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'asr-config-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  return root;
}

test('loads BOM, CRLF, comments and quoted values without expanding them', t => {
  const file = join(fixture(t), 'asr.env');
  writeFileSync(file, '\uFEFF# configuration\r\n' + valid.replaceAll('\n', '\r\n') + 'EXTRA="literal#${VALUE}" # comment\r\n');
  const env = loadAsrEnvFile(file);
  assert.equal(env.EXTRA, 'literal#${VALUE}');
  const config = readConfig(env);
  assert.equal(config.host, '127.0.0.1');
  assert.equal(config.port, 8787);
  assert.equal(DEFAULT_ASR_ENV_FILE.href, new URL('../config/asr.env', import.meta.url).href);
});

test('missing file and malformed entries fail without printing values', t => {
  const file = join(fixture(t), 'asr.env');
  assert.throws(() => loadAsrEnvFile(file), /missing or unreadable/);
  for (const content of ['SECRET=test-private\nSECRET=other', 'SECRET="test-private', 'invalid test-private']) {
    writeFileSync(file, content);
    assert.throws(() => loadAsrEnvFile(file), error => /Invalid/.test(error.message) && !error.message.includes('test-private'));
  }
});

test('Markdown auth links are rejected as configuration URLs', t => {
  const file = join(fixture(t), 'asr.env');
  writeFileSync(file, valid.replace('AUTH_VALIDATE_URL=http://127.0.0.1:10008/internal/validate-session', 'AUTH_VALIDATE_URL=[http://127.0.0.1:10008/internal/validate-session](http://127.0.0.1:10008/internal/validate-session)'));
  assert.throws(() => readConfig(loadAsrEnvFile(file)), /AUTH_VALIDATE_URL/);
});

for (const scenario of ['missing', 'empty', 'override']) {
  test(`CLI configuration ${scenario} uses a required script-relative file without environment credential fallback`, t => {
    const root = fixture(t);
    const proxy = join(root, 'proxy');
    const cwd = join(root, 'other');
    mkdirSync(join(proxy, 'config'), { recursive: true });
    mkdirSync(join(cwd, 'config'), { recursive: true });
    for (const name of ['server.mjs', 'config-file.mjs']) {
      copyFileSync(fileURLToPath(new URL(`../${name}`, import.meta.url)), join(proxy, name));
    }
    writeFileSync(join(cwd, 'config', 'asr.env'), valid);
    if (scenario === 'empty') writeFileSync(join(proxy, 'config', 'asr.env'), '');
    const override = join(root, 'override.env');
    if (scenario === 'override') writeFileSync(override, valid + 'PORT=invalid\n');
    const result = spawnSync(process.execPath, [join(proxy, 'server.mjs')], {
      cwd, encoding: 'utf8', windowsHide: true, timeout: 5000,
      env: { ...process.env, TENCENT_ASR_APP_ID: '123', TENCENT_ASR_SECRET_ID: 'test-id', TENCENT_ASR_SECRET_KEY: 'test-private', AUTH_VALIDATE_URL: 'https://auth.example/validate', ASR_ENV_FILE: scenario === 'override' ? override : '' },
    });
    assert.equal(result.error, undefined);
    assert.equal(result.status, 1);
    assert.match(result.stderr, scenario === 'missing' ? /missing or unreadable/ : scenario === 'empty' ? /TENCENT_ASR_APP_ID/ : /PORT/);
    assert.ok(!result.stderr.includes('test-private'));
    assert.equal(result.stdout, '');
  });
}
