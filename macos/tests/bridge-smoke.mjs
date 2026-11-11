import { spawn, execFileSync } from 'node:child_process';
import { mkdtemp, writeFile, readFile, chmod, lstat, readdir, rm } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const executable = process.argv[2];
assert(executable && path.isAbsolute(executable));
const temporary = await mkdtemp(path.join(os.tmpdir(), 'codex-dragon-bridge-'));
const profile = path.join(temporary, 'profile');
const wrapper = path.join(temporary, 'isolated-client');
const pidFile = path.join(temporary, 'child.pid');
const quote = value => `'${value.replaceAll("'", "'\\''")}'`;
await writeFile(wrapper, `#!/bin/sh\necho $$ > ${quote(pidFile)}\nexec ${quote(executable)} --user-data-dir=${quote(profile)} --no-first-run --disable-background-networking "$@"\n`);
await chmod(wrapper, 0o700);
const bridge = spawn(process.execPath, [path.join(root, 'dist/Codex Dragon.app/Contents/Resources/bridge.mjs'), wrapper], { stdio: ['pipe', 'pipe', 'inherit'] });
const events = [];
let buffer = '';
bridge.stdout.on('data', data => {
  buffer += data;
  let newline;
  while ((newline = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, newline); buffer = buffer.slice(newline + 1);
    events.push(JSON.parse(line));
  }
});
const send = command => { if (!bridge.stdin.writableEnded) bridge.stdin.write(JSON.stringify({ command }) + '\n'); };
async function waitFor(predicate, timeout = 45000, after = 0) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const event = events.slice(after).find(predicate);
    if (event) return event;
    assert(bridge.exitCode === null, 'Bridge exited before the requested event');
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw Error('Bridge timeout: ' + JSON.stringify(events));
}
async function writableDirectories(directory) {
  const info = await lstat(directory);
  if (!info.isDirectory() || info.isSymbolicLink()) return;
  await chmod(directory, 0o700);
  for (const name of await readdir(directory)) await writableDirectories(path.join(directory, name));
}
try {
  // Deliberately skip before the client/renderer exists: the reveal must survive.
  send('reveal');
  const playing = await waitFor(event => event.event === 'status' && event.playing && event.firstFrameConfirmed && event.stageVisible);
  assert(playing.alternateAvailable && playing.activeClip === 'ambient');
  let mark = events.length;
  send('pause');
  await waitFor(event => event.event === 'status' && event.manuallyPaused, 10000, mark);
  mark = events.length;
  send('resume');
  await waitFor(event => event.event === 'status' && event.playing, 10000, mark);
  mark = events.length;
  send('disable');
  await waitFor(event => event.event === 'wallpaper-disabled', 10000, mark);
  mark = events.length;
  send('resume');
  await waitFor(event => event.event === 'status' && event.playing && event.stageVisible, 25000, mark);
  mark = events.length;
  send('disable');
  await waitFor(event => event.event === 'wallpaper-disabled', 10000, mark);
  bridge.stdout.destroy();
  bridge.stdin.end();
  await new Promise(resolve => setTimeout(resolve, 1200));
  assert(bridge.exitCode === null, 'Closing the launcher must retain the private pipe for the still-running official client');
  console.log(JSON.stringify({ bridge: 'passed', earlySkip: true, officialMacFirstFrame: true, pauseResume: true, restoreReenable: true, launcherDetachKeepsClient: true }));
} finally {
  send('disable');
  await new Promise(resolve => setTimeout(resolve, 400));
  const childPID = Number(await readFile(pidFile, 'utf8').catch(() => '0'));
  if (childPID > 1) {
    const parentPID = Number(execFileSync('/bin/ps', ['-o', 'ppid=', '-p', String(childPID)], { encoding: 'utf8' }).trim());
    // Signal only the test-owned isolated client, never the user's existing app.
    if (parentPID === bridge.pid) process.kill(childPID, 'SIGTERM');
  }
  bridge.stdin.end();
  for (let attempt = 0; attempt < 50 && bridge.exitCode === null; attempt++) await new Promise(resolve => setTimeout(resolve, 100));
  if (bridge.exitCode === null) bridge.kill('SIGTERM');
  await writableDirectories(temporary);
  await rm(temporary, { recursive: true, force: true });
}
