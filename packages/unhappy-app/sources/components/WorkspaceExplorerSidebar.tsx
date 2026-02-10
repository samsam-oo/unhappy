import { Text } from '@/components/StyledText';
import { RowActionMenu } from '@/components/RowActionMenu';
import type { RowAction } from '@/components/RowActionMenu';
import { Typography } from '@/constants/Typography';
import { useNavigateToSession } from '@/hooks/useNavigateToSession';
import { Ionicons, Octicons } from '@/icons/vector-icons';
import { useHappyAction } from '@/hooks/useHappyAction';
import type { Project } from '@/sync/projectManager';
import { sessionKill } from '@/sync/ops';
import { useAllSessions, useProjects } from '@/sync/storage';
import type { Session } from '@/sync/storageTypes';
import { sync } from '@/sync/sync';
import { t } from '@/text';
import { HappyError } from '@/utils/errors';
import { useSessionStatus } from '@/utils/sessionUtils';
import { Modal } from '@/modal';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { usePathname, useRouter } from 'expo-router';
import * as React from 'react';
import { ActivityIndicator, FlatList, LayoutAnimation, Platform, Pressable, UIManager, View } from 'react-native';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import Animated, {
    Easing,
    FadeIn,
    FadeOut,
    LinearTransition,
    cancelAnimation,
    runOnJS,
    useAnimatedStyle,
    useSharedValue,
    withRepeat,
    withTiming,
} from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { useCompactLayout, COMPACT_WIDTH_THRESHOLD } from '@/utils/responsive';

const LOCAL_STORAGE_KEY = 'happy.workspaceExplorer.expanded.v1';
const WORKSPACE_ORDER_KEY = 'happy.workspaceExplorer.workspaceOrder.v1';

const IS_WEB = Platform.OS === 'web';
const DEFAULT_EXPANDED = true;

// This view is used both in the desktop sidebar and as the phone "Sessions" main screen.
// Compact layout for wide screens (≥800px); regular layout for narrow/mobile screens.
function getMetrics(compact: boolean) {
    return {
        sectionHeaderPaddingV: compact ? 6 : 10,
        sectionHeaderMinHeight: compact ? 32 : 44,
        rowMinHeight: compact ? 30 : 52,
        rowPaddingV: compact ? 4 : 12,
        rowPaddingH: compact ? 8 : 14,
        rowMarginV: compact ? 1 : 3,
        rowRadius: compact ? 6 : 12,
        rowGap: compact ? 6 : 12,
        selectionBarInsetV: compact ? 4 : 10,
        actionButtonSize: compact ? 24 : 38,
        actionButtonRadius: compact ? 5 : 10,
        chevronWidth: compact ? 14 : 22,
        iconWidth: compact ? 16 : 24,
        childIndent: 0,
        grandChildIndent: 0,
        rowInset1: compact ? 10 : 18,
        rowInset2: compact ? 26 : 44,
        nestRailInsetV: compact ? 4 : 10,
        nestRailWidth: 2,
        titleFontSize: compact ? 12 : 17,
        titleLineHeight: compact ? 16 : 22,
        subtitleFontSize: compact ? 10 : 14,
        subtitleLineHeight: compact ? 14 : 19,
        subtitleMarginTop: compact ? 1 : 3,
    };
}

function getIcons(compact: boolean) {
    return {
        spinner: compact ? 12 : 18,
        rowIcon: compact ? 14 : 22,
        chevron: compact ? 12 : 20,
        folder: compact ? 13 : 20,
        gitBranch: compact ? 10 : 14,
        headerAdd: compact ? 16 : 22,
        headerCollapse: compact ? 16 : 22,
        rowAdd: compact ? 14 : 22,
        reorderHandle: compact ? 14 : 22,
    };
}

function safeParseJson<T>(value: string | null): T | null {
    if (!value) return null;
    try {
        return JSON.parse(value) as T;
    } catch {
        return null;
    }
}

function migrateExpandedMap(stored: unknown): Record<string, boolean> | null {
    if (!stored || typeof stored !== 'object') return null;
    const entries = Object.entries(stored as Record<string, unknown>);
    const migrated: Record<string, boolean> = {};
    for (const [k, v] of entries) {
        if (typeof v !== 'boolean') continue;
        // Migration: older versions stored keys as `${machineId}:${path}` without a type prefix.
        if (k.startsWith('p:') || k.startsWith('w:')) migrated[k] = v;
        else migrated[`p:${k}`] = v;
    }
    return migrated;
}

function sessionNeedsAttention(session: Session): boolean {
    if (session.unread) return true;
    const requests = session.agentState?.requests;
    return !!requests && Object.keys(requests).length > 0;
}

function formatBadgeCount(count: number): string {
    if (count <= 0) return '';
    if (count > 99) return '99+';
    return String(count);
}

function getProjectStableId(project: Project): string {
    return `${project.key.machineId}:${project.key.path}`;
}

function getBasename(path: string): string {
    const parts = path.split(/[\\/]/).filter(Boolean);
    return parts[parts.length - 1] || path || 'Workspace';
}

function getSelectedSessionIdFromPathname(pathname: string): string | null {
    const match = pathname.match(/^\/session\/([^\/\?]+)(?:\/|$)/);
    return match?.[1] ?? null;
}

function truncateWithEllipsis(text: string, maxChars: number): string {
    const t = text.trim();
    if (t.length <= maxChars) return t;
    if (maxChars <= 3) return t.slice(0, maxChars);
    return t.slice(0, maxChars - 3).trimEnd() + '...';
}

const WORKTREE_SEGMENT_POSIX = '/.unhappy/worktree/';
const WORKTREE_SEGMENT_WIN = '\\.unhappy\\worktree\\';

function isWorktreePath(path: string): boolean {
    return path.includes(WORKTREE_SEGMENT_POSIX) || path.includes(WORKTREE_SEGMENT_WIN);
}

function getWorktreeBasePath(path: string): string | null {
    const posixIdx = path.indexOf(WORKTREE_SEGMENT_POSIX);
    if (posixIdx >= 0) return path.slice(0, posixIdx);
    const winIdx = path.indexOf(WORKTREE_SEGMENT_WIN);
    if (winIdx >= 0) return path.slice(0, winIdx);
    return null;
}

function getExpandedKey(kind: 'project' | 'worktree', stableId: string): string {
    return `${kind === 'project' ? 'p' : 'w'}:${stableId}`;
}

function arraysEqual(a: readonly string[], b: readonly string[]): boolean {
    if (a === b) return true;
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
    return true;
}

function normalizeWorkspaceOrder(current: string[] | null, stableIds: readonly string[]): string[] {
    const stableIdSet = new Set(stableIds);
    const out: string[] = [];
    const seen = new Set<string>();

    if (current) {
        for (const id of current) {
            if (!stableIdSet.has(id)) continue;
            if (seen.has(id)) continue;
            seen.add(id);
            out.push(id);
        }
    }

    // Append anything new at the end to avoid surprising reorders.
    for (const id of stableIds) {
        if (seen.has(id)) continue;
        seen.add(id);
        out.push(id);
    }

    return out;
}

async function loadWorkspaceOrder(): Promise<string[] | null> {
    try {
        if (Platform.OS === 'web') {
            if (typeof window === 'undefined') return null;
            const parsed = safeParseJson<unknown>(window.localStorage.getItem(WORKSPACE_ORDER_KEY));
            if (Array.isArray(parsed) && parsed.every((v) => typeof v === 'string')) return parsed as string[];
            return null;
        }

        const raw = await AsyncStorage.getItem(WORKSPACE_ORDER_KEY);
        const parsed = safeParseJson<unknown>(raw);
        if (Array.isArray(parsed) && parsed.every((v) => typeof v === 'string')) return parsed as string[];
        return null;
    } catch {
        return null;
    }
}

async function saveWorkspaceOrder(order: string[]): Promise<void> {
    try {
        const raw = JSON.stringify(order);
        if (Platform.OS === 'web') {
            if (typeof window === 'undefined') return;
            window.localStorage.setItem(WORKSPACE_ORDER_KEY, raw);
            return;
        }
        await AsyncStorage.setItem(WORKSPACE_ORDER_KEY, raw);
    } catch {
        // ignore
    }
}

