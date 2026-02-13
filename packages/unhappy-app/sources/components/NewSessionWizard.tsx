import React, { useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, View, Text, Pressable, ScrollView, TextInput, Platform } from 'react-native';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { Typography } from '@/constants/Typography';
import { t } from '@/text';
import { Ionicons } from '@/icons/vector-icons';
import { SessionTypeSelector } from '@/components/SessionTypeSelector';
import { PermissionMode, ModelMode } from '@/components/PermissionModeSelector';
import { ItemGroup } from '@/components/ItemGroup';
import { Item } from '@/components/Item';
import { useAllMachines, useSetting, storage } from '@/sync/storage';
import { useRouter } from 'expo-router';
import { AIBackendProfile, validateProfileForAgent, getProfileEnvironmentVariables } from '@/sync/settings';
import { Modal } from '@/modal';
import { sync } from '@/sync/sync';
import { profileSyncService } from '@/sync/profileSync';
import { machineListDirectory } from '@/sync/ops';
import { normalizePermissionPolicy } from '@/sync/permissionPolicy';

const stylesheet = StyleSheet.create((theme) => ({
    container: {
        flex: 1,
    },
    header: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        paddingHorizontal: Platform.select({ web: 16, default: 24 }),
        paddingVertical: Platform.select({ web: 10, default: 16 }),
        borderBottomWidth: 1,
        borderBottomColor: theme.colors.divider,
    },
    headerTitle: {
        fontSize: Platform.select({ web: 15, default: 18 }),
        fontWeight: '600',
        color: theme.colors.text,
        ...Typography.default('semiBold'),
    },
    stepIndicator: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: Platform.select({ web: 16, default: 24 }),
        paddingVertical: Platform.select({ web: 10, default: 16 }),
        borderBottomWidth: 1,
        borderBottomColor: theme.colors.divider,
    },
    stepDot: {
        width: 8,
        height: 8,
        borderRadius: 4,
        marginHorizontal: 4,
    },
    stepDotActive: {
        backgroundColor: theme.colors.button.primary.background,
    },
    stepDotInactive: {
        backgroundColor: theme.colors.divider,
    },
    stepContent: {
        flex: 1,
        paddingHorizontal: Platform.select({ web: 16, default: 24 }),
        paddingTop: Platform.select({ web: 16, default: 24 }),
        paddingBottom: 0, // No bottom padding since footer is separate
    },
    stepTitle: {
        fontSize: Platform.select({ web: 16, default: 20 }),
        fontWeight: '600',
        color: theme.colors.text,
        marginBottom: 8,
        ...Typography.default('semiBold'),
    },
    stepDescription: {
        fontSize: Platform.select({ web: 13, default: 16 }),
        color: theme.colors.textSecondary,
        marginBottom: Platform.select({ web: 16, default: 24 }),
        ...Typography.default(),
    },
    footer: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        paddingHorizontal: Platform.select({ web: 16, default: 24 }),
        paddingVertical: Platform.select({ web: 10, default: 16 }),
        borderTopWidth: 1,
        borderTopColor: theme.colors.divider,
        backgroundColor: theme.colors.surface, // Ensure footer has solid background
    },
    button: {
        paddingHorizontal: 16,
        paddingVertical: Platform.select({ web: 10, default: 12 }),
        borderRadius: 8,
        minWidth: 100,
        alignItems: 'center',
        justifyContent: 'center',
    },
    buttonPrimary: {
        backgroundColor: theme.colors.button.primary.background,
    },
    buttonSecondary: {
        backgroundColor: 'transparent',
        borderWidth: 1,
        borderColor: theme.colors.divider,
    },
    buttonText: {
        fontSize: 16,
        fontWeight: '600',
        ...Typography.default('semiBold'),
    },
    buttonTextPrimary: {
        color: '#FFFFFF',
    },
    buttonTextSecondary: {
        color: theme.colors.text,
    },
    textInput: {
        backgroundColor: theme.colors.input.background,
        borderRadius: 8,
        paddingHorizontal: 12,
        paddingVertical: 10,
        fontSize: 16,
        color: theme.colors.text,
        borderWidth: 1,
        borderColor: theme.colors.divider,
        ...Typography.default(),
    },
    agentOption: {
        flexDirection: 'row',
        alignItems: 'center',
        padding: Platform.select({ web: 12, default: 16 }),
        borderRadius: 12,
        borderWidth: 2,
        marginBottom: 12,
    },
    agentOptionSelected: {
        borderColor: theme.colors.button.primary.background,
        backgroundColor: theme.colors.input.background,
    },
    agentOptionUnselected: {
        borderColor: theme.colors.divider,
        backgroundColor: theme.colors.input.background,
    },
    agentIcon: {
        width: 40,
        height: 40,
        borderRadius: 20,
        backgroundColor: theme.colors.button.primary.background,
        alignItems: 'center',
        justifyContent: 'center',
        marginRight: 16,
    },
    agentInfo: {
        flex: 1,
    },
    agentName: {
        fontSize: 16,
        fontWeight: '600',
        color: theme.colors.text,
        ...Typography.default('semiBold'),
    },
    agentDescription: {
        fontSize: 14,
        color: theme.colors.textSecondary,
        marginTop: 4,
        ...Typography.default(),
    },
}));

type RemoteDirectoryEntry = {
    name: string;
    type: 'file' | 'directory' | 'other';
    size?: number;
    modified?: number;
};

function normalizeRemotePath(path: string): string {
    const trimmed = (path || '').trim();
    if (!trimmed) return '/';
    if (trimmed === '/') return '/';
    // Remove trailing slashes (except root)
    return trimmed.replace(/\/+$/, '');
}

function joinRemotePath(base: string, childName: string): string {
    const b = normalizeRemotePath(base);
    const c = (childName || '').replace(/^\/+/, '').replace(/\/+$/, '');
    if (!c) return b;
    return b === '/' ? `/${c}` : `${b}/${c}`;
}

function parentRemotePath(path: string): string {
    const p = normalizeRemotePath(path);
    if (p === '/') return '/';
    const idx = p.lastIndexOf('/');
    if (idx <= 0) return '/';
    return p.slice(0, idx);
}

function remotePathRelativeToRoot(path: string, root: string): string {
    const p = normalizeRemotePath(path);
    const r = normalizeRemotePath(root);
    if (!r) return p;
    if (p === r) return '.';
    const prefix = r === '/' ? '/' : `${r}/`;
    if (p.startsWith(prefix)) return p.slice(prefix.length);
    return p;
}

type WizardStep = 'profile' | 'profileConfig' | 'sessionType' | 'agent' | 'options' | 'machine' | 'path' | 'prompt';

// Profile selection item component with management actions
interface ProfileSelectionItemProps {
    profile: AIBackendProfile;
    isSelected: boolean;
    onSelect: () => void;
    onUseAsIs: () => void;
    onEdit: () => void;
    onDuplicate?: () => void;
    onDelete?: () => void;
    showManagementActions?: boolean;
}

