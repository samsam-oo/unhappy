import { storage } from '@/sync/storage';
import { Session } from '@/sync/storageTypes';
import { getCurrentLanguage, t } from '@/text';
import { VIBING_MESSAGES_BY_LANGUAGE } from '@/text/translations/vibing';
import { pathRelativeToBase } from '@/utils/basePathUtils';
import * as React from 'react';

export type SessionState = 'disconnected' | 'thinking' | 'waiting' | 'permission_required';

export interface SessionStatus {
    state: SessionState;
    isConnected: boolean;
    statusText: string;
    shouldShowStatus: boolean;
    statusColor: string;
    statusDotColor: string;
    isPulsing?: boolean;
}

const SESSION_TITLE_I18N_KEY_PATTERN = /^(files|machine)\.[A-Za-z0-9_.-]+$/;

function isSessionTitleI18nKey(value: string | undefined | null): boolean {
    if (!value) return false;
    return SESSION_TITLE_I18N_KEY_PATTERN.test(value.trim());
}

export function resolveSessionSummaryTitle(summaryText?: string | null): string {
    const trimmed = summaryText?.trim();
    if (!trimmed || isSessionTitleI18nKey(trimmed)) {
        return t('machine.untitledSession');
    }

    return trimmed;
}

/**
 * Get the current state of a session based on presence and thinking status.
 * Uses centralized session state from storage.ts
 */
export function useSessionStatus(session: Session): SessionStatus {
    const isOnline = session.presence === "online";
    const hasPermissions = (session.agentState?.requests && Object.keys(session.agentState.requests).length > 0 ? true : false);
    const currentLanguage = getCurrentLanguage();

const vibingMessage = React.useMemo(() => {
        const messages = VIBING_MESSAGES_BY_LANGUAGE[currentLanguage] ?? VIBING_MESSAGES_BY_LANGUAGE.en;
        return messages[Math.floor(Math.random() * messages.length)].toLowerCase() + '…';
    }, [currentLanguage, isOnline, hasPermissions, session.thinking]);

    if (!isOnline) {
        return {
            state: 'disconnected',
            isConnected: false,
            statusText: t('status.lastSeen', { time: formatLastSeen(session.activeAt, false) }),
            shouldShowStatus: true,
            statusColor: '#999',
            statusDotColor: '#999'
        };
    }

    // Check if permission is required
    if (hasPermissions) {
        return {
            state: 'permission_required',
            isConnected: true,
            statusText: t('status.permissionRequired'),
            shouldShowStatus: true,
            statusColor: '#FF9500',
            statusDotColor: '#FF9500',
            isPulsing: true
        };
    }

    if (session.thinking === true) {
        return {
            state: 'thinking',
            isConnected: true,
            statusText: vibingMessage,
            shouldShowStatus: true,
            statusColor: '#007AFF',
            statusDotColor: '#007AFF',
            isPulsing: true
        };
    }

    return {
        state: 'waiting',
        isConnected: true,
        statusText: t('status.online'),
        shouldShowStatus: false,
        statusColor: '#34C759',
        statusDotColor: '#34C759'
    };
}

/**
 * Extracts a display name from a session's metadata path.
 * Returns the last segment of the path, or 'unknown' if no path is available.
 */
export function getSessionName(session: Session): string {
    if (session.metadata?.summary) {
        return resolveSessionSummaryTitle(session.metadata.summary.text);
    } else if (session.metadata) {
        const segments = session.metadata.path.split('/').filter(Boolean);
        const lastSegment = segments.pop();
        if (!lastSegment) {
            return t('status.unknown');
        }
        if (isSessionTitleI18nKey(lastSegment)) {
            return t('machine.untitledSession');
        }
        return lastSegment;
    }
    return t('status.unknown');
}

/**
 * Generates a deterministic avatar ID from machine ID and path.
 * This ensures the same machine + path combination always gets the same avatar.
 */
export function getSessionAvatarId(session: Session): string {
    if (session.metadata?.machineId && session.metadata?.path) {
        // Combine machine ID and path for a unique, deterministic avatar
        return `${session.metadata.machineId}:${session.metadata.path}`;
    }
    // Fallback to session ID if metadata is missing
    return session.id;
}

