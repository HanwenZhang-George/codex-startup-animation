#!/usr/bin/env python3
import os
import pathlib
import plistlib
import subprocess
import tempfile
import uuid

root = pathlib.Path(__file__).resolve().parents[1]
domain = 'local.codex-dragon.test.' + uuid.uuid4().hex
environment = dict(os.environ, CODEX_DRAGON_DOCK_TEST_DOMAIN=domain)


def tile(label, url):
    return {'tile-type': 'file-tile', 'tile-data': {'file-label': label, 'file-data': {'_CFURLString': url, '_CFURLStringType': 15}}}


def exported():
    return plistlib.loads(subprocess.check_output(['/usr/bin/defaults', 'export', domain, '-']))


with tempfile.TemporaryDirectory(prefix='codex-dragon-dock-') as temporary:
    directory = pathlib.Path(temporary)
    official = directory / 'Official.app'
    entry = directory / 'Animation.app'
    for application, identifier in [(official, 'com.openai.codex'), (entry, 'local.codex-dragon.chatgpt-entry')]:
        (application / 'Contents').mkdir(parents=True)
        (application / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': identifier, 'CFBundlePackageType': 'APPL'}))
    fixture = directory / 'preferences.plist'
    original = [tile('Safari', 'file:///Applications/Safari.app/'), tile('ChatGPT', official.as_uri() + '/'), tile('Notes', 'file:///System/Applications/Notes.app/')]
    fixture.write_bytes(plistlib.dumps({'persistent-apps': original, 'unrelated': 'preserve'}))
    subprocess.run(['/usr/bin/defaults', 'import', domain, str(fixture)], check=True)
    command = ['/usr/bin/xcrun', 'swift', str(root / 'scripts/dock-entry.swift')]
    arguments = [str(entry), str(directory / 'state.plist')]
    try:
        for _ in range(2):
            subprocess.run(command + ['bind', *arguments], env=environment, check=True)
            result = exported()
            assert result['unrelated'] == 'preserve'
            tiles = result['persistent-apps']
            assert len(tiles) == 3 and tiles[0] == original[0] and tiles[2] == original[2], tiles
            assert tiles[1]['tile-data']['bundle-identifier'] == 'local.codex-dragon.chatgpt-entry'
        extra = tile('Maps', 'file:///System/Applications/Maps.app/')
        result['persistent-apps'].append(extra)
        fixture.write_bytes(plistlib.dumps(result))
        subprocess.run(['/usr/bin/defaults', 'import', domain, str(fixture)], check=True)
        subprocess.run(command + ['restore', *arguments], env=environment, check=True)
        assert exported()['persistent-apps'] == original + [extra]
        print('PASS: Dock position preserved, binding idempotent, restore preserves later changes')
    finally:
        subprocess.run(['/usr/bin/defaults', 'delete', domain], check=True)
