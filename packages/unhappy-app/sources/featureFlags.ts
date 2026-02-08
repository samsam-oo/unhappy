function parseBooleanEnv(value: string | undefined): boolean | undefined {
    if (value === undefined) return undefined;
    const v = value.trim().toLowerCase();
    if (v === '1' || v === 'true' || v === 'yes' || v === 'on') return true;
    if (v === '0' || v === 'false' || v === 'no' || v === 'off') return false;
    return undefined;
}

function envFlag(name: string, defaultValue: boolean): boolean {
    const parsed = parseBooleanEnv(process.env[name]);
    return parsed ?? defaultValue;
}

// Feature flags are intentionally environment-only (no in-app UI toggle).
// Default: disabled unless explicitly enabled.
export const ENABLE_INBOX = envFlag('EXPO_PUBLIC_ENABLE_INBOX', false);

