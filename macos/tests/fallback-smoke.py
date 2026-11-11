#!/usr/bin/env python3
"""Exercise real Launch Services failure paths without changing the user's config."""
import os
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import time

root = pathlib.Path(__file__).resolve().parents[1]
native = root / 'dist/Codex Dragon.app'
entry = root / 'dist/ChatGPT.app'


def run_native(application, report, extra=(), expected=()):
    process = subprocess.Popen([str(application / 'Contents/MacOS/CodexDragon'), '--test-report', str(report), *extra])
    started = time.monotonic()
    try:
        while time.monotonic() - started < 20:
            events = report.read_text() if report.exists() else ''
            if 'handoff-success' in events:
                assert all(event in events for event in expected), events
                return time.monotonic() - started
            assert process.poll() is None, events
            time.sleep(.1)
        raise AssertionError('No handoff: ' + report.read_text())
    finally:
        process.terminate()
        process.wait(timeout=5)


with tempfile.TemporaryDirectory(prefix='codex-dragon-fallback-') as temporary:
    directory = pathlib.Path(temporary)
    missing_media = directory / 'Missing Media.app'
    (missing_media / 'Contents/MacOS').mkdir(parents=True)
    shutil.copy2(native / 'Contents/Info.plist', missing_media / 'Contents/Info.plist')
    shutil.copy2(native / 'Contents/MacOS/CodexDragon', missing_media / 'Contents/MacOS/CodexDragon')
    elapsed = run_native(missing_media, directory / 'media.log', expected=['animation-unavailable'])
    assert elapsed < 5, elapsed
    bad_config = directory / 'broken.json'
    bad_config.write_text('{invalid')
    run_native(native, directory / 'config.log', ['--config', str(bad_config)], expected=['config-fallback'])
    print('PASS: missing video opens official client immediately; invalid config still opens official client')

    # An independent entry still opens the official app if its animation target
    # disappears, or starts and immediately exits. Original app stays untouched.
    for failure in ['missing', 'exits']:
        fixture = directory / (failure + '-entry.app')
        shutil.copytree(entry, fixture)
        animation = directory / (failure + '-animation.app')
        if failure == 'exits':
            (animation / 'Contents/MacOS').mkdir(parents=True)
            (animation / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                'CFBundleExecutable': 'Exit', 'CFBundleIdentifier': 'local.codex-dragon.launcher',
                'CFBundleName': 'Fault Fixture', 'CFBundlePackageType': 'APPL'}))
            executable = animation / 'Contents/MacOS/Exit'
            executable.write_text('#!/bin/sh\nexit 7\n')
            executable.chmod(0o755)
        info = fixture / 'Contents/Info.plist'
        metadata = plistlib.loads(info.read_bytes())
        metadata['DragonApplicationPath'] = str(animation)
        info.write_bytes(plistlib.dumps(metadata))
        report = directory / (failure + '.log')
        subprocess.run([str(fixture / 'Contents/MacOS/ChatGPTEntry'), '--test-report', str(report)], timeout=12, check=True)
        events = report.read_text()
        assert 'entry-fallback-success' in events, events
    print('PASS: independent Dock entry recovers from missing launcher and launcher exit')