const stylesheet = StyleSheet.create((theme, runtime) => {
    const UI_METRICS = getMetrics(Platform.OS === 'web' && runtime.screen.width >= COMPACT_WIDTH_THRESHOLD);
    return {
    container: {
        flex: 1,
        backgroundColor: theme.colors.chrome.sidebarBackground,
    },
    sectionHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        paddingHorizontal: 12,
        // Keep the sidebar compact but avoid "cramped" headers.
        paddingVertical: UI_METRICS.sectionHeaderPaddingV,
        minHeight: UI_METRICS.sectionHeaderMinHeight,
        borderBottomWidth: StyleSheet.hairlineWidth,
        borderBottomColor: theme.colors.chrome.panelBorder,
    },
    sectionTitle: {
        fontSize: 12,
        lineHeight: 16,
        fontWeight: '700',
        color: theme.colors.groupped.sectionTitle,
        letterSpacing: 0.7,
        textTransform: 'uppercase',
        ...Typography.default('semiBold'),
    },
    headerButtons: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 10,
    },
    headerButton: {
        width: UI_METRICS.actionButtonSize,
        height: UI_METRICS.actionButtonSize,
        alignItems: 'center',
        justifyContent: 'center',
        borderRadius: UI_METRICS.actionButtonRadius,
    },
    headerButtonHover: {
        backgroundColor: theme.colors.chrome.listHoverBackground,
    },

    emptyState: {
        flex: 1,
        paddingHorizontal: 14,
        paddingVertical: 18,
        alignItems: 'center',
        justifyContent: 'center',
        gap: 10,
    },
    emptyStateTitle: {
        fontSize: 13,
        lineHeight: 18,
        color: theme.colors.text,
        textAlign: 'center',
        ...Typography.default('semiBold'),
    },
    emptyStateSubtitle: {
        fontSize: 12,
        lineHeight: 16,
        color: theme.colors.textSecondary,
        textAlign: 'center',
        ...Typography.default(),
    },
    emptyStateButton: {
        marginTop: 6,
        paddingHorizontal: 12,
        paddingVertical: 10,
        borderRadius: 10,
        backgroundColor: theme.colors.surface,
        borderWidth: StyleSheet.hairlineWidth,
        borderColor: theme.colors.chrome.panelBorder,
    },
    emptyStateButtonHover: {
        backgroundColor: theme.colors.chrome.listHoverBackground,
    },
    emptyStateButtonText: {
        fontSize: 12,
        lineHeight: 16,
        color: theme.colors.text,
        ...Typography.default('semiBold'),
    },

    list: {
        // Avoid a "double padding" feel: the header already provides vertical rhythm.
        paddingTop: 8,
        paddingBottom: 10,
    },

    row: {
        minHeight: UI_METRICS.rowMinHeight,
        paddingHorizontal: UI_METRICS.rowPaddingH,
        paddingVertical: UI_METRICS.rowPaddingV,
        marginVertical: UI_METRICS.rowMarginV,
        marginHorizontal: 6,
        borderRadius: UI_METRICS.rowRadius,
        flexDirection: 'row',
        alignItems: 'center',
        gap: UI_METRICS.rowGap,
    },
    rowHover: {
        backgroundColor: theme.colors.chrome.listHoverBackground,
    },
    rowPressed: {
        backgroundColor: theme.colors.surfacePressed,
    },
    rowActive: {
        backgroundColor: theme.colors.chrome.listActiveBackground,
    },
    rowMobileBase: {
        borderWidth: StyleSheet.hairlineWidth,
        borderColor: theme.colors.chrome.panelBorder,
    },
    rowMobileRoot: {
        backgroundColor: theme.colors.surface,
    },
    rowMobileNested: {
        backgroundColor: 'transparent',
    },
    rowMobileNestedDeep: {
        backgroundColor: 'transparent',
    },
    rowMobileInset1: {
        marginLeft: UI_METRICS.rowInset1,
        marginRight: 6,
    },
    rowMobileInset2: {
        marginLeft: UI_METRICS.rowInset2,
        marginRight: 6,
    },
    // Mobile: keep a single outer border per workspace group; indent via padding (not margin)
    // so group borders align vertically.
    mobileIndent1: {
        paddingLeft: UI_METRICS.rowPaddingH + UI_METRICS.rowInset1,
    },
    mobileIndent2: {
        paddingLeft: UI_METRICS.rowPaddingH + UI_METRICS.rowInset2,
    },
    selectionBar: {
        position: 'absolute',
        left: 0,
        top: UI_METRICS.selectionBarInsetV,
        bottom: UI_METRICS.selectionBarInsetV,
        width: 2,
        backgroundColor: theme.colors.chrome.accent,
        borderTopLeftRadius: 2,
        borderBottomLeftRadius: 2,
    },

    chevron: {
        width: UI_METRICS.chevronWidth,
        alignItems: 'center',
        justifyContent: 'center',
        position: 'relative',
    },
    nestRail: {
        position: 'absolute',
        top: UI_METRICS.nestRailInsetV,
        bottom: UI_METRICS.nestRailInsetV,
        left: Math.floor(UI_METRICS.chevronWidth / 2),
        width: UI_METRICS.nestRailWidth,
        backgroundColor: theme.colors.chrome.panelBorder,
        opacity: 0.75,
    },
    // Mobile: use a dot marker instead of an "elbow" underscore.
    treeDotWrap: {
        ...StyleSheet.absoluteFillObject,
        alignItems: 'center',
        justifyContent: 'center',
        // Keep the dot slightly left so it sits on the rail (not in the middle of empty space).
        paddingLeft: Math.floor(UI_METRICS.chevronWidth / 2),
    },
    treeDot: {
        width: 4,
        height: 4,
        borderRadius: 2,
        backgroundColor: theme.colors.chrome.panelBorder,
        borderWidth: StyleSheet.hairlineWidth,
        borderColor: theme.colors.surface,
        opacity: 0.95,
    },
    treeDotWorktree: {
        width: 5,
        height: 5,
        borderRadius: 3,
        opacity: 1,
    },
    projectActions: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 6,
    },
    badge: {
        minWidth: 18,
        height: 18,
        paddingHorizontal: 6,
        borderRadius: 999,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: theme.colors.status.error,
    },
    badgeText: {
        fontSize: 12,
        lineHeight: 16,
        fontWeight: '800',
        color: '#FFFFFF',
        ...Typography.default('semiBold'),
    },
    rowActionButton: {
        width: UI_METRICS.actionButtonSize,
        height: UI_METRICS.actionButtonSize,
        alignItems: 'center',
        justifyContent: 'center',
        borderRadius: UI_METRICS.actionButtonRadius,
    },
    icon: {
        width: UI_METRICS.iconWidth,
        alignItems: 'center',
        justifyContent: 'center',
    },
    textBlock: {
        flex: 1,
        minWidth: 0,
        flexDirection: 'column',
    },
    title: {
        fontSize: UI_METRICS.titleFontSize,
        lineHeight: UI_METRICS.titleLineHeight,
        color: theme.colors.text,
        ...Typography.default('semiBold'),
    },
    subtitleRow: {
        flexDirection: 'row',
        alignItems: 'center',
        marginTop: UI_METRICS.subtitleMarginTop,
        gap: 6,
    },
    subtitle: {
        fontSize: UI_METRICS.subtitleFontSize,
        lineHeight: UI_METRICS.subtitleLineHeight,
        color: theme.colors.textSecondary,
        ...Typography.default(),
    },

    childIndent: {
        paddingLeft: UI_METRICS.childIndent,
    },
    grandChildIndent: {
        paddingLeft: UI_METRICS.grandChildIndent,
    },
    };
});

type Row =
    | { type: 'project'; project: Project; expanded: boolean; isVirtual?: boolean; groupStableId: string }
    | { type: 'worktree'; project: Project; expanded: boolean; parentStableId: string; groupStableId: string }
    | { type: 'session'; session: Session; depth: 1 | 2; groupStableId: string };

type ProjectGroup = {
    stableId: string;
    project: Project;
    isVirtual: boolean;
    worktrees: Project[];
    updatedAt: number;
};

