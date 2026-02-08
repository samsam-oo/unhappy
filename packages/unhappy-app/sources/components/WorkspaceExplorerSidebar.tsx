import { Text } from '@/components/StyledText';
import { Typography } from '@/constants/Typography';
import { useNavigateToSession } from '@/hooks/useNavigateToSession';
import { Ionicons, Octicons } from '@/icons/vector-icons';
import type { Project } from '@/sync/projectManager';
import { useAllSessions, useProjects } from '@/sync/storage';
import type { Session } from '@/sync/storageTypes';
import { t } from '@/text';
import { useSessionStatus } from '@/utils/sessionUtils';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { usePathname, useRouter } from 'expo-router';
import * as React from 'react';
import { ActivityIndicator, FlatList, LayoutAnimation, Platform, Pressable, UIManager, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import Animated, {
    FadeIn,
    FadeOut,
    LinearTransition,
    Easing,
    cancelAnimation,
    runOnJS,
    useAnimatedStyle,
    useSharedValue,
    withRepeat,
    withTiming,
} from 'react-native-reanimated';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';

const LOCAL_STORAGE_KEY = 'happy.workspaceExplorer.expanded.v1';
const WORKSPACE_ORDER_KEY = 'happy.workspaceExplorer.workspaceOrder.v1';

const IS_WEB = Platform.OS === 'web';

// This view is used both in the desktop sidebar and as the phone "Sessions" main screen.
// Keep it readable/tappable on mobile while still reasonably dense on web.
const UI_METRICS = {
    sectionHeaderPaddingV: IS_WEB ? 8 : 10,
    sectionHeaderMinHeight: IS_WEB ? 36 : 44,

    rowMinHeight: IS_WEB ? 34 : 48,
    rowPaddingV: IS_WEB ? 7 : 10,
    rowPaddingH: IS_WEB ? 10 : 12,
    rowMarginV: IS_WEB ? 1 : 2,
    rowRadius: IS_WEB ? 8 : 10,
    rowGap: IS_WEB ? 9 : 10,

    selectionBarInsetV: IS_WEB ? 7 : 10,

    actionButtonSize: IS_WEB ? 28 : 34,
    actionButtonRadius: IS_WEB ? 7 : 9,

    chevronWidth: IS_WEB ? 18 : 20,
    iconWidth: IS_WEB ? 20 : 22,

    // On mobile we prefer inset rows (box moves in), not just indented content.
    childIndent: IS_WEB ? 6 : 0,
    grandChildIndent: IS_WEB ? 32 : 0,
    rowInset1: IS_WEB ? 0 : 16,
    rowInset2: IS_WEB ? 0 : 40,

    nestRailInsetV: IS_WEB ? 6 : 10,
    nestRailWidth: IS_WEB ? 1 : 2,

    titleFontSize: IS_WEB ? 14 : 16,
    titleLineHeight: IS_WEB ? 18 : 20,
    subtitleFontSize: IS_WEB ? 12 : 13,
    subtitleLineHeight: IS_WEB ? 16 : 18,
    subtitleMarginTop: IS_WEB ? 2 : 3,
} as const;

const UI_ICONS = {
    spinner: IS_WEB ? 14 : 16,
    rowIcon: IS_WEB ? 18 : 20,
    chevron: IS_WEB ? 16 : 18,
    folder: IS_WEB ? 16 : 18,
    gitBranch: IS_WEB ? 12 : 13,
    headerAdd: IS_WEB ? 18 : 20,
    rowAdd: IS_WEB ? 18 : 20,
    reorderHandle: IS_WEB ? 18 : 20,
} as const;

function safeParseJson<T>(value: string | null): T | null {
    if (!value) return null;
    try {
        return JSON.parse(value) as T;
    } catch {
        return null;
    }
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

const stylesheet = StyleSheet.create((theme) => ({
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
        fontSize: IS_WEB ? 11 : 12,
        lineHeight: IS_WEB ? 14 : 16,
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

    list: {
        // Avoid a "double padding" feel: the header already provides vertical rhythm.
        paddingTop: IS_WEB ? 4 : 8,
        paddingBottom: IS_WEB ? 6 : 10,
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
        opacity: IS_WEB ? 0.9 : 0.75,
    },
    projectActions: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 2,
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
}));

type Row =
    | { type: 'project'; project: Project; expanded: boolean; isVirtual?: boolean }
    | { type: 'worktree'; project: Project; expanded: boolean; parentStableId: string }
    | { type: 'session'; session: Session; depth: 1 | 2 };

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
}) {
    const styles = stylesheet;
    const { theme } = useUnistyles();
    const navigateToSession = useNavigateToSession();

    const sessionStatus = useSessionStatus(props.session);
    const sessionTitle = props.session.metadata?.summary?.text?.trim() || 'Session';

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

    return (
        <Pressable
            onPress={() => navigateToSession(props.session.id)}
            style={({ hovered, pressed }: any) => [
                styles.row,
                !IS_WEB && (props.depth === 2 ? styles.rowMobileNestedDeep : styles.rowMobileNested),
                !IS_WEB && (props.depth === 2 ? styles.rowMobileInset2 : styles.rowMobileInset1),
                props.depth === 2 ? styles.grandChildIndent : styles.childIndent,
                props.selected && styles.rowActive,
                (IS_WEB && hovered && !props.selected) && styles.rowHover,
                (pressed && !props.selected) && styles.rowPressed,
            ]}
        >
            {props.selected && <View style={styles.selectionBar} />}
            <View style={styles.chevron}>
                {!IS_WEB && (
                    <>
                        <View style={styles.nestRail} />
                    </>
                )}
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
        </Pressable>
    );
});

