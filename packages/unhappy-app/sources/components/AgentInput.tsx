import { Ionicons, Octicons } from '@/icons/vector-icons';
import * as React from 'react';
import { View, Platform, useWindowDimensions, Text, ActivityIndicator, TouchableWithoutFeedback, Pressable, TextInput } from 'react-native';
import { layout } from './layout';
import { MultiTextInput, KeyPressEvent } from './MultiTextInput';
import { Typography } from '@/constants/Typography';
import { PermissionMode } from './PermissionModeSelector';
import { hapticsLight, hapticsError } from './haptics';
import { Shaker, ShakeInstance } from './Shaker';
import { StatusDot } from './StatusDot';
import { useActiveWord } from './autocomplete/useActiveWord';
import { useActiveSuggestions } from './autocomplete/useActiveSuggestions';
import { AgentInputAutocomplete } from './AgentInputAutocomplete';
import { FloatingOverlay } from './FloatingOverlay';
import { TextInputState, MultiTextInputHandle } from './MultiTextInput';
import { applySuggestion } from './autocomplete/applySuggestion';
import { GitStatusBadge, useHasMeaningfulGitStatus } from './GitStatusBadge';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { apiSocket } from '@/sync/apiSocket';
import { useSetting } from '@/sync/storage';
import { Theme } from '@/theme';
import { t } from '@/text';
import { Metadata, type ReasoningEffortMode } from '@/sync/storageTypes';

interface AgentInputProps {
    value: string;
    placeholder: string;
    onChangeText: (text: string) => void;
    sessionId?: string;
    machineId?: string;
    onSend: () => void;
    sendIcon?: React.ReactNode;
    permissionMode?: PermissionMode;
    onPermissionModeChange?: (mode: PermissionMode) => void;
    modelMode?: string | null;
    onModelModeChange?: (mode: string | null) => void;
    effortMode?: ReasoningEffortMode | null;
    onEffortModeChange?: (mode: ReasoningEffortMode | null) => void;
    metadata?: Metadata | null;
    onAbort?: () => void | Promise<void>;
    showAbortButton?: boolean;
    connectionStatus?: {
        text: string;
        color: string;
        dotColor: string;
        isPulsing?: boolean;
        cliStatus?: {
            claude: boolean | null;
            codex: boolean | null;
            gemini?: boolean | null;
        };
    };
    autocompletePrefixes: string[];
    autocompleteSuggestions: (query: string) => Promise<{ key: string, text: string, component: React.ElementType }[]>;
    usageData?: {
        inputTokens: number;
        outputTokens: number;
        cacheCreation: number;
        cacheRead: number;
        contextSize: number;
    };
    onFileViewerPress?: () => void;
    agentType?: 'claude' | 'codex' | 'gemini';
    onAgentClick?: () => void;
    onAgentTypeChange?: (agentType: 'claude' | 'codex' | 'gemini') => void;
    machineName?: string | null;
    onMachineClick?: () => void;
    currentPath?: string | null;
    onPathClick?: () => void;
    sessionType?: 'simple' | 'worktree';
    onSessionTypeChange?: (value: 'simple' | 'worktree') => void;
    worktreeName?: string;
    onWorktreeNameChange?: (value: string) => void;
    onWorktreeNameGenerate?: () => void;
    isSendDisabled?: boolean;
    isSending?: boolean;
    minHeight?: number;
    profileId?: string | null;
    onProfileClick?: () => void;
}

const MAX_CONTEXT_SIZE = 190000;

const SUPPORTED_CLAUDE_MODELS = new Set([
    'claude-opus-4-6',
    'claude-sonnet-4-5',
    'claude-haiku-4-5',
]);

