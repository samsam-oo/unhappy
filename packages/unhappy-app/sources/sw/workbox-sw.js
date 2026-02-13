const CACHE_VERSION = 'v3';
const CACHE_NAME = `unhappy-pwa-${CACHE_VERSION}`;
const SCOPE_BASE_PATH = new URL(self.registration.scope).pathname.replace(/\/$/, '');

function toScopedPath(pathname) {
  const normalizedPath = pathname.startsWith('/') ? pathname : `/${pathname}`;
  if (!SCOPE_BASE_PATH) return normalizedPath;
  return `${SCOPE_BASE_PATH}${normalizedPath}`.replace(/\/{2,}/g, '/');
}

const STATIC_PATHS = new Set([
  toScopedPath('/canvaskit.wasm'),
  toScopedPath('/manifest.webmanifest'),
  toScopedPath('/favicon.ico'),
  toScopedPath('/apple-touch-icon.png'),
  toScopedPath('/pwa-192.png'),
  toScopedPath('/pwa-512.png'),
  toScopedPath('/pwa-maskable-512.png'),
]);

const APP_SHELL_FILES = [
  toScopedPath('/'),
  toScopedPath('/index.html'),
  toScopedPath('/manifest.webmanifest'),
  toScopedPath('/favicon.ico'),
  toScopedPath('/apple-touch-icon.png'),
  toScopedPath('/pwa-192.png'),
  toScopedPath('/pwa-512.png'),
  toScopedPath('/pwa-maskable-512.png'),
];

const PRECACHE_ENTRIES = self.__WB_MANIFEST;
const RESOLVED_PRECACHE_ENTRIES = Array.isArray(PRECACHE_ENTRIES)
  ? PRECACHE_ENTRIES
  : [];

const PRECACHE_FILES = Array.from(
  new Set(
    RESOLVED_PRECACHE_ENTRIES.map((entry) =>
      new URL(entry.url, self.registration.scope).pathname
    )
  )
);
const PRECACHE_FILE_SET = new Set([...APP_SHELL_FILES, ...PRECACHE_FILES]);

const INSTALL_FILES = Array.from(new Set([...APP_SHELL_FILES, ...PRECACHE_FILES]));

self.addEventListener('message', (event) => {
  if (!event.data || event.data.type !== 'SKIP_WAITING') return;
  self.skipWaiting();
});

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(INSTALL_FILES))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheKeys) =>
      Promise.all(
        cacheKeys
          .filter((cacheKey) => cacheKey !== CACHE_NAME)
          .map((cacheKey) => caches.delete(cacheKey))
      )
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    event.respondWith(networkFirst(request, toScopedPath('/index.html')));
    return;
  }

  if (isCachedStaticAsset(url.pathname)) {
    event.respondWith(cacheFirstNoWrite(request));
  }
});

function isCachedStaticAsset(pathname) {
  if (STATIC_PATHS.has(pathname)) return true;
  return PRECACHE_FILE_SET.has(pathname);
}

async function networkFirst(request, fallbackPath) {
  const cache = await caches.open(CACHE_NAME);

  try {
    return await fetch(request);
  } catch (error) {
    const cachedResponse = await cache.match(request);
    if (cachedResponse) return cachedResponse;

    const fallbackResponse = await cache.match(fallbackPath);
    if (fallbackResponse) return fallbackResponse;

    throw error;
  }
}

async function cacheFirstNoWrite(request) {
  const cache = await caches.open(CACHE_NAME);
  const cachedResponse = await cache.match(request);
  if (cachedResponse) return cachedResponse;

  return fetch(request);
}
