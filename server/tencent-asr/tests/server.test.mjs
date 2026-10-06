import assert from 'node:assert/strict';
import { request as httpRequest } from 'node:http';
import { once } from 'node:events';
import test from 'node:test';
import { buildFlashRequest, createAsrProxy, HttpError, readConfig, TRANSCRIBE_PATH } from '../server.mjs';

const authUrl = 'https://business.example.test/validate-session';
const credentials = {
  TENCENT_ASR_APP_ID: '1234567890',
  TENCENT_ASR_SECRET_ID: 'test-secret-id',
  TENCENT_ASR_SECRET_KEY: 'test-secret-key',
  AUTH_VALIDATE_URL: authUrl,
};
const audio = Buffer.from('test audio');
const success = () => ({ code: 0, request_id: 'request-123', audio_duration: 1800, flash_result: [{ channel_id: 0, text: '你好，腾讯云。' }] });
const json = (payload, status = 200) => new Response(JSON.stringify(payload), { status, headers: { 'Content-Type': 'application/json' } });
const publicErrorStatuses = new Map([
  ['BAD_REQUEST', 400], ['BAD_FORMAT', 400], ['BAD_DURATION', 400], ['EMPTY_AUDIO', 400], ['UNKNOWN_PARAM', 400],
  ['AUTH_INVALID_TOKEN', 401], ['PAYLOAD_TOO_LARGE', 413], ['UNSUPPORTED_MEDIA', 415],
  ['NO_SPEECH', 422], ['AUDIO_TOO_LONG', 422], ['RATE_LIMITED', 429], ['UPSTREAM_ERROR', 502],
  ['AUTH_UNAVAILABLE', 503], ['TIMEOUT', 504],
]);
function assertPublicFailure(status, payload) {
  if (status < 400 || [403, 404, 405].includes(status)) return;
  assert.equal(payload.errCode, status, 'HTTP status and errCode must match');
  assert.equal(publicErrorStatuses.get(payload.errorCode), status, 'ASR error must follow the backend public error table');
}
function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function waitForAbort(signal) {
  return new Promise((resolve, reject) => {
    if (signal.aborted) { reject(signal.reason); return; }
    signal.addEventListener('abort', () => reject(signal.reason), { once: true });
  });
}

async function fixture(t, { env = {}, auth = { errCode: 0, data: { userID: 'trusted-user' } }, cloud, authenticate } = {}) {
  const calls = [];
  const configuredAuthUrl = env.AUTH_VALIDATE_URL || authUrl;
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    if (url === configuredAuthUrl) return typeof auth === 'function' ? auth(init) : json(auth);
    assert.equal(new URL(url).hostname, 'asr.cloud.tencent.com', 'only fixed Tencent host may receive audio');
    return cloud ? cloud(init, url) : json(success());
  };
  const server = createAsrProxy({ env: { ...credentials, ...env }, fetchImpl, authenticate, now: () => 1700000000000 });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  });
  const base = `http://127.0.0.1:${server.address().port}`;
  const post = async (options = {}) => {
    const response = await fetch(`${base}${options.path || `${TRANSCRIBE_PATH}?voiceFormat=m4a&duration=1.8`}`, {
      method: options.method || 'POST',
      headers: { token: 'valid-chat-token', 'Content-Type': 'application/octet-stream', ...options.headers },
      body: options.body === undefined ? audio : options.body,
    });
    if (response.status >= 400) assertPublicFailure(response.status, await response.clone().json());
    return response;
  };
  return { server, calls, base, post };
}

function streamPost(url, { chunks, end = true, headers = {} }) {
  return new Promise((resolve, reject) => {
    const request = httpRequest(url, {
      method: 'POST',
      headers: { token: 'valid-chat-token', 'Content-Type': 'application/octet-stream', ...headers },
    }, (response) => {
      const received = [];
      response.on('data', (chunk) => received.push(chunk));
      response.on('end', () => {
        try {
          const body = JSON.parse(Buffer.concat(received).toString());
          assertPublicFailure(response.statusCode, body);
          resolve({ status: response.statusCode, body });
        } catch (error) { reject(error); }
      });
      response.on('error', reject);
    });
    request.on('error', reject);
    for (const chunk of chunks) request.write(chunk);
    if (end) request.end();
  });
}