const stylesheet = StyleSheet.create((theme, runtime) => ({
    container: {
        alignItems: 'center',
        paddingBottom: Platform.select({ web: 6, default: 8 }),
        paddingTop: Platform.select({ web: 6, default: 8 }),
    },
    innerContainer: {
        width: '100%',
        position: 'relative',
    },
    unifiedPanel: {
        backgroundColor: theme.colors.input.background,
        borderRadius: Platform.select({ web: theme.borderRadius.md, default: 16, android: 20 }),
        overflow: 'hidden',
        paddingVertical: 2,
        paddingBottom: 8,
        paddingHorizontal: 8,
        ...(Platform.OS === 'web'
            ? {
                borderWidth: StyleSheet.hairlineWidth,
                borderColor: theme.colors.chrome.panelBorder,
                backgroundColor: theme.colors.surfaceHigh,
            }
            : null),
    },
    inputContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        borderWidth: 0,
        paddingLeft: 8,
        paddingRight: 8,
        paddingVertical: 4,
        minHeight: 40,
    },
    sessionTypeBox: {
        backgroundColor: theme.colors.surfacePressed,
        borderRadius: 12,
        padding: 10,
        marginBottom: 8,
        gap: 8,
    },
    sessionTypeTitle: {
        fontSize: 11,
        color: theme.colors.textSecondary,
        ...Typography.default('semiBold'),
    },
    sessionTypeOption: {
        flexDirection: 'row',
        alignItems: 'center',
        borderRadius: 12,
        paddingHorizontal: 10,
        paddingVertical: 10,
        gap: 10,
        borderWidth: 1,
        borderColor: theme.colors.divider,
        backgroundColor: theme.colors.surfaceHigh,
    },
    sessionTypeOptionActive: {
        borderColor: theme.colors.button.primary.background,
        backgroundColor: theme.colors.button.primary.background + '10',
    },
    sessionTypeOptionLabel: {
        fontSize: 13,
        color: theme.colors.text,
        fontWeight: '600',
        ...Typography.default('semiBold'),
    },
    sessionTypeOptionSpacer: {
        flex: 1,
    },
    worktreeNameBlock: {
        marginTop: 2,
        gap: 6,
    },
    worktreeNameHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
    },
    worktreeNameLabel: {
        fontSize: 12,
        color: theme.colors.textSecondary,
        ...Typography.default('semiBold'),
    },
    worktreeNameAction: {
        width: 32,
        height: 32,
        alignItems: 'center',
        justifyContent: 'center',
        borderRadius: 8,
        backgroundColor: theme.colors.surfaceHigh,
        borderWidth: 1,
        borderColor: theme.colors.divider,
    },
    worktreeNameInput: {
        backgroundColor: theme.colors.input.background,
        borderRadius: 10,
        paddingHorizontal: 12,
        paddingVertical: Platform.select({ web: 10, default: 12 }),
        borderWidth: 1,
        borderColor: theme.colors.divider,
        color: theme.colors.text,
        fontSize: 14,
        ...Typography.default(),
    },
    worktreeNameHint: {
        fontSize: 11,
        color: theme.colors.textSecondary,
        ...Typography.default(),
    },

    // Overlay styles
    autocompleteOverlay: {
        position: 'absolute',
        bottom: '100%',
        left: 0,
        right: 0,
        marginBottom: 8,
        zIndex: 1000,
    },
    settingsOverlay: {
        position: 'absolute',
        bottom: '100%',
        left: 0,
        right: 0,
        marginBottom: 8,
        zIndex: 1000,
    },
    overlayBackdrop: {
        position: 'absolute',
        top: -1000,
        left: -1000,
        right: -1000,
        bottom: -1000,
        zIndex: 999,
        backgroundColor: Platform.select({
            web: theme.dark ? 'rgba(0, 0, 0, 0.32)' : 'rgba(0, 0, 0, 0.10)',
            default: 'transparent'
        }),
    },
    overlaySection: {
        paddingVertical: 8,
    },
    overlaySectionTitle: {
        fontSize: 12,
        fontWeight: '600',
        color: theme.colors.textSecondary,
        paddingHorizontal: Platform.select({ web: 12, default: 16 }),
        paddingBottom: 4,
        ...Typography.default('semiBold'),
    },
    overlayDivider: {
        height: 1,
        backgroundColor: Platform.select({ web: theme.colors.chrome.panelBorder, default: theme.colors.divider }),
        marginHorizontal: Platform.select({ web: 12, default: 16 }),
    },

    // Selection styles
    selectionItem: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: Platform.select({ web: 12, default: 16 }),
        paddingVertical: 8,
        backgroundColor: 'transparent',
    },
    selectionItemPressed: {
        backgroundColor: theme.colors.surfacePressed,
    },
    radioButton: {
        width: 16,
        height: 16,
        borderRadius: 8,
        borderWidth: 2,
        alignItems: 'center',
        justifyContent: 'center',
        marginRight: 12,
    },
    radioButtonActive: {
        borderColor: theme.colors.radio.active,
    },
    radioButtonInactive: {
        borderColor: theme.colors.radio.inactive,
    },
    radioButtonDot: {
        width: 6,
        height: 6,
        borderRadius: 3,
        backgroundColor: theme.colors.radio.dot,
    },
    selectionLabel: {
        fontSize: 14,
        ...Typography.default(),
    },
    selectionLabelActive: {
        color: theme.colors.radio.active,
    },
    selectionLabelInactive: {
        color: theme.colors.text,
    },

    // Status styles
    statusContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        paddingHorizontal: Platform.select({ web: 12, default: 16 }),
        paddingBottom: 4,
    },
    statusRow: {
        flexDirection: 'row',
        alignItems: 'center',
    },
    statusText: {
        fontSize: 11,
        ...Typography.default(),
    },
    permissionModeContainer: {
        flexDirection: 'column',
        alignItems: 'flex-end',
    },
    permissionModeText: {
        fontSize: 11,
        ...Typography.default(),
    },
    contextWarningText: {
        fontSize: 11,
        marginLeft: 8,
        ...Typography.default(),
    },

    // Button styles
    actionButtonsContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        paddingHorizontal: 0,
    },
    actionButtonsLeft: {
        flexDirection: 'row',
        gap: 8,
        flex: 1,
        overflow: 'hidden',
    },
    actionButton: {
        flexDirection: 'row',
        alignItems: 'center',
        borderRadius: Platform.select({ default: 16, android: 20 }),
        paddingHorizontal: 8,
        paddingVertical: 6,
        justifyContent: 'center',
        height: 32,
    },
    actionButtonPressed: {
        opacity: 0.7,
    },
    actionButtonIcon: {
        color: theme.colors.button.secondary.tint,
    },
    sendButton: {
        width: 32,
        height: 32,
        borderRadius: 16,
        justifyContent: 'center',
        alignItems: 'center',
        flexShrink: 0,
        marginLeft: 8,
    },
    sendButtonActive: {
        backgroundColor: theme.colors.button.primary.background,
    },
    sendButtonInactive: {
        backgroundColor: theme.colors.button.primary.disabled,
    },
    sendButtonInner: {
        width: '100%',
        height: '100%',
        alignItems: 'center',
        justifyContent: 'center',
    },
    sendButtonInnerPressed: {
        opacity: 0.7,
    },
    sendButtonIcon: {
        color: theme.colors.button.primary.tint,
    },
}));

const getContextWarning = (contextSize: number, theme: Theme) => {
    const percentageUsed = (contextSize / MAX_CONTEXT_SIZE) * 100;
    const percentageRemaining = Math.max(0, Math.min(100, 100 - percentageUsed));

    if (percentageRemaining <= 5) {
        return { text: t('agentInput.context.remaining', { percent: Math.round(percentageRemaining) }), color: theme.colors.warningCritical };
    } else if (percentageRemaining <= 10) {
        return { text: t('agentInput.context.remaining', { percent: Math.round(percentageRemaining) }), color: theme.colors.warning };
    }
    // Always show context remaining in a neutral color when not near limit.
    return { text: t('agentInput.context.remaining', { percent: Math.round(percentageRemaining) }), color: theme.colors.textSecondary };
};

