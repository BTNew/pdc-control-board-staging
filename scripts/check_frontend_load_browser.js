/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// Headless check of the built Pages artifact. Not part of node --test test_*.js
// because the GitHub runner does not provide Chrome.
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const builder = require('./build_pages_runtime.js');

const sourceRoot = path.resolve(__dirname, '..');
const outputRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'pdc-frontend-load-'));
const port = 8766;

function getJson(url) {
  return new Promise((resolve, reject) => {
    http.get(url, response => {
      let body = '';
      response.on('data', chunk => { body += chunk; });
      response.on('end', () => resolve(JSON.parse(body)));
    }).on('error', reject);
  });
}

function listen(root) {
  const server = http.createServer((request, response) => {
    const url = new URL(request.url, 'http://127.0.0.1');
    let relative = decodeURIComponent(url.pathname).replace(/^\/+/, '');
    if (!relative || relative.endsWith('/')) relative += 'index.html';
    const target = path.join(root, relative);
    if (!target.startsWith(root + path.sep) && target !== root) {
      response.writeHead(403).end();
      return;
    }
    fs.readFile(target, (error, bytes) => {
      if (error) { response.writeHead(404).end('missing'); return; }
      response.writeHead(200).end(bytes);
    });
  });
  return new Promise(resolve => server.listen(port, '127.0.0.1', () => resolve(server)));
}

async function openPage(browserWs, url) {
  let id = 0;
  const pending = new Map();
  const ws = new WebSocket(browserWs);
  ws.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      pending.get(message.id)(message);
      pending.delete(message.id);
    }
  });
  const send = (method, params) => new Promise(resolve => {
    const messageId = ++id;
    pending.set(messageId, resolve);
    ws.send(JSON.stringify({ id: messageId, method, params }));
  });
  await new Promise(resolve => ws.addEventListener('open', resolve));
  const created = await send('Target.createTarget', { url: 'about:blank' });
  const targets = await getJson('http://127.0.0.1:9224/json/list');
  const page = targets.find(target => target.id === created.result.targetId);
  const pageWs = new WebSocket(page.webSocketDebuggerUrl);
  let pageId = 0;
  const pagePending = new Map();
  const events = [];
  pageWs.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (message.id && pagePending.has(message.id)) {
      pagePending.get(message.id)(message);
      pagePending.delete(message.id);
    } else if (message.method) events.push(message);
  });
  const pageSend = (method, params) => new Promise(resolve => {
    const messageId = ++pageId;
    pagePending.set(messageId, resolve);
    pageWs.send(JSON.stringify({ id: messageId, method, params }));
  });
  await new Promise(resolve => pageWs.addEventListener('open', resolve));
  await pageSend('Page.enable');
  await pageSend('Runtime.enable');
  await pageSend('Network.enable');
  const loaded = new Promise(resolve => {
    const timer = setTimeout(() => resolve('timeout'), 15000);
    const onMessage = event => {
      const message = JSON.parse(event.data);
      if (message.method === 'Page.domContentEventFired') {
        clearTimeout(timer);
        pageWs.removeEventListener('message', onMessage);
        resolve('domcontentloaded');
      }
    };
    pageWs.addEventListener('message', onMessage);
  });
  await pageSend('Page.navigate', { url });
  const loadState = await loaded;
  await new Promise(resolve => setTimeout(resolve, 500));
  const exceptions = events
    .filter(event => event.method === 'Runtime.exceptionThrown')
    .map(event => event.params.exceptionDetails.exception?.description || event.params.exceptionDetails.text)
    .slice(0, 5);
  const evaluated = await pageSend('Runtime.evaluate', {
    expression: `JSON.stringify({
      title: document.querySelector('h1') && document.querySelector('h1').textContent,
      order: window.PDC_DEFERRED_SCRIPT_ORDER,
      auth: typeof window.PDC_AUTH_READY,
      init: typeof window.init,
      stage2b: typeof window.PDC_STAGE2B_C4_EXPORT,
      assessment: typeof window.PDC_STAGING_BROWSER_ASSESSMENT,
      banner: !!document.querySelector('.startup-error-banner'),
      shellHidden: document.querySelector('#app-shell') ? getComputedStyle(document.querySelector('#app-shell')).display : null
    })`,
    returnByValue: true
  });
  const scripts = events
    .filter(event => event.method === 'Network.requestWillBeSent' && /\.js(?:\?|$)/.test(event.params.request.url))
    .map(event => new URL(event.params.request.url).pathname);
  ws.close();
  pageWs.close();
  return { loadState, value: JSON.parse(evaluated.result.result.value), scripts, exceptions };
}

async function main() {
  const built = builder.buildRuntimeArtifact(sourceRoot, outputRoot);
  const server = await listen(outputRoot);
  const chrome = spawn('google-chrome', [
    '--headless=new', '--disable-gpu', '--no-sandbox',
    '--remote-debugging-port=9224', '--user-data-dir=' + path.join(outputRoot, 'chrome-profile'),
    'about:blank'
  ], { stdio: 'ignore' });
  try {
    let version;
    for (let attempt = 0; attempt < 20; attempt += 1) {
      try { version = await getJson('http://127.0.0.1:9224/json/version'); break; }
      catch (error) { await new Promise(resolve => setTimeout(resolve, 250)); }
    }
    if (!version) throw new Error('Chrome debugging port did not open');
    const board = await openPage(version.webSocketDebuggerUrl, 'http://127.0.0.1:' + port + '/');
    const karratha = await openPage(version.webSocketDebuggerUrl, 'http://127.0.0.1:' + port + '/karratha/');
    const report = {
      files: built.fileCount,
      bytes: built.byteCount,
      appSource: fs.statSync(path.join(sourceRoot, 'app.js')).size,
      appPublished: fs.statSync(path.join(outputRoot, 'app.js')).size,
      cssSource: fs.statSync(path.join(sourceRoot, 'styles.css')).size,
      cssPublished: fs.statSync(path.join(outputRoot, 'styles.css')).size,
      board, karratha
    };
    console.log(JSON.stringify(report, null, 2));
    const dead = ['/data-staging-empty.js', '/scripts/stage2b_c4_browser_export.js', '/staging-browser-assessment.js'];
    if (board.loadState !== 'domcontentloaded') throw new Error('Live board did not reach DOMContentLoaded');
    if (board.value.order !== true || board.value.auth !== 'object' || board.value.init !== 'function') throw new Error('Live board boot order was not preserved');
    if (board.value.banner) throw new Error('Live board rendered a startup error');
    if (!/PDC staff sign-in|Checking secure sign-in/.test(board.value.title || '')) throw new Error('Live board did not show the sign-in gate');
    if (board.value.stage2b !== 'undefined' || board.value.assessment !== 'undefined') throw new Error('A removed diagnostic script still ran');
    if (dead.some(file => board.scripts.includes(file))) throw new Error('A removed diagnostic script was requested');
    if (!/Department 135 is paused/.test(karratha.value.title || '')) throw new Error('Department 135 page did not stay paused');
    if (karratha.scripts.some(file => file.startsWith('/karratha/') && !file.endsWith('/pd135-visibility.js') && !file.endsWith('/pd135-board-loader.js'))) {
      throw new Error('Department 135 downloaded a board script: ' + karratha.scripts.join(', '));
    }
  } finally {
    chrome.kill();
    server.close();
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