test('signs Tencent flash request against an independently computed fixed HMAC-SHA1 vector', () => {
  const request = buildFlashRequest(readConfig(credentials), 'm4a', 1700000000);
  assert.equal(request.signText, 'POSTasr.cloud.tencent.com/asr/flash/v1/1234567890?convert_num_mode=1&engine_type=16k_zh&filter_dirty=0&filter_modal=0&filter_punc=0&first_channel_only=1&secretid=test-secret-id&speaker_diarization=0&timestamp=1700000000&voice_format=m4a&word_info=0');
  assert.equal(request.authorization, 'nomt+pBbrKLiKp9JXGFBLkJJCPI=');
  assert.equal(request.url, `https://${request.signText.slice(4)}`);
});

test('refuses startup without credentials or a trusted token validation URL', () => {
  assert.throws(() => readConfig({}), /TENCENT_ASR_APP_ID/);
  assert.throws(() => readConfig({ ...credentials, AUTH_VALIDATE_URL: '' }), /AUTH_VALIDATE_URL is required/);
  assert.throws(() => readConfig({ ...credentials, AUTH_VALIDATE_URL: 'http://business.test/validate' }), /requires HTTPS/);
  assert.throws(() => readConfig({ ...credentials, AUTH_VALIDATE_URL: 'https://user:pass@business.test/validate' }), /requires HTTPS/);
  assert.throws(() => readConfig({ ...credentials, MAX_AUDIO_BYTES: String(100 * 1024 * 1024 + 1) }), /MAX_AUDIO_BYTES/);
});

test('requires an explicit HTTP opt-in for the existing loopback Chat session validator', () => {
  const loopbackUrl = 'http://127.0.0.1:10008/internal/validate-session';
  assert.throws(() => readConfig({ ...credentials, AUTH_VALIDATE_URL: loopbackUrl }), /requires HTTPS/);
  const config = readConfig({ ...credentials, AUTH_VALIDATE_URL: loopbackUrl, AUTH_ALLOW_INSECURE_HTTP: 'true' });
  assert.equal(config.authUrl, loopbackUrl);
  assert.equal(config.host, '127.0.0.1');
  assert.equal(config.port, 8787);
  assert.throws(() => readConfig({ ...credentials, CORS_ALLOWED_ORIGINS: '*' }), /CORS_ALLOWED_ORIGINS/);
});

test('forwards token and an empty JSON body to the existing Chat validator through a mock only', async (t) => {
  const loopbackUrl = 'http://127.0.0.1:10008/internal/validate-session';
  const { post, calls } = await fixture(t, {
    env: { AUTH_VALIDATE_URL: loopbackUrl, AUTH_ALLOW_INSECURE_HTTP: 'true' },
  });
  assert.equal((await post()).status, 200);
  assert.equal(calls[0].url, loopbackUrl);
  assert.equal(calls[0].init.method, 'POST');
  assert.equal(calls[0].init.headers.token, 'valid-chat-token');
  assert.equal(calls[0].init.headers['Content-Type'], 'application/json');
  assert.match(calls[0].init.headers.operationID, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.equal(calls[0].init.body, '{}');
  assert.equal(calls.length, 2);
});

test('authenticates token through the configured business endpoint and forwards only binary audio to Tencent', async (t) => {
  const { post, calls } = await fixture(t);
  const response = await post();
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { errCode: 0, data: { text: '你好，腾讯云。', requestId: 'request-123' } });
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(calls.length, 2);
  assert.equal(calls[0].url, authUrl);
  assert.equal(calls[0].init.headers.token, 'valid-chat-token');
  assert.equal(calls[0].init.body, '{}');
  assert.equal(calls[0].init.redirect, 'error');
  assert.equal(calls[1].init.headers.Authorization, 'nomt+pBbrKLiKp9JXGFBLkJJCPI=');
  assert.equal(calls[1].init.headers['Content-Type'], 'application/octet-stream');
  assert.equal(calls[1].init.headers['Content-Length'], String(audio.length));
  assert.deepEqual(calls[1].init.body, audio);
  assert.equal(calls[1].init.headers.token, undefined);
});

