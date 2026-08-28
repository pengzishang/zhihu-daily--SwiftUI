import { chromium } from 'playwright';
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const repoRoot = process.cwd();
const evidenceDir = path.join(repoRoot, '.omo/evidence/homepage-prototype-qa');
const htmlPath = path.join(repoRoot, 'outputs/首页三套方案-互动设计稿.html');
const cssPath = path.join(repoRoot, 'outputs/首页三套方案-tokens.css');
const url = pathToFileURL(htmlPath).href;

const widths = [320, 375, 414, 768];
const layouts = ['directory', 'frontpage', 'sections'];
const themes = ['day', 'night'];

await fs.mkdir(evidenceDir, { recursive: true });

const artifacts = [];
function artifact(id, kind, description, filePath) {
  artifacts.push({ id, kind, description, path: filePath });
}

const browser = await chromium.launch({
  headless: true,
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
});
const page = await browser.newPage({ viewport: { width: 375, height: 900 }, deviceScaleFactor: 1 });

const consoleEvents = [];
const pageErrors = [];
const failedRequests = [];
const networkRequests = [];

page.on('console', (msg) => {
  consoleEvents.push({ type: msg.type(), text: msg.text(), location: msg.location() });
});
page.on('pageerror', (err) => {
  pageErrors.push({ name: err.name, message: err.message, stack: err.stack });
});
page.on('request', (req) => {
  networkRequests.push({ url: req.url(), resourceType: req.resourceType(), method: req.method() });
});
page.on('requestfailed', (req) => {
  failedRequests.push({ url: req.url(), resourceType: req.resourceType(), failure: req.failure() });
});

async function writeJson(name, data, description) {
  const filePath = path.join(evidenceDir, name);
  await fs.writeFile(filePath, JSON.stringify(data, null, 2));
  artifact(name.replace(/\W+/g, '-').replace(/-json$/, ''), 'json', description, filePath);
  return filePath;
}

async function evaluateState(expectedLayout, expectedTheme) {
  return page.evaluate(({ expectedLayout, expectedTheme }) => {
    const activeLayoutEls = [...document.querySelectorAll('.layout.is-active')];
    const visibleLayouts = [...document.querySelectorAll('[data-layout]')]
      .filter((el) => getComputedStyle(el).display !== 'none')
      .map((el) => el.dataset.layout);
    const activeButtons = [...document.querySelectorAll('[data-view][aria-pressed="true"]')].map((el) => el.dataset.view);
    const activeNotes = [...document.querySelectorAll('[data-note]')]
      .filter((el) => !el.hidden && getComputedStyle(el).display !== 'none')
      .map((el) => el.dataset.note);
    const inactiveNotesVisible = [...document.querySelectorAll('[data-note]')]
      .filter((el) => el.hidden && getComputedStyle(el).display !== 'none')
      .map((el) => el.dataset.note);
    const themeButton = document.querySelector('#theme-toggle');
    const allButtons = [...document.querySelectorAll('button')].map((el) => ({
      text: el.textContent.trim(),
      type: el.getAttribute('type'),
      ariaPressed: el.getAttribute('aria-pressed'),
      dataView: el.dataset.view || null,
    }));
    const root = document.documentElement;
    const body = document.body;
    const overflowingElements = [...document.body.querySelectorAll('*')]
      .map((el) => {
        const rect = el.getBoundingClientRect();
        return {
          tag: el.tagName.toLowerCase(),
          className: typeof el.className === 'string' ? el.className : '',
          text: el.textContent.trim().slice(0, 80),
          left: Math.round(rect.left * 100) / 100,
          right: Math.round(rect.right * 100) / 100,
          width: Math.round(rect.width * 100) / 100,
        };
      })
      .filter((item) => item.right > window.innerWidth + 1 || item.left < -1);
    const focusOutline = getComputedStyle(document.querySelector('button')).outlineStyle;
    return {
      expectedLayout,
      expectedTheme,
      url: location.href,
      title: document.title,
      lang: document.documentElement.lang,
      viewportMeta: document.querySelector('meta[name="viewport"]')?.content || null,
      bodyTheme: body.dataset.theme,
      themeButton: {
        text: themeButton?.textContent.trim() || null,
        ariaPressed: themeButton?.getAttribute('aria-pressed') || null,
      },
      activeLayoutCount: activeLayoutEls.length,
      visibleLayouts,
      activeButtons,
      activeNotes,
      inactiveNotesVisible,
      documentScrollWidth: root.scrollWidth,
      bodyScrollWidth: body.scrollWidth,
      innerWidth: window.innerWidth,
      clientWidth: root.clientWidth,
      horizontalOverflow: root.scrollWidth > window.innerWidth || body.scrollWidth > window.innerWidth || overflowingElements.length > 0,
      overflowingElements,
      allButtons,
      focusOutline,
      hasH1: Boolean(document.querySelector('h1')),
      labelledMainSurface: document.querySelector('.reader-surface')?.getAttribute('aria-label') || null,
      labelledNav: document.querySelector('.control-strip')?.getAttribute('aria-label') || null,
    };
  }, { expectedLayout, expectedTheme });
}

