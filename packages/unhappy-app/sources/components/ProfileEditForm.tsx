import React from 'react';
import { Keyboard, View, Text, Pressable, ScrollView, TextInput, ViewStyle, Linking, Platform } from 'react-native';
import { Ionicons } from '@/icons/vector-icons';
import { StyleSheet } from 'react-native-unistyles';
import { useUnistyles } from 'react-native-unistyles';
import { Typography } from '@/constants/Typography';
import { t } from '@/text';
import { AIBackendProfile } from '@/sync/settings';
import { PermissionMode } from '@/components/PermissionModeSelector';
import { SessionTypeSelector } from '@/components/SessionTypeSelector';
import { ItemGroup } from '@/components/ItemGroup';
import { Item } from '@/components/Item';
import { getBuiltInProfileDocumentation } from '@/sync/profileUtils';
import { useEnvironmentVariables, extractEnvVarReferences } from '@/hooks/useEnvironmentVariables';
import { EnvironmentVariablesList } from '@/components/EnvironmentVariablesList';

export interface ProfileEditFormProps {
    profile: AIBackendProfile;
    machineId: string | null;
    onSave: (profile: AIBackendProfile) => void;
    onCancel: () => void;
    containerStyle?: ViewStyle;
}

export function ProfileEditForm({
    profile,
    machineId,
    onSave,
    onCancel,
    containerStyle
}: ProfileEditFormProps) {
    const { theme } = useUnistyles();

    // Get documentation for built-in profiles
    const profileDocs = React.useMemo(() => {
        if (!profile.isBuiltIn) return null;
        return getBuiltInProfileDocumentation(profile.id);
    }, [profile.isBuiltIn, profile.id]);

    // Local state for environment variables (unified for all config)
    const [environmentVariables, setEnvironmentVariables] = React.useState<Array<{ name: string; value: string }>>(
        profile.environmentVariables || []
    );

    // Extract ${VAR} references from environmentVariables for querying daemon
    const envVarNames = React.useMemo(() => {
        return extractEnvVarReferences(environmentVariables);
    }, [environmentVariables]);

    // Query daemon environment using hook
    const { variables: actualEnvVars } = useEnvironmentVariables(machineId, envVarNames);

    const [name, setName] = React.useState(profile.name || '');
    const [useTmux, setUseTmux] = React.useState(profile.tmuxConfig?.sessionName !== undefined);
    const [tmuxSession, setTmuxSession] = React.useState(profile.tmuxConfig?.sessionName || '');
    const [tmuxTmpDir, setTmuxTmpDir] = React.useState(profile.tmuxConfig?.tmpDir || '');
    const [useStartupScript, setUseStartupScript] = React.useState(!!profile.startupBashScript);
    const [startupScript, setStartupScript] = React.useState(profile.startupBashScript || '');
    const [defaultSessionType, setDefaultSessionType] = React.useState<'simple' | 'worktree'>(profile.defaultSessionType || 'simple');
    const [defaultPermissionMode, setDefaultPermissionMode] = React.useState<PermissionMode>((profile.defaultPermissionMode as PermissionMode) || 'default');
    const [agentType, setAgentType] = React.useState<'claude' | 'codex'>(() => {
        if (profile.compatibility.claude && !profile.compatibility.codex) return 'claude';
        if (profile.compatibility.codex && !profile.compatibility.claude) return 'codex';
        return 'claude'; // Default to Claude if both or neither
    });

    const handleSave = () => {
        if (!name.trim()) {
            // Profile name validation - prevent saving empty profiles
            return;
        }

        onSave({
            ...profile,
            name: name.trim(),
            // Clear all config objects - ALL configuration now in environmentVariables
            anthropicConfig: {},
            openaiConfig: {},
            azureOpenAIConfig: {},
            // Use environment variables from state (managed by EnvironmentVariablesList)
            environmentVariables,
            // Keep non-env-var configuration
            tmuxConfig: useTmux ? {
                sessionName: tmuxSession.trim() || '', // Empty string = use current/most recent tmux session
                tmpDir: tmuxTmpDir.trim() || undefined,
                updateEnvironment: undefined, // Preserve schema compatibility, not used by daemon
            } : {
                sessionName: undefined,
                tmpDir: undefined,
                updateEnvironment: undefined,
            },
            startupBashScript: useStartupScript ? (startupScript.trim() || undefined) : undefined,
            defaultSessionType: defaultSessionType,
            defaultPermissionMode: defaultPermissionMode,
            updatedAt: Date.now(),
        });
    };

    return (
        <ScrollView
            style={[profileEditFormStyles.scrollView, containerStyle]}
            contentContainerStyle={profileEditFormStyles.scrollContent}
            keyboardShouldPersistTaps="handled"
            keyboardDismissMode="on-drag"
        >
            <Pressable onPress={Keyboard.dismiss}>
                <View style={profileEditFormStyles.formContainer}>
                    {/* Profile Name */}
                    <Text style={{
                        fontSize: 14,
                        fontWeight: '600',
                        color: theme.colors.text,
                        marginBottom: 8,
                        ...Typography.default('semiBold')
                    }}>
                        {t('profiles.profileName')}
                    </Text>
                    <TextInput
                        style={{
                            backgroundColor: theme.colors.input.background,
                            borderRadius: 10, // Matches new session panel input fields
                            padding: 12,
                            fontSize: 16,
                            color: theme.colors.text,
                            marginBottom: 16,
                            borderWidth: 1,
                            borderColor: theme.colors.textSecondary,
                        }}
                        placeholder={t('profiles.enterName')}
                        value={name}
                        onChangeText={setName}
                    />

                    {/* Built-in Profile Documentation - Setup Instructions */}
                    {profile.isBuiltIn && profileDocs && (
                        <View style={{
                            backgroundColor: theme.colors.surface,
                            borderRadius: 12,
                            padding: 16,
                            marginBottom: 20,
                            borderWidth: 1,
                            borderColor: theme.colors.button.primary.background,
                        }}>
                            <View style={{ flexDirection: 'row', alignItems: 'center', marginBottom: 12 }}>
                                <Ionicons name="information-circle" size={20} color={theme.colors.button.primary.tint} style={{ marginRight: 8 }} />
                                <Text style={{
                                    fontSize: 15,
                                    fontWeight: '600',
                                    color: theme.colors.text,
                                    ...Typography.default('semiBold')
                                }}>
                                    설정 가이드
                                </Text>
                            </View>

                            <Text style={{
                                fontSize: 13,
                                color: theme.colors.text,
                                marginBottom: 12,
                                lineHeight: 18,
                                ...Typography.default()
                            }}>
                                {profileDocs.description}
                            </Text>

                            {profileDocs.setupGuideUrl && (
                                <Pressable
                                    onPress={async () => {
                                        try {
                                            const url = profileDocs.setupGuideUrl!;
                                            // On web/Tauri desktop, use window.open
                                            if (Platform.OS === 'web') {
                                                window.open(url, '_blank');
                                            } else {
                                                // On native (iOS/Android), use Linking API
                                                await Linking.openURL(url);
                                            }
                                        } catch (error) {
                                            console.error('Failed to open URL:', error);
                                        }
                                    }}
                                    style={{
                                        flexDirection: 'row',
                                        alignItems: 'center',
                                        backgroundColor: theme.colors.button.primary.background,
                                        borderRadius: 8,
                                        padding: 12,
                                        marginBottom: 16,
                                    }}
                                >
                                    <Ionicons name="book-outline" size={16} color={theme.colors.button.primary.tint} style={{ marginRight: 8 }} />
                                    <Text style={{
                                        fontSize: 13,
                                        color: theme.colors.button.primary.tint,
                                        fontWeight: '600',
                                        flex: 1,
                                        ...Typography.default('semiBold')
                                    }}>
                                        공식 설정 가이드 보기
                                    </Text>
                                    <Ionicons name="open-outline" size={14} color={theme.colors.button.primary.tint} />
                                </Pressable>
                            )}
                        </View>
                    )}

                    {/* Session Type */}
                    <Text style={{
                        fontSize: 14,
                        fontWeight: '600',
                        color: theme.colors.text,
                        marginBottom: 12,
                        ...Typography.default('semiBold')
                    }}>
                        기본 세션 유형
                    </Text>
                    <View style={{ marginBottom: 16 }}>
                        <SessionTypeSelector
                            value={defaultSessionType}
                            onChange={setDefaultSessionType}
                        />
                    </View>

                    {/* Permission Mode */}
                    <Text style={{
                        fontSize: 14,
                        fontWeight: '600',
                        color: theme.colors.text,
                        marginBottom: 12,
                        ...Typography.default('semiBold')
                    }}>
                        기본 권한 모드
                    </Text>
                    <ItemGroup title="">
                            {[
                            { value: 'default' as PermissionMode, label: '기본', description: '권한을 요청합니다', icon: 'shield-outline' },
                            { value: 'plan' as PermissionMode, label: '계획', description: '실행 전 계획', icon: 'list-outline' },
                            { value: 'allow-edits' as PermissionMode, label: '편집 허용', description: '편집 요청을 자동 승인', icon: 'create-outline' },
                            { value: 'read-only' as PermissionMode, label: '읽기 전용', description: '읽기만 가능합니다', icon: 'eye-outline' },
                            { value: 'bypass' as PermissionMode, label: '바이패스', description: '모든 권한 요청 건너뛰기', icon: 'flash-outline' },
                        ].map((option, index, array) => (
                            <Item
                                key={option.value}
                                title={option.label}
                                subtitle={option.description}
                                leftElement={
                                    <Ionicons
                                        name={option.icon as any}
                                        size={24}
                                        color={defaultPermissionMode === option.value ? theme.colors.button.primary.tint : theme.colors.textSecondary}
                                    />
                                }
                                rightElement={defaultPermissionMode === option.value ? (
                                    <Ionicons
                                        name="checkmark-circle"
                                        size={20}
                                        color={theme.colors.button.primary.tint}
                                    />
                                ) : null}
                                onPress={() => setDefaultPermissionMode(option.value)}
                                showChevron={false}
                                selected={defaultPermissionMode === option.value}
                                showDivider={index < array.length - 1}
                                style={defaultPermissionMode === option.value ? {
                                    borderWidth: 2,
                                    borderColor: theme.colors.button.primary.tint,
                                    borderRadius: 8,
                                } : undefined}
                            />
                        ))}
                    </ItemGroup>
                    <View style={{ marginBottom: 16 }} />

                    {/* Tmux Enable/Disable */}
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        marginBottom: 8,
                    }}>
                        <Pressable
                            style={{
                                flexDirection: 'row',
                                alignItems: 'center',
                                marginRight: 8,
                            }}
                            onPress={() => setUseTmux(!useTmux)}
                        >
                            <View style={{
                                width: 20,
                                height: 20,
                                borderRadius: 4,
                                borderWidth: 2,
                                borderColor: useTmux ? theme.colors.button.primary.background : theme.colors.textSecondary,
                                backgroundColor: useTmux ? theme.colors.button.primary.background : 'transparent',
                                justifyContent: 'center',
                                alignItems: 'center',
                                marginRight: 8,
                            }}>
                                {useTmux && (
                                    <Ionicons name="checkmark" size={12} color={theme.colors.button.primary.tint} />
                                )}
                            </View>
                        </Pressable>
                        <Text style={{
                            fontSize: 14,
                            fontWeight: '600',
                            color: theme.colors.text,
                            ...Typography.default('semiBold')
                        }}>
                            Tmux로 세션 시작
                        </Text>
                    </View>
                    <Text style={{
                        fontSize: 12,
                        color: theme.colors.textSecondary,
                        marginBottom: 12,
                        ...Typography.default()
                    }}>
                        {useTmux ? '세션은 새로운 tmux 창에서 시작됩니다. 아래에서 세션 이름과 임시 디렉토리를 설정하세요.' : 'tmux 없이 일반 셸에서 바로 시작됩니다'}
                    </Text>

                    {/* Tmux Session Name */}
                    <Text style={{
                        fontSize: 14,
                        fontWeight: '600',
                        color: theme.colors.text,
                        marginBottom: 8,
                        ...Typography.default('semiBold')
                    }}>
                        Tmux 세션 이름 ({t('common.optional')})
                    </Text>
                    <Text style={{
                        fontSize: 12,
                        color: theme.colors.textSecondary,
                        marginBottom: 8,
                        ...Typography.default()
                    }}>
                        비워두면 기존 tmux 세션 중 첫 번째를 사용합니다. (없으면 unhappy로 생성). 특정 세션을 쓰려면 이름을 입력하세요. (예: "my-work")
                    </Text>
                    <TextInput
                        style={{
                            backgroundColor: theme.colors.input.background,
                            borderRadius: 10, // Matches new session panel input fields
                            padding: 12,
                            fontSize: 16,
                            color: useTmux ? theme.colors.text : theme.colors.textSecondary,
                            marginBottom: 16,
                            borderWidth: 1,
                            borderColor: theme.colors.textSecondary,
                            opacity: useTmux ? 1 : 0.5,
                        }}
                        placeholder={useTmux ? '비워두면 첫 번째 기존 세션 사용' : '비활성 - tmux 미사용'}
                        value={tmuxSession}
                        onChangeText={setTmuxSession}
                        editable={useTmux}
                    />

                    {/* Tmux Temp Directory */}
                    <Text style={{
                        fontSize: 14,
                        fontWeight: '600',
                        color: theme.colors.text,
                        marginBottom: 8,
                        ...Typography.default('semiBold')
                    }}>
                        Tmux 임시 디렉토리 ({t('common.optional')})
                    </Text>
                    <Text style={{
                        fontSize: 12,
                        color: theme.colors.textSecondary,
                        marginBottom: 8,
                        ...Typography.default()
                    }}>
                        tmux 세션 파일이 저장되는 임시 디렉토리입니다. 비워두면 시스템 기본값을 사용합니다.
                    </Text>
                    <TextInput
                        style={{
                            backgroundColor: theme.colors.input.background,
                            borderRadius: 10, // Matches new session panel input fields
                            padding: 12,
                            fontSize: 16,
                            color: useTmux ? theme.colors.text : theme.colors.textSecondary,
                            marginBottom: 16,
                            borderWidth: 1,
                            borderColor: theme.colors.textSecondary,
                            opacity: useTmux ? 1 : 0.5,
                        }}
                        placeholder={useTmux ? '/tmp (선택)' : '비활성 - tmux 미사용'}
                        placeholderTextColor={theme.colors.input.placeholder}
                        value={tmuxTmpDir}
                        onChangeText={setTmuxTmpDir}
                        editable={useTmux}
                    />

                    {/* Startup Bash Script */}
                    <View style={{ marginBottom: 24 }}>
                        <View style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            marginBottom: 8,
                        }}>
                            <Pressable
                                style={{
                                    flexDirection: 'row',
                                    alignItems: 'center',
                                    marginRight: 8,
                                }}
                                onPress={() => setUseStartupScript(!useStartupScript)}
                            >
                                <View style={{
                                    width: 20,
                                    height: 20,
                                    borderRadius: 4,
                                    borderWidth: 2,
                                    borderColor: useStartupScript ? theme.colors.button.primary.background : theme.colors.textSecondary,
                                    backgroundColor: useStartupScript ? theme.colors.button.primary.background : 'transparent',
                                    justifyContent: 'center',
                                    alignItems: 'center',
                                    marginRight: 8,
                                }}>
                                    {useStartupScript && (
                                        <Ionicons name="checkmark" size={12} color={theme.colors.button.primary.tint} />
                                    )}
                                </View>
                            </Pressable>
                            <Text style={{
                                fontSize: 16,
                                fontWeight: '600',
                                color: theme.colors.text,
                                ...Typography.default('semiBold')
                            }}>
                                시작 스크립트
                            </Text>
                        </View>
                        <Text style={{
                            fontSize: 12,
                            color: theme.colors.textSecondary,
                            marginBottom: 12,
                            ...Typography.default()
                        }}>
                            {useStartupScript
                                ? '각 세션 시작 전 실행됩니다. 동적 설정, 환경 검사, 커스텀 초기화에 사용하세요.'
                                : '시작 스크립트 없음 - 세션을 바로 시작합니다'}
                        </Text>
                        <View style={{
                            flexDirection: 'row',
                            alignItems: 'flex-start',
                            gap: 8,
                            opacity: useStartupScript ? 1 : 0.5,
                        }}>
                            <TextInput
                                style={{
                                    flex: 1,
                                    backgroundColor: useStartupScript ? theme.colors.input.background : theme.colors.surface,
                                    borderRadius: 10, // Matches new session panel input fields
                                    padding: 12,
                                    fontSize: 14,
                                    color: useStartupScript ? theme.colors.text : theme.colors.textSecondary,
                                    borderWidth: 1,
                                    borderColor: theme.colors.textSecondary,
                                    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
                                    minHeight: 100,
                                }}
                                placeholder={useStartupScript ? "#!/bin/bash\necho '초기화 중...'\n# 스크립트를 입력하세요" : '비활성'}
                                value={startupScript}
                                onChangeText={setStartupScript}
                                editable={useStartupScript}
                                multiline
                                textAlignVertical="top"
                            />
                            {useStartupScript && startupScript.trim() && (
                                <Pressable
                                    style={{
                                        backgroundColor: theme.colors.button.primary.background,
                                        borderRadius: 6,
                                        padding: 10,
                                        justifyContent: 'center',
                                        alignItems: 'center',
                                    }}
                                    onPress={() => {
                                        if (Platform.OS === 'web') {
                                            navigator.clipboard.writeText(startupScript);
                                        }
                                    }}
                                >
                                    <Ionicons name="copy-outline" size={18} color={theme.colors.button.primary.tint} />
                                </Pressable>
                            )}
                        </View>
                    </View>

                    {/* Environment Variables Section - Unified configuration */}
                    <EnvironmentVariablesList
                        environmentVariables={environmentVariables}
                        machineId={machineId}
                        profileDocs={profileDocs}
                        onChange={setEnvironmentVariables}
                    />

                    {/* Action buttons */}
                    <View style={{ flexDirection: 'row', gap: 12 }}>
                        <Pressable
                            style={{
                                flex: 1,
                                backgroundColor: theme.colors.surface,
                                borderRadius: 8,
                                padding: 12,
                                alignItems: 'center',
                            }}
                            onPress={onCancel}
                        >
                            <Text style={{
                                fontSize: 16,
                                fontWeight: '600',
                                color: theme.colors.button.secondary.tint,
                                ...Typography.default('semiBold')
                            }}>
                                {t('common.cancel')}
                            </Text>
                        </Pressable>
                        {profile.isBuiltIn ? (
                            // For built-in profiles, show "Save As" button (creates custom copy)
                            <Pressable
                                style={{
                                    flex: 1,
                                    backgroundColor: theme.colors.button.primary.background,
                                    borderRadius: 8,
                                    padding: 12,
                                    alignItems: 'center',
                                }}
                                onPress={handleSave}
                            >
                                <Text style={{
                                    fontSize: 16,
                                    fontWeight: '600',
                                    color: theme.colors.button.primary.tint,
                                    ...Typography.default('semiBold')
                                }}>
                                    {t('common.saveAs')}
                                </Text>
                            </Pressable>
                        ) : (
                            // For custom profiles, show regular "Save" button
                            <Pressable
                                style={{
                                    flex: 1,
                                    backgroundColor: theme.colors.button.primary.background,
                                    borderRadius: 8,
                                    padding: 12,
                                    alignItems: 'center',
                                }}
                                onPress={handleSave}
                            >
                                <Text style={{
                                    fontSize: 16,
                                    fontWeight: '600',
                                    color: theme.colors.button.primary.tint,
                                    ...Typography.default('semiBold')
                                }}>
                                    {t('common.save')}
                                </Text>
                            </Pressable>
                        )}
                    </View>
                </View>
            </Pressable>
        </ScrollView>
    );
}

const profileEditFormStyles = StyleSheet.create((theme, rt) => ({
    scrollView: {
        flex: 1,
    },
    scrollContent: {
        padding: Platform.select({ web: 12, default: 20 }),
    },
    formContainer: {
        backgroundColor: theme.colors.surface,
        borderRadius: Platform.select({ web: theme.borderRadius.md, default: 16 }), // Matches new session panel main container
        padding: Platform.select({ web: 12, default: 20 }),
        width: '100%',
        ...(Platform.OS === 'web'
            ? {
                borderWidth: StyleSheet.hairlineWidth,
                borderColor: theme.colors.chrome.panelBorder,
            }
            : null),
    },
}));
