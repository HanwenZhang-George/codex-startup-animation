#!/usr/bin/env python3
import pathlib
import subprocess
import tempfile
import time

root = pathlib.Path(__file__).resolve().parents[1]
executable = root / 'dist/Codex Dragon.app/Contents/MacOS/CodexDragon'
with tempfile.TemporaryDirectory(prefix='codex-dragon-native-') as temporary:
    preview_log = pathlib.Path(temporary) / 'preview.log'
    subprocess.run([str(executable), '--preview', '--test-report', str(preview_log)], check=True, timeout=25)
    preview = preview_log.read_text()
    for event in ['media-ready', 'first-frame-displayed', 'finale-started', 'finale-ended']:
        assert event in preview, (event, preview)
    print('PASS: native preview decoded, displayed first frame, played finale, exited')
    handoff_log = pathlib.Path(temporary) / 'handoff.log'
    application = subprocess.Popen([str(executable), '--test-report', str(handoff_log)])
    try:
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if handoff_log.exists() and 'handoff-success' in handoff_log.read_text():
                break
            assert application.poll() is None, 'Native launcher exited before handoff'
            time.sleep(0.25)
        else:
            raise AssertionError('Native handoff did not complete')
        print('PASS: native animation handed off to existing official client')
    finally:
        application.terminate()
        application.wait(timeout=5)
