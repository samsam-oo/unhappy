import { useAuth } from "@/auth/AuthContext";
import { authGetToken } from "@/auth/authGetToken";
import { HomeHeaderNotAuth } from "@/components/HomeHeader";
import { MainView } from "@/components/MainView";
import { RoundButton } from "@/components/RoundButton";
import { Typography } from "@/constants/Typography";
import { encodeBase64 } from "@/encryption/base64";
import { Ionicons } from "@/icons/vector-icons";
import { t } from '@/text';
import { trackAccountCreated, trackAccountRestored } from '@/track';
import { useIsLandscape } from "@/utils/responsive";
import { getRandomBytesAsync } from "expo-crypto";
import { Image } from "expo-image";
import { useRouter } from "expo-router";
import * as React from 'react';
import { Platform, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { StyleSheet, useUnistyles } from "react-native-unistyles";

export default function Home() {
    const auth = useAuth();
    if (!auth.isAuthenticated) {
        return <NotAuthenticated />;
    }
    return (
        <Authenticated />
    )
}

function Authenticated() {
    return <MainView variant="phone" />;
}

function FeatureBadge({ icon, label }: { icon: React.ComponentProps<typeof Ionicons>['name']; label: string }) {
    const { theme } = useUnistyles();
    return (
        <View style={styles.featureBadge}>
            <Ionicons name={icon} size={14} color={theme.colors.textLink} />
            <Text style={styles.featureBadgeText}>{label}</Text>
        </View>
    );
}

function BrandingSection() {
    const { theme } = useUnistyles();
    return (
        <View style={styles.brandingSection}>
            <View style={styles.iconGlow}>
                <Image
                    source={require('@/assets/images/logotype.png')}
                    contentFit="contain"
                    style={styles.iconLogo}
                />
            </View>
            <Text style={styles.brandName}>Unhappy Coder</Text>
            <Text style={styles.tagline}>
                {t('welcome.title')}
            </Text>
        </View>
    );
}

function CTAButtons({ createAccount, router: nav }: { createAccount: () => Promise<void>; router: ReturnType<typeof useRouter> }) {
    if (Platform.OS !== 'android' && Platform.OS !== 'ios') {
        return (
            <>
                <View style={styles.buttonContainer}>
                    <RoundButton
                        title={t('welcome.loginWithMobileApp')}
                        onPress={() => {
                            trackAccountRestored();
                            nav.push('/restore');
                        }}
                    />
                </View>
                <View style={styles.buttonContainerSecondary}>
                    <RoundButton
                        size="normal"
                        title={t('welcome.createAccount')}
                        action={createAccount}
                        display="inverted"
                    />
                </View>
            </>
        );
    }
    return (
        <>
            <View style={styles.buttonContainer}>
                <RoundButton
                    title={t('welcome.createAccount')}
                    action={createAccount}
                />
            </View>
            <View style={styles.buttonContainerSecondary}>
                <RoundButton
                    size="normal"
                    title={t('welcome.linkOrRestoreAccount')}
                    onPress={() => {
                        trackAccountRestored();
                        nav.push('/restore');
                    }}
                    display="inverted"
                />
            </View>
        </>
    );
}

function NotAuthenticated() {
    const auth = useAuth();
    const router = useRouter();
    const isLandscape = useIsLandscape();
    const insets = useSafeAreaInsets();

    const createAccount = async () => {
        try {
            const secret = await getRandomBytesAsync(32);
            const token = await authGetToken(secret);
            if (token && secret) {
                await auth.login(token, encodeBase64(secret, 'base64url'));
                trackAccountCreated();
            }
        } catch (error) {
            console.error('Error creating account', error);
        }
    }

    const featureBadges = (
        <View style={styles.featureRow}>
            <FeatureBadge icon="lock-closed" label={t('welcome.featureEncrypted')} />
            <FeatureBadge icon="globe-outline" label={t('welcome.featureCrossPlatform')} />
            <FeatureBadge icon="flash" label={t('welcome.featureInstantSync')} />
        </View>
    );

    const portraitLayout = (
        <View style={styles.portraitContainer}>
            <BrandingSection />
            <Text style={styles.subtitle}>
                {t('welcome.subtitle')}
            </Text>
            {featureBadges}
            <View style={styles.ctaSection}>
                <CTAButtons createAccount={createAccount} router={router} />
            </View>
        </View>
    );

    const landscapeLayout = (
        <View style={[styles.landscapeContainer, { paddingBottom: insets.bottom + 24 }]}>
            <View style={styles.landscapeInner}>
                <View style={styles.landscapeLogoSection}>
                    <BrandingSection />
                    {featureBadges}
                </View>
                <View style={styles.landscapeContentSection}>
                    <Text style={styles.landscapeSubtitle}>
                        {t('welcome.subtitle')}
                    </Text>
                    <CTAButtons createAccount={createAccount} router={router} />
                </View>
            </View>
        </View>
    );

    return (
        <>
            <HomeHeaderNotAuth />
            {isLandscape ? landscapeLayout : portraitLayout}
        </>
    )
}

const styles = StyleSheet.create((theme) => ({
    // Portrait layout
    portraitContainer: {
        flex: 1,
        alignItems: 'center',
        justifyContent: 'center',
        paddingHorizontal: 24,
    },

    // Branding
    brandingSection: {
        alignItems: 'center',
    },
    iconGlow: {
        width: 80,
        height: 80,
        borderRadius: 40,
        backgroundColor: theme.dark ? 'rgba(255, 255, 255, 0.06)' : 'rgba(0, 0, 0, 0.04)',
        alignItems: 'center',
        justifyContent: 'center',
        marginBottom: 20,
    },
    iconLogo: {
        width: 44,
        height: 44,
    },
    brandName: {
        ...Typography.logo(),
        fontSize: 36,
        color: theme.colors.text,
        letterSpacing: -0.5,
        marginBottom: 8,
    },
    tagline: {
        ...Typography.default(),
        fontSize: 16,
        color: theme.colors.textLink,
        textAlign: 'center',
    },

    // Subtitle
    subtitle: {
        ...Typography.default(),
        fontSize: 15,
        lineHeight: 22,
        color: theme.colors.textSecondary,
        marginTop: 16,
        textAlign: 'center',
        maxWidth: 320,
    },

    // Feature badges
    featureRow: {
        flexDirection: 'row',
        flexWrap: 'wrap',
        justifyContent: 'center',
        gap: 8,
        marginTop: 24,
    },
    featureBadge: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 6,
        paddingHorizontal: 12,
        paddingVertical: 6,
        borderRadius: 20,
        backgroundColor: theme.dark ? 'rgba(255, 255, 255, 0.06)' : 'rgba(0, 0, 0, 0.04)',
    },
    featureBadgeText: {
        ...Typography.default(),
        fontSize: 12,
        color: theme.colors.textSecondary,
    },

    // CTA
    ctaSection: {
        alignItems: 'center',
        marginTop: 48,
        width: '100%',
    },
    buttonContainer: {
        maxWidth: 280,
        width: '100%',
        marginBottom: 16,
    },
    buttonContainerSecondary: {
    },

    // Landscape styles
    landscapeContainer: {
        flexBasis: 0,
        flexGrow: 1,
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'center',
        paddingHorizontal: 48,
    },
    landscapeInner: {
        flexGrow: 1,
        flexBasis: 0,
        maxWidth: 800,
        flexDirection: 'row',
    },
    landscapeLogoSection: {
        flexBasis: 0,
        flexGrow: 1,
        alignItems: 'center',
        justifyContent: 'center',
        paddingRight: 24,
    },
    landscapeContentSection: {
        flexBasis: 0,
        flexGrow: 1,
        alignItems: 'center',
        justifyContent: 'center',
        paddingLeft: 24,
    },
    landscapeSubtitle: {
        ...Typography.default(),
        fontSize: 15,
        lineHeight: 22,
        color: theme.colors.textSecondary,
        textAlign: 'center',
        marginBottom: 32,
        paddingHorizontal: 16,
        maxWidth: 320,
    },
}));
