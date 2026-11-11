#!/usr/bin/env python3
"""Extract only the original, hash-verified startup movie; never run Windows files."""
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
ARCHIVE_SHA = '23243e01a53a80c7b73e5a970160d46556b7a0d727fb7991e5693eaa4268c3ff'
MOVIE_SHA = 'f5e20feab29d3e89893bee995a24857be3e37f773795af9a21ffaa017c199187'
URL = ('https://github.com/HanwenZhang-George/codex-startup-animation/releases/download/'
       'community-v34-r5/CodexDragon-V34-Portable-Windows-x64-r5.zip')


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def main():
    destination = ROOT / 'media' / 'startup.mp4'
    manifest = json.loads((ROOT.parent / 'community-v34/media-manifest.json').read_text())
    entries = [entry for entry in manifest['files'] if entry['path'].endswith('.mp4')]
    def output(entry):
        return destination if entry['sha256'].lower() == MOVIE_SHA else destination.parent / pathlib.PurePosixPath(entry['path']).name
    if all(output(entry).exists() and digest(output(entry)) == entry['sha256'].lower() for entry in entries):
        print('全部六段原版视频已校验。')
        return
    with tempfile.TemporaryDirectory(prefix='codex-dragon-') as temporary:
        archive = pathlib.Path(sys.argv[1]).expanduser().resolve() if len(sys.argv) > 1 else pathlib.Path(temporary) / 'release.zip'
        if len(sys.argv) == 1:
            subprocess.run(['/usr/bin/curl', '--fail', '--location', '--retry', '3',
                            '--connect-timeout', '20', '--max-time', '900', URL, '-o', str(archive)], check=True)
        if digest(archive) != ARCHIVE_SHA:
            raise SystemExit('发布包 SHA-256 不匹配，已停止。')
        with zipfile.ZipFile(archive) as package:
            for entry in entries:
                names = [name for name in package.namelist() if name.replace('\\', '/') == entry['path']]
                if len(names) != 1:
                    raise SystemExit('发布包内没有唯一的原版视频。')
                movie = package.read(names[0])
                if hashlib.sha256(movie).hexdigest() != entry['sha256'].lower():
                    raise SystemExit('视频 SHA-256 不匹配，已停止。')
                target = output(entry)
                target.parent.mkdir(parents=True, exist_ok=True)
                staging = target.with_suffix('.tmp')
                staging.write_bytes(movie)
                staging.replace(target)
    print('全部六段原版视频已提取并校验，未重新编码。')


if __name__ == '__main__':
    main()
