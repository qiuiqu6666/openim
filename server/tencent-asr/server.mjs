import { createHmac, randomUUID } from 'node:crypto';
import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';
import { loadAsrEnvFile } from './config-file.mjs';

export const TRANSCRIBE_PATH = '/chat/asr/transcribe';
export const MAX_AUDIO_BYTES = 100 * 1024 * 1024;
export const MAX_AUDIO_SECONDS = 2 * 60 * 60;
const FORMATS = new Set(['wav', 'pcm', 'ogg-opus', 'speex', 'silk', 'mp3', 'm4a', 'aac', 'amr']);
const TENCENT_HOST = 'asr.cloud.tencent.com';

const PUBLIC_ERRORS = {
  BAD_REQUEST: [400, '请求参数或音频数据无效'],
  BAD_FORMAT: [400, '音频格式或内容无法识别，请更换文件'],
  BAD_DURATION: [400, '音频时长必须为正数（单位：秒）'],
  EMPTY_AUDIO: [400, '音频数据不能为空'],
  UNKNOWN_PARAM: [400, '仅支持 voiceFormat 和 duration 参数'],
  AUTH_INVALID_TOKEN: [401, '登录已失效，请重新登录'],
  PAYLOAD_TOO_LARGE: [413, '音频文件不能超过 100 MiB 或服务端设置的更小上限'],
  UNSUPPORTED_MEDIA: [415, '请上传未压缩的原始音频二进制数据'],
  NO_SPEECH: [422, '未识别到文字，请确认音频中包含清晰语音'],
  AUDIO_TOO_LONG: [422, '音频时长不能超过 2 小时'],
  RATE_LIMITED: [429, '转文字请求过于频繁，请稍后重试'],
  UPSTREAM_ERROR: [502, '语音识别服务暂时不可用，请稍后重试'],
  AUTH_UNAVAILABLE: [503, '登录校验服务暂不可用，请稍后重试'],
  TIMEOUT: [504, '请求超时，请稍后重试'],
};
const PUBLIC_ERROR_ALIASES = {
  AUTH_REQUIRED: 'AUTH_INVALID_TOKEN',
  AUDIO_TOO_LARGE: 'PAYLOAD_TOO_LARGE',
  AUDIO_DECODE_FAILED: 'BAD_FORMAT',
  UNSUPPORTED_AUDIO_FORMAT: 'BAD_FORMAT',
  INVALID_DURATION: 'BAD_DURATION',
  INVALID_CONTENT_TYPE: 'UNSUPPORTED_MEDIA',
  INVALID_CONTENT_ENCODING: 'UNSUPPORTED_MEDIA',
};
const DEFAULT_ERROR_CODES = {
  400: 'BAD_REQUEST', 401: 'AUTH_INVALID_TOKEN', 413: 'PAYLOAD_TOO_LARGE',
  415: 'UNSUPPORTED_MEDIA', 429: 'RATE_LIMITED', 502: 'UPSTREAM_ERROR',
  503: 'AUTH_UNAVAILABLE', 504: 'TIMEOUT',
};
const ROUTING_ERRORS = {
  ORIGIN_NOT_ALLOWED: [403, '此来源未获授权'],
  NOT_FOUND: [404, '接口不存在'],
  METHOD_NOT_ALLOWED: [405, '请使用 POST 请求'],
};

export class HttpError extends Error {
  constructor(status, code, message, requestId = '') {
    super(message);
    this.status = status;
    this.code = code;
    this.requestId = requestId;
  }
}

// Keep detailed internal errors private and expose only the agreed client contract.
function publicError(error) {
  const known = error instanceof HttpError ? error : null;
  const code = known && ((Object.hasOwn(PUBLIC_ERROR_ALIASES, known.code) ? PUBLIC_ERROR_ALIASES[known.code] : null) ||
    (Object.hasOwn(PUBLIC_ERRORS, known.code) ? known.code : DEFAULT_ERROR_CODES[known.status]));
  const definition = (Object.hasOwn(PUBLIC_ERRORS, code) ? PUBLIC_ERRORS[code] : null) ||
    (known && Object.hasOwn(ROUTING_ERRORS, known.code) ? ROUTING_ERRORS[known.code] : null);
  const [status, message] = definition || PUBLIC_ERRORS.UPSTREAM_ERROR;
  return new HttpError(status, definition ? (PUBLIC_ERRORS[code] ? code : known.code) : 'UPSTREAM_ERROR',
    message, safeRequestId(known?.requestId));
}