test('missing token never reaches authentication or Tencent', async (t) => {
  const { post, calls } = await fixture(t);
  const response = await post({ headers: { token: '' } });
  assert.equal(response.status, 401);
  assert.equal((await response.json()).errorCode, 'AUTH_INVALID_TOKEN');
  assert.equal(calls.length, 0);
});

for (const [label, payload] of [
  ['failed validation', { errCode: 1, data: { userID: 'forged-user' } }],
  ['missing identity', { errCode: 0, data: {} }],
  ['blank identity', { errCode: 0, data: { userID: '  ' } }],
  ['non-numeric success code', { errCode: '0', data: { userID: 'user' } }],
  ['unexpected token parse envelope', { errCode: 0, data: { tokenInfo: { userID: 'user' } } }],
]) {
  test(`rejects ${label} without recognizing audio`, async (t) => {
    const { post, calls } = await fixture(t, { auth: payload });
    const response = await post();
    assert.equal(response.status, 401);
    assert.equal((await response.json()).errorCode, 'AUTH_INVALID_TOKEN');
    assert.equal(calls.length, 1);
  });
}

test('authentication response error and unavailable validator fail closed without leaking details', async (t) => {
  const { post, calls } = await fixture(t, { auth: () => { throw new Error('test-secret-key valid-chat-token'); } });
  const response = await post();
  assert.equal(response.status, 503);
  const payload = await response.text();
  assert.match(payload, /AUTH_UNAVAILABLE/);
  assert.doesNotMatch(payload, /test-secret-key|valid-chat-token/);
  assert.equal(calls.length, 1);
});

test('a Chat validator HTTP outage is unavailable instead of invalidating the login', async (t) => {
  const { post, calls } = await fixture(t, { auth: () => json({ errCode: 503, errMsg: 'private detail' }, 503) });
  const response = await post();
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), {
    errCode: 503, errMsg: '登录校验服务暂不可用，请稍后重试', errorCode: 'AUTH_UNAVAILABLE', data: null,
  });
  assert.equal(calls.length, 1);
});

test('allows an explicitly injected authenticator to adapt a different trusted backend contract', async (t) => {
  const { post, calls } = await fixture(t, {
    env: { AUTH_VALIDATE_URL: '' },
    authenticate: async (token, { signal }) => {
      assert.equal(token, 'valid-chat-token');
      assert.equal(signal.aborted, false);
      return { userID: 'verified-on-server' };
    },
  });
  assert.equal((await post()).status, 200);
  assert.equal(calls.length, 1);
});

test('injected authenticator must still return a verified nonempty identity', async (t) => {
  const { post, calls } = await fixture(t, { authenticate: async () => ({ token: 'valid-chat-token' }) });
  assert.equal((await post()).status, 401);
  assert.equal(calls.length, 0);
});

