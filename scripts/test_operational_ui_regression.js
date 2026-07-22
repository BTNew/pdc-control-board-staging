'use strict';
const { chromium } = require(process.env.PDC_PLAYWRIGHT_PATH || 'playwright-core');
const url = process.env.PDC_UI_REGRESSION_URL || 'http://127.0.0.1:8106/test-75.html';
const chromePath = process.env.PDC_CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const views = ['dashboard','workflow','parts','emailreview','sublet','rft','completed','deleted','backend','lists','import'];
(async () => {
  const browser = await chromium.launch({ executablePath: chromePath, headless: true });
  const results = [];
  for (const viewport of [{ width: 1600, height: 1000 }, { width: 1024, height: 768 }]) {
    const page = await browser.newPage({ viewport });
    const errors = [];
    page.on('pageerror', error => errors.push(String(error.message || error)));
    await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
    await page.evaluate(() => {
      const vehicle = typeof partsDepartmentRows === 'function' ? partsDepartmentRows()[0] : null;
      if (vehicle) vehicle.pdcPartsWorstEta = '2026-08-15';
    });
    for (const view of views) {
      await page.locator(`.nav-item[data-view="${view}"]`).click();
      await page.waitForFunction(expected => document.querySelector('.view.active')?.id === expected, view);
      const state = await page.evaluate(expected => {
        const active = document.querySelector('.view.active');
        const partsWrap = expected === 'parts' ? document.querySelector('.parts-table-wrap') : null;
        const wrapStyle = partsWrap ? getComputedStyle(partsWrap) : null;
        const partsCells = expected === 'parts' ? [...document.querySelectorAll('.parts-queue-row td')] : [];
        const emailSales = expected === 'parts' ? document.querySelector('[data-parts-eta-email]') : null;
        const statusOverlap = expected === 'parts' ? [...document.querySelectorAll('.parts-queue-row td:first-child')].some(cell => {
          const pill = cell.querySelector('.parts-status-pill');
          if (!pill) return false;
          return pill.getBoundingClientRect().right > cell.getBoundingClientRect().right + 1;
        }) : false;
        return {
          view: active?.id || '',
          bodyHorizontalOverflow: Math.max(document.body.scrollWidth, document.documentElement.scrollWidth) - document.documentElement.clientWidth,
          partsNestedVerticalScroll: Boolean(partsWrap && partsWrap.scrollHeight > partsWrap.clientHeight + 1 && /auto|scroll/.test(wrapStyle.overflowY)),
          partsCellOverflow: partsCells.reduce((max, cell) => Math.max(max, cell.scrollWidth - cell.clientWidth), 0),
          partsStatusOverlap: statusOverlap,
          emailSalesAtRowEnd: Boolean(emailSales && emailSales.closest('td') === emailSales.closest('tr')?.lastElementChild),
          emptyActiveView: !active || active.getBoundingClientRect().height < 60,
        };
      }, view);
      if (state.bodyHorizontalOverflow > 2) throw new Error(`${viewport.width}px ${view}: page overflows horizontally by ${state.bodyHorizontalOverflow}px`);
      if (state.partsNestedVerticalScroll) throw new Error(`${viewport.width}px Parts: nested vertical table scrolling remains`);
      if (state.partsCellOverflow > 1) throw new Error(`${viewport.width}px Parts: table cell content overflows by ${state.partsCellOverflow}px`);
      if (state.partsStatusOverlap) throw new Error(`${viewport.width}px Parts: status pill overlaps the next column`);
      if (view === 'parts' && !state.emailSalesAtRowEnd) throw new Error(`${viewport.width}px Parts: compact Email sales action is not demonstrated at row end`);
      if (state.emptyActiveView) throw new Error(`${viewport.width}px ${view}: active view is unexpectedly empty`);
      results.push({ viewport: viewport.width, ...state });
    }
    if (errors.length) throw new Error(`Browser errors at ${viewport.width}px: ${errors.join('; ')}`);
    await page.close();
  }
  await browser.close();
  console.log(JSON.stringify({ schema: 'pdc.operational-ui-regression/v1', views: views.length, checks: results.length, passed: true, results }, null, 2));
})().catch(error => { console.error(error); process.exit(1); });
