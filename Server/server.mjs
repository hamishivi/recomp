import http from 'node:http';
import {createHash, timingSafeEqual} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {RequestError, validateRequest, estimateMeal} from './estimate.mjs';
const MAX_BODY = 12_300_000;
export function configFromEnv(env = process.env) {
  const apiKey = env.OPENAI_API_KEY?.trim(), accessToken = env.RECOMP_ACCESS_TOKEN?.trim();
  if (!apiKey || apiKey.includes('replace-me')) throw new Error('Set OPENAI_API_KEY on the server.');
  if (!accessToken || accessToken.length < 32 || accessToken.includes('replace-me')) throw new Error('Set a random RECOMP_ACCESS_TOKEN of at least 32 characters.');
  if (accessToken === apiKey || accessToken.startsWith('sk-')) throw new Error('Use an independent random RECOMP_ACCESS_TOKEN, never the upstream API key.');
  const port = Number(env.PORT || 8787);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT.');
  return {apiKey, accessToken, model:env.OPENAI_MODEL || 'gpt-4.1-mini', host:env.HOST || '127.0.0.1', port};
}
const digest = s => createHash('sha256').update(s).digest();
function send(res, status, data) {
  if (res.destroyed || res.writableEnded) return;
  res.writeHead(status, {'Content-Type':'application/json; charset=utf-8', 'Cache-Control':'no-store',
    'X-Content-Type-Options':'nosniff', 'Connection':'close'});
  res.end(JSON.stringify(data));
}
function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0, parts = [], finished = false;
    const timer = setTimeout(() => fail(new RequestError(408, 'Photo upload timed out.')), 20000);
    function cleanup() { clearTimeout(timer); req.off('data', data); req.off('end', end); req.off('aborted', aborted); req.off('error', fail); }
    function fail(error) { if (finished) return; finished = true; cleanup(); parts = []; req.resume(); reject(error); }
    function aborted() { fail(new RequestError(400, 'Upload cancelled.')); }
    function data(chunk) { size += chunk.length; if (size > MAX_BODY) return fail(new RequestError(413, 'Photos are too large.'));
      parts.push(chunk); }
    function end() { if (finished) return; finished = true; cleanup();
      try { resolve(JSON.parse(Buffer.concat(parts).toString('utf8'))); }
      catch { reject(new RequestError(400, 'Invalid JSON request.')); } }
    req.on('data', data); req.on('end', end); req.on('aborted', aborted); req.on('error', fail);
  });
}
/// A single-user proxy. Quotas are deliberately global for its one access token,
/// not keyed by easily spoofed X-Forwarded-For headers. Restart resets counters.
export function createServer(config, provider = estimateMeal) {
  const expected = digest(`Bearer ${config.accessToken}`);
  let minute = 0, minuteCount = 0, day = 0, dayCount = 0, active = 0;
  return http.createServer({requestTimeout:25000, headersTimeout:10000, maxHeaderSize:8192}, async (req,res) => {
    const cancel = new AbortController();
    res.on('close', () => { if (!res.writableEnded) cancel.abort(); });
    try {
      if (req.method === 'GET' && req.url === '/health') return send(res,200,{ok:true});
      if (req.method !== 'POST' || req.url !== '/v1/estimate') return send(res,404,{error:'Not found.'});
      if (!timingSafeEqual(expected, digest(req.headers.authorization ?? ''))) return send(res,401,{error:'Incorrect server access token. Check estimator settings.'});
      if (req.headers['content-type']?.split(';',1)[0].trim().toLowerCase() !== 'application/json') return send(res,415,{error:'Use application/json.'});
      if (req.headers['content-encoding'] && req.headers['content-encoding'] !== 'identity') return send(res,415,{error:'Compressed uploads are not accepted.'});
      if (Number(req.headers['content-length'] || 0) > MAX_BODY) {
        // Drain the declared body before responding so clients receive the
        // rejection instead of a connection reset while they are uploading.
        // The bounded declared size is never parsed or retained in memory.
        req.once('end', () => send(res,413,{error:'Photos are too large.'}));
        req.once('error', () => { if (!res.writableEnded) send(res,413,{error:'Photos are too large.'}); });
        req.resume();
        return;
      }
      const now = Date.now(), thisMinute = Math.floor(now/60000), thisDay = Math.floor(now/86400000);
      if (minute !== thisMinute) { minute = thisMinute; minuteCount = 0; }
      if (day !== thisDay) { day = thisDay; dayCount = 0; }
      if (minuteCount >= (config.perMinute ?? 6) || dayCount >= (config.perDay ?? 100)) return send(res,429,{error:'Estimate limit reached. Try later; manual logging still works.'});
      if (active >= 2) return send(res,429,{error:'An estimate is already running. Try again shortly.'});
      minuteCount++; dayCount++; active++;
      try {
        const input = validateRequest(await readBody(req));
        const result = await provider(input, config, undefined, cancel.signal);
        send(res,200,result);
      } finally { active--; }
    } catch (error) {
      const timedOut = error.name === 'TimeoutError' || error.name === 'AbortError';
      send(res, error instanceof RequestError ? error.status : timedOut ? 504 : 502,
        {error:error instanceof RequestError ? error.message : timedOut ? 'Estimation timed out. Your draft is unchanged.' : 'Estimation service is unavailable. Try later or enter values manually.'});
      // Never log food, photos, headers, API responses or credentials.
    }
  });
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const config = configFromEnv();
    const server = createServer(config);
    server.listen(config.port, config.host, () => console.log(`Recomp estimator listening on ${config.host}:${config.port}. Use HTTPS for an iPhone.`));
    server.on('error', () => { console.error('Cannot start estimator. Check host and port.'); process.exitCode=1; });
  } catch (error) { console.error(error.message); process.exitCode=1; }
}
