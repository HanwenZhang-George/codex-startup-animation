import { spawn } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { createHash, randomBytes } from 'node:crypto';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// Chromium's private FD 3/4 transport: no listening socket or debug port.
export class CDPPipe {
  constructor(executable, args) {
    this.pending = new Map(); this.nextID = 0; this.buffer = Buffer.alloc(0);
    this.child = spawn(executable, [...args, '--remote-debugging-pipe'], {
      stdio: ['ignore', 'ignore', 'ignore', 'pipe', 'pipe'],
    });
    this.child.stdio[4].on('data', data => this.receive(data));
    this.child.stdio[4].on('error', () => this.fail());
    this.child.stdio[3].on('error', () => this.fail());
    this.child.on('error', () => this.fail());
    this.child.once('exit', () => this.fail());
  }
  fail() {
    for (const request of this.pending.values()) { clearTimeout(request.timer); request.reject(Error('transport-closed')); }
    this.pending.clear();
  }
  receive(data) {
    if (this.buffer.length + data.length > 2 * 1024 * 1024) { this.fail(); this.buffer = Buffer.alloc(0); return; }
    this.buffer = Buffer.concat([this.buffer, data]);
    let zero;
    while ((zero = this.buffer.indexOf(0)) !== -1) {
      const frame = this.buffer.subarray(0, zero); this.buffer = this.buffer.subarray(zero + 1);
      try {
        const message = JSON.parse(frame.toString('utf8'));
        const pending = this.pending.get(message.id);
        if (!pending) { if (!message.id) this.onEvent?.(message); continue; }
        this.pending.delete(message.id); clearTimeout(pending.timer);
        if (message.error) { pending.reject(Error(`protocol-error:${pending.method}:${message.error.code}:${String(message.error.message).slice(0, 160)}`)); continue; }
        if (message.sessionId !== pending.session) { pending.reject(Error(`session-mismatch:${pending.method}:expected-${typeof pending.session}:received-${typeof message.sessionId}`)); continue; }
        pending.resolve(message.result);
      } catch { this.fail(); }
    }
  }
  send(method, params = {}, session, timeout = 5000) {
    if (this.pending.size > 8) return Promise.reject(Error('too-many-requests'));
    const id = ++this.nextID;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(Error('request-timeout')); }, timeout);
      this.pending.set(id, { resolve, reject, timer, session, method });
      const packet = JSON.stringify({ id, method, params, ...(session ? { sessionId: session } : {}) });
      this.child.stdio[3].write(packet + '\0', error => {
        if (error) { clearTimeout(timer); this.pending.delete(id); reject(Error('transport-write-failed')); }
      });
    });
  }
  async evaluate(expression, session, awaitPromise = false, timeout = 8000) {
    const result = await this.send('Runtime.evaluate', { expression, awaitPromise, returnByValue: true }, session, timeout);
    if (result.exceptionDetails) throw Error('renderer-evaluation-failed');
    return result.result?.value;
  }
}