function required(env, key) {
  const value = env[key]?.trim();
  if (!value || /[\r\n]/.test(value)) throw new Error(`Missing or invalid ${key}`);
  return value;
}

function integer(env, key, fallback, min, max) {
  const value = env[key] === undefined || env[key] === '' ? fallback : Number(env[key]);
  if (!Number.isSafeInteger(value) || value < min || value > max) {
    throw new Error(`${key} must be an integer between ${min} and ${max}`);
  }
  return value;
}

export function readConfig(env = process.env, { hasCustomAuthenticate = false } = {}) {
  const appId = required(env, 'TENCENT_ASR_APP_ID');
  if (!/^\d+$/.test(appId)) throw new Error('TENCENT_ASR_APP_ID must contain only digits');
  const authUrl = env.AUTH_VALIDATE_URL?.trim() || '';
  if (!authUrl && !hasCustomAuthenticate) {
    throw new Error('AUTH_VALIDATE_URL is required; configure trusted token validation before starting');
  }
  if (authUrl) {
    let url;
    try { url = new URL(authUrl); } catch { throw new Error('AUTH_VALIDATE_URL must be an absolute URL'); }
    if (url.username || url.password || url.hash ||
        (url.protocol !== 'https:' && !(url.protocol === 'http:' && env.AUTH_ALLOW_INSECURE_HTTP === 'true'))) {
      throw new Error('AUTH_VALIDATE_URL requires HTTPS (explicit AUTH_ALLOW_INSECURE_HTTP=true for trusted internal HTTP)');
    }
  }
  const engineType = env.TENCENT_ASR_ENGINE_TYPE?.trim() || '16k_zh';
  if (!/^[a-zA-Z0-9_-]+$/.test(engineType)) throw new Error('Invalid TENCENT_ASR_ENGINE_TYPE');
  const corsOrigins = (env.CORS_ALLOWED_ORIGINS || '').split(',').map((value) => value.trim()).filter(Boolean);
  for (const origin of corsOrigins) {
    let url;
    try { url = new URL(origin); } catch { throw new Error('Invalid CORS_ALLOWED_ORIGINS'); }
    if (!['http:', 'https:'].includes(url.protocol) || url.origin !== origin) throw new Error('Invalid CORS_ALLOWED_ORIGINS');
  }
  return Object.freeze({
    appId,
    secretId: required(env, 'TENCENT_ASR_SECRET_ID'),
    secretKey: required(env, 'TENCENT_ASR_SECRET_KEY'),
    engineType,
    authUrl,
    host: env.HOST || '127.0.0.1',
    port: integer(env, 'PORT', 8787, 1, 65535),
    maxAudioBytes: integer(env, 'MAX_AUDIO_BYTES', MAX_AUDIO_BYTES, 1, MAX_AUDIO_BYTES),
    maxConcurrent: integer(env, 'MAX_CONCURRENT', 2, 1, 20),
    maxUserConcurrent: integer(env, 'MAX_USER_CONCURRENT', 1, 1, 20),
    maxUserRequestsPerMinute: integer(env, 'MAX_USER_REQUESTS_PER_MINUTE', 10, 1, 1000),
    maxTrackedUsers: integer(env, 'MAX_TRACKED_USERS', 5000, 1, 100000),
    authTimeoutMs: integer(env, 'AUTH_TIMEOUT_MS', 5000, 1, 60000),
    uploadTimeoutMs: integer(env, 'UPLOAD_TIMEOUT_MS', 60000, 1, 600000),
    upstreamTimeoutMs: integer(env, 'UPSTREAM_TIMEOUT_MS', 120000, 1, 600000),
    requestTimeoutMs: integer(env, 'REQUEST_TIMEOUT_MS', 180000, 1, 900000),
    corsOrigins: new Set(corsOrigins),
  });
}