const WorkspaceExplorerSessionRow = React.memo(function WorkspaceExplorerSessionRow(props: {
    session: Session;
    selected: boolean;
    depth: 1 | 2;
    groupChromeStyle?: any;
}) {
    const styles = stylesheet;
    const { theme } = useUnistyles();
    const compact = useCompactLayout();
    const UI_ICONS = getIcons(compact);
    const navigateToSession = useNavigateToSession();

    const [, performArchive] = useHappyAction(async () => {
        const result = await sessionKill(props.session.id);
        if (!result.success) {
            throw new HappyError(result.message || t('sessionInfo.failedToArchiveSession'), false);
        }
    });

    const sessionStatus = useSessionStatus(props.session);
    const rawSessionTitle = props.session.metadata?.summary?.text?.trim() || 'Session';
    const sessionTitle = truncateWithEllipsis(rawSessionTitle, compact ? 44 : 30);

    // Keep icon colors intentionally monotone. Use selection state (not session status)
    // to slightly increase contrast.
    const iconColor = props.selected ? theme.colors.text : theme.colors.textSecondary;

    const shouldPulseUnreadIcon =
        !!props.session.unread &&
        sessionStatus.state !== 'thinking' &&
        sessionStatus.state !== 'permission_required';

    const unreadPulse = useSharedValue(0);

    React.useEffect(() => {
        if (shouldPulseUnreadIcon) {
            unreadPulse.value = withRepeat(
                // Smooth fade out/in (blink) for unread sessions.
                withTiming(1, { duration: 1100, easing: Easing.inOut(Easing.cubic) }),
                -1,
                true
            );
            return;
        }
        cancelAnimation(unreadPulse);
        unreadPulse.value = withTiming(0, { duration: 150 });
    }, [shouldPulseUnreadIcon, unreadPulse]);

    const unreadPulseStyle = useAnimatedStyle(() => {
        const t = unreadPulse.value;
        return {
            // Fade between almost-hidden and fully visible (no scale/motion).
            opacity: 0.15 + (1 - t) * 0.85,
        };
    });

    const iconName = React.useMemo(() => {
        // If a session became ready while the user was away, prioritize an explicit "unread" icon.
        // Keep "thinking" and "permission_required" icons since those states are more actionable.
        if (props.session.unread && sessionStatus.state !== 'thinking' && sessionStatus.state !== 'permission_required') {
            return 'notifications-outline';
        }

        switch (sessionStatus.state) {
            case 'thinking':
                return 'sparkles-outline';
            case 'permission_required':
                return 'alert-circle-outline';
            case 'waiting':
                // "Waiting for your message" feels closer to chat than terminal.
                return 'chatbubble-outline';
            case 'disconnected':
                return 'cloud-outline';
            default:
                return 'terminal-outline';
        }
    }, [props.session.unread, sessionStatus.state]);

    const sessionActions: RowAction[] = React.useMemo(() => [
        {
            key: 'archive',
            label: t('sessionInfo.archiveSession'),
            icon: 'archive-outline',
            destructive: true,
            onPress: async () => {
                const confirmed = await Modal.confirm(
                    t('sessionInfo.archiveSession'),
                    t('workspaceExplorer.archiveSessionConfirm'),
                    { destructive: true },
                );
                if (confirmed) performArchive();
            },
        },
    ], [performArchive]);

    return (
        <Pressable
            onPress={() => navigateToSession(props.session.id)}
            style={({ hovered, pressed }: any) => [
                styles.row,
                props.groupChromeStyle,
                props.depth === 2 ? styles.mobileIndent2 : styles.mobileIndent1,
                props.selected && styles.rowActive,
                (IS_WEB && hovered && !props.selected) && styles.rowHover,
                (pressed && !props.selected) && styles.rowPressed,
            ]}
        >
            {props.selected && <View style={styles.selectionBar} />}
            <View style={styles.chevron}>
                <>
                    <View style={styles.nestRail} />
                    <View style={styles.treeDotWrap} pointerEvents="none">
                        <View style={styles.treeDot} />
                    </View>
                </>
            </View>
            <View style={styles.icon}>
                {sessionStatus.state === 'thinking'
                    ? <ActivityIndicator size={UI_ICONS.spinner} color={iconColor} />
                    : (
                        <Animated.View style={shouldPulseUnreadIcon ? unreadPulseStyle : undefined}>
                            <Ionicons name={iconName} size={UI_ICONS.rowIcon} color={iconColor} />
                        </Animated.View>
                    )
                }
            </View>
            <View style={styles.textBlock}>
                <Text style={styles.title} numberOfLines={1}>
                    {sessionTitle}
                </Text>
            </View>
            <View style={styles.projectActions}>
                <RowActionMenu actions={sessionActions} />
            </View>
        </Pressable>
    );
});

