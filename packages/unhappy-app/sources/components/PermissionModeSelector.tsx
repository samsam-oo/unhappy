import React from 'react';
import { Text, Pressable, Platform } from 'react-native';
import { Ionicons } from '@/icons/vector-icons';
import { Typography } from '@/constants/Typography';
import { hapticsLight } from './haptics';
import { useUnistyles } from 'react-native-unistyles';
import { t, type TranslationKey } from '@/text';

export type PermissionMode = 'default' | 'acceptEdits' | 'bypassPermissions' | 'plan' | 'read-only' | 'safe-yolo' | 'yolo' | 'allow-edits' | 'bypass';

// Model is now treated as an external ID (returned by the CLI / server), not a closed set.
export type ModelMode = string;

interface PermissionModeSelectorProps {
    mode: PermissionMode;
    onModeChange: (mode: PermissionMode) => void;
    disabled?: boolean;
}

type PermissionModeIcon =
    | 'shield-checkmark'
    | 'create'
    | 'list'
    | 'flash'
    | 'eye'
    | 'shield'
    | 'rocket';

const modeConfig: Record<
    PermissionMode,
    { label: TranslationKey; icon: PermissionModeIcon; description: TranslationKey }
> = {
    default: {
        label: 'agentInput.permissionMode.default',
        icon: 'shield-checkmark' as const,
        description: 'agentInput.permissionMode.askEveryAction'
    },
    acceptEdits: {
        label: 'agentInput.permissionMode.acceptEdits',
        icon: 'create' as const,
        description: 'agentInput.permissionMode.autoApproveEdits'
    },
    'allow-edits': {
        label: 'agentInput.permissionMode.acceptEdits',
        icon: 'create' as const,
        description: 'agentInput.permissionMode.autoApproveEdits'
    },
    plan: {
        label: 'agentInput.permissionMode.plan',
        icon: 'list' as const,
        description: 'agentInput.permissionMode.planOnly'
    },
    bypassPermissions: {
        label: 'agentInput.permissionMode.bypassPermissions',
        icon: 'flash' as const,
        description: 'agentInput.permissionMode.autoApproveAll'
    },
    bypass: {
        label: 'agentInput.permissionMode.bypassPermissions',
        icon: 'flash' as const,
        description: 'agentInput.permissionMode.autoApproveAll'
    },
    // Codex modes (not displayed in this component, but needed for type compatibility)
    'read-only': {
        label: 'agentInput.codexPermissionMode.readOnly',
        icon: 'eye' as const,
        description: 'agentInput.permissionMode.readOnlyTools'
    },
    'safe-yolo': {
        label: 'agentInput.codexPermissionMode.safeYolo',
        icon: 'shield' as const,
        description: 'agentInput.codexPermissionMode.safeYolo'
    },
    'yolo': {
        label: 'agentInput.codexPermissionMode.yolo',
        icon: 'rocket' as const,
        description: 'agentInput.codexPermissionMode.yolo'
    },
};

const modeOrder: PermissionMode[] = ['default', 'plan', 'allow-edits', 'read-only', 'bypass'];

export const PermissionModeSelector: React.FC<PermissionModeSelectorProps> = ({
    mode,
    onModeChange,
    disabled = false
}) => {
    const { theme } = useUnistyles();
    const currentConfig = {
        ...modeConfig[mode],
        label: t(modeConfig[mode].label),
        description: t(modeConfig[mode].description),
    };

    const iconColor = (() => {
        switch (mode) {
            case 'acceptEdits':
            case 'allow-edits':
                return theme.colors.permission.acceptEdits;
            case 'plan':
                return theme.colors.permission.plan;
            case 'bypassPermissions':
            case 'bypass':
                return theme.colors.permission.bypass;
            case 'read-only':
                return theme.colors.permission.readOnly;
            case 'safe-yolo':
                return theme.colors.permission.safeYolo;
            case 'yolo':
                return theme.colors.permission.yolo;
            case 'default':
            default:
                return theme.colors.permission.default;
        }
    })();

    const handleTap = () => {
        hapticsLight();
        const currentIndex = modeOrder.indexOf(mode);
        const nextIndex = ((currentIndex >= 0 ? currentIndex : 0) + 1) % modeOrder.length;
        onModeChange(modeOrder[nextIndex]);
    };

    return (
        <Pressable
            onPress={handleTap}
            disabled={disabled}
            hitSlop={{ top: 5, bottom: 10, left: 0, right: 0 }}
            style={{
                flexDirection: 'row',
                alignItems: 'center',
                backgroundColor: theme.colors.surfaceHigh,
                borderWidth: 1,
                borderColor: theme.colors.divider,
                borderRadius: Platform.select({ default: 16, android: 20 }),
                paddingHorizontal: 12,
                paddingVertical: 6,
                width: 120,
                justifyContent: 'center',
                height: 32,
                opacity: disabled ? 0.5 : 1,
            }}
        >
            <Ionicons
                name={currentConfig.icon}
                size={16}
                color={iconColor}
                style={{ marginRight: 0 }}
            />
            {/* <Text style={{
                fontSize: 13,
                color: '#000',
                fontWeight: '600',
                ...Typography.default('semiBold')
            }}>
                {currentConfig.label}
            </Text> */}
        </Pressable>
    );
};
