import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';
import test from 'node:test';

// Execute the actual embedded JavaScript with a delayed SDK, without loading
// remote scripts, generating a proof, or sending an SMS.
const file = new URL('../../../../../lib/pages/mine/settings/widgets/aliyun_captcha_html.dart', import.meta.url);
const source = readFileSync(fileURLToPath(file), 'utf8');
const script = source.match(/<script>([\s\S]*?)<\/script>/)[1]
  .replace('${jsonEncode(language)}', JSON.stringify('cn'));

function fixture() {
  const messages = [], timers = [];
  let config, tag;
  const window = {initAliyunCaptcha: value => { config = value; }};
  const context = {
    window,
    CaptchaBridge: {postMessage: raw => messages.push(JSON.parse(raw))},
    setTimeout: (fn, ms) => { timers.push({fn, ms}); },
    document: {createElement: () => ({}), head: {appendChild: value => { tag = value; }}},
  };
  vm.runInNewContext(script, context);
  tag.onload();
  return {
    window, config, messages, tag,
    async tick() {
      for (const timer of timers.splice(0)) timer.fn();
      // Drain both VM and host promise queues, including thenable adoption.
      await new Promise(resolve => setImmediate(resolve));
    },
  };
}

test('slow SDK never reports ready before it provides an instance', async () => {
  const f = fixture();
  await f.tick(); // Any previous fixed 2.1-second callback would run here.
  assert.deepEqual(f.messages, []);
  let shown = 0;
  f.config.getInstance({show() { shown++; }});
  await f.tick();
  assert.equal(shown, 1);
  assert.deepEqual(f.messages, [{type: 'ready'}]);
});

test('opening exceptions report an error instead of a false ready', async () => {
  const f = fixture();
  f.config.getInstance({show() { throw new Error('not ready'); }});
  await f.tick();
  assert.deepEqual(f.messages, [{type: 'error'}]);
});

test('a rejected asynchronous open also reports failure', async () => {
  const f = fixture();
  f.config.getInstance({show() { return Promise.reject(new Error('failed')); }});
  await f.tick();
  assert.deepEqual(f.messages, [{type: 'error'}]);
});

test('invalid instance cannot silently stall', async () => {
  const f = fixture();
  f.config.getInstance(undefined);
  await f.tick();
  assert.deepEqual(f.messages, [{type: 'error'}]);
});

test('resource failure ignores late initialization', async () => {
  const f = fixture();
  f.tag.onerror();
  f.config.onError();
  f.config.getInstance({show() { assert.fail('must not open after failure'); }});
  await f.tick();
  assert.deepEqual(f.messages, [{type: 'error'}]);
});

test('duplicate initialization opens the challenge only once', async () => {
  const f = fixture();
  let shown = 0;
  const instance = {show() { shown++; }};
  f.config.getInstance(instance);
  f.config.getInstance(instance);
  await f.tick();
  assert.equal(shown, 1);
  assert.deepEqual(f.messages, [{type: 'ready'}]);
});

test('proof and backend confirmation still travel through the original bridge', async () => {
  const f = fixture();
  f.config.getInstance({show() {}});
  await f.tick();
  const proof = '  {"proof":"test-only"}  ';
  const pending = f.config.captchaVerifyCallback(proof);
  const message = f.messages.at(-1);
  assert.equal(message.captchaVerifyParam, proof);
  const result = {captchaResult: true, bizResult: true};
  f.window.resolveCaptchaRequest(message.id, result);
  assert.deepEqual(await pending, result);
});
