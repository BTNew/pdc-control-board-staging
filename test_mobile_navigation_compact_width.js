const fs = require('fs');
const assert = require('assert');

const css = fs.readFileSync('styles.css', 'utf8').replace(/\r\n/g, '\n');
const html = fs.readFileSync('index.html', 'utf8').replace(/\r\n/g, '\n');

const mobileBlock = css.match(/@media \(max-width: 820px\) \{\n  \.app-shell \{ grid-template-columns: 1fr !important; \}[\s\S]*?\n\}/);
assert(mobileBlock, 'mobile navigation media block must exist');
const block = mobileBlock[0];
assert(block.includes('width: 72px !important;'), 'mobile nav items must have a bounded width');
assert(block.includes('max-width: 72px !important;'), 'later width rules must not stretch mobile nav items');
assert(block.includes('flex-basis: 72px !important;'), 'mobile nav flex basis must remain compact');
assert(block.includes('min-width: 72px;'), 'mobile nav touch target width must remain at least 72px');
assert(html.includes('styles.css?v=2026.08.29.736-rft-final-controls'), 'staging shell must cache-bust the corrected mobile navigation CSS');
console.log('PASS mobile navigation compact-width regression');
