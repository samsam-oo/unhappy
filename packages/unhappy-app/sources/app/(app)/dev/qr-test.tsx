import React, { useState } from 'react';
import { View, Text, TextInput, ScrollView } from 'react-native';
import { QRCode } from '@/components/qr';
import { RoundButton } from '@/components/RoundButton';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { Typography } from '@/constants/Typography';

const stylesheet = StyleSheet.create((theme) => ({
    container: {
        flex: 1,
        backgroundColor: theme.colors.surface,
        padding: 20,
    },
    section: {
        marginBottom: 30,
    },
    sectionTitle: {
        fontSize: 18,
        fontWeight: 'bold',
        color: theme.colors.text,
        marginBottom: 15,
        ...Typography.default(),
    },
    input: {
        backgroundColor: theme.colors.input.background,
        padding: 12,
        borderRadius: 8,
        marginBottom: 15,
        color: theme.colors.input.text,
        fontSize: 16,
    },
    qrContainer: {
        alignItems: 'center',
        marginVertical: 15,
        padding: 15,
        backgroundColor: theme.colors.surfaceHigh,
        borderRadius: 12,
    },
    qrLabel: {
        fontSize: 14,
        color: theme.colors.textSecondary,
        marginBottom: 10,
        textAlign: 'center',
        ...Typography.default(),
    },
    row: {
        flexDirection: 'row',
        flexWrap: 'wrap',
        justifyContent: 'space-around',
    },
}));

export default function QRTest() {
    const { theme } = useUnistyles();
    const styles = stylesheet;
    const [customData, setCustomData] = useState('안녕하세요!');

    const testData = [
        { label: '단순 텍스트', data: '안녕하세요 QR 코드!' },
        { label: 'URL', data: 'https://github.com/samsam-oo/unhappy' },
        { label: '이메일', data: 'mailto:test@example.com' },
        { label: '전화', data: 'tel:+1234567890' },
        { label: 'WiFi', data: 'WIFI:T:WPA;S:MyNetwork;P:password123;H:false;;' },
    ];

    const sizes = [100, 150, 200, 250];
    const errorLevels: Array<'low' | 'medium' | 'quartile' | 'high'> = ['low', 'medium', 'quartile', 'high'];

    return (
        <ScrollView style={styles.container}>
            {/* Custom QR Code */}
            <View style={styles.section}>
                <Text style={styles.sectionTitle}>사용자 지정 QR 코드</Text>
                <TextInput
                    style={styles.input}
                    value={customData}
                    onChangeText={setCustomData}
                    placeholder="여기에 데이터를 입력하세요"
                    placeholderTextColor={theme.colors.input.placeholder}
                    multiline
                />
                <View style={styles.qrContainer}>
                    <Text style={styles.qrLabel}>사용자 데이터</Text>
                    <QRCode data={customData} size={200} />
                </View>
            </View>

            {/* 미리 정의된 예시 */}
            <View style={styles.section}>
                <Text style={styles.sectionTitle}>QR 코드 예시</Text>
                {testData.map((item, index) => (
                    <View key={index} style={styles.qrContainer}>
                        <Text style={styles.qrLabel}>{item.label}: {item.data}</Text>
                        <QRCode data={item.data} size={180} />
                    </View>
                ))}
            </View>

            {/* 다양한 크기 */}
            <View style={styles.section}>
                <Text style={styles.sectionTitle}>다양한 크기</Text>
                <View style={styles.row}>
                    {sizes.map((size) => (
                        <View key={size} style={[styles.qrContainer, { margin: 5 }]}>
                            <Text style={styles.qrLabel}>{size}x{size}</Text>
                            <QRCode data="크기 테스트" size={size} />
                        </View>
                    ))}
                </View>
            </View>

            {/* 오류 보정 레벨 */}
            <View style={styles.section}>
                <Text style={styles.sectionTitle}>오류 보정 레벨</Text>
                <View style={styles.row}>
                    {errorLevels.map((level) => (
                        <View key={level} style={[styles.qrContainer, { margin: 5 }]}>
                            <Text style={styles.qrLabel}>{level.toUpperCase()}</Text>
                            <QRCode 
                                data="오류 보정 테스트(긴 텍스트로 차이 확인)"
                                size={150} 
                                errorCorrectionLevel={level}
                            />
                        </View>
                    ))}
                </View>
            </View>

            {/* 색상 변형 */}
            <View style={styles.section}>
                <Text style={styles.sectionTitle}>색상 변형</Text>
                <View style={styles.row}>
                    <View style={[styles.qrContainer, { margin: 5 }]}>
                        <Text style={styles.qrLabel}>흰색 바탕 파란색</Text>
                        <QRCode 
                            data="파란색 QR 코드" 
                            size={150} 
                            foregroundColor="#0066CC"
                            backgroundColor="#FFFFFF"
                        />
                    </View>
                    <View style={[styles.qrContainer, { margin: 5 }]}>
                        <Text style={styles.qrLabel}>어두운 배경 흰색</Text>
                        <QRCode 
                            data="흰색 QR 코드" 
                            size={150} 
                            foregroundColor="#FFFFFF"
                            backgroundColor="#333333"
                        />
                    </View>
                </View>
            </View>

            {/* 긴 텍스트 테스트 */}
            <View style={styles.section}>
                <Text style={styles.sectionTitle}>긴 텍스트 처리</Text>
                <View style={styles.qrContainer}>
                    <Text style={styles.qrLabel}>여러 줄로 긴 텍스트</Text>
                    <QRCode 
                        data="이것은 많은 양의 데이터를 인코딩하여 QR 코드 컴포넌트가 얼마나 처리할 수 있는지 테스트하는 긴 텍스트입니다. QR 코드는 가독성과 스캔 가능성을 유지하면서 모든 텍스트를 맞추기 위해 버전을 자동으로 조정합니다."
                        size={250}
                        errorCorrectionLevel="high"
                    />
                </View>
            </View>
        </ScrollView>
    );
}
