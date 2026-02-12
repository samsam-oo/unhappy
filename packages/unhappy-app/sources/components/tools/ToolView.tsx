import { knownTools } from '@/components/tools/knownTools';
import { PermissionFooter } from '@/components/tools/PermissionFooter';
import { Typography } from '@/constants/Typography';
import { useElapsedTime } from '@/hooks/useElapsedTime';
import { Ionicons, Octicons } from '@/icons/vector-icons';
import { Metadata } from '@/sync/storageTypes';
import { Message, ToolCall } from '@/sync/typesMessage';
import { t } from '@/text';
import { parseToolUseError } from '@/utils/toolErrorParser';
import { useRouter } from 'expo-router';
import * as React from 'react';
import { ActivityIndicator, LayoutAnimation, Platform, Text, TouchableOpacity, UIManager, View } from 'react-native';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { CodeView } from '../CodeView';
import { CommandView } from '../CommandView';
import {
    dedupeShellOutputAgainstError,
    parseShellOutput,
    resolveShellErrorMessage,
    toToolPreviewText,
} from './shellOutput';
import { ToolError } from './ToolError';
import { ToolSectionView } from './ToolSectionView';
import { getToolFullViewComponent, getToolViewComponent } from './views/_all';
import { formatMCPTitle } from './views/MCPToolView';

// Enable LayoutAnimation on Android once for this module.
if (Platform.OS === 'android' && UIManager.setLayoutAnimationEnabledExperimental) {
    UIManager.setLayoutAnimationEnabledExperimental(true);
}

interface ToolViewProps {
    metadata: Metadata | null;
    tool: ToolCall;
    messages?: Message[];
    onPress?: () => void;
    sessionId?: string;
    messageId?: string;
    variant?: 'default' | 'chat';
}

const REASONING_TOOL_NAMES = new Set(['CodexReasoning', 'GeminiReasoning', 'think']);
const MAX_REASONING_PREVIEW_CHARS = 4000;
const CHANGE_SUMMARY_TOOL_NAMES = new Set(['CodexPatch', 'GeminiPatch', 'CodexDiff', 'GeminiDiff']);
const MAX_CHANGE_PREVIEW_FILES = 8;

function toBasename(path: string): string {
    const normalized = path.replace(/\\/g, '/');
    const parts = normalized.split('/').filter(Boolean);
    return parts[parts.length - 1] || normalized || path;
}

function formatChangeSummary(lines: string[]): string | null {
    if (lines.length === 0) return null;
    return lines.join('\n');
}

function extractPatchChangePreview(input: unknown): string | null {
    if (!input || typeof input !== 'object') return null;
    const rawChanges = (input as Record<string, unknown>).changes;
    if (!rawChanges || typeof rawChanges !== 'object') return null;

    const entries = Object.entries(rawChanges as Record<string, unknown>);
    if (entries.length === 0) return null;

    let addCount = 0;
    let modifyCount = 0;
    let deleteCount = 0;
    const detailLines: string[] = [];

    for (const [path, value] of entries) {
        const change = (value && typeof value === 'object')
            ? value as Record<string, unknown>
            : {};

        let kind: 'A' | 'M' | 'D' = 'M';
        if (change.add !== undefined) {
            kind = 'A';
            addCount += 1;
        } else if (change.delete !== undefined) {
            kind = 'D';
            deleteCount += 1;
        } else {
            modifyCount += 1;
        }

        detailLines.push(`${kind} ${toBasename(path)}`);
    }

    const fileWord = entries.length === 1 ? 'file' : 'files';
    const summaryLines = [
        `${entries.length} ${fileWord} changed (A${addCount} M${modifyCount} D${deleteCount})`,
        ...detailLines.slice(0, MAX_CHANGE_PREVIEW_FILES),
    ];

    const hiddenCount = detailLines.length - MAX_CHANGE_PREVIEW_FILES;
    if (hiddenCount > 0) {
        summaryLines.push(`... +${hiddenCount} more`);
    }

    return formatChangeSummary(summaryLines);
}