export function WorkspaceExplorerSidebar(props?: { bottomPaddingExtra?: number }) {
    const bottomPaddingExtra = props?.bottomPaddingExtra ?? 0;
    const styles = stylesheet;
    const { theme } = useUnistyles();
    const compact = useCompactLayout();
    const UI_METRICS = getMetrics(compact);
    const UI_ICONS = getIcons(compact);
    const insets = useSafeAreaInsets();
    const router = useRouter();
    const pathname = usePathname();

    const projects = useProjects();
    // Hide archived sessions in the sidebar list.
    const allSessions = useAllSessions();
    const sessions = React.useMemo(() => allSessions.filter((s) => s.active), [allSessions]);

    const selectedSessionId = React.useMemo(() => getSelectedSessionIdFromPathname(pathname), [pathname]);

    const sessionById = React.useMemo(() => {
        const map = new Map<string, Session>();
        for (const s of sessions) map.set(s.id, s);
        return map;
    }, [sessions]);

    const initialExpanded = React.useMemo(() => {
        if (Platform.OS === 'web' && typeof window !== 'undefined') {
            const stored = safeParseJson<unknown>(window.localStorage.getItem(LOCAL_STORAGE_KEY));
            const migrated = migrateExpandedMap(stored);
            if (migrated) return migrated;
        }
        return {} as Record<string, boolean>;
    }, []);

    const [expanded, setExpanded] = React.useState<Record<string, boolean>>(initialExpanded);

    const activeSessionIds = React.useMemo(() => new Set(sessions.map((s) => s.id)), [sessions]);

    React.useEffect(() => {
        if (Platform.OS === 'web') return;
        let cancelled = false;
        void (async () => {
            try {
                const raw = await AsyncStorage.getItem(LOCAL_STORAGE_KEY);
                const parsed = safeParseJson<unknown>(raw);
                const migrated = migrateExpandedMap(parsed);
                if (cancelled) return;
                if (migrated) setExpanded(migrated);
            } catch {
                // ignore
            }
        })();
        return () => {
            cancelled = true;
        };
    }, []);

    const listContainerRef = React.useRef<View>(null);
    const listPageYRef = React.useRef(0);
    const scrollOffsetRef = React.useRef(0);
    const projectHeaderLayoutsRef = React.useRef(new Map<string, { y: number; height: number }>());
    const projectHeaderRefsRef = React.useRef(new Map<string, React.RefObject<View | null>>());
    const draggingStableIdRef = React.useRef<string | null>(null);
    const draftOrderRef = React.useRef<string[]>([]);
    const lastDragUpdateAtRef = React.useRef(0);
    const lastLayoutAnimAtRef = React.useRef(0);
    const dragStartedAtRef = React.useRef(0);
    const suppressProjectToggleRef = React.useRef(false);
    const dragGrabOffsetRef = React.useRef(0);
    const dragRowHeightRef = React.useRef(0);

    const [draggingStableId, setDraggingStableId] = React.useState<string | null>(null);
    const listPageY = useSharedValue(0);
    const listPageYReady = useSharedValue(0);
    const dragOverlayTop = useSharedValue(0);
    const dragStartOverlayTop = useSharedValue(0);
    const dragIsActive = useSharedValue(0);
    const dragScale = useSharedValue(1);
    const dragGrabOffset = useSharedValue(0);

    // Reanimated: avoid passing inline/anonymous functions to `runOnJS` from a worklet.
    const setSuppressProjectToggle = React.useCallback((v: boolean) => {
        suppressProjectToggleRef.current = v;
    }, []);

    const suppressProjectToggleFor = React.useCallback((ms: number) => {
        suppressProjectToggleRef.current = true;
        setTimeout(() => {
            suppressProjectToggleRef.current = false;
        }, ms);
    }, []);

    const ensureProjectHeaderRef = React.useCallback((stableId: string) => {
        const existing = projectHeaderRefsRef.current.get(stableId);
        if (existing) return existing;
        const created = React.createRef<View>();
        projectHeaderRefsRef.current.set(stableId, created);
        return created;
    }, []);

    React.useEffect(() => {
        dragIsActive.value = withTiming(draggingStableId ? 1 : 0, { duration: 120 });
    }, [dragIsActive, draggingStableId]);

    React.useEffect(() => {
        dragScale.value = withTiming(draggingStableId ? 1.03 : 1, { duration: 120 });
    }, [dragScale, draggingStableId]);

    React.useEffect(() => {
        if (Platform.OS !== 'android') return;
        if (!UIManager.setLayoutAnimationEnabledExperimental) return;
        UIManager.setLayoutAnimationEnabledExperimental(true);
    }, []);

    const initialWorkspaceOrder = React.useMemo(() => {
        if (Platform.OS === 'web' && typeof window !== 'undefined') {
            const parsed = safeParseJson<unknown>(window.localStorage.getItem(WORKSPACE_ORDER_KEY));
            if (Array.isArray(parsed) && parsed.every((v) => typeof v === 'string')) return parsed as string[];
        }
        return null;
    }, []);

    const [workspaceOrderLoaded, setWorkspaceOrderLoaded] = React.useState(Platform.OS === 'web');
    const [workspaceOrder, setWorkspaceOrder] = React.useState<string[] | null>(initialWorkspaceOrder);
    const commitWorkspaceOrder = React.useCallback((next: string[]) => {
        setWorkspaceOrder(next);
        void saveWorkspaceOrder(next);
    }, []);

    React.useEffect(() => {
        if (Platform.OS === 'web') return;
        let cancelled = false;
        void (async () => {
            const loaded = await loadWorkspaceOrder();
            if (cancelled) return;
            setWorkspaceOrder(loaded);
            setWorkspaceOrderLoaded(true);
        })();
        return () => {
            cancelled = true;
        };
    }, []);

    React.useEffect(() => {
        if (!selectedSessionId) return;
        const s = sessionById.get(selectedSessionId);
        const machineId = s?.metadata?.machineId;
        const path = s?.metadata?.path;
        if (!machineId || !path) return;
        const stableId = `${machineId}:${path}`;

        const basePath = isWorktreePath(path) ? (getWorktreeBasePath(path) || path) : path;
        const baseStableId = `${machineId}:${basePath}`;

        setExpanded((prev) => {
            const projectKey = getExpandedKey('project', baseStableId);
            const shouldExpandProject = prev[projectKey] !== true;

            if (isWorktreePath(path)) {
                const worktreeKey = getExpandedKey('worktree', stableId);
                const shouldExpandWorktree = prev[worktreeKey] !== true;

                // Important: avoid returning a new object when nothing changed.
                // This effect runs whenever `sessionById` changes (which can be frequent),
                // and returning a fresh object here would cause an infinite re-render loop.
                if (!shouldExpandProject && !shouldExpandWorktree) return prev;

                return {
                    ...prev,
                    ...(shouldExpandProject ? { [projectKey]: true } : {}),
                    ...(shouldExpandWorktree ? { [worktreeKey]: true } : {}),
                };
            }

            if (!shouldExpandProject) return prev;
            return { ...prev, [projectKey]: true };
        });
    }, [selectedSessionId, sessionById]);

    React.useEffect(() => {
        try {
            const raw = JSON.stringify(expanded);
            if (Platform.OS === 'web') {
                if (typeof window === 'undefined') return;
                window.localStorage.setItem(LOCAL_STORAGE_KEY, raw);
                return;
            }
            void AsyncStorage.setItem(LOCAL_STORAGE_KEY, raw);
        } catch {
            // ignore
        }
    }, [expanded]);

    const toggleExpanded = React.useCallback((expandedKey: string) => {
        if (draggingStableIdRef.current) return;
        if (Platform.OS !== 'web') {
            LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
        }
        setExpanded((prev) => ({ ...prev, [expandedKey]: !(prev[expandedKey] ?? DEFAULT_EXPANDED) }));
    }, []);

    const projectGroups: ProjectGroup[] = React.useMemo(() => {
        const realProjectByStableId = new Map<string, Project>();
        for (const p of projects) realProjectByStableId.set(getProjectStableId(p), p);

        const groups = new Map<string, ProjectGroup>();

        const ensureGroup = (stableId: string, project: Project, isVirtual: boolean) => {
            const existing = groups.get(stableId);
            if (!existing) {
                groups.set(stableId, {
                    stableId,
                    project,
                    isVirtual,
                    worktrees: [],
                    updatedAt: project.updatedAt,
                });
                return;
            }

            // Prefer the real project if we previously created a virtual placeholder.
            if (existing.isVirtual && !isVirtual) {
                existing.project = project;
                existing.isVirtual = false;
            }
            existing.updatedAt = Math.max(existing.updatedAt, project.updatedAt);
        };

        const createVirtualProject = (machineId: string, basePath: string, template?: Project): Project => {
            const now = Date.now();
            return {
                id: `virtual_${machineId}:${basePath}`,
                key: { machineId, path: basePath },
                sessionIds: [],
                machineMetadata: template?.machineMetadata ?? null,
                gitStatus: template?.gitStatus ?? null,
                lastGitStatusUpdate: template?.lastGitStatusUpdate,
                createdAt: template?.createdAt ?? now,
                updatedAt: template?.updatedAt ?? now,
            };
        };

        // 1) Ensure groups for all non-worktree projects (top-level workspaces).
        for (const project of projects) {
            const stableId = getProjectStableId(project);
            if (isWorktreePath(project.key.path)) continue;
            ensureGroup(stableId, project, false);
        }

        // 2) Attach worktrees under their base project, creating a virtual base if needed.
        for (const project of projects) {
            if (!isWorktreePath(project.key.path)) continue;
            const basePath = getWorktreeBasePath(project.key.path);
            if (!basePath) continue;

            const parentStableId = `${project.key.machineId}:${basePath}`;
            const parentReal = realProjectByStableId.get(parentStableId);
            ensureGroup(
                parentStableId,
                parentReal ?? createVirtualProject(project.key.machineId, basePath, project),
                !parentReal
            );

            const group = groups.get(parentStableId)!;
            group.worktrees.push(project);
            group.updatedAt = Math.max(group.updatedAt, project.updatedAt);
        }

        return Array.from(groups.values());
    }, [projects]);

    const visibleProjectGroups = React.useMemo(() => {
        if (!activeSessionIds.size) return [];

        // Only show workspaces/worktrees that have at least one active (unarchived) session.
        // "Delete workspace" is implemented by archiving all sessions under that workspace.
        const out: ProjectGroup[] = [];
        for (const g of projectGroups) {
            const activeWorktrees = g.worktrees.filter((wt) => (wt.sessionIds || []).some((id) => activeSessionIds.has(id)));
            const hasActiveRoot = (g.project.sessionIds || []).some((id) => activeSessionIds.has(id));
            if (!hasActiveRoot && activeWorktrees.length === 0) continue;
            out.push({ ...g, worktrees: activeWorktrees });
        }
        return out;
    }, [activeSessionIds, projectGroups]);

    const defaultWorkspaceOrder = React.useMemo(() => {
        return [...visibleProjectGroups].sort((a, b) => b.updatedAt - a.updatedAt).map((g) => g.stableId);
    }, [visibleProjectGroups]);

    React.useEffect(() => {
        if (!workspaceOrderLoaded) return;
        if (visibleProjectGroups.length === 0) return;
        if (draggingStableIdRef.current) return;

        // First run: freeze a default order so the sidebar doesn't keep jumping as `updatedAt` changes.
        if (!workspaceOrder) {
            commitWorkspaceOrder(defaultWorkspaceOrder);
            return;
        }

        const stableIds = visibleProjectGroups.map((g) => g.stableId);
        const normalized = normalizeWorkspaceOrder(workspaceOrder, stableIds);
        if (!arraysEqual(normalized, workspaceOrder)) commitWorkspaceOrder(normalized);
    }, [commitWorkspaceOrder, defaultWorkspaceOrder, visibleProjectGroups, workspaceOrder, workspaceOrderLoaded]);

    const orderedGroupStableIds = React.useMemo(() => {
        const stableIds = visibleProjectGroups.map((g) => g.stableId);
        const base = workspaceOrderLoaded ? (workspaceOrder ?? defaultWorkspaceOrder) : defaultWorkspaceOrder;
        return normalizeWorkspaceOrder(base, stableIds);
    }, [defaultWorkspaceOrder, visibleProjectGroups, workspaceOrder, workspaceOrderLoaded]);

    const allExpandableKeys = React.useMemo(() => {
        const keys: string[] = [];
        for (const group of visibleProjectGroups) {
            keys.push(getExpandedKey('project', group.stableId));
            for (const wt of group.worktrees) {
                keys.push(getExpandedKey('worktree', getProjectStableId(wt)));
            }
        }
        return keys;
    }, [visibleProjectGroups]);

    const allExpanded = React.useMemo(() => {
        if (!allExpandableKeys.length) return true;
        return allExpandableKeys.every((k) => (expanded[k] ?? DEFAULT_EXPANDED) === true);
    }, [allExpandableKeys, expanded]);

    const toggleAllExpanded = React.useCallback(() => {
        if (draggingStableIdRef.current) return;
        if (!allExpandableKeys.length) return;
        if (Platform.OS !== 'web') {
            LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
        }
        const nextValue = !allExpanded;
        setExpanded((prev) => {
            const next = { ...prev };
            for (const k of allExpandableKeys) next[k] = nextValue;
            return next;
        });
    }, [allExpanded, allExpandableKeys]);

    const orderedProjectGroups = React.useMemo(() => {
        const map = new Map<string, ProjectGroup>();
        for (const g of visibleProjectGroups) map.set(g.stableId, g);
        return orderedGroupStableIds.map((id) => map.get(id)).filter(Boolean) as ProjectGroup[];
    }, [orderedGroupStableIds, visibleProjectGroups]);

    const groupByStableId = React.useMemo(() => {
        const map = new Map<string, ProjectGroup>();
        for (const g of visibleProjectGroups) map.set(g.stableId, g);
        return map;
    }, [visibleProjectGroups]);

    const [deletingWorkspaceId, setDeletingWorkspaceId] = React.useState<string | null>(null);

    const archiveSessions = React.useCallback(async (workspaceStableId: string, sessionIds: string[]) => {
        if (draggingStableIdRef.current) return;
        if (!sessionIds.length) return;

        setDeletingWorkspaceId(workspaceStableId);
        try {
            // Best-effort: attempt to stop every session process. If some are already dead/offline,
            // treat failures as non-fatal and refresh state afterwards.
            const errors: string[] = [];
            for (const id of sessionIds) {
                const result = await sessionKill(id);
                if (!result.success) errors.push(result.message || 'Failed to archive session');
            }

            await sync.refreshSessions();

            if (errors.length) {
                Modal.alert('Error', errors[0]!, [{ text: 'OK', style: 'cancel' }]);
            }
        } catch (e) {
            if (e instanceof HappyError) {
                Modal.alert('Error', e.message, [{ text: 'OK', style: 'cancel' }]);
            } else {
                Modal.alert('Error', 'Unknown error', [{ text: 'OK', style: 'cancel' }]);
            }
        } finally {
            setDeletingWorkspaceId((cur) => (cur === workspaceStableId ? null : cur));
        }

        // Remove from saved order so it stays removed from the list ordering.
        if (workspaceOrder && workspaceOrder.includes(workspaceStableId)) {
            commitWorkspaceOrder(workspaceOrder.filter((id) => id !== workspaceStableId));
        }
    }, [commitWorkspaceOrder, workspaceOrder]);

    const startWorkspaceDrag = React.useCallback((stableId: string, absoluteY: number) => {
        if (draggingStableIdRef.current) return;

        dragStartedAtRef.current = Date.now();
        draggingStableIdRef.current = stableId;
        suppressProjectToggleRef.current = true;
        draftOrderRef.current = orderedGroupStableIds;
        setDraggingStableId(stableId);

        const layout = projectHeaderLayoutsRef.current.get(stableId);
        const rowHeight = layout?.height ?? 0;
        dragRowHeightRef.current = rowHeight;

        const itemTopInContainer = (layout?.y ?? 0) - scrollOffsetRef.current;
        dragStartOverlayTop.value = itemTopInContainer;
        dragOverlayTop.value = itemTopInContainer;

        // Reasonable default until we have a container window measurement.
        const defaultGrabOffset = rowHeight > 0 ? rowHeight / 2 : 0;
        dragGrabOffsetRef.current = defaultGrabOffset;
        dragGrabOffset.value = defaultGrabOffset;

        // Measure container's window Y so we can keep the exact grab point under the pointer.
        try {
            listContainerRef.current?.measureInWindow((_x, y) => {
                listPageYRef.current = y;
                listPageY.value = y;
                listPageYReady.value = 1;
                if (rowHeight > 0) {
                    const itemTopInWindow = y + itemTopInContainer;
                    const grabOffset = Math.max(0, Math.min(rowHeight, absoluteY - itemTopInWindow));
                    dragGrabOffsetRef.current = grabOffset;
                    dragGrabOffset.value = grabOffset;
                    dragOverlayTop.value = absoluteY - y - grabOffset;
                }
            });
        } catch {
            // ignore
        }

        // Auto-collapse the folder while dragging to make reordering less jumpy.
        if (Platform.OS !== 'web') {
            LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
        }
        const projectKey = getExpandedKey('project', stableId);
        setExpanded((prev) => {
            const isExpanded = prev[projectKey] ?? DEFAULT_EXPANDED;
            if (!isExpanded) return prev;
            return { ...prev, [projectKey]: false };
        });
    }, [dragGrabOffset, dragOverlayTop, dragStartOverlayTop, listPageY, listPageYReady, orderedGroupStableIds]);

    const updateWorkspaceDrag = React.useCallback(() => {
        const draggingId = draggingStableIdRef.current;
        if (!draggingId) return;

        const now = Date.now();
        // Let layout settle right after drag starts (especially when we auto-collapse).
        if (now - dragStartedAtRef.current < 60) return;
        if (now - lastDragUpdateAtRef.current < 16) return;
        lastDragUpdateAtRef.current = now;

        // Use the animated overlay position instead of window measurements. This avoids "teleporting"
        // when coordinate conversions are briefly stale on web/desktop.
        const rowCenterY = dragOverlayTop.value + scrollOffsetRef.current + dragRowHeightRef.current / 2;

        const order = draftOrderRef.current;
        if (!order.length) return;

        const remaining = order.filter((id) => id !== draggingId);
        let targetIndex = 0;

        for (const id of remaining) {
            const layout = projectHeaderLayoutsRef.current.get(id);
            if (!layout) continue;
            const centerY = layout.y + layout.height / 2;
            if (rowCenterY > centerY) targetIndex++;
        }

        const nextOrder = [
            ...remaining.slice(0, targetIndex),
            draggingId,
            ...remaining.slice(targetIndex),
        ];

        if (arraysEqual(nextOrder, order)) return;
        draftOrderRef.current = nextOrder;
        if (Platform.OS !== 'web') {
            const last = lastLayoutAnimAtRef.current;
            if (now - last > 50) {
                lastLayoutAnimAtRef.current = now;
                LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
            }
        }
        setWorkspaceOrder(nextOrder);
    }, [dragOverlayTop]);

    const endWorkspaceDrag = React.useCallback(() => {
        const draggingId = draggingStableIdRef.current;
        if (!draggingId) return;

        draggingStableIdRef.current = null;
        setDraggingStableId(null);

        const finalOrder = draftOrderRef.current;
        draftOrderRef.current = [];
        if (finalOrder.length) commitWorkspaceOrder(finalOrder);
    }, [commitWorkspaceOrder]);

    const draggingGroup = React.useMemo(() => {
        if (!draggingStableId) return null;
        return groupByStableId.get(draggingStableId) ?? null;
    }, [draggingStableId, groupByStableId]);

    const draggingOverlayStyle = useAnimatedStyle(() => {
        return {
            opacity: dragIsActive.value,
            top: dragOverlayTop.value,
            transform: [{ scale: dragScale.value }],
        };
    });

    const rows: Row[] = React.useMemo(() => {
        const out: Row[] = [];
        const included = new Set<string>();
        for (const group of orderedProjectGroups) {
            const projectStableId = group.stableId;
            const projectExpandedKey = getExpandedKey('project', projectStableId);
            const isProjectExpanded = expanded[projectExpandedKey] ?? DEFAULT_EXPANDED;

            out.push({
                type: 'project',
                project: group.project,
                expanded: isProjectExpanded,
                isVirtual: group.isVirtual,
                groupStableId: projectStableId,
            });

            // Mark included ids even if collapsed, so we don't duplicate in the "ungrouped" section.
            for (const id of group.project.sessionIds || []) included.add(id);
            for (const wt of group.worktrees) for (const id of wt.sessionIds || []) included.add(id);

            if (!isProjectExpanded) continue;

            const rootSessionIds = group.project.sessionIds || [];
            const rootSessions: Session[] = rootSessionIds
                .map((id) => sessionById.get(id))
                .filter(Boolean) as Session[];
            rootSessions.sort((a, b) => b.updatedAt - a.updatedAt);

            // Sessions and worktrees are siblings under the project, but the "folder" (worktree)
            // should stay visually at the bottom of the list.
            for (const s of rootSessions) out.push({ type: 'session', session: s, depth: 1, groupStableId: projectStableId });

            const worktrees = [...group.worktrees].sort((a, b) => b.updatedAt - a.updatedAt);
            for (const wt of worktrees) {
                const wtStableId = getProjectStableId(wt);
                const wtExpandedKey = getExpandedKey('worktree', wtStableId);
                const isWorktreeExpanded = expanded[wtExpandedKey] ?? DEFAULT_EXPANDED;

                out.push({
                    type: 'worktree',
                    project: wt,
                    expanded: isWorktreeExpanded,
                    parentStableId: projectStableId,
                    groupStableId: projectStableId,
                });

                if (!isWorktreeExpanded) continue;

                const wtSessions: Session[] = (wt.sessionIds || [])
                    .map((id) => sessionById.get(id))
                    .filter(Boolean) as Session[];
                wtSessions.sort((a, b) => b.updatedAt - a.updatedAt);
                for (const s of wtSessions) out.push({ type: 'session', session: s, depth: 2, groupStableId: projectStableId });
            }
        }

        // Fallback: sessions without metadata/project association.
        const ungrouped = sessions
            .filter((s) => !included.has(s.id))
            .sort((a, b) => b.updatedAt - a.updatedAt);
        for (const s of ungrouped) {
            out.push({ type: 'session', session: s, depth: 1, groupStableId: `u:${s.id}` });
        }

        return out;
    }, [expanded, orderedProjectGroups, sessionById, sessions]);

    const attentionCountByStableId = React.useMemo(() => {
        const map = new Map<string, number>();

        for (const group of visibleProjectGroups) {
            let groupCount = 0;

            const rootSessions = group.project.sessionIds || [];
            for (const id of rootSessions) {
                const s = sessionById.get(id);
                if (s && sessionNeedsAttention(s)) groupCount++;
            }

            for (const wt of group.worktrees) {
                const wtStableId = getProjectStableId(wt);
                let wtCount = 0;
                for (const id of wt.sessionIds || []) {
                    const s = sessionById.get(id);
                    if (s && sessionNeedsAttention(s)) wtCount++;
                }
                map.set(wtStableId, wtCount);
                groupCount += wtCount;
            }

            map.set(group.stableId, groupCount);
        }

        return map;
    }, [sessionById, visibleProjectGroups]);

    return (
        <View style={styles.container}>
            <View style={styles.sectionHeader}>
                <Text style={styles.sectionTitle}>Workspaces</Text>
                <View style={styles.headerButtons}>
                    <Pressable
                        onPress={() => router.push('/new')}
                        hitSlop={10}
                        style={({ hovered, pressed }: any) => [
                            styles.headerButton,
                            (Platform.OS === 'web' && (hovered || pressed)) && styles.headerButtonHover,
                        ]}
                        accessibilityLabel="New session"
                    >
                        <Ionicons name="add" size={UI_ICONS.headerAdd} color={theme.colors.header.tint} />
                    </Pressable>
                    <Pressable
                        onPress={toggleAllExpanded}
                        hitSlop={10}
                        style={({ hovered, pressed }: any) => [
                            styles.headerButton,
                            (Platform.OS === 'web' && (hovered || pressed)) && styles.headerButtonHover,
                        ]}
                        accessibilityLabel={allExpanded ? 'Collapse all workspaces' : 'Expand all workspaces'}
                    >
                        <Ionicons
                            name={allExpanded ? 'chevron-up-outline' : 'chevron-down-outline'}
                            size={UI_ICONS.headerCollapse}
                            color={theme.colors.header.tint}
                        />
                    </Pressable>
                </View>
            </View>

            <View
                ref={listContainerRef}
                onLayout={() => {
                    try {
                        listContainerRef.current?.measureInWindow((_x, y) => {
                            listPageYRef.current = y;
                            listPageY.value = y;
                            listPageYReady.value = 1;
                        });
                    } catch {
                        // ignore
                    }
                }}
                style={{ flex: 1, position: 'relative' }}
            >
                <FlatList
                    data={rows}
                    keyExtractor={(row) => {
                        if (row.type === 'project') return `p:${getProjectStableId(row.project)}`;
                        if (row.type === 'worktree') return `w:${getProjectStableId(row.project)}`;
                        return `s:${row.session.id}`;
                    }}
                    ListEmptyComponent={() => {
                        return (
                            <View style={styles.emptyState}>
                                <Text style={styles.emptyStateTitle}>
                                    {'No active workspaces'}
                                </Text>
                                <Text style={styles.emptyStateSubtitle}>
                                    {'Create a new session to add a workspace.'}
                                </Text>
                                <Pressable
                                    onPress={() => router.push('/new')}
                                    style={({ hovered, pressed }: any) => [
                                        styles.emptyStateButton,
                                        (Platform.OS === 'web' && (hovered || pressed)) && styles.emptyStateButtonHover,
                                        pressed && styles.rowPressed,
                                    ]}
                                    accessibilityLabel="New session"
                                >
                                    <Text style={styles.emptyStateButtonText}>New session</Text>
                                </Pressable>
                            </View>
                        );
                    }}
                    // This view can be rendered with a bottom overlay (e.g. a floating "new session" button on tablet).
                    // Add extra bottom padding so the last rows can scroll above the overlay.
                    contentContainerStyle={[styles.list, { paddingBottom: insets.bottom + 16 + bottomPaddingExtra }]}
                    scrollEnabled={!draggingStableId}
                    removeClippedSubviews={false}
                    onScroll={(e) => {
                        scrollOffsetRef.current = e.nativeEvent.contentOffset.y;
                    }}
                    scrollEventThrottle={16}
                    renderItem={({ item: row, index }) => {
                        const groupStableId = row.groupStableId;
                        const prevGroupStableId = index > 0 ? rows[index - 1].groupStableId : null;
                        const nextGroupStableId = index < rows.length - 1 ? rows[index + 1].groupStableId : null;

                        const isGroupStart = groupStableId !== prevGroupStableId;
                        const isGroupEnd = groupStableId !== nextGroupStableId;
                        const isUngrouped = groupStableId.startsWith('u:');
                        const groupAccent = !isUngrouped && (row.type !== 'project' || row.expanded);

                        const groupChromeStyle = {
                            // Make each workspace feel like a single expandable "card".
                            marginVertical: 0,
                            marginTop: isGroupStart ? 6 : 0,
                            marginBottom: isGroupEnd ? 6 : 0,
                            borderRadius: 0,
                            borderTopLeftRadius: isGroupStart ? UI_METRICS.rowRadius : 0,
                            borderTopRightRadius: isGroupStart ? UI_METRICS.rowRadius : 0,
                            borderBottomLeftRadius: isGroupEnd ? UI_METRICS.rowRadius : 0,
                            borderBottomRightRadius: isGroupEnd ? UI_METRICS.rowRadius : 0,
                            borderTopWidth: StyleSheet.hairlineWidth,
                            borderBottomWidth: isGroupEnd ? StyleSheet.hairlineWidth : 0,
                            borderRightWidth: StyleSheet.hairlineWidth,
                            borderLeftWidth: groupAccent ? 3 : StyleSheet.hairlineWidth,
                            borderColor: theme.colors.chrome.panelBorder,
                            // Keep the expand/collapse "group stripe" neutral.
                            borderLeftColor: groupAccent ? theme.colors.groupped.sectionTitle : theme.colors.chrome.panelBorder,
                            backgroundColor:
                                row.type === 'project' && row.expanded
                                    ? theme.colors.surfaceHighest
                                    : row.type === 'worktree' && row.expanded
                                        ? theme.colors.surfaceHigh
                                        : row.type === 'session' && row.depth === 2
                                            ? theme.colors.surfaceHigh
                                    : theme.colors.surface,
                        } as const;

                        if (row.type === 'project') {
                            const stableId = getProjectStableId(row.project);
                            const expandedKey = getExpandedKey('project', stableId);
                            const title = getBasename(row.project.key.path);
                            const hasGitStatus = row.project.gitStatus != null;
                            const branch = row.project.gitStatus?.branch;
                            const isDirty = row.project.gitStatus?.isDirty === true;
                            const attentionCount = attentionCountByStableId.get(stableId) ?? 0;
                            const badgeText = formatBadgeCount(attentionCount);
                            const machineName =
                                row.project.machineMetadata?.displayName ||
                                row.project.machineMetadata?.host ||
                                row.project.key.machineId;

                            const headerRef = ensureProjectHeaderRef(stableId);

                            const reorderGesture = Gesture.Pan()
                                .activateAfterLongPress(250)
                                .onBegin(() => {
                                    'worklet';
                                    // The handle lives inside a Pressable row that toggles expansion.
                                    // If the long-press drag doesn't activate (or activates slightly late),
                                    // we still don't want the row "click" to toggle.
                                    runOnJS(setSuppressProjectToggle)(true);
                                })
                                .onStart((e) => {
                                    'worklet';
                                    runOnJS(startWorkspaceDrag)(stableId, e.absoluteY);
                                })
                                .onUpdate((e) => {
                                    'worklet';
                                    if (listPageYReady.value) {
                                        dragOverlayTop.value = (e.absoluteY - listPageY.value) - dragGrabOffset.value;
                                    } else {
                                        dragOverlayTop.value = dragStartOverlayTop.value + e.translationY;
                                    }
                                    runOnJS(updateWorkspaceDrag)();
                                })
                                .onFinalize(() => {
                                    'worklet';
                                    // Keep suppression through the release -> onPress sequence.
                                    runOnJS(suppressProjectToggleFor)(250);
                                    runOnJS(endWorkspaceDrag)();
                                });

                            return (
                                <Animated.View layout={LinearTransition.duration(140)}>
                                    <Pressable
                                        ref={headerRef as any}
                                        onLayout={(e) => {
                                            const fallbackHeight = e.nativeEvent.layout.height;
                                            const store = (absoluteY: number, measuredHeight?: number) => {
                                                // Convert window Y -> list content Y
                                                const yInContent = absoluteY - listPageYRef.current + scrollOffsetRef.current;
                                                projectHeaderLayoutsRef.current.set(stableId, {
                                                    y: yInContent,
                                                    height: measuredHeight ?? fallbackHeight,
                                                });
                                            };

                                            // We need absolute coordinates; `layout.y` here is relative to the cell wrapper,
                                            // and is typically 0 for every row (which breaks drag targeting).
                                            try {
                                                const node = headerRef.current as any;
                                                if (node?.measureInWindow) {
                                                    // Ensure we have the container's window Y before converting coordinates.
                                                    if (!listPageYRef.current && listContainerRef.current?.measureInWindow) {
                                                        listContainerRef.current.measureInWindow((_x: number, y: number) => {
                                                            listPageYRef.current = y;
                                                            listPageY.value = y;
                                                            listPageYReady.value = 1;
                                                            node.measureInWindow((_ix: number, iy: number, _w: number, ih: number) => {
                                                                store(iy, ih || fallbackHeight);
                                                            });
                                                        });
                                                    } else {
                                                        node.measureInWindow((_ix: number, iy: number, _w: number, ih: number) => {
                                                            store(iy, ih || fallbackHeight);
                                                        });
                                                    }
                                                } else {
                                                    // Best-effort fallback (may be 0 in some environments). Don't clobber
                                                    // a previously measured absolute position with a likely-wrong 0.
                                                    const prev = projectHeaderLayoutsRef.current.get(stableId);
                                                    if (prev) {
                                                        projectHeaderLayoutsRef.current.set(stableId, { ...prev, height: fallbackHeight });
                                                    } else {
                                                        projectHeaderLayoutsRef.current.set(stableId, {
                                                            y: e.nativeEvent.layout.y,
                                                            height: fallbackHeight,
                                                        });
                                                    }
                                                }
                                            } catch {
                                                const prev = projectHeaderLayoutsRef.current.get(stableId);
                                                if (prev) {
                                                    projectHeaderLayoutsRef.current.set(stableId, { ...prev, height: fallbackHeight });
                                                } else {
                                                    projectHeaderLayoutsRef.current.set(stableId, {
                                                        y: e.nativeEvent.layout.y,
                                                        height: fallbackHeight,
                                                    });
                                                }
                                            }
                                        }}
                                        onPress={() => {
                                            if (suppressProjectToggleRef.current) return;
                                            toggleExpanded(expandedKey);
                                        }}
                                        style={({ hovered, pressed }: any) => [
                                            styles.row,
                                            groupChromeStyle,
                                            (IS_WEB && hovered) && styles.rowHover,
                                            pressed && styles.rowPressed,
                                            draggingStableId === stableId && { opacity: 0 },
                                        ]}
                                    >
                                        <GestureDetector gesture={reorderGesture}>
                                            <View style={styles.rowActionButton}>
                                                <Ionicons
                                                    name="reorder-three-outline"
                                                    size={UI_ICONS.reorderHandle}
                                                    color={theme.colors.textSecondary}
                                                />
                                            </View>
                                        </GestureDetector>
                                        <View style={styles.textBlock}>
                                            <Text style={styles.title} numberOfLines={1}>
                                                {title}
                                            </Text>
                                            <View style={styles.subtitleRow}>
                                                {hasGitStatus && (
                                                    <>
                                                        <Octicons name="git-branch" size={UI_ICONS.gitBranch} color={theme.colors.textSecondary} />
                                                        <Text style={styles.subtitle} numberOfLines={1}>
                                                            {branch || 'detached'}
                                                        </Text>
                                                    </>
                                                )}
                                                <Text style={styles.subtitle} numberOfLines={1}>
                                                    {machineName}
                                                </Text>
                                            </View>
                                        </View>
                                        <View style={styles.projectActions}>
                                            {attentionCount > 0 && (
                                                <View
                                                    style={styles.badge}
                                                    accessibilityLabel={`${attentionCount} notifications`}
                                                >
                                                    <Text style={styles.badgeText}>{badgeText}</Text>
                                                </View>
                                            )}
                                            <RowActionMenu actions={(() => {
                                                const actions: RowAction[] = [
                                                    {
                                                        key: 'add-session',
                                                        label: t('newSession.startNewSessionInFolder'),
                                                        icon: 'add',
                                                        onPress: () => {
                                                            router.push({
                                                                pathname: '/new',
                                                                params: { machineId: row.project.key.machineId, path: row.project.key.path },
                                                            });
                                                        },
                                                    },
                                                ];
                                                if (isDirty) {
                                                    actions.push({
                                                        key: 'review-diff',
                                                        label: t('files.diff'),
                                                        icon: 'file-diff',
                                                        iconPack: 'octicons',
                                                        onPress: () => {
                                                            const group = groupByStableId.get(stableId);
                                                            const rootActiveIds = (row.project.sessionIds || []).filter((id) => activeSessionIds.has(id));
                                                            const worktreeActiveIds = group
                                                                ? group.worktrees.flatMap((wt) => (wt.sessionIds || []).filter((id) => activeSessionIds.has(id)))
                                                                : [];
                                                            const pickPreferred = (ids: string[]) => {
                                                                if (!ids.length) return null;
                                                                if (selectedSessionId && ids.includes(selectedSessionId)) return selectedSessionId;
                                                                const best = ids
                                                                    .map((id) => sessionById.get(id))
                                                                    .filter((s): s is Session => Boolean(s))
                                                                    .sort((a, b) => b.updatedAt - a.updatedAt)[0]?.id;
                                                                return best ?? ids[0] ?? null;
                                                            };
                                                            const preferred = pickPreferred(rootActiveIds) ?? pickPreferred(worktreeActiveIds);
                                                            if (preferred) router.push(`/session/${preferred}/review`);
                                                        },
                                                    });
                                                }
                                                actions.push({
                                                    key: 'delete',
                                                    label: t('workspaceExplorer.deleteWorkspace'),
                                                    icon: 'trash',
                                                    destructive: true,
                                                    onPress: async () => {
                                                        const confirmed = await Modal.confirm(
                                                            t('workspaceExplorer.deleteWorkspace'),
                                                            t('workspaceExplorer.deleteWorkspaceConfirm'),
                                                            { destructive: true },
                                                        );
                                                        if (!confirmed) return;
                                                        const group = groupByStableId.get(stableId);
                                                        const ids = new Set<string>();
                                                        if (group) {
                                                            for (const id of group.project.sessionIds || []) {
                                                                if (activeSessionIds.has(id)) ids.add(id);
                                                            }
                                                            for (const wt of group.worktrees) {
                                                                for (const id of wt.sessionIds || []) {
                                                                    if (activeSessionIds.has(id)) ids.add(id);
                                                                }
                                                            }
                                                        }
                                                        void archiveSessions(stableId, Array.from(ids));
                                                    },
                                                });
                                                return actions;
                                            })()} />
                                        </View>
                                    </Pressable>
                                </Animated.View>
                            );
                        }

                        if (row.type === 'worktree') {
                            const stableId = getProjectStableId(row.project);
                            const expandedKey = getExpandedKey('worktree', stableId);

                            const title = getBasename(row.project.key.path);
                            const hasGitStatus = row.project.gitStatus != null;
                            const branch = row.project.gitStatus?.branch;
                            const isDirty = row.project.gitStatus?.isDirty === true;
                            const attentionCount = attentionCountByStableId.get(stableId) ?? 0;
                            const badgeText = formatBadgeCount(attentionCount);
                            const machineName =
                                row.project.machineMetadata?.displayName ||
                                row.project.machineMetadata?.host ||
                                row.project.key.machineId;

                            return (
                                <Animated.View
                                    layout={LinearTransition.duration(140)}
                                    entering={FadeIn.duration(140)}
                                    exiting={FadeOut.duration(120)}
                                >
                                    <Pressable
                                        onPress={() => toggleExpanded(expandedKey)}
                                        style={({ hovered, pressed }: any) => [
                                            styles.row,
                                            groupChromeStyle,
                                            styles.mobileIndent1,
                                            (IS_WEB && hovered) && styles.rowHover,
                                            pressed && styles.rowPressed,
                                        ]}
                                    >
                                        {/* Keep alignment consistent with session rows (which reserve a chevron slot). */}
                                        <View style={styles.chevron}>
                                            <>
                                                <View style={styles.nestRail} />
                                                <View style={styles.treeDotWrap} pointerEvents="none">
                                                    <View style={[styles.treeDot, styles.treeDotWorktree]} />
                                                </View>
                                            </>
                                        </View>
                                        <View style={styles.icon}>
                                            <Octicons name="file-directory" size={UI_ICONS.folder} color={theme.colors.textSecondary} />
                                        </View>
                                        <View style={styles.textBlock}>
                                            <Text style={styles.title} numberOfLines={1}>
                                                {title}
                                            </Text>
                                            <View style={styles.subtitleRow}>
                                                <Text style={styles.subtitle} numberOfLines={1}>
                                                    worktree
                                                </Text>
                                                {hasGitStatus && (
                                                    <>
                                                        <Octicons name="git-branch" size={UI_ICONS.gitBranch} color={theme.colors.textSecondary} />
                                                        <Text style={styles.subtitle} numberOfLines={1}>
                                                            {branch || 'detached'}
                                                        </Text>
                                                    </>
                                                )}
                                                <Text style={styles.subtitle} numberOfLines={1}>
                                                    {machineName}
                                                </Text>
                                            </View>
                                        </View>
                                        <View style={styles.projectActions}>
                                            {attentionCount > 0 && (
                                                <View
                                                    style={styles.badge}
                                                    accessibilityLabel={`${attentionCount} notifications`}
                                                >
                                                    <Text style={styles.badgeText}>{badgeText}</Text>
                                                </View>
                                            )}
                                            <RowActionMenu actions={(() => {
                                                const actions: RowAction[] = [
                                                    {
                                                        key: 'add-session',
                                                        label: t('newSession.startNewSessionInFolder'),
                                                        icon: 'add',
                                                        onPress: () => {
                                                            router.push({
                                                                pathname: '/new',
                                                                params: { machineId: row.project.key.machineId, path: row.project.key.path },
                                                            });
                                                        },
                                                    },
                                                ];
                                                if (isDirty) {
                                                    actions.push({
                                                        key: 'review-diff',
                                                        label: t('files.diff'),
                                                        icon: 'file-diff',
                                                        iconPack: 'octicons',
                                                        onPress: () => {
                                                            const allIds = row.project.sessionIds || [];
                                                            const activeIds = allIds.filter((id) => activeSessionIds.has(id));
                                                            const candidates = activeIds.length ? activeIds : allIds;
                                                            if (candidates.length === 0) return;
                                                            const preferred =
                                                                selectedSessionId && candidates.includes(selectedSessionId)
                                                                    ? selectedSessionId
                                                                    : candidates[0];
                                                            router.push(`/session/${preferred}/review`);
                                                        },
                                                    });
                                                }
                                                actions.push({
                                                    key: 'delete',
                                                    label: t('workspaceExplorer.deleteWorktree'),
                                                    icon: 'trash',
                                                    destructive: true,
                                                    onPress: async () => {
                                                        const confirmed = await Modal.confirm(
                                                            t('workspaceExplorer.deleteWorktree'),
                                                            t('workspaceExplorer.deleteWorktreeConfirm'),
                                                            { destructive: true },
                                                        );
                                                        if (!confirmed) return;
                                                        const ids = (row.project.sessionIds || []).filter((id) => activeSessionIds.has(id));
                                                        void archiveSessions(stableId, ids);
                                                    },
                                                });
                                                return actions;
                                            })()} />
                                        </View>
                                    </Pressable>
                                </Animated.View>
                            );
                        }

            const isSelected = selectedSessionId === row.session.id;
            return (
                <Animated.View
                    layout={LinearTransition.duration(140)}
                    entering={FadeIn.duration(140)}
                    exiting={FadeOut.duration(120)}
                >
                    <WorkspaceExplorerSessionRow
                        session={row.session}
                        selected={isSelected}
                        depth={row.depth}
                        groupChromeStyle={groupChromeStyle}
                    />
                </Animated.View>
            );
        }}
    />
                {draggingGroup && (
                    <Animated.View
                        pointerEvents="none"
                        style={[
                            {
                                position: 'absolute',
                                left: 0,
                                right: 0,
                            },
                            draggingOverlayStyle,
                        ]}
                    >
                        <View
                            style={[
                                styles.row,
                                {
                                    backgroundColor: theme.colors.chrome.listActiveBackground,
                                    borderWidth: 1,
                                    borderColor: theme.colors.chrome.accent,
                                    borderRadius: 10,
                                    shadowColor: '#000',
                                    shadowOpacity: 0.28,
                                    shadowRadius: 14,
                                    shadowOffset: { width: 0, height: 4 },
                                    elevation: 10,
                                },
                            ]}
                        >
                            <View style={styles.rowActionButton}>
                                <Ionicons name="reorder-three-outline" size={UI_ICONS.reorderHandle} color={theme.colors.textSecondary} />
                            </View>
                            <View style={styles.textBlock}>
                                <Text style={styles.title} numberOfLines={1}>
                                    {getBasename(draggingGroup.project.key.path)}
                                </Text>
                                <View style={styles.subtitleRow}>
                                    <Text style={styles.subtitle} numberOfLines={1}>
                                        {draggingGroup.project.machineMetadata?.displayName ||
                                            draggingGroup.project.machineMetadata?.host ||
                                            draggingGroup.project.key.machineId}
                                    </Text>
                                </View>
                            </View>
                        </View>
                    </Animated.View>
                )}
            </View>
        </View>
    );
}
