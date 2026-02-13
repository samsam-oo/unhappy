import * as React from 'react';
import { View, Text, ScrollView } from 'react-native';
import { MultiTextInput, KeyPressEvent } from '@/components/MultiTextInput';
import { Typography } from '@/constants/Typography';

export default function MultiTextInputDemo() {
    const [text1, setText1] = React.useState('');
    const [text2, setText2] = React.useState('이 텍스트는 컴포넌트가 기존 내용을 어떻게 처리하는지 보여주는 예시입니다.');
    const [text3, setText3] = React.useState('');
    const [text4, setText4] = React.useState('');
    const [text5, setText5] = React.useState('');
    const [lastKey, setLastKey] = React.useState<string>('');

    return (
        <ScrollView style={{ flex: 1, backgroundColor: 'white' }}>
            <View style={{ padding: 16, gap: 24 }}>
                <View>
                    <Text style={{ 
                        fontSize: 16, 
                        marginBottom: 8,
                        ...Typography.default('semiBold')
                    }}>
                        기본 사용법
                    </Text>
                    <Text style={{ 
                        fontSize: 14, 
                        color: '#666',
                        marginBottom: 12,
                        ...Typography.default()
                    }}>
                        기본 최대 높이(120px)가 적용된 다중 줄 텍스트 입력
                    </Text>
                    <View style={{
                        backgroundColor: '#f5f5f5',
                        borderRadius: 8,
                        padding: 12,
                    }}>
                        <MultiTextInput
                            value={text1}
                            onChangeText={setText1}
                        placeholder="여기에 입력하세요..."
                        />
                    </View>
                    <Text style={{ 
                        fontSize: 12, 
                        color: '#999',
                        marginTop: 4,
                        ...Typography.default()
                    }}>
                        글자 수: {text1.length}
                    </Text>
                </View>

                <View>
                    <Text style={{ 
                        fontSize: 16, 
                        marginBottom: 8,
                        ...Typography.default('semiBold')
                    }}>
                        초기값 예시
                    </Text>
                    <Text style={{ 
                        fontSize: 14, 
                        color: '#666',
                        marginBottom: 12,
                        ...Typography.default()
                    }}>
                        미리 채워진 텍스트가 있습니다
                    </Text>
                    <View style={{
                        backgroundColor: '#f0f7ff',
                        borderRadius: 8,
                        padding: 12,
                    }}>
                        <MultiTextInput
                            value={text2}
                            onChangeText={setText2}
                        placeholder="이미 텍스트가 있어 표시되지 않습니다"
                        />
                    </View>
                    <Text style={{ 
                        fontSize: 12, 
                        color: '#999',
                        marginTop: 4,
                        ...Typography.default()
                    }}>
                        글자 수: {text2.length}
                    </Text>
                </View>

                <View>
                    <Text style={{ 
                        fontSize: 16, 
                        marginBottom: 8,
                        ...Typography.default('semiBold')
                    }}>
                        제한 높이 (60px)
                    </Text>
                    <Text style={{ 
                        fontSize: 14, 
                        color: '#666',
                        marginBottom: 12,
                        ...Typography.default()
                    }}>
                        이 입력창은 최대 높이가 낮아 더 빨리 스크롤됩니다
                    </Text>
                    <View style={{
                        backgroundColor: '#fff5f5',
                        borderRadius: 8,
                        padding: 12,
                    }}>
                        <MultiTextInput
                            value={text3}
                            onChangeText={setText3}
                        placeholder="여러 줄을 입력해 스크롤을 확인해 보세요..."
                            maxHeight={60}
                        />
                    </View>
                    <Text style={{ 
                        fontSize: 12, 
                        color: '#999',
                        marginTop: 4,
                        ...Typography.default()
                    }}>
                        글자 수: {text3.length} | 최대 높이: 60px
                    </Text>
                </View>

                <View>
                    <Text style={{ 
                        fontSize: 16, 
                        marginBottom: 8,
                        ...Typography.default('semiBold')
                    }}>
                    더 큰 높이 (200px)
                    </Text>
                    <Text style={{ 
                        fontSize: 14, 
                        color: '#666',
                        marginBottom: 12,
                        ...Typography.default()
                    }}>
                        이 입력창은 더 큰 높이로 확장되어 스크롤이 늦게 발생합니다
                    </Text>
                    <View style={{
                        backgroundColor: '#f5fff5',
                        borderRadius: 8,
                        padding: 12,
                    }}>
                        <MultiTextInput
                            value={text4}
                            onChangeText={setText4}
                        placeholder="더 많은 텍스트를 작성해도 스크롤이 늦게 시작됩니다..."
                            maxHeight={200}
                        />
                    </View>
                    <Text style={{ 
                        fontSize: 12, 
                        color: '#999',
                        marginTop: 4,
                        ...Typography.default()
                    }}>
                        글자 수: {text4.length} | 최대 높이: 200px
                    </Text>
                </View>

                <View>
                    <Text style={{ 
                        fontSize: 16, 
                        marginBottom: 8,
                        ...Typography.default('semiBold')
                    }}>
                        키보드 제어 예시
                    </Text>
                    <Text style={{ 
                        fontSize: 14, 
                        color: '#666',
                        marginBottom: 12,
                        ...Typography.default()
                    }}>
                        엔터: 전송(필드 초기화), 이스케이프: 입력 취소, 화살표 키 사용 가능
                    </Text>
                    <View style={{
                        backgroundColor: '#fff0f5',
                        borderRadius: 8,
                        padding: 12,
                    }}>
                        <MultiTextInput
                            value={text5}
                            onChangeText={setText5}
                        placeholder="엔터, 이스케이프, 방향키를 눌러 이동하세요"
                            onKeyPress={(event: KeyPressEvent): boolean => {
                                setLastKey(`${event.key}${event.shiftKey ? ' + Shift' : ''}`);
                                
                                if (event.key === 'Enter' && !event.shiftKey) {
                                    if (text5.trim()) {
                                        // Simulate submit
                                        setText5('');
                                        return true;
                                    }
                                } else if (event.key === 'Escape') {
                                    setText5('');
                                    return true;
                                }
                                
                                return false; // Let arrow keys and other keys work normally
                            }}
                        />
                    </View>
                    <Text style={{ 
                        fontSize: 12, 
                        color: '#999',
                        marginTop: 4,
                        ...Typography.default()
                    }}>
                        마지막 키: {lastKey || '없음'} | 글자 수: {text5.length}
                    </Text>
                </View>

                <View style={{ height: 100 }} />
            </View>
        </ScrollView>
    );
}
