import * as React from 'react';
import { View, Text, ScrollView, Pressable, TextInput, Platform } from 'react-native';
import { Ionicons, MaterialIcons, Feather } from '@/icons/vector-icons';
import { Typography } from '@/constants/Typography';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

type InputStyle = {
    id: string;
    name: string;
    description: string;
    preview: React.ReactNode;
};

export default function InputStylesDemo() {
    const [selectedStyle, setSelectedStyle] = React.useState('slack');
    const safeArea = useSafeAreaInsets();

    // Define all input style variants
    const inputStyles: InputStyle[] = [
        {
            id: 'slack',
            name: '슬랙 스타일',
            description: '아이콘만 표시되는 미니멀 디자인',
            preview: (
                <View style={{ backgroundColor: '#fff' }}>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        paddingHorizontal: 12,
                        paddingTop: 8,
                        paddingBottom: 4,
                    }}>
                        <Pressable style={{ padding: 6, marginRight: 2 }}>
                            <Ionicons name="at" size={18} color="#666" />
                        </Pressable>
                        <Pressable style={{ padding: 6, marginRight: 2 }}>
                            <Ionicons name="happy-outline" size={18} color="#666" />
                        </Pressable>
                        <Pressable style={{ padding: 6, marginRight: 2 }}>
                            <MaterialIcons name="format-bold" size={18} color="#666" />
                        </Pressable>
                        <Pressable style={{ padding: 6, marginRight: 2 }}>
                            <MaterialIcons name="format-italic" size={18} color="#666" />
                        </Pressable>
                        <Pressable style={{ padding: 6, marginRight: 2 }}>
                            <MaterialIcons name="link" size={18} color="#666" />
                        </Pressable>
                        <View style={{ flex: 1 }} />
                        <Pressable style={{ padding: 6 }}>
                            <Ionicons name="code-slash" size={18} color="#666" />
                        </Pressable>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'flex-end',
                        paddingHorizontal: 12,
                        paddingBottom: 12,
                    }}>
                        <Pressable style={{ padding: 8 }}>
                            <Ionicons name="add" size={20} color="#666" />
                        </Pressable>
                        <View style={{
                            flex: 1,
                            flexDirection: 'row',
                            alignItems: 'center',
                            backgroundColor: '#f8f8f8',
                            borderRadius: 8,
                            borderWidth: 1,
                            borderColor: '#e0e0e0',
                            paddingHorizontal: 12,
                            marginHorizontal: 8,
                            height: 36,
                        }}>
                            <TextInput
                                style={{ flex: 1, fontSize: 14, color: '#333' }}
                                placeholder="메시지"
                                placeholderTextColor="#999"
                                editable={false}
                            />
                        </View>
                        <Pressable style={{ padding: 8 }}>
                            <Ionicons name="send" size={18} color="#007a5a" />
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'openai',
            name: '오픈AI 스타일',
            description: '부드러운 둥근 모서리의 깔끔한 디자인',
            preview: (
                <View style={{ backgroundColor: '#fff' }}>
                    <View style={{ padding: 16 }}>
                        <View style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            backgroundColor: '#f7f7f8',
                            borderRadius: 24,
                            borderWidth: 1,
                            borderColor: '#e5e5e5',
                            paddingLeft: 16,
                            paddingRight: 4,
                            minHeight: 48,
                        }}>
                            <TextInput
                                style={{ flex: 1, fontSize: 16, color: '#000', paddingVertical: 12 }}
                                placeholder="메시지 ChatGPT..."
                                placeholderTextColor="#8e8e8e"
                                editable={false}
                            />
                            <Pressable style={{
                                width: 40,
                                height: 40,
                                borderRadius: 20,
                                backgroundColor: '#000',
                                alignItems: 'center',
                                justifyContent: 'center',
                            }}>
                                <Ionicons name="arrow-up" size={20} color="#fff" />
                            </Pressable>
                        </View>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        paddingHorizontal: 20,
                        paddingBottom: 12,
                    }}>
                        <Pressable style={{
                            paddingHorizontal: 14,
                            paddingVertical: 6,
                            borderRadius: 16,
                            backgroundColor: '#f0f0f0',
                            marginRight: 8,
                        }}>
                            <Ionicons name="attach" size={16} color="#666" />
                        </Pressable>
                        <Pressable style={{
                            paddingHorizontal: 14,
                            paddingVertical: 6,
                            borderRadius: 16,
                            backgroundColor: '#f0f0f0',
                            marginRight: 8,
                        }}>
                            <Ionicons name="image" size={16} color="#666" />
                        </Pressable>
                        <Pressable style={{
                            paddingHorizontal: 14,
                            paddingVertical: 6,
                            borderRadius: 16,
                            backgroundColor: '#f0f0f0',
                        }}>
                            <Text style={{ fontSize: 13, color: '#666' }}>GPT-4</Text>
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'discord',
            name: '디스코드 스타일',
            description: '다크 모드와 첨부 파일 버튼',
            preview: (
                <View style={{ backgroundColor: '#36393f' }}>
                    <View style={{ padding: 16 }}>
                        <View style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            backgroundColor: '#40444b',
                            borderRadius: 8,
                            paddingHorizontal: 16,
                            minHeight: 44,
                        }}>
                            <Pressable style={{ marginRight: 16 }}>
                                <Ionicons name="add-circle" size={24} color="#b9bbbe" />
                            </Pressable>
                            <TextInput
                                style={{ flex: 1, fontSize: 16, color: '#dcddde' }}
                                placeholder="메시지 #일반"
                                placeholderTextColor="#72767d"
                                editable={false}
                            />
                            <Pressable style={{ marginLeft: 12 }}>
                                <MaterialIcons name="gif" size={24} color="#b9bbbe" />
                            </Pressable>
                            <Pressable style={{ marginLeft: 12 }}>
                                <Ionicons name="happy" size={24} color="#b9bbbe" />
                            </Pressable>
                        </View>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        paddingHorizontal: 20,
                        paddingBottom: 12,
                    }}>
                        <Pressable style={{ padding: 4, marginRight: 8 }}>
                            <Feather name="gift" size={18} color="#b9bbbe" />
                        </Pressable>
                        <Pressable style={{ padding: 4, marginRight: 8 }}>
                            <MaterialIcons name="sticky-note-2" size={18} color="#b9bbbe" />
                        </Pressable>
                        <Pressable style={{ padding: 4 }}>
                            <Ionicons name="game-controller" size={18} color="#b9bbbe" />
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'whatsapp',
            name: '왓츠앱 스타일',
            description: '원형 버튼의 초록색 포인트',
            preview: (
                <View style={{ backgroundColor: '#e5ddd5' }}>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'flex-end',
                        padding: 8,
                    }}>
                        <View style={{
                            flex: 1,
                            flexDirection: 'row',
                            alignItems: 'center',
                            backgroundColor: '#fff',
                            borderRadius: 25,
                            paddingHorizontal: 12,
                            marginRight: 8,
                            minHeight: 42,
                        }}>
                            <Pressable style={{ marginRight: 8 }}>
                                <Ionicons name="happy-outline" size={24} color="#51585c" />
                            </Pressable>
                            <TextInput
                                style={{ flex: 1, fontSize: 16, color: '#000' }}
                                placeholder="메시지를 입력하세요"
                                placeholderTextColor="#999"
                                editable={false}
                            />
                            <Pressable style={{ marginLeft: 8 }}>
                                <Ionicons name="attach" size={24} color="#51585c" />
                            </Pressable>
                            <Pressable style={{ marginLeft: 8 }}>
                                <Ionicons name="camera" size={24} color="#51585c" />
                            </Pressable>
                        </View>
                        <Pressable style={{
                            width: 48,
                            height: 48,
                            borderRadius: 24,
                            backgroundColor: '#25d366',
                            alignItems: 'center',
                            justifyContent: 'center',
                        }}>
                            <Ionicons name="mic" size={24} color="#fff" />
                        </Pressable>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        paddingHorizontal: 12,
                        paddingBottom: 8,
                    }}>
                        <Pressable style={{
                            paddingHorizontal: 12,
                            paddingVertical: 4,
                            backgroundColor: 'rgba(0,0,0,0.05)',
                            borderRadius: 12,
                            marginRight: 6,
                        }}>
                            <Text style={{ fontSize: 12, color: '#667781' }}>사진</Text>
                        </Pressable>
                        <Pressable style={{
                            paddingHorizontal: 12,
                            paddingVertical: 4,
                            backgroundColor: 'rgba(0,0,0,0.05)',
                            borderRadius: 12,
                            marginRight: 6,
                        }}>
                            <Text style={{ fontSize: 12, color: '#667781' }}>동영상</Text>
                        </Pressable>
                        <Pressable style={{
                            paddingHorizontal: 12,
                            paddingVertical: 4,
                            backgroundColor: 'rgba(0,0,0,0.05)',
                            borderRadius: 12,
                        }}>
                            <Text style={{ fontSize: 12, color: '#667781' }}>문서</Text>
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'telegram',
            name: '텔레그램 스타일',
            description: '날카로운 모서리의 플랫 디자인',
            preview: (
                <View style={{ backgroundColor: '#fff' }}>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        padding: 8,
                        borderTopWidth: 1,
                        borderTopColor: '#e0e0e0',
                    }}>
                        <Pressable style={{ padding: 8 }}>
                            <Ionicons name="attach" size={24} color="#8e8e8e" />
                        </Pressable>
                        <View style={{
                            flex: 1,
                            backgroundColor: '#f0f0f0',
                            borderRadius: 18,
                            paddingHorizontal: 16,
                            paddingVertical: 8,
                            marginHorizontal: 8,
                        }}>
                            <TextInput
                                style={{ fontSize: 16, color: '#000' }}
                                placeholder="메시지"
                                placeholderTextColor="#999"
                                editable={false}
                            />
                        </View>
                        <Pressable style={{ padding: 8 }}>
                            <Ionicons name="mic" size={24} color="#0088cc" />
                        </Pressable>
                        <Pressable style={{
                            padding: 8,
                            backgroundColor: '#0088cc',
                            borderRadius: 20,
                        }}>
                            <Ionicons name="send" size={20} color="#fff" />
                        </Pressable>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        paddingHorizontal: 16,
                        paddingBottom: 8,
                    }}>
                        <Pressable style={{ padding: 4, marginRight: 12 }}>
                            <Ionicons name="happy-outline" size={20} color="#8e8e8e" />
                        </Pressable>
                        <Pressable style={{ padding: 4, marginRight: 12 }}>
                            <MaterialIcons name="sticky-note-2" size={20} color="#8e8e8e" />
                        </Pressable>
                        <Pressable style={{ padding: 4, marginRight: 12 }}>
                            <Ionicons name="location" size={20} color="#8e8e8e" />
                        </Pressable>
                        <Pressable style={{ padding: 4 }}>
                            <Ionicons name="timer-outline" size={20} color="#8e8e8e" />
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'linear',
            name: '리니어 스타일',
            description: '은은한 그라데이션이 있는 현대적 디자인',
            preview: (
                <View style={{ backgroundColor: '#fcfcfc' }}>
                    <View style={{ padding: 16 }}>
                        <View style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            backgroundColor: '#fff',
                            borderRadius: 8,
                            borderWidth: 1,
                            borderColor: '#e1e4e8',
                            paddingLeft: 16,
                            paddingRight: 8,
                            minHeight: 42,
                        }}>
                            <TextInput
                                style={{ flex: 1, fontSize: 15, color: '#24292e' }}
                                placeholder="댓글을 작성하세요..."
                                placeholderTextColor="#6a737d"
                                editable={false}
                            />
                            <Pressable style={{
                                paddingHorizontal: 16,
                                paddingVertical: 6,
                                backgroundColor: '#5e6ad2',
                                borderRadius: 6,
                            }}>
                                <Text style={{ color: '#fff', fontSize: 14, fontWeight: '600' }}>
                                    댓글
                                </Text>
                            </Pressable>
                        </View>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        paddingHorizontal: 20,
                        paddingBottom: 12,
                    }}>
                        <Pressable style={{ marginRight: 16 }}>
                            <Ionicons name="at" size={18} color="#6a737d" />
                        </Pressable>
                        <Pressable style={{ marginRight: 16 }}>
                            <MaterialIcons name="tag" size={18} color="#6a737d" />
                        </Pressable>
                        <Pressable style={{ marginRight: 16 }}>
                            <Ionicons name="code-slash" size={18} color="#6a737d" />
                        </Pressable>
                        <Pressable>
                            <Ionicons name="attach" size={18} color="#6a737d" />
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'notion',
            name: '노션 스타일',
            description: '"/" 명령어 힌트가 있는 미니멀 스타일',
            preview: (
                <View style={{ backgroundColor: '#fff' }}>
                    <View style={{ padding: 16 }}>
                        <View style={{
                            borderRadius: 3,
                            borderWidth: 1,
                            borderColor: 'rgba(55, 53, 47, 0.16)',
                            paddingHorizontal: 12,
                            paddingVertical: 8,
                        }}>
                            <TextInput
                                style={{ fontSize: 16, color: '#37352f' }}
                                placeholder="'/' 명령어 입력"
                                placeholderTextColor="rgba(55, 53, 47, 0.4)"
                                editable={false}
                            />
                        </View>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        paddingHorizontal: 20,
                        paddingBottom: 12,
                    }}>
                        <Pressable style={{
                            paddingHorizontal: 10,
                            paddingVertical: 4,
                            backgroundColor: '#f7f6f3',
                            borderRadius: 3,
                            marginRight: 8,
                        }}>
                            <Text style={{ fontSize: 12, color: '#787774' }}>아이콘 추가</Text>
                        </Pressable>
                        <Pressable style={{
                            paddingHorizontal: 10,
                            paddingVertical: 4,
                            backgroundColor: '#f7f6f3',
                            borderRadius: 3,
                            marginRight: 8,
                        }}>
                            <Text style={{ fontSize: 12, color: '#787774' }}>표지 추가</Text>
                        </Pressable>
                        <Pressable style={{
                            paddingHorizontal: 10,
                            paddingVertical: 4,
                            backgroundColor: '#f7f6f3',
                            borderRadius: 3,
                        }}>
                            <Text style={{ fontSize: 12, color: '#787774' }}>댓글 추가</Text>
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'github',
            name: '깃허브 스타일',
            description: '개발자 중심의 마크다운 힌트',
            preview: (
                <View style={{ backgroundColor: '#f6f8fa' }}>
                    <View style={{ padding: 16 }}>
                        <View style={{
                            backgroundColor: '#fff',
                            borderRadius: 6,
                            borderWidth: 1,
                            borderColor: '#d1d5da',
                            padding: 8,
                        }}>
                            <View style={{
                                flexDirection: 'row',
                                marginBottom: 8,
                                paddingBottom: 8,
                                borderBottomWidth: 1,
                                borderBottomColor: '#e1e4e8',
                            }}>
                                <Pressable style={{ marginRight: 16 }}>
                                    <MaterialIcons name="format-bold" size={18} color="#586069" />
                                </Pressable>
                                <Pressable style={{ marginRight: 16 }}>
                                    <MaterialIcons name="format-italic" size={18} color="#586069" />
                                </Pressable>
                                <Pressable style={{ marginRight: 16 }}>
                                    <MaterialIcons name="code" size={18} color="#586069" />
                                </Pressable>
                                <Pressable style={{ marginRight: 16 }}>
                                    <MaterialIcons name="link" size={18} color="#586069" />
                                </Pressable>
                                <Pressable style={{ marginRight: 16 }}>
                                    <MaterialIcons name="format-list-bulleted" size={18} color="#586069" />
                                </Pressable>
                                <Pressable>
                                    <MaterialIcons name="format-list-numbered" size={18} color="#586069" />
                                </Pressable>
                            </View>
                            <TextInput
                                style={{ fontSize: 14, color: '#24292e', minHeight: 60 }}
                                placeholder="댓글을 입력하세요"
                                placeholderTextColor="#6a737d"
                                multiline
                                editable={false}
                            />
                        </View>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        paddingHorizontal: 20,
                        paddingBottom: 12,
                    }}>
                        <Text style={{ fontSize: 12, color: '#6a737d' }}>
                            마크다운 지원
                        </Text>
                        <View style={{ flexDirection: 'row' }}>
                            <Pressable style={{
                                paddingHorizontal: 12,
                                paddingVertical: 6,
                                backgroundColor: '#fafbfc',
                                borderRadius: 6,
                                borderWidth: 1,
                                borderColor: '#d1d5da',
                                marginRight: 8,
                            }}>
                                <Text style={{ fontSize: 14, color: '#24292e' }}>취소</Text>
                            </Pressable>
                            <Pressable style={{
                                paddingHorizontal: 12,
                                paddingVertical: 6,
                                backgroundColor: '#2ea44f',
                                borderRadius: 6,
                            }}>
                                <Text style={{ fontSize: 14, color: '#fff', fontWeight: '600' }}>댓글</Text>
                            </Pressable>
                        </View>
                    </View>
                </View>
            ),
        },
        {
            id: 'imessage',
            name: '애플 메시지',
            description: 'iOS 기본 메시징 스타일',
            preview: (
                <View style={{ backgroundColor: '#fff' }}>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'flex-end',
                        padding: 8,
                    }}>
                        <Pressable style={{ 
                            width: 34,
                            height: 34,
                            borderRadius: 17,
                            backgroundColor: '#007AFF',
                            alignItems: 'center',
                            justifyContent: 'center',
                            marginRight: 8,
                        }}>
                            <Ionicons name="camera" size={20} color="#fff" />
                        </Pressable>
                        <View style={{
                            flex: 1,
                            backgroundColor: '#e5e5ea',
                            borderRadius: 18,
                            paddingHorizontal: 12,
                            paddingVertical: 8,
                            marginRight: 8,
                            minHeight: 34,
                        }}>
                            <TextInput
                                style={{ fontSize: 17, color: '#000' }}
                                placeholder="i메시지"
                                placeholderTextColor="#8e8e93"
                                editable={false}
                            />
                        </View>
                        <Pressable style={{ 
                            width: 34,
                            height: 34,
                            borderRadius: 17,
                            backgroundColor: '#007AFF',
                            alignItems: 'center',
                            justifyContent: 'center',
                        }}>
                            <Ionicons name="arrow-up" size={20} color="#fff" />
                        </Pressable>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        paddingHorizontal: 12,
                        paddingBottom: 8,
                    }}>
                        <Pressable style={{ padding: 6, marginRight: 4 }}>
                            <Ionicons name="apps" size={22} color="#8e8e93" />
                        </Pressable>
                        <Pressable style={{ padding: 6, marginRight: 4 }}>
                            <Ionicons name="images" size={22} color="#8e8e93" />
                        </Pressable>
                        <Pressable style={{ padding: 6, marginRight: 4 }}>
                            <MaterialIcons name="sticky-note-2" size={22} color="#8e8e93" />
                        </Pressable>
                        <Pressable style={{ padding: 6 }}>
                            <Ionicons name="musical-notes" size={22} color="#8e8e93" />
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'material',
            name: '머테리얼 디자인',
            description: 'Google의 디자인 언어',
            preview: (
                <View style={{ backgroundColor: '#fff' }}>
                    <View style={{ padding: 16 }}>
                        <View style={{
                            borderBottomWidth: 2,
                            borderBottomColor: '#1976d2',
                            paddingBottom: 8,
                        }}>
                            <Text style={{
                                fontSize: 12,
                                color: '#1976d2',
                                marginBottom: 4,
                            }}>
                                Message
                            </Text>
                            <View style={{
                                flexDirection: 'row',
                                alignItems: 'center',
                            }}>
                                <TextInput
                                    style={{ flex: 1, fontSize: 16, color: '#000' }}
                                    placeholder="메시지를 입력하세요"
                                    placeholderTextColor="#999"
                                    editable={false}
                                />
                                <Pressable style={{ marginLeft: 8 }}>
                                    <MaterialIcons name="send" size={24} color="#1976d2" />
                                </Pressable>
                            </View>
                        </View>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        paddingHorizontal: 20,
                        paddingBottom: 12,
                    }}>
                        <Pressable style={{
                            width: 40,
                            height: 40,
                            borderRadius: 20,
                            backgroundColor: '#f5f5f5',
                            alignItems: 'center',
                            justifyContent: 'center',
                            marginRight: 12,
                        }}>
                            <Ionicons name="attach" size={20} color="#757575" />
                        </Pressable>
                        <Pressable style={{
                            width: 40,
                            height: 40,
                            borderRadius: 20,
                            backgroundColor: '#f5f5f5',
                            alignItems: 'center',
                            justifyContent: 'center',
                            marginRight: 12,
                        }}>
                            <Ionicons name="image" size={20} color="#757575" />
                        </Pressable>
                        <Pressable style={{
                            width: 40,
                            height: 40,
                            borderRadius: 20,
                            backgroundColor: '#f5f5f5',
                            alignItems: 'center',
                            justifyContent: 'center',
                            marginRight: 12,
                        }}>
                            <Ionicons name="mic" size={20} color="#757575" />
                        </Pressable>
                        <Pressable style={{
                            width: 40,
                            height: 40,
                            borderRadius: 20,
                            backgroundColor: '#f5f5f5',
                            alignItems: 'center',
                            justifyContent: 'center',
                        }}>
                            <Ionicons name="location" size={20} color="#757575" />
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'brutalist',
            name: '브루탈리스트 스타일',
            description: '굵은 테두리와 높은 대비',
            preview: (
                <View style={{ backgroundColor: '#ffeb3b' }}>
                    <View style={{ padding: 16 }}>
                        <View style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            backgroundColor: '#fff',
                            borderWidth: 3,
                            borderColor: '#000',
                            paddingHorizontal: 16,
                            minHeight: 56,
                        }}>
                            <TextInput
                                style={{ 
                                    flex: 1, 
                                    fontSize: 18, 
                                    color: '#000',
                                    fontWeight: 'bold',
                                }}
                                placeholder="여기에 입력하세요!"
                                placeholderTextColor="#666"
                                editable={false}
                            />
                            <Pressable style={{
                                backgroundColor: '#000',
                                paddingHorizontal: 20,
                                paddingVertical: 10,
                                marginLeft: 8,
                            }}>
                                <Text style={{ 
                                    color: '#fff', 
                                    fontSize: 16, 
                                    fontWeight: 'bold' 
                                }}>
                                    SEND
                                </Text>
                            </Pressable>
                        </View>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        paddingHorizontal: 20,
                        paddingBottom: 12,
                    }}>
                        <Pressable style={{
                            backgroundColor: '#000',
                            borderWidth: 2,
                            borderColor: '#000',
                            paddingHorizontal: 16,
                            paddingVertical: 8,
                            marginRight: 8,
                        }}>
                            <Text style={{ color: '#fff', fontWeight: 'bold' }}>굵게</Text>
                        </Pressable>
                        <Pressable style={{
                            backgroundColor: '#fff',
                            borderWidth: 2,
                            borderColor: '#000',
                            paddingHorizontal: 16,
                            paddingVertical: 8,
                            marginRight: 8,
                        }}>
                            <Text style={{ color: '#000', fontWeight: 'bold' }}>기울임</Text>
                        </Pressable>
                        <Pressable style={{
                            backgroundColor: '#f44336',
                            borderWidth: 2,
                            borderColor: '#000',
                            paddingHorizontal: 16,
                            paddingVertical: 8,
                        }}>
                            <Text style={{ color: '#fff', fontWeight: 'bold' }}>링크</Text>
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'glassmorphism',
            name: '글래스모피즘',
            description: '반투명 블러 효과',
            preview: (
                <View style={{ backgroundColor: '#1a1a2e' }}>
                    <View style={{ padding: 16 }}>
                        <View style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            backgroundColor: 'rgba(255, 255, 255, 0.1)',
                            borderRadius: 16,
                            borderWidth: 1,
                            borderColor: 'rgba(255, 255, 255, 0.2)',
                            paddingHorizontal: 16,
                            paddingVertical: 12,
                        }}>
                            <TextInput
                                style={{ 
                                    flex: 1, 
                                    fontSize: 16, 
                                    color: '#fff',
                                }}
                                placeholder="메시지를 입력하세요..."
                                placeholderTextColor="rgba(255, 255, 255, 0.5)"
                                editable={false}
                            />
                            <Pressable style={{
                                width: 40,
                                height: 40,
                                borderRadius: 20,
                                backgroundColor: 'rgba(255, 255, 255, 0.2)',
                                alignItems: 'center',
                                justifyContent: 'center',
                                marginLeft: 12,
                            }}>
                                <Ionicons name="send" size={20} color="#fff" />
                            </Pressable>
                        </View>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        paddingHorizontal: 20,
                        paddingBottom: 12,
                    }}>
                        <Pressable style={{
                            width: 36,
                            height: 36,
                            borderRadius: 18,
                            backgroundColor: 'rgba(255, 255, 255, 0.1)',
                            borderWidth: 1,
                            borderColor: 'rgba(255, 255, 255, 0.2)',
                            alignItems: 'center',
                            justifyContent: 'center',
                            marginRight: 12,
                        }}>
                            <Ionicons name="attach" size={18} color="rgba(255, 255, 255, 0.8)" />
                        </Pressable>
                        <Pressable style={{
                            width: 36,
                            height: 36,
                            borderRadius: 18,
                            backgroundColor: 'rgba(255, 255, 255, 0.1)',
                            borderWidth: 1,
                            borderColor: 'rgba(255, 255, 255, 0.2)',
                            alignItems: 'center',
                            justifyContent: 'center',
                            marginRight: 12,
                        }}>
                            <Ionicons name="image" size={18} color="rgba(255, 255, 255, 0.8)" />
                        </Pressable>
                        <Pressable style={{
                            width: 36,
                            height: 36,
                            borderRadius: 18,
                            backgroundColor: 'rgba(255, 255, 255, 0.1)',
                            borderWidth: 1,
                            borderColor: 'rgba(255, 255, 255, 0.2)',
                            alignItems: 'center',
                            justifyContent: 'center',
                        }}>
                            <Ionicons name="sparkles" size={18} color="rgba(255, 255, 255, 0.8)" />
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'spotify',
            name: '스포티파이 스타일',
            description: '재생 제어가 있는 음악 중심 UI',
            preview: (
                <View style={{ backgroundColor: '#121212' }}>
                    <View style={{ padding: 16 }}>
                        <View style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            backgroundColor: '#282828',
                            borderRadius: 24,
                            paddingHorizontal: 16,
                            paddingVertical: 12,
                        }}>
                            <Ionicons name="search" size={20} color="#b3b3b3" />
                            <TextInput
                                style={{ 
                                    flex: 1, 
                                    fontSize: 16, 
                                    color: '#fff',
                                    marginLeft: 12,
                                }}
                                placeholder="노래 검색..."
                                placeholderTextColor="#535353"
                                editable={false}
                            />
                            <Pressable style={{ marginLeft: 12 }}>
                                <Ionicons name="mic" size={20} color="#1db954" />
                            </Pressable>
                        </View>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        justifyContent: 'center',
                        paddingHorizontal: 20,
                        paddingBottom: 12,
                    }}>
                        <Pressable style={{ padding: 12 }}>
                            <Ionicons name="shuffle" size={24} color="#b3b3b3" />
                        </Pressable>
                        <Pressable style={{ padding: 12 }}>
                            <Ionicons name="play-skip-back" size={24} color="#fff" />
                        </Pressable>
                        <Pressable style={{
                            width: 56,
                            height: 56,
                            borderRadius: 28,
                            backgroundColor: '#1db954',
                            alignItems: 'center',
                            justifyContent: 'center',
                            marginHorizontal: 16,
                        }}>
                            <Ionicons name="play" size={28} color="#000" style={{ marginLeft: 2 }} />
                        </Pressable>
                        <Pressable style={{ padding: 12 }}>
                            <Ionicons name="play-skip-forward" size={24} color="#fff" />
                        </Pressable>
                        <Pressable style={{ padding: 12 }}>
                            <Ionicons name="repeat" size={24} color="#1db954" />
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'figma',
            name: '피그마 스타일',
            description: '협업 기능이 있는 디자인 도구',
            preview: (
                <View style={{ backgroundColor: '#2c2c2c' }}>
                    <View style={{ padding: 16 }}>
                        <View style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            backgroundColor: '#383838',
                            borderRadius: 8,
                            paddingHorizontal: 12,
                            paddingVertical: 10,
                        }}>
                            <TextInput
                                style={{ flex: 1, fontSize: 14, color: '#fff' }}
                                placeholder="댓글을 작성하세요..."
                                placeholderTextColor="#a0a0a0"
                                editable={false}
                            />
                            <Pressable style={{
                                paddingHorizontal: 16,
                                paddingVertical: 6,
                                backgroundColor: '#0d99ff',
                                borderRadius: 6,
                                marginLeft: 8,
                            }}>
                                <Text style={{ color: '#fff', fontSize: 14, fontWeight: '600' }}>
                                    Post
                                </Text>
                            </Pressable>
                        </View>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        paddingHorizontal: 20,
                        paddingBottom: 12,
                    }}>
                        <View style={{ flexDirection: 'row' }}>
                            <Pressable style={{ 
                                width: 28, 
                                height: 28, 
                                borderRadius: 14, 
                                backgroundColor: '#ff7262',
                                marginRight: -8,
                                borderWidth: 2,
                                borderColor: '#2c2c2c',
                            }} />
                            <Pressable style={{ 
                                width: 28, 
                                height: 28, 
                                borderRadius: 14, 
                                backgroundColor: '#0d99ff',
                                marginRight: -8,
                                borderWidth: 2,
                                borderColor: '#2c2c2c',
                                zIndex: -1,
                            }} />
                            <Pressable style={{ 
                                width: 28, 
                                height: 28, 
                                borderRadius: 14, 
                                backgroundColor: '#1abcfe',
                                borderWidth: 2,
                                borderColor: '#2c2c2c',
                                zIndex: -2,
                            }} />
                            <Text style={{ 
                                color: '#a0a0a0', 
                                fontSize: 12, 
                                marginLeft: 12,
                                alignSelf: 'center',
                            }}>
                                3 people here
                            </Text>
                        </View>
                        <View style={{ flexDirection: 'row' }}>
                            <Pressable style={{ padding: 4 }}>
                                <Ionicons name="happy-outline" size={20} color="#a0a0a0" />
                            </Pressable>
                            <Pressable style={{ padding: 4, marginLeft: 8 }}>
                                <Ionicons name="at" size={20} color="#a0a0a0" />
                            </Pressable>
                        </View>
                    </View>
                </View>
            ),
        },
        {
            id: 'twitter',
            name: '트위터/X 스타일',
            description: '짧은 글쓰기 기반의 마이크로블로그',
            preview: (
                <View style={{ backgroundColor: '#000' }}>
                    <View style={{ padding: 16 }}>
                        <View style={{
                            borderRadius: 16,
                            borderWidth: 1,
                            borderColor: '#333',
                            padding: 12,
                        }}>
                            <TextInput
                                style={{ 
                                    fontSize: 18, 
                                    color: '#fff',
                                    minHeight: 60,
                                }}
                                placeholder="새 소식은 무엇인가요?"
                                placeholderTextColor="#71767b"
                                multiline
                                editable={false}
                            />
                            <View style={{
                                flexDirection: 'row',
                                alignItems: 'center',
                                justifyContent: 'space-between',
                                marginTop: 12,
                            }}>
                                <View style={{ flexDirection: 'row' }}>
                                    <Pressable style={{ marginRight: 16 }}>
                                        <Ionicons name="image-outline" size={20} color="#1d9bf0" />
                                    </Pressable>
                                    <Pressable style={{ marginRight: 16 }}>
                                        <MaterialIcons name="gif" size={20} color="#1d9bf0" />
                                    </Pressable>
                                    <Pressable style={{ marginRight: 16 }}>
                                        <Ionicons name="stats-chart" size={20} color="#1d9bf0" />
                                    </Pressable>
                                    <Pressable>
                                        <Ionicons name="happy-outline" size={20} color="#1d9bf0" />
                                    </Pressable>
                                </View>
                                <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                                    <Text style={{ color: '#71767b', fontSize: 14, marginRight: 12 }}>
                                        0/280
                                    </Text>
                                    <Pressable style={{
                                        paddingHorizontal: 16,
                                        paddingVertical: 8,
                                        backgroundColor: '#1d9bf0',
                                        borderRadius: 18,
                                    }}>
                                        <Text style={{ color: '#fff', fontSize: 15, fontWeight: '600' }}>
                                            Post
                                        </Text>
                                    </Pressable>
                                </View>
                            </View>
                        </View>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        paddingHorizontal: 20,
                        paddingBottom: 12,
                    }}>
                        <Pressable style={{
                            paddingHorizontal: 12,
                            paddingVertical: 4,
                            borderRadius: 12,
                            borderWidth: 1,
                            borderColor: '#333',
                            marginRight: 8,
                        }}>
                            <Text style={{ fontSize: 12, color: '#1d9bf0' }}>모두</Text>
                        </Pressable>
                        <Pressable style={{
                            paddingHorizontal: 12,
                            paddingVertical: 4,
                            borderRadius: 12,
                            borderWidth: 1,
                            borderColor: '#333',
                            marginRight: 8,
                        }}>
                            <Text style={{ fontSize: 12, color: '#71767b' }}>위치</Text>
                        </Pressable>
                        <Pressable style={{
                            paddingHorizontal: 12,
                            paddingVertical: 4,
                            borderRadius: 12,
                            borderWidth: 1,
                            borderColor: '#333',
                        }}>
                            <Text style={{ fontSize: 12, color: '#71767b' }}>일정</Text>
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'arc',
            name: 'Arc 브라우저 스타일',
            description: '명령 팔레트를 사용하는 미니멀 스타일',
            preview: (
                <View style={{ backgroundColor: '#f6f6f6' }}>
                    <View style={{ padding: 16 }}>
                        <View style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            backgroundColor: '#fff',
                            borderRadius: 12,
                            paddingHorizontal: 16,
                            paddingVertical: 12,
                            ...Platform.select({
                                ios: {
                                    shadowColor: '#000',
                                    shadowOffset: { width: 0, height: 2 },
                                    shadowOpacity: 0.05,
                                    shadowRadius: 8,
                                },
                                android: {
                                    elevation: 2,
                                },
                            }),
                        }}>
                            <Ionicons name="search" size={18} color="#999" />
                            <TextInput
                                style={{ 
                                    flex: 1, 
                                    fontSize: 15, 
                                    color: '#000',
                                    marginLeft: 12,
                                }}
                                placeholder="검색하거나 URL을 입력하세요..."
                                placeholderTextColor="#999"
                                editable={false}
                            />
                            <Pressable style={{
                                paddingHorizontal: 8,
                                paddingVertical: 4,
                                backgroundColor: '#f0f0f0',
                                borderRadius: 6,
                            }}>
                                <Text style={{ fontSize: 12, color: '#666' }}>⌘K</Text>
                            </Pressable>
                        </View>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        justifyContent: 'center',
                        paddingHorizontal: 20,
                        paddingBottom: 12,
                    }}>
                        <Pressable style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            paddingHorizontal: 12,
                            paddingVertical: 6,
                            backgroundColor: '#e8e8e8',
                            borderRadius: 8,
                            marginRight: 8,
                        }}>
                            <View style={{
                                width: 8,
                                height: 8,
                                borderRadius: 4,
                                backgroundColor: '#ff5f57',
                                marginRight: 6,
                            }} />
                            <Text style={{ fontSize: 13, color: '#333' }}>공간 1</Text>
                        </Pressable>
                        <Pressable style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            paddingHorizontal: 12,
                            paddingVertical: 6,
                            backgroundColor: '#e8e8e8',
                            borderRadius: 8,
                            marginRight: 8,
                        }}>
                            <View style={{
                                width: 8,
                                height: 8,
                                borderRadius: 4,
                                backgroundColor: '#ffbd2e',
                                marginRight: 6,
                            }} />
                            <Text style={{ fontSize: 13, color: '#333' }}>공간 2</Text>
                        </Pressable>
                        <Pressable style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            paddingHorizontal: 12,
                            paddingVertical: 6,
                            backgroundColor: '#e8e8e8',
                            borderRadius: 8,
                        }}>
                            <View style={{
                                width: 8,
                                height: 8,
                                borderRadius: 4,
                                backgroundColor: '#28ca42',
                                marginRight: 6,
                            }} />
                            <Text style={{ fontSize: 13, color: '#333' }}>공간 3</Text>
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'claude',
            name: '클로드 스타일',
            description: '아티팩트 기능이 있는 AI 어시스턴트',
            preview: (
                <View style={{ backgroundColor: '#f9f7f4' }}>
                    <View style={{ padding: 16 }}>
                        <View style={{
                            backgroundColor: '#fff',
                            borderRadius: 16,
                            borderWidth: 1,
                            borderColor: '#e5e3df',
                            paddingHorizontal: 16,
                            paddingVertical: 12,
                        }}>
                            <TextInput
                                style={{ 
                                    fontSize: 16, 
                                    color: '#000',
                                    minHeight: 40,
                                }}
                                placeholder="Claude에게 무엇이든 물어보세요..."
                                placeholderTextColor="#999"
                                multiline
                                editable={false}
                            />
                            <View style={{
                                flexDirection: 'row',
                                alignItems: 'center',
                                justifyContent: 'space-between',
                                marginTop: 8,
                            }}>
                                <View style={{ flexDirection: 'row' }}>
                                    <Pressable style={{ marginRight: 16 }}>
                                        <Ionicons name="attach" size={20} color="#666" />
                                    </Pressable>
                                    <Pressable>
                                        <Ionicons name="code-slash" size={20} color="#666" />
                                    </Pressable>
                                </View>
                                <Pressable style={{
                                    backgroundColor: '#d97706',
                                    paddingHorizontal: 16,
                                    paddingVertical: 8,
                                    borderRadius: 20,
                                }}>
                                    <Ionicons name="arrow-up" size={18} color="#fff" />
                                </Pressable>
                            </View>
                        </View>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        paddingHorizontal: 20,
                        paddingBottom: 12,
                    }}>
                        <Pressable style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            paddingHorizontal: 12,
                            paddingVertical: 6,
                            backgroundColor: '#fff',
                            borderRadius: 20,
                            borderWidth: 1,
                            borderColor: '#e5e3df',
                            marginRight: 8,
                        }}>
                            <View style={{
                                width: 6,
                                height: 6,
                                borderRadius: 3,
                                backgroundColor: '#d97706',
                                marginRight: 6,
                            }} />
                            <Text style={{ fontSize: 13, color: '#666' }}>Claude 3.5</Text>
                        </Pressable>
                        <Pressable style={{
                            paddingHorizontal: 12,
                            paddingVertical: 6,
                            backgroundColor: '#f4f2ee',
                            borderRadius: 20,
                            marginRight: 8,
                        }}>
                            <Text style={{ fontSize: 13, color: '#666' }}>아티팩트</Text>
                        </Pressable>
                        <Pressable style={{
                            paddingHorizontal: 12,
                            paddingVertical: 6,
                            backgroundColor: '#f4f2ee',
                            borderRadius: 20,
                        }}>
                            <Text style={{ fontSize: 13, color: '#666' }}>프로젝트</Text>
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'reddit',
            name: '레딧 스타일',
            description: '커뮤니티 중심의 마크다운 지원',
            preview: (
                <View style={{ backgroundColor: '#1a1a1b' }}>
                    <View style={{ padding: 12 }}>
                        <View style={{
                            backgroundColor: '#272729',
                            borderRadius: 4,
                            borderWidth: 1,
                            borderColor: '#343536',
                            padding: 12,
                        }}>
                            <TextInput
                                style={{ 
                                    fontSize: 14, 
                                    color: '#d7dadc',
                                    minHeight: 80,
                                }}
                                placeholder="의견을 알려주세요"
                                placeholderTextColor="#818384"
                                multiline
                                editable={false}
                            />
                        </View>
                        <View style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            marginTop: 8,
                            backgroundColor: '#1a1a1b',
                            borderRadius: 4,
                            paddingVertical: 4,
                        }}>
                            <Pressable style={{ padding: 8 }}>
                                <MaterialIcons name="format-bold" size={18} color="#818384" />
                            </Pressable>
                            <Pressable style={{ padding: 8 }}>
                                <MaterialIcons name="format-italic" size={18} color="#818384" />
                            </Pressable>
                            <Pressable style={{ padding: 8 }}>
                                <MaterialIcons name="link" size={18} color="#818384" />
                            </Pressable>
                            <Pressable style={{ padding: 8 }}>
                                <MaterialIcons name="strikethrough-s" size={18} color="#818384" />
                            </Pressable>
                            <Pressable style={{ padding: 8 }}>
                                <MaterialIcons name="code" size={18} color="#818384" />
                            </Pressable>
                            <View style={{ flex: 1 }} />
                            <Pressable style={{
                                paddingHorizontal: 16,
                                paddingVertical: 6,
                                backgroundColor: '#ff4500',
                                borderRadius: 20,
                                marginRight: 8,
                            }}>
                                <Text style={{ color: '#fff', fontSize: 14, fontWeight: '600' }}>
                                    Reply
                                </Text>
                            </Pressable>
                        </View>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        paddingHorizontal: 16,
                        paddingBottom: 8,
                    }}>
                        <Pressable style={{ marginRight: 16 }}>
                            <Ionicons name="arrow-up-outline" size={20} color="#818384" />
                        </Pressable>
                        <Text style={{ color: '#818384', fontSize: 16, marginRight: 16 }}>0</Text>
                        <Pressable style={{ marginRight: 16 }}>
                            <Ionicons name="arrow-down-outline" size={20} color="#818384" />
                        </Pressable>
                        <Pressable style={{ marginRight: 16 }}>
                            <Ionicons name="chatbox-outline" size={18} color="#818384" />
                        </Pressable>
                        <Pressable style={{ marginRight: 16 }}>
                            <Ionicons name="share-outline" size={18} color="#818384" />
                        </Pressable>
                        <Pressable>
                            <Ionicons name="bookmark-outline" size={18} color="#818384" />
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'wechat',
            name: '위쳇 스타일',
            description: '중국형 슈퍼앱 스타일',
            preview: (
                <View style={{ backgroundColor: '#ededed' }}>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'flex-end',
                        padding: 8,
                    }}>
                        <Pressable style={{
                            width: 40,
                            height: 40,
                            borderRadius: 20,
                            backgroundColor: '#fff',
                            alignItems: 'center',
                            justifyContent: 'center',
                            marginRight: 8,
                            borderWidth: 1,
                            borderColor: '#e0e0e0',
                        }}>
                            <Ionicons name="mic-outline" size={24} color="#333" />
                        </Pressable>
                        <View style={{
                            flex: 1,
                            backgroundColor: '#fff',
                            borderRadius: 4,
                            paddingHorizontal: 12,
                            paddingVertical: 8,
                            marginRight: 8,
                            borderWidth: 1,
                            borderColor: '#e0e0e0',
                        }}>
                            <TextInput
                                style={{ fontSize: 16, color: '#000' }}
                                placeholder="메시지를 입력하세요"
                                placeholderTextColor="#999"
                                editable={false}
                            />
                        </View>
                        <Pressable style={{
                            width: 40,
                            height: 40,
                            borderRadius: 20,
                            backgroundColor: '#fff',
                            alignItems: 'center',
                            justifyContent: 'center',
                            marginRight: 8,
                            borderWidth: 1,
                            borderColor: '#e0e0e0',
                        }}>
                            <Ionicons name="happy-outline" size={24} color="#333" />
                        </Pressable>
                        <Pressable style={{
                            width: 40,
                            height: 40,
                            borderRadius: 20,
                            backgroundColor: '#fff',
                            alignItems: 'center',
                            justifyContent: 'center',
                            borderWidth: 1,
                            borderColor: '#e0e0e0',
                        }}>
                            <Ionicons name="add" size={24} color="#333" />
                        </Pressable>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        justifyContent: 'space-around',
                        paddingVertical: 12,
                        backgroundColor: '#fff',
                        borderTopWidth: 1,
                        borderTopColor: '#e0e0e0',
                    }}>
                        <Pressable style={{ alignItems: 'center' }}>
                            <Ionicons name="camera" size={24} color="#576b95" />
                            <Text style={{ fontSize: 11, color: '#576b95', marginTop: 2 }}>앨범</Text>
                        </Pressable>
                        <Pressable style={{ alignItems: 'center' }}>
                            <Ionicons name="videocam" size={24} color="#576b95" />
                            <Text style={{ fontSize: 11, color: '#576b95', marginTop: 2 }}>사진</Text>
                        </Pressable>
                        <Pressable style={{ alignItems: 'center' }}>
                            <Ionicons name="call" size={24} color="#576b95" />
                            <Text style={{ fontSize: 11, color: '#576b95', marginTop: 2 }}>통화</Text>
                        </Pressable>
                        <Pressable style={{ alignItems: 'center' }}>
                            <Ionicons name="location" size={24} color="#576b95" />
                            <Text style={{ fontSize: 11, color: '#576b95', marginTop: 2 }}>위치</Text>
                        </Pressable>
                        <Pressable style={{ alignItems: 'center' }}>
                            <MaterialIcons name="attach-money" size={24} color="#576b95" />
                            <Text style={{ fontSize: 11, color: '#576b95', marginTop: 2 }}>송금</Text>
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'obsidian',
            name: '옵시디언 스타일',
            description: '링크 기반 노트 작성',
            preview: (
                <View style={{ backgroundColor: '#202020' }}>
                    <View style={{ padding: 16 }}>
                        <View style={{
                            backgroundColor: '#262626',
                            borderRadius: 6,
                            borderWidth: 1,
                            borderColor: '#404040',
                            padding: 12,
                        }}>
                            <TextInput
                                style={{ 
                                    fontSize: 15, 
                                    color: '#e0e0e0',
                                    fontFamily: Platform.select({ ios: 'Menlo', android: 'monospace' }),
                                }}
                                placeholder="코드를 입력하세요..."
                                placeholderTextColor="#666"
                                editable={false}
                            />
                        </View>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        paddingHorizontal: 20,
                        paddingBottom: 12,
                    }}>
                        <Pressable style={{ padding: 6, marginRight: 8 }}>
                            <Text style={{ color: '#7f6df2', fontSize: 16 }}>[[</Text>
                        </Pressable>
                        <Pressable style={{ padding: 6, marginRight: 8 }}>
                            <MaterialIcons name="tag" size={18} color="#7f6df2" />
                        </Pressable>
                        <Pressable style={{ padding: 6, marginRight: 8 }}>
                            <MaterialIcons name="format-bold" size={18} color="#666" />
                        </Pressable>
                        <Pressable style={{ padding: 6, marginRight: 8 }}>
                            <MaterialIcons name="format-italic" size={18} color="#666" />
                        </Pressable>
                        <Pressable style={{ padding: 6, marginRight: 8 }}>
                            <MaterialIcons name="code" size={18} color="#666" />
                        </Pressable>
                        <View style={{ flex: 1 }} />
                        <Pressable style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            paddingHorizontal: 10,
                            paddingVertical: 4,
                            backgroundColor: '#404040',
                            borderRadius: 4,
                        }}>
                            <Ionicons name="document-text" size={14} color="#e0e0e0" />
                            <Text style={{ color: '#e0e0e0', fontSize: 12, marginLeft: 4 }}>
                                마크다운
                            </Text>
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'snapchat',
            name: '스냅챗 스타일',
            description: '카메라 기반 일회성 메시지',
            preview: (
                <View style={{ backgroundColor: '#000' }}>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        padding: 12,
                    }}>
                        <Pressable style={{
                            width: 50,
                            height: 50,
                            borderRadius: 25,
                            backgroundColor: '#fffc00',
                            alignItems: 'center',
                            justifyContent: 'center',
                            marginRight: 12,
                        }}>
                            <Ionicons name="camera" size={28} color="#000" />
                        </Pressable>
                        <View style={{
                            flex: 1,
                            backgroundColor: '#1a1a1a',
                            borderRadius: 25,
                            paddingHorizontal: 16,
                            paddingVertical: 12,
                            marginRight: 12,
                        }}>
                            <TextInput
                                style={{ fontSize: 16, color: '#fff' }}
                                placeholder="채팅 보내기"
                                placeholderTextColor="#666"
                                editable={false}
                            />
                        </View>
                        <Pressable style={{
                            width: 36,
                            height: 36,
                            borderRadius: 18,
                            backgroundColor: '#1a1a1a',
                            alignItems: 'center',
                            justifyContent: 'center',
                        }}>
                            <MaterialIcons name="more-horiz" size={24} color="#fff" />
                        </Pressable>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        justifyContent: 'center',
                        paddingBottom: 12,
                    }}>
                        <Pressable style={{
                            paddingHorizontal: 16,
                            paddingVertical: 8,
                            backgroundColor: '#fffc00',
                            borderRadius: 20,
                            marginRight: 8,
                        }}>
                                <Text style={{ color: '#000', fontSize: 14, fontWeight: '600' }}>
                                    스냅
                                </Text>
                        </Pressable>
                        <Pressable style={{
                            paddingHorizontal: 16,
                            paddingVertical: 8,
                            backgroundColor: '#1a1a1a',
                            borderRadius: 20,
                            marginRight: 8,
                        }}>
                                <Text style={{ color: '#fff', fontSize: 14 }}>
                                    스티커
                                </Text>
                        </Pressable>
                        <Pressable style={{
                            paddingHorizontal: 16,
                            paddingVertical: 8,
                            backgroundColor: '#1a1a1a',
                            borderRadius: 20,
                        }}>
                                <Text style={{ color: '#fff', fontSize: 14 }}>
                                    게임
                                </Text>
                        </Pressable>
                    </View>
                </View>
            ),
        },
        {
            id: 'teams',
            name: '마이크로소프트 팀즈',
            description: '기업 커뮤니케이션 스타일',
            preview: (
                <View style={{ backgroundColor: '#f5f5f5' }}>
                    <View style={{ padding: 12 }}>
                        <View style={{
                            backgroundColor: '#fff',
                            borderRadius: 4,
                            borderWidth: 1,
                            borderColor: '#e1e1e1',
                            paddingBottom: 8,
                        }}>
                            <View style={{
                                flexDirection: 'row',
                                borderBottomWidth: 1,
                                borderBottomColor: '#e1e1e1',
                                paddingHorizontal: 12,
                                paddingVertical: 8,
                            }}>
                                <Pressable style={{ marginRight: 16 }}>
                                    <MaterialIcons name="format-bold" size={20} color="#605e5c" />
                                </Pressable>
                                <Pressable style={{ marginRight: 16 }}>
                                    <MaterialIcons name="format-italic" size={20} color="#605e5c" />
                                </Pressable>
                                <Pressable style={{ marginRight: 16 }}>
                                    <MaterialIcons name="format-underlined" size={20} color="#605e5c" />
                                </Pressable>
                                <Pressable style={{ marginRight: 16 }}>
                                    <MaterialIcons name="format-color-text" size={20} color="#605e5c" />
                                </Pressable>
                                <View style={{ flex: 1 }} />
                                <Pressable>
                                    <MaterialIcons name="more-horiz" size={20} color="#605e5c" />
                                </Pressable>
                            </View>
                            <TextInput
                                style={{ 
                                    fontSize: 14, 
                                    color: '#201f1e',
                                    paddingHorizontal: 12,
                                    paddingVertical: 8,
                                    minHeight: 40,
                                }}
                                placeholder="새 메시지를 입력하세요"
                                placeholderTextColor="#a19f9d"
                                editable={false}
                            />
                            <View style={{
                                flexDirection: 'row',
                                alignItems: 'center',
                                justifyContent: 'space-between',
                                paddingHorizontal: 12,
                                marginTop: 8,
                            }}>
                                <View style={{ flexDirection: 'row' }}>
                                    <Pressable style={{ marginRight: 16 }}>
                                        <Ionicons name="attach" size={20} color="#605e5c" />
                                    </Pressable>
                                    <Pressable style={{ marginRight: 16 }}>
                                        <Ionicons name="happy-outline" size={20} color="#605e5c" />
                                    </Pressable>
                                    <Pressable>
                                        <MaterialIcons name="gif" size={20} color="#605e5c" />
                                    </Pressable>
                                </View>
                                <Pressable style={{
                                    backgroundColor: '#6264a7',
                                    paddingHorizontal: 20,
                                    paddingVertical: 8,
                                    borderRadius: 4,
                                }}>
                                    <Ionicons name="send" size={16} color="#fff" />
                                </Pressable>
                            </View>
                        </View>
                    </View>
                    <View style={{
                        flexDirection: 'row',
                        alignItems: 'center',
                        paddingHorizontal: 16,
                        paddingBottom: 8,
                    }}>
                        <Pressable style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            paddingHorizontal: 12,
                            paddingVertical: 6,
                            backgroundColor: '#fff',
                            borderRadius: 16,
                            borderWidth: 1,
                            borderColor: '#e1e1e1',
                            marginRight: 8,
                        }}>
                            <Ionicons name="videocam" size={16} color="#6264a7" />
                            <Text style={{ fontSize: 13, color: '#605e5c', marginLeft: 6 }}>
                                지금 만나기
                            </Text>
                        </Pressable>
                        <Pressable style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            paddingHorizontal: 12,
                            paddingVertical: 6,
                            backgroundColor: '#fff',
                            borderRadius: 16,
                            borderWidth: 1,
                            borderColor: '#e1e1e1',
                        }}>
                            <Ionicons name="calendar" size={16} color="#6264a7" />
                            <Text style={{ fontSize: 13, color: '#605e5c', marginLeft: 6 }}>
                                일정
                            </Text>
                        </Pressable>
                    </View>
                </View>
            ),
        },
    ];

    // Render the selected style at the bottom
    const renderActiveInput = () => {
        const style = inputStyles.find(s => s.id === selectedStyle);
        if (!style) return null;
        
        return (
            <View style={{
                position: 'absolute',
                bottom: safeArea.bottom,
                left: 0,
                right: 0,
                backgroundColor: '#fff',
                borderTopWidth: 1,
                borderTopColor: '#e0e0e0',
                ...Platform.select({
                    ios: {
                        shadowColor: '#000',
                        shadowOffset: { width: 0, height: -2 },
                        shadowOpacity: 0.1,
                        shadowRadius: 4,
                    },
                    android: {
                        elevation: 8,
                    },
                }),
            }}>
                <View style={{ paddingBottom: 8, paddingTop: 8 }}>
                    <Text style={{
                        textAlign: 'center',
                        fontSize: 12,
                        color: '#666',
                        marginBottom: 4,
                        ...Typography.default(),
                    }}>
                        현재 스타일: {style.name}
                    </Text>
                    {style.preview}
                </View>
            </View>
        );
    };

    return (
        <View style={{ flex: 1, backgroundColor: '#f5f5f5' }}>
            <ScrollView 
                style={{ flex: 1 }}
                contentContainerStyle={{ 
                    paddingBottom: 250 + safeArea.bottom,
                    paddingTop: 16,
                }}
            >
                <Text style={{
                    fontSize: 24,
                    fontWeight: 'bold',
                    marginBottom: 8,
                    paddingHorizontal: 16,
                    ...Typography.default('semiBold'),
                }}>
                    입력 스타일 목록
                </Text>
                <Text style={{
                    fontSize: 14,
                    color: '#666',
                    marginBottom: 24,
                    paddingHorizontal: 16,
                    ...Typography.default(),
                }}>
                    원하는 스타일을 선택하면 하단 입력창에 미리보기됩니다
                </Text>

                {inputStyles.map((style) => (
                    <Pressable
                        key={style.id}
                        onPress={() => setSelectedStyle(style.id)}
                        style={{
                            marginHorizontal: 16,
                            marginBottom: 16,
                            backgroundColor: '#fff',
                            borderRadius: 12,
                            overflow: 'hidden',
                            borderWidth: selectedStyle === style.id ? 2 : 1,
                            borderColor: selectedStyle === style.id ? '#007AFF' : '#e0e0e0',
                        }}
                    >
                        <View style={{
                            paddingHorizontal: 16,
                            paddingTop: 12,
                            paddingBottom: 8,
                        }}>
                            <View style={{
                                flexDirection: 'row',
                                alignItems: 'center',
                                justifyContent: 'space-between',
                                marginBottom: 4,
                            }}>
                                <Text style={{
                                    fontSize: 18,
                                    fontWeight: '600',
                                    color: '#000',
                                    ...Typography.default('semiBold'),
                                }}>
                                    {style.name}
                                </Text>
                                {selectedStyle === style.id && (
                                    <Ionicons name="checkmark-circle" size={24} color="#007AFF" />
                                )}
                            </View>
                            <Text style={{
                                fontSize: 14,
                                color: '#666',
                                marginBottom: 12,
                                ...Typography.default(),
                            }}>
                                {style.description}
                            </Text>
                        </View>
                        <View style={{
                            borderTopWidth: 1,
                            borderTopColor: '#f0f0f0',
                        }}>
                            {style.preview}
                        </View>
                    </Pressable>
                ))}
            </ScrollView>
            
            {renderActiveInput()}
        </View>
    );
}