// Tencent's flash API uses this HMAC-SHA1 protocol, not cloud API TC3.
export function buildFlashRequest(config, voiceFormat, timestamp = Math.floor(Date.now() / 1000)) {
  const params = {
    convert_num_mode: 1,
    engine_type: config.engineType,
    filter_dirty: 0,
    filter_modal: 0,
    filter_punc: 0,
    first_channel_only: 1,
    secretid: config.secretId,
    speaker_diarization: 0,
    timestamp,
    voice_format: voiceFormat,
    word_info: 0,
  };
  const entries = Object.entries(params).sort(([a], [b]) => a.localeCompare(b, 'en'));
  const path = `/asr/flash/v1/${config.appId}`;
  const query = entries.map(([key, value]) => `${key}=${value}`).join('&');
  const signText = `POST${TENCENT_HOST}${path}?${query}`;
  const authorization = createHmac('sha1', config.secretKey).update(signText).digest('base64');
  // Sign original values, then encode the transport URL, as in the official SDK.
  const encodedQuery = entries.map(([key, value]) => `${key}=${encodeURIComponent(value)}`).join('&');
  return { url: `https://${TENCENT_HOST}${path}?${encodedQuery}`, authorization, signText };
}

async function readJsonResponse(response, maxBytes) {
  if (!response.body) throw new Error('Empty upstream response');
  const reader = response.body.getReader();
  const chunks = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maxBytes) throw new Error('Upstream response too large');
      chunks.push(Buffer.from(value));
    }
    return JSON.parse(Buffer.concat(chunks, length).toString('utf8'));
  } catch (error) {
    await reader.cancel().catch(() => {});
    throw error;
  } finally {
    reader.releaseLock();
  }
}

async function withDeadline(parentSignal, timeoutMs, code, work) {
  const deadline = new AbortController();
  const timer = setTimeout(() => deadline.abort(new HttpError(504, code, '请求超时，请稍后重试')), timeoutMs);
  timer.unref();
  const signal = AbortSignal.any([parentSignal, deadline.signal]);
  let onAbort;
  const cancelled = new Promise((resolve, reject) => {
    onAbort = () => reject(signal.reason);
    if (signal.aborted) onAbort();
    else signal.addEventListener('abort', onAbort, { once: true });
  });
  try {
    return await Promise.race([
      cancelled,
      Promise.resolve().then(() => {
        if (signal.aborted) throw signal.reason;
        return work(signal);
      }),
    ]);
  } catch (error) {
    if (parentSignal.aborted) throw parentSignal.reason;
    if (deadline.signal.aborted) throw deadline.signal.reason;
    throw error;
  } finally {
    clearTimeout(timer);
    signal.removeEventListener('abort', onAbort);
  }
}

// Contract: trusted backend derives userID from the token; the client never supplies it.
export function createTokenAuthenticator({ url, fetchImpl = fetch, timeoutMs = 5000 }) {
  return async (token, { signal }) => withDeadline(signal, timeoutMs, 'AUTH_TIMEOUT', async (authSignal) => {
    let response;
    let payload;
    try {
      response = await fetchImpl(url, {
        method: 'POST',
        headers: { token, 'Content-Type': 'application/json', operationID: randomUUID() },
        body: '{}',
        redirect: 'error',
        signal: authSignal,
      });
      payload = await readJsonResponse(response, 64 * 1024);
    } catch (error) {
      if (authSignal.aborted) throw error;
      throw new HttpError(503, 'AUTH_UNAVAILABLE', '登录校验服务暂不可用，请稍后重试');
    }
    if (response.status >= 500) {
      throw new HttpError(503, 'AUTH_UNAVAILABLE', '登录校验服务暂不可用，请稍后重试');
    }
    if (!response.ok || payload?.errCode !== 0 || !validIdentity(payload?.data)) {
      throw new HttpError(401, 'AUTH_INVALID_TOKEN', '登录已失效，请重新登录');
    }
    return { userID: payload.data.userID.trim() };
  });
}

function validIdentity(identity) {
  return typeof identity?.userID === 'string' && identity.userID.trim().length > 0 && identity.userID.length <= 256;
}

