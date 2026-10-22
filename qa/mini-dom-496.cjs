/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r496 (F109) test helper: a small in-memory DOM (HTML parser, the CSS selectors the slide-out uses, events with
// bubbling, select / option / input values). Tests only; never shipped to the browser. No network, no storage.
const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr']);
const decode = text => String(text).replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
const encodeAttr = text => String(text).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
const encodeText = text => String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const camel = name => name.replace(/-([a-z])/g, (_, ch) => ch.toUpperCase());
const kebab = name => name.replace(/[A-Z]/g, ch => `-${ch.toLowerCase()}`);

function createDocument() {
  class Node {
    constructor(type) { this.nodeType = type; this.parentNode = null; }
    get parentElement() { return this.parentNode && this.parentNode.nodeType === 1 ? this.parentNode : null; }
    get isConnected() { let n = this; while (n.parentNode) n = n.parentNode; return n === doc.documentElement; }
    remove() { if (this.parentNode) this.parentNode.childNodes.splice(this.parentNode.childNodes.indexOf(this), 1); this.parentNode = null; }
  }
  class Text extends Node { constructor(text) { super(3); this.data = text; } get textContent() { return this.data; } set textContent(v) { this.data = String(v); } }
  class Element extends Node {
    constructor(tag) {
      super(1); this.tagName = tag.toUpperCase(); this.localName = tag.toLowerCase(); this.attrs = new Map(); this.childNodes = []; this.listeners = {};
      this.scrollTop = 0; this.scrollWidth = 0; this.clientWidth = 0; this._value = null; this._selected = null; this.style = {};
      const el = this;
      this.dataset = new Proxy({}, {
        get: (_, key) => (typeof key === 'string' && el.attrs.has(`data-${kebab(key)}`) ? el.attrs.get(`data-${kebab(key)}`) : undefined),
        set: (_, key, value) => { el.attrs.set(`data-${kebab(key)}`, String(value)); return true; },
        deleteProperty: (_, key) => { el.attrs.delete(`data-${kebab(key)}`); return true; },
        has: (_, key) => el.attrs.has(`data-${kebab(key)}`),
        ownKeys: () => [...el.attrs.keys()].filter(k => k.startsWith('data-')).map(k => camel(k.slice(5))),
        getOwnPropertyDescriptor: (_, key) => (el.attrs.has(`data-${kebab(key)}`) ? { enumerable: true, configurable: true, value: el.attrs.get(`data-${kebab(key)}`) } : undefined),
      });
      this.classList = {
        list: () => (el.attrs.get('class') || '').split(/\s+/).filter(Boolean),
        contains: n => el.classList.list().includes(n),
        add: (...names) => { const s = new Set(el.classList.list()); names.forEach(n => s.add(n)); el.attrs.set('class', [...s].join(' ')); },
        remove: (...names) => { el.attrs.set('class', el.classList.list().filter(n => !names.includes(n)).join(' ')); },
        toggle: (n, force) => { const on = force === undefined ? !el.classList.contains(n) : !!force; if (on) el.classList.add(n); else el.classList.remove(n); return on; },
      };
    }
    get children() { return this.childNodes.filter(n => n.nodeType === 1); }
    get id() { return this.attrs.get('id') || ''; } set id(v) { this.attrs.set('id', String(v)); }
    get className() { return this.attrs.get('class') || ''; } set className(v) { this.attrs.set('class', String(v)); }
    get title() { return this.attrs.get('title') || ''; } set title(v) { this.attrs.set('title', String(v)); }
    get type() { return this.attrs.get('type') || ''; } set type(v) { this.attrs.set('type', String(v)); }
    get rel() { return this.attrs.get('rel') || ''; } set rel(v) { this.attrs.set('rel', String(v)); }
    get href() { return this.attrs.get('href') || ''; } set href(v) { this.attrs.set('href', String(v)); }
    get src() { return this.attrs.get('src') || ''; } set src(v) { this.attrs.set('src', String(v)); }
    get tabIndex() { return Number(this.attrs.get('tabindex') ?? -1); } set tabIndex(v) { this.attrs.set('tabindex', String(v)); }
    get hidden() { return this.attrs.has('hidden'); } set hidden(v) { if (v) this.attrs.set('hidden', ''); else this.attrs.delete('hidden'); }
    get disabled() { return this.attrs.has('disabled'); } set disabled(v) { if (v) this.attrs.set('disabled', ''); else this.attrs.delete('disabled'); }
    get open() { return this.attrs.has('open'); } set open(v) { if (v) this.attrs.set('open', ''); else this.attrs.delete('open'); }
    getAttribute(n) { return this.attrs.has(n) ? this.attrs.get(n) : null; }
    setAttribute(n, v) { this.attrs.set(n, String(v)); }
    hasAttribute(n) { return this.attrs.has(n); }
    removeAttribute(n) { this.attrs.delete(n); }
    // select / option / input
    get options() { return this.querySelectorAll('option'); }
    get defaultSelected() { return this.attrs.has('selected'); }
    get selected() { return this._selected ?? this.attrs.has('selected'); } set selected(v) { this._selected = !!v; }
    get value() {
      if (this.localName === 'select') { const opts = this.options; const hit = opts.find(o => o.selected) || opts[0]; return hit ? hit.value : ''; }
      if (this.localName === 'option') return this.attrs.has('value') ? this.attrs.get('value') : this.textContent;
      return this._value ?? this.attrs.get('value') ?? '';
    }
    set value(v) {
      if (this.localName === 'select') { const opts = this.options; const hit = opts.find(o => o.value === String(v)); if (hit) opts.forEach(o => { o._selected = o === hit; }); return; }
      this._value = String(v);
    }
    get textContent() { return this.childNodes.map(n => n.textContent).join(''); }
    set textContent(v) { this.childNodes.forEach(n => { n.parentNode = null; }); this.childNodes = []; if (String(v)) this.appendChild(new Text(String(v))); }
    get innerText() { return this.textContent; }
    get innerHTML() { return this.childNodes.map(serialize).join(''); }
    set innerHTML(html) { this.childNodes.forEach(n => { n.parentNode = null; }); this.childNodes = []; parseInto(this, String(html)); }
    get outerHTML() { return serialize(this); }
    appendChild(child) { child.remove(); child.parentNode = this; this.childNodes.push(child); return child; }
    prepend(child) { child.remove(); child.parentNode = this; this.childNodes.unshift(child); }
    after(child) { const p = this.parentNode; if (!p) return; child.remove(); child.parentNode = p; p.childNodes.splice(p.childNodes.indexOf(this) + 1, 0, child); }
    replaceWith(child) { const p = this.parentNode; if (!p) return; child.remove(); child.parentNode = p; p.childNodes.splice(p.childNodes.indexOf(this), 1, child); this.parentNode = null; }
    replaceChildren(...kids) { this.childNodes.forEach(n => { n.parentNode = null; }); this.childNodes = []; kids.forEach(k => this.appendChild(k)); }
    insertAdjacentHTML(where, html) {
      const holder = new Element('div'); parseInto(holder, String(html)); const nodes = [...holder.childNodes];
      if (where === 'afterbegin') nodes.reverse().forEach(n => this.prepend(n));
      else if (where === 'beforeend') nodes.forEach(n => this.appendChild(n));
      else if (where === 'afterend') { let ref = this; nodes.forEach(n => { ref.after(n); ref = n; }); }
      else throw new Error(`insertAdjacentHTML ${where} not supported`);
    }
    focus() { doc.activeElement = this; }
    addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); }
    dispatch(type, init = {}) {
      let stopped = false; const event = { type, target: this, ...init, stopPropagation() { stopped = true; }, preventDefault() { this.defaultPrevented = true; } };
      const results = [];
      for (let node = this; node && !stopped; node = node.parentNode) for (const fn of node.listeners?.[type] || []) results.push(fn.call(node, event));
      return results;
    }
    matches(selector) { return splitList(selector).some(complex => matchComplex(this, parseComplex(complex), this)); }
    closest(selector) { for (let n = this; n && n.nodeType === 1; n = n.parentNode) if (n.matches(selector)) return n; return null; }
    querySelectorAll(selector) {
      const out = []; const lists = splitList(selector).map(parseComplex);
      const walk = node => { for (const child of node.childNodes) if (child.nodeType === 1) { if (lists.some(l => matchComplex(child, l, this))) out.push(child); walk(child); } };
      walk(this); return out;
    }
    querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
    getBoundingClientRect() { return { width: 0, height: 0, top: 0, left: 0, right: 0, bottom: 0 }; }
  }
  function serialize(node) {
    if (node.nodeType === 3) return encodeText(node.data);
    const attrs = [...node.attrs].map(([k, v]) => (v === '' ? ` ${k}` : ` ${k}="${encodeAttr(v)}"`)).join('');
    if (VOID.has(node.localName)) return `<${node.localName}${attrs}>`;
    return `<${node.localName}${attrs}>${node.childNodes.map(serialize).join('')}</${node.localName}>`;
  }
  function parseInto(parent, html) {
    const re = /<!--[\s\S]*?-->|<\/([a-zA-Z][\w-]*)\s*>|<([a-zA-Z][\w-]*)((?:\s+[^\s=>\/]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?)*)\s*(\/?)>|([^<]+|<)/g;
    let current = parent; let m;
    while ((m = re.exec(html))) {
      if (m[0].startsWith('<!--')) continue;
      if (m[1]) { const tag = m[1].toLowerCase(); let n = current; while (n !== parent && n.localName !== tag) n = n.parentNode; if (n !== parent) current = n.parentNode; continue; }
      if (m[2]) {
        const el = new Element(m[2]);
        for (const a of (m[3] || '').matchAll(/([^\s=>\/]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g)) el.attrs.set(a[1].toLowerCase(), decode(a[2] ?? a[3] ?? a[4] ?? ''));
        current.appendChild(el);
        if (!VOID.has(el.localName) && !m[4]) current = el;
        continue;
      }
      if (m[5]) current.appendChild(new Text(decode(m[5])));
    }
  }
  // Selectors: comma lists; descendant and '>' combinators; tag, #id, .class, [attr], [attr="v"], :not(simple), :scope.
  function splitList(sel) { const out = []; let depth = 0, quote = '', cur = ''; for (const ch of sel) { if (quote) { if (ch === quote) quote = ''; } else if (ch === '"' || ch === "'") quote = ch; else if (ch === '[' || ch === '(') depth++; else if (ch === ']' || ch === ')') depth--; else if (ch === ',' && !depth) { out.push(cur.trim()); cur = ''; continue; } cur += ch; } if (cur.trim()) out.push(cur.trim()); return out; }
  function parseComplex(sel) {
    const parts = []; let depth = 0, quote = '', cur = '';
    const flush = () => { if (cur.trim()) parts.push(cur.trim()); cur = ''; };
    for (const ch of sel) { if (quote) { if (ch === quote) quote = ''; cur += ch; continue; } if (ch === '"' || ch === "'") { quote = ch; cur += ch; continue; } if (ch === '[' || ch === '(') depth++; if (ch === ']' || ch === ')') depth--; if (!depth && (ch === ' ' || ch === '>')) { flush(); if (ch === '>') parts.push('>'); continue; } cur += ch; }
    flush(); return parts;
  }
  function matchCompound(el, compound, scope) {
    if (compound === ':scope') return el === scope;
    const re = /^([a-zA-Z*][\w-]*)|#([\w-]+)|\.([\w-]+)|\[([\w-]+)(?:([*^$]?=)"?([^"\]]*)"?)?\]|:not\(([^)]*)\)|:scope/g; let m; let used = 0;
    while ((m = re.exec(compound))) {
      if (m.index !== used) throw new Error(`unsupported selector ${compound}`);
      used = re.lastIndex;
      if (m[0] === ':scope') { if (el !== scope) return false; }
      else if (m[1]) { if (m[1] !== '*' && el.localName !== m[1].toLowerCase()) return false; }
      else if (m[2]) { if (el.id !== m[2]) return false; }
      else if (m[3]) { if (!el.classList.contains(m[3])) return false; }
      else if (m[4]) { if (!el.attrs.has(m[4])) return false; const v = el.attrs.get(m[4]); if (m[5] === '=' && v !== m[6]) return false; if (m[5] === '*=' && !v.includes(m[6])) return false; if (m[5] === '^=' && !v.startsWith(m[6])) return false; if (m[5] === '$=' && !v.endsWith(m[6])) return false; }
      else if (m[7] !== undefined) { if (matchCompound(el, m[7].trim(), scope)) return false; }
    }
    if (used !== compound.length) throw new Error(`unsupported selector ${compound}`);
    return true;
  }
  function matchComplex(el, parts, scope) {
    let i = parts.length - 1;
    if (!matchCompound(el, parts[i], scope)) return false;
    let node = el;
    for (i -= 1; i >= 0; i -= 1) {
      if (parts[i] === '>') { i -= 1; node = node.parentNode; if (!node || node.nodeType !== 1 && parts[i] !== ':scope') return false; if (!(parts[i] === ':scope' ? node === scope : matchCompound(node, parts[i], scope))) return false; continue; }
      let found = false;
      for (node = node.parentNode; node && node.nodeType === 1; node = node.parentNode) if (parts[i] === ':scope' ? node === scope : matchCompound(node, parts[i], scope)) { found = true; break; }
      if (!found) return false;
    }
    return true;
  }
  const doc = {
    activeElement: null,
    createElement: tag => new Element(tag),
    getElementById: id => doc.documentElement.querySelector(`#${id}`),
    querySelector: sel => doc.documentElement.querySelector(sel),
    querySelectorAll: sel => doc.documentElement.querySelectorAll(sel),
    addEventListener() {}, removeEventListener() {}, readyState: 'complete',
  };
  doc.documentElement = new Element('html');
  doc.head = doc.documentElement.appendChild(new Element('head'));
  doc.body = doc.documentElement.appendChild(new Element('body'));
  return doc;
}
module.exports = { createDocument };
