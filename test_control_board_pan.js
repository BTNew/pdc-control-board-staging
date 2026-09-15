'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { mountTimeline } = require('./control-board-overview.js');

function fixture({ total = 10000, visible = 1000, left = 0 } = {}) {
  function element() {
    const handlers = new Map(), attributes = {}, captured = new Set();
    return { style: {}, classList: { add() {}, remove() {} }, clientWidth: 800, attributes, handlers,
      addEventListener(type, fn) { handlers.set(type, fn); }, removeEventListener(type) { handlers.delete(type); },
      setAttribute(name, value) { attributes[name] = value; }, focus() {}, contains(target) { return target === this; },
      getBoundingClientRect() { return { left: 100 }; },
      setPointerCapture(id) { captured.add(id); }, hasPointerCapture(id) { return captured.has(id); }, releasePointerCapture(id) { captured.delete(id); },
      fire(type, data = {}) { const e = { preventDefault() { this.prevented = true; }, ...data }; handlers.get(type)?.(e); return e; },
    };
  }
  const scroll = Object.assign(element(), { scrollWidth: total, clientWidth: visible, scrollLeft: left });
  const header = element(), rail = element(), thumb = element();
  let observer;
  const view = { ResizeObserver: class { constructor(fn) { this.fn = fn; observer = this; } observe() {} disconnect() { this.disconnected = true; } } };
  const nodes = { '.control-board-timeline-scroll': scroll, '.control-board-timeline-header-viewport': header, '.control-board-pan-rail': rail, '.control-board-pan-thumb': thumb };
  const shell = { querySelector: name => nodes[name] };
  const host = { ownerDocument: { defaultView: view }, querySelector: () => shell };
  const cleanup = mountTimeline(host);
  return { scroll, header, rail, thumb, cleanup, observer };
}

test('restored and native scroll positions keep the date header and pan indicator aligned', () => {
  const f = fixture({ left: 2400 });
  assert.equal(f.header.scrollLeft, 2400);
  assert.equal(f.rail.attributes['aria-valuenow'], '2400');
  f.scroll.scrollLeft = 7000;
  f.scroll.fire('scroll');
  assert.equal(f.header.scrollLeft, 7000);
  assert.equal(f.rail.attributes['aria-valuenow'], '7000');
});

test('dragging pans both directions, clamps at the dates, and cancellation ends the gesture', () => {
  const f = fixture();
  f.rail.fire('pointerdown', { button: 0, pointerId: 1, clientX: 120, target: f.thumb });
  f.rail.fire('pointermove', { pointerId: 1, clientX: 220 });
  assert.ok(f.scroll.scrollLeft > 0);
  assert.equal(f.header.scrollLeft, f.scroll.scrollLeft);
  f.rail.fire('pointermove', { pointerId: 1, clientX: 5000 });
  assert.equal(f.scroll.scrollLeft, 9000);
  f.rail.fire('pointermove', { pointerId: 1, clientX: 0 });
  assert.equal(f.scroll.scrollLeft, 0);
  f.rail.fire('pointercancel', { pointerId: 1 });
  f.rail.fire('pointermove', { pointerId: 1, clientX: 300 });
  assert.equal(f.scroll.scrollLeft, 0);
  assert.equal(f.rail.hasPointerCapture(1), false);
});

test('track click and keyboard allow navigation without dragging a booking', () => {
  const f = fixture();
  f.rail.fire('pointerdown', { button: 0, pointerId: 2, clientX: 500, target: f.rail });
  assert.equal(f.scroll.scrollLeft, 4500);
  f.rail.fire('pointerup', { pointerId: 2 });
  f.rail.fire('keydown', { key: 'Home' });
  f.rail.fire('keydown', { key: 'ArrowRight' });
  assert.equal(f.scroll.scrollLeft, 64);
  f.rail.fire('keydown', { key: 'End' });
  assert.equal(f.scroll.scrollLeft, 9000);
  f.rail.fire('keydown', { key: 'PageUp' });
  assert.ok(f.scroll.scrollLeft < 9000);
  assert.equal(f.rail.fire('keydown', { key: 'Tab' }).prevented, undefined);
});

test('vertical wheel remains page scrolling while horizontal and Shift-wheel pan dates', () => {
  const f = fixture();
  assert.equal(f.header.fire('wheel', { deltaX: 0, deltaY: 100, deltaMode: 0 }).prevented, undefined);
  assert.equal(f.scroll.scrollLeft, 0);
  assert.equal(f.header.fire('wheel', { deltaX: 200, deltaY: 0, deltaMode: 0 }).prevented, true);
  assert.equal(f.scroll.scrollLeft, 200);
  f.rail.fire('wheel', { deltaX: 0, deltaY: 100, shiftKey: true, deltaMode: 0 });
  assert.equal(f.scroll.scrollLeft, 300);
});

test('resizing updates the range and rerender cleanup releases capture, events and observer', () => {
  const f = fixture();
  f.scroll.clientWidth = 2000;
  f.observer.fn();
  assert.equal(f.rail.attributes['aria-valuemax'], '8000');
  f.rail.fire('pointerdown', { button: 0, pointerId: 1, clientX: 120, target: f.thumb });
  f.cleanup();
  assert.equal(f.rail.hasPointerCapture(1), false);
  assert.equal(f.rail.handlers.size, 0);
  assert.equal(f.scroll.handlers.size, 0);
  assert.equal(f.observer.disconnected, true);
});

test('a timeline that fits the viewport disables panning without invalid geometry', () => {
  const f = fixture({ total: 800, visible: 1000 });
  assert.equal(f.rail.attributes['aria-disabled'], 'true');
  f.rail.fire('pointerdown', { button: 0, pointerId: 1, clientX: 300, target: f.rail });
  f.rail.fire('keydown', { key: 'End' });
  assert.equal(f.scroll.scrollLeft, 0);
  assert.equal(f.thumb.style.width, '800px');
  assert.equal(f.thumb.style.transform, 'translateX(0px)');
});