function readAudio(request, maxBytes, signal) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let length = 0;
    const cleanup = () => {
      request.off('data', onData);
      request.off('end', onEnd);
      request.off('error', onError);
      request.off('aborted', onAborted);
      signal.removeEventListener('abort', onSignal);
    };
    const fail = (error) => { cleanup(); request.pause(); reject(error); };
    const onData = (chunk) => {
      length += chunk.length;
      if (length > maxBytes) { fail(new HttpError(413, 'AUDIO_TOO_LARGE', '音频文件不能超过 100 MB 或服务端设置的更小上限')); return; }
      chunks.push(chunk);
    };
    const onEnd = () => {
      cleanup();
      if (length === 0) reject(new HttpError(400, 'EMPTY_AUDIO', '音频数据不能为空'));
      else resolve(Buffer.concat(chunks, length));
    };
    const onError = () => fail(new HttpError(400, 'AUDIO_UPLOAD_FAILED', '音频上传中断，请重试'));
    const onAborted = () => fail(new HttpError(400, 'AUDIO_UPLOAD_FAILED', '音频上传中断，请重试'));
    const onSignal = () => fail(signal.reason);
    if (signal.aborted) { fail(signal.reason); return; }
    request.on('data', onData);
    request.on('end', onEnd);
    request.on('error', onError);
    request.on('aborted', onAborted);
    signal.addEventListener('abort', onSignal, { once: true });
  });
}

function safeRequestId(value) {
  return typeof value === 'string' && /^[a-zA-Z0-9-]{1,128}$/.test(value) ? value : '';
}

function providerError(code, requestId) {
  if (code === 4007) return new HttpError(400, 'AUDIO_DECODE_FAILED', '音频格式或内容无法识别，请更换文件', requestId);
  if (code === 4011) return new HttpError(413, 'AUDIO_TOO_LARGE', '音频文件超过识别限制', requestId);
  if (code === 4012) return new HttpError(400, 'EMPTY_AUDIO', '音频数据不能为空', requestId);
  if (code === 4006) return new HttpError(429, 'ASR_BUSY', '语音识别服务繁忙，请稍后重试', requestId);
  if ([4008, 5003].includes(code)) return new HttpError(504, 'ASR_TIMEOUT', '语音识别超时，请稍后重试', requestId);
  if ([4002, 4003].includes(code)) return new HttpError(502, 'ASR_CONFIGURATION_ERROR', '语音识别服务配置异常，请联系管理员', requestId);
  if ([4004, 4005].includes(code)) return new HttpError(502, 'ASR_UNAVAILABLE', '语音识别服务暂不可用，请联系管理员', requestId);
  return new HttpError(502, 'ASR_FAILED', '语音识别失败，请稍后重试', requestId);
}

async function transcribe(config, audio, voiceFormat, signal, fetchImpl, now) {
  return withDeadline(signal, config.upstreamTimeoutMs, 'ASR_TIMEOUT', async (upstreamSignal) => {
    const request = buildFlashRequest(config, voiceFormat, Math.floor(now() / 1000));
    let response;
    let payload;
    try {
      response = await fetchImpl(request.url, {
        method: 'POST',
        headers: {
          Host: TENCENT_HOST,
          Authorization: request.authorization,
          'Content-Type': 'application/octet-stream',
          'Content-Length': String(audio.length),
        },
        body: audio,
        redirect: 'error',
        signal: upstreamSignal,
      });
      payload = await readJsonResponse(response, 2 * 1024 * 1024);
    } catch (error) {
      if (upstreamSignal.aborted) throw error;
      throw new HttpError(502, 'ASR_UPSTREAM_ERROR', '语音识别服务响应异常，请稍后重试');
    }
    const requestId = safeRequestId(payload?.request_id);
    if (!response.ok) throw new HttpError(502, 'ASR_UPSTREAM_ERROR', '语音识别服务响应异常，请稍后重试', requestId);
    if (payload?.code !== 0) throw providerError(payload?.code, requestId);
    if (typeof payload.audio_duration !== 'number' || !Number.isFinite(payload.audio_duration) || payload.audio_duration < 0) {
      throw new HttpError(502, 'ASR_INVALID_RESPONSE', '语音识别服务响应异常，请稍后重试', requestId);
    }
    if (payload.audio_duration > MAX_AUDIO_SECONDS * 1000) {
      throw new HttpError(422, 'AUDIO_TOO_LONG', '音频时长不能超过 2 小时', requestId);
    }
    const results = payload.flash_result;
    if (!Array.isArray(results) || results.length === 0) throw new HttpError(502, 'ASR_INVALID_RESPONSE', '语音识别服务响应异常，请稍后重试', requestId);
    const channel = results.find((result) => result?.channel_id === 0) || results[0];
    if (typeof channel?.text !== 'string') throw new HttpError(502, 'ASR_INVALID_RESPONSE', '语音识别服务响应异常，请稍后重试', requestId);
    const text = channel.text.trim();
    if (!text) throw new HttpError(422, 'NO_SPEECH', '未识别到文字，请确认音频中包含清晰语音', requestId);
    return { text, requestId };
  });
}

