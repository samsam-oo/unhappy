import * as React from 'react';
import { View, Text, Pressable, ScrollView, Platform, useWindowDimensions } from 'react-native';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { Ionicons, Octicons } from '@/icons/vector-icons';
import { Typography } from '@/constants/Typography';
import { DiffView } from '@/components/diff/DiffView';
import { RawDiffView } from '@/components/diff/RawDiffView';
import { FileIcon } from '@/components/FileIcon';
import { useSettingMutable } from '@/sync/storage';
import { calculateDiffStats } from '@/components/diff/calculateDiff';
import { t } from '@/text';
import Animated, {
    Easing,
    FadeIn,
    FadeOut,
    LinearTransition,
    runOnJS,
    useAnimatedStyle,
    useSharedValue,
    withTiming,
} from 'react-native-reanimated';

export type ChangeKind = 'modified' | 'added' | 'deleted';

export type ChangesEditorFile = {
    id: string;
    path: string;
    kind: ChangeKind;
    oldText?: string;
    newText?: string;
    rawDiff?: string;
};

interface ChangesEditorProps {
    files: ChangesEditorFile[];
    initialFileId?: string;
    allowRawToggle?: boolean;
    defaultMode?: 'rendered' | 'raw';
}

function basename(p: string) {
    const parts = p.split('/').filter(Boolean);
    return parts[parts.length - 1] || p;
}

function dirname(p: string) {
    const parts = p.split('/').filter(Boolean);
    if (parts.length <= 1) return '';
    return parts.slice(0, -1).join('/');
}

function hasConflictMarkers(text: string) {
    return /^<{7}|\n<{7}|\n={7}|\n>{7}/m.test(text);
}

function countRawDiffStats(rawDiff: string): { additions: number; deletions: number } {
    // GitHub-style stats: count only real added/removed lines (ignore file headers).
    const lines = rawDiff.split('\n');
    let additions = 0;
    let deletions = 0;
    for (const l of lines) {
        if (l.startsWith('+++') || l.startsWith('---')) continue;
        if (l.startsWith('+')) additions += 1;
        else if (l.startsWith('-')) deletions += 1;
    }
    return { additions, deletions };
}

function kindIcon(kind: ChangeKind): React.ComponentProps<typeof Octicons>['name'] {
    switch (kind) {
        case 'added':
            return 'diff-added';
        case 'deleted':
            return 'diff-removed';
        case 'modified':
        default:
            return 'diff-modified';
    }
}

function kindBadge(kind: ChangeKind) {
    switch (kind) {
        case 'added':
            return { label: 'A', intent: 'success' as const };
        case 'deleted':
            return { label: 'D', intent: 'danger' as const };
        case 'modified':
        default:
            return { label: 'M', intent: 'neutral' as const };
    }
}

