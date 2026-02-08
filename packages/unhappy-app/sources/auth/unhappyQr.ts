export type UnhappyQrKind = 'account' | 'terminal';

export type ParsedUnhappyQr = {
  kind: UnhappyQrKind;
  /**
   * Base64url-encoded public key, as stored in the QR (query string).
   *
   * Existing QR formats in this repo encode the key as a raw query string:
   * - unhappy:///account?<base64url>
   * - unhappy://terminal?<base64url>
   *
   * Some scanners normalize slashes (e.g. unhappy:/account?...), so we parse via URL.
   */
  publicKeyBase64Url: string;
};

type UnhappyQrDebugInfo = {
  inputLen: number;
  trimmedLen: number;
  parseable: boolean;
  protocol?: string;
  host?: string;
  path?: string;
  searchLen?: number;
  kind?: UnhappyQrKind | null;
};

export function getUnhappyQrDebugInfo(input: string): UnhappyQrDebugInfo {
  const raw = input ?? '';
  const trimmed = raw.trim();

  const info: UnhappyQrDebugInfo = {
    inputLen: raw.length,
    trimmedLen: trimmed.length,
    parseable: false,
  };

  try {
    const url = new URL(trimmed);
    info.parseable = true;
    info.protocol = url.protocol;
    info.host = url.hostname || '';
    info.path = url.pathname || '';
    info.searchLen = (url.search || '').length;

    if (url.protocol === 'unhappy:') {
      const host = (url.hostname || '').toLowerCase();
      const path = (url.pathname || '').toLowerCase();
      if (host === 'terminal' || path === '/terminal') info.kind = 'terminal';
      else if (host === 'account' || path === '/account') info.kind = 'account';
      else info.kind = null;
    }
  } catch {
    // Ignore
  }

  return info;
}

export function parseUnhappyQrData(input: string): ParsedUnhappyQr | null {
  const raw = (input ?? '').trim();
  if (!raw) return null;

  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }

  if (url.protocol !== 'unhappy:') return null;

  const host = (url.hostname || '').toLowerCase();
  const path = (url.pathname || '').toLowerCase();

  let kind: UnhappyQrKind | null = null;
  if (host === 'terminal' || path === '/terminal') kind = 'terminal';
  if (host === 'account' || path === '/account') kind = 'account';
  if (!kind) return null;

  const search = url.search || '';
  if (!search.startsWith('?') || search.length <= 1) return null;

  // Default format is a raw query string with no keys: "?<base64url>"
  let publicKeyBase64Url = search.slice(1);

  // Tolerate "key=value" query formats if any scanner/app re-encodes it.
  if (publicKeyBase64Url.includes('&') || publicKeyBase64Url.includes('=')) {
    const param =
      url.searchParams.get('publicKey') ||
      url.searchParams.get('key') ||
      url.searchParams.get('k');
    if (!param) return null;
    publicKeyBase64Url = param;
  }

  publicKeyBase64Url = publicKeyBase64Url.trim();
  if (!publicKeyBase64Url) return null;

  return { kind, publicKeyBase64Url };
}
