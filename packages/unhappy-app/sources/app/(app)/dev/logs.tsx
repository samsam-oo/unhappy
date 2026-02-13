import * as React from 'react';
import { View, Text, FlatList, Pressable } from 'react-native';
import { Ionicons } from '@/icons/vector-icons';
import { log } from '@/log';
import { ItemGroup } from '@/components/ItemGroup';
import { ItemList } from '@/components/ItemList';
import { Item } from '@/components/Item';
import * as Clipboard from 'expo-clipboard';
import { Modal } from '@/modal';

export default function LogsScreen() {
    const [logs, setLogs] = React.useState<string[]>([]);
    const flatListRef = React.useRef<FlatList>(null);

    // Subscribe to log changes
    React.useEffect(() => {
        // Add some sample logs if empty (for demo purposes)
        if (log.getCount() === 0) {
            log.log('로거 초기화 완료');
            log.log('디버그 메시지 예시');
            log.log('앱 실행이 정상적으로 시작되었습니다');
        }

        // Initial load
        setLogs(log.getLogs());

        // Subscribe to changes
        const unsubscribe = log.onChange(() => {
            setLogs(log.getLogs());
        });

        return unsubscribe;
    }, []);

    // Auto-scroll to bottom when new logs arrive
    React.useEffect(() => {
        if (logs.length > 0) {
            setTimeout(() => {
                flatListRef.current?.scrollToEnd({ animated: false });
            }, 100);
        }
    }, [logs.length]);

    const handleClear = async () => {
        const confirmed = await Modal.confirm(
            '로그 삭제',
            '모든 로그를 삭제하시겠습니까?',
            { confirmText: '삭제', destructive: true }
        );
        if (confirmed) {
            log.clear();
        }
    };

    const handleCopyAll = async () => {
        if (logs.length === 0) {
            Modal.alert('로그 없음', '복사할 로그가 없습니다');
            return;
        }

        const allLogs = logs.join('\n');
        await Clipboard.setStringAsync(allLogs);
        Modal.alert('복사됨', `로그 ${logs.length}건이 클립보드에 복사되었습니다`);
    };

    const handleAddTestLog = () => {
        const timestamp = new Date().toLocaleTimeString();
        log.log(`테스트 로그 항목: ${timestamp}`);
    };

    const renderLogItem = ({ item, index }: { item: string; index: number }) => (
        <View style={{
            paddingHorizontal: 16,
            paddingVertical: 8,
            borderBottomWidth: 1,
            borderBottomColor: '#F0F0F0'
        }}>
            <Text style={{
                fontFamily: 'IBMPlexMono-Regular',
                fontSize: 12,
                color: '#333',
                lineHeight: 16
            }}>
                {item}
            </Text>
        </View>
    );

    return (
        <View style={{ flex: 1, backgroundColor: '#F5F5F5' }}>
            {/* Header with actions */}
            <ItemList>
                    <ItemGroup title={`Logs (${logs.length})`}>
                    <Item 
                        title="테스트 로그 추가"
                        subtitle="타임스탬프가 포함된 테스트 로그를 추가합니다"
                        icon={<Ionicons name="add-circle-outline" size={24} color="#34C759" />}
                        onPress={handleAddTestLog}
                    />
                    <Item 
                        title="모든 로그 복사"
                        icon={<Ionicons name="copy-outline" size={24} color="#007AFF" />}
                        onPress={handleCopyAll}
                        disabled={logs.length === 0}
                    />
                    <Item 
                        title="모든 로그 삭제"
                        icon={<Ionicons name="trash-outline" size={24} color="#FF3B30" />}
                        onPress={handleClear}
                        disabled={logs.length === 0}
                        destructive={true}
                    />
                </ItemGroup>
            </ItemList>

            {/* Logs display */}
            <View style={{ flex: 1, backgroundColor: '#FFFFFF', margin: 16, borderRadius: 8 }}>
                {logs.length === 0 ? (
                    <View style={{
                        flex: 1,
                        justifyContent: 'center',
                        alignItems: 'center',
                        padding: 32
                    }}>
                        <Ionicons name="document-text-outline" size={48} color="#C0C0C0" />
                            <Text style={{
                                fontSize: 16,
                                color: '#999',
                                marginTop: 16,
                                textAlign: 'center'
                            }}>
                            아직 로그가 없습니다
                        </Text>
                        <Text style={{
                            fontSize: 14,
                            color: '#C0C0C0',
                            marginTop: 8,
                            textAlign: 'center'
                        }}>
                            생성되면 여기에 로그가 표시됩니다
                        </Text>
                    </View>
                ) : (
                    <FlatList
                        ref={flatListRef}
                        data={logs}
                        renderItem={renderLogItem}
                        keyExtractor={(item, index) => index.toString()}
                        style={{ flex: 1 }}
                        contentContainerStyle={{ paddingVertical: 8 }}
                        showsVerticalScrollIndicator={true}
                    />
                )}
            </View>
        </View>
    );
}