function ProfileSelectionItem({ profile, isSelected, onSelect, onUseAsIs, onEdit, onDuplicate, onDelete, showManagementActions = false }: ProfileSelectionItemProps) {
    const { theme } = useUnistyles();
    const styles = stylesheet;

    return (
        <View style={{
            backgroundColor: isSelected ? theme.colors.input.background : 'transparent',
            borderRadius: 12,
            borderWidth: isSelected ? 2 : 1,
            borderColor: isSelected ? theme.colors.button.primary.background : theme.colors.divider,
            marginBottom: 12,
            padding: 4,
        }}>
            {/* Profile Header */}
            <Pressable onPress={onSelect} style={{ padding: 12 }}>
                <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                    <View style={{
                        width: 40,
                        height: 40,
                        borderRadius: 20,
                        backgroundColor: theme.colors.button.primary.background,
                        alignItems: 'center',
                        justifyContent: 'center',
                        marginRight: 12,
                    }}>
                        <Ionicons
                            // "Profile" here means backend preset, not a user profile.
                            name="layers-outline"
                            size={20}
                            color="white"
                        />
                    </View>
                    <View style={{ flex: 1 }}>
                        <Text style={{
                            fontSize: 16,
                            fontWeight: '600',
                            color: theme.colors.text,
                            marginBottom: 4,
                            ...Typography.default('semiBold'),
                        }}>
                            {profile.name}
                        </Text>
                        <Text style={{
                            fontSize: 14,
                            color: theme.colors.textSecondary,
                            ...Typography.default(),
                        }}>
                            {profile.description}
                        </Text>
                        {profile.isBuiltIn && (
                            <Text style={{
                                fontSize: 12,
                                color: theme.colors.textSecondary,
                                marginTop: 2,
                            }}>
                                기본 프리셋
                            </Text>
                        )}
                    </View>
                    {isSelected && (
                        <Ionicons
                            name="checkmark-circle"
                            size={20}
                            color={theme.colors.button.primary.background}
                        />
                    )}
                </View>
            </Pressable>

            {/* Action Buttons - Only show when selected */}
            {isSelected && (
                <View style={{
                    flexDirection: 'column',
                    paddingHorizontal: 12,
                    paddingBottom: 12,
                    gap: 8,
                }}>
                    {/* Primary Actions */}
                    <View style={{
                        flexDirection: 'row',
                        gap: 8,
                    }}>
                        <Pressable
                            style={{
                                flex: 1,
                                flexDirection: 'row',
                                alignItems: 'center',
                                justifyContent: 'center',
                                paddingVertical: 8,
                                paddingHorizontal: 12,
                                borderRadius: 8,
                                backgroundColor: theme.colors.button.primary.background,
                            }}
                            onPress={onUseAsIs}
                        >
                            <Ionicons name="checkmark" size={16} color="white" />
                            <Text style={{
                                color: 'white',
                                fontSize: 14,
                                fontWeight: '600',
                                marginLeft: 6,
                                ...Typography.default('semiBold'),
                            }}>
                                그대로 사용
                            </Text>
                        </Pressable>

                        <Pressable
                            style={{
                                flex: 1,
                                flexDirection: 'row',
                                alignItems: 'center',
                                justifyContent: 'center',
                                paddingVertical: 8,
                                paddingHorizontal: 12,
                                borderRadius: 8,
                                backgroundColor: 'transparent',
                                borderWidth: 1,
                                borderColor: theme.colors.divider,
                            }}
                            onPress={onEdit}
                        >
                            <Ionicons name="create-outline" size={16} color={theme.colors.text} />
                            <Text style={{
                                color: theme.colors.text,
                                fontSize: 14,
                                fontWeight: '600',
                                marginLeft: 6,
                                ...Typography.default('semiBold'),
                            }}>
                                편집
                            </Text>
                        </Pressable>
                    </View>

                    {/* Management Actions - Only show for custom profiles */}
                    {showManagementActions && !profile.isBuiltIn && (
                        <View style={{
                            flexDirection: 'row',
                            gap: 8,
                        }}>
                            <Pressable
                                style={{
                                    flex: 1,
                                    flexDirection: 'row',
                                    alignItems: 'center',
                                    justifyContent: 'center',
                                    paddingVertical: 6,
                                    paddingHorizontal: 8,
                                    borderRadius: 6,
                                    backgroundColor: 'transparent',
                                    borderWidth: 1,
                                    borderColor: theme.colors.divider,
                                }}
                                onPress={onDuplicate}
                            >
                                <Ionicons name="copy-outline" size={14} color={theme.colors.textSecondary} />
                                <Text style={{
                                    color: theme.colors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: '600',
                                    marginLeft: 4,
                                    ...Typography.default('semiBold'),
                            }}>
                                복제
                            </Text>
                            </Pressable>

                            <Pressable
                                style={{
                                    flex: 1,
                                    flexDirection: 'row',
                                    alignItems: 'center',
                                    justifyContent: 'center',
                                    paddingVertical: 6,
                                    paddingHorizontal: 8,
                                    borderRadius: 6,
                                    backgroundColor: 'transparent',
                                    borderWidth: 1,
                                    borderColor: theme.colors.textDestructive,
                                }}
                                onPress={onDelete}
                            >
                                <Ionicons name="trash-outline" size={14} color={theme.colors.textDestructive} />
                                <Text style={{
                                    color: theme.colors.textDestructive,
                                    fontSize: 12,
                                    fontWeight: '600',
                                    marginLeft: 4,
                                    ...Typography.default('semiBold'),
                            }}>
                                삭제
                            </Text>
                            </Pressable>
                        </View>
                    )}
                </View>
            )}
        </View>
    );
}

// Manual configuration item component
interface ManualConfigurationItemProps {
    isSelected: boolean;
    onSelect: () => void;
    onUseCliVars: () => void;
    onConfigureManually: () => void;
}

function ManualConfigurationItem({ isSelected, onSelect, onUseCliVars, onConfigureManually }: ManualConfigurationItemProps) {
    const { theme } = useUnistyles();
    const styles = stylesheet;

    return (
        <View style={{
            backgroundColor: isSelected ? theme.colors.input.background : 'transparent',
            borderRadius: 12,
            borderWidth: isSelected ? 2 : 1,
            borderColor: isSelected ? theme.colors.button.primary.background : theme.colors.divider,
            marginBottom: 12,
            padding: 4,
        }}>
            {/* Profile Header */}
            <Pressable onPress={onSelect} style={{ padding: 12 }}>
                <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                    <View style={{
                        width: 40,
                        height: 40,
                        borderRadius: 20,
                        backgroundColor: theme.colors.textSecondary,
                        alignItems: 'center',
                        justifyContent: 'center',
                        marginRight: 12,
                    }}>
                        <Ionicons
                            name="settings"
                            size={20}
                            color="white"
                        />
                    </View>
                    <View style={{ flex: 1 }}>
                        <Text style={{
                            fontSize: 16,
                            fontWeight: '600',
                            color: theme.colors.text,
                            marginBottom: 4,
                            ...Typography.default('semiBold'),
                        }}>
                            수동 설정
                        </Text>
                        <Text style={{
                            fontSize: 14,
                            color: theme.colors.textSecondary,
                            ...Typography.default(),
                        }}>
                            CLI 환경변수를 사용하거나 수동으로 설정하세요
                        </Text>
                    </View>
                    {isSelected && (
                        <Ionicons
                            name="checkmark-circle"
                            size={20}
                            color={theme.colors.button.primary.background}
                        />
                    )}
                </View>
            </Pressable>

            {/* Action Buttons - Only show when selected */}
            {isSelected && (
                <View style={{
                    flexDirection: 'row',
                    paddingHorizontal: 12,
                    paddingBottom: 12,
                    gap: 8,
                }}>
                    <Pressable
                        style={{
                            flex: 1,
                            flexDirection: 'row',
                            alignItems: 'center',
                            justifyContent: 'center',
                            paddingVertical: 8,
                            paddingHorizontal: 12,
                            borderRadius: 8,
                            backgroundColor: theme.colors.button.primary.background,
                        }}
                        onPress={onUseCliVars}
                    >
                        <Ionicons name="terminal-outline" size={16} color="white" />
                        <Text style={{
                            color: 'white',
                            fontSize: 14,
                            fontWeight: '600',
                            marginLeft: 6,
                            ...Typography.default('semiBold'),
                        }}>
                            CLI 변수 사용
                        </Text>
                    </Pressable>

                    <Pressable
                        style={{
                            flex: 1,
                            flexDirection: 'row',
                            alignItems: 'center',
                            justifyContent: 'center',
                            paddingVertical: 8,
                            paddingHorizontal: 12,
                            borderRadius: 8,
                            backgroundColor: 'transparent',
                            borderWidth: 1,
                            borderColor: theme.colors.divider,
                        }}
                        onPress={onConfigureManually}
                    >
                        <Ionicons name="create-outline" size={16} color={theme.colors.text} />
                        <Text style={{
                            color: theme.colors.text,
                            fontSize: 14,
                            fontWeight: '600',
                            marginLeft: 6,
                            ...Typography.default('semiBold'),
                        }}>
                            설정
                        </Text>
                    </Pressable>
                </View>
            )}
        </View>
    );
}

interface NewSessionWizardProps {
    onComplete: (config: {
        sessionType: 'simple' | 'worktree';
        profileId: string | null;
        agentType: 'claude' | 'codex';
        permissionMode: PermissionMode;
        planOnly: boolean;
        modelMode: ModelMode;
        machineId: string;
        path: string;
        prompt: string;
        environmentVariables?: Record<string, string>;
    }) => void;
    onCancel: () => void;
    initialPrompt?: string;
}

