'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');

const html = fs.readFileSync('www/index.html', 'utf8');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));

assert.equal(pkg.dependencies['hls.js'], '1.5.17', 'HLS.js must remain version-pinned');
assert.match(html, /src="lib\/hls\.min\.js"/, 'App must load the local HLS.js bundle first');
assert.match(html, /function requestJsonWithRetry\(/, 'JSON retry helper must exist');
assert.match(html, /timeoutMs: 10000, maxRetries: 2/, 'TMDB requests must have bounded retries');
assert.match(html, /timeoutMs: 8000, maxRetries: 1/, 'Add-on requests must have bounded retries');
assert.match(html, /signal\?\.aborted\) throw error/, 'Stream lookup cancellation must propagate');
assert.match(html, /window\.addEventListener\('pagehide', flushWatchProgress\)/, 'Progress must flush on pagehide');
assert.match(html, /recoverMediaError\(\)/, 'HLS media recovery must remain present');
assert.match(html, /nativeFallbackAttempted/, 'Native HLS fallback must remain single-attempt');
console.log('Streaming reliability smoke checks passed.');