function parseAudioRequest(request, url, config) {
  for (const key of url.searchParams.keys()) {
    if (!['voiceFormat', 'duration'].includes(key)) throw new HttpError(400, 'UNKNOWN_PARAM', '仅支持 voiceFormat 和 duration 参数');
    if (url.searchParams.getAll(key).length !== 1) throw new HttpError(400, 'BAD_REQUEST', '查询参数不能重复');
  }
  const voiceFormat = url.searchParams.get('voiceFormat')?.toLowerCase();
  if (!FORMATS.has(voiceFormat)) throw new HttpError(400, 'UNSUPPORTED_AUDIO_FORMAT', '不支持此音频格式');
  const duration = url.searchParams.get('duration');
  if (duration !== null) {
    const seconds = Number(duration);
    if (duration.trim() === '' || !Number.isFinite(seconds) || seconds <= 0) throw new HttpError(400, 'INVALID_DURATION', '音频时长必须为正数（单位：秒）');
    if (seconds > MAX_AUDIO_SECONDS) throw new HttpError(422, 'AUDIO_TOO_LONG', '音频时长不能超过 2 小时');
  }
  const contentType = String(request.headers['content-type'] || '').split(';')[0].trim().toLowerCase();
  if (contentType !== 'application/octet-stream') throw new HttpError(415, 'INVALID_CONTENT_TYPE', '请上传原始音频二进制数据');
  if (request.headers['content-encoding'] && request.headers['content-encoding'] !== 'identity') {
    throw new HttpError(415, 'INVALID_CONTENT_ENCODING', '音频请求不支持压缩编码');
  }
  const lengthHeader = request.headers['content-length'];
  if (lengthHeader !== undefined) {
    const length = Number(lengthHeader);
    if (!/^\d+$/.test(lengthHeader) || !Number.isSafeInteger(length)) throw new HttpError(400, 'INVALID_CONTENT_LENGTH', '音频长度无效');
    if (length === 0) throw new HttpError(400, 'EMPTY_AUDIO', '音频数据不能为空');
    if (length > config.maxAudioBytes) throw new HttpError(413, 'AUDIO_TOO_LARGE', '音频文件不能超过 100 MB 或服务端设置的更小上限');
  }
  return voiceFormat;
}

function userLimiter(config, now) {
  const users = new Map();
  let nextCleanup = 0;
  return (userID) => {
    const time = now();
    if (time >= nextCleanup || users.size >= config.maxTrackedUsers) {
      for (const [key, value] of users) if (value.active === 0 && value.resetAt <= time) users.delete(key);
      nextCleanup = time + 60000;
    }
    let user = users.get(userID);
    if (!user) {
      if (users.size >= config.maxTrackedUsers) throw new HttpError(429, 'ASR_BUSY', '语音识别服务繁忙，请稍后重试');
      user = { active: 0, count: 0, resetAt: time + 60000 };
      users.set(userID, user);
    }
    if (user.resetAt <= time) { user.count = 0; user.resetAt = time + 60000; }
    if (user.active >= config.maxUserConcurrent) throw new HttpError(429, 'USER_BUSY', '已有音频正在识别，请稍后重试');
    if (user.count >= config.maxUserRequestsPerMinute) throw new HttpError(429, 'USER_RATE_LIMIT', '转文字请求过于频繁，请稍后重试');
    user.active++;
    user.count++;
    return () => { user.active--; };
  };
}

function sendJson(response, status, payload) {
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    ...(status >= 400 ? { Connection: 'close' } : {}),
    ...(status === 429 ? { 'Retry-After': '60' } : {}),
  });
  response.end(JSON.stringify(payload));
}

