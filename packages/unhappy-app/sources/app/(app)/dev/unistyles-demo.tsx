import React, { useState } from 'react';
import { View, Text, ScrollView, Pressable, Switch, Dimensions } from 'react-native';
import { StyleSheet, UnistylesRuntime, useUnistyles } from 'react-native-unistyles';
import { Ionicons } from '@/icons/vector-icons';

const { width: screenWidth } = Dimensions.get('window');

const stylesheet = StyleSheet.create((theme, runtime) => ({
    container: {
        flex: 1,
        backgroundColor: theme.colors.surface,
    },
    scrollContent: {
        padding: 16,
        paddingBottom: 32,
    },
    section: {
        marginBottom: 24,
        backgroundColor: theme.colors.surface,
        borderRadius: 12,
        padding: 16,
        shadowColor: '#000',
        shadowOffset: {
            width: 0,
            height: 2,
        },
        shadowOpacity: 0.1,
        shadowRadius: 3.84,
        elevation: 5,
    },
    sectionTitle: {
        fontSize: 20,
        fontWeight: 'bold',
        marginBottom: 12,
        color: '#333',
    },
    themeCard: {
        padding: 16,
        borderRadius: 8,
        marginBottom: 12,
        backgroundColor: theme.colors.surface,
        borderWidth: 2,
        borderColor: theme.colors.surface,
    },
    themeText: {
        color: 'white',
        fontSize: 16,
        fontWeight: '600',
        textAlign: 'center',
    },
    breakpointBox: {
        padding: 12,
        margin: 4,
        borderRadius: 8,
        backgroundColor: {
            xs: '#FF6B6B',
            sm: '#4ECDC4',
            md: '#45B7D1',
            lg: '#96CEB4',
            xl: '#FECA57',
        },
        minHeight: 60,
        justifyContent: 'center',
        alignItems: 'center',
    },
    breakpointText: {
        color: 'white',
        fontWeight: 'bold',
        fontSize: {
            xs: 12,
            sm: 14,
            md: 16,
            lg: 18,
            xl: 20,
        },
    },
    responsiveContainer: {
        flexDirection: {
            xs: 'column',
            md: 'row',
        },
    },
    responsiveBox: {
        flex: 1,
        backgroundColor: theme.colors.surface,  // 기본색으로 변경 예정
        padding: 16,
        borderRadius: 8,
        minHeight: 80,
        justifyContent: 'center',
        alignItems: 'center',
    },
    orientationBox: {
        backgroundColor: {
            portrait: '#E74C3C',
            landscape: '#2ECC71',
        },
        padding: 20,
        borderRadius: 8,
        alignItems: 'center',
        justifyContent: 'center',
        minHeight: 80,
    },
    orientationText: {
        color: 'white',
        fontSize: 16,
        fontWeight: 'bold',
    },
    runtimeBox: {
        backgroundColor: '#9B59B6',
        padding: 12,
        borderRadius: 8,
        marginBottom: 8,
    },
    runtimeText: {
        color: 'white',
        fontSize: 14,
        fontFamily: 'monospace',
    },
    themeButton: {
        backgroundColor: theme.colors.surface,  // 기본색으로 변경 예정
        padding: 12,
        borderRadius: 8,
        marginHorizontal: 4,
        minWidth: 80,
        alignItems: 'center',
    },
    themeButtonText: {
        color: 'white',
        fontWeight: '600',
    },
    switchContainer: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        marginBottom: 12,
    },
    adaptiveBox: {
        backgroundColor: theme.colors.surface,  // 기본색으로 변경 예정
        padding: {
            xs: 8,
            sm: 12,
            md: 16,
            lg: 20,
            xl: 24,
        },
        borderRadius: {
            xs: 4,
            sm: 6,
            md: 8,
            lg: 10,
            xl: 12,
        },
        marginBottom: 8,
    },
    adaptiveText: {
        color: 'white',
        fontSize: {
            xs: 12,
            sm: 14,
            md: 16,
            lg: 18,
            xl: 20,
        },
        textAlign: 'center',
    },
}));

