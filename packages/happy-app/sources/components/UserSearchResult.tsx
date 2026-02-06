import React from 'react';
import { View, Text, TouchableOpacity, ActivityIndicator, Pressable, Platform } from 'react-native';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { UserProfile, getDisplayName } from '@/sync/friendTypes';
import { Avatar } from '@/components/Avatar';
import { t } from '@/text';
import { useRouter } from 'expo-router';

interface UserSearchResultProps {
    user: UserProfile;
    onAddFriend: () => void;
    isProcessing?: boolean;
}

export function UserSearchResult({ 
    user, 
    onAddFriend, 
    isProcessing = false 
}: UserSearchResultProps) {
    const router = useRouter();
    const { theme } = useUnistyles();
    const displayName = getDisplayName(user);
    const avatarUrl = user.avatar?.url || user.avatar?.path;
    
    // Determine button state based on relationship status
    const getButtonContent = () => {
        if (isProcessing) {
            return <ActivityIndicator size="small" color="white" />;
        }
        
        switch (user.status) {
            case 'friend':
                return <Text style={styles.buttonTextDisabled}>{t('friends.alreadyFriends')}</Text>;
            case 'pending':
                return <Text style={styles.buttonTextDisabled}>{t('friends.requestPending')}</Text>;
            case 'requested':
                return <Text style={styles.buttonTextDisabled}>{t('friends.requestSent')}</Text>;
            default:
                return <Text style={styles.buttonText}>{t('friends.addFriend')}</Text>;
        }
    };
    
    const isDisabled = isProcessing || user.status === 'friend' || user.status === 'pending' || user.status === 'requested';

    return (
        <Pressable 
            style={({ pressed, hovered }: any) => ([
                styles.container,
                Platform.OS === 'web' && (hovered || pressed) && { backgroundColor: theme.colors.chrome.listHoverBackground },
            ])}
            onPress={() => router.push(`/user/${user.id}`)}
        >
            <View style={styles.content}>
                <Avatar
                    id={user.id}
                    size={Platform.select({ web: 40, default: 48 })}
                    imageUrl={avatarUrl}
                    thumbhash={user.avatar?.thumbhash}
                />
                
                <View style={styles.info}>
                    <Text style={styles.name}>{displayName}</Text>
                    <Text style={styles.username}>@{user.username}</Text>
                </View>

                <TouchableOpacity
                    style={[
                        styles.button, 
                        isDisabled && styles.buttonDisabled
                    ]}
                    onPress={onAddFriend}
                    disabled={isDisabled}
                >
                    {getButtonContent()}
                </TouchableOpacity>
            </View>
        </Pressable>
    );
}

const styles = StyleSheet.create((theme) => ({
    container: {
        backgroundColor: Platform.select({ web: 'transparent', default: theme.colors.surface }),
        borderRadius: Platform.select({ web: 0, default: 12 }),
        marginHorizontal: Platform.select({ web: 0, default: 16 }),
        marginVertical: Platform.select({ web: 0, default: 4 }),
        ...(Platform.OS === 'web'
            ? {
                borderBottomWidth: StyleSheet.hairlineWidth,
                borderBottomColor: theme.colors.chrome.panelBorder,
            }
            : {
                shadowColor: '#000',
                shadowOffset: { width: 0, height: 1 },
                shadowOpacity: 0.05,
                shadowRadius: 2,
                elevation: 2,
            }),
    },
    content: {
        flexDirection: 'row',
        alignItems: 'center',
        padding: Platform.select({ web: 12, default: 16 }),
    },
    info: {
        flex: 1,
        marginLeft: Platform.select({ web: 12, default: 16 }),
    },
    name: {
        fontSize: Platform.select({ web: 13, default: 16 }),
        fontWeight: '600',
        color: theme.colors.text,
        marginBottom: 2,
    },
    username: {
        fontSize: Platform.select({ web: 12, default: 14 }),
        color: theme.colors.textSecondary,
    },
    button: {
        backgroundColor: theme.colors.button.primary.background,
        paddingHorizontal: Platform.select({ web: 10, default: 16 }),
        paddingVertical: Platform.select({ web: 6, default: 10 }),
        borderRadius: Platform.select({ web: 6, default: 8 }),
        minWidth: Platform.select({ web: 86, default: 100 }),
        alignItems: 'center',
    },
    buttonDisabled: {
        backgroundColor: Platform.select({ web: theme.colors.surfaceHighest, default: theme.colors.divider }),
    },
    buttonText: {
        color: theme.colors.button.primary.tint,
        fontSize: Platform.select({ web: 12, default: 14 }),
        fontWeight: '600',
    },
    buttonTextDisabled: {
        color: theme.colors.textSecondary,
        fontSize: Platform.select({ web: 12, default: 14 }),
        fontWeight: '500',
    },
}));