type DiffFileStat = {
    path: string;
    added: number;
    deleted: number;
};

function extractUnifiedDiffPreview(input: unknown): string | null {
    if (!input || typeof input !== 'object') return null;

    const obj = input as Record<string, unknown>;
    const unifiedDiff = typeof obj.unified_diff === 'string' ? obj.unified_diff : '';
    const fallbackPath = typeof obj.filePath === 'string' ? obj.filePath : null;

    if (!unifiedDiff && !fallbackPath) return null;

    const byPath = new Map<string, DiffFileStat>();
    const ensure = (path: string): DiffFileStat => {
        const existing = byPath.get(path);
        if (existing) return existing;
        const created: DiffFileStat = { path, added: 0, deleted: 0 };
        byPath.set(path, created);
        return created;
    };

    let currentPath: string | null = fallbackPath;
    if (currentPath) ensure(currentPath);

    for (const line of unifiedDiff.split('\n')) {
        if (line.startsWith('diff --git ')) {
            const match = line.match(/^diff --git a\/(.+?) b\/(.+)$/);
            if (match) {
                currentPath = match[2] || match[1] || null;
                if (currentPath) ensure(currentPath);
            }
            continue;
        }

        if (line.startsWith('+++ ')) {
            let nextPath = line.replace(/^\+\+\+\s+/, '');
            nextPath = nextPath.replace(/^b\//, '');
            if (nextPath && nextPath !== '/dev/null') {
                currentPath = nextPath;
                ensure(currentPath);
            }
            continue;
        }

        if (!currentPath) continue;

        if (line.startsWith('+') && !line.startsWith('+++')) {
            ensure(currentPath).added += 1;
            continue;
        }
        if (line.startsWith('-') && !line.startsWith('---')) {
            ensure(currentPath).deleted += 1;
            continue;
        }
    }

    const files = Array.from(byPath.values()).sort((a, b) => a.path.localeCompare(b.path));
    if (files.length === 0) return null;

    const totalAdded = files.reduce((sum, f) => sum + f.added, 0);
    const totalDeleted = files.reduce((sum, f) => sum + f.deleted, 0);

    const fileWord = files.length === 1 ? 'file' : 'files';
    const summaryLines = [
        `${files.length} ${fileWord} changed (+${totalAdded} -${totalDeleted})`,
        ...files.slice(0, MAX_CHANGE_PREVIEW_FILES).map((f) => (
            f.added === 0 && f.deleted === 0
                ? `M ${toBasename(f.path)}`
                : `M ${toBasename(f.path)} (+${f.added} -${f.deleted})`
        )),
    ];

    const hiddenCount = files.length - MAX_CHANGE_PREVIEW_FILES;
    if (hiddenCount > 0) {
        summaryLines.push(`... +${hiddenCount} more`);
    }

    return formatChangeSummary(summaryLines);
}

function extractChangePreview(tool: ToolCall): string | null {
    if (tool.name === 'CodexPatch' || tool.name === 'GeminiPatch') {
        return extractPatchChangePreview(tool.input);
    }
    if (tool.name === 'CodexDiff' || tool.name === 'GeminiDiff') {
        return extractUnifiedDiffPreview(tool.input);
    }
    return null;
}

function canRenderRichChangePreview(tool: ToolCall): boolean {
    if (tool.name === 'CodexPatch' || tool.name === 'GeminiPatch') {
        const changes = (tool.input as any)?.changes;
        return !!changes && typeof changes === 'object' && Object.keys(changes).length > 0;
    }
    if (tool.name === 'CodexDiff' || tool.name === 'GeminiDiff') {
        const unified = (tool.input as any)?.unified_diff;
        return typeof unified === 'string' && unified.trim().length > 0;
    }
    return false;
}

function extractCodexCommand(input: any): string | null {
    const parsedCmd = input?.parsed_cmd;
    if (Array.isArray(parsedCmd) && parsedCmd.length > 0 && typeof parsedCmd[0]?.cmd === 'string') {
        return parsedCmd[0].cmd;
    }

    if (Array.isArray(input?.command)) {
        const cmdArray = input.command as unknown[];
        if (
            cmdArray.length >= 3 &&
            (cmdArray[0] === 'bash' || cmdArray[0] === '/bin/bash' || cmdArray[0] === 'zsh' || cmdArray[0] === '/bin/zsh') &&
            cmdArray[1] === '-lc' &&
            typeof cmdArray[2] === 'string'
        ) {
            return cmdArray[2];
        }
        const joined = cmdArray.map((part) => String(part)).join(' ').trim();
        return joined || null;
    }

    return null;
}

function extractReasoningPreview(result: unknown): string | null {
    const truncatePreview = (text: string): string => (
        text.length > MAX_REASONING_PREVIEW_CHARS
            ? `${text.slice(0, MAX_REASONING_PREVIEW_CHARS)}\n...`
            : text
    );

    if (result === null || result === undefined) {
        return null;
    }

    if (typeof result === 'object') {
        const obj = result as Record<string, unknown>;
        const fromObject =
            toToolPreviewText(obj.content) ??
            toToolPreviewText(obj.text) ??
            toToolPreviewText(obj.message) ??
            toToolPreviewText(obj.reasoning);
        if (fromObject && fromObject.trim()) {
            return truncatePreview(fromObject);
        }
    }

    const direct = toToolPreviewText(result);
    if (!direct || !direct.trim()) {
        return null;
    }

    return truncatePreview(direct);
}

export const ToolView = React.memo<ToolViewProps>((props) => {
    const { tool, onPress, sessionId, messageId } = props;
    const router = useRouter();
    const { theme } = useUnistyles();
    const isShellLikeTool = tool.name === 'Bash' || tool.name === 'CodexBash';
    const isReasoningTool = REASONING_TOOL_NAMES.has(tool.name);
    const isChangeSummaryTool = CHANGE_SUMMARY_TOOL_NAMES.has(tool.name);
    const ChangeFullPreviewView = isChangeSummaryTool ? getToolFullViewComponent(tool.name) : null;
    const isPermissionPending = tool.permission?.status === 'pending';
    const [chatExpanded, setChatExpanded] = React.useState(() => {
        // If we're actively asking the user for consent (pending permission), keep the preview open.
        return props.variant === 'chat' && isShellLikeTool && isPermissionPending;
    });

    React.useEffect(() => {
        if (props.variant === 'chat' && isShellLikeTool && isPermissionPending) {
            setChatExpanded(true);
        }
    }, [props.variant, isShellLikeTool, isPermissionPending]);

    // Create default onPress handler for navigation
    const handlePress = React.useCallback(() => {
        if (onPress) {
            onPress();
        } else if (sessionId && messageId) {
            router.push(`/session/${sessionId}/message/${messageId}`);
        }
    }, [onPress, sessionId, messageId, router]);

    // Enable pressable if either onPress is provided or we have navigation params
    const isPressable = !!(onPress || (sessionId && messageId));

    let knownTool = knownTools[tool.name as keyof typeof knownTools] as any;

    let description: string | null = null;
    let status: string | null = null;
    let minimal = false;
    let icon = <Ionicons name="construct-outline" size={18} color={theme.colors.textSecondary} />;
    let noStatus = false;
    let hideDefaultError = false;
    
    // For Gemini: unknown tools should be rendered as minimal (hidden)
    // This prevents showing raw INPUT/OUTPUT for internal Gemini tools
    // that we haven't explicitly added to knownTools
    const isGemini = props.metadata?.flavor === 'gemini';
    if (!knownTool && isGemini) {
        minimal = true;
    }

    const isChatVariant = props.variant === 'chat';
    const showExpandedInChat = tool.name === 'AskUserQuestion';

    // Extract status first to potentially use as title
    if (knownTool && typeof knownTool.extractStatus === 'function') {
        const state = knownTool.extractStatus({ tool, metadata: props.metadata });
        if (typeof state === 'string' && state) {
            status = state;
        }
    }

    // Handle optional title and function type
    let toolTitle = tool.name;
    
    // Special handling for MCP tools
    if (tool.name.startsWith('mcp__')) {
        toolTitle = formatMCPTitle(tool.name);
        icon = <Ionicons name="extension-puzzle-outline" size={18} color={theme.colors.textSecondary} />;
        minimal = true;
    } else if (knownTool?.title) {
        if (typeof knownTool.title === 'function') {
            toolTitle = knownTool.title({ tool, metadata: props.metadata });
        } else {
            toolTitle = knownTool.title;
        }
    }

    if (knownTool && typeof knownTool.extractSubtitle === 'function') {
        const subtitle = knownTool.extractSubtitle({ tool, metadata: props.metadata });
        if (typeof subtitle === 'string' && subtitle) {
            description = subtitle;
        }
    }
    if (knownTool && knownTool.minimal !== undefined) {
        if (typeof knownTool.minimal === 'function') {
            minimal = knownTool.minimal({ tool, metadata: props.metadata, messages: props.messages });
        } else {
            minimal = knownTool.minimal;
        }
    }
    
    // Special handling for CodexBash to determine icon based on parsed_cmd
    if (tool.name === 'CodexBash' && tool.input?.parsed_cmd && Array.isArray(tool.input.parsed_cmd) && tool.input.parsed_cmd.length > 0) {
        const parsedCmd = tool.input.parsed_cmd[0];
        if (parsedCmd.type === 'read') {
            icon = <Octicons name="eye" size={18} color={theme.colors.text} />;
        } else if (parsedCmd.type === 'write') {
            icon = <Octicons name="file-diff" size={18} color={theme.colors.text} />;
        } else {
            icon = <Octicons name="terminal" size={18} color={theme.colors.text} />;
        }
    } else if (knownTool && typeof knownTool.icon === 'function') {
        icon = knownTool.icon(18, theme.colors.text);
    }
    
    if (knownTool && typeof knownTool.noStatus === 'boolean') {
        noStatus = knownTool.noStatus;
    }
    if (knownTool && typeof knownTool.hideDefaultError === 'boolean') {
        hideDefaultError = knownTool.hideDefaultError;
    }

    let statusIcon = null;

    let isToolUseError = false;
    if (tool.state === 'error' && tool.result && parseToolUseError(tool.result).isToolUseError) {
        isToolUseError = true;
        console.log('isToolUseError', tool.result);
    }

    // Check permission status first for denied/canceled states
    if (tool.permission && (tool.permission.status === 'denied' || tool.permission.status === 'canceled')) {
        statusIcon = <Ionicons name="remove-circle-outline" size={20} color={theme.colors.textSecondary} />;
    } else if (isToolUseError) {
        statusIcon = <Ionicons name="remove-circle-outline" size={20} color={theme.colors.textSecondary} />;
        hideDefaultError = true;
        minimal = true;
    } else {
        switch (tool.state) {
            case 'running':
                if (!noStatus) {
                    statusIcon = <ActivityIndicator size="small" color={theme.colors.text} style={{ transform: [{ scaleX: 0.8 }, { scaleY: 0.8 }] }} />;
                }
                break;
            case 'completed':
                // if (!noStatus) {
                //     statusIcon = <Ionicons name="checkmark-circle" size={20} color="#34C759" />;
                // }
                break;
            case 'error':
                statusIcon = <Ionicons name="alert-circle-outline" size={20} color={theme.colors.warning} />;
                break;
        }
    }

    // In chat, hide unknown Gemini internal tools completely.
    if (isChatVariant && isGemini && !knownTool && minimal) {
        return null;
    }

    // Chat-variant: keep the conversation readable by collapsing most tool cards to a single-line summary.
    // Users can tap to open the full tool details screen.
    if (isChatVariant && !showExpandedInChat) {
        // Build a nice, short label. Prefer the tool's "description" line when available.
        // Example: "터미널 • git status" feels closer to an activity line than just "터미널".
        let chatLabel = toolTitle;
        if (isReasoningTool) {
            const reasoningTitle =
                typeof tool.input?.title === 'string' ? tool.input.title.trim() : '';
            chatLabel = reasoningTitle || 'Thinking...';
        } else if (knownTool && typeof knownTool.extractDescription === 'function') {
            const desc = knownTool.extractDescription({ tool, metadata: props.metadata });
            if (typeof desc === 'string' && desc.trim()) {
                chatLabel = desc;
            }
        } else if (description && description.trim()) {
            chatLabel = description;
        }

        // Optional collapse/expand preview for shell commands and reasoning streams.
        // If we're asking for consent (pending permission), force the command preview open and hide the collapse icon.
        const isShellLike = isShellLikeTool;

        let command: string | null = null;
        let stdout: string | null = null;
        let stderr: string | null = null;
        let error: string | null = null;
        let reasoningPreview: string | null = null;
        let changesPreview: string | null = null;
        const hasRichChangesPreview =
            isChangeSummaryTool &&
            !!ChangeFullPreviewView &&
            canRenderRichChangePreview(tool);

        if (isShellLike) {
            if (tool.name === 'Bash') {
                if (typeof tool.input?.command === 'string') {
                    command = tool.input.command;
                }
                if (tool.state === 'completed' || tool.state === 'running' || tool.state === 'error') {
                    const parsed = parseShellOutput(tool.result);
                    stdout = parsed.stdout;
                    stderr = parsed.stderr;
                    if (tool.state === 'error') {
                        error = resolveShellErrorMessage(tool.result, parsed);
                        const deduped = dedupeShellOutputAgainstError(parsed, error);
                        stdout = deduped.stdout;
                        stderr = deduped.stderr;
                    }
                }
            } else if (tool.name === 'CodexBash') {
                command = extractCodexCommand(tool.input);
                if (tool.state === 'completed' || tool.state === 'running' || tool.state === 'error') {
                    const parsed = parseShellOutput(tool.result);
                    stdout = parsed.stdout;
                    stderr = parsed.stderr;
                    if (tool.state === 'error') {
                        error = resolveShellErrorMessage(tool.result, parsed);
                        const deduped = dedupeShellOutputAgainstError(parsed, error);
                        stdout = deduped.stdout;
                        stderr = deduped.stderr;
                    } else {
                        error = parsed.error;
                    }
                }
            }
        }
        if (isReasoningTool) {
            reasoningPreview = extractReasoningPreview(tool.result);
        }
        if (isChangeSummaryTool && !hasRichChangesPreview) {
            changesPreview = extractChangePreview(tool);
        }

        const canShowCommandPreview = isShellLike && !!command;
        const canShowReasoningPreview = isReasoningTool && !!reasoningPreview;
        const canShowChangesPreview = isChangeSummaryTool && (hasRichChangesPreview || !!changesPreview);
        const canShowPreview = canShowCommandPreview || canShowReasoningPreview || canShowChangesPreview;
        const forceExpanded = canShowCommandPreview && isPermissionPending;
        const expanded = chatExpanded || forceExpanded;
        const canToggleCollapse = canShowPreview && !forceExpanded;

        const toggleCollapse = React.useCallback(() => {
            // Keep web deterministic; animate native transitions lightly.
            if (Platform.OS !== 'web') {
                LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
            }
            setChatExpanded(v => !v);
        }, []);

        // For command tools: tap toggles collapse, long-press opens full tool details.
        const onChatPress = canToggleCollapse ? toggleCollapse : handlePress;
        const onChatLongPress = canToggleCollapse && isPressable ? handlePress : undefined;
        const isChatInteractive = isPressable || canToggleCollapse;

        const collapsedErrorLine =
            tool.state === 'error' && tool.result
                ? String(tool.result).split('\n')[0].trim()
                : null;

        return (
            <View style={styles.chatContainer}>
                {isChatInteractive ? (
                    <TouchableOpacity
                        style={styles.chatPressable}
                        onPress={onChatPress}
                        onLongPress={onChatLongPress}
                        activeOpacity={0.85}
                    >
                        <View style={styles.chatHeaderRow}>
                            <View style={styles.chatHeaderLeft}>
                                <View style={styles.chatIconDot} />
                                <Text style={styles.chatLabel} numberOfLines={1}>{chatLabel}</Text>
                            </View>
                            {tool.state === 'running' && (
                                <View style={styles.elapsedContainer}>
                                    <ElapsedView from={tool.createdAt} />
                                </View>
                            )}
                            <View style={styles.chatHeaderRight}>
                                {canToggleCollapse ? (
                                    <Ionicons
                                        name={expanded ? 'chevron-up' : 'chevron-down'}
                                        size={16}
                                        color={theme.colors.textSecondary}
                                    />
                                ) : null}
                                {statusIcon}
                            </View>
                        </View>
                        {collapsedErrorLine && !expanded ? (
                            <Text style={styles.chatErrorLine} numberOfLines={1}>
                                {collapsedErrorLine}
                            </Text>
                        ) : null}

                    </TouchableOpacity>
                ) : (
                    <View style={styles.chatStatic}>
                        <View style={styles.chatHeaderRow}>
                            <View style={styles.chatHeaderLeft}>
                                <View style={styles.chatIconDot} />
                                <Text style={styles.chatLabel} numberOfLines={1}>{chatLabel}</Text>
                            </View>
                            {tool.state === 'running' && (
                                <View style={styles.elapsedContainer}>
                                    <ElapsedView from={tool.createdAt} />
                                </View>
                            )}
                            <View style={styles.chatHeaderRight}>
                                {canToggleCollapse ? (
                                    <Ionicons
                                        name={expanded ? 'chevron-up' : 'chevron-down'}
                                        size={16}
                                        color={theme.colors.textSecondary}
                                    />
                                ) : null}
                                {statusIcon}
                            </View>
                        </View>
                        {collapsedErrorLine && !expanded ? (
                            <Text style={styles.chatErrorLine} numberOfLines={1}>
                                {collapsedErrorLine}
                            </Text>
                        ) : null}

                    </View>
                )}

                {canShowPreview && expanded ? (
                    <View style={styles.chatPreview}>
                        {canShowCommandPreview ? (
                            <CommandView
                                command={command!}
                                stdout={stdout}
                                stderr={stderr}
                                error={error}
                                maxHeight={240}
                                fullWidth
                                hideEmptyOutput={tool.state === 'running'}
                                variant="plain"
                            />
                        ) : canShowReasoningPreview ? (
                            <Text style={styles.chatReasoningPreviewText}>{reasoningPreview}</Text>
                        ) : hasRichChangesPreview && ChangeFullPreviewView ? (
                            <View style={styles.chatChangesPreviewContainer}>
                                <ChangeFullPreviewView
                                    tool={tool}
                                    metadata={props.metadata}
                                    messages={props.messages ?? []}
                                    sessionId={sessionId}
                                />
                            </View>
                        ) : (
                            <Text style={styles.chatChangesPreviewText}>{changesPreview}</Text>
                        )}
                    </View>
                ) : null}

                {/* Keep errors visible even in compact mode */}
                {tool.state === 'error' && tool.result &&
                    !(tool.permission && (tool.permission.status === 'denied' || tool.permission.status === 'canceled')) &&
                    !hideDefaultError && (
                        <View style={styles.chatError}>
                            <ToolError message={String(tool.result)} />
                        </View>
                    )}

                {/* Permission footer - always renders when permission exists to maintain consistent height */}
                {/* AskUserQuestion has its own Submit button UI - no permission footer needed */}
                {tool.permission && sessionId && tool.name !== 'AskUserQuestion' && (
                    <PermissionFooter permission={tool.permission} sessionId={sessionId} toolName={tool.name} toolInput={tool.input} metadata={props.metadata} />
                )}
            </View>
        );
    }

    return (
        <View style={styles.container}>
            {isPressable ? (
                <TouchableOpacity style={styles.header} onPress={handlePress} activeOpacity={0.8}>
                    <View style={styles.headerLeft}>
                        <View style={styles.iconContainer}>
                            {icon}
                        </View>
                        <View style={styles.titleContainer}>
                            <Text style={styles.toolName} numberOfLines={1}>{toolTitle}{status ? <Text style={styles.status}>{` ${status}`}</Text> : null}</Text>
                            {description && (
                                <Text style={styles.toolDescription} numberOfLines={1}>
                                    {description}
                                </Text>
                            )}
                        </View>
                        {tool.state === 'running' && (
                            <View style={styles.elapsedContainer}>
                                <ElapsedView from={tool.createdAt} />
                            </View>
                        )}
                        {statusIcon}
                    </View>
                </TouchableOpacity>
            ) : (
                <View style={styles.header}>
                    <View style={styles.headerLeft}>
                        <View style={styles.iconContainer}>
                            {icon}
                        </View>
                        <View style={styles.titleContainer}>
                            <Text style={styles.toolName} numberOfLines={1}>{toolTitle}{status ? <Text style={styles.status}>{` ${status}`}</Text> : null}</Text>
                            {description && (
                                <Text style={styles.toolDescription} numberOfLines={1}>
                                    {description}
                                </Text>
                            )}
                        </View>
                        {tool.state === 'running' && (
                            <View style={styles.elapsedContainer}>
                                <ElapsedView from={tool.createdAt} />
                            </View>
                        )}
                        {statusIcon}
                    </View>
                </View>
            )}

            {/* Content area - either custom children or tool-specific view */}
            {(() => {
                // Check if minimal first - minimal tools don't show content
                if (minimal) {
                    return null;
                }

                // Try to use a specific tool view component first
                const SpecificToolView = getToolViewComponent(tool.name);
                if (SpecificToolView) {
                    return (
                        <View style={styles.content}>
                            <SpecificToolView tool={tool} metadata={props.metadata} messages={props.messages ?? []} sessionId={sessionId} />
                            {tool.state === 'error' && tool.result &&
                                !(tool.permission && (tool.permission.status === 'denied' || tool.permission.status === 'canceled')) &&
                                !hideDefaultError && (
                                    <ToolError message={String(tool.result)} />
                                )}
                        </View>
                    );
                }

                // Show error state if present (but not for denied/canceled permissions and not when hideDefaultError is true)
                if (tool.state === 'error' && tool.result &&
                    !(tool.permission && (tool.permission.status === 'denied' || tool.permission.status === 'canceled')) &&
                    !isToolUseError) {
                    return (
                        <View style={styles.content}>
                            <ToolError message={String(tool.result)} />
                        </View>
                    );
                }

                // Fall back to default view
                return (
                    <View style={styles.content}>
                        {/* Default content when no custom view available */}
                        {tool.input && (
                            <ToolSectionView title={t('toolView.input')}>
                                <CodeView code={JSON.stringify(tool.input, null, 2)} />
                            </ToolSectionView>
                        )}

                        {tool.state === 'completed' && tool.result && (
                            <ToolSectionView title={t('toolView.output')}>
                                <CodeView
                                    code={typeof tool.result === 'string' ? tool.result : JSON.stringify(tool.result, null, 2)}
                                />
                            </ToolSectionView>
                        )}
                    </View>
                );
            })()}

            {/* Permission footer - always renders when permission exists to maintain consistent height */}
            {/* AskUserQuestion has its own Submit button UI - no permission footer needed */}
            {tool.permission && sessionId && tool.name !== 'AskUserQuestion' && (
                <PermissionFooter permission={tool.permission} sessionId={sessionId} toolName={tool.name} toolInput={tool.input} metadata={props.metadata} />
            )}
        </View>
    );
});

function ElapsedView(props: { from: number }) {
    const { from } = props;
    const elapsed = useElapsedTime(from);
    return <Text style={styles.elapsedText}>{elapsed.toFixed(1)}s</Text>;
}

const styles = StyleSheet.create((theme) => ({
    container: {
        backgroundColor: theme.colors.surfaceHigh,
        borderRadius: 8,
        marginVertical: 4,
        overflow: 'hidden'
    },
	    chatContainer: {
	        marginVertical: 4,
            width: '100%',
            alignSelf: 'stretch',
	    },
	    chatPressable: {
	        alignSelf: 'stretch',
            width: '100%',
	        maxWidth: '100%',
	        paddingVertical: 4,
	    },
	    chatStatic: {
	        alignSelf: 'stretch',
            width: '100%',
	        maxWidth: '100%',
	        paddingVertical: 4,
	    },
	    chatHeaderRow: {
	        flexDirection: 'row',
	        alignItems: 'center',
	        gap: 8,
	    },
    chatHeaderLeft: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
        flex: 1,
        minWidth: 0,
    },
    chatHeaderRight: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 6,
    },
    chatIconDot: {
        width: 6,
        height: 6,
        borderRadius: 999,
        backgroundColor: theme.colors.textSecondary,
        opacity: 0.55,
    },
	    chatLabel: {
	        flex: 1,
	        fontSize: 12,
	        color: theme.colors.textSecondary,
	        fontWeight: '500',
	    },
	    chatErrorLine: {
	        marginTop: 6,
	        fontSize: 12,
	        color: theme.colors.warning,
	        opacity: 0.9,
	    },
	    chatPreview: {
	        marginTop: 8,
	        marginBottom: 6,
	        marginLeft: 14, // align after dot
	        paddingLeft: 10,
	        borderLeftWidth: 2,
	        borderLeftColor: theme.colors.divider,
            flex: 1,
	    },
    chatReasoningPreviewText: {
        fontSize: 12,
        lineHeight: 18,
        color: theme.colors.text,
        opacity: 0.9,
    },
    chatChangesPreviewText: {
        fontSize: 12,
        lineHeight: 18,
        color: theme.colors.text,
        opacity: 0.9,
        ...Typography.mono(),
    },
    chatChangesPreviewContainer: {
        minHeight: 220,
        maxHeight: Platform.OS === 'web' ? 360 : 520,
        borderRadius: 10,
        overflow: 'visible',
    },
    chatError: {
        marginTop: 4,
    },
    header: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: 12,
        backgroundColor: theme.colors.surfaceHighest,
    },
    headerLeft: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
        flex: 1,
    },
    iconContainer: {
        width: 24,
        height: 24,
        alignItems: 'center',
        justifyContent: 'center',
    },
    titleContainer: {
        flex: 1,
    },
    elapsedContainer: {
        marginLeft: 8,
    },
    elapsedText: {
        fontSize: 13,
        color: theme.colors.textSecondary,
        fontFamily: Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' }),
    },
    toolName: {
        fontSize: 14,
        fontWeight: '500',
        color: theme.colors.text,
    },
    status: {
        fontWeight: '400',
        opacity: 0.3,
        fontSize: 15,
    },
    toolDescription: {
        fontSize: 13,
        color: theme.colors.textSecondary,
        marginTop: 2,
    },
    content: {
        paddingHorizontal: 12,
        paddingTop: 8,
        overflow: 'visible'
    },
}));