export function createAsrProxy({ env = process.env, config, authenticate, fetchImpl = fetch, now = Date.now } = {}) {
  config ??= readConfig(env, { hasCustomAuthenticate: typeof authenticate === 'function' });
  authenticate ??= createTokenAuthenticator({ url: config.authUrl, fetchImpl, timeoutMs: config.authTimeoutMs });
  const reserveUser = userLimiter(config, now);
  let active = 0;
  const server = createServer({ maxHeaderSize: 16384 }, async (request, response) => {
    const controller = new AbortController();
    const onAborted = () => controller.abort(new HttpError(499, 'CLIENT_DISCONNECTED', '客户端已断开连接'));
    const onClose = () => { if (!response.writableEnded) onAborted(); };
    request.on('aborted', onAborted);
    response.on('close', onClose);
    const timer = setTimeout(() => controller.abort(new HttpError(504, 'REQUEST_TIMEOUT', '请求超时，请稍后重试')), config.requestTimeoutMs);
    timer.unref();
    let acquired = false;
    let releaseUser;
    try {
      const url = new URL(request.url, 'http://localhost');
      if (url.pathname !== TRANSCRIBE_PATH) throw new HttpError(404, 'NOT_FOUND', '接口不存在');
      const origin = request.headers.origin;
      if (origin) {
        if (!config.corsOrigins.has(origin)) throw new HttpError(403, 'ORIGIN_NOT_ALLOWED', '此来源未获授权');
        response.setHeader('Access-Control-Allow-Origin', origin);
        response.setHeader('Vary', 'Origin');
      }
      if (request.method === 'OPTIONS' && origin) {
        response.writeHead(204, {
          'Access-Control-Allow-Methods': 'POST',
          'Access-Control-Allow-Headers': 'token, content-type, operationID',
          'Access-Control-Max-Age': '600',
        });
        response.end();
        return;
      }
      if (request.method !== 'POST') { response.setHeader('Allow', 'POST'); throw new HttpError(405, 'METHOD_NOT_ALLOWED', '请使用 POST 请求'); }
      const token = request.headers.token;
      if (typeof token !== 'string' || !token.trim() || token.length > 8192) throw new HttpError(401, 'AUTH_REQUIRED', '请先登录');
      const voiceFormat = parseAudioRequest(request, url, config);
      if (active >= config.maxConcurrent) throw new HttpError(429, 'ASR_BUSY', '语音识别服务繁忙，请稍后重试');
      active++;
      acquired = true;
      const identity = await withDeadline(controller.signal, config.authTimeoutMs, 'AUTH_TIMEOUT',
        (signal) => authenticate(token, { signal }));
      if (!validIdentity(identity)) throw new HttpError(401, 'AUTH_INVALID_TOKEN', '登录已失效，请重新登录');
      releaseUser = reserveUser(identity.userID.trim());
      const audio = await withDeadline(controller.signal, config.uploadTimeoutMs, 'UPLOAD_TIMEOUT',
        (signal) => readAudio(request, config.maxAudioBytes, signal));
      const result = await transcribe(config, audio, voiceFormat, controller.signal, fetchImpl, now);
      if (!response.destroyed) sendJson(response, 200, { errCode: 0, data: result });
    } catch (error) {
      if (!response.destroyed && !response.writableEnded) {
        const known = publicError(error);
        sendJson(response, known.status, { errCode: known.status, errMsg: known.message, errorCode: known.code, data: known.requestId ? { requestId: known.requestId } : null });
      }
    } finally {
      clearTimeout(timer);
      releaseUser?.();
      if (acquired) active--;
      request.off('aborted', onAborted);
      response.off('close', onClose);
    }
  });
  server.headersTimeout = 10000;
  server.requestTimeout = config.requestTimeoutMs + 1000;
  server.maxRequestsPerSocket = 100;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const config = readConfig(loadAsrEnvFile(process.env.ASR_ENV_FILE || undefined));
    const server = createAsrProxy({ config });
    server.listen(config.port, config.host, () => console.info(`ASR proxy listening on ${config.host}:${config.port}`));
    server.on('error', () => { console.error('ASR proxy could not listen; check HOST and PORT'); process.exitCode = 1; });
    const shutdown = () => { server.close(); server.closeAllConnections(); };
    process.once('SIGTERM', shutdown);
    process.once('SIGINT', shutdown);
  } catch (error) {
    console.error(`ASR proxy configuration error: ${error.message}`);
    process.exitCode = 1;
  }
}