/**
 * Formats a path relative to home directory if possible.
 * If the path starts with the home directory, replaces it with ~
 * Otherwise returns the full path.
 */
export function formatPathRelativeToHome(path: string, homeDir?: string): string {
    if (!homeDir) return path;
    
    // Normalize paths to handle trailing slashes
    const normalizedHome = homeDir.endsWith('/') ? homeDir.slice(0, -1) : homeDir;
    const normalizedPath = path;
    
    // Check if path starts with home directory
    if (normalizedPath.startsWith(normalizedHome)) {
        // Replace home directory with ~
        const relativePath = normalizedPath.slice(normalizedHome.length);
        // Add ~ and ensure there's a / after it if needed
        if (relativePath.startsWith('/')) {
            return '~' + relativePath;
        } else if (relativePath === '') {
            return '~';
        } else {
            return '~/' + relativePath;
        }
    }
    
    return path;
}

/**
 * Formats a path relative to the machine's configured "Base Repository" (project base path).
 * Falls back to home-relative (~) formatting when the path is outside the base.
 *
 * Display goal: hide absolute paths from the user whenever possible.
 */
export function formatPathRelativeToProjectBase(path: string, machineId?: string | null, homeDir?: string | null): string {
    const p = (path || '').trim();
    if (!p) return path;

    const settings = storage.getState().settings;
    const configuredBase = machineId
        ? settings.projectBasePaths?.find(e => e.machineId === machineId)?.path
        : null;
    const base = (configuredBase || homeDir || '').trim();
    if (!base) return p;

    const rel = pathRelativeToBase(p, base);
    // If rel is unchanged, it's outside base; still try to hide absolute bits via "~".
    if (rel === p) {
        return formatPathRelativeToHome(p, homeDir || undefined);
    }
    return rel;
}

/**
 * Returns the session path for the subtitle.
 */
export function getSessionSubtitle(session: Session): string {
    if (session.metadata) {
        return formatPathRelativeToProjectBase(session.metadata.path, session.metadata.machineId, session.metadata.homeDir);
    }
    return t('status.unknown');
}

/**
 * Checks if a session is currently online based on the active flag.
 * A session is considered online if the active flag is true.
 */
export function isSessionOnline(session: Session): boolean {
    return session.active;
}

/**
 * Checks if a session should be shown in the active sessions group.
 * Uses the active flag directly.
 */
export function isSessionActive(session: Session): boolean {
    return session.active;
}

/**
 * Formats OS platform string into a more readable format
 */
export function formatOSPlatform(platform?: string): string {
    if (!platform) return '';

    const osMap: Record<string, string> = {
        'darwin': 'macOS',
        'win32': 'Windows',
        'linux': 'Linux',
        'android': 'Android',
        'ios': 'iOS',
        'aix': 'AIX',
        'freebsd': 'FreeBSD',
        'openbsd': 'OpenBSD',
        'sunos': 'SunOS'
    };

    return osMap[platform.toLowerCase()] || platform;
}

/**
 * Formats the last seen time of a session into a human-readable relative time.
 * @param activeAt - Timestamp when the session was last active
 * @param isActive - Whether the session is currently active
 * @returns Formatted string like "Active now", "5 minutes ago", "2 hours ago", or a date
 */
export function formatLastSeen(activeAt: number, isActive: boolean = false): string {
    if (isActive) {
        return t('status.activeNow');
    }

    const now = Date.now();
    const diffMs = now - activeAt;
    const diffSeconds = Math.floor(diffMs / 1000);
    const diffMinutes = Math.floor(diffSeconds / 60);
    const diffHours = Math.floor(diffMinutes / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffSeconds < 60) {
        return t('time.justNow');
    } else if (diffMinutes < 60) {
        return t('time.minutesAgo', { count: diffMinutes });
    } else if (diffHours < 24) {
        return t('time.hoursAgo', { count: diffHours });
    } else if (diffDays < 7) {
        return t('sessionHistory.daysAgo', { count: diffDays });
    } else {
        // Format as date
        const date = new Date(activeAt);
        const options: Intl.DateTimeFormatOptions = {
            month: 'short',
            day: 'numeric',
            year: date.getFullYear() !== new Date().getFullYear() ? 'numeric' : undefined
        };
        return date.toLocaleDateString(undefined, options);
    }
}
