import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { injectManifest } from 'workbox-build';

const outputDirArg = process.argv[2] ?? 'dist';
const outputDir = resolve(process.cwd(), outputDirArg);
const indexHtmlPath = resolve(outputDir, 'index.html');
const swSrc = resolve(process.cwd(), 'sources/sw/workbox-sw.js');
const swDest = resolve(outputDir, 'sw.js');

if (!existsSync(indexHtmlPath)) {
  console.error(`[buildWorkbox] Missing index.html at ${indexHtmlPath}`);
  process.exit(1);
}

if (!existsSync(swSrc)) {
  console.error(`[buildWorkbox] Missing service worker source at ${swSrc}`);
  process.exit(1);
}

const { count, size, warnings } = await injectManifest({
  swSrc,
  swDest,
  globDirectory: outputDir,
  globPatterns: [
    'index.html',
    'manifest.webmanifest',
    'favicon.ico',
    'apple-touch-icon.png',
    'pwa-192.png',
    'pwa-512.png',
    'pwa-maskable-512.png',
    'canvaskit.wasm',
    '_expo/static/css/*.css',
    '_expo/static/js/web/*.js',
  ],
  globIgnores: ['sw.js'],
  maximumFileSizeToCacheInBytes: 12 * 1024 * 1024,
});

if (warnings.length > 0) {
  for (const warning of warnings) {
    console.warn(`[buildWorkbox] ${warning}`);
  }
}

console.log(`[buildWorkbox] Generated ${swDest} (precache: ${count} files, ${size} bytes)`);
