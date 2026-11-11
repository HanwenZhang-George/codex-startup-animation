import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { chromium } from 'playwright';

// The Mac 157 component hashes differ independently, unlike the older shared
// module hash. Synthetic controls only; no application, account, or network.
const source = await readFile(new URL('../Runtime/renderer.js', import.meta.url), 'utf8');
const browser = await chromium.launch({
  executablePath: process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
  args: ['--disable-background-networking', '--disable-component-update', '--no-first-run'],
});
let checks = 0;
function check(actual, expected = true) { assert.deepEqual(actual, expected); checks++; }
try {
  const page = await browser.newPage();
  await page.route('**/*', route => route.abort());
  const shell = `<div id="root"><div class="Layout-SYw9n4 PageSurfaceLayout-oqnRfB" data-app-shell-frame="true" data-app-shell-page-surface="true">
    <div data-app-shell-workspace-row="true"><div class="Workspace-IfYAxV">
      <aside id="app-shell-sidebar" class="LeftPanel-RtYuIo"><nav data-app-navigation-rail>Navigation</nav></aside>
      <div class="MainContentClip-QvkcTI"><main id="main" class="MainContentSurface-EnuIYE" data-app-shell-main-surface="default">
        <div class="WorkspaceContent-dnr6uY"><div id="composer" class="ComposerLayoutRoot-XCKS7O" data-composer-surface-variant="default">
          <textarea></textarea><button id="send">Send</button>
        </div></div>
      </main></div>
    </div></div></div></div>`;
  const status = () => page.evaluate(() => window.__codexDragonWallpaperV1.status());
  async function install() {
    await page.setContent(`<style>:root{--color-surface:#1d1e2c;--color-surface-elevated-secondary:#343646}
      #composer{background:var(--composer-layout-surface-background,#343646)}</style>${shell}`);
    check((await page.evaluate(source)).ok);
  }
  await install();
  check((await status()).layoutSupported);
  check((await status()).layoutSurfaceKind, 'main');
  await page.evaluate(() => document.documentElement.setAttribute('data-codex-dragon-background', 'v1'));
  const paint = await page.locator('#composer').evaluate(node => {
    const color = getComputedStyle(node).backgroundColor;
    const canvas = document.createElement('canvas'); canvas.width = canvas.height = 1;
    const context = canvas.getContext('2d'); context.fillStyle = color; context.fillRect(0, 0, 1, 1);
    return { color, alpha: context.getImageData(0, 0, 1, 1).data[3],
      reducedTransparency: matchMedia('(prefers-reduced-transparency: reduce)').matches,
      highContrast: matchMedia('(prefers-contrast: more)').matches };
  });
  assert.equal(paint.alpha, 153, JSON.stringify(paint)); checks++;
  await page.locator('textarea').fill('Synthetic input');
  check(await page.locator('textarea').inputValue(), 'Synthetic input');
  await page.evaluate(() => document.getElementById('send').onclick = () => window.syntheticClicked = true);
  await page.locator('#send').click();
  check(await page.evaluate(() => window.syntheticClicked));
  await page.evaluate(() => document.getElementById('main').classList.add('MainContentSurface-AbCdEf'));
  check((await status()).layoutSupported, false);
  await install();
  await page.evaluate(() => document.getElementById('composer').classList.add('ComposerLayoutRoot-AbCdEf'));
  check((await status()).layoutSupported, false);
  await page.evaluate(() => window.__codexDragonWallpaperV1.dispose());
  check(await page.locator('#codex-dragon-stage-v1,#codex-dragon-file-v1,#codex-dragon-style-v1').count(), 0);
  check(await page.evaluate(() => document.documentElement.hasAttribute('data-codex-dragon-background')), false);
  console.log(JSON.stringify({ passed: true, checks, suite: 'modern-mac-layout', networkBlocked: true }));
} finally { await browser.close(); }