export function acceptedTarget(target) {
  if (target.type !== 'page') return false;
  try {
    const url = new URL(target.url);
    return url.protocol === 'app:' && url.hostname === '-' && url.pathname === '/index.html';
  } catch { return false; }
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const KEY = 'window.__codexDragonWallpaperV1';
const here = path.dirname(fileURLToPath(import.meta.url));
let outputOpen = true;
process.stdout.on('error', () => { outputOpen = false; });
process.stdout.on('close', () => { outputOpen = false; });
const emit = (event, fields = {}) => { if (outputOpen) process.stdout.write(JSON.stringify({ event, ...fields }) + '\n'); };
const SHA = {
  'dragon-wallpaper-ambient-2k-144fps.mp4': '7d72905fcc39478e0d8006f712549fa78f100036fafa09d506de209acffd9eba',
  'dragon-wallpaper-particles-1440p48.mp4': 'e45905234e9c0bc7370ab7c480e5898fb561818db7bd51a57921312ebcce6cdd',
};
// Keep only fixed, bounded media/layout fields. No DOM, page text, titles or URLs.
function summary(status) {
  const result = {};
  for (const name of ['code', 'layoutReason', 'activeClip', 'actualPhase']) {
    if (typeof status?.[name] === 'string' && /^[a-z-]{1,64}$/.test(status[name])) result[name] = status[name];
  }
  for (const name of ['attached', 'playing', 'stageVisible', 'layoutSupported', 'mediaReady', 'wallpaperApplied', 'firstFrameConfirmed', 'manuallyPaused', 'betweenAppearances', 'alternateAvailable']) {
    if (typeof status?.[name] === 'boolean') result[name] = status[name];
  }
  for (const name of ['mediaTimeMs', 'presentedFrames', 'completedCycles', 'nextAppearanceMs']) {
    if (Number.isSafeInteger(status?.[name]) && status[name] >= 0 && status[name] < 2 ** 31) result[name] = status[name];
  }
  return result;
}

async function main() {
  const executable = process.argv[2];
  if (!executable || !path.isAbsolute(executable)) throw Error('invalid-executable');
  for (const [name, hash] of Object.entries(SHA)) {
    const bytes = await readFile(path.join(here, name));
    if (createHash('sha256').update(bytes).digest('hex') !== hash) throw Error('media-hash-mismatch');
  }
  const source = await readFile(path.join(here, 'renderer.js'), 'utf8');
  const transport = new CDPPipe(executable, []);
  let session, timer, busy = false, disabled = false, revealRequested = false, paused = false, installed = false;
  let generation;
  const evaluate = expression => transport.evaluate(expression, session);
  transport.onEvent = message => {
    if (message.method === 'Target.detachedFromTarget' && message.params?.sessionId === session) {
      session = undefined; installed = false; generation = undefined;
      emit('wallpaper-waiting');
    }
  };
  transport.child.once('exit', () => { clearInterval(timer); emit('codex-exited'); process.exit(0); });
  emit('codex-started');
  async function dispose() {
    disabled = true;
    if (session) await evaluate(`${KEY}?.dispose()`).catch(() => {});
    emit('wallpaper-disabled');
  }
  const commands = createInterface({ input: process.stdin, terminal: false });
  commands.on('line', line => {
    if (line.length > 128) return;
    let command;
    try { command = JSON.parse(line).command; } catch { return; }
    if (command === 'disable') { void dispose(); return; }
    if (command === 'reveal') { revealRequested = true; paused = false; }
    if (command === 'pause') { paused = true; }
    if (command === 'resume') { revealRequested = true; paused = false; disabled = false; }
    if (session && !disabled) {
      if (command === 'pause') void evaluate(`${KEY}?.pause()`).catch(() => {});
      else if (command === 'reveal' || command === 'resume') void evaluate(`${KEY}?.reveal()`).catch(() => {});
      else if (command === 'pressure-on' || command === 'pressure-off')
        void evaluate(`${KEY}?.memoryPressure(${command === 'pressure-on'})`).catch(() => {});
    }
  });
  commands.once('close', () => { void dispose(); });
  async function install() {
    const result = await evaluate(source);
    if (!result?.ok) throw Error('renderer-install-failed');
    generation = randomBytes(16).toString('hex');
    await evaluate(`${KEY}.configure(${JSON.stringify({ managed: true, documentGeneration: generation })})`);
    const { root } = await transport.send('DOM.getDocument', { depth: 0 }, session);
    const { nodeId } = await transport.send('DOM.querySelector', { nodeId: root.nodeId, selector: '#codex-dragon-file-v1' }, session);
    if (!nodeId) throw Error('media-input-missing');
    await transport.send('DOM.setFileInputFiles', { nodeId, files: Object.keys(SHA).map(name => path.join(here, name)) }, session);
    const attached = await transport.evaluate(`${KEY}.attach({deferReveal:true})`, session, true, 18000);
    if (!attached?.ok) {
      const status = await evaluate(`${KEY}.status()`);
      emit('wallpaper-unavailable', summary(status));
      await evaluate(`${KEY}.dispose()`);
      return false;
    }
    emit('wallpaper-prepared');
    if (paused) await evaluate(`${KEY}.pause()`);
    else if (revealRequested) await evaluate(`${KEY}.reveal()`);
    return true;
  }
  // One page binding per owned client. Unknown pages remain unchanged.
  const deadline = Date.now() + 45000;
  while (!session && Date.now() < deadline && !disabled) {
    try {
      const { targetInfos } = await transport.send('Target.getTargets');
      const pages = targetInfos.filter(acceptedTarget);
      if (pages.length === 1) {
        ({ sessionId: session } = await transport.send('Target.attachToTarget', { targetId: pages[0].targetId, flatten: true }));
        break;
      }
    } catch { /* Cold startup can delay target discovery. */ }
    await sleep(500);
  }
  if (!session) { emit('wallpaper-unavailable', { code: 'page-not-ready' }); return; }
  let lastStatus = '';
  async function tick() {
    if (busy || disabled) return;
    busy = true;
    try {
      if (!session) {
        const { targetInfos } = await transport.send('Target.getTargets');
        const pages = targetInfos.filter(acceptedTarget);
        if (pages.length !== 1) return;
        ({ sessionId: session } = await transport.send('Target.attachToTarget', { targetId: pages[0].targetId, flatten: true }));
      }
      const rootReady = await evaluate(`!!document.getElementById('root') && !!document.body`);
      if (!rootReady) return;
      const shellReady = await evaluate(`!!document.querySelector('#root [data-app-shell-frame], #root main[data-app-shell-main-surface="default"]')`);
      if (!shellReady) { emit('wallpaper-waiting', {code:'shell-not-ready'}); return; }
      const present = await evaluate(`!!${KEY}`);
      if (!present) installed = await install();
      if (!installed) return;
      await evaluate(`${KEY}.renewLease(${JSON.stringify(generation)})`);
      let status = await evaluate(`${KEY}.status()`);
      if (status?.recoveryNeeded) {
        await evaluate(`${KEY}.recover(${status.mediaGeneration})`);
        status = await evaluate(`${KEY}.status()`);
      }
      const current = summary(status);
      // Throttled, numeric state only; does not read user content.
      const serialized = JSON.stringify(current);
      if (serialized !== lastStatus) { emit('status', current); lastStatus = serialized; }
    } catch (error) {
      installed = false;
      if (error.message.includes(':-32001:')) session = undefined;
      emit('wallpaper-waiting');
    }
    finally { busy = false; }
  }
  await tick();
  timer = setInterval(() => { void tick(); }, 2500);
  // On launcher quit, restore the interface but drain the owned private pipe
  // until Codex exits; disconnecting Chromium's pipe can terminate its process.
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => { emit('error', { code: 'bridge-failed' }); process.exitCode = 1; });
}