const surfaceEvidence = [];
const adversarialCases = [];
const screenshots = [];

await page.goto(url, { waitUntil: 'load' });
await page.evaluate(() => {
  localStorage.removeItem('dailyreader-prototype-layout');
  localStorage.removeItem('dailyreader-prototype-theme');
});

for (const width of widths) {
  await page.setViewportSize({ width, height: 950 });
  for (const theme of themes) {
    await page.goto(url, { waitUntil: 'load' });
    await page.evaluate((theme) => {
      localStorage.clear();
      document.querySelector('#theme-toggle').click();
      if (document.body.dataset.theme !== theme) document.querySelector('#theme-toggle').click();
    }, theme);
    for (const layout of layouts) {
      await page.click(`[data-view="${layout}"]`);
      await page.waitForTimeout(260);
      const state = await evaluateState(layout, theme);
      const id = `${width}-${theme}-${layout}`;
      const screenshotPath = path.join(evidenceDir, `${id}.png`);
      await page.screenshot({ path: screenshotPath, fullPage: true });
      artifact(`shot-${id}`, 'png', `Full-page browser screenshot at ${width}px, ${theme} theme, ${layout} layout`, screenshotPath);
      screenshots.push({ id, path: screenshotPath });
      const statePath = await writeJson(`${id}.state.json`, state, `DOM state and overflow checks for ${id}`);
      const pass =
        state.bodyTheme === theme &&
        state.activeLayoutCount === 1 &&
        state.visibleLayouts.length === 1 &&
        state.visibleLayouts[0] === layout &&
        state.activeButtons.length === 1 &&
        state.activeButtons[0] === layout &&
        state.activeNotes.length === 1 &&
        state.activeNotes[0] === layout &&
        state.inactiveNotesVisible.length === 0 &&
        !state.horizontalOverflow;
      surfaceEvidence.push({
        scenarioId: `S-${id}`,
        criterionRef: 'layout-theme-responsive-state-no-horizontal-scroll',
        surface: 'static web prototype in local Chromium',
        exactInvocation: `file URL ${url}; viewport=${width}x950; click #theme-toggle until body[data-theme="${theme}"]; click button[data-view="${layout}"]; screenshot ${screenshotPath}; inspect DOM via Playwright evaluate`,
        verdict: pass ? 'PASS' : 'FAIL',
        artifactRefs: [`shot-${id}`, statePath.split('/').pop().replace(/\W+/g, '-').replace(/-json$/, '')],
      });
    }
  }
}

await page.setViewportSize({ width: 375, height: 900 });
await page.goto(url, { waitUntil: 'load' });
await page.evaluate(() => localStorage.clear());
await page.reload({ waitUntil: 'load' });
await page.keyboard.press('Tab');
const focusTrace = [];
for (let i = 0; i < 5; i += 1) {
  focusTrace.push(await page.evaluate(() => ({
    index: document.activeElement ? [...document.querySelectorAll('button')].indexOf(document.activeElement) : -1,
    text: document.activeElement?.textContent?.trim() || null,
    dataView: document.activeElement?.dataset?.view || null,
    id: document.activeElement?.id || null,
    matchesFocusVisible: document.activeElement?.matches?.(':focus-visible') || false,
    outline: document.activeElement ? getComputedStyle(document.activeElement).outline : null,
  })));
  await page.keyboard.press('Tab');
}

