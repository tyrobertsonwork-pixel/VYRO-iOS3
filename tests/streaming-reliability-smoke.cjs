'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');

const html = fs.readFileSync('www/index.html', 'utf8');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));

assert.equal(pkg.dependencies['hls.js'], '1.5.17', 'HLS.js must remain version-pinned');
assert.match(html, /src="lib\/hls\.min\.js"/, 'App must load the local HLS.js bundle first');
assert.match(html, /function requestJsonWithRetry\(/, 'JSON retry helper must exist');
assert.match(html, /timeoutMs: 10000, maxRetries: 1/, 'TMDB requests must have bounded retries');
assert.match(html, /timeoutMs: 8000, maxRetries: 1/, 'Add-on requests must have bounded retries');
assert.match(html, /stream\.behaviorHints\?\.filename/, 'Native format detection must inspect provider filename hints');
assert.match(html, /matroska/, 'Native format detection must recognize Matroska MIME types');
assert.match(html, /signal\?\.aborted\) throw error/, 'Stream lookup cancellation must propagate');
assert.match(html, /window\.addEventListener\('pagehide', flushWatchProgress\)/, 'Progress must flush on pagehide');
assert.match(html, /recoverMediaError\(\)/, 'HLS media recovery must remain present');
assert.match(html, /nativeFallbackAttempted/, 'Native HLS fallback must remain single-attempt');
assert.match(html, /window\.Capacitor\?\.Plugins\?\.AetherPlayer/, 'Unsupported containers must route through the registered native player');
assert.match(html, /headers: nativeHeaders/, 'Provider request headers must be forwarded to native playback');
const nativePlugin = fs.readFileSync('native/ios/AetherPlayerPlugin.swift', 'utf8');
assert.match(nativePlugin, /options: \.init\(httpHeaders: httpHeaders\)/, 'AetherEngine must receive provider HTTP headers');
assert.match(nativePlugin, /@objc func play\(_ call: CAPPluginCall\)/, 'Native play control must be implemented');
const nativeBridge = fs.readFileSync('native/ios/VYROBridgeViewController.swift', 'utf8');
assert.match(nativeBridge, /registerPluginType\(AetherPlayerPlugin\.self\)/, 'AetherPlayer must be registered with Capacitor');
console.log('Streaming reliability smoke checks passed.');
