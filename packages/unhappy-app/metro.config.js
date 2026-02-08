const { getDefaultConfig } = require("expo/metro-config");

const config = getDefaultConfig(__dirname, {
  // Enable CSS support for web
  isCSSEnabled: true,
});

// Work around double-encoded Expo `unstable_path` asset URLs (e.g. `%252F` -> `%2F` -> `/`).
// When this happens, Metro ends up looking for a literal directory name like `.%2Fsources...`.
// Decoding once here keeps the rest of Metro's asset handling unchanged.
const _rewriteRequestUrl = config.server?.rewriteRequestUrl ?? ((url) => url);
config.server = config.server ?? {};
config.server.rewriteRequestUrl = (url) => {
  const rewritten = _rewriteRequestUrl(url);

  // Only touch URLs that have `unstable_path` in the query.
  try {
    const isRelative = typeof rewritten === "string" && rewritten.startsWith("/");
    const u = isRelative ? new URL(rewritten, "https://metro.local") : new URL(rewritten);

    const unstablePath = u.searchParams.get("unstable_path");
    if (unstablePath && /%[0-9A-Fa-f]{2}/.test(unstablePath)) {
      let decoded = unstablePath;
      // Decode a couple times to handle cases like `%252F` -> `%2F` -> `/`.
      for (let i = 0; i < 2; i++) {
        try {
          const next = decodeURIComponent(decoded);
          if (next === decoded) break;
          decoded = next;
        } catch {
          break;
        }
      }

      if (decoded !== unstablePath) {
        u.searchParams.set("unstable_path", decoded);
        return isRelative ? u.toString().replace(u.origin, "") : u.toString();
      }
    }
  } catch {
    // Ignore parse errors and return the original rewritten URL.
  }

  return rewritten;
};

// Add support for .wasm files (required by Skia for all platforms)
// Source: https://shopify.github.io/react-native-skia/docs/getting-started/installation/
config.resolver.assetExts.push('wasm');

// Enable inlineRequires for proper Skia and Reanimated loading
// Source: https://shopify.github.io/react-native-skia/docs/getting-started/web/
// Without this, Skia throws "react-native-reanimated is not installed" error
// This is cross-platform compatible (iOS, Android, web)
config.transformer.getTransformOptions = async () => ({
  transform: {
    experimentalImportSupport: false,
    inlineRequires: true, // Critical for @shopify/react-native-skia
  },
});

module.exports = config;
