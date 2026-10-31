'use strict';

const fs = require('node:fs');
const path = require('node:path');

const packageEntry = require.resolve('hls.js');
const source = path.join(path.dirname(packageEntry), 'hls.min.js');
const destinationDirectory = path.join(process.cwd(), 'www', 'lib');
const destination = path.join(destinationDirectory, 'hls.min.js');

if (!fs.existsSync(source)) {
  throw new Error('The installed hls.js package does not contain dist/hls.min.js: ' + source);
}

fs.mkdirSync(destinationDirectory, { recursive: true });
fs.copyFileSync(source, destination);
console.log('Bundled local HLS.js asset:', destination);