export const AgentInput = React.memo(React.forwardRef<MultiTextInputHandle, AgentInputProps>((props, ref) => {
    const styles = stylesheet;
    const { theme } = useUnistyles();
    const screenWidth = useWindowDimensions().width;

    const hasText = props.value.trim().length > 0;

    // Check which agent "flavor" we're on.
    // Use metadata.flavor for existing sessions, agentType prop for new sessions.
    const agentFlavor: 'claude' | 'codex' | 'gemini' =
        props.agentType === 'codex' || props.metadata?.flavor === 'codex'
            ? 'codex'
            : props.agentType === 'gemini' || props.metadata?.flavor === 'gemini'
                ? 'gemini'
                : 'claude';
    const isCodex = agentFlavor === 'codex';
    const isGemini = agentFlavor === 'gemini';

    // Calculate context warning (always shown when contextSize is known)
    const contextSize = props.usageData?.contextSize;
    const contextWarning = typeof contextSize === 'number' ? getContextWarning(contextSize, theme) : null;

    const agentInputEnterToSend = useSetting('agentInputEnterToSend');


    // Abort button state
    const [isAborting, setIsAborting] = React.useState(false);
    const shakerRef = React.useRef<ShakeInstance>(null);
    const inputRef = React.useRef<MultiTextInputHandle>(null);

    // Forward ref to the MultiTextInput
    React.useImperativeHandle(ref, () => inputRef.current!, []);

    // Autocomplete state - track text and selection together
    const [inputState, setInputState] = React.useState<TextInputState>({
        text: props.value,
        selection: { start: 0, end: 0 }
    });

    // Handle combined text and selection state changes
    const handleInputStateChange = React.useCallback((newState: TextInputState) => {
        setInputState(newState);
    }, []);

    // Use the tracked selection from inputState
    const activeWord = useActiveWord(inputState.text, inputState.selection, props.autocompletePrefixes);
    // Using default options: clampSelection=true, autoSelectFirst=true, wrapAround=true
    // To customize: useActiveSuggestions(activeWord, props.autocompleteSuggestions, { clampSelection: false, wrapAround: false })
    const [suggestions, selected, moveUp, moveDown] = useActiveSuggestions(activeWord, props.autocompleteSuggestions, { clampSelection: true, wrapAround: true });

    // Handle suggestion selection
    const handleSuggestionSelect = React.useCallback((index: number) => {
        if (!suggestions[index] || !inputRef.current) return;

        const suggestion = suggestions[index];

        // Apply the suggestion
        const result = applySuggestion(
            inputState.text,
            inputState.selection,
            suggestion.text,
            props.autocompletePrefixes,
            true // add space after
        );

        // Use imperative API to set text and selection
        inputRef.current.setTextAndSelection(result.text, {
            start: result.cursorPosition,
            end: result.cursorPosition
        });

        // Small haptic feedback
        hapticsLight();
    }, [suggestions, inputState, props.autocompletePrefixes]);

    type OverlayKind = null | 'permission' | 'model';
    const [overlayKind, setOverlayKind] = React.useState<OverlayKind>(null);

    // Model dropdown state (loaded on demand)
    type ListModelsResponse =
        | { success: true; models: string[] }
        | { success: false; error: string };
    const [availableModels, setAvailableModels] = React.useState<string[] | null>(null);
    const [isLoadingModels, setIsLoadingModels] = React.useState(false);
    const [modelLoadError, setModelLoadError] = React.useState<string | null>(null);
    const isResolvingModel = !!props.onModelModeChange && isLoadingModels && !availableModels;
    const ensureValidSelectedModel = React.useCallback((models: string[]) => {
        if (!props.onModelModeChange) return;
        if (!models || models.length === 0) return;
        const current = typeof props.modelMode === 'string' ? props.modelMode.trim() : '';
        if (!current || current === 'default' || !models.includes(current)) {
            props.onModelModeChange(models[0]);
        }
    }, [props.onModelModeChange, props.modelMode]);

    // Prevent cross-session/provider stale lists from sticking around.
    React.useEffect(() => {
        setAvailableModels(null);
        setModelLoadError(null);
    }, [agentFlavor, props.sessionId, props.machineId]);

    // Final guard: even if a daemon returns extra Claude ids, only show supported ones.
    React.useEffect(() => {
        if (agentFlavor !== 'claude') return;
        if (!availableModels) return;
        const filtered = availableModels.filter((m) => SUPPORTED_CLAUDE_MODELS.has(m));
        if (filtered.length === availableModels.length) return;
        if (filtered.length === 0) {
            setAvailableModels(null);
            setModelLoadError('No supported Claude models found.');
            return;
        }
        setAvailableModels(filtered);
        ensureValidSelectedModel(filtered);
    }, [agentFlavor, availableModels]);

    const loadModels = React.useCallback(async () => {
        if (agentFlavor === 'gemini') {
            // Static list, no RPC required.
            const models = ['gemini-2.5-pro', 'gemini-2.5-flash', 'gemini-2.5-flash-lite'];
            setAvailableModels(models);
            setModelLoadError(null);
            ensureValidSelectedModel(models);
            return;
        }
        if (!props.sessionId) {
            // New-session flow: no sessionId yet. If we have machineId, use machine-scoped RPC.
            if (props.machineId) {
                setIsLoadingModels(true);
                setModelLoadError(null);
                try {
                    const resp = await apiSocket.machineRPC<ListModelsResponse, { agent: 'claude' | 'codex' | 'gemini' }>(
                        props.machineId,
                        'list-models',
                        { agent: agentFlavor }
                    );
                    if (resp.success) {
                        const models = agentFlavor === 'claude'
                            ? (resp.models || []).filter((m) => SUPPORTED_CLAUDE_MODELS.has(m))
                            : (resp.models || []);
                        if (models.length === 0) {
                            setAvailableModels(null);
                            setModelLoadError(agentFlavor === 'claude' ? 'No supported Claude models found.' : 'No models found.');
                        } else {
                            setAvailableModels(models);
                            ensureValidSelectedModel(models);
                        }
                    } else {
                        setAvailableModels(null);
                        setModelLoadError(resp.error || 'Failed to load models.');
                    }
                } catch (e) {
                    setAvailableModels(null);
                    setModelLoadError(e instanceof Error ? e.message : 'Failed to load models.');
                } finally {
                    setIsLoadingModels(false);
                }
                return;
            }
            setAvailableModels(null);
            setModelLoadError(t('newSession.noMachineSelected'));
            return;
        }
        setIsLoadingModels(true);
        setModelLoadError(null);
        try {
            const resp = await apiSocket.sessionRPC<ListModelsResponse, {}>(props.sessionId, 'list-models', {});
            if (resp.success) {
                const models = agentFlavor === 'claude'
                    ? (resp.models || []).filter((m) => SUPPORTED_CLAUDE_MODELS.has(m))
                    : (resp.models || []);
                if (models.length === 0) {
                    setAvailableModels(null);
                    setModelLoadError(agentFlavor === 'claude' ? 'No supported Claude models found.' : 'No models found.');
                } else {
                    setAvailableModels(models);
                    ensureValidSelectedModel(models);
                }
            } else {
                setAvailableModels(null);
                setModelLoadError(resp.error || 'Failed to load models.');
            }
        } catch (e) {
            setAvailableModels(null);
            setModelLoadError(e instanceof Error ? e.message : 'Failed to load models.');
        } finally {
            setIsLoadingModels(false);
        }
    }, [agentFlavor, props.sessionId, props.machineId, ensureValidSelectedModel]);

    // If the caller supports model selection, ensure we have a *real* model selected.
    //
    // Important: modelMode can be pre-populated (ex: older sessions) with a model id that no longer exists.
    // In that case we still need to load the available model list once so we can auto-fallback to the first model.
    React.useEffect(() => {
        if (!props.onModelModeChange) return;
        if (isLoadingModels) return;
        // Avoid infinite background retry loops; user can tap-to-retry from the overlay.
        if (modelLoadError) return;

        // If we haven't loaded the list yet, do so once in the background.
        if (!availableModels) {
            // Fire-and-forget; loadModels handles errors internally.
            void loadModels();
            return;
        }

        // If we do have a list, ensure the current selection is valid (or pick the first).
        ensureValidSelectedModel(availableModels);
    }, [
        props.onModelModeChange,
        props.modelMode,
        isLoadingModels,
        modelLoadError,
        availableModels,
        loadModels,
        ensureValidSelectedModel
    ]);

    const handleAgentTypeSwitch = React.useCallback((next: 'claude' | 'codex' | 'gemini') => {
        if (!props.onAgentTypeChange) return;
        hapticsLight();
        props.onAgentTypeChange(next);

        // Always ensure Gemini has a concrete model.
        if (next === 'gemini') props.onModelModeChange?.('gemini-2.5-pro');
        // Force reload next time overlay opens (or immediately if already open).
        setAvailableModels(null);
        setModelLoadError(null);
    }, [props.onAgentTypeChange, props.onModelModeChange]);

    const openPermissionOverlay = React.useCallback(() => {
        if (!props.onPermissionModeChange) return;
        hapticsLight();
        setOverlayKind('permission');
    }, [props.onPermissionModeChange]);

    const openModelOverlay = React.useCallback(async () => {
        if (!props.onModelModeChange) return;
        hapticsLight();
        setOverlayKind('model');
        // Load models lazily when opening.
        // Treat empty list as "not loaded" so we recover from older cached empty results.
        if ((!availableModels || availableModels.length === 0 || !!modelLoadError) && !isLoadingModels) {
            await loadModels();
        }
    }, [props.onModelModeChange, availableModels, isLoadingModels, loadModels, modelLoadError]);

    const handlePermissionSelect = React.useCallback((mode: PermissionMode) => {
        hapticsLight();
        props.onPermissionModeChange?.(mode);
    }, [props.onPermissionModeChange]);

    const handleModelSelect = React.useCallback((model: string | null) => {
        hapticsLight();
        props.onModelModeChange?.(model);
        setOverlayKind(null);
    }, [props.onModelModeChange]);

    const permissionModeLabel = React.useMemo(() => {
        const mode = props.permissionMode ?? 'default';
        if (isCodex) {
            return mode === 'default' ? t('agentInput.codexPermissionMode.default') :
                mode === 'read-only' ? t('agentInput.codexPermissionMode.badgeReadOnly') :
                    mode === 'safe-yolo' ? t('agentInput.codexPermissionMode.badgeSafeYolo') :
                        mode === 'yolo' ? t('agentInput.codexPermissionMode.badgeYolo') : '';
        }
        if (isGemini) {
            return mode === 'default' ? t('agentInput.geminiPermissionMode.default') :
                mode === 'read-only' ? t('agentInput.geminiPermissionMode.badgeReadOnly') :
                    mode === 'safe-yolo' ? t('agentInput.geminiPermissionMode.badgeSafeYolo') :
                        mode === 'yolo' ? t('agentInput.geminiPermissionMode.badgeYolo') : '';
        }
        return mode === 'default' ? t('agentInput.permissionMode.default') :
            mode === 'acceptEdits' ? t('agentInput.permissionMode.badgeAcceptAllEdits') :
                mode === 'bypassPermissions' ? t('agentInput.permissionMode.badgeBypassAllPermissions') :
                    mode === 'plan' ? t('agentInput.permissionMode.badgePlanMode') : '';
    }, [isCodex, isGemini, props.permissionMode]);

    const permissionModeColor = React.useMemo(() => {
        const mode = props.permissionMode ?? 'default';
        return mode === 'acceptEdits' ? theme.colors.permission.acceptEdits :
            mode === 'bypassPermissions' ? theme.colors.permission.bypass :
                mode === 'plan' ? theme.colors.permission.plan :
                    mode === 'read-only' ? theme.colors.permission.readOnly :
                        mode === 'safe-yolo' ? theme.colors.permission.safeYolo :
                            mode === 'yolo' ? theme.colors.permission.yolo :
                                theme.colors.button.secondary.tint;
    }, [props.permissionMode, theme.colors]);

    const effectiveEffortLabel: string = props.effortMode ?? 'Default';
    const handleEffortPress = React.useCallback(() => {
        if (!props.onEffortModeChange) return;
        hapticsLight();
        const order: Array<ReasoningEffortMode | null> = [null, 'low', 'medium', 'high', 'max'];
        const current: ReasoningEffortMode | null = props.effortMode ?? null;
        const idx = order.indexOf(current);
        const next = order[(idx >= 0 ? idx + 1 : 0) % order.length] ?? null;
        props.onEffortModeChange(next);
    }, [props.onEffortModeChange, props.effortMode]);

    // Handle abort button press
    const handleAbortPress = React.useCallback(async () => {
        if (!props.onAbort) return;

        hapticsError();
        setIsAborting(true);
        const startTime = Date.now();

        try {
            await props.onAbort?.();

            // Ensure minimum 300ms loading time
            const elapsed = Date.now() - startTime;
            if (elapsed < 300) {
                await new Promise(resolve => setTimeout(resolve, 300 - elapsed));
            }
        } catch (error) {
            // Shake on error
            shakerRef.current?.shake();
            console.error('Abort RPC call failed:', error);
        } finally {
            setIsAborting(false);
        }
    }, [props.onAbort]);

    // Handle keyboard navigation
    const handleKeyPress = React.useCallback((event: KeyPressEvent): boolean => {
        // Handle autocomplete navigation first
        if (suggestions.length > 0) {
            if (event.key === 'ArrowUp') {
                moveUp();
                return true;
            } else if (event.key === 'ArrowDown') {
                moveDown();
                return true;
            } else if ((event.key === 'Enter' || (event.key === 'Tab' && !event.shiftKey))) {
                // Both Enter and Tab select the current suggestion
                // If none selected (selected === -1), select the first one
                const indexToSelect = selected >= 0 ? selected : 0;
                handleSuggestionSelect(indexToSelect);
                return true;
            } else if (event.key === 'Escape') {
                // Clear suggestions by collapsing selection (triggers activeWord to clear)
                if (inputRef.current) {
                    const cursorPos = inputState.selection.start;
                    inputRef.current.setTextAndSelection(inputState.text, {
                        start: cursorPos,
                        end: cursorPos
                    });
                }
                return true;
            }
        }

        // Handle Escape for abort when no suggestions are visible
        if (event.key === 'Escape' && props.showAbortButton && props.onAbort && !isAborting) {
            handleAbortPress();
            return true;
        }

        // Original key handling
        if (Platform.OS === 'web') {
            if (agentInputEnterToSend && event.key === 'Enter' && !event.shiftKey) {
                if (props.value.trim()) {
                    props.onSend();
                    return true; // Key was handled
                }
            }
            // Handle Shift+Tab for permission mode switching
            if (event.key === 'Tab' && event.shiftKey && props.onPermissionModeChange) {
                const modeOrder: PermissionMode[] = isCodex
                    ? ['default', 'read-only', 'safe-yolo', 'yolo']
                    : ['default', 'acceptEdits', 'plan', 'bypassPermissions']; // Claude and Gemini share same modes
                const currentIndex = modeOrder.indexOf(props.permissionMode || 'default');
                const nextIndex = (currentIndex + 1) % modeOrder.length;
                props.onPermissionModeChange(modeOrder[nextIndex]);
                hapticsLight();
                return true; // Key was handled, prevent default tab behavior
            }

        }
        return false; // Key was not handled
    }, [suggestions, moveUp, moveDown, selected, handleSuggestionSelect, props.showAbortButton, props.onAbort, isAborting, handleAbortPress, agentInputEnterToSend, props.value, props.onSend, props.permissionMode, props.onPermissionModeChange]);




    return (
        <View style={[
            styles.container,
            { paddingHorizontal: screenWidth > 700 ? 16 : 8 }
        ]}>
            <View style={[
                styles.innerContainer,
                { maxWidth: layout.maxWidth }
            ]}>
                {/* Autocomplete suggestions overlay */}
                {suggestions.length > 0 && (
                    <View style={[
                        styles.autocompleteOverlay,
                        { paddingHorizontal: screenWidth > 700 ? 0 : 8 }
                    ]}>
                        <AgentInputAutocomplete
                            suggestions={suggestions.map(s => {
                                const Component = s.component;
                                return <Component key={s.key} />;
                            })}
                            selectedIndex={selected}
                            onSelect={handleSuggestionSelect}
                            itemHeight={48}
                        />
                    </View>
                )}

                {/* Settings overlays */}
                {overlayKind && (
                    <>
                        <TouchableWithoutFeedback onPress={() => setOverlayKind(null)}>
                            <View style={styles.overlayBackdrop} />
                        </TouchableWithoutFeedback>
                        <View style={[
                            styles.settingsOverlay,
                            { paddingHorizontal: screenWidth > 700 ? 0 : 8 }
                        ]}>
                            <FloatingOverlay maxHeight={400} keyboardShouldPersistTaps="always">
                                {overlayKind === 'permission' ? (
                                    <View style={styles.overlaySection}>
                                        <Text style={styles.overlaySectionTitle}>
                                            {isCodex ? t('agentInput.codexPermissionMode.title') : isGemini ? t('agentInput.geminiPermissionMode.title') : t('agentInput.permissionMode.title')}
                                        </Text>
                                        {((isCodex || isGemini)
                                            ? (['default', 'read-only', 'safe-yolo', 'yolo'] as const)
                                            : (['default', 'acceptEdits', 'plan', 'bypassPermissions'] as const)
                                        ).map((mode) => {
                                            const modeConfig = isCodex ? {
                                                'default': { label: t('agentInput.codexPermissionMode.default') },
                                                'read-only': { label: t('agentInput.codexPermissionMode.readOnly') },
                                                'safe-yolo': { label: t('agentInput.codexPermissionMode.safeYolo') },
                                                'yolo': { label: t('agentInput.codexPermissionMode.yolo') },
                                            } : isGemini ? {
                                                'default': { label: t('agentInput.geminiPermissionMode.default') },
                                                'read-only': { label: t('agentInput.geminiPermissionMode.readOnly') },
                                                'safe-yolo': { label: t('agentInput.geminiPermissionMode.safeYolo') },
                                                'yolo': { label: t('agentInput.geminiPermissionMode.yolo') },
                                            } : {
                                                default: { label: t('agentInput.permissionMode.default') },
                                                acceptEdits: { label: t('agentInput.permissionMode.acceptEdits') },
                                                plan: { label: t('agentInput.permissionMode.plan') },
                                                bypassPermissions: { label: t('agentInput.permissionMode.bypassPermissions') },
                                            };
                                            const config = modeConfig[mode as keyof typeof modeConfig];
                                            if (!config) return null;
                                            const isSelected = props.permissionMode === mode;

                                            return (
                                                <Pressable
                                                    key={mode}
                                                    onPress={() => handlePermissionSelect(mode)}
                                                    style={({ pressed, hovered }: any) => ({
                                                        flexDirection: 'row',
                                                        alignItems: 'center',
                                                        paddingHorizontal: Platform.select({ web: 12, default: 16 }),
                                                        paddingVertical: 8,
                                                        backgroundColor: Platform.OS === 'web'
                                                            ? (pressed
                                                                ? theme.colors.chrome.listActiveBackground
                                                                : hovered
                                                                    ? theme.colors.chrome.listHoverBackground
                                                                    : 'transparent')
                                                            : (pressed ? theme.colors.surfacePressed : 'transparent')
                                                    })}
                                                >
                                                    <View style={{
                                                        width: 16,
                                                        height: 16,
                                                        borderRadius: 8,
                                                        borderWidth: 2,
                                                        borderColor: isSelected ? theme.colors.radio.active : theme.colors.radio.inactive,
                                                        alignItems: 'center',
                                                        justifyContent: 'center',
                                                        marginRight: 12
                                                    }}>
                                                        {isSelected && (
                                                            <View style={{
                                                                width: 6,
                                                                height: 6,
                                                                borderRadius: 3,
                                                                backgroundColor: theme.colors.radio.dot
                                                            }} />
                                                        )}
                                                    </View>
                                                    <Text style={{
                                                        fontSize: 14,
                                                        color: isSelected ? theme.colors.radio.active : theme.colors.text,
                                                        ...Typography.default()
                                                    }}>
                                                        {config.label}
                                                    </Text>
                                                </Pressable>
                                            );
                                        })}
                                    </View>
                                ) : (
                                    <View style={{ paddingVertical: 8 }}>
                                        <Text style={{
                                            fontSize: 12,
                                            fontWeight: '600',
                                            color: theme.colors.textSecondary,
                                            paddingHorizontal: Platform.select({ web: 12, default: 16 }),
                                            paddingBottom: 4,
                                            ...Typography.default('semiBold')
                                        }}>
                                            {t('agentInput.model.title')}
                                        </Text>

                                        {/* Provider switcher (pre-session only). This unifies "Claude/Codex" switching with the model picker. */}
                                        {!props.sessionId && props.onAgentTypeChange && (
                                            <View style={{
                                                flexDirection: 'row',
                                                gap: 8,
                                                paddingHorizontal: Platform.select({ web: 12, default: 16 }),
                                                paddingBottom: 8,
                                            }}>
                                                {(['claude', 'codex', 'gemini'] as const).map((k) => {
                                                    // Only show Gemini when the caller has Gemini enabled (ex: experiments flag).
                                                    if (k === 'gemini' && props.connectionStatus?.cliStatus?.gemini === undefined) return null;
                                                    const active = agentFlavor === k;
                                                    return (
                                                        <Pressable
                                                            key={k}
                                                            onPress={() => handleAgentTypeSwitch(k)}
                                                            style={({ pressed }: any) => ({
                                                                height: 28,
                                                                paddingHorizontal: 10,
                                                                borderRadius: 999,
                                                                borderWidth: 1,
                                                                borderColor: active ? theme.colors.button.primary.background : theme.colors.divider,
                                                                backgroundColor: active ? theme.colors.button.primary.background + '14' : 'transparent',
                                                                justifyContent: 'center',
                                                                opacity: pressed ? 0.7 : 1,
                                                            })}
                                                        >
                                                            <Text style={{
                                                                fontSize: 12,
                                                                fontWeight: '600',
                                                                color: active ? theme.colors.button.primary.background : theme.colors.textSecondary,
                                                                ...Typography.default('semiBold'),
                                                            }}>
                                                                {k === 'claude' ? 'Claude' : k === 'codex' ? 'Codex' : 'Gemini'}
                                                            </Text>
                                                        </Pressable>
                                                    );
                                                })}
                                            </View>
                                        )}

                                        {isLoadingModels ? (
                                            <View style={{ paddingHorizontal: Platform.select({ web: 12, default: 16 }), paddingVertical: 12 }}>
                                                <ActivityIndicator size="small" color={theme.colors.textSecondary} />
                                            </View>
                                        ) : modelLoadError ? (
                                            <Pressable
                                                onPress={() => {
                                                    if (!isLoadingModels) void loadModels();
                                                }}
                                                style={({ pressed }: any) => ({
                                                    paddingHorizontal: Platform.select({ web: 12, default: 16 }),
                                                    paddingVertical: 8,
                                                    opacity: pressed ? 0.7 : 1,
                                                })}
                                            >
                                                    <Text style={{
                                                        fontSize: 13,
                                                        color: theme.colors.textSecondary,
                                                        ...Typography.default()
                                                    }}>
                                                        {modelLoadError} {' '}
                                                        <Text style={{ color: theme.colors.button.secondary.tint, fontWeight: '600', ...Typography.default('semiBold') }}>
                                                            Tap to retry
                                                        </Text>
                                                    </Text>
                                            </Pressable>
                                        ) : (
                                            <>
                                                {(availableModels || []).map((model) => {
                                                    const isSelected = props.modelMode === model;
                                                    return (
                                                        <Pressable
                                                            key={model}
                                                            onPress={() => handleModelSelect(model)}
                                                            style={({ pressed, hovered }: any) => ({
                                                                flexDirection: 'row',
                                                                alignItems: 'center',
                                                                paddingHorizontal: Platform.select({ web: 12, default: 16 }),
                                                                paddingVertical: 8,
                                                                backgroundColor: Platform.OS === 'web'
                                                                    ? (pressed
                                                                        ? theme.colors.chrome.listActiveBackground
                                                                        : hovered
                                                                            ? theme.colors.chrome.listHoverBackground
                                                                            : 'transparent')
                                                                    : (pressed ? theme.colors.surfacePressed : 'transparent')
                                                            })}
                                                        >
                                                            <View style={{
                                                                width: 16,
                                                                height: 16,
                                                                borderRadius: 8,
                                                                borderWidth: 2,
                                                                borderColor: isSelected ? theme.colors.radio.active : theme.colors.radio.inactive,
                                                                alignItems: 'center',
                                                                justifyContent: 'center',
                                                                marginRight: 12
                                                            }}>
                                                                {isSelected && (
                                                                    <View style={{
                                                                        width: 6,
                                                                        height: 6,
                                                                        borderRadius: 3,
                                                                        backgroundColor: theme.colors.radio.dot
                                                                    }} />
                                                                )}
                                                            </View>
                                                            <Text style={{
                                                                fontSize: 14,
                                                                color: isSelected ? theme.colors.radio.active : theme.colors.text,
                                                                ...Typography.default()
                                                            }}>
                                                                {model}
                                                            </Text>
                                                        </Pressable>
                                                    );
                                                })}
                                            </>
                                        )}
                                    </View>
                                )}
                            </FloatingOverlay>
                        </View>
                    </>
                )}

                {/* Connection status and context warning */}
                {(props.connectionStatus || contextWarning) && (
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        justifyContent: 'flex-start',
                        paddingHorizontal: 16,
                        paddingBottom: 4,
                        minHeight: 20, // Fixed minimum height to prevent jumping
                    }}>
                        <View style={{ flexDirection: 'row', alignItems: 'center', flex: 1, gap: 11 }}>
                            {props.connectionStatus && (
                                <>
                                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
                                        <StatusDot
                                            color={props.connectionStatus.dotColor}
                                            isPulsing={props.connectionStatus.isPulsing}
                                            size={6}
                                        />
                                        <Text style={{
                                            fontSize: 11,
                                            color: props.connectionStatus.color,
                                            ...Typography.default()
                                        }}>
                                            {props.connectionStatus.text}
                                        </Text>
                                    </View>
                                    {/* CLI Status - only shown when provided (wizard only) */}
                                    {props.connectionStatus.cliStatus && (
                                        <>
                                            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
                                                <Text style={{
                                                    fontSize: 11,
                                                    color: props.connectionStatus.cliStatus.claude
                                                        ? theme.colors.success
                                                        : theme.colors.textDestructive,
                                                    ...Typography.default()
                                                }}>
                                                    {props.connectionStatus.cliStatus.claude ? '✓' : '✗'}
                                                </Text>
                                                <Text style={{
                                                    fontSize: 11,
                                                    color: props.connectionStatus.cliStatus.claude
                                                        ? theme.colors.success
                                                        : theme.colors.textDestructive,
                                                    ...Typography.default()
                                                }}>
                                                    claude
                                                </Text>
                                            </View>
                                            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
                                                <Text style={{
                                                    fontSize: 11,
                                                    color: props.connectionStatus.cliStatus.codex
                                                        ? theme.colors.success
                                                        : theme.colors.textDestructive,
                                                    ...Typography.default()
                                                }}>
                                                    {props.connectionStatus.cliStatus.codex ? '✓' : '✗'}
                                                </Text>
                                                <Text style={{
                                                    fontSize: 11,
                                                    color: props.connectionStatus.cliStatus.codex
                                                        ? theme.colors.success
                                                        : theme.colors.textDestructive,
                                                    ...Typography.default()
                                                }}>
                                                    codex
                                                </Text>
                                            </View>
                                            {props.connectionStatus.cliStatus.gemini !== undefined && (
                                                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
                                                    <Text style={{
                                                        fontSize: 11,
                                                        color: props.connectionStatus.cliStatus.gemini
                                                            ? theme.colors.success
                                                            : theme.colors.textDestructive,
                                                        ...Typography.default()
                                                    }}>
                                                        {props.connectionStatus.cliStatus.gemini ? '✓' : '✗'}
                                                    </Text>
                                                    <Text style={{
                                                        fontSize: 11,
                                                        color: props.connectionStatus.cliStatus.gemini
                                                            ? theme.colors.success
                                                            : theme.colors.textDestructive,
                                                        ...Typography.default()
                                                    }}>
                                                        gemini
                                                    </Text>
                                                </View>
                                            )}
                                        </>
                                    )}
                                </>
                            )}
                            {contextWarning && (
                                <Text style={{
                                    fontSize: 11,
                                    color: contextWarning.color,
                                    marginLeft: props.connectionStatus ? 8 : 0,
                                    ...Typography.default()
                                }}>
                                    {props.connectionStatus ? '• ' : ''}{contextWarning.text}
                                </Text>
                            )}
                        </View>
                    </View>
                )}

                {/* Box 1: Context Information (Machine + Path) - Only show if either exists */}
                {(props.machineName !== undefined || props.currentPath) && (
                    <View style={{
                        backgroundColor: theme.colors.surfacePressed,
                        borderRadius: 12,
                        padding: 8,
                        marginBottom: 8,
                        gap: 4,
                    }}>
                        {/* Machine chip */}
                        {props.machineName !== undefined && props.onMachineClick && (
                            <Pressable
                                onPress={() => {
                                    hapticsLight();
                                    props.onMachineClick?.();
                                }}
                                hitSlop={{ top: 5, bottom: 10, left: 0, right: 0 }}
                                style={(p) => ({
                                    flexDirection: 'row',
                                    alignItems: 'center',
                                    borderRadius: Platform.select({ default: 16, android: 20 }),
                                    paddingHorizontal: 10,
                                    paddingVertical: 6,
                                    height: 32,
                                    opacity: p.pressed ? 0.7 : 1,
                                    gap: 6,
                                })}
                            >
                                <Ionicons
                                    name="desktop-outline"
                                    size={14}
                                    color={theme.colors.textSecondary}
                                />
                                <Text style={{
                                    fontSize: 13,
                                    color: theme.colors.text,
                                    fontWeight: '600',
                                    ...Typography.default('semiBold'),
                                }}>
                                    {props.machineName === null ? t('agentInput.noMachinesAvailable') : props.machineName}
                                </Text>
                            </Pressable>
                        )}

                        {/* Path chip */}
                        {props.currentPath && props.onPathClick && (
                            <Pressable
                                onPress={() => {
                                    hapticsLight();
                                    props.onPathClick?.();
                                }}
                                hitSlop={{ top: 5, bottom: 10, left: 0, right: 0 }}
                                style={(p) => ({
                                    flexDirection: 'row',
                                    alignItems: 'center',
                                    borderRadius: Platform.select({ default: 16, android: 20 }),
                                    paddingHorizontal: 10,
                                    paddingVertical: 6,
                                    height: 32,
                                    opacity: p.pressed ? 0.7 : 1,
                                    gap: 6,
                                })}
                            >
                                <Ionicons
                                    name="folder-outline"
                                    size={14}
                                    color={theme.colors.textSecondary}
                                />
                                <Text style={{
                                    fontSize: 13,
                                    color: theme.colors.text,
                                    fontWeight: '600',
                                    ...Typography.default('semiBold'),
                                }}>
                                    {props.currentPath}
                                </Text>
                            </Pressable>
                        )}
                    </View>
                )}

                {/* Box 1.5: Session Type (rendered under path selection for new-session flows) */}
                {!!props.sessionType && !!props.onSessionTypeChange && (
                    <View style={styles.sessionTypeBox}>
                        <Text style={styles.sessionTypeTitle}>{t('newSession.sessionType.title')}</Text>

                        <Pressable
                            onPress={() => {
                                hapticsLight();
                                props.onSessionTypeChange?.('simple');
                            }}
                            style={(p) => ([
                                styles.sessionTypeOption,
                                props.sessionType === 'simple' && styles.sessionTypeOptionActive,
                                p.pressed ? { opacity: 0.85 } : null,
                            ])}
                        >
                            <Ionicons name="folder-outline" size={16} color={theme.colors.textSecondary} />
                            <Text style={styles.sessionTypeOptionLabel}>{t('newSession.sessionType.simple')}</Text>
                            <View style={styles.sessionTypeOptionSpacer} />
                            {props.sessionType === 'simple' && (
                                <Ionicons
                                    name="checkmark-circle"
                                    size={18}
                                    color={theme.colors.button.primary.background}
                                />
                            )}
                        </Pressable>

                        <Pressable
                            onPress={() => {
                                hapticsLight();
                                props.onSessionTypeChange?.('worktree');
                            }}
                            style={(p) => ([
                                styles.sessionTypeOption,
                                props.sessionType === 'worktree' && styles.sessionTypeOptionActive,
                                p.pressed ? { opacity: 0.85 } : null,
                            ])}
                        >
                            <Ionicons name="git-branch-outline" size={16} color={theme.colors.textSecondary} />
                            <Text style={styles.sessionTypeOptionLabel}>{t('newSession.sessionType.worktree')}</Text>
                            <View style={styles.sessionTypeOptionSpacer} />
                            {props.sessionType === 'worktree' && (
                                <Ionicons
                                    name="checkmark-circle"
                                    size={18}
                                    color={theme.colors.button.primary.background}
                                />
                            )}
                        </Pressable>

                        {props.sessionType === 'worktree' && props.worktreeName !== undefined && props.onWorktreeNameChange && (
                            <View style={styles.worktreeNameBlock}>
                                <View style={styles.worktreeNameHeader}>
                                    <Text style={styles.worktreeNameLabel}>{t('newSession.worktree.nameLabel')}</Text>
                                    {props.onWorktreeNameGenerate && (
                                        <Pressable
                                            onPress={() => {
                                                hapticsLight();
                                                props.onWorktreeNameGenerate?.();
                                            }}
                                            hitSlop={10}
                                            style={(p) => ([
                                                styles.worktreeNameAction,
                                                p.pressed ? { opacity: 0.85 } : null,
                                            ])}
                                            accessibilityLabel="Generate worktree name"
                                        >
                                            <Ionicons name="shuffle" size={16} color={theme.colors.textSecondary} />
                                        </Pressable>
                                    )}
                                </View>
                                <TextInput
                                    value={props.worktreeName}
                                    onChangeText={props.onWorktreeNameChange}
                                    placeholder={t('newSession.worktree.namePlaceholder')}
                                    placeholderTextColor={theme.colors.textSecondary}
                                    autoCapitalize="none"
                                    autoCorrect={false}
                                    spellCheck={false}
                                    style={styles.worktreeNameInput}
                                />
                                <Text style={styles.worktreeNameHint}>{t('newSession.worktree.nameHint')}</Text>
                            </View>
                        )}
                    </View>
                )}

                {/* Box 2: Action Area (Input + Send) */}
                <View style={styles.unifiedPanel}>
                    {/* Input field */}
                    <View style={[styles.inputContainer, props.minHeight ? { minHeight: props.minHeight } : undefined]}>
                        <MultiTextInput
                            ref={inputRef}
                            value={props.value}
                            paddingTop={Platform.OS === 'web' ? 10 : 8}
                            paddingBottom={Platform.OS === 'web' ? 10 : 8}
                            onChangeText={props.onChangeText}
                            placeholder={props.placeholder}
                            onKeyPress={handleKeyPress}
                            onStateChange={handleInputStateChange}
                            maxHeight={120}
                        />
                    </View>

                    {/* Action buttons below input */}
                    <View style={styles.actionButtonsContainer}>
                        <View style={styles.actionButtonsLeft}>
                            {/* Permission mode (YOLO / approvals) */}
                            {props.permissionMode && (
                                <Pressable
                                    disabled={!props.onPermissionModeChange}
                                    onPress={openPermissionOverlay}
                                    hitSlop={{ top: 5, bottom: 10, left: 0, right: 0 }}
                                    style={({ pressed, hovered }: any) => ({
                                        flexDirection: 'row',
                                        alignItems: 'center',
                                        borderRadius: Platform.select({ default: 16, android: 20 }),
                                        paddingHorizontal: 10,
                                        paddingVertical: 6,
                                        justifyContent: 'center',
                                        height: 32,
                                        opacity: props.onPermissionModeChange
                                            ? ((Platform.OS === 'web' && (hovered || pressed)) || pressed ? 0.7 : 1)
                                            : 1,
                                        gap: 6,
                                        flexShrink: 0,
                                    })}
                                >
                                    <Ionicons
                                        name="shield-checkmark-outline"
                                        size={14}
                                        color={permissionModeColor}
                                    />
                                    <Text style={{
                                        fontSize: 13,
                                        color: permissionModeColor,
                                        fontWeight: '600',
                                        ...Typography.default('semiBold'),
                                    }} numberOfLines={1}>
                                        {permissionModeLabel}
                                    </Text>
                                    <Ionicons
                                        name="chevron-down"
                                        size={14}
                                        color={permissionModeColor}
                                    />
                                </Pressable>
                            )}

                            {/* Model */}
                            {props.onModelModeChange && (
                                <Pressable
                                    onPress={openModelOverlay as any}
                                    hitSlop={{ top: 5, bottom: 10, left: 0, right: 0 }}
                                    style={(p) => ({
                                        flexDirection: 'row',
                                        alignItems: 'center',
                                        borderRadius: Platform.select({ default: 16, android: 20 }),
                                        paddingHorizontal: 10,
                                        paddingVertical: 6,
                                        justifyContent: 'center',
                                        height: 32,
                                        opacity: p.pressed ? 0.7 : 1,
                                        gap: 6,
                                    })}
                                >
                                    <Ionicons
                                        name="cube-outline"
                                        size={14}
                                        color={theme.colors.button.secondary.tint}
                                    />
                                    {isLoadingModels && (
                                        <ActivityIndicator size="small" color={theme.colors.button.secondary.tint} />
                                    )}
                                    <Text style={{
                                        fontSize: 13,
                                        color: theme.colors.button.secondary.tint,
                                        fontWeight: '600',
                                        ...Typography.default('semiBold'),
                                    }} numberOfLines={1}>
                                        {isLoadingModels && !availableModels
                                            ? t('common.loading')
                                            : (props.modelMode && props.modelMode !== 'default'
                                                ? props.modelMode
                                                : 'Select model')}
                                    </Text>
                                    <Ionicons
                                        name="chevron-down"
                                        size={14}
                                        color={theme.colors.button.secondary.tint}
                                    />
                                </Pressable>
                            )}

                            {/* Reasoning effort */}
                            {props.onEffortModeChange && (
                                <Pressable
                                    onPress={handleEffortPress}
                                    hitSlop={{ top: 5, bottom: 10, left: 0, right: 0 }}
                                    accessibilityRole="button"
                                    accessibilityLabel={`Reasoning effort: ${effectiveEffortLabel}`}
                                    style={(p) => ({
                                        flexDirection: 'row',
                                        alignItems: 'center',
                                        borderRadius: Platform.select({ default: 16, android: 20 }),
                                        paddingHorizontal: 10,
                                        paddingVertical: 6,
                                        justifyContent: 'center',
                                        height: 32,
                                        opacity: p.pressed ? 0.7 : 1,
                                    })}
                                >
                                    <EffortBatteryIcon effort={props.effortMode ?? null} color={theme.colors.button.secondary.tint} />
                                </Pressable>
                            )}

                            {/* Agent selector (new session only) */}
                            {props.agentType && props.onAgentClick && (
                                <Pressable
                                    onPress={() => {
                                        hapticsLight();
                                        props.onAgentClick?.();
                                    }}
                                    hitSlop={{ top: 5, bottom: 10, left: 0, right: 0 }}
                                    style={(p) => ({
                                        flexDirection: 'row',
                                        alignItems: 'center',
                                        borderRadius: Platform.select({ default: 16, android: 20 }),
                                        paddingHorizontal: 10,
                                        paddingVertical: 6,
                                        justifyContent: 'center',
                                        height: 32,
                                        opacity: p.pressed ? 0.7 : 1,
                                        gap: 6,
                                    })}
                                >
                                    <Octicons
                                        name="cpu"
                                        size={14}
                                        color={theme.colors.button.secondary.tint}
                                    />
                                    <Text style={{
                                        fontSize: 13,
                                        color: theme.colors.button.secondary.tint,
                                        fontWeight: '600',
                                        ...Typography.default('semiBold'),
                                    }}>
                                        {props.agentType === 'claude' ? t('agentInput.agent.claude') : props.agentType === 'codex' ? t('agentInput.agent.codex') : t('agentInput.agent.gemini')}
                                    </Text>
                                </Pressable>
                            )}

                            <GitStatusButton sessionId={props.sessionId} onPress={props.onFileViewerPress} />
                        </View>

                        {/* Send / Abort (stop) */}
                        <View
                            style={[
                                styles.sendButton,
                                ((props.onAbort && props.showAbortButton) || hasText || props.isSending)
                                    ? styles.sendButtonActive
                                    : styles.sendButtonInactive
                            ]}
                        >
                            <Shaker ref={shakerRef}>
                                <Pressable
                                    style={(p) => ({
                                        width: '100%',
                                        height: '100%',
                                        alignItems: 'center',
                                        justifyContent: 'center',
                                        opacity: p.pressed ? 0.7 : 1,
                                    })}
                                    hitSlop={{ top: 5, bottom: 10, left: 0, right: 0 }}
                                    onPress={() => {
                                        hapticsLight();
                                        if (props.onAbort && props.showAbortButton) {
                                            handleAbortPress();
                                            return;
                                        }
                                        if (hasText) {
                                            props.onSend();
                                        }
                                    }}
                                    disabled={
                                        props.isSendDisabled ||
                                        props.isSending ||
                                        isResolvingModel ||
                                        ((props.onAbort && props.showAbortButton) ? isAborting : !hasText)
                                    }
                                >
                                    {(props.isSending || isAborting) ? (
                                        <ActivityIndicator
                                            size="small"
                                            color={theme.colors.button.primary.tint}
                                        />
                                    ) : (props.onAbort && props.showAbortButton) ? (
                                        <Octicons
                                            name={"stop"}
                                            size={16}
                                            color={theme.colors.button.primary.tint}
                                        />
                                    ) : (
                                        props.sendIcon ?? (
                                            <Octicons
                                                name="arrow-up"
                                                size={16}
                                                color={theme.colors.button.primary.tint}
                                                style={[
                                                    styles.sendButtonIcon,
                                                    { marginTop: Platform.OS === 'web' ? 2 : 0 }
                                                ]}
                                            />
                                        )
                                    )}
                                </Pressable>
                            </Shaker>
                        </View>
                    </View>
                </View>
            </View>
        </View>
    );
}));