export default function UnistylesDemo() {
    const { theme, rt } = useUnistyles();
    const styles = stylesheet;
    const [showRuntimeInfo, setShowRuntimeInfo] = useState(true);

    const switchTheme = (themeName: 'light' | 'dark') => {  
        UnistylesRuntime.setTheme(themeName);
    };

    const toggleColorScheme = () => {
        // React Native에서는 색상 스킴이 보통 시스템에서 제어됩니다.
        console.log('컬러 스킴 토글 요청됨 - 일반적으로 시스템에서 제어됩니다');
    };

    return (
        <View style={styles.container}>
            <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.scrollContent}>
                {/* 테마 데모 */}
                <View style={styles.section}>
                    <Text style={styles.sectionTitle}>🎨 테마 시스템</Text>
                    <View style={styles.themeCard}>
                        <Text style={styles.themeText}>
                            현재 테마: {rt.themeName}
                        </Text>
                        <Text style={[styles.themeText, { fontSize: 14, opacity: 0.8 }]}>
                            기본색: {theme.colors.surface}  // 기본색은 추후 조정 예정
                        </Text>
                    </View>

                    <View style={{ flexDirection: 'row', justifyContent: 'center', gap: 8 }}>
                        <Pressable
                            style={styles.themeButton}
                            onPress={() => switchTheme('light')}
                        >
                            <Text style={styles.themeButtonText}>라이트</Text>
                        </Pressable>
                        <Pressable
                            style={styles.themeButton}
                            onPress={() => switchTheme('dark')}
                        >
                            <Text style={styles.themeButtonText}>다크</Text>
                        </Pressable>
                    </View>
                </View>

                {/* 반응형 중단점 데모 */}
                <View style={styles.section}>
                    <Text style={styles.sectionTitle}>📱 반응형 중단점</Text>
                    <Text style={{ marginBottom: 12, color: '#666' }}>
                        현재: {rt.breakpoint} ({screenWidth}px)
                    </Text>

                    <View style={styles.breakpointBox}>
                        <Text style={styles.breakpointText}>
                            활성 중단점: {rt.breakpoint}
                        </Text>
                        <Text style={[styles.breakpointText, { fontSize: 12, opacity: 0.8 }]}>
                            화면 너비: {rt.screen.width}px
                        </Text>
                    </View>

                    <View style={styles.responsiveContainer}>
                        <View style={styles.responsiveBox}>
                            <Text style={{ color: 'white', fontWeight: 'bold' }}>박스 1</Text>
                        </View>
                        <View style={styles.responsiveBox}>
                            <Text style={{ color: 'white', fontWeight: 'bold' }}>박스 2</Text>
                        </View>
                    </View>
                </View>

                {/* 화면 방향 데모 */}
                <View style={styles.section}>
                    <Text style={styles.sectionTitle}>🔄 방향 스타일</Text>
                    <View style={styles.orientationBox}>
                        <Ionicons
                            name={rt.isPortrait ? 'phone-portrait' : 'phone-landscape'}
                            size={24}
                            color="white"
                        />
                        <Text style={styles.orientationText}>
                            {rt.isPortrait ? '세로 모드' : '가로 모드'}
                        </Text>
                    </View>
                </View>

                {/* Adaptive Components */}
                <View style={styles.section}>
                    <Text style={styles.sectionTitle}>🎯 적응형 컴포넌트</Text>
                    <Text style={{ marginBottom: 12, color: '#666' }}>
                        패딩과 둥근 모서리가 화면 크기에 맞춰 조정됩니다
                    </Text>

                    {['Tiny', 'Small', 'Medium', 'Large', 'Extra Large'].map((size, index) => (
                        <View key={size} style={styles.adaptiveBox}>
                            <Text style={styles.adaptiveText}>
                                {size} - {rt.breakpoint}에 적응
                            </Text>
                        </View>
                    ))}
                </View>

                {/* Runtime Information */}
                <View style={styles.section}>
                    <Text style={styles.sectionTitle}>⚙️ 런타임 정보</Text>

                    <View style={styles.switchContainer}>
                            <Text style={{ fontSize: 16, color: '#333' }}>런타임 상세 보기</Text>
                        <Switch
                            value={showRuntimeInfo}
                            onValueChange={setShowRuntimeInfo}
                        />
                    </View>

                    {showRuntimeInfo && (
                        <>
                            <View style={styles.runtimeBox}>
                                <Text style={styles.runtimeText}>
                                    테마: {rt.themeName}
                                </Text>
                            </View>
                            <View style={styles.runtimeBox}>
                                <Text style={styles.runtimeText}>
                                    중단점: {rt.breakpoint}
                                </Text>
                            </View>
                            <View style={styles.runtimeBox}>
                                <Text style={styles.runtimeText}>
                                    화면: {rt.screen.width} × {rt.screen.height}
                                </Text>
                            </View>
                            <View style={styles.runtimeBox}>
                                <Text style={styles.runtimeText}>
                                    방향: {rt.isPortrait ? '세로 모드' : '가로 모드'}
                                </Text>
                            </View>
                            <View style={styles.runtimeBox}>
                                <Text style={styles.runtimeText}>
                                    컬러 스킴: {rt.colorScheme}
                                </Text>
                            </View>
                            <View style={styles.runtimeBox}>
                                <Text style={styles.runtimeText}>
                                    콘텐츠 크기: {rt.contentSizeCategory}
                                </Text>
                            </View>
                            <View style={styles.runtimeBox}>
                                <Text style={styles.runtimeText}>
                                    다이내믹 아일랜드 존재: {rt.insets.top > 50 ? '있음' : '없음'}
                                </Text>
                            </View>
                            <View style={styles.runtimeBox}>
                                <Text style={styles.runtimeText}>
                                    안전 여백: 상:{rt.insets.top} 하:{rt.insets.bottom} 좌:{rt.insets.left} 우:{rt.insets.right}
                                </Text>
                            </View>
                        </>
                    )}

                    <Pressable
                        style={[styles.themeButton, { marginTop: 12 }]}
                        onPress={toggleColorScheme}
                    >
                        <Text style={styles.themeButtonText}>
                            컬러 스킴 전환 ({rt.colorScheme})
                        </Text>
                    </Pressable>
                </View>

                {/* Color Scheme Demo */}
                <View style={styles.section}>
                    <Text style={styles.sectionTitle}>🌙 색상 스킴</Text>
                    <View style={{
                        backgroundColor: rt.colorScheme === 'dark' ? '#2C3E50' : '#ECF0F1',
                        padding: 16,
                        borderRadius: 8,
                    }}>
                            <Text style={{
                                color: rt.colorScheme === 'dark' ? 'white' : 'black',
                                textAlign: 'center',
                                fontSize: 16,
                                fontWeight: '600'
                            }}>
                                현재 색상 스킴: {rt.colorScheme}
                            </Text>
                            <Text style={{
                            color: rt.colorScheme === 'dark' ? '#BDC3C7' : '#7F8C8D',
                            textAlign: 'center',
                            fontSize: 14,
                            marginTop: 4
                        }}>
                                이 박스는 시스템 색상 스킴에 맞춰 조정됩니다
                            </Text>
                        </View>
                    </View>

                {/* Performance Note */}
                <View style={[styles.section, { backgroundColor: '#FFF3CD', borderColor: '#FFEAA7', borderWidth: 1 }]}>
                    <Text style={[styles.sectionTitle, { color: '#856404' }]}>⚡ 성능 참고</Text>
                    <Text style={{ color: '#856404', lineHeight: 20 }}>
                        Unistyles는 빌드 타임에 스타일을 컴파일하고 런타임 최적화를 제공합니다.
                        여기서 보는 모든 반응형 기능은 네이티브 브릿지 통합 덕분에 성능 저하 없이 동작합니다.
                    </Text>
                </View>
            </ScrollView>
        </View>
    );
}
