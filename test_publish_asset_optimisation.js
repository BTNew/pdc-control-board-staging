/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');
const builder = require('./scripts/build_pages_runtime.js');
// Both parsers are already pinned transitive dependencies of the publish tools.
const acorn = createRequire(require.resolve('terser'))('acorn');
const cssTree = createRequire(require.resolve('csso'))('css-tree');

function tree(source) {
  const normalise = (value, tagged = false) => {
    if (typeof value === 'bigint') return { bigint: value.toString() };
    if (Array.isArray(value)) return value.map(child => normalise(child, tagged));
    if (!value || typeof value !== 'object') return value;
    const out = {};
    // The printer can turn an arrow's single return into its expression form.
    if (value.type === 'ArrowFunctionExpression' && value.body.type === 'BlockStatement' && value.body.body.length === 1 && value.body.body[0].type === 'ReturnStatement' && value.body.body[0].argument) {
      value = { ...value, expression: true, body: value.body.body[0].argument };
    }
    for (const [key, child] of Object.entries(value)) {
      if (key === 'flags' && typeof child === 'string') { out[key] = child.split('').sort().join(''); continue; }
      if (['start', 'end', 'shorthand'].includes(key) || (key === 'raw' && value.type === 'Literal')) continue;
      // { foo } / { foo: foo } and { "foo": x } / { foo: x } are equivalent
      // print forms. Keep computed keys, methods, values and property order.
      if (key === 'key' && value.type === 'Property' && !value.computed && ['Identifier', 'Literal'].includes(child.type)) {
        out.key = { type: 'StaticPropertyName', value: String(child.type === 'Identifier' ? child.name : child.value) };
      } else if (key === 'value' && value.type === 'TemplateElement' && !tagged) {
        out.value = { cooked: child.cooked };
      } else out[key] = normalise(child, tagged || (value.type === 'TaggedTemplateExpression' && key === 'quasi'));
    }
    return out;
  };
  return normalise(acorn.parse(source, { ecmaVersion: 'latest' }));
}
function publish(filename, source) {
  return builder.publishedAsset(filename, Buffer.from(source))[0][1].toString('utf8');
}

test('every newly minified real script retains its complete parsed program and a recoverable source map', () => {
  const scripts = builder.PUBLISHED_MINIFIED_ASSETS.filter(file => file.endsWith('.js') && file !== 'app.js');
  assert.ok(scripts.includes('workshop-planner.js'));
  assert.ok(scripts.includes('pdc-ai-intake-review.js'));
  for (const filename of scripts) {
    const source = fs.readFileSync(path.join(__dirname, filename), 'utf8');
    const outputs = builder.publishedAsset(filename, Buffer.from(source));
    const minified = outputs[0][1].toString('utf8');
    const digest = value => require('node:crypto').createHash('sha256').update(JSON.stringify(tree(value))).digest('hex');
    assert.equal(digest(minified), digest(source), filename + ': formatting must not change executable syntax');
    const map = JSON.parse(outputs[1][1]);
    assert.equal(map.sourcesContent[0], source, filename + ': original source is recoverable');
    assert.equal(map.file, path.posix.basename(filename));
  }
});

test('classic scripts retain shared lexical bindings, globals, names, wrappers and installed execution order', () => {
  const scripts = [
    ['workshop-data-service.js', 'const station = "HOIST"; let calls = 0; function scopedRead(value) { calls++; return station + ":" + value; } window.scopedRead = scopedRead;'],
    ['pdc-ai-intake-review.js', 'const original = window.scopedRead; window.scopedRead = function reviewedRead(value) { return original(value) + ":review"; }; window.installOrder.push("review");'],
    ['workshop-planner.js', 'window.installOrder.push("planner"); window.result = [window.scopedRead("fixture"), station, calls, scopedRead.name, window.scopedRead.name];']
  ];
  const run = transformed => {
    const context = vm.createContext({ window: { installOrder: [] } });
    for (const [filename, source] of scripts) vm.runInContext(transformed ? publish(filename, source) : source, context, { filename });
    return JSON.parse(JSON.stringify(context.window));
  };
  const expected = run(false);
  assert.deepEqual(run(true), expected);
  assert.deepEqual(expected.installOrder, ['review', 'planner']);
  assert.deepEqual(expected.result, ['HOIST:fixture:review', 'HOIST', 1, 'scopedRead', 'reviewedRead']);
});

test('new stylesheet output retains selector and declaration order, including custom properties and important overrides', () => {
  const source = '.vehicle { --station-colour: rgb(20, 30, 40); color: var(--station-colour); padding: 0px; }\n.vehicle { color: red !important; }\n@media (max-width: 700px) { .vehicle { display: grid; } }';
  const css = publish('workshop-planner.css', source);
  const outline = text => {
    const result = [];
    cssTree.walk(cssTree.parse(text), node => {
      if (node.type === 'Rule') result.push(['rule', cssTree.generate(node.prelude)]);
      if (node.type === 'Declaration') result.push(['property', node.property, Boolean(node.important)]);
      if (node.type === 'Atrule') result.push(['at', node.name, cssTree.generate(node.prelude)]);
    });
    return result;
  };
  assert.deepEqual(outline(css), outline(source));
  assert.match(css, /var\(--station-colour\)/);
  assert.match(css, /color:red!important/);
});

test('vendor bundles and frozen Department 135 assets remain byte-identical and cannot acquire generated maps', () => {
  for (const filename of builder.RUNTIME_FILES.filter(file => /^(?:vendor|karratha|scripts)\//.test(file))) {
    assert.equal(builder.PUBLISHED_MINIFIED_ASSETS.includes(filename), false);
    const bytes = fs.readFileSync(path.join(__dirname, filename));
    const outputs = builder.publishedAsset(filename, bytes);
    assert.equal(outputs.length, 1);
    assert.equal(outputs[0][0], filename);
    assert.deepEqual(outputs[0][1], bytes);
    assert.equal(builder.PUBLISHED_SOURCE_MAPS.includes(filename + '.map'), false);
  }
});


test('copyright notices survive new JavaScript and stylesheet minification without encoding damage', () => {
  const notice = '/* \u00a9 2026 Example copyright fixture. */';
  for (const [filename, body] of [['workshop-planner.js', 'window.fixture = true;'], ['workshop-planner.css', '.fixture { color: red; }']]) {
    const output = publish(filename, notice + '\n' + body);
    assert.ok(output.includes(notice), filename + ': copyright notice retained');
    assert.equal(output.includes('\u00c2\u00a9'), false, filename + ': no double-encoded copyright');
  }
});