function GitStatusButton({ sessionId, onPress }: { sessionId?: string, onPress?: () => void }) {
    const hasMeaningfulGitStatus = useHasMeaningfulGitStatus(sessionId || '');
    const { theme } = useUnistyles();

    if (!sessionId || !onPress) return null;

    return (
        <Pressable
            style={(p) => ({
                flexDirection: 'row',
                alignItems: 'center',
                borderRadius: Platform.select({ default: 16, android: 20 }),
                paddingHorizontal: 8,
                paddingVertical: 6,
                height: 32,
                opacity: p.pressed ? 0.7 : 1,
                overflow: 'hidden',
            })}
            hitSlop={{ top: 5, bottom: 10, left: 0, right: 0 }}
            onPress={() => {
                hapticsLight();
                onPress?.();
            }}
        >
            {hasMeaningfulGitStatus ? (
                <GitStatusBadge sessionId={sessionId} />
            ) : (
                <Octicons
                    name="git-branch"
                    size={16}
                    color={theme.colors.button.secondary.tint}
                />
            )}
        </Pressable>
    );
}

function EffortBatteryIcon(props: { effort: ReasoningEffortMode | null; color: string }) {
    const filled =
        props.effort == null
            ? 0
            : props.effort === 'low'
                ? 1
                : props.effort === 'medium'
                    ? 2
                    : props.effort === 'high'
                        ? 3
                        : 4;
    const dim = (idx: number) => idx >= filled;
    const barStyle = (idx: number) => ({
        flex: 1,
        alignSelf: 'stretch' as const,
        borderRadius: 1,
        backgroundColor: dim(idx) ? 'transparent' : props.color,
        opacity: dim(idx) ? 0.18 : 1,
    });

    return (
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
            <View
                style={{
                    width: 20,
                    height: 12,
                    borderWidth: 1.5,
                    borderColor: props.color,
                    borderRadius: 3,
                    padding: 1.5,
                    flexDirection: 'row',
                    gap: 1,
                }}
            >
                <View style={barStyle(0)} />
                <View style={barStyle(1)} />
                <View style={barStyle(2)} />
                <View style={barStyle(3)} />
            </View>
            <View
                style={{
                    width: 2,
                    height: 6,
                    marginLeft: 1.5,
                    borderRadius: 1,
                    backgroundColor: props.color,
                    opacity: props.effort == null ? 0.25 : 1,
                }}
            />
        </View>
    );
}
