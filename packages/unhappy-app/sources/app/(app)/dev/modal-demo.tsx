import React from 'react';
import { View, Text, StyleSheet, ScrollView, Platform } from 'react-native';
import { Item } from '@/components/Item';
import { ItemGroup } from '@/components/ItemGroup';
import { ItemList } from '@/components/ItemList';
import { Modal } from '@/modal';
import { Typography } from '@/constants/Typography';
import { RoundButton } from '@/components/RoundButton';

// Example custom modal component
function CustomContentModal({ onClose, title, message }: { onClose: () => void; title: string; message: string }) {
    return (
        <View style={styles.customModal}>
            <Text style={[styles.customModalTitle, Typography.default('semiBold')]}>{title}</Text>
            <Text style={[styles.customModalMessage, Typography.default()]}>{message}</Text>
            <View style={styles.customModalButtons}>
                <RoundButton
                    title="닫기"
                    onPress={onClose}
                    size="normal"
                />
            </View>
        </View>
    );
}

export default function ModalDemoScreen() {
    const [lastResult, setLastResult] = React.useState<string>('아직 작업이 없습니다');

    const showSimpleAlert = () => {
        Modal.alert('간단 알림', '간단한 알림 모달입니다.');
        setLastResult('간단 알림을 표시했습니다');
    };

    const showAlertWithMessage = () => {
        Modal.alert(
            '메시지 알림',
            '이 알림은 상세한 메시지를 표시합니다. 필요 시 여러 줄로 표시됩니다.'
        );
        setLastResult('메시지 알림을 표시했습니다');
    };

    const showAlertWithButtons = () => {
        Modal.alert(
            '다중 액션',
            '동작을 선택하세요:',
            [
                { text: '취소', style: 'cancel', onPress: () => setLastResult('취소 선택') },
                { text: '옵션 1', onPress: () => setLastResult('옵션 1 선택') },
                { text: '옵션 2', onPress: () => setLastResult('옵션 2 선택') }
            ]
        );
    };

    const showConfirm = async () => {
        const result = await Modal.confirm(
            '작업 확인',
            '계속 진행하시겠습니까?'
        );
        setLastResult(`확인 결과: ${result ? '확인' : '취소'}`);
    };

    const showDestructiveConfirm = async () => {
        const result = await Modal.confirm(
            '항목 삭제',
            '이 작업은 되돌릴 수 없습니다. 진행하시겠습니까?',
            {
                confirmText: '삭제',
                cancelText: '취소',
                destructive: true
            }
        );
        setLastResult(`삭제 결과: ${result ? '삭제됨' : '취소됨'}`);
    };

    const showCustomModal = () => {
        Modal.show({
            component: CustomContentModal,
            props: {
                title: '맞춤 모달',
                message: '완전히 커스텀된 모달 컴포넌트입니다. 원하는 내용을 넣을 수 있습니다.'
            }
        });
        setLastResult('맞춤 모달을 표시했습니다');
    };

    const showMultipleModals = async () => {
        Modal.alert('첫 번째 모달', '첫 번째 모달입니다');
        
        setTimeout(() => {
            Modal.alert('두 번째 모달', '이 모달은 첫 번째 다음에 표시됩니다');
        }, 1500);
        
        setLastResult('여러 모달을 표시했습니다');
    };

    return (
        <ScrollView style={styles.container}>
            <View style={styles.header}>
                <Text style={[styles.title, Typography.default('semiBold')]}>모달 데모</Text>
                <Text style={[styles.subtitle, Typography.default()]}>
                    플랫폼: {Platform.OS} ({Platform.OS === 'web' ? '커스텀 모달' : '기본 알림'})
                </Text>
            </View>

            <ItemList>
                <ItemGroup title="알림 모달">
                    <Item
                        title="간단 알림"
                        subtitle="제목만 있는 기본 알림"
                        onPress={showSimpleAlert}
                    />
                    <Item
                        title="메시지 알림"
                        subtitle="제목과 메시지를 함께 보여주는 알림"
                        onPress={showAlertWithMessage}
                    />
                    <Item
                        title="다중 버튼 알림"
                        subtitle="커스텀 버튼이 있는 알림"
                        onPress={showAlertWithButtons}
                    />
                </ItemGroup>

                <ItemGroup title="확인 모달">
                    <Item
                        title="기본 확인"
                        subtitle="간단한 예/아니오 확인"
                        onPress={showConfirm}
                    />
                    <Item
                        title="삭제 확인"
                        subtitle="파괴적 액션이 포함된 확인"
                        onPress={showDestructiveConfirm}
                        destructive
                    />
                </ItemGroup>

                <ItemGroup title="맞춤 모달">
                    <Item
                        title="맞춤 모달"
                        subtitle="완전 커스텀 모달 컴포넌트"
                        onPress={showCustomModal}
                    />
                    <Item
                        title="연속 모달"
                        subtitle="여러 모달을 순차적으로 표시"
                        onPress={showMultipleModals}
                    />
                </ItemGroup>

                <ItemGroup title="마지막 작업 결과">
                    <View style={styles.resultContainer}>
                        <Text style={[styles.resultText, Typography.default()]}>
                            {lastResult}
                        </Text>
                    </View>
                </ItemGroup>
            </ItemList>
        </ScrollView>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#F2F2F7'
    },
    header: {
        padding: 20,
        backgroundColor: '#fff',
        borderBottomWidth: StyleSheet.hairlineWidth,
        borderBottomColor: '#E5E5E7'
    },
    title: {
        fontSize: 24,
        marginBottom: 4
    },
    subtitle: {
        fontSize: 14,
        color: '#8E8E93'
    },
    resultContainer: {
        padding: 16,
        backgroundColor: '#fff'
    },
    resultText: {
        fontSize: 16,
        color: '#007AFF'
    },
    customModal: {
        backgroundColor: '#fff',
        borderRadius: 12,
        padding: 20,
        width: 300,
        alignItems: 'center'
    },
    customModalTitle: {
        fontSize: 20,
        marginBottom: 12
    },
    customModalMessage: {
        fontSize: 16,
        textAlign: 'center',
        marginBottom: 20,
        color: '#666'
    },
    customModalButtons: {
        width: '100%'
    }
});