for (const [label, options, status, errorCode] of [
  ['unsupported format', { path: `${TRANSCRIBE_PATH}?voiceFormat=flac` }, 400, 'BAD_FORMAT'],
  ['missing format', { path: TRANSCRIBE_PATH }, 400, 'BAD_FORMAT'],
  ['multipart body', { headers: { 'Content-Type': 'multipart/form-data' } }, 415, 'UNSUPPORTED_MEDIA'],
  ['compressed HTTP body', { headers: { 'Content-Encoding': 'gzip' } }, 415, 'UNSUPPORTED_MEDIA'],
  ['empty audio', { body: Buffer.alloc(0) }, 400, 'EMPTY_AUDIO'],
  ['duration over two hours', { path: `${TRANSCRIBE_PATH}?voiceFormat=m4a&duration=7200.1` }, 422, 'AUDIO_TOO_LONG'],
  ['invalid duration', { path: `${TRANSCRIBE_PATH}?voiceFormat=m4a&duration=NaN` }, 400, 'BAD_DURATION'],
  ['zero duration', { path: `${TRANSCRIBE_PATH}?voiceFormat=m4a&duration=0` }, 400, 'BAD_DURATION'],
  ['negative duration', { path: `${TRANSCRIBE_PATH}?voiceFormat=m4a&duration=-1` }, 400, 'BAD_DURATION'],
  ['empty duration', { path: `${TRANSCRIBE_PATH}?voiceFormat=m4a&duration=` }, 400, 'BAD_DURATION'],
  ['external audio URL', { path: `${TRANSCRIBE_PATH}?voiceFormat=m4a&url=https://private.example.test/audio` }, 400, 'UNKNOWN_PARAM'],
  ['client identity', { path: `${TRANSCRIBE_PATH}?voiceFormat=m4a&userID=admin` }, 400, 'UNKNOWN_PARAM'],
  ['duplicate format', { path: `${TRANSCRIBE_PATH}?voiceFormat=m4a&voiceFormat=mp3` }, 400, 'BAD_REQUEST'],
]) {
  test(`rejects ${label} before cloud requests`, async (t) => {
    const { post, calls } = await fixture(t);
    const response = await post(options);
    assert.equal(response.status, status);
    assert.equal((await response.json()).errorCode, errorCode);
    assert.equal(calls.length, 0);
  });
}

test('enforces declared audio byte limit before authentication', async (t) => {
  const { post, calls } = await fixture(t, { env: { MAX_AUDIO_BYTES: '3' } });
  assert.equal((await post({ body: Buffer.from('four') })).status, 413);
  assert.equal(calls.length, 0);
});

test('enforces actual byte limit for chunked uploads without Content-Length', async (t) => {
  const { base, calls } = await fixture(t, { env: { MAX_AUDIO_BYTES: '3' } });
  const response = await streamPost(`${base}${TRANSCRIBE_PATH}?voiceFormat=mp3`, { chunks: ['ab', 'cd'] });
  assert.equal(response.status, 413);
  assert.equal(response.body.errorCode, 'PAYLOAD_TOO_LARGE');
  assert.equal(calls.length, 1);
});

test('does not accept empty chunked uploads', async (t) => {
  const { base, calls } = await fixture(t);
  const response = await streamPost(`${base}${TRANSCRIBE_PATH}?voiceFormat=mp3`, { chunks: [], headers: { 'Transfer-Encoding': 'chunked' } });
  assert.equal(response.status, 400);
  assert.equal(response.body.errorCode, 'EMPTY_AUDIO');
  assert.ok(calls.length <= 1);
});

test('maps Tencent failures and never reflects provider messages or secrets', async (t) => {
  const { post } = await fixture(t, { cloud: () => json({ code: 4002, message: 'test-secret-key valid-chat-token', request_id: 'request-123' }) });
  const response = await post();
  assert.equal(response.status, 502);
  const payload = await response.text();
  assert.match(payload, /UPSTREAM_ERROR/);
  assert.doesNotMatch(payload, /test-secret-key|valid-chat-token/);
});

