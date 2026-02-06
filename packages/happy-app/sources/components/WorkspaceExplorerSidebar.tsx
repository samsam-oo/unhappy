import { Text } from '@/components/StyledText';
import { Typography } from '@/constants/Typography';
import { useNavigateToSession } from '@/hooks/useNavigateToSession';
import { Ionicons, Octicons } from '@/icons/vector-icons';
import type { Project } from '@/sync/projectManager';
import { useAllSessions, useProjects } from '@/sync/storage';
import type { Session } from '@/sync/storageTypes';
import { t } from '@/text';
import { useSessionStatus } from '@/utils/sessionUtils';
import { usePathname, useRouter } from 'expo-router';
import * as React from 'react';
import { ActivityIndicator, FlatList, Platform, Pressable, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';

const LOCAL_STORAGE_KEY = 'happy.workspaceExplorer.expanded.v1';

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
        paddingVertical: 8,
        minHeight: 36,
        borderBottomWidth: StyleSheet.hairlineWidth,
        borderBottomColor: theme.colors.chrome.panelBorder,
    },
    sectionTitle: {
        fontSize: 11,
        lineHeight: 14,
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
        width: 28,
        height: 28,
        alignItems: 'center',
        justifyContent: 'center',
        borderRadius: 6,
    },
    headerButtonHover: {
        backgroundColor: theme.colors.chrome.listHoverBackground,
    },

    list: {
        // Avoid a "double padding" feel: the header already provides vertical rhythm.
        paddingTop: 4,
        paddingBottom: 6,
    },

    row: {
        // Slightly tighter rows for a more compact sidebar density.
        minHeight: 28,
        paddingHorizontal: 8,
        paddingVertical: 5,
        marginHorizontal: 6,
        borderRadius: 6,
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
    },
    rowHover: {
        backgroundColor: theme.colors.chrome.listHoverBackground,
    },
    rowActive: {
        backgroundColor: theme.colors.chrome.listActiveBackground,
    },
    selectionBar: {
        position: 'absolute',
        left: 0,
        top: 5,
        bottom: 5,
        width: 2,
        backgroundColor: theme.colors.chrome.accent,
        borderTopLeftRadius: 2,
        borderBottomLeftRadius: 2,
    },

    chevron: {
        width: 16,
        alignItems: 'center',
        justifyContent: 'center',
    },
    projectActions: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 2,
    },
    rowActionButton: {
        width: 24,
        height: 24,
        alignItems: 'center',
        justifyContent: 'center',
        borderRadius: 6,
    },
    icon: {
        width: 18,
        alignItems: 'center',
        justifyContent: 'center',
    },
    textBlock: {
        flex: 1,
        minWidth: 0,
        flexDirection: 'column',
    },
    title: {
        fontSize: 13,
        color: theme.colors.text,
        ...Typography.default('semiBold'),
    },
    subtitleRow: {
        flexDirection: 'row',
        alignItems: 'center',
        marginTop: 1,
        gap: 6,
    },
    subtitle: {
        fontSize: 11,
        color: theme.colors.textSecondary,
        ...Typography.default(),
    },

    childIndent: {
        paddingLeft: 6,
    },
    grandChildIndent: {
        paddingLeft: 32,
    },
}));

