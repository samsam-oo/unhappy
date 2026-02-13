import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const outputDirArg = process.argv[2] ?? 'dist';
const outputDir = resolve(process.cwd(), outputDirArg);
const indexHtmlPath = resolve(outputDir, 'index.html');

if (!existsSync(indexHtmlPath)) {
  console.error(`[enablePwa] Missing index.html at ${indexHtmlPath}`);
  process.exit(1);
}

const manifestTag = '<link rel="manifest" href="./manifest.webmanifest" />';
const appleTouchTag = '<link rel="apple-touch-icon" href="./apple-touch-icon.png" />';
const faviconTag = '<link rel="icon" href="./favicon.ico" />';
const themeColorTag = '<meta name="theme-color" content="#18171C" />';
const mobileCapableTag = '<meta name="mobile-web-app-capable" content="yes" />';
const appleCapableTag = '<meta name="apple-mobile-web-app-capable" content="yes" />';
const appleStatusBarTag =
  '<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />';
const appleTitleTag = '<meta name="apple-mobile-web-app-title" content="Unhappy" />';

const registerServiceWorkerSnippet = [
  '<script>',
  "(() => {",
  "  const canRegister = 'serviceWorker' in navigator && window.isSecureContext;",
  '',
  '  if (!canRegister) return;',
  '',
  "  const hadController = Boolean(navigator.serviceWorker.controller);",
  '  let reloadingForUpdate = false;',
  '',
  '  const reloadOnControllerChange = () => {',
  '    if (!hadController || reloadingForUpdate) return;',
  '    reloadingForUpdate = true;',
  '    window.location.reload();',
  '  };',
  '',
  "  navigator.serviceWorker.addEventListener('controllerchange', reloadOnControllerChange);",
  '',
  '  const activateWaitingWorker = (registration) => {',
  '    if (registration.waiting) {',
  "      registration.waiting.postMessage({ type: 'SKIP_WAITING' });",
  '    }',
  '  };',
  '',
  '  const attachUpdateListener = (registration) => {',
  "    registration.addEventListener('updatefound', () => {",
  '      const newWorker = registration.installing;',
  '      if (!newWorker) return;',
  '',
  "      newWorker.addEventListener('statechange', () => {",
  "        if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {",
  '          activateWaitingWorker(registration);',
  '        }',
  '      });',
  '    });',
  '  };',
  '',
  '  const register = async () => {',
  '    try {',
  "      const registration = await navigator.serviceWorker.register('./sw.js', {",
  "        updateViaCache: 'none',",
  '      });',
  '',
  '      activateWaitingWorker(registration);',
  '      attachUpdateListener(registration);',
  '',
  '      const checkForUpdate = () => {',
  '        registration.update().catch((error) => {',
  "          console.warn('[PWA] Service worker update check failed', error);",
  '        });',
  '      };',
  '',
  "      document.addEventListener('visibilitychange', () => {",
  "        if (document.visibilityState === 'visible') {",
  '          checkForUpdate();',
  '        }',
  '      });',
  "      window.addEventListener('focus', checkForUpdate);",
  '      window.setInterval(checkForUpdate, 5 * 60 * 1000);',
  '    } catch (error) {',
  "      console.warn('[PWA] Service worker registration failed', error);",
  '    }',
  '  };',
  '',
  "  window.addEventListener('load', register);",
  '})();',
  '</script>',
].join('\n');

let html = readFileSync(indexHtmlPath, 'utf8');

if (!html.includes('manifest.webmanifest')) {
  const headInsert = [
    themeColorTag,
    mobileCapableTag,
    appleCapableTag,
    appleStatusBarTag,
    appleTitleTag,
    faviconTag,
    appleTouchTag,
    manifestTag,
  ].join('');
  html = html.replace('</head>', `${headInsert}</head>`);
}

if (!html.includes("updateViaCache: 'none'")) {
  html = html.replace('</body>', `${registerServiceWorkerSnippet}</body>`);
}

writeFileSync(indexHtmlPath, html);
console.log(`[enablePwa] Updated ${indexHtmlPath}`);