export function WorkspaceExplorerSidebar() {
    const styles = stylesheet;
    const { theme } = useUnistyles();
    const insets = useSafeAreaInsets();
    const router = useRouter();
    const pathname = usePathname();

    const projects = useProjects();
    const sessions = useAllSessions();

    const selectedSessionId = React.useMemo(() => getSelectedSessionIdFromPathname(pathname), [pathname]);

    const sessionById = React.useMemo(() => {
        const map = new Map<string, Session>();
        for (const s of sessions) map.set(s.id, s);
        return map;
    }, [sessions]);

    const initialExpanded = React.useMemo(() => {
        if (Platform.OS === 'web' && typeof window !== 'undefined') {
            const stored = safeParseJson<Record<string, boolean>>(
                window.localStorage.getItem(LOCAL_STORAGE_KEY)
            );
            if (stored && typeof stored === 'object') {
                // Migration: older versions stored keys as `${machineId}:${path}` without a type prefix.
                const migrated: Record<string, boolean> = {};
                for (const [k, v] of Object.entries(stored)) {
                    if (k.startsWith('p:') || k.startsWith('w:')) migrated[k] = v;
                    else migrated[`p:${k}`] = v;
                }
                return migrated;
            }
        }
        return {} as Record<string, boolean>;
    }, []);

    const [expanded, setExpanded] = React.useState<Record<string, boolean>>(initialExpanded);

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
            const next = { ...prev };

            const projectKey = getExpandedKey('project', baseStableId);
            if (next[projectKey] === false) next[projectKey] = true;

            if (isWorktreePath(path)) {
                const worktreeKey = getExpandedKey('worktree', stableId);
                if (next[worktreeKey] === false) next[worktreeKey] = true;
            }

            return next;
        });
    }, [selectedSessionId, sessionById]);

    React.useEffect(() => {
        if (Platform.OS !== 'web' || typeof window === 'undefined') return;
        try {
            window.localStorage.setItem(LOCAL_STORAGE_KEY, JSON.stringify(expanded));
        } catch {
            // ignore
        }
    }, [expanded]);

    const toggleExpanded = React.useCallback((expandedKey: string) => {
        if (draggingStableIdRef.current) return;
        if (Platform.OS !== 'web') {
            LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
        }
        setExpanded((prev) => ({ ...prev, [expandedKey]: !(prev[expandedKey] ?? true) }));
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

    const defaultWorkspaceOrder = React.useMemo(() => {
        return [...projectGroups].sort((a, b) => b.updatedAt - a.updatedAt).map((g) => g.stableId);
    }, [projectGroups]);

    React.useEffect(() => {
        if (!workspaceOrderLoaded) return;
        if (projectGroups.length === 0) return;
        if (draggingStableIdRef.current) return;

        // First run: freeze a default order so the sidebar doesn't keep jumping as `updatedAt` changes.
        if (!workspaceOrder) {
            commitWorkspaceOrder(defaultWorkspaceOrder);
            return;
        }

        const stableIds = projectGroups.map((g) => g.stableId);
        const normalized = normalizeWorkspaceOrder(workspaceOrder, stableIds);
        if (!arraysEqual(normalized, workspaceOrder)) commitWorkspaceOrder(normalized);
    }, [commitWorkspaceOrder, defaultWorkspaceOrder, projectGroups, workspaceOrder, workspaceOrderLoaded]);

    const orderedGroupStableIds = React.useMemo(() => {
        const stableIds = projectGroups.map((g) => g.stableId);
        const base = workspaceOrderLoaded ? (workspaceOrder ?? defaultWorkspaceOrder) : defaultWorkspaceOrder;
        return normalizeWorkspaceOrder(base, stableIds);
    }, [defaultWorkspaceOrder, projectGroups, workspaceOrder, workspaceOrderLoaded]);

    const orderedProjectGroups = React.useMemo(() => {
        const map = new Map<string, ProjectGroup>();
        for (const g of projectGroups) map.set(g.stableId, g);
        return orderedGroupStableIds.map((id) => map.get(id)).filter(Boolean) as ProjectGroup[];
    }, [orderedGroupStableIds, projectGroups]);

    const groupByStableId = React.useMemo(() => {
        const map = new Map<string, ProjectGroup>();
        for (const g of projectGroups) map.set(g.stableId, g);
        return map;
    }, [projectGroups]);

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
            const isExpanded = prev[projectKey] ?? true;
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
            const isProjectExpanded = expanded[projectExpandedKey] ?? true;

            out.push({ type: 'project', project: group.project, expanded: isProjectExpanded, isVirtual: group.isVirtual });

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
            for (const s of rootSessions) out.push({ type: 'session', session: s, depth: 1 });

            const worktrees = [...group.worktrees].sort((a, b) => b.updatedAt - a.updatedAt);
            for (const wt of worktrees) {
                const wtStableId = getProjectStableId(wt);
                const wtExpandedKey = getExpandedKey('worktree', wtStableId);
                const isWorktreeExpanded = expanded[wtExpandedKey] ?? true;

                out.push({ type: 'worktree', project: wt, expanded: isWorktreeExpanded, parentStableId: projectStableId });

                if (!isWorktreeExpanded) continue;

                const wtSessions: Session[] = (wt.sessionIds || [])
                    .map((id) => sessionById.get(id))
                    .filter(Boolean) as Session[];
                wtSessions.sort((a, b) => b.updatedAt - a.updatedAt);
                for (const s of wtSessions) out.push({ type: 'session', session: s, depth: 2 });
            }
        }

        // Fallback: sessions without metadata/project association.
        const ungrouped = sessions
            .filter((s) => !included.has(s.id))
            .sort((a, b) => b.updatedAt - a.updatedAt);
        for (const s of ungrouped) {
            out.push({ type: 'session', session: s, depth: 1 });
        }

        return out;
    }, [expanded, orderedProjectGroups, sessionById, sessions]);

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
                    contentContainerStyle={[styles.list, { paddingBottom: insets.bottom + 16 }]}
                    scrollEnabled={!draggingStableId}
                    removeClippedSubviews={false}
                    onScroll={(e) => {
                        scrollOffsetRef.current = e.nativeEvent.contentOffset.y;
                    }}
                    scrollEventThrottle={16}
                    renderItem={({ item: row }) => {
                        if (row.type === 'project') {
                            const stableId = getProjectStableId(row.project);
                            const expandedKey = getExpandedKey('project', stableId);
                            const title = getBasename(row.project.key.path);
                            const hasGitStatus = row.project.gitStatus != null;
                            const branch = row.project.gitStatus?.branch;
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
                                    runOnJS(() => {
                                        suppressProjectToggleRef.current = true;
                                    })();
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
                                    runOnJS(endWorkspaceDrag)();
                                    runOnJS(() => {
                                        // Keep suppression through the release -> onPress sequence.
                                        suppressProjectToggleRef.current = true;
                                        setTimeout(() => {
                                            suppressProjectToggleRef.current = false;
                                        }, 250);
                                    })();
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
                                            !IS_WEB && styles.rowMobileBase,
                                            !IS_WEB && styles.rowMobileRoot,
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
                                            <Pressable
                                                hitSlop={10}
                                                onPress={(e: any) => {
                                                    if (draggingStableIdRef.current) return;
                                                    e?.stopPropagation?.();
                                                    router.push({
                                                        pathname: '/new',
                                                        params: { machineId: row.project.key.machineId, path: row.project.key.path },
                                                    });
                                                }}
                                                style={({ hovered, pressed }: any) => [
                                                    styles.rowActionButton,
                                                    (Platform.OS === 'web' && (hovered || pressed)) && styles.headerButtonHover,
                                                ]}
                                                accessibilityLabel={t('newSession.startNewSessionInFolder')}
                                            >
                                                <Ionicons name="add" size={UI_ICONS.rowAdd} color={theme.colors.textSecondary} />
                                            </Pressable>
                                            <View style={styles.chevron}>
                                                <Ionicons
                                                    name={row.expanded ? 'chevron-down' : 'chevron-forward'}
                                                    size={UI_ICONS.chevron}
                                                    color={theme.colors.textSecondary}
                                                />
                                            </View>
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
                                            !IS_WEB && styles.rowMobileNested,
                                            !IS_WEB && styles.rowMobileInset1,
                                            styles.childIndent,
                                            (IS_WEB && hovered) && styles.rowHover,
                                            pressed && styles.rowPressed,
                                        ]}
                                    >
                                        {/* Keep alignment consistent with session rows (which reserve a chevron slot). */}
                                        <View style={styles.chevron}>
                                            {!IS_WEB && (
                                                <>
                                                    <View style={styles.nestRail} />
                                                </>
                                            )}
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
                                            <Pressable
                                                hitSlop={10}
                                                onPress={(e: any) => {
                                                    e?.stopPropagation?.();
                                                    router.push({
                                                        pathname: '/new',
                                                        params: { machineId: row.project.key.machineId, path: row.project.key.path },
                                                    });
                                                }}
                                                style={({ hovered, pressed }: any) => [
                                                    styles.rowActionButton,
                                                    (Platform.OS === 'web' && (hovered || pressed)) && styles.headerButtonHover,
                                                ]}
                                                accessibilityLabel={t('newSession.startNewSessionInFolder')}
                                            >
                                                <Ionicons name="add" size={UI_ICONS.rowAdd} color={theme.colors.textSecondary} />
                                            </Pressable>
                                            <View style={styles.chevron}>
                                                <Ionicons
                                                    name={row.expanded ? 'chevron-down' : 'chevron-forward'}
                                                    size={UI_ICONS.chevron}
                                                    color={theme.colors.textSecondary}
                                                />
                                            </View>
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
