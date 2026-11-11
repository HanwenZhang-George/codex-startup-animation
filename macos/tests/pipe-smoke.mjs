import { CDPPipe, acceptedTarget } from '../Runtime/bridge.mjs';
import { mkdtemp, rm, readFile, lstat, chmod, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';

const executable = process.argv[2];
assert(executable && path.isAbsolute(executable));
const directory = await mkdtemp(path.join(os.tmpdir(), 'codex-dragon-isolated-'));
async function writableDirectories(directory) {
  const info = await lstat(directory);
  if (!info.isDirectory() || info.isSymbolicLink()) return;
  await chmod(directory, 0o700);
  for (const name of await readdir(directory)) await writableDirectories(path.join(directory, name));
}
const pipe = new CDPPipe(executable, [`--user-data-dir=${directory}`, '--no-first-run', '--disable-background-networking']);
pipe.onEvent = event => { if (['Target.detachedFromTarget', 'Inspector.detached', 'Inspector.targetCrashed'].includes(event.method)) console.log(JSON.stringify({event:event.method,reason:event.params?.reason})); };
let closed = false;
pipe.child.once('exit', () => { closed = true; });
try {
  let response;
  for (let attempt = 0; attempt < 40; attempt++) {
    try { response = await pipe.send('Target.getTargets', {}, undefined, 3000); if (response.targetInfos.some(target => target.type === 'page')) break; }
    catch { /* A cold process may take a moment to expose targets. */ }
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  assert(Array.isArray(response?.targetInfos), 'The signed Mac client must respond over its private pipe');
  console.log(JSON.stringify({ privatePipeResponded: true, eligiblePages: response.targetInfos.filter(acceptedTarget).length,
    pagePaths: response.targetInfos.filter(target => target.type === 'page').map(target => {
      const url = new URL(target.url); return `${url.protocol}//${url.host}${url.pathname}`;
    }) }));
  if (process.argv.includes('--wallpaper')) {
    await new Promise(resolve => setTimeout(resolve, 4000));
    response = await pipe.send('Target.getTargets');
    const target = response.targetInfos.find(acceptedTarget);
    assert(target, 'An official app:// renderer must exist');
    const { sessionId } = await pipe.send('Target.attachToTarget', { targetId: target.targetId, flatten: true });
    const evaluate = (expression, wait = false) => pipe.evaluate(expression, sessionId, wait, 18000);
    for (let attempt = 0; attempt < 60; attempt++) {
      if (await evaluate(`!!document.querySelector('#root [data-app-shell-frame], #root main[data-app-shell-main-surface="default"]')`)) break;
      await new Promise(resolve => setTimeout(resolve, 500));
    }
    const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
    const result = await evaluate(await readFile(path.join(root, 'macos/Runtime/renderer.js'), 'utf8'));
    assert(result?.ok, 'The official Mac renderer must accept the local wallpaper layer');
    const status = await evaluate('window.__codexDragonWallpaperV1.status()');
    console.log(JSON.stringify({ layoutSupported: status.layoutSupported, layoutReason: status.layoutReason, layoutSurfaceKind: status.layoutSurfaceKind }));
    if (!status.layoutSupported) console.log(JSON.stringify({ shellTokens: await evaluate(`Array.from(document.querySelectorAll('#root main[data-app-shell-main-surface="default"], #root [data-app-shell-frame], #root [data-app-shell-workspace-row], #root [data-composer-surface-variant]')).slice(0,12).map(n=>({tag:n.tagName,classes:n.className,children:Array.from(n.children).slice(0,12).map(c=>({tag:c.tagName,classes:c.className})),ancestors:[n.parentElement?.className,n.parentElement?.parentElement?.className]}))`) }));
    assert(status.layoutSupported, 'The current official Mac layout must be supported');
    await evaluate(`window.__codexDragonWallpaperV1.configure({managed:true,documentGeneration:'11111111111111111111111111111111'})`);
    const { root: document } = await pipe.send('DOM.getDocument', { depth: 0 }, sessionId);
    const { nodeId } = await pipe.send('DOM.querySelector', { nodeId: document.nodeId, selector: '#codex-dragon-file-v1' }, sessionId);
    await pipe.send('DOM.setFileInputFiles', { nodeId, files: [
      path.join(root, 'macos/media/dragon-wallpaper-ambient-2k-144fps.mp4'),
      path.join(root, 'macos/media/dragon-wallpaper-particles-1440p48.mp4'),
    ] }, sessionId);
    assert((await evaluate('window.__codexDragonWallpaperV1.attach({deferReveal:true})', true))?.ok);
    await evaluate('window.__codexDragonWallpaperV1.reveal()');
    let playing;
    for (let attempt = 0; attempt < 40; attempt++) {
      playing = await evaluate('window.__codexDragonWallpaperV1.status()');
      if (playing.playing && playing.firstFrameConfirmed && playing.stageVisible) break;
      await new Promise(resolve => setTimeout(resolve, 250));
    }
    assert(playing.playing && playing.firstFrameConfirmed && playing.stageVisible, 'The original wallpaper must present a frame inside the official Mac client');
    assert(playing.alternateAvailable, 'Both original videos must be available');
    await evaluate('window.__codexDragonWallpaperV1.pause()');
    assert((await evaluate('window.__codexDragonWallpaperV1.status()')).manuallyPaused);
    await evaluate('window.__codexDragonWallpaperV1.dispose()');
    assert(await evaluate(`!document.getElementById('codex-dragon-stage-v1') && !document.documentElement.hasAttribute('data-codex-dragon-background')`));
    console.log(JSON.stringify({ officialMacWallpaper: 'passed', firstFrameConfirmed: true, pauseAndRestore: true, originalSessionUntouched: true }));
  }
} finally {
  await pipe.send('Browser.close', {}, undefined, 3000).catch(() => {});
  for (let attempt = 0; attempt < 30 && !closed; attempt++) await new Promise(resolve => setTimeout(resolve, 100));
  // Only the process created by this test, using its isolated temporary profile.
  if (!closed) pipe.child.kill('SIGTERM');
  await new Promise(resolve => setTimeout(resolve, 1000));
  await writableDirectories(directory);
  await rm(directory, { recursive: true, force: true });
}