type Row =
    | { type: 'project'; project: Project; expanded: boolean; isVirtual?: boolean }
    | { type: 'worktree'; project: Project; expanded: boolean; parentStableId: string }
    | { type: 'session'; session: Session; depth: 1 | 2 };

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

    const { iconName, iconColor } = React.useMemo(() => {
        switch (sessionStatus.state) {
            case 'thinking':
                return { iconName: 'sparkles-outline', iconColor: sessionStatus.statusDotColor };
            case 'permission_required':
                return { iconName: 'alert-circle-outline', iconColor: sessionStatus.statusDotColor };
            case 'waiting':
                // "Waiting for your message" feels closer to chat than terminal.
                return { iconName: 'chatbubble-outline', iconColor: sessionStatus.statusDotColor };
            case 'disconnected':
                return { iconName: 'cloud-outline', iconColor: sessionStatus.statusDotColor };
            default:
                return { iconName: 'terminal-outline', iconColor: theme.colors.textSecondary };
        }
    }, [sessionStatus.state, sessionStatus.statusDotColor, theme.colors.textSecondary]);

    return (
        <Pressable
            onPress={() => navigateToSession(props.session.id)}
            style={({ hovered, pressed }: any) => [
                styles.row,
                props.depth === 2 ? styles.grandChildIndent : styles.childIndent,
                props.selected && styles.rowActive,
                (Platform.OS === 'web' && (hovered || pressed) && !props.selected) && styles.rowHover,
            ]}
        >
            {props.selected && <View style={styles.selectionBar} />}
            <View style={styles.chevron} />
            <View style={styles.icon}>
                {sessionStatus.state === 'thinking'
                    ? <ActivityIndicator size={14} color={sessionStatus.statusDotColor} />
                    : <Ionicons name={iconName} size={18} color={iconColor} />
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
    const navigateToSession = useNavigateToSession();

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
        setExpanded((prev) => ({ ...prev, [expandedKey]: !(prev[expandedKey] ?? true) }));
    }, []);

    const rows: Row[] = React.useMemo(() => {
        const out: Row[] = [];
        const included = new Set<string>();

        const realProjectByStableId = new Map<string, Project>();
        for (const p of projects) realProjectByStableId.set(getProjectStableId(p), p);

        type ProjectGroup = {
            stableId: string;
            project: Project;
            isVirtual: boolean;
            worktrees: Project[];
            updatedAt: number;
        };

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

        const sortedGroups = Array.from(groups.values()).sort((a, b) => b.updatedAt - a.updatedAt);

        for (const group of sortedGroups) {
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
    }, [projects, expanded, sessionById, sessions]);

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
                        <Ionicons name="add" size={18} color={theme.colors.header.tint} />
                    </Pressable>
                </View>
            </View>

            <FlatList
                data={rows}
                keyExtractor={(row) => {
                    if (row.type === 'project') return `p:${getProjectStableId(row.project)}`;
                    if (row.type === 'worktree') return `w:${getProjectStableId(row.project)}`;
                    return `s:${row.session.id}`;
                }}
                contentContainerStyle={[styles.list, { paddingBottom: insets.bottom + 16 }]}
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

                        return (
                            <Pressable
                                onPress={() => toggleExpanded(expandedKey)}
                                style={({ hovered, pressed }: any) => [
                                    styles.row,
                                    (Platform.OS === 'web' && (hovered || pressed)) && styles.rowHover,
                                ]}
                            >
                                <View style={styles.icon}>
                                    <Octicons name="file-directory" size={16} color={theme.colors.textSecondary} />
                                </View>
                                <View style={styles.textBlock}>
                                    <Text style={styles.title} numberOfLines={1}>
                                        {title}
                                    </Text>
                                    <View style={styles.subtitleRow}>
                                        {hasGitStatus && (
                                            <>
                                                <Octicons name="git-branch" size={12} color={theme.colors.textSecondary} />
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
                                        <Ionicons name="add" size={18} color={theme.colors.textSecondary} />
                                    </Pressable>
                                    <View style={styles.chevron}>
                                        <Ionicons
                                            name={row.expanded ? 'chevron-down' : 'chevron-forward'}
                                            size={16}
                                            color={theme.colors.textSecondary}
                                        />
                                    </View>
                                </View>
                            </Pressable>
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
                            <Pressable
                                onPress={() => toggleExpanded(expandedKey)}
                                style={({ hovered, pressed }: any) => [
                                    styles.row,
                                    styles.childIndent,
                                    (Platform.OS === 'web' && (hovered || pressed)) && styles.rowHover,
                                ]}
                            >
                                {/* Keep alignment consistent with session rows (which reserve a chevron slot). */}
                                <View style={styles.chevron} />
                                <View style={styles.icon}>
                                    <Octicons name="file-directory" size={16} color={theme.colors.textSecondary} />
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
                                                <Octicons name="git-branch" size={12} color={theme.colors.textSecondary} />
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
                                        <Ionicons name="add" size={18} color={theme.colors.textSecondary} />
                                    </Pressable>
                                    <View style={styles.chevron}>
                                        <Ionicons
                                            name={row.expanded ? 'chevron-down' : 'chevron-forward'}
                                            size={16}
                                            color={theme.colors.textSecondary}
                                        />
                                    </View>
                                </View>
                            </Pressable>
                        );
                    }

                    const isSelected = selectedSessionId === row.session.id;
                    return (
                        <WorkspaceExplorerSessionRow
                            session={row.session}
                            selected={isSelected}
                            depth={row.depth}
                        />
                    );
                }}
            />
        </View>
    );
}
