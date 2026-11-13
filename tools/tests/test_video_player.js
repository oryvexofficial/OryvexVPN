'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const script = fs.readFileSync(path.join(__dirname, '../../site/video-player.js'), 'utf8');

class Element {
  constructor() {
    this.events = {};
    this.attributes = {};
    this.hidden = false;
    this.disabled = false;
    this.textContent = '';
    this.value = '';
  }
  addEventListener(name, fn) { (this.events[name] ||= []).push(fn); }
  setAttribute(name, value) { this.attributes[name] = value; }
  emit(name) { for (const fn of this.events[name] || []) fn({ target: this }); }
}

function setup(options = {}) {
  const names = ['controls', 'play', 'center', 'icon', 'label', 'seek', 'current', 'duration', 'fullscreen', 'error'];
  const parts = Object.fromEntries(names.map((name) => [name, new Element()]));
  parts.controls.hidden = true;
  parts.center.hidden = true;
  parts.error.hidden = true;
  const video = new Element();
  Object.assign(video, { controls: true, paused: true, ended: false, duration: NaN, currentTime: 0, error: null });
  video.play = () => {
    if (options.reject) return Promise.reject(new Error('cannot play'));
    video.paused = false;
    video.ended = false;
    video.emit('play');
    return Promise.resolve();
  };
  video.pause = () => { video.paused = true; video.emit('pause'); };
  const player = new Element();
  const classes = new Set();
  player.classList = { add: (name) => classes.add(name), remove: (name) => classes.delete(name), contains: (name) => classes.has(name) };
  player.querySelector = (selector) => selector === 'video' ? video :
    parts[selector.replace('[data-player-', '').replace(']', '')];
  const doc = new Element();
  doc.querySelector = (selector) => selector === '[data-video-player]' ? player : null;
  doc.fullscreenElement = null;
  doc.exitFullscreen = () => { doc.fullscreenElement = null; doc.emit('fullscreenchange'); };
  if (!options.noFullscreen) {
    player.requestFullscreen = () => {
      doc.fullscreenElement = player;
      doc.emit('fullscreenchange');
      return Promise.resolve();
    };
  }
  vm.runInNewContext(script, { document: doc, Number, String }, { filename: 'video-player.js' });
  return { video, player, parts, doc };
}

async function main() {
  {
    const { video, player, parts, doc } = setup();
    assert.equal(video.controls, false);
    assert.equal(player.classList.contains('has-custom-video'), true);
    assert.equal(parts.controls.hidden, false);
    assert.equal(parts.center.hidden, false);
    assert.equal(parts.seek.disabled, true);
    video.duration = 54.76;
    video.emit('loadedmetadata');
    assert.equal(parts.duration.textContent, '0:54');
    assert.equal(parts.seek.disabled, false);
    parts.center.emit('click');
    assert.equal(video.paused, false);
    assert.equal(parts.center.hidden, true);
    assert.equal(parts.play.attributes['aria-label'], 'Pause walkthrough');
    parts.seek.value = '500';
    parts.seek.emit('input');
    assert.equal(video.currentTime, 27.38);
    assert.equal(parts.seek.attributes['aria-valuetext'], '0:27 of 0:54');
    parts.play.emit('click');
    assert.equal(video.paused, true);
    assert.equal(parts.center.hidden, false);
    video.ended = true;
    video.emit('ended');
    assert.equal(parts.label.textContent, 'Replay');
    parts.play.emit('click');
    assert.equal(video.currentTime, 0);
    parts.fullscreen.emit('click');
    assert.equal(parts.fullscreen.attributes['aria-label'], 'Exit fullscreen');
    parts.fullscreen.emit('click');
    assert.equal(doc.fullscreenElement, null);
  }
  {
    const { parts } = setup({ noFullscreen: true });
    assert.equal(parts.fullscreen.hidden, true);
  }
  {
    const { video, player, parts } = setup({ reject: true });
    parts.play.emit('click');
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(video.controls, true);
    assert.equal(player.classList.contains('has-custom-video'), false);
    assert.equal(parts.controls.hidden, true);
    assert.equal(parts.error.hidden, false);
  }
  {
    const doc = { querySelector: () => null };
    assert.doesNotThrow(() => vm.runInNewContext(script, { document: doc, Number, String }));
  }
  console.log('Video player checks passed: fallback, play/pause/replay, seek, fullscreen, and errors.');
}

main().catch((error) => { console.error(error); process.exitCode = 1; });
