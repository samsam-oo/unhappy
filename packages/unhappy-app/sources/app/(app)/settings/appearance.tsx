import Ionicons from '@expo/vector-icons/Ionicons';
import { Item } from '@/components/Item';
import { ItemGroup } from '@/components/ItemGroup';
import { ItemList } from '@/components/ItemList';
import { useSettingMutable } from '@/sync/storage';
import { useRouter } from 'expo-router';
import * as Localization from 'expo-localization';
import { useUnistyles } from 'react-native-unistyles';
import { Switch } from '@/components/Switch';
import { t, getLanguageNativeName, SUPPORTED_LANGUAGES } from '@/text';

// 앱에서 지원하는 아바타 스타일을 지정
type KnownAvatarStyle = 'pixelated' | 'gradient' | 'brutalist';

const isKnownAvatarStyle = (style: string): style is KnownAvatarStyle => {
    return style === 'pixelated' || style === 'gradient' || style === 'brutalist';
};

export default function AppearanceSettingsScreen() {
    const { theme } = useUnistyles();
    const router = useRouter();
    const accentPrimary = theme.dark ? 'rgba(203,213,225,0.86)' : 'rgba(71,85,105,0.78)';
    const accentMuted = theme.dark ? 'rgba(148,163,184,0.80)' : 'rgba(100,116,139,0.74)';
    const APPEARANCE_ICON_SIZE = 24;
    const [viewInline, setViewInline] = useSettingMutable('viewInline');
    const [expandTodos, setExpandTodos] = useSettingMutable('expandTodos');
    const [showLineNumbers, setShowLineNumbers] = useSettingMutable('showLineNumbers');
    const [showLineNumbersInToolViews, setShowLineNumbersInToolViews] = useSettingMutable('showLineNumbersInToolViews');
    const [wrapLinesInDiffs, setWrapLinesInDiffs] = useSettingMutable('wrapLinesInDiffs');
    const [avatarStyle, setAvatarStyle] = useSettingMutable('avatarStyle');
    const [showFlavorIcons, setShowFlavorIcons] = useSettingMutable('showFlavorIcons');
    const [compactSessionView, setCompactSessionView] = useSettingMutable('compactSessionView');
    const [preferredLanguage] = useSettingMutable('preferredLanguage');
    
    // 표시할 수 있는 스타일이 아니면 기본값(그라디언트)으로 보정
    const displayStyle: KnownAvatarStyle = isKnownAvatarStyle(avatarStyle) ? avatarStyle : 'gradient';
    
    // 언어 표시 문자열 계산
    const getLanguageDisplayText = () => {
        if (preferredLanguage === null) {
            const deviceLocale = Localization.getLocales()?.[0]?.languageTag ?? 'en-US';
            const deviceLanguage = deviceLocale.split('-')[0].toLowerCase();
            const detectedLanguageName = deviceLanguage in SUPPORTED_LANGUAGES ? 
                                        getLanguageNativeName(deviceLanguage as keyof typeof SUPPORTED_LANGUAGES) : 
                                        getLanguageNativeName('en');
            return `${t('settingsLanguage.automatic')} (${detectedLanguageName})`;
        } else if (preferredLanguage && preferredLanguage in SUPPORTED_LANGUAGES) {
            return getLanguageNativeName(preferredLanguage as keyof typeof SUPPORTED_LANGUAGES);
        }
        return t('settingsLanguage.automatic');
    };
    return (
        <ItemList style={{ paddingTop: 0 }}>

            {/* 테마 설정 */}
            <ItemGroup title={t('settingsAppearance.theme')} footer={t('settingsAppearance.themeDescription')}>
                <Item
                    title={t('settings.appearance')}
                    subtitle={t('settingsAppearance.themeDescriptions.dark')}
                    icon={<Ionicons name="contrast-outline" size={APPEARANCE_ICON_SIZE} color={accentMuted} />}
                    detail={t('settingsAppearance.themeOptions.dark')}
                    disabled
                />
            </ItemGroup>

            {/* 언어 설정 */}
            <ItemGroup title={t('settingsLanguage.title')} footer={t('settingsLanguage.description')}>
                <Item
                    title={t('settingsLanguage.currentLanguage')}
                    icon={<Ionicons name="language-outline" size={APPEARANCE_ICON_SIZE} color={accentPrimary} />}
                    detail={getLanguageDisplayText()}
                    onPress={() => router.push('/settings/language')}
                />
            </ItemGroup>

            {/* 텍스트 설정 */}
            {/* <ItemGroup title="텍스트" footer="텍스트 크기와 글꼴 선호도를 조정">
                <Item
                    title="텍스트 크기"
                    subtitle="텍스트를 더 크거나 작게 조정"
                    icon={<Ionicons name="text-outline" size={29} color="#FF9500" />}
                    detail="기본"
                    onPress={() => { }}
                    disabled
                />
                <Item
                    title="글꼴"
                    subtitle="선호하는 글꼴 선택"
                    icon={<Ionicons name="text-outline" size={29} color="#FF9500" />}
                    detail="시스템"
                    onPress={() => { }}
                    disabled
                />
            </ItemGroup> */}

            {/* 표시 설정 */}
            <ItemGroup title={t('settingsAppearance.display')} footer={t('settingsAppearance.displayDescription')}>
                <Item
                    title={t('settingsAppearance.compactSessionView')}
                    subtitle={t('settingsAppearance.compactSessionViewDescription')}
                    icon={<Ionicons name="albums-outline" size={APPEARANCE_ICON_SIZE} color={accentPrimary} />}
                    rightElement={
                        <Switch
                            value={compactSessionView}
                            onValueChange={setCompactSessionView}
                        />
                    }
                />
                <Item
                    title={t('settingsAppearance.inlineToolCalls')}
                    subtitle={t('settingsAppearance.inlineToolCallsDescription')}
                    icon={<Ionicons name="code-slash-outline" size={APPEARANCE_ICON_SIZE} color={accentPrimary} />}
                    rightElement={
                        <Switch
                            value={viewInline}
                            onValueChange={setViewInline}
                        />
                    }
                />
                <Item
                    title={t('settingsAppearance.expandTodoLists')}
                    subtitle={t('settingsAppearance.expandTodoListsDescription')}
                    icon={<Ionicons name="checkmark-done-outline" size={APPEARANCE_ICON_SIZE} color={accentPrimary} />}
                    rightElement={
                        <Switch
                            value={expandTodos}
                            onValueChange={setExpandTodos}
                        />
                    }
                />
                <Item
                    title={t('settingsAppearance.showLineNumbersInDiffs')}
                    subtitle={t('settingsAppearance.showLineNumbersInDiffsDescription')}
                    icon={<Ionicons name="list-outline" size={APPEARANCE_ICON_SIZE} color={accentPrimary} />}
                    rightElement={
                        <Switch
                            value={showLineNumbers}
                            onValueChange={setShowLineNumbers}
                        />
                    }
                />
                <Item
                    title={t('settingsAppearance.showLineNumbersInToolViews')}
                    subtitle={t('settingsAppearance.showLineNumbersInToolViewsDescription')}
                    icon={<Ionicons name="code-working-outline" size={APPEARANCE_ICON_SIZE} color={accentPrimary} />}
                    rightElement={
                        <Switch
                            value={showLineNumbersInToolViews}
                            onValueChange={setShowLineNumbersInToolViews}
                        />
                    }
                />
                <Item
                    title={t('settingsAppearance.wrapLinesInDiffs')}
                    subtitle={t('settingsAppearance.wrapLinesInDiffsDescription')}
                    icon={<Ionicons name="return-down-forward-outline" size={APPEARANCE_ICON_SIZE} color={accentPrimary} />}
                    rightElement={
                        <Switch
                            value={wrapLinesInDiffs}
                            onValueChange={setWrapLinesInDiffs}
                        />
                    }
                />
                <Item
                    title={t('settingsAppearance.avatarStyle')}
                    subtitle={t('settingsAppearance.avatarStyleDescription')}
                    icon={<Ionicons name="person-circle-outline" size={APPEARANCE_ICON_SIZE} color={accentPrimary} />}
                    detail={displayStyle === 'pixelated' ? t('settingsAppearance.avatarOptions.pixelated') : displayStyle === 'brutalist' ? t('settingsAppearance.avatarOptions.brutalist') : t('settingsAppearance.avatarOptions.gradient')}
                    onPress={() => {
                        const currentIndex = displayStyle === 'pixelated' ? 0 : displayStyle === 'gradient' ? 1 : 2;
                        const nextIndex = (currentIndex + 1) % 3;
                        const nextStyle = nextIndex === 0 ? 'pixelated' : nextIndex === 1 ? 'gradient' : 'brutalist';
                        setAvatarStyle(nextStyle);
                    }}
                />
                <Item
                    title={t('settingsAppearance.showFlavorIcons')}
                    subtitle={t('settingsAppearance.showFlavorIconsDescription')}
                    icon={<Ionicons name="apps-outline" size={APPEARANCE_ICON_SIZE} color={accentPrimary} />}
                    rightElement={
                        <Switch
                            value={showFlavorIcons}
                            onValueChange={setShowFlavorIcons}
                        />
                    }
                />
                {/* <Item
                    title="컴팩트 모드"
                    subtitle="요소 간 간격을 줄임"
                    icon={<Ionicons name="contract-outline" size={29} color="#5856D6" />}
                    disabled
                    rightElement={
                        <Switch
                            value={false}
                            disabled
                        />
                    }
                />
                <Item
                    title="아바타 표시"
                    subtitle="사용자와 어시스턴트 아바타 표시"
                    icon={<Ionicons name="person-circle-outline" size={29} color="#5856D6" />}
                    disabled
                    rightElement={
                        <Switch
                            value={true}
                            disabled
                        />
                    }
                /> */}
            </ItemGroup>

            {/* 색상 */}
            {/* <ItemGroup title="색상" footer="강조 색상과 하이라이트를 조정">
                <Item
                    title="강조색"
                    subtitle="강조 색상을 선택"
                    icon={<Ionicons name="color-palette-outline" size={29} color="#FF3B30" />}
                    detail="파랑"
                    onPress={() => { }}
                    disabled
                />
            </ItemGroup> */}
        </ItemList>
    );
}