await page.goto(url, { waitUntil: 'load' });
await page.evaluate(() => localStorage.clear());
await page.reload({ waitUntil: 'load' });
await page.keyboard.press('Tab');
await page.keyboard.press('Enter');
const themeAfterKeyboard = await evaluateState('directory', 'night');
await page.keyboard.press('Tab');
await page.keyboard.press('Tab');
await page.keyboard.press('Enter');
const frontpageAfterKeyboard = await evaluateState('frontpage', 'night');
await page.keyboard.press('Tab');
await page.keyboard.press('Space');
const sectionsAfterKeyboard = await evaluateState('sections', 'night');
const keyboard = {
  invocation: `file URL ${url}; viewport=375x900; clear localStorage; Tab through buttons; Enter on #theme-toggle; Enter on B button; Space on C button`,
  focusTrace,
  themeAfterKeyboard,
  frontpageAfterKeyboard,
  sectionsAfterKeyboard,
};
const keyboardPath = await writeJson('keyboard-focus-and-activation.json', keyboard, 'Keyboard focus order, focus-visible evidence, and Enter/Space activation state trace');
const keyboardPass =
  focusTrace.slice(0, 4).map((f) => f.text).join('|') === '切换夜间墨纸|A · 今日目录|B · 头版 + 全览|C · 主题分版' &&
  focusTrace.slice(0, 4).every((f) => f.matchesFocusVisible && f.outline && !f.outline.startsWith('0px')) &&
  themeAfterKeyboard.bodyTheme === 'night' &&
  frontpageAfterKeyboard.visibleLayouts[0] === 'frontpage' &&
  frontpageAfterKeyboard.activeButtons[0] === 'frontpage' &&
  frontpageAfterKeyboard.activeNotes[0] === 'frontpage' &&
  sectionsAfterKeyboard.visibleLayouts[0] === 'sections' &&
  sectionsAfterKeyboard.activeButtons[0] === 'sections' &&
  sectionsAfterKeyboard.activeNotes[0] === 'sections';
surfaceEvidence.push({
  scenarioId: 'S-keyboard-375',
  criterionRef: 'keyboard-focus-behavior',
  surface: 'static web prototype in local Chromium',
  exactInvocation: keyboard.invocation,
  verdict: keyboardPass ? 'PASS' : 'FAIL',
  artifactRefs: [keyboardPath.split('/').pop().replace(/\W+/g, '-').replace(/-json$/, '')],
});

await page.setViewportSize({ width: 375, height: 900 });
await page.goto(url, { waitUntil: 'load' });
await page.evaluate(() => {
  localStorage.setItem('dailyreader-prototype-layout', 'bogus-layout');
  localStorage.setItem('dailyreader-prototype-theme', 'bogus-theme');
});
await page.reload({ waitUntil: 'load' });
const invalidStorageState = await evaluateState('directory', 'day');
const invalidStoragePath = await writeJson('invalid-localstorage-state.json', invalidStorageState, 'Adversarial invalid localStorage layout/theme state after reload');
const invalidStoragePass =
  invalidStorageState.bodyTheme === 'day' &&
  invalidStorageState.visibleLayouts.length === 1 &&
  invalidStorageState.visibleLayouts[0] === 'directory' &&
  invalidStorageState.activeButtons.length === 1 &&
  invalidStorageState.activeButtons[0] === 'directory' &&
  invalidStorageState.activeNotes.length === 1 &&
  invalidStorageState.activeNotes[0] === 'directory';
adversarialCases.push({
  scenarioId: 'A-invalid-localstorage',
  criterionRef: 'state-restoration-defensive-defaults',
  adversarialClass: 'tampered persisted layout/theme values',
  expectedBehavior: 'Invalid saved layout/theme should fall back to one valid default layout, one active button, one note, and day or night theme.',
  verdict: invalidStoragePass ? 'PASS' : 'FAIL',
  artifactRefs: [invalidStoragePath.split('/').pop().replace(/\W+/g, '-').replace(/-json$/, '')],
});

await page.setViewportSize({ width: 320, height: 900 });
await page.goto(url, { waitUntil: 'load' });
await page.evaluate(() => localStorage.clear());
for (let i = 0; i < 6; i += 1) {
  await page.click('#theme-toggle');
}
for (const layout of ['frontpage', 'sections', 'directory', 'sections', 'frontpage', 'directory']) {
  await page.click(`[data-view="${layout}"]`);
}
const rapidState = await evaluateState('directory', 'day');
const rapidPath = await writeJson('rapid-toggle-state.json', rapidState, 'Adversarial rapid click sequence on theme and layout controls at 320px');
const rapidPass =
  rapidState.bodyTheme === 'day' &&
  rapidState.visibleLayouts.length === 1 &&
  rapidState.visibleLayouts[0] === 'directory' &&
  rapidState.activeButtons.length === 1 &&
  rapidState.activeButtons[0] === 'directory' &&
  rapidState.activeNotes.length === 1 &&
  rapidState.activeNotes[0] === 'directory' &&
  !rapidState.horizontalOverflow;