export function NewSessionWizard({ onComplete, onCancel, initialPrompt = '' }: NewSessionWizardProps) {
    const { theme } = useUnistyles();
    const styles = stylesheet;
    const router = useRouter();
    const machines = useAllMachines();
    const experimentsEnabled = useSetting('experiments');
    const recentMachinePaths = useSetting('recentMachinePaths');
    const lastUsedAgent = useSetting('lastUsedAgent');
    const lastUsedPermissionMode = useSetting('lastUsedPermissionMode');
    const lastUsedPlanOnly = useSetting('lastUsedPlanOnly');
    const lastUsedModelMode = useSetting('lastUsedModelMode');
    const profiles = useSetting('profiles');
    const lastUsedProfile = useSetting('lastUsedProfile');

    const resolvedInitialAgentType: 'claude' | 'codex' =
        lastUsedAgent === 'claude' || lastUsedAgent === 'codex'
            ? lastUsedAgent
            : 'claude';

    const resolvedInitialPermissionPolicy = (() => {
        const raw = typeof lastUsedPermissionMode === 'string' ? lastUsedPermissionMode.trim() : '';
        return normalizePermissionPolicy({
            permissionMode: raw ? (raw as PermissionMode) : undefined,
            planOnly: lastUsedPlanOnly,
        });
    })();

    const resolvedInitialModelMode: ModelMode = (() => {
        const raw = typeof lastUsedModelMode === 'string' ? lastUsedModelMode.trim() : '';
        if (!raw) return 'default';
        // Only apply the last-used model when it matches the initial agent selection.
        if (lastUsedAgent !== resolvedInitialAgentType) return 'default';
        return raw;
    })();

    // Wizard state
    const [currentStep, setCurrentStep] = useState<WizardStep>('profile');
    const [sessionType, setSessionType] = useState<'simple' | 'worktree'>('simple');
    const [agentType, setAgentType] = useState<'claude' | 'codex'>(resolvedInitialAgentType);
    const [permissionMode, setPermissionMode] = useState<PermissionMode>(resolvedInitialPermissionPolicy.permissionMode);
    const [planOnly, setPlanOnly] = useState<boolean>(resolvedInitialPermissionPolicy.planOnly);
    const [modelMode, setModelMode] = useState<ModelMode>(resolvedInitialModelMode);
    const modelTouchedRef = useRef(false);
    const [selectedProfileId, setSelectedProfileId] = useState<string | null>(() => {
        return lastUsedProfile;
    });

    // Built-in profiles
    const builtInProfiles: AIBackendProfile[] = useMemo(() => [
        {
            id: 'anthropic',
            name: 'Anthropic (Claude API)',
            description: 'Anthropic Claude 직접 연동 백엔드(ANTHROPIC_* 환경변수 사용)',
            anthropicConfig: {},
            environmentVariables: [],
            compatibility: { claude: true, codex: false, gemini: false },
            isBuiltIn: true,
            createdAt: Date.now(),
            updatedAt: Date.now(),
            version: '1.0.0',
        },
        {
            id: 'deepseek',
            name: 'DeepSeek (Reasoner)',
            description: 'Anthropic API 프록시를 사용하는 DeepSeek 추론 모델',
            anthropicConfig: {
                baseUrl: 'https://api.deepseek.com/anthropic',
                model: 'deepseek-reasoner',
            },
            environmentVariables: [
                { name: 'API_TIMEOUT_MS', value: '600000' },
                { name: 'ANTHROPIC_SMALL_FAST_MODEL', value: 'deepseek-chat' },
                { name: 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC', value: '1' },
            ],
            compatibility: { claude: true, codex: false, gemini: false },
            isBuiltIn: true,
            createdAt: Date.now(),
            updatedAt: Date.now(),
            version: '1.0.0',
        },
        {
            id: 'openai',
            name: 'OpenAI (GPT-4/Codex)',
            description: 'OpenAI GPT-4 / Codex 모델',
            openaiConfig: {
                baseUrl: 'https://api.openai.com/v1',
                model: 'gpt-4-turbo',
            },
            environmentVariables: [],
            compatibility: { claude: false, codex: true, gemini: false },
            isBuiltIn: true,
            createdAt: Date.now(),
            updatedAt: Date.now(),
            version: '1.0.0',
        },
        {
            id: 'azure-openai-codex',
            name: 'Azure OpenAI (Codex)',
            description: 'Codex 에이전트용 Microsoft Azure OpenAI',
            azureOpenAIConfig: {
                endpoint: 'https://your-resource.openai.azure.com/',
                apiVersion: '2024-02-15-preview',
                deploymentName: 'gpt-4-turbo',
            },
            environmentVariables: [],
            compatibility: { claude: false, codex: true, gemini: false },
            isBuiltIn: true,
            createdAt: Date.now(),
            updatedAt: Date.now(),
            version: '1.0.0',
        },
        {
            id: 'azure-openai',
            name: 'Azure OpenAI',
            description: 'Microsoft Azure OpenAI 구성',
            azureOpenAIConfig: {
                apiVersion: '2024-02-15-preview',
            },
            environmentVariables: [
                { name: 'AZURE_OPENAI_API_VERSION', value: '2024-02-15-preview' },
            ],
            compatibility: { claude: false, codex: true, gemini: false },
            isBuiltIn: true,
            createdAt: Date.now(),
            updatedAt: Date.now(),
            version: '1.0.0',
        },
        {
            id: 'zai',
            name: 'Z.ai (GLM-4.6)',
            description: 'Anthropic API 프록시를 사용하는 Z.ai GLM-4.6 모델',
            anthropicConfig: {
                baseUrl: 'https://api.z.ai/api/anthropic',
                model: 'glm-4.6',
            },
            environmentVariables: [],
            compatibility: { claude: true, codex: false, gemini: false },
            isBuiltIn: true,
            createdAt: Date.now(),
            updatedAt: Date.now(),
            version: '1.0.0',
        },
        {
            id: 'microsoft',
            name: 'Microsoft Azure',
            description: 'Microsoft Azure AI 서비스',
            openaiConfig: {
                baseUrl: 'https://api.openai.azure.com',
                model: 'gpt-4-turbo',
            },
            environmentVariables: [],
            compatibility: { claude: false, codex: true, gemini: false },
            isBuiltIn: true,
            createdAt: Date.now(),
            updatedAt: Date.now(),
            version: '1.0.0',
        },
    ], []);

    // Combined profiles
    const allProfiles = useMemo(() => {
        return [...builtInProfiles, ...profiles];
    }, [profiles, builtInProfiles]);

    const [selectedMachineId, setSelectedMachineId] = useState<string>(() => {
        if (machines.length > 0) {
            // Check if we have a recently used machine that's currently available
            if (recentMachinePaths.length > 0) {
                for (const recent of recentMachinePaths) {
                    if (machines.find(m => m.id === recent.machineId)) {
                        return recent.machineId;
                    }
                }
            }
            return machines[0].id;
        }
        return '';
    });
    const [selectedPath, setSelectedPath] = useState<string>(() => {
        if (machines.length > 0 && selectedMachineId) {
            const machine = machines.find(m => m.id === selectedMachineId);
            return machine?.metadata?.homeDir || '/home';
        }
        return '/home';
    });
    const selectedMachine = useMemo(() => {
        return machines.find(m => m.id === selectedMachineId);
    }, [machines, selectedMachineId]);
    const selectedMachineHomeDir = useMemo(() => {
        return selectedMachine?.metadata?.homeDir || '/home';
    }, [selectedMachine?.metadata?.homeDir]);
    const selectedMachineIsOnline = selectedMachine?.active === true;

    // Remote "file explorer" state (directory picker for the selected machine)
    const [browseRoot, setBrowseRoot] = useState<string>('');
    const [browsePath, setBrowsePath] = useState<string>(() => {
        if (machines.length > 0 && selectedMachineId) {
            const machine = machines.find(m => m.id === selectedMachineId);
            return machine?.metadata?.homeDir || '/home';
        }
        return '/home';
    });
    const [browseEntries, setBrowseEntries] = useState<RemoteDirectoryEntry[]>([]);
    const [browseError, setBrowseError] = useState<string | null>(null);
    const [isBrowsing, setIsBrowsing] = useState(false);
    const [browseReloadToken, setBrowseReloadToken] = useState(0);
    const lastBrowseInitKeyRef = useRef<string | null>(null);
    const [prompt, setPrompt] = useState<string>(initialPrompt);
    const [customPath, setCustomPath] = useState<string>('');
    const [showCustomPathInput, setShowCustomPathInput] = useState<boolean>(false);

    // Profile configuration state
    const [profileApiKeys, setProfileApiKeys] = useState<Record<string, Record<string, string>>>({});
    const [profileConfigs, setProfileConfigs] = useState<Record<string, Record<string, string>>>({});

    // Dynamic steps based on whether profile needs configuration
    const steps: WizardStep[] = React.useMemo(() => {
        const baseSteps: WizardStep[] = ['profile', 'sessionType', 'agent', 'options', 'machine', 'path', 'prompt'];

        // Insert profileConfig step after profile if needed
        if (profileNeedsConfiguration(selectedProfileId)) {
            const profileIndex = baseSteps.indexOf('profile');
            const beforeProfile = baseSteps.slice(0, profileIndex + 1) as WizardStep[];
            const afterProfile = baseSteps.slice(profileIndex + 1) as WizardStep[];
            return [
                ...beforeProfile,
                'profileConfig',
                ...afterProfile
            ] as WizardStep[];
        }

        return baseSteps;
    }, [selectedProfileId, allProfiles]);

    // Helper function to check if profile needs API keys
    function profileNeedsConfiguration(profileId: string | null): boolean {
        if (!profileId) return false; // Manual configuration doesn't need API keys
        const profile = allProfiles.find(p => p.id === profileId);
        if (!profile) return false;

        // Check if profile is one that requires API keys
        const profilesNeedingKeys = ['openai', 'azure-openai', 'azure-openai-codex', 'zai', 'microsoft', 'deepseek'];
        return profilesNeedingKeys.includes(profile.id);
    }

    // Get required fields for profile configuration
    const getProfileRequiredFields = (profileId: string | null): Array<{key: string, label: string, placeholder: string, isPassword?: boolean}> => {
        if (!profileId) return [];
        const profile = allProfiles.find(p => p.id === profileId);
        if (!profile) return [];

        switch (profile.id) {
            case 'deepseek':
                return [
                    { key: 'ANTHROPIC_AUTH_TOKEN', label: 'DeepSeek API 키', placeholder: 'DEEPSEEK_API_KEY', isPassword: true }
                ];
            case 'openai':
                return [
                    { key: 'OPENAI_API_KEY', label: 'OpenAI API 키', placeholder: 'sk-...', isPassword: true }
                ];
            case 'azure-openai':
                return [
                    { key: 'AZURE_OPENAI_API_KEY', label: 'Azure OpenAI API 키', placeholder: 'Azure OpenAI API 키를 입력하세요', isPassword: true },
                    { key: 'AZURE_OPENAI_ENDPOINT', label: 'Azure 엔드포인트', placeholder: 'https://your-resource.openai.azure.com/' },
                    { key: 'AZURE_OPENAI_DEPLOYMENT_NAME', label: '배포 이름', placeholder: 'gpt-4-turbo' }
                ];
            case 'zai':
                return [
                    { key: 'ANTHROPIC_AUTH_TOKEN', label: 'Z.ai API 키', placeholder: 'Z_AI_API_KEY', isPassword: true }
                ];
            case 'microsoft':
                return [
                    { key: 'AZURE_OPENAI_API_KEY', label: 'Azure API 키', placeholder: 'Azure API 키를 입력하세요', isPassword: true },
                    { key: 'AZURE_OPENAI_ENDPOINT', label: 'Azure 엔드포인트', placeholder: 'https://your-resource.openai.azure.com/' },
                    { key: 'AZURE_OPENAI_DEPLOYMENT_NAME', label: '배포 이름', placeholder: 'gpt-4-turbo' }
                ];
            case 'azure-openai-codex':
                return [
                    { key: 'AZURE_OPENAI_API_KEY', label: 'Azure OpenAI API 키', placeholder: 'Azure OpenAI API 키를 입력하세요', isPassword: true },
                    { key: 'AZURE_OPENAI_ENDPOINT', label: 'Azure 엔드포인트', placeholder: 'https://your-resource.openai.azure.com/' },
                    { key: 'AZURE_OPENAI_DEPLOYMENT_NAME', label: '배포 이름', placeholder: 'gpt-4-turbo' }
                ];
            default:
                return [];
        }
    };

    // If we ever land on `profileConfig` when no config is required (e.g. profiles changed),
    // advance after render instead of setting state during render.
    useEffect(() => {
        if (currentStep !== 'profileConfig') return;
        if (!selectedProfileId || !profileNeedsConfiguration(selectedProfileId)) {
            const profileIdx = steps.indexOf('profile');
            const next = profileIdx >= 0 ? steps[profileIdx + 1] : steps[0];
            if (next && next !== currentStep) setCurrentStep(next);
        }
    }, [currentStep, selectedProfileId, steps]);

    // Auto-load profile settings and sync with CLI
    React.useEffect(() => {
        if (selectedProfileId) {
            const selectedProfile = allProfiles.find(p => p.id === selectedProfileId);
            if (selectedProfile) {
                // Auto-select agent type based on profile compatibility
                if (selectedProfile.compatibility.claude && !selectedProfile.compatibility.codex) {
                    setAgentType('claude');
                } else if (selectedProfile.compatibility.codex && !selectedProfile.compatibility.claude) {
                    setAgentType('codex');
                }

                // Sync active profile to CLI
                profileSyncService.setActiveProfile(selectedProfileId).catch(error => {
                    console.error('[Wizard] Failed to sync active profile to CLI:', error);
                });
            }
        }
    }, [selectedProfileId, allProfiles]);

    // Sync profiles with CLI on component mount and when profiles change
    React.useEffect(() => {
        const syncProfiles = async () => {
            try {
                await profileSyncService.bidirectionalSync(allProfiles);
            } catch (error) {
                console.error('[Wizard] Failed to sync profiles with CLI:', error);
                // Continue without sync - profiles work locally
            }
        };

        // Sync on mount
        syncProfiles();

        // Set up sync listener for profile changes
        const handleSyncEvent = (event: any) => {
            if (event.status === 'error') {
                console.warn('[Wizard] Profile sync error:', event.error);
            }
        };

        profileSyncService.addEventListener(handleSyncEvent);

        return () => {
            profileSyncService.removeEventListener(handleSyncEvent);
        };
    }, [allProfiles]);

    // Keep the file explorer in sync with the selected machine.
    useEffect(() => {
        if (!selectedMachineId) {
            lastBrowseInitKeyRef.current = null;
            return;
        }
        const homeDir = selectedMachineHomeDir;
        const initKey = `${selectedMachineId}|${homeDir}`;
        if (lastBrowseInitKeyRef.current === initKey) return;
        lastBrowseInitKeyRef.current = initKey;
        setBrowsePath(homeDir);
        setBrowseRoot(homeDir);
        setBrowseEntries([]);
        setBrowseError(null);
        // Force reload (helps when the machine selection changes).
        setBrowseReloadToken(x => x + 1);
    }, [selectedMachineId, selectedMachineHomeDir]);

    useEffect(() => {
        if (currentStep !== 'path') return;
        if (!selectedMachineId) return;

        if (!selectedMachineIsOnline) {
            setBrowseEntries([]);
            setBrowseError('머신이 오프라인 상태입니다');
            setIsBrowsing(false);
            return;
        }

        let cancelled = false;
        const run = async () => {
            setIsBrowsing(true);
            setBrowseError(null);

            const root = normalizeRemotePath(browseRoot || '/');
            const target = normalizeRemotePath(browsePath || root || '/');

            let response = await machineListDirectory(selectedMachineId, target, {
                // We only display folder names here; avoid per-entry `stat`.
                includeStats: false,
                types: ['directory'],
                sort: true,
                maxEntries: 2000,
            });
            if (cancelled) return;

            if (!response.success && root && normalizeRemotePath(target) !== normalizeRemotePath(root)) {
                const fallback = normalizeRemotePath(root);
                setBrowsePath(fallback);
                response = await machineListDirectory(selectedMachineId, fallback, {
                    includeStats: false,
                    types: ['directory'],
                    sort: true,
                    maxEntries: 2000,
                });
                if (cancelled) return;
            }

            if (!response.success) {
                setBrowseEntries([]);
                setBrowseError(response.error || '디렉토리 목록을 불러오지 못했습니다');
                return;
            }

            const directories = (response.entries || [])
                .filter((e): e is RemoteDirectoryEntry => !!e && e.type === 'directory' && typeof e.name === 'string')
                .filter(e => e.name !== '.' && e.name !== '..');

            setBrowseEntries(directories);
            setBrowseError(null);
        };

        run().finally(() => {
            if (!cancelled) setIsBrowsing(false);
        });

        return () => {
            cancelled = true;
        };
    }, [currentStep, selectedMachineId, selectedMachineIsOnline, browsePath, browseRoot, browseReloadToken]);

    const currentStepIndex = steps.indexOf(currentStep);
    const isFirstStep = currentStepIndex === 0;
    const isLastStep = currentStepIndex === steps.length - 1;

    // Handler for "Use Profile As-Is" - quick session creation
    const handleUseProfileAsIs = (profile: AIBackendProfile) => {
        setSelectedProfileId(profile.id);

        // Auto-select agent type based on profile compatibility
        if (profile.compatibility.claude && !profile.compatibility.codex) {
            setAgentType('claude');
        } else if (profile.compatibility.codex && !profile.compatibility.claude) {
            setAgentType('codex');
        }

        // Get environment variables from profile (no user configuration)
        const environmentVariables = getProfileEnvironmentVariables(profile);

        // Complete wizard immediately with profile settings
        onComplete({
            sessionType,
            profileId: profile.id,
            agentType: agentType || (profile.compatibility.claude ? 'claude' : 'codex'),
            permissionMode,
            planOnly,
            modelMode,
            machineId: selectedMachineId,
            path: showCustomPathInput && customPath.trim() ? customPath.trim() : selectedPath,
            prompt,
            environmentVariables,
        });
    };

    // Handler for "Edit Profile" - load profile and go to configuration step
    const handleEditProfile = (profile: AIBackendProfile) => {
        setSelectedProfileId(profile.id);

        // Auto-select agent type based on profile compatibility
        if (profile.compatibility.claude && !profile.compatibility.codex) {
            setAgentType('claude');
        } else if (profile.compatibility.codex && !profile.compatibility.claude) {
            setAgentType('codex');
        }

        // If profile needs configuration, go to profileConfig step
        if (profileNeedsConfiguration(profile.id)) {
            setCurrentStep('profileConfig');
        } else {
            // If no configuration needed, proceed to next step in the normal flow
            const profileIndex = steps.indexOf('profile');
            setCurrentStep(steps[profileIndex + 1]);
        }
    };

    // Handler for "Create New Profile"
    const handleCreateProfile = () => {
        Modal.prompt(
            '새 프로필 만들기',
            '새 프로필 이름을 입력하세요:',
            {
                defaultValue: '내 커스텀 프로필',
                confirmText: '생성',
                cancelText: '취소'
            }
        ).then((profileName) => {
            if (profileName && profileName.trim()) {
                const newProfile: AIBackendProfile = {
                    id: crypto.randomUUID(),
                    name: profileName.trim(),
                    description: '사용자 정의 AI 프로필',
                    anthropicConfig: {},
                    environmentVariables: [],
                    compatibility: { claude: true, codex: true, gemini: true },
                    isBuiltIn: false,
                    createdAt: Date.now(),
                    updatedAt: Date.now(),
                    version: '1.0.0',
                };

                // Get current profiles from settings
                const currentProfiles = storage.getState().settings.profiles || [];
                const updatedProfiles = [...currentProfiles, newProfile];

                // Persist through settings system
                sync.applySettings({ profiles: updatedProfiles });

                // Sync with CLI
                profileSyncService.syncGuiToCli(updatedProfiles).catch(error => {
                    console.error('[Wizard] Failed to sync new profile with CLI:', error);
                });

                // Auto-select the newly created profile
                setSelectedProfileId(newProfile.id);
            }
        });
    };

    // Handler for "Duplicate Profile"
    const handleDuplicateProfile = (profile: AIBackendProfile) => {
        Modal.prompt(
            '프로필 복제',
            `"${profile.name}"의 복제본 이름을 입력하세요:`,
            {
                defaultValue: `${profile.name} (복사본)`,
                confirmText: '복제',
                cancelText: '취소'
            }
        ).then((newName) => {
            if (newName && newName.trim()) {
                const duplicatedProfile: AIBackendProfile = {
                    ...profile,
                    id: crypto.randomUUID(),
                    name: newName.trim(),
                    description: profile.description ? `${profile.description} 복사본` : '사용자 정의 AI 프로필',
                    isBuiltIn: false,
                    createdAt: Date.now(),
                    updatedAt: Date.now(),
                };

                // Get current profiles from settings
                const currentProfiles = storage.getState().settings.profiles || [];
                const updatedProfiles = [...currentProfiles, duplicatedProfile];

                // Persist through settings system
                sync.applySettings({ profiles: updatedProfiles });

                // Sync with CLI
                profileSyncService.syncGuiToCli(updatedProfiles).catch(error => {
                    console.error('[Wizard] Failed to sync duplicated profile with CLI:', error);
                });
            }
        });
    };

    // Handler for "Delete Profile"
    const handleDeleteProfile = (profile: AIBackendProfile) => {
        Modal.confirm(
            '프로필 삭제',
            `"${profile.name}"을(를) 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.`,
            {
                confirmText: '삭제',
                destructive: true
            }
        ).then((confirmed) => {
            if (confirmed) {
                // Get current profiles from settings
                const currentProfiles = storage.getState().settings.profiles || [];
                const updatedProfiles = currentProfiles.filter(p => p.id !== profile.id);

                // Persist through settings system
                sync.applySettings({ profiles: updatedProfiles });

                // Sync with CLI
                profileSyncService.syncGuiToCli(updatedProfiles).catch(error => {
                    console.error('[Wizard] Failed to sync profile deletion with CLI:', error);
                });

                // Clear selection if deleted profile was selected
                if (selectedProfileId === profile.id) {
                    setSelectedProfileId(null);
                }
            }
        });
    };

    // Handler for "Use CLI Environment Variables" - quick session creation with CLI vars
    const handleUseCliEnvironmentVariables = () => {
        setSelectedProfileId(null);

        // Complete wizard immediately with no profile (rely on CLI environment variables)
        onComplete({
            sessionType,
            profileId: null,
            agentType,
            permissionMode,
            planOnly,
            modelMode,
            machineId: selectedMachineId,
            path: showCustomPathInput && customPath.trim() ? customPath.trim() : selectedPath,
            prompt,
            environmentVariables: undefined, // Let CLI handle environment variables
        });
    };

    // Handler for "Manual Configuration" - go through normal wizard flow
    const handleManualConfiguration = () => {
        setSelectedProfileId(null);

        // Proceed to next step in normal wizard flow
        const profileIndex = steps.indexOf('profile');
        setCurrentStep(steps[profileIndex + 1]);
    };

    const handleNext = () => {
        // Special handling for profileConfig step - skip if profile doesn't need configuration
        if (currentStep === 'profileConfig' && (!selectedProfileId || !profileNeedsConfiguration(selectedProfileId))) {
            setCurrentStep(steps[currentStepIndex + 1]);
            return;
        }

        if (isLastStep) {
            // Get environment variables from selected profile with proper precedence handling
            let environmentVariables: Record<string, string> | undefined;
            if (selectedProfileId) {
                const selectedProfile = allProfiles.find(p => p.id === selectedProfileId);
                if (selectedProfile) {
                    // Start with profile environment variables (base configuration)
                    environmentVariables = getProfileEnvironmentVariables(selectedProfile);

                    // Only add user-provided API keys if they're non-empty
                    // This preserves CLI environment variable precedence when wizard fields are empty
                    const userApiKeys = profileApiKeys[selectedProfileId];
                    if (userApiKeys) {
                        Object.entries(userApiKeys).forEach(([key, value]) => {
                            // Only override if user provided a non-empty value
                            if (value && value.trim().length > 0) {
                                environmentVariables![key] = value;
                            }
                        });
                    }

                    // Only add user configurations if they're non-empty
                    const userConfigs = profileConfigs[selectedProfileId];
                    if (userConfigs) {
                        Object.entries(userConfigs).forEach(([key, value]) => {
                            // Only override if user provided a non-empty value
                            if (value && value.trim().length > 0) {
                                environmentVariables![key] = value;
                            }
                        });
                    }
                }
            }

            onComplete({
                sessionType,
                profileId: selectedProfileId,
                agentType,
                permissionMode,
                planOnly,
                modelMode,
                machineId: selectedMachineId,
                path: showCustomPathInput && customPath.trim() ? customPath.trim() : selectedPath,
                prompt,
                environmentVariables,
            });
        } else {
            setCurrentStep(steps[currentStepIndex + 1]);
        }
    };

    const handleBack = () => {
        if (isFirstStep) {
            onCancel();
        } else {
            setCurrentStep(steps[currentStepIndex - 1]);
        }
    };

    const canProceed = useMemo(() => {
        switch (currentStep) {
            case 'profile':
                return true; // Always valid (profile can be null for manual config)
            case 'profileConfig':
                if (!selectedProfileId) return false;
                const requiredFields = getProfileRequiredFields(selectedProfileId);
                // Profile configuration step is always shown when needed
                // Users can leave fields empty to preserve CLI environment variables
                return true;
            case 'sessionType':
                return true; // Always valid
            case 'agent':
                return true; // Always valid
            case 'options':
                return true; // Always valid
            case 'machine':
                return selectedMachineId.length > 0;
            case 'path':
                return (selectedPath.trim().length > 0) || (showCustomPathInput && customPath.trim().length > 0);
            case 'prompt':
                return prompt.trim().length > 0;
            default:
                return false;
        }
    }, [currentStep, selectedMachineId, selectedPath, prompt, showCustomPathInput, customPath, selectedProfileId, profileApiKeys, profileConfigs, getProfileRequiredFields]);

    const renderStepContent = () => {
        switch (currentStep) {
            case 'profile':
                return (
                    <View>
                        <Text style={styles.stepTitle}>AI 백엔드 프리셋 선택</Text>
                        <Text style={styles.stepDescription}>
                            프리셋은 제공업체 설정(엔드포인트, 모델, 환경변수)을 묶은 구성입니다.
                        </Text>

                        <ItemGroup title="기본 프리셋">
                            {builtInProfiles.map((profile) => (
                                <ProfileSelectionItem
                                    key={profile.id}
                                    profile={profile}
                                    isSelected={selectedProfileId === profile.id}
                                    onSelect={() => setSelectedProfileId(profile.id)}
                                    onUseAsIs={() => handleUseProfileAsIs(profile)}
                                    onEdit={() => handleEditProfile(profile)}
                                />
                            ))}
                        </ItemGroup>

                        {profiles.length > 0 && (
                            <ItemGroup title="사용자 정의 프리셋">
                                {profiles.map((profile) => (
                                    <ProfileSelectionItem
                                        key={profile.id}
                                        profile={profile}
                                        isSelected={selectedProfileId === profile.id}
                                        onSelect={() => setSelectedProfileId(profile.id)}
                                        onUseAsIs={() => handleUseProfileAsIs(profile)}
                                        onEdit={() => handleEditProfile(profile)}
                                        onDuplicate={() => handleDuplicateProfile(profile)}
                                        onDelete={() => handleDeleteProfile(profile)}
                                        showManagementActions={true}
                                    />
                                ))}
                            </ItemGroup>
                        )}

                        {/* Create New Profile Button */}
                        <Pressable
                            style={{
                                backgroundColor: theme.colors.input.background,
                                borderRadius: 12,
                                borderWidth: 2,
                                borderColor: theme.colors.button.primary.background,
                                borderStyle: 'dashed',
                                padding: 16,
                                marginBottom: 12,
                            }}
                            onPress={handleCreateProfile}
                        >
                            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center' }}>
                                <View style={{
                                    width: 40,
                                    height: 40,
                                    borderRadius: 20,
                                    backgroundColor: theme.colors.button.primary.background,
                                    alignItems: 'center',
                                    justifyContent: 'center',
                                    marginRight: 12,
                                }}>
                                    <Ionicons name="add" size={20} color="white" />
                                </View>
                                <View style={{ flex: 1 }}>
                                    <Text style={{
                                        fontSize: 16,
                                        fontWeight: '600',
                                        color: theme.colors.text,
                                        marginBottom: 4,
                                        ...Typography.default('semiBold'),
                                    }}>
                                        새 프로필 만들기
                                    </Text>
                                    <Text style={{
                                        fontSize: 14,
                                        color: theme.colors.textSecondary,
                                        ...Typography.default(),
                                    }}>
                                        사용자 정의 AI 백엔드 구성을 설정하세요
                                    </Text>
                                </View>
                            </View>
                        </Pressable>

                        <ItemGroup title="수동 설정">
                            <ManualConfigurationItem
                                isSelected={selectedProfileId === null}
                                onSelect={() => setSelectedProfileId(null)}
                                onUseCliVars={() => handleUseCliEnvironmentVariables()}
                                onConfigureManually={() => handleManualConfiguration()}
                            />
                        </ItemGroup>

                        <View style={{
                            backgroundColor: theme.colors.input.background,
                            padding: 12,
                            borderRadius: 8,
                            borderWidth: 1,
                            borderColor: theme.colors.divider,
                            marginTop: 16,
                        }}>
                            <Text style={{
                                fontSize: 14,
                                color: theme.colors.textSecondary,
                                marginBottom: 4,
                            }}>
                                프리셋 동작 방식:
                            </Text>
                            <Text style={{
                                fontSize: 12,
                                color: theme.colors.textSecondary,
                                marginTop: 4,
                            }}>
                                • 현재 프리셋 그대로 사용: 현재 프리셋 설정으로 바로 세션 생성
                            </Text>
                            <Text style={{
                                fontSize: 12,
                                color: theme.colors.textSecondary,
                                marginTop: 4,
                            }}>
                                • 편집: 세션 생성 전 API 키 및 설정 변경
                            </Text>
                            <Text style={{
                                fontSize: 12,
                                color: theme.colors.textSecondary,
                                marginTop: 4,
                            }}>
                                • 수동: 프리셋 설정 없이 CLI 환경변수 사용
                            </Text>
                        </View>
                    </View>
                );

            case 'profileConfig':
                if (!selectedProfileId || !profileNeedsConfiguration(selectedProfileId)) {
                    return (
                        <View>
                            <Text style={styles.stepTitle}>프리셋 설정</Text>
                            <Text style={styles.stepDescription}>설정을 건너뜁니다...</Text>
                            <ActivityIndicator />
                        </View>
                    );
                }

                return (
                    <View>
                        <Text style={styles.stepTitle}>{allProfiles.find(p => p.id === selectedProfileId)?.name || '프로필'} 설정</Text>
                        <Text style={styles.stepDescription}>
                            API 키와 설정 정보를 입력하세요
                        </Text>

                        <ItemGroup title="필수 설정">
                            {getProfileRequiredFields(selectedProfileId).map((field) => (
                                <View key={field.key} style={{ marginBottom: 16 }}>
                                    <Text style={{
                                        fontSize: 16,
                                        fontWeight: '600',
                                        color: theme.colors.text,
                                        marginBottom: 8,
                                        ...Typography.default('semiBold'),
                                    }}>
                                        {field.label}
                                    </Text>
                                    <TextInput
                                        style={[
                                            styles.textInput,
                                            { fontFamily: 'monospace' } // Monospace font for API keys
                                        ]}
                                        placeholder={field.placeholder}
                                        placeholderTextColor={theme.colors.textSecondary}
                                        value={(profileApiKeys[selectedProfileId!] as any)?.[field.key] || (profileConfigs[selectedProfileId!] as any)?.[field.key] || ''}
                                        onChangeText={(text) => {
                                            if (field.isPassword) {
                                                // API key
                                                setProfileApiKeys(prev => ({
                                                    ...prev,
                                                    [selectedProfileId!]: {
                                                        ...(prev[selectedProfileId!] as Record<string, string> || {}),
                                                        [field.key]: text
                                                    }
                                                }));
                                            } else {
                                                // Configuration field
                                                setProfileConfigs(prev => ({
                                                    ...prev,
                                                    [selectedProfileId!]: {
                                                        ...(prev[selectedProfileId!] as Record<string, string> || {}),
                                                        [field.key]: text
                                                    }
                                                }));
                                            }
                                        }}
                                        secureTextEntry={field.isPassword}
                                        autoCapitalize="none"
                                        autoCorrect={false}
                                        returnKeyType="next"
                                    />
                                </View>
                            ))}
                        </ItemGroup>

                        <View style={{
                            backgroundColor: theme.colors.input.background,
                            padding: 12,
                            borderRadius: 8,
                            borderWidth: 1,
                            borderColor: theme.colors.divider,
                            marginTop: 16,
                        }}>
                            <Text style={{
                                fontSize: 14,
                                color: theme.colors.textSecondary,
                                marginBottom: 4,
                            }}>
                                💡 팁: API 키는 이 세션에서만 사용되며 영구 저장되지 않습니다
                            </Text>
                            <Text style={{
                                fontSize: 12,
                                color: theme.colors.textSecondary,
                                marginTop: 4,
                            }}>
                                📝 참고: CLI 환경변수가 이미 설정돼 있으면 입력란을 비워두세요
                            </Text>
                        </View>
                    </View>
                );

            case 'sessionType':
                return (
                    <View>
                        <Text style={styles.stepTitle}>AI 백엔드와 세션 유형 선택</Text>
                        <Text style={styles.stepDescription}>
                            AI 제공업체와 코드 작업 방식을 선택하세요
                        </Text>

                        <ItemGroup title="AI 백엔드">
                            {[
                                {
                                    id: 'anthropic',
                                    name: 'Anthropic Claude',
                                    description: '고급 추론 및 코딩 지원',
                                    icon: 'cube-outline',
                                    agentType: 'claude' as const
                                },
                                {
                                    id: 'openai',
                                    name: 'OpenAI GPT-5',
                                    description: '특화된 코딩 비서',
                                    icon: 'code-outline',
                                    agentType: 'codex' as const
                                },
                                {
                                    id: 'deepseek',
                                    name: 'DeepSeek Reasoner',
                                    description: '고급 추론 모델',
                                    icon: 'analytics-outline',
                                    agentType: 'claude' as const
                                },
                                {
                                    id: 'zai',
                                    name: 'Z.ai',
                                    description: '개발용 AI 어시스턴트',
                                    icon: 'flash-outline',
                                    agentType: 'claude' as const
                                },
                                {
                                    id: 'microsoft',
                                    name: 'Microsoft Azure',
                                    description: '기업용 AI 서비스',
                                    icon: 'cloud-outline',
                                    agentType: 'codex' as const
                                },
                            ].map((backend) => (
                                <Item
                                    key={backend.id}
                                    title={backend.name}
                                    subtitle={backend.description}
                                    leftElement={
                                        <Ionicons
                                            name={backend.icon as any}
                                            size={24}
                                            color={theme.colors.textSecondary}
                                        />
                                    }
                                    rightElement={agentType === backend.agentType ? (
                                        <Ionicons
                                            name="checkmark-circle"
                                            size={20}
                                            color={theme.colors.button.primary.background}
                                        />
                                    ) : null}
                                    onPress={() => setAgentType(backend.agentType)}
                                    showChevron={false}
                                    selected={agentType === backend.agentType}
                                    showDivider={true}
                                />
                            ))}
                        </ItemGroup>

                        <SessionTypeSelector
                            value={sessionType}
                            onChange={setSessionType}
                        />
                    </View>
                );

            case 'agent':
                return (
                    <View>
                        <Text style={styles.stepTitle}>AI 에이전트 선택</Text>
                        <Text style={styles.stepDescription}>
                            사용할 AI 비서를 선택하세요
                        </Text>

                        {selectedProfileId && (
                            <View style={{
                                backgroundColor: theme.colors.input.background,
                                padding: 12,
                                borderRadius: 8,
                                marginBottom: 16,
                                borderWidth: 1,
                                borderColor: theme.colors.divider
                            }}>
                                <Text style={{
                                    fontSize: 14,
                                    color: theme.colors.textSecondary,
                                    marginBottom: 4
                                }}>
                                    프로필: {allProfiles.find(p => p.id === selectedProfileId)?.name || '알 수 없음'}
                                </Text>
                                <Text style={{
                                    fontSize: 12,
                                    color: theme.colors.textSecondary
                                }}>
                                    {allProfiles.find(p => p.id === selectedProfileId)?.description}
                                </Text>
                            </View>
                        )}

                        <Pressable
                            style={[
                                styles.agentOption,
                                agentType === 'claude' ? styles.agentOptionSelected : styles.agentOptionUnselected,
                                selectedProfileId && !allProfiles.find(p => p.id === selectedProfileId)?.compatibility.claude && {
                                    opacity: 0.5,
                                    backgroundColor: theme.colors.surface
                                }
                            ]}
                            onPress={() => {
                                if (!selectedProfileId || allProfiles.find(p => p.id === selectedProfileId)?.compatibility.claude) {
                                    setAgentType('claude');
                                }
                            }}
                            disabled={!!(selectedProfileId && !allProfiles.find(p => p.id === selectedProfileId)?.compatibility.claude)}
                        >
                            <View style={styles.agentIcon}>
                                <Text style={{ color: 'white', fontSize: 16, fontWeight: 'bold' }}>C</Text>
                            </View>
                            <View style={styles.agentInfo}>
                                <Text style={styles.agentName}>Claude</Text>
                                <Text style={styles.agentDescription}>
                                    코딩과 분석에 강점이 있는 Anthropic AI 비서
                                </Text>
                                {selectedProfileId && !allProfiles.find(p => p.id === selectedProfileId)?.compatibility.claude && (
                                    <Text style={{ fontSize: 12, color: theme.colors.textDestructive, marginTop: 4 }}>
                                        선택한 프로필과 호환되지 않습니다
                                    </Text>
                                )}
                            </View>
                            {agentType === 'claude' && (
                                <Ionicons name="checkmark-circle" size={24} color={theme.colors.button.primary.background} />
                            )}
                        </Pressable>

                        <Pressable
                            style={[
                                styles.agentOption,
                                agentType === 'codex' ? styles.agentOptionSelected : styles.agentOptionUnselected,
                                selectedProfileId && !allProfiles.find(p => p.id === selectedProfileId)?.compatibility.codex && {
                                    opacity: 0.5,
                                    backgroundColor: theme.colors.surface
                                }
                            ]}
                            onPress={() => {
                                if (!selectedProfileId || allProfiles.find(p => p.id === selectedProfileId)?.compatibility.codex) {
                                    setAgentType('codex');
                                }
                            }}
                            disabled={!!(selectedProfileId && !allProfiles.find(p => p.id === selectedProfileId)?.compatibility.codex)}
                        >
                            <View style={styles.agentIcon}>
                                <Text style={{ color: 'white', fontSize: 16, fontWeight: 'bold' }}>X</Text>
                            </View>
                            <View style={styles.agentInfo}>
                                <Text style={styles.agentName}>Codex</Text>
                                <Text style={styles.agentDescription}>
                                    OpenAI의 특화된 코딩 비서
                                </Text>
                                {selectedProfileId && !allProfiles.find(p => p.id === selectedProfileId)?.compatibility.codex && (
                                    <Text style={{ fontSize: 12, color: theme.colors.textDestructive, marginTop: 4 }}>
                                        선택한 프로필과 호환되지 않습니다
                                    </Text>
                                )}
                            </View>
                            {agentType === 'codex' && (
                                <Ionicons name="checkmark-circle" size={24} color={theme.colors.button.primary.background} />
                            )}
                        </Pressable>
                    </View>
                );

            case 'options':
                return (
                    <View>
                        <Text style={styles.stepTitle}>에이전트 옵션</Text>
                        <Text style={styles.stepDescription}>
                            AI 에이전트가 동작할 방식을 설정하세요
                        </Text>

                        {selectedProfileId && (
                            <View style={{
                                backgroundColor: theme.colors.input.background,
                                padding: 12,
                                borderRadius: 8,
                                marginBottom: 16,
                                borderWidth: 1,
                                borderColor: theme.colors.divider
                            }}>
                                <Text style={{
                                    fontSize: 14,
                                    color: theme.colors.textSecondary,
                                    marginBottom: 4
                                }}>
                                    사용 중인 프로필: {allProfiles.find(p => p.id === selectedProfileId)?.name || '알 수 없음'}
                                </Text>
                                <Text style={{
                                    fontSize: 12,
                                    color: theme.colors.textSecondary
                                }}>
                                    환경변수는 자동으로 적용됩니다
                                </Text>
                            </View>
                        )}
                        <ItemGroup title="권한 모드">
                            {([
                                {
                                    kind: 'mode',
                                    value: 'default',
                                    label: t('agentInput.permissionMode.default'),
                                    description: t('agentInput.permissionMode.askEveryAction'),
                                    icon: 'shield-outline'
                                },
                                {
                                    kind: 'plan',
                                    label: t('agentInput.permissionMode.plan'),
                                    description: t('agentInput.permissionMode.planOnly'),
                                    icon: 'list-outline'
                                },
                                {
                                    kind: 'mode',
                                    value: 'allow-edits',
                                    label: t('agentInput.permissionMode.acceptEdits'),
                                    description: t('agentInput.permissionMode.autoApproveEdits'),
                                    icon: 'create-outline'
                                },
                                {
                                    kind: 'mode',
                                    value: 'read-only',
                                    label: t('agentInput.codexPermissionMode.readOnly'),
                                    description: t('agentInput.permissionMode.readOnlyTools'),
                                    icon: 'eye-outline'
                                },
                                {
                                    kind: 'mode',
                                    value: 'bypass',
                                    label: t('agentInput.permissionMode.bypassPermissions'),
                                    description: t('agentInput.permissionMode.autoApproveAll'),
                                    icon: 'flash-outline'
                                },
                            ] as const).map((row, index, array) => {
                                const isSelected = row.kind === 'plan' ? planOnly : !planOnly && permissionMode === row.value;
                                return (
                                    <Item
                                        key={row.kind === 'plan' ? 'planning' : row.value}
                                        title={row.label}
                                        subtitle={row.description}
                                        leftElement={
                                            <Ionicons
                                                name={row.icon}
                                                size={24}
                                                color={theme.colors.textSecondary}
                                            />
                                        }
                                        rightElement={isSelected ? (
                                            <Ionicons
                                                name="checkmark-circle"
                                                size={20}
                                                color={theme.colors.button.primary.background}
                                            />
                                        ) : null}
                                        onPress={() => {
                                            if (row.kind === 'plan') {
                                                setPlanOnly(!planOnly);
                                                return;
                                            }
                                            setPlanOnly(false);
                                            setPermissionMode(row.value as PermissionMode);
                                        }}
                                        showChevron={false}
                                        selected={isSelected}
                                        showDivider={index < array.length - 1}
                                    />
                                );
                            })}
                        </ItemGroup>

                        <ItemGroup title="모델 모드">
                            {(agentType === 'claude' ? [
                                { value: 'default', label: '기본', description: '균형 잡힌 성능', icon: 'cube-outline' },
                                { value: 'adaptiveUsage', label: '적응형 사용', description: '모델 자동 선택', icon: 'analytics-outline' },
                                { value: 'sonnet', label: 'Sonnet', description: '빠르고 효율적', icon: 'speedometer-outline' },
                                { value: 'opus', label: 'Opus', description: '가장 성능이 높은 모델', icon: 'diamond-outline' },
                            ] as const : [
                                { value: 'gpt-5-codex-high', label: 'GPT-5 코덱스 고성능', description: '복잡한 코딩에 최적', icon: 'diamond-outline' },
                                { value: 'gpt-5-codex-medium', label: 'GPT-5 코덱스 중간', description: '균형 잡힌 코딩 지원', icon: 'cube-outline' },
                                { value: 'gpt-5-codex-low', label: 'GPT-5 코덱스 저용량', description: '빠른 코딩 지원', icon: 'speedometer-outline' },
                            ] as const).map((option, index, array) => (
                                <Item
                                    key={option.value}
                                    title={option.label}
                                    subtitle={option.description}
                                    leftElement={
                                        <Ionicons
                                            name={option.icon}
                                            size={24}
                                            color={theme.colors.textSecondary}
                                        />
                                    }
                                    rightElement={modelMode === option.value ? (
                                        <Ionicons
                                            name="checkmark-circle"
                                            size={20}
                                            color={theme.colors.button.primary.background}
                                        />
                                    ) : null}
                                    onPress={() => {
                                        modelTouchedRef.current = true;
                                        setModelMode(option.value as ModelMode);
                                    }}
                                    showChevron={false}
                                    selected={modelMode === option.value}
                                    showDivider={index < array.length - 1}
                                />
                            ))}
                        </ItemGroup>
                    </View>
                );

            case 'machine':
                return (
                    <View>
                        <Text style={styles.stepTitle}>기기 선택</Text>
                        <Text style={styles.stepDescription}>
                            세션을 실행할 기기를 선택하세요
                        </Text>

                        <ItemGroup title="사용 가능한 기기">
                            {machines.map((machine, index) => (
                                <Item
                                    key={machine.id}
                                    title={machine.metadata?.displayName || machine.metadata?.host || machine.id}
                                    subtitle={machine.metadata?.host || ''}
                                    leftElement={
                                        <Ionicons
                                            name="laptop-outline"
                                            size={24}
                                            color={theme.colors.textSecondary}
                                        />
                                    }
                                    rightElement={selectedMachineId === machine.id ? (
                                        <Ionicons
                                            name="checkmark-circle"
                                            size={20}
                                            color={theme.colors.button.primary.background}
                                        />
                                    ) : null}
                                    onPress={() => {
                                        setSelectedMachineId(machine.id);
                                        // Update path when machine changes
                                        const homeDir = machine.metadata?.homeDir || '/home';
                                        setSelectedPath(homeDir);
                                        setBrowsePath(homeDir);
                                    }}
                                    showChevron={false}
                                    selected={selectedMachineId === machine.id}
                                    showDivider={index < machines.length - 1}
                                />
                            ))}
                        </ItemGroup>
                    </View>
                );

            case 'path':
                return (
                    <View>
                        <Text style={styles.stepTitle}>작업 디렉토리</Text>
                        <Text style={styles.stepDescription}>
                            작업할 디렉토리를 선택하세요
                        </Text>

                        {/* 파일 탐색기 */}
                        <ItemGroup
                            title={(() => {
                                const root = normalizeRemotePath(browseRoot || '/');
                                const current = normalizeRemotePath(browsePath);
                                const canGoUp = current !== root && current !== '/';
                                const accent = theme.colors.chrome?.accent ?? theme.colors.textLink;
                                const parent = parentRemotePath(current);
                                const clampedParent =
                                    root && root !== '/' && !parent.startsWith(root) ? root : parent;

                                return (
                                    <View style={{ gap: 8 }}>
                                        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
                                            <Text style={{
                                                ...Typography.default('regular'),
                                                color: theme.colors.groupped.sectionTitle,
                                                fontSize: Platform.select({ ios: 13, web: 12, default: 13 }),
                                                lineHeight: Platform.select({ ios: 18, default: 20 }),
                                                letterSpacing: Platform.select({ ios: -0.08, default: 0.1 }),
                                                textTransform: 'uppercase',
                                                fontWeight: Platform.select({ ios: 'normal', default: '500' }) as any,
                                            }}>
                                                파일 탐색기
                                            </Text>

                                            <Pressable
                                                accessibilityLabel="새로 고침"
                                                onPress={() => setBrowseReloadToken(x => x + 1)}
                                                style={({ pressed }) => ({
                                                    opacity: pressed ? 0.8 : 1,
                                                    paddingHorizontal: 10,
                                                    paddingVertical: 7,
                                                    borderRadius: 10,
                                                    borderWidth: 1,
                                                    borderColor: theme.colors.divider,
                                                    backgroundColor: pressed ? theme.colors.surfacePressedOverlay : theme.colors.surfaceHigh,
                                                })}
                                            >
                                                <Ionicons
                                                    name="refresh-outline"
                                                    size={18}
                                                    color={theme.colors.textSecondary}
                                                />
                                            </Pressable>
                                        </View>

	                                        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
	                                            <Pressable
	                                                accessibilityLabel="상위 폴더로"
	                                                disabled={!canGoUp}
	                                                onPress={() => setBrowsePath(clampedParent)}
                                                style={({ pressed }) => ({
                                                    opacity: !canGoUp ? 0.35 : (pressed ? 0.8 : 1),
                                                    width: 34,
                                                    height: 34,
                                                    borderRadius: 10,
                                                    borderWidth: 1,
                                                    borderColor: theme.colors.divider,
                                                    alignItems: 'center',
                                                    justifyContent: 'center',
                                                    backgroundColor: pressed ? theme.colors.surfacePressedOverlay : theme.colors.surfaceHigh,
                                                })}
                                            >
                                                <Ionicons
                                                    name="chevron-back-outline"
                                                    size={18}
                                                    color={theme.colors.textSecondary}
                                                />
                                            </Pressable>

	                                            {(() => {
	                                                const rel = remotePathRelativeToRoot(current, root);
	                                                const label = rel === '.' ? '/' : `/${rel}`;
	                                                return (
	                                                    <Text
	                                                        style={{
	                                                            ...Typography.default('regular'),
	                                                            fontSize: 13,
	                                                            color: theme.colors.textSecondary,
	                                                            flex: 1,
	                                                        }}
	                                                        numberOfLines={1}
	                                                        ellipsizeMode="middle"
	                                                    >
	                                                        {label}
	                                                    </Text>
	                                                );
	                                            })()}
	                                        </View>
	                                    </View>
	                                );
	                            })()}
                            headerStyle={{
                                // Balance vertical rhythm: the default ItemGroup header is top-heavy (esp. iOS),
                                // which makes this "파일 탐색기" block feel like it has extra top margin but
                                // not enough space before the folder list.
                                paddingTop: Platform.select({ ios: 18, web: 10, default: 14 }),
                                paddingBottom: Platform.select({ ios: 12, web: 10, default: 12 }),
                            }}
	                        >
	                            <Item
	                                title="이 폴더로 선택"
	                                subtitle={remotePathRelativeToRoot(browsePath, browseRoot || browsePath)}
	                                subtitleLines={1}
	                                rightElement={
	                                    <Ionicons
	                                        name="checkmark-circle"
	                                        size={22}
	                                        color={theme.colors.chrome?.accent ?? theme.colors.textLink}
	                                    />
	                                }
	                                onPress={() => {
	                                    setSelectedPath(browsePath);
	                                    setShowCustomPathInput(false);
	                                    setCurrentStep('prompt');
	                                }}
	                                showChevron={false}
	                                pressableStyle={{
	                                    backgroundColor: theme.colors.surfaceSelected,
	                                }}
	                            />

                            {browseError && (
                                <Item
                                    title="폴더 목록을 불러오지 못했습니다"
                                    subtitle={browseError}
                                    subtitleLines={2}
                                    leftElement={
                                        <Ionicons
                                            name="alert-circle-outline"
                                            size={24}
                                            color={theme.colors.textSecondary}
                                        />
                                    }
                                    showChevron={false}
                                    disabled={true}
                                />
                            )}

                            {isBrowsing && (
                                <Item
                                    title="불러오는 중..."
                                    subtitle="기기에서 폴더를 가져오는 중"
                                    leftElement={<ActivityIndicator />}
                                    showChevron={false}
                                    disabled={true}
                                />
                            )}

                            {!isBrowsing && !browseError && browseEntries.length === 0 && (
                                <Item
                                    title="폴더가 없습니다"
                                    subtitle="이 디렉토리는 비어 있습니다"
                                    leftElement={
                                        <Ionicons
                                            name="folder-outline"
                                            size={24}
                                            color={theme.colors.textSecondary}
                                        />
                                    }
                                    showChevron={false}
                                    disabled={true}
                                />
                            )}

	                            {!browseError && browseEntries.map((entry) => (
	                                <Item
	                                    key={`${browsePath}:${entry.name}`}
	                                    title={entry.name}
	                                    subtitle={remotePathRelativeToRoot(joinRemotePath(browsePath, entry.name), browseRoot || browsePath)}
	                                    subtitleLines={1}
                                    leftElement={
                                        <Ionicons
                                            name="folder-outline"
                                            size={24}
                                            color={theme.colors.textSecondary}
                                        />
                                    }
                                    onPress={() => setBrowsePath(joinRemotePath(browsePath, entry.name))}
                                    onLongPress={() => {
                                        const next = joinRemotePath(browsePath, entry.name);
                                        setSelectedPath(next);
                                        setShowCustomPathInput(false);
	                                    }}
	                                />
	                            ))}
	                        </ItemGroup>

                        {/* Common Directories */}
                        <ItemGroup title="자주 사용하는 디렉토리">
                            {(() => {
                                const machine = machines.find(m => m.id === selectedMachineId);
                                const homeDir = machine?.metadata?.homeDir || '/home';
                                const pathOptions = [
                                    { value: homeDir, label: homeDir, description: '홈 디렉터리' },
                                    { value: `${homeDir}/projects`, label: `${homeDir}/projects`, description: '프로젝트 폴더' },
                                    { value: `${homeDir}/Documents`, label: `${homeDir}/Documents`, description: '문서 폴더' },
                                    { value: `${homeDir}/Desktop`, label: `${homeDir}/Desktop`, description: '바탕화면 폴더' },
                                ];
                                return pathOptions.map((option, index) => (
                                    <Item
                                        key={option.value}
                                        title={option.label}
                                        subtitle={option.description}
                                        leftElement={
                                            <Ionicons
                                                name="folder-outline"
                                                size={24}
                                                color={theme.colors.textSecondary}
                                            />
                                        }
                                        rightElement={selectedPath === option.value && !showCustomPathInput ? (
                                            <Ionicons
                                                name="checkmark-circle"
                                                size={20}
                                                color={theme.colors.button.primary.background}
                                            />
                                        ) : null}
                                        onPress={() => {
                                            setSelectedPath(option.value);
                                            setBrowsePath(option.value);
                                            setShowCustomPathInput(false);
                                        }}
                                        showChevron={false}
                                        selected={selectedPath === option.value && !showCustomPathInput}
                                        showDivider={index < pathOptions.length - 1}
                                    />
                                ));
                            })()}
                        </ItemGroup>

                        {/* Custom Path Option */}
                        <ItemGroup title="직접 지정 디렉토리">
                            <Item
                                title="직접 경로 입력"
                                subtitle={showCustomPathInput && customPath ? customPath : "직접 지정한 디렉터리 경로를 입력하세요"}
                                leftElement={
                                    <Ionicons
                                        name="create-outline"
                                        size={24}
                                        color={theme.colors.textSecondary}
                                    />
                                }
                                rightElement={showCustomPathInput ? (
                                    <Ionicons
                                        name="checkmark-circle"
                                        size={20}
                                        color={theme.colors.button.primary.background}
                                    />
                                ) : null}
                                onPress={() => setShowCustomPathInput(true)}
                                showChevron={false}
                                selected={showCustomPathInput}
                                showDivider={false}
                            />
                            {showCustomPathInput && (
                                <View style={{ paddingHorizontal: 16, paddingVertical: 12 }}>
                                    <TextInput
                                        style={styles.textInput}
                                        placeholder="디렉토리 경로를 입력하세요 (예: /home/user/my-project)"
                                        placeholderTextColor={theme.colors.textSecondary}
                                        value={customPath}
                                        onChangeText={setCustomPath}
                                        autoCapitalize="none"
                                        autoCorrect={false}
                                        returnKeyType="done"
                                    />
                                </View>
                            )}
                        </ItemGroup>
                    </View>
                );

            case 'prompt':
                return (
                    <View>
                        <Text style={styles.stepTitle}>초기 메시지</Text>
                        <Text style={styles.stepDescription}>
                            AI 에이전트에게 보낼 첫 메시지를 작성하세요
                        </Text>

                        <TextInput
                            style={[styles.textInput, { height: 120, textAlignVertical: 'top' }]}
                            placeholder={t('session.inputPlaceholder')}
                            placeholderTextColor={theme.colors.textSecondary}
                            value={prompt}
                            onChangeText={setPrompt}
                            multiline={true}
                            autoCapitalize="sentences"
                            autoCorrect={true}
                            returnKeyType="default"
                        />
                    </View>
                );

            default:
                return null;
        }
    };

    return (
        <View style={styles.container}>
            <View style={styles.header}>
                <Text style={styles.headerTitle}>새 세션</Text>
                <Pressable onPress={onCancel}>
                    <Ionicons name="close" size={24} color={theme.colors.textSecondary} />
                </Pressable>
            </View>

            <View style={styles.stepIndicator}>
                {steps.map((step, index) => (
                    <View
                        key={step}
                        style={[
                            styles.stepDot,
                            index <= currentStepIndex ? styles.stepDotActive : styles.stepDotInactive
                        ]}
                    />
                ))}
            </View>

            <ScrollView
                style={styles.stepContent}
                contentContainerStyle={{ paddingBottom: 24 }}
                showsVerticalScrollIndicator={true}
            >
                {renderStepContent()}
            </ScrollView>

            <View style={styles.footer}>
                <Pressable
                    style={[styles.button, styles.buttonSecondary]}
                    onPress={handleBack}
                >
                    <Text style={[styles.buttonText, styles.buttonTextSecondary]}>
                        {isFirstStep ? '취소' : '이전'}
                    </Text>
                </Pressable>

                <Pressable
                    style={[
                        styles.button,
                        styles.buttonPrimary,
                        !canProceed && { opacity: 0.5 }
                    ]}
                    onPress={handleNext}
                    disabled={!canProceed}
                >
                    <Text style={[styles.buttonText, styles.buttonTextPrimary]}>
                        {isLastStep ? '세션 생성' : '다음'}
                    </Text>
                </Pressable>
            </View>
        </View>
    );
}