export const ChangesEditor = React.memo<ChangesEditorProps>(({ files, initialFileId, allowRawToggle = true, defaultMode = 'rendered' }) => {
    const { theme } = useUnistyles();
    const { width } = useWindowDimensions();
    // Keep explicit theme references here (not hard-coded) so light/dark stay correct.

    const isWide = width >= 860;
    const isCompactHeader = width < 520;
    // VSCode-like layout: keep the sidebar visible on wide screens, even for single-file diffs.
    const showSidebar = isWide;
    const canOpenOverlaySidebar = !showSidebar && files.length > 1;
    const [overlaySidebarVisible, setOverlaySidebarVisible] = React.useState(false);
    const overlaySidebarProgress = useSharedValue(0);

    const openOverlaySidebar = React.useCallback(() => {
        if (!canOpenOverlaySidebar) return;
        setOverlaySidebarVisible(true);
        overlaySidebarProgress.value = 0;
        overlaySidebarProgress.value = withTiming(1, { duration: 180, easing: Easing.out(Easing.cubic) });
    }, [canOpenOverlaySidebar, overlaySidebarProgress]);

    const closeOverlaySidebar = React.useCallback((opts?: { immediate?: boolean }) => {
        if (opts?.immediate) {
            overlaySidebarProgress.value = 0;
            setOverlaySidebarVisible(false);
            return;
        }
        overlaySidebarProgress.value = withTiming(0, { duration: 160, easing: Easing.in(Easing.cubic) }, (finished) => {
            if (finished) runOnJS(setOverlaySidebarVisible)(false);
        });
    }, [overlaySidebarProgress]);

    const overlayScrimAnimatedStyle = useAnimatedStyle(() => ({
        opacity: overlaySidebarProgress.value,
    }));

    const overlayPanelAnimatedStyle = useAnimatedStyle(() => ({
        opacity: overlaySidebarProgress.value,
        transform: [
            { translateX: -320 + overlaySidebarProgress.value * 320 },
            { scale: 0.985 + overlaySidebarProgress.value * 0.015 },
        ],
    }));

    React.useEffect(() => {
        if (showSidebar && overlaySidebarVisible) closeOverlaySidebar({ immediate: true });
    }, [closeOverlaySidebar, overlaySidebarVisible, showSidebar]);

    React.useEffect(() => {
        if (!canOpenOverlaySidebar && overlaySidebarVisible) closeOverlaySidebar({ immediate: true });
    }, [canOpenOverlaySidebar, closeOverlaySidebar, overlaySidebarVisible]);

    const [wrapLinesInDiffs, setWrapLinesInDiffs] = useSettingMutable('wrapLinesInDiffs');
    const [showLineNumbersInToolViews, setShowLineNumbersInToolViews] = useSettingMutable('showLineNumbersInToolViews');

    const [selectedId, setSelectedId] = React.useState(() => {
        const first = files[0]?.id;
        if (!first) return '';
        if (initialFileId && files.some(f => f.id === initialFileId)) return initialFileId;
        return first;
    });

    const selected = React.useMemo(() => {
        return files.find(f => f.id === selectedId) ?? files[0] ?? null;
    }, [files, selectedId]);

    const anyRawDiff = allowRawToggle && files.some((f) => !!f.rawDiff);
    const [mode, setMode] = React.useState<'rendered' | 'raw'>(defaultMode);

    React.useEffect(() => {
        // If the file list changes, ensure the selection still points at a valid file.
        if (!files.length) return;
        if (!files.some((f) => f.id === selectedId)) {
            setSelectedId(files[0]!.id);
        }
    }, [files, selectedId]);

    // Keep mode valid for current file.
    React.useEffect(() => {
        if (mode === 'raw' && !anyRawDiff) setMode('rendered');
    }, [anyRawDiff, mode]);

    if (!selected) return null;

    const fileBase = basename(selected.path);
    const fileDir = dirname(selected.path);
    const badge = kindBadge(selected.kind);

    const canShowRaw = anyRawDiff;
    const conflictDetected = hasConflictMarkers(selected.newText ?? '');

    const selectedStats = React.useMemo(() => {
        if (selected.rawDiff) return countRawDiffStats(selected.rawDiff);
        const oldText = selected.oldText ?? '';
        const newText = selected.newText ?? '';
        return calculateDiffStats(oldText, newText);
    }, [selected.newText, selected.oldText, selected.rawDiff]);

    const statsById = React.useMemo(() => {
        const map = new Map<string, { additions: number; deletions: number }>();
        for (const f of files) {
            if (f.rawDiff) map.set(f.id, countRawDiffStats(f.rawDiff));
            else map.set(f.id, calculateDiffStats(f.oldText ?? '', f.newText ?? ''));
        }
        return map;
    }, [files]);

    const scrollRef = React.useRef<ScrollView>(null);
    const selectFile = React.useCallback((fileId: string) => {
        setSelectedId(fileId);
        // Explorer-style: always start at the top of the selected file.
        scrollRef.current?.scrollTo({ y: 0, animated: false });
    }, []);

    const renderFileDiff = (file: ChangesEditorFile) => {
        const showLineNumbers = showLineNumbersInToolViews;
        // GitHub-style: rely on background colors + line numbers, no extra "+/-" column.
        const showPlusMinus = false;

        const node =
            mode === 'raw' && file.rawDiff ? (
                <RawDiffView
                    diff={file.rawDiff}
                    wrapLines={wrapLinesInDiffs}
                    showLineNumbers={showLineNumbers}
                    showFileHeaders={false}
                />
            ) : (
                <DiffView
                    oldText={file.oldText ?? ''}
                    newText={file.newText ?? ''}
                    wrapLines={wrapLinesInDiffs}
                    showLineNumbers={showLineNumbers}
                    showPlusMinusSymbols={showPlusMinus}
                    contextLines={3}
                />
            );

        if (wrapLinesInDiffs) {
            return node;
        }

        return (
            <ScrollView
                horizontal
                nestedScrollEnabled
                showsHorizontalScrollIndicator
                contentContainerStyle={{ flexGrow: 1 }}
            >
                {node}
            </ScrollView>
        );
    };

    function ToolbarToggle(props: { label: string; active: boolean; onPress: () => void }) {
        return (
            <Pressable
                onPress={props.onPress}
                style={({ pressed }) => [
                    styles.toggle,
                    props.active && styles.toggleActive,
                    pressed && styles.togglePressed,
                ]}
                accessibilityRole="button"
                accessibilityState={{ selected: props.active }}
            >
                <Text style={[styles.toggleText, props.active && styles.toggleTextActive]}>{props.label}</Text>
            </Pressable>
        );
    }

    function FileRow(props: { file: ChangesEditorFile; active: boolean; onPress: () => void }) {
        const base = basename(props.file.path);
        const dir = dirname(props.file.path);
        const b = kindBadge(props.file.kind);
        const s = statsById.get(props.file.id);
        const badgeColor =
            b.intent === 'success'
                ? theme.colors.success
                : b.intent === 'danger'
                    ? theme.colors.textDestructive
                    : theme.colors.textSecondary;

        return (
            <Pressable
                onPress={props.onPress}
                style={({ pressed }) => [
                    styles.fileRow,
                    props.active && styles.fileRowActive,
                    pressed && styles.fileRowPressed,
                ]}
                accessibilityRole="button"
                accessibilityState={{ selected: props.active }}
            >
                <View style={styles.fileRowLeft}>
                    <FileIcon fileName={base} size={18} />
                    <View style={{ flex: 1, minWidth: 0 }}>
                        <Text style={styles.fileName} numberOfLines={1}>{base}</Text>
                        {dir ? (
                            <Text style={styles.fileDir} numberOfLines={1}>{dir}</Text>
                        ) : null}
                    </View>
                </View>
                {s && (s.additions > 0 || s.deletions > 0) ? (
                    <View style={styles.fileRowStats}>
                        {s.additions > 0 ? (
                            <Text style={[styles.fileRowStatText, { color: theme.colors.success }]}>+{s.additions}</Text>
                        ) : null}
                        {s.deletions > 0 ? (
                            <Text style={[styles.fileRowStatText, { color: theme.colors.textDestructive }]}>-{s.deletions}</Text>
                        ) : null}
                    </View>
                ) : null}
                <View style={[styles.kindBadge, { borderColor: theme.colors.divider }]}>
                    <Text style={[styles.kindBadgeText, { color: badgeColor }]}>{b.label}</Text>
                </View>
            </Pressable>
        );
    }

    const header = (
        <View style={styles.header}>
            <View style={styles.headerLeft}>
                {canOpenOverlaySidebar ? (
                    <Pressable
                        onPress={openOverlaySidebar}
                        style={({ pressed }) => [styles.iconButton, pressed && styles.iconButtonPressed]}
                        accessibilityRole="button"
                        accessibilityLabel={`${t('common.files')} ${t('common.open')}`}
                    >
                        <Ionicons name="list-outline" size={18} color={theme.colors.textSecondary} />
                    </Pressable>
                ) : null}
                <Octicons name={kindIcon(selected.kind)} size={16} color={theme.colors.textSecondary} />
                <Text style={styles.headerPath} numberOfLines={1}>
                    {selected.path}
                </Text>
                {(() => {
                    const s = selectedStats;
                    if (s.additions === 0 && s.deletions === 0) return null;
                    return (
                    <View style={styles.diffStats}>
                        {s.additions > 0 ? (
                            <Text style={[styles.diffStatText, { color: theme.colors.success }]}>
                                +{s.additions}
                            </Text>
                        ) : null}
                        {s.deletions > 0 ? (
                            <Text style={[styles.diffStatText, { color: theme.colors.textDestructive }]}>
                                -{s.deletions}
                            </Text>
                        ) : null}
                    </View>
                    );
                })()}
            </View>
            <View style={styles.headerRight}>
                {canShowRaw ? (
                    isCompactHeader ? (
                        <ToolbarToggle
                            label="원본"
                            active={mode === 'raw'}
                            onPress={() => setMode(mode === 'raw' ? 'rendered' : 'raw')}
                        />
                    ) : (
                        <>
                            <ToolbarToggle label="렌더링" active={mode === 'rendered'} onPress={() => setMode('rendered')} />
                            <ToolbarToggle label="원본" active={mode === 'raw'} onPress={() => setMode('raw')} />
                            <View style={styles.headerDivider} />
                        </>
                    )
                ) : null}
                <ToolbarToggle
                    label={isCompactHeader ? '줄바꿈' : (wrapLinesInDiffs ? '줄바꿈: 켬' : '줄바꿈: 끔')}
                    active={wrapLinesInDiffs}
                    onPress={() => setWrapLinesInDiffs(!wrapLinesInDiffs)}
                />
                <ToolbarToggle
                    label={isCompactHeader ? '줄 번호' : (showLineNumbersInToolViews ? '줄 번호: 표시' : '줄 번호: 숨김')}
                    active={showLineNumbersInToolViews}
                    onPress={() => setShowLineNumbersInToolViews(!showLineNumbersInToolViews)}
                />
            </View>
        </View>
    );

    const statusBar = (
        <View style={styles.statusBar}>
            <View style={styles.statusLeft}>
                <Text style={styles.statusText}>
                    {fileBase}
                </Text>
                {fileDir ? <Text style={styles.statusMuted}> • {fileDir}</Text> : null}
            </View>
            <View style={styles.statusRight}>
                <Text style={styles.statusMuted}>
                    {(() => {
                        if (files.length <= 1) return badge.label;
                        const idx = files.findIndex((f) => f.id === selected.id);
                        const pos = idx >= 0 ? `${idx + 1}/${files.length}` : `${files.length}`;
                        return `${badge.label} • ${pos}`;
                    })()}
                </Text>
            </View>
        </View>
    );

    return (
        <View style={styles.frame}>
            {showSidebar ? (
                <View style={styles.split}>
                    <View style={styles.sidebar}>
                    <View style={styles.sidebarHeader}>
                        <Text style={styles.sidebarHeaderTitle}>{t('files.diff')}</Text>
                        <Text style={styles.sidebarHeaderCount}>{files.length}</Text>
                    </View>
                        <ScrollView style={{ flex: 1 }} showsVerticalScrollIndicator>
                            {files.map((f) => (
                                <FileRow
                                    key={f.id}
                                    file={f}
                                    active={f.id === selected.id}
                                    onPress={() => selectFile(f.id)}
                                />
                            ))}
                        </ScrollView>
                    </View>

                    <View style={styles.editor}>
                        {header}
                        <ScrollView
                            ref={scrollRef}
                            style={styles.editorScroll}
                            nestedScrollEnabled
                            showsVerticalScrollIndicator
                            contentContainerStyle={styles.editorScrollContent}
                        >
                            <Animated.View
                                key={`file-${selected.id}-${mode}`}
                                entering={FadeIn.duration(140)}
                                exiting={FadeOut.duration(120)}
                                layout={LinearTransition.duration(140)}
                            >
                                {conflictDetected ? (
                            <View style={styles.callout}>
                                <Ionicons name="warning-outline" size={14} color={theme.colors.warningCritical} />
                                <Text style={styles.calloutText} numberOfLines={2}>
                                    이 변경사항에서 충돌 표시자가 감지되었습니다. 충돌 해결 UI는 추후 추가됩니다.
                                </Text>
                            </View>
                        ) : null}
                                <View style={styles.singleDiffCard}>
                                    {renderFileDiff(selected)}
                                </View>
                            </Animated.View>
                        </ScrollView>
                        {statusBar}
                    </View>
                </View>
            ) : (
                <View style={styles.single}>
                    {header}
                    <ScrollView
                        ref={scrollRef}
                        style={styles.editorScroll}
                        nestedScrollEnabled
                        showsVerticalScrollIndicator
                        contentContainerStyle={styles.editorScrollContent}
                    >
                        <Animated.View
                            key={`file-${selected.id}-${mode}`}
                            entering={FadeIn.duration(140)}
                            exiting={FadeOut.duration(120)}
                            layout={LinearTransition.duration(140)}
                        >
                            {conflictDetected ? (
                            <View style={styles.callout}>
                                <Ionicons name="warning-outline" size={14} color={theme.colors.warningCritical} />
                                <Text style={styles.calloutText} numberOfLines={2}>
                                    이 변경사항에서 충돌 표시자가 감지되었습니다. 충돌 해결 UI는 추후 추가됩니다.
                                </Text>
                            </View>
                        ) : null}
                            <View style={styles.singleDiffCard}>
                                {renderFileDiff(selected)}
                            </View>
                        </Animated.View>
                    </ScrollView>
                    {statusBar}
                </View>
            )}

            {canOpenOverlaySidebar && overlaySidebarVisible ? (
                <View style={styles.overlay} pointerEvents="box-none">
                    <Animated.View style={[styles.overlayScrim, overlayScrimAnimatedStyle]}>
                        <Pressable
                            style={styles.overlayScrimPressable}
                            onPress={() => closeOverlaySidebar()}
                            accessibilityRole="button"
                            accessibilityLabel={t('common.close')}
                        />
                    </Animated.View>
                    <Animated.View style={[styles.overlayPanel, overlayPanelAnimatedStyle]}>
                        <View style={styles.overlayHeader}>
                            <Text style={styles.overlayTitle} numberOfLines={1}>
                                {t('files.diff')}
                            </Text>
                            <Text style={styles.overlayCount}>{files.length}</Text>
                            <Pressable
                                onPress={() => closeOverlaySidebar()}
                                style={({ pressed }) => [styles.iconButton, pressed && styles.iconButtonPressed]}
                                accessibilityRole="button"
                                accessibilityLabel={t('common.close')}
                            >
                                <Ionicons name="close-outline" size={18} color={theme.colors.textSecondary} />
                            </Pressable>
                        </View>
                        <ScrollView style={{ flex: 1 }} showsVerticalScrollIndicator>
                            {files.map((f) => (
                                <FileRow
                                    key={`overlay-${f.id}`}
                                    file={f}
                                    active={f.id === selected.id}
                                    onPress={() => {
                                        selectFile(f.id);
                                        closeOverlaySidebar();
                                    }}
                                />
                            ))}
                        </ScrollView>
                    </Animated.View>
                </View>
            ) : null}
        </View>
    );
});

