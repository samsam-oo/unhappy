import * as React from 'react';
import { ActivityIndicator, FlatList, Platform, Pressable, View } from 'react-native';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { usePathname, useRouter } from 'expo-router';
import { Text } from '@/components/StyledText';
import { Ionicons, Octicons } from '@/icons/vector-icons';
import { Typography } from '@/constants/Typography';
import { useAllSessions, useProjects } from '@/sync/storage';
import type { Project } from '@/sync/projectManager';
import type { Session } from '@/sync/storageTypes';
import { useNavigateToSession } from '@/hooks/useNavigateToSession';
import { t } from '@/text';
import { useSessionStatus } from '@/utils/sessionUtils';

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
    const parts = path.split('/').filter(Boolean);
    return parts[parts.length - 1] || path || 'Workspace';
}

function getSelectedSessionIdFromPathname(pathname: string): string | null {
    const match = pathname.match(/^\/session\/([^\/\?]+)(?:\/|$)/);
    return match?.[1] ?? null;
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
        paddingLeft: 22,
    },
}));

type Row =
    | { type: 'project'; project: Project; expanded: boolean }
    | { type: 'session'; session: Session }
    | { type: 'section'; id: 'playground'; title: string }
    | { type: 'action'; id: 'new-playground'; title: string };

const WorkspaceExplorerSessionRow = React.memo(function WorkspaceExplorerSessionRow(props: {
    session: Session;
    selected: boolean;
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
                styles.childIndent,
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
            if (stored && typeof stored === 'object') return stored;
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
        setExpanded((prev) => (prev[stableId] === false ? { ...prev, [stableId]: true } : prev));
    }, [selectedSessionId, sessionById]);

    React.useEffect(() => {
        if (Platform.OS !== 'web' || typeof window === 'undefined') return;
        try {
            window.localStorage.setItem(LOCAL_STORAGE_KEY, JSON.stringify(expanded));
        } catch {
            // ignore
        }
    }, [expanded]);

    const toggleProject = React.useCallback((projectStableId: string) => {
        setExpanded((prev) => ({ ...prev, [projectStableId]: !(prev[projectStableId] ?? true) }));
    }, []);

    const rows: Row[] = React.useMemo(() => {
        const out: Row[] = [];
        const included = new Set<string>();

        for (const project of projects) {
            const stableId = getProjectStableId(project);
            const isExpanded = expanded[stableId] ?? true;
            out.push({ type: 'project', project, expanded: isExpanded });

            if (isExpanded) {
                const projectSessionIds = project.sessionIds || [];
                const projectSessions: Session[] = projectSessionIds
                    .map((id) => sessionById.get(id))
                    .filter(Boolean) as Session[];
                projectSessions.sort((a, b) => b.updatedAt - a.updatedAt);

                for (const s of projectSessions) {
                    included.add(s.id);
                    out.push({ type: 'session', session: s });
                }
            } else {
                // still track included ids to avoid duplication in ungrouped
                for (const id of project.sessionIds || []) included.add(id);
            }
        }

        // Fallback: sessions without metadata/project association.
        const ungrouped = sessions
            .filter((s) => !included.has(s.id))
            .sort((a, b) => b.updatedAt - a.updatedAt);
        for (const s of ungrouped) {
            out.push({ type: 'session', session: s });
        }

        out.push({ type: 'section', id: 'playground', title: 'Playground' });
        out.push({ type: 'action', id: 'new-playground', title: 'New Playground' });
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
                keyExtractor={(row, idx) => {
                    switch (row.type) {
                        case 'project':
                            return `p:${getProjectStableId(row.project)}`;
                        case 'session':
                            return `s:${row.session.id}`;
                        case 'section':
                            return `sec:${row.id}`;
                        case 'action':
                            return `a:${row.id}`;
                    }
                }}
                contentContainerStyle={[styles.list, { paddingBottom: insets.bottom + 16 }]}
                renderItem={({ item: row }) => {
                    if (row.type === 'section') {
                        return (
                            <View
                                style={[
                                    styles.sectionHeader,
                                    {
                                        borderTopWidth: StyleSheet.hairlineWidth,
                                        borderTopColor: theme.colors.chrome.panelBorder,
                                        marginTop: 8,
                                        // Keep the break between groups, but avoid an extra "loose" feeling.
                                        marginBottom: 4,
                                    },
                                ]}
                            >
                                <Text style={styles.sectionTitle}>{row.title}</Text>
                                <View style={styles.headerButtons}>
                                    <Pressable
                                        onPress={() => router.push('/new')}
                                        hitSlop={10}
                                        style={({ hovered, pressed }: any) => [
                                            styles.headerButton,
                                            (Platform.OS === 'web' && (hovered || pressed)) && styles.headerButtonHover,
                                        ]}
                                        accessibilityLabel="New playground"
                                    >
                                        <Ionicons name="add" size={18} color={theme.colors.header.tint} />
                                    </Pressable>
                                </View>
                            </View>
                        );
                    }

                    if (row.type === 'action') {
                        return (
                            <Pressable
                                onPress={() => router.push('/new')}
                                style={({ hovered, pressed }: any) => [
                                    styles.row,
                                    (Platform.OS === 'web' && (hovered || pressed)) && styles.rowHover,
                                ]}
                            >
                                <View style={styles.chevron} />
                                <View style={styles.icon}>
                                    <Ionicons name="add-circle-outline" size={18} color={theme.colors.textSecondary} />
                                </View>
                                <View style={styles.textBlock}>
                                    <Text style={styles.title} numberOfLines={1}>
                                        {row.title}
                                    </Text>
                                </View>
                            </Pressable>
                        );
                    }

                    if (row.type === 'project') {
                        const stableId = getProjectStableId(row.project);
                        const title = getBasename(row.project.key.path);
                        const branch = row.project.gitStatus?.branch;
                        const machineName =
                            row.project.machineMetadata?.displayName ||
                            row.project.machineMetadata?.host ||
                            row.project.key.machineId;

                        return (
                            <Pressable
                                onPress={() => toggleProject(stableId)}
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
                                        <Octicons name="git-branch" size={12} color={theme.colors.textSecondary} />
                                        <Text style={styles.subtitle} numberOfLines={1}>
                                            {branch || 'detached'}
                                        </Text>
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
                    return <WorkspaceExplorerSessionRow session={row.session} selected={isSelected} />;
                }}
            />
        </View>
    );
}
