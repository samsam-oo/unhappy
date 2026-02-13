import * as React from 'react';
import { ScrollView, View, Text, StyleSheet } from 'react-native';
import { Typography } from '@/constants/Typography';

const ColorSwatch = ({ name, color, textColor = '#000' }: { name: string; color: string; textColor?: string }) => (
    <View style={styles.swatchContainer}>
        <View 
            style={[styles.swatch, { backgroundColor: color }]}
        >
            <Text style={{ color: textColor, ...Typography.default('semiBold') }}>{name}</Text>
            <Text style={{ color: textColor, ...Typography.mono(), fontSize: 12 }}>{color}</Text>
        </View>
    </View>
);

const ColorPair = ({ name, bg, text }: { name: string; bg: string; text: string }) => (
    <View style={styles.swatchContainer}>
        <View 
            style={[styles.swatch, { backgroundColor: bg }]}
        >
            <Text style={{ color: text, ...Typography.default('semiBold'), marginBottom: 4 }}>{name}</Text>
            <Text style={{ color: text, ...Typography.mono(), fontSize: 12 }}>BG: {bg}</Text>
            <Text style={{ color: text, ...Typography.mono(), fontSize: 12 }}>Text: {text}</Text>
        </View>
    </View>
);

export default function ColorsScreen() {
    return (
        <ScrollView style={styles.container}>
                <View style={styles.content}>
                {/* iOS System Colors */}
                <View style={styles.section}>
                    <Text style={[styles.sectionTitle, Typography.default('semiBold')]}>
                        iOS 시스템 색상
                    </Text>
                    
                    <ColorSwatch name="파랑 (기본 강조색)" color="#007AFF" textColor="#FFF" />
                    <ColorSwatch name="녹색 (성공)" color="#34C759" textColor="#FFF" />
                    <ColorSwatch name="주황 (경고)" color="#FF9500" textColor="#FFF" />
                    <ColorSwatch name="빨강 (파괴)" color="#FF3B30" textColor="#FFF" />
                    <ColorSwatch name="보라" color="#AF52DE" textColor="#FFF" />
                    <ColorSwatch name="분홍" color="#FF2D55" textColor="#FFF" />
                    <ColorSwatch name="남색" color="#5856D6" textColor="#FFF" />
                    <ColorSwatch name="청록" color="#5AC8FA" textColor="#FFF" />
                    <ColorSwatch name="노랑" color="#FFCC00" textColor="#000" />
                </View>

                {/* Gray Scale */}
                <View style={styles.section}>
                    <Text style={[styles.sectionTitle, Typography.default('semiBold')]}>
                        회색 스케일
                    </Text>
                    
                    <ColorSwatch name="주 라벨" color="#000000" textColor="#FFF" />
                    <ColorSwatch name="보조 라벨" color="#3C3C43" textColor="#FFF" />
                    <ColorSwatch name="3차 라벨" color="#3C3C43" textColor="#FFF" />
                    <ColorSwatch name="4차 라벨" color="#3C3C43" textColor="#FFF" />
                    <ColorSwatch name="플레이스홀더 텍스트" color="#C7C7CC" />
                    <ColorSwatch name="구분선" color="#C6C6C8" />
                    <ColorSwatch name="불투명 구분선" color="#C6C6C8" />
                    <ColorSwatch name="시스템 회색" color="#8E8E93" textColor="#FFF" />
                    <ColorSwatch name="시스템 회색 2" color="#AEAEB2" />
                    <ColorSwatch name="시스템 회색 3" color="#C7C7CC" />
                    <ColorSwatch name="시스템 회색 4" color="#D1D1D6" />
                    <ColorSwatch name="시스템 회색 5" color="#E5E5EA" />
                    <ColorSwatch name="시스템 회색 6" color="#F2F2F7" />
                </View>

                {/* Backgrounds */}
                <View style={styles.section}>
                    <Text style={[styles.sectionTitle, Typography.default('semiBold')]}>
                        배경색
                    </Text>
                    
                    <ColorSwatch name="시스템 배경" color="#FFFFFF" />
                    <ColorSwatch name="보조 시스템 배경" color="#F2F2F7" />
                    <ColorSwatch name="3차 시스템 배경" color="#FFFFFF" />
                    <ColorSwatch name="그룹화 시스템 배경" color="#F2F2F7" />
                    <ColorSwatch name="보조 그룹화 시스템 배경" color="#FFFFFF" />
                </View>

                {/* Component Colors */}
                <View style={styles.section}>
                    <Text style={[styles.sectionTitle, Typography.default('semiBold')]}>
                        컴포넌트 색상
                    </Text>
                    
                    <ColorPair name="리스트 항목" bg="#FFFFFF" text="#000000" />
                    <ColorPair name="리스트 항목 (눌림)" bg="#D1D1D6" text="#000000" />
                    <ColorPair name="리스트 항목 (선택됨)" bg="#007AFF" text="#FFFFFF" />
                    <ColorPair name="리스트 항목 (경고)" bg="#FFFFFF" text="#FF3B30" />
                    <ColorPair name="리스트 그룹 헤더" bg="transparent" text="#8E8E93" />
                </View>

                {/* Usage in Code */}
                <View style={styles.section}>
                    <Text style={[styles.sectionTitle, Typography.default('semiBold')]}>
                        사용 예시
                    </Text>
                    
                    <View style={styles.codeBlock}>
                        <Text style={{ ...Typography.mono(), fontSize: 12 }}>
{`// iOS System Colors
const tintColor = '#007AFF';
const successColor = '#34C759';
const warningColor = '#FF9500';
const destructiveColor = '#FF3B30';

// Gray Scale
const labelColor = '#000000';
const secondaryLabel = '#8E8E93';
const separator = '#C6C6C8';
const systemGray = '#8E8E93';

// Backgrounds
const background = '#FFFFFF';
const groupedBackground = '#F2F2F7';`}
                        </Text>
                    </View>
                </View>

                {/* Tailwind/NativeWind Classes */}
                <View style={styles.section}>
                    <Text style={[styles.sectionTitle, Typography.default('semiBold')]}>
                        NativeWind 클래스
                    </Text>
                    
                    <View style={styles.colorGrid}>
                        <View style={[styles.colorItem, { backgroundColor: '#3b82f6' }]}>
                            <Text style={styles.colorItemTextWhite}>bg-blue-500</Text>
                        </View>
                        <View style={[styles.colorItem, { backgroundColor: '#10b981' }]}>
                            <Text style={styles.colorItemTextWhite}>bg-green-500</Text>
                        </View>
                        <View style={[styles.colorItem, { backgroundColor: '#ef4444' }]}>
                            <Text style={styles.colorItemTextWhite}>bg-red-500</Text>
                        </View>
                        <View style={[styles.colorItem, { backgroundColor: '#f3f4f6' }]}>
                            <Text style={styles.colorItemTextDark}>bg-gray-100</Text>
                        </View>
                        <View style={[styles.colorItem, { backgroundColor: '#e5e7eb' }]}>
                            <Text style={styles.colorItemTextDark}>bg-gray-200</Text>
                        </View>
                        <View style={[styles.colorItem, { backgroundColor: '#1f2937' }]}>
                            <Text style={styles.colorItemTextWhite}>bg-gray-800</Text>
                        </View>
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
    section: {
        marginBottom: 32,
    },
    sectionTitle: {
        fontSize: 20,
        marginBottom: 16,
    },
    swatchContainer: {
        marginBottom: 16,
    },
    swatch: {
        borderRadius: 8,
        padding: 16,
        marginBottom: 8,
    },
    codeBlock: {
        backgroundColor: '#f0f0f0',
        padding: 16,
        borderRadius: 8,
    },
    colorGrid: {
        gap: 8,
    },
    colorItem: {
        padding: 12,
        borderRadius: 8,
        marginBottom: 8,
    },
    colorItemTextWhite: {
        color: 'white',
    },
    colorItemTextDark: {
        color: '#111827',
    },
});
