import * as React from 'react';
import { ScrollView, View, Text, StyleSheet } from 'react-native';
import { Typography } from '@/constants/Typography';
import { Item } from '@/components/Item';
import { ItemGroup } from '@/components/ItemGroup';

const TextSample = ({ title, style, text = '빠른 갈색 여우가 느긋한 개를 뛰어넘습니다' }: { title: string; style: any; text?: string }) => (
    <View style={styles.sampleContainer}>
        <Text style={styles.sampleTitle}>{title}</Text>
        <Text style={[{ fontSize: 16 }, style]}>{text}</Text>
    </View>
);

const CodeSample = ({ title, style }: { title: string; style: any }) => (
    <View style={styles.sampleContainer}>
        <Text style={styles.sampleTitle}>{title}</Text>
        <Text style={[{ fontSize: 14 }, style]}>
            {`const greeting = "안녕하세요, 세계!";\nconsole.log(greeting);`}
        </Text>
    </View>
);

export default function TypographyScreen() {
    return (
        <ScrollView style={styles.container}>
            <View style={styles.content}>
                {/* IBM Plex Sans (Default) */}
                <View style={styles.section}>
                    <Text style={styles.sectionTitle}>IBM Plex Sans (기본)</Text>
                    
                    <TextSample 
                        title="일반 (400)" 
                        style={Typography.default()}
                    />
                    
                    <TextSample 
                        title="이탤릭" 
                        style={Typography.default('italic')}
                    />
                    
                    <TextSample 
                        title="세미볼드 (600)" 
                        style={Typography.default('semiBold')}
                    />
                </View>

                {/* IBM Plex Mono */}
                <View style={styles.section}>
                    <Text style={styles.sectionTitle}>IBM Plex Mono</Text>
                    
                    <CodeSample 
                        title="일반 (400)" 
                        style={Typography.mono()}
                    />
                    
                    <CodeSample 
                        title="이탤릭" 
                        style={Typography.mono('italic')}
                    />
                    
                    <CodeSample 
                        title="세미볼드 (600)" 
                        style={Typography.mono('semiBold')}
                    />
                </View>

                {/* Bricolage Grotesque (Logo) */}
                <View style={styles.section}>
                    <Text style={styles.sectionTitle}>Bricolage Grotesque (로고)</Text>
                    
                    <TextSample 
                        title="볼드 (700) - 로고 전용" 
                        style={{ fontSize: 28, ...Typography.logo() }}
                        text="Unhappy"
                    />
                    <Text style={styles.note}>
                        참고: 이 폰트는 앱 로고와 브랜딩에만 사용해야 합니다
                    </Text>
                </View>

                {/* Font Sizes */}
                <View style={styles.section}>
                        <Text style={styles.sectionTitle}>폰트 크기 스케일</Text>
                    
                    {[12, 14, 16, 18, 20, 24, 28, 32, 36].map(size => (
                        <View key={size} style={styles.fontSizeItem}>
                            <Text style={{ fontSize: size, ...Typography.default() }}>
                                {size}px - 빠른 갈색 여우
                            </Text>
                        </View>
                    ))}
                </View>

                {/* Text in Components */}
                <View style={styles.section}>
                    <Text style={styles.sectionTitle}>컴포넌트의 타이포그래피</Text>
                    
                    <ItemGroup title="목록 항목 타이포그래피">
                        <Item 
                            title="기본 제목 (17px 일반)"
                            subtitle="기본 부제목 (15px 일반, #8E8E93)"
                            detail="세부"
                        />
                        <Item 
                            title="커스텀 제목 스타일"
                            titleStyle={{ ...Typography.default('semiBold') }}
                            subtitle="제목에 세미볼드를 사용"
                        />
                        <Item 
                            title="고정폭 상세"
                            detail="v1.0.0"
                            detailStyle={{ ...Typography.mono() }}
                        />
                    </ItemGroup>
                </View>

                {/* Usage Examples */}
                <View style={styles.section}>
                    <Text style={styles.sectionTitle}>사용 예시</Text>
                    
                    <View style={styles.codeBlock}>
                        <Text style={{ ...Typography.mono(), fontSize: 12 }}>
{`// 기본 타이포그래피 (IBM Plex Sans)
<Text style={{ fontSize: 16, ...Typography.default() }}>일반</Text>
<Text style={{ fontSize: 16, ...Typography.default('semiBold') }}>볼드</Text>

// 고정폭 타이포그래피 (IBM Plex Mono)
<Text style={{ fontSize: 14, ...Typography.mono() }}>코드</Text>

// 로고 타이포그래피 (Bricolage Grotesque)
<Text style={{ fontSize: 28, ...Typography.logo() }}>로고</Text>`}
                        </Text>
                    </View>
                </View>
            </View>
        </ScrollView>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: 'white',
    },
    content: {
        padding: 16,
    },
    sampleContainer: {
        marginBottom: 24,
    },
    sampleTitle: {
        fontSize: 14,
        color: 'rgba(0,0,0,0.5)',
        marginBottom: 4,
    },
    section: {
        marginBottom: 32,
    },
    sectionTitle: {
        fontSize: 20,
        fontWeight: '600',
        marginBottom: 16,
    },
    note: {
        fontSize: 14,
        color: 'rgba(0,0,0,0.5)',
        marginTop: 8,
    },
    fontSizeItem: {
        marginBottom: 12,
    },
    codeBlock: {
        backgroundColor: '#f0f0f0',
        padding: 16,
        borderRadius: 8,
    },
});
