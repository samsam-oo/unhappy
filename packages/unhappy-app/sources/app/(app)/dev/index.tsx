import * as React from 'react';
import { ActivityIndicator } from 'react-native';
import { Ionicons } from '@/icons/vector-icons';
import { Item } from '@/components/Item';
import { ItemGroup } from '@/components/ItemGroup';
import { ItemList } from '@/components/ItemList';
import { useRouter } from 'expo-router';
import Constants from 'expo-constants';
import * as Application from 'expo-application';
import { useLocalSettingMutable, useSocketStatus } from '@/sync/storage';
import { Modal } from '@/modal';
import { sync } from '@/sync/sync';
import { getServerUrl, setServerUrl, validateServerUrl } from '@/sync/serverConfig';
import { Switch } from '@/components/Switch';
import { useUnistyles } from 'react-native-unistyles';
import { setLastViewedVersion, getLatestVersion } from '@/changelog';

export default function DevScreen() {
    const router = useRouter();
    const [debugMode, setDebugMode] = useLocalSettingMutable('debugMode');
    const [verboseLogging, setVerboseLogging] = React.useState(false);
    const socketStatus = useSocketStatus();
    const anonymousId = sync.encryption!.anonID;
    const { theme } = useUnistyles();

    const handleEditServerUrl = async () => {
        const currentUrl = getServerUrl();

        const newUrl = await Modal.prompt(
            'API 엔드포인트 수정',
            '서버 URL을 입력하세요:',
            {
                defaultValue: currentUrl,
                confirmText: '저장'
            }
        );

        if (newUrl && newUrl !== currentUrl) {
            const validation = validateServerUrl(newUrl);
            if (validation.valid) {
                setServerUrl(newUrl);
                Modal.alert('성공', '서버 URL이 업데이트되었습니다. 변경사항을 적용하려면 앱을 재시작하세요.');
            } else {
                Modal.alert('잘못된 URL', validation.error || '유효한 URL을 입력해 주세요.');
            }
        }
    };

    const handleClearCache = async () => {
        const confirmed = await Modal.confirm(
            '캐시 삭제',
            '저장된 캐시 데이터를 모두 삭제하시겠습니까?',
            { confirmText: '삭제', destructive: true }
        );
        if (confirmed) {
            console.log('캐시가 삭제되었습니다');
            Modal.alert('성공', '캐시가 삭제되었습니다');
        }
    };

    // 시간 표시 문자열을 변환하는 함수
    const formatTimeAgo = (timestamp: number | null): string => {
        if (!timestamp) return '';

        const now = Date.now();
        const diff = now - timestamp;
        const seconds = Math.floor(diff / 1000);
        const minutes = Math.floor(seconds / 60);
        const hours = Math.floor(minutes / 60);
        const days = Math.floor(hours / 24);

        if (seconds < 10) return '방금';
        if (seconds < 60) return `${seconds}초 전`;
        if (minutes < 60) return `${minutes}분 전`;
        if (hours < 24) return `${hours}시간 전`;
        if (days < 7) return `${days}일 전`;

        return new Date(timestamp).toLocaleDateString();
    };

    // 소켓 연결 상태 부제목 계산 함수
    const getSocketStatusSubtitle = (): string => {
        const { status, lastConnectedAt, lastDisconnectedAt } = socketStatus;

        if (status === 'connected' && lastConnectedAt) {
            return `연결됨 ${formatTimeAgo(lastConnectedAt)}`;
        } else if ((status === 'disconnected' || status === 'error') && lastDisconnectedAt) {
            return `마지막 연결 ${formatTimeAgo(lastDisconnectedAt)}`;
        } else if (status === 'connecting') {
            return '서버에 연결 중...';
        }

        return '연결 정보 없음';
    };

    // 소켓 상태 표시 컴포넌트
    const SocketStatusIndicator = () => {
        switch (socketStatus.status) {
            case 'connected':
                return <Ionicons name="checkmark-circle" size={22} color="#34C759" />;
            case 'connecting':
                return <ActivityIndicator size="small" color={theme.colors.textSecondary} />;
            case 'error':
                return <Ionicons name="close-circle" size={22} color="#FF3B30" />;
            case 'disconnected':
                return <Ionicons name="close-circle" size={22} color="#FF9500" />;
            default:
                return <Ionicons name="help-circle" size={22} color="#8E8E93" />;
        }
    };

    return (
        <ItemList>
            {/* App Information */}
            <ItemGroup title="앱 정보">
                <Item
                    title="버전"
                    detail={Constants.expoConfig?.version || '1.0.0'}
                />
                <Item
                    title="빌드 번호"
                    detail={Application.nativeBuildVersion || '해당 없음'}
                />
                <Item
                    title="SDK 버전"
                    detail={Constants.expoConfig?.sdkVersion || '알 수 없음'}
                />
                <Item
                    title="플랫폼"
                    detail={`${Constants.platform?.ios ? 'iOS' : 'Android'} ${Constants.systemVersion || ''}`}
                />
                <Item
                    title="익명 ID"
                    detail={anonymousId}
                />
            </ItemGroup>

            {/* Debug Options */}
            <ItemGroup title="디버그 옵션">
                <Item
                    title="디버그 모드"
                    rightElement={
                        <Switch
                            value={debugMode}
                            onValueChange={setDebugMode}
                        />
                    }
                    showChevron={false}
                />
                <Item
                    title="상세 로그"
                    subtitle="모든 네트워크 요청 및 응답을 로그에 기록"
                    rightElement={
                        <Switch
                            value={verboseLogging}
                            onValueChange={setVerboseLogging}
                        />
                    }
                    showChevron={false}
                />
                <Item
                    title="로그 보기"
                    icon={<Ionicons name="document-text-outline" size={28} color="#007AFF" />}
                    onPress={() => router.push('/dev/logs')}
                />
            </ItemGroup>

            {/* Component Demos */}
            <ItemGroup title="컴포넌트 데모">
                <Item
                    title="기기 정보"
                    subtitle="안전 영역 인셋과 기기 파라미터"
                    icon={<Ionicons name="phone-portrait-outline" size={28} color="#007AFF" />}
                    onPress={() => router.push('/dev/device-info')}
                />
                <Item
                    title="목록 컴포넌트"
                    subtitle="목록, 리스트 그룹, 리스트 아이템 예시"
                    icon={<Ionicons name="list-outline" size={28} color="#007AFF" />}
                    onPress={() => router.push('/dev/list-demo')}
                />
                <Item
                    title="타이포그래피"
                    subtitle="전체 타이포그래피 스타일"
                    icon={<Ionicons name="text-outline" size={28} color="#007AFF" />}
                    onPress={() => router.push('/dev/typography')}
                />
                <Item
                    title="색상"
                    subtitle="색상 팔레트와 테마"
                    icon={<Ionicons name="color-palette-outline" size={28} color="#007AFF" />}
                    onPress={() => router.push('/dev/colors')}
                />
                <Item
                    title="메시지 데모"
                    subtitle="다양한 메시지 유형과 컴포넌트"
                    icon={<Ionicons name="chatbubbles-outline" size={28} color="#007AFF" />}
                    onPress={() => router.push('/dev/messages-demo')}
                />
                <Item
                    title="반전 리스트 테스트"
                    subtitle="키보드 환경에서 역순 리스트 테스트"
                    icon={<Ionicons name="swap-vertical-outline" size={28} color="#007AFF" />}
                    onPress={() => router.push('/dev/inverted-list')}
                />
                <Item
                    title="도구 뷰"
                    subtitle="도구 호출 시각화 컴포넌트"
                    icon={<Ionicons name="construct-outline" size={28} color="#007AFF" />}
                    onPress={() => router.push('/dev/tools2')}
                />
                <Item
                    title="쉐이머 뷰"
                    subtitle="마스크가 적용된 쉬머 로딩 효과"
                    icon={<Ionicons name="sparkles-outline" size={28} color="#007AFF" />}
                    onPress={() => router.push('/dev/shimmer-demo')}
                />
                <Item
                    title="멀티라인 텍스트 입력"
                    subtitle="자동으로 커지는 다중줄 입력"
                    icon={<Ionicons name="create-outline" size={28} color="#007AFF" />}
                    onPress={() => router.push('/dev/multi-text-input')}
                />
                <Item
                    title="입력 스타일"
                    subtitle="10개 이상의 다양한 입력 필드 스타일"
                    icon={<Ionicons name="color-palette-outline" size={28} color="#007AFF" />}
                    onPress={() => router.push('/dev/input-styles')}
                />
                <Item
                    title="모달 시스템"
                    subtitle="알림, 확인 및 커스텀 모달"
                    icon={<Ionicons name="albums-outline" size={28} color="#007AFF" />}
                    onPress={() => router.push('/dev/modal-demo')}
                />
                <Item
                    title="단위 테스트"
                    subtitle="앱 환경에서 테스트 실행"
                    icon={<Ionicons name="flask-outline" size={28} color="#34C759" />}
                    onPress={() => router.push('/dev/tests')}
                />
                <Item
                    title="Unistyles 데모"
                    subtitle="리액트 네이티브 Unistyles 기능"
                    icon={<Ionicons name="brush-outline" size={28} color="#FF6B6B" />}
                    onPress={() => router.push('/dev/unistyles-demo')}
                />
                <Item
                    title="QR 코드 테스트"
                    subtitle="다양한 파라미터로 QR 코드 생성 테스트"
                    icon={<Ionicons name="qr-code-outline" size={28} color="#007AFF" />}
                    onPress={() => router.push('/dev/qr-test')}
                />
                <Item
                    title="Todo 데모"
                    subtitle="인라인 편집 및 정렬이 가능한 할 일 목록"
                    icon={<Ionicons name="checkbox-outline" size={28} color="#34C759" />}
                    onPress={() => router.push('/dev/todo-demo')}
                />
            </ItemGroup>

            {/* Test Features */}
            <ItemGroup title="테스트 기능" footer="일부 동작은 앱 안정성에 영향을 줄 수 있습니다">
                <Item
                    title="Claude OAuth 테스트"
                    subtitle="Claude 인증 플로우 테스트"
                    icon={<Ionicons name="key-outline" size={28} color="#007AFF" />}
                    onPress={() => router.push('/settings/connect/claude')}
                />
                <Item
                    title="테스트 크래시"
                    subtitle="테스트 크래시를 실행합니다"
                    destructive={true}
                    icon={<Ionicons name="warning-outline" size={28} color="#FF3B30" />}
                    onPress={async () => {
                        const confirmed = await Modal.confirm(
                            '테스트 크래시',
                            '앱이 충돌될 예정입니다. 계속하시겠습니까?',
                            { confirmText: '크래시', destructive: true }
                        );
                        if (confirmed) {
                        throw new Error('개발 메뉴에서 테스트 크래시가 실행되었습니다');
                        }
                    }}
                />
                <Item
                    title="캐시 삭제"
                    subtitle="모든 캐시 데이터 삭제"
                    icon={<Ionicons name="trash-outline" size={28} color="#FF9500" />}
                    onPress={handleClearCache}
                />
                <Item
                    title="변경로그 재표시"
                    subtitle="새 소식 배너를 다시 표시"
                    icon={<Ionicons name="sparkles-outline" size={28} color="#007AFF" />}
                    onPress={() => {
                        // 최신 버전을 기준으로 1 감소시켜 미확인 상태로 유지
                        // 0으로 설정하면 최초 설치 판정 로직이 동작해 자동으로 읽음 처리됨
                        const latest = getLatestVersion();
                        setLastViewedVersion(Math.max(0, latest - 1));
                        Modal.alert('완료', '변경로그가 초기화되었습니다. 배너를 보려면 앱을 재시작하세요.');
                    }}
                />
                <Item
                    title="앱 상태 초기화"
                    subtitle="모든 사용자 데이터와 설정 삭제"
                    destructive={true}
                    icon={<Ionicons name="refresh-outline" size={28} color="#FF3B30" />}
                    onPress={async () => {
                        const confirmed = await Modal.confirm(
                            '앱 상태 초기화',
                            '모든 데이터가 삭제됩니다. 계속하시겠습니까?',
                            { confirmText: '초기화', destructive: true }
                        );
                        if (confirmed) {
                        console.log('앱 상태가 초기화되었습니다');
                        }
                    }}
                />
            </ItemGroup>

            {/* System */}
            <ItemGroup title="시스템">
                <Item
                    title="구매 내역"
                    subtitle="구독 및 권한 항목 확인"
                    icon={<Ionicons name="card-outline" size={28} color="#007AFF" />}
                    onPress={() => router.push('/dev/purchases')}
                />
                <Item
                    title="Expo 상수"
                    subtitle="expoConfig, 매니페스트, 시스템 상수 조회"
                    icon={<Ionicons name="information-circle-outline" size={28} color="#007AFF" />}
                    onPress={() => router.push('/dev/expo-constants')}
                />
            </ItemGroup>

            {/* Network */}
            <ItemGroup title="네트워크">
                <Item
                    title="API 엔드포인트"
                    detail={getServerUrl()}
                    onPress={handleEditServerUrl}
                    detailStyle={{ flex: 1, textAlign: 'right', minWidth: '70%' }}
                />
                <Item
                    title="Socket.IO 상태"
                    subtitle={getSocketStatusSubtitle()}
                    detail={socketStatus.status}
                    rightElement={<SocketStatusIndicator />}
                    showChevron={false}
                />
            </ItemGroup>
        </ItemList>
    );
}