for (const [label, cloud, status, errorCode] of [
  ['empty recognition text', () => json({ ...success(), flash_result: [{ channel_id: 0, text: ' ' }] }), 422, 'NO_SPEECH'],
  ['audio decode error', () => json({ code: 4007 }), 400, 'BAD_FORMAT'],
  ['provider audio byte limit', () => json({ code: 4011 }), 413, 'PAYLOAD_TOO_LARGE'],
  ['provider empty audio', () => json({ code: 4012 }), 400, 'EMPTY_AUDIO'],
  ['provider concurrency limit', () => json({ code: 4006 }), 429, 'RATE_LIMITED'],
  ['provider timeout', () => json({ code: 4008 }), 504, 'TIMEOUT'],
  ['non-JSON upstream body', () => new Response('error body with test-secret-key'), 502, 'UPSTREAM_ERROR'],
  ['upstream HTTP failure', () => json(success(), 500), 502, 'UPSTREAM_ERROR'],
  ['missing recognition result', () => json({ code: 0, audio_duration: 1000 }), 502, 'UPSTREAM_ERROR'],
  ['actual duration above two hours', () => json({ ...success(), audio_duration: 7200001 }), 422, 'AUDIO_TOO_LONG'],
]) {
  test(`handles ${label}`, async (t) => {
    const { post } = await fixture(t, { cloud });
    const response = await post();
    assert.equal(response.status, status);
    assert.equal((await response.json()).errorCode, errorCode);
  });
}

test('times out and cancels an authentication request', async (t) => {
  let aborted = false;
  const { post, calls } = await fixture(t, {
    env: { AUTH_TIMEOUT_MS: '30' },
    auth: async ({ signal }) => {
      try { await waitForAbort(signal); } finally { aborted = signal.aborted; }
    },
  });
  const response = await post();
  assert.equal(response.status, 504);
  assert.equal((await response.json()).errorCode, 'TIMEOUT');
  assert.equal(aborted, true);
  assert.equal(calls.length, 1);
});

test('bounds the authentication deadline even if an injected adapter ignores cancellation', async (t) => {
  const { post, calls } = await fixture(t, {
    env: { AUTH_TIMEOUT_MS: '30' },
    authenticate: () => new Promise(() => {}),
  });
  const response = await post();
  assert.equal(response.status, 504);
  assert.equal((await response.json()).errorCode, 'TIMEOUT');
  assert.equal(calls.length, 0);
});

test('times out incomplete uploads and never calls Tencent', async (t) => {
  const { base, calls } = await fixture(t, { env: { UPLOAD_TIMEOUT_MS: '30' } });
  const response = await streamPost(`${base}${TRANSCRIBE_PATH}?voiceFormat=mp3`, { chunks: ['partial audio'], end: false });
  assert.equal(response.status, 504);
  assert.equal(response.body.errorCode, 'TIMEOUT');
  assert.equal(calls.length, 1);
});

test('times out and aborts upstream recognition', async (t) => {
  let aborted = false;
  const { post } = await fixture(t, {
    env: { UPSTREAM_TIMEOUT_MS: '30' },
    cloud: async ({ signal }) => {
      try { await waitForAbort(signal); } finally { aborted = signal.aborted; }
    },
  });
  const response = await post();
  assert.equal(response.status, 504);
  assert.equal((await response.json()).errorCode, 'TIMEOUT');
  assert.equal(aborted, true);
});

test('enforces the overall deadline even when the upstream deadline is longer', async (t) => {
  const { post } = await fixture(t, {
    env: { REQUEST_TIMEOUT_MS: '40', UPSTREAM_TIMEOUT_MS: '1000' },
    cloud: ({ signal }) => waitForAbort(signal),
  });
  const response = await post();
  assert.equal(response.status, 504);
  assert.equal((await response.json()).errorCode, 'TIMEOUT');
});

test('limits authenticated users per minute', async (t) => {
  const { post, calls } = await fixture(t, { env: { MAX_USER_REQUESTS_PER_MINUTE: '1' } });
  assert.equal((await post()).status, 200);
  const response = await post();
  assert.equal(response.status, 429);
  assert.equal((await response.json()).errorCode, 'RATE_LIMITED');
  assert.equal(calls.filter((call) => call.url !== authUrl).length, 1);
});