adversarialCases.push({
  scenarioId: 'A-rapid-toggle-320',
  criterionRef: 'state-consistency-under-repeated-input',
  adversarialClass: 'rapid repeated theme and layout activation on narrow viewport',
  expectedBehavior: 'Controls remain deterministic: exactly one layout, one active button, one note, expected final theme, and no horizontal overflow.',
  verdict: rapidPass ? 'PASS' : 'FAIL',
  artifactRefs: [rapidPath.split('/').pop().replace(/\W+/g, '-').replace(/-json$/, '')],
});

const a11y = await page.evaluate(() => ({
  lang: document.documentElement.lang,
  viewport: document.querySelector('meta[name="viewport"]')?.content || null,
  navLabel: document.querySelector('.control-strip')?.getAttribute('aria-label') || null,
  readerSurfaceLabel: document.querySelector('.reader-surface')?.getAttribute('aria-label') || null,
  aiSearchLabel: document.querySelector('.reader-nav [aria-label="AI 搜索"]')?.getAttribute('aria-label') || null,
  buttons: [...document.querySelectorAll('button')].map((button) => ({
    text: button.textContent.trim(),
    type: button.getAttribute('type'),
    ariaPressed: button.getAttribute('aria-pressed'),
    disabled: button.disabled,
  })),
  h1Count: document.querySelectorAll('h1').length,
  unlabeledButtons: [...document.querySelectorAll('button')].filter((button) => !button.textContent.trim() && !button.getAttribute('aria-label')).length,
}));
const a11yPath = await writeJson('accessibility-basics.json', a11y, 'Accessibility basics inspection for labels, language, viewport, buttons, and heading');
const a11yPass =
  a11y.lang === 'zh-CN' &&
  a11y.viewport?.includes('width=device-width') &&
  a11y.navLabel &&
  a11y.readerSurfaceLabel &&
  a11y.aiSearchLabel &&
  a11y.h1Count === 1 &&
  a11y.unlabeledButtons === 0 &&
  a11y.buttons.every((button) => button.type === 'button' && (button.disabled || button.ariaPressed !== null));
surfaceEvidence.push({
  scenarioId: 'S-accessibility-basics',
  criterionRef: 'accessibility-basics',
  surface: 'static web prototype DOM in local Chromium',
  exactInvocation: `file URL ${url}; viewport=320x900 final state after rapid toggle; inspect lang/meta/labels/button types/aria-pressed/H1 via Playwright evaluate`,
  verdict: a11yPass ? 'PASS' : 'FAIL',
  artifactRefs: [a11yPath.split('/').pop().replace(/\W+/g, '-').replace(/-json$/, '')],
});

const localFiles = [htmlPath, cssPath];
const sourceStats = [];
for (const filePath of localFiles) {
  const stat = await fs.stat(filePath);
  sourceStats.push({ path: filePath, bytes: stat.size, mtime: stat.mtime.toISOString() });
}
const runtime = {
  invocation: `node .omo/evidence/homepage-prototype-qa/run_homepage_prototype_qa.mjs from ${repoRoot}`,
  playwright: 'chromium',
  url,
  sourceStats,
  consoleEvents,
  pageErrors,
  failedRequests,
  networkRequests,
  nonFileRequests: networkRequests.filter((req) => !req.url.startsWith('file://') && req.url !== 'about:blank'),
  screenshots,
};
const runtimePath = await writeJson('runtime-browser-log.json', runtime, 'Browser runtime log, source mtimes, console/page errors, failed requests, and network request list');
surfaceEvidence.push({
  scenarioId: 'S-runtime-local-only',
  criterionRef: 'no-page-errors-no-network-dependency',
  surface: 'static web prototype in local Chromium',
  exactInvocation: `Playwright Chromium page.goto("${url}", waitUntil=load); listeners for console/pageerror/request/requestfailed during all tested states`,
  verdict: pageErrors.length === 0 && failedRequests.length === 0 && runtime.nonFileRequests.length === 0 ? 'PASS' : 'FAIL',
  artifactRefs: [runtimePath.split('/').pop().replace(/\W+/g, '-').replace(/-json$/, '')],
});

await browser.close();

const manualQa = { surfaceEvidence, adversarialCases, artifactRefs: artifacts };
await fs.writeFile(path.join(evidenceDir, 'manualQa.json'), JSON.stringify(manualQa, null, 2));
console.log(JSON.stringify({
  verdict: [...surfaceEvidence, ...adversarialCases].every((row) => row.verdict === 'PASS') ? 'PASS' : 'FAIL',
  evidenceDir,
  counts: {
    surfaceEvidence: surfaceEvidence.length,
    adversarialCases: adversarialCases.length,
    artifacts: artifacts.length + 1,
  },
  failures: [...surfaceEvidence, ...adversarialCases].filter((row) => row.verdict !== 'PASS'),
}, null, 2));
