'use strict';

const assert = require('assert');
const fs = require('fs');
const http = require('http');
const path = require('path');
let chromium;
for (const candidate of [
  './_staging_test_tools/node-playwright/node_modules/playwright-core',
  'C:/Users/nwmgr/AppData/Local/Temp/pdc-phase-a-playwright/node_modules/playwright',
]) {
  try { ({ chromium } = require(candidate)); break; } catch (_) {}
}
if (!chromium) throw new Error('Playwright is required for the rendered Parts layout regression.');

const root = __dirname;
const mime = { '.html':'text/html', '.js':'application/javascript', '.css':'text/css', '.svg':'image/svg+xml', '.png':'image/png' };
const server = http.createServer((request, response) => {
  const raw = decodeURIComponent(String(request.url || '/').split('?')[0]);
  const relative = raw === '/' ? 'test-75.html' : raw.replace(/^\/+/, '');
  const file = path.resolve(root, relative);
  if (!file.startsWith(path.resolve(root)) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    response.writeHead(404); response.end('not found'); return;
  }
  response.writeHead(200, { 'Content-Type': `${mime[path.extname(file)] || 'application/octet-stream'}; charset=utf-8` });
  response.end(fs.readFileSync(file));
});

(async () => {
  await new Promise((resolve, reject) => server.listen(0, '127.0.0.1', error => error ? reject(error) : resolve()));
  const browser = await chromium.launch({ headless: true, executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe' });
  try {
    for (const viewport of [{ width: 1920, height: 1080 }, { width: 1264, height: 625 }]) {
      const page = await browser.newPage({ viewport });

      const origin = `http://127.0.0.1:${server.address().port}`;
      await page.goto(`${origin}/test-75.html`, { waitUntil: 'networkidle' });
      await page.click('[data-view="parts"]');
      const eta = page.locator('[data-parts-worst-eta]').first();
      if (await eta.count()) {
        await eta.fill('2026-08-01');
        await eta.dispatchEvent('change');
        await page.waitForTimeout(100);
      }
      const metrics = await page.evaluate(() => {
        const wrap = document.querySelector('.parts-queue-wrap');
        const table = document.querySelector('.parts-queue-table');
        const email = document.querySelector('.parts-email-sales-secondary');
        const actionGroup = document.querySelector('.parts-action-group');
        const emailRow = email && email.closest('tr');
        const emailRect = email && email.getBoundingClientRect();
        const visibleBottom = Math.max(0, ...Array.from(document.querySelectorAll('body *')).map(element => {
          const rect = element.getBoundingClientRect();
          const style = getComputedStyle(element);
          return style.display === 'none' || style.visibility === 'hidden' || rect.height <= 0 ? 0 : rect.bottom;
        }));
        return {
          wrapperClientWidth: wrap && wrap.clientWidth,
          wrapperScrollWidth: wrap && wrap.scrollWidth,
          wrapperClientHeight: wrap && wrap.clientHeight,
          wrapperScrollHeight: wrap && wrap.scrollHeight,
          tableWidth: table && table.getBoundingClientRect().width,
          emailWidth: emailRect && emailRect.width,
          emailHeight: emailRect && emailRect.height,
          emailRowHeight: emailRow && emailRow.getBoundingClientRect().height,
          rootScrollHeight: document.documentElement.scrollHeight,
          rootClientWidth: document.documentElement.clientWidth,
          rootScrollWidth: document.documentElement.scrollWidth,
          bodyHeight: document.body.getBoundingClientRect().height,
          viewportHeight: innerHeight,
          visibleBottom,
          actionDisplay: actionGroup && getComputedStyle(actionGroup).display,
          emailPresent: Boolean(email),
          wrapperOverflow: wrap && getComputedStyle(wrap).overflow,
          wrapperOverflowX: wrap && getComputedStyle(wrap).overflowX,
          wrapperOverflowY: wrap && getComputedStyle(wrap).overflowY,
          wrapperPosition: wrap && getComputedStyle(wrap).position,
          deepestElements: Array.from(document.querySelectorAll('body *')).map(element => {
            const rect = element.getBoundingClientRect();
            const style = getComputedStyle(element);
            return { tag: element.tagName, id: element.id, className: String(element.className || '').slice(0, 100), top: rect.top, bottom: rect.bottom, height: rect.height, position: style.position, display: style.display, visibility: style.visibility };
          }).filter(item => item.display !== 'none' && item.visibility !== 'hidden' && item.height > 0).sort((a, b) => b.bottom - a.bottom).slice(0, 8),
        };
      });
      assert.ok(metrics.wrapperClientWidth > 0 && metrics.tableWidth > 0, `Parts table rendered at ${viewport.width}px`);
      assert.ok(metrics.rootScrollWidth <= metrics.rootClientWidth + 1, `the page itself has no horizontal overflow at ${viewport.width}px: ${JSON.stringify(metrics)}`);
      if (metrics.wrapperScrollWidth > metrics.wrapperClientWidth + 1) {
        assert.ok(['auto', 'scroll'].includes(metrics.wrapperOverflowX), `wide tables stay contained in their horizontal scroll wrapper at ${viewport.width}px: ${JSON.stringify(metrics)}`);
      }
      assert.strictEqual(metrics.actionDisplay, 'flex', `actions use flex grouping at ${viewport.width}px`);
      if (metrics.emailPresent) {
        assert.ok(metrics.emailWidth >= 60 && metrics.emailHeight <= 36, `Email sales stays compact at ${viewport.width}px: ${JSON.stringify(metrics)}`);
        assert.ok(metrics.emailRowHeight <= 78, `Email sales row remains compact at ${viewport.width}px: ${metrics.emailRowHeight}`);
      }
      assert.ok(metrics.rootScrollHeight <= metrics.visibleBottom + 24, `continuous Parts table has no blank root region after visible content at ${viewport.width}px: ${JSON.stringify(metrics)}`);
      assert.ok(metrics.wrapperScrollHeight >= metrics.wrapperClientHeight, 'long Parts queues remain fully represented by the continuous table wrapper');
      await page.screenshot({ path: path.join(process.env.TEMP || root, `pdc-parts-${viewport.width}x${viewport.height}.png`), fullPage: false });
      await page.close();
    }
    console.log('Rendered Parts/Vehicle Locations layout regression passed at 1920x1080 and 1264x625.');
  } finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