for (const [label, env, errorCode] of [
  ['global concurrency', { MAX_CONCURRENT: '1' }, 'RATE_LIMITED'],
  ['per-user concurrency', { MAX_CONCURRENT: '2', MAX_USER_CONCURRENT: '1' }, 'RATE_LIMITED'],
]) {
  test(`bounds ${label} and releases the slot after completion`, async (t) => {
    const started = deferred();
    const complete = deferred();
    let first = true;
    const { post } = await fixture(t, {
      env,
      cloud: async () => {
        if (first) { first = false; started.resolve(); await complete.promise; }
        return json(success());
      },
    });
    const pending = post();
    await started.promise;
    const busy = await post();
    assert.equal(busy.status, 429);
    assert.equal((await busy.json()).errorCode, errorCode);
    complete.resolve();
    assert.equal((await pending).status, 200);
    assert.equal((await post()).status, 200);
  });
}

test('client disconnect aborts upstream recognition and frees concurrency', async (t) => {
  const started = deferred();
  const cancelled = deferred();
  let first = true;
  const { base, post } = await fixture(t, {
    env: { MAX_CONCURRENT: '1' },
    cloud: async ({ signal }) => {
      if (!first) return json(success());
      first = false;
      started.resolve();
      try { await waitForAbort(signal); } finally { cancelled.resolve(signal.aborted); }
    },
  });
  const request = httpRequest(`${base}${TRANSCRIBE_PATH}?voiceFormat=m4a`, {
    method: 'POST', headers: { token: 'valid-chat-token', 'Content-Type': 'application/octet-stream' },
  });
  request.on('error', () => {});
  request.end(audio);
  await started.promise;
  request.destroy();
  assert.equal(await cancelled.promise, true);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal((await post()).status, 200);
});

test('only explicitly configured browser origins can use preflight', async (t) => {
  const { base, post, calls } = await fixture(t, { env: { CORS_ALLOWED_ORIGINS: 'https://chat.example.test' } });
  const blocked = await post({ headers: { Origin: 'https://untrusted.example.test' } });
  assert.equal(blocked.status, 403);
  const allowed = await fetch(`${base}${TRANSCRIBE_PATH}`, { method: 'OPTIONS', headers: { Origin: 'https://chat.example.test' } });
  assert.equal(allowed.status, 204);
  assert.equal(allowed.headers.get('access-control-allow-origin'), 'https://chat.example.test');
  assert.match(allowed.headers.get('access-control-allow-headers'), /operationID/);
  assert.equal(calls.length, 0);
});

test('authenticator can explicitly report an invalid token without exposing internal details', async (t) => {
  const { post } = await fixture(t, { authenticate: async () => { throw new HttpError(401, 'AUTH_INVALID_TOKEN', '登录已失效，请重新登录'); } });
  assert.equal((await post()).status, 401);
});

test('normalizes unexpected adapter failures without exposing tokens, secrets, or unsafe request IDs', async (t) => {
  const { post } = await fixture(t, {
    authenticate: async () => { throw new HttpError(500, 'PRIVATE_BACKEND_ERROR', 'test-secret-key valid-chat-token', 'https://private.test/token'); },
  });
  const response = await post();
  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), {
    errCode: 502, errMsg: '语音识别服务暂时不可用，请稍后重试', errorCode: 'UPSTREAM_ERROR', data: null,
  });
});

test('returns the agreed empty-speech error envelope with the provider request ID', async (t) => {
  const { post } = await fixture(t, { cloud: () => json({ ...success(), flash_result: [{ channel_id: 0, text: '' }] }) });
  const response = await post();
  assert.equal(response.status, 422);
  assert.deepEqual(await response.json(), {
    errCode: 422, errMsg: '未识别到文字，请确认音频中包含清晰语音', errorCode: 'NO_SPEECH', data: { requestId: 'request-123' },
  });
});