const styles = StyleSheet.create((theme) => ({
    frame: {
        flex: 1,
        minHeight: 360,
        borderRadius: 12,
        borderWidth: 1,
        borderColor: theme.colors.divider,
        backgroundColor: theme.colors.surface,
        overflow: 'hidden',
        ...(Platform.OS === 'web'
            ? ({ boxShadow: theme.dark ? '0 18px 48px rgba(0,0,0,0.45)' : '0 18px 48px rgba(0,0,0,0.12)' } as any)
            : null),
    },
    split: {
        flex: 1,
        flexDirection: 'row',
    },
    single: {
        flex: 1,
    },
    sidebar: {
        width: 270,
        backgroundColor: theme.colors.surfaceHigh,
        borderRightWidth: 1,
        borderRightColor: theme.colors.divider,
    },
    sidebarHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: 12,
        paddingVertical: 10,
        borderBottomWidth: 1,
        borderBottomColor: theme.colors.divider,
    },
    sidebarHeaderTitle: {
        fontSize: 12,
        letterSpacing: 1.2,
        textTransform: 'uppercase',
        color: theme.colors.textSecondary,
        ...Typography.default('semiBold'),
    },
    sidebarHeaderCount: {
        marginLeft: 'auto',
        fontSize: 12,
        color: theme.colors.textSecondary,
        ...Typography.mono(),
    },
    fileRow: {
        paddingHorizontal: 10,
        paddingVertical: 10,
        flexDirection: 'row',
        alignItems: 'center',
        gap: 10,
    },
    fileRowLeft: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 10,
        flex: 1,
        minWidth: 0,
    },
    fileRowActive: {
        backgroundColor: theme.colors.surfaceSelected,
    },
    fileRowPressed: {
        backgroundColor: theme.colors.surfacePressed,
    },
    fileName: {
        fontSize: 13,
        color: theme.colors.text,
        ...Typography.default('semiBold'),
    },
    fileDir: {
        fontSize: 11,
        color: theme.colors.textSecondary,
        marginTop: 2,
        ...Typography.default(),
    },
    kindBadge: {
        borderWidth: 1,
        borderRadius: 999,
        paddingHorizontal: 8,
        paddingVertical: 4,
        backgroundColor: theme.colors.surface,
    },
    kindBadgeText: {
        fontSize: 11,
        ...Typography.mono('semiBold'),
    },
    fileRowStats: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
        marginRight: 8,
    },
    fileRowStatText: {
        fontSize: 11,
        ...Typography.mono('semiBold'),
        opacity: 0.95,
    },
    editor: {
        flex: 1,
        minWidth: 0,
    },
    header: {
        height: 40,
        flexDirection: 'row',
        alignItems: 'center',
        backgroundColor: theme.colors.surfaceHigh,
        borderBottomWidth: 1,
        borderBottomColor: theme.colors.divider,
        paddingHorizontal: 12,
        gap: 10,
    },
    headerLeft: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
        flex: 1,
        minWidth: 0,
    },
    headerRight: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 6,
        flexShrink: 0,
    },
    headerPath: {
        fontSize: 12,
        color: theme.colors.text,
        ...Typography.mono(),
    },
    iconButton: {
        width: 32,
        height: 32,
        borderRadius: 10,
        alignItems: 'center',
        justifyContent: 'center',
        borderWidth: 1,
        borderColor: theme.colors.divider,
        backgroundColor: theme.colors.surface,
    },
    iconButtonPressed: {
        backgroundColor: theme.colors.surfacePressed,
    },
    diffStats: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
        marginLeft: 8,
        paddingLeft: 8,
        borderLeftWidth: 1,
        borderLeftColor: theme.colors.chrome.panelBorder,
    },
    diffStatText: {
        fontSize: 12,
        ...Typography.mono('semiBold'),
    },
    headerDivider: {
        width: 1,
        height: 16,
        backgroundColor: theme.colors.divider,
        marginHorizontal: 4,
    },
    toggle: {
        borderWidth: 1,
        borderColor: theme.colors.divider,
        borderRadius: 8,
        paddingHorizontal: 10,
        paddingVertical: 6,
        backgroundColor: theme.colors.surface,
    },
    toggleActive: {
        borderColor: theme.colors.chrome.accent,
        backgroundColor: theme.colors.surfaceSelected,
    },
    togglePressed: {
        opacity: 0.8,
    },
    toggleText: {
        fontSize: 12,
        color: theme.colors.textSecondary,
        ...Typography.default('semiBold'),
    },
    toggleTextActive: {
        color: theme.colors.text,
    },
    callout: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
        paddingHorizontal: 12,
        paddingVertical: 10,
        backgroundColor: theme.colors.surfaceHigh,
        borderBottomWidth: 1,
        borderBottomColor: theme.colors.divider,
    },
    calloutText: {
        flex: 1,
        fontSize: 12,
        color: theme.colors.textSecondary,
        ...Typography.default(),
    },
    tabsStrip: {
        backgroundColor: theme.colors.surfaceHigh,
        borderBottomWidth: 1,
        borderBottomColor: theme.colors.divider,
    },
    tabsStripContent: {
        paddingHorizontal: 8,
        paddingVertical: 8,
        gap: 8,
        alignItems: 'center',
    },
    tab: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
        paddingHorizontal: 10,
        paddingVertical: 8,
        borderRadius: 10,
        borderWidth: 1,
        borderColor: theme.colors.divider,
        backgroundColor: theme.colors.surface,
        maxWidth: 220,
    },
    tabActive: {
        borderColor: theme.colors.chrome.accent,
        backgroundColor: `${theme.colors.chrome.accent}22`,
    },
    tabPressed: {
        opacity: 0.85,
    },
    tabText: {
        fontSize: 12,
        color: theme.colors.textSecondary,
        ...Typography.default('semiBold'),
        flexShrink: 1,
        minWidth: 0,
    },
    tabTextActive: {
        color: theme.colors.text,
    },
    tabDot: {
        width: 6,
        height: 6,
        borderRadius: 999,
        backgroundColor: theme.colors.chrome.panelBorder,
        marginLeft: 'auto',
    },
    editorScroll: {
        flex: 1,
        backgroundColor: theme.colors.chrome.editorBackground,
    },
    editorScrollContent: {
        paddingBottom: 12,
    },
    allWrap: {
        paddingVertical: 12,
        paddingHorizontal: 12,
        gap: 12,
    },
    singleDiffCard: {
        borderWidth: 1,
        borderColor: theme.colors.divider,
        borderRadius: 10,
        overflow: 'hidden',
        backgroundColor: theme.colors.chrome.editorBackground,
    },
    fileSection: {
        borderWidth: 1,
        borderColor: theme.colors.divider,
        borderRadius: 10,
        overflow: 'hidden',
        backgroundColor: theme.colors.surface,
    },
    fileSectionHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 10,
        paddingHorizontal: 12,
        paddingVertical: 10,
        backgroundColor: theme.colors.surfaceHigh,
        borderBottomWidth: 1,
        borderBottomColor: theme.colors.divider,
    },
    fileSectionHeaderPressed: {
        backgroundColor: theme.colors.surfacePressed,
    },
    fileSectionTitle: {
        fontSize: 13,
        color: theme.colors.text,
        ...Typography.default('semiBold'),
    },
    fileSectionSubtitle: {
        fontSize: 11,
        color: theme.colors.textSecondary,
        marginTop: 2,
        ...Typography.default(),
    },
    fileSectionStats: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
        marginRight: 4,
    },
    fileSectionBody: {
        backgroundColor: theme.colors.chrome.editorBackground,
    },
    statusBar: {
        height: 28,
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: 12,
        backgroundColor: theme.colors.surfaceHigh,
        borderTopWidth: 1,
        borderTopColor: theme.colors.divider,
    },
    statusLeft: {
        flexDirection: 'row',
        alignItems: 'center',
        flex: 1,
        minWidth: 0,
    },
    statusRight: {
        flexDirection: 'row',
        alignItems: 'center',
        flexShrink: 0,
    },
    statusText: {
        fontSize: 11,
        color: theme.colors.textSecondary,
        letterSpacing: 0.4,
        ...Typography.default('semiBold'),
    },
    statusMuted: {
        fontSize: 11,
        color: theme.colors.textSecondary,
        ...Typography.default(),
    },
    overlay: {
        ...StyleSheet.absoluteFillObject,
        zIndex: 50,
        elevation: 50,
        flexDirection: 'row',
    },
    overlayScrim: {
        ...StyleSheet.absoluteFillObject,
        backgroundColor: 'rgba(0, 0, 0, 0.35)',
    },
    overlayScrimPressable: {
        ...StyleSheet.absoluteFillObject,
    },
    overlayPanel: {
        width: 300,
        maxWidth: '86%',
        height: '100%',
        backgroundColor: theme.colors.surfaceHigh,
        borderRightWidth: 1,
        borderRightColor: theme.colors.divider,
    },
    overlayHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 10,
        paddingHorizontal: 12,
        paddingVertical: 10,
        borderBottomWidth: 1,
        borderBottomColor: theme.colors.divider,
    },
    overlayTitle: {
        fontSize: 12,
        letterSpacing: 1.2,
        textTransform: 'uppercase',
        color: theme.colors.textSecondary,
        ...Typography.default('semiBold'),
        flex: 1,
        minWidth: 0,
    },
    overlayCount: {
        fontSize: 12,
        color: theme.colors.textSecondary,
        ...Typography.mono(),
    },
}));
