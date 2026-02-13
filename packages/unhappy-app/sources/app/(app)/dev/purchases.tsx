import * as React from 'react';
import { View, Text, TextInput, ActivityIndicator } from 'react-native';
import { Stack } from 'expo-router';
import { Item } from '@/components/Item';
import { ItemGroup } from '@/components/ItemGroup';
import { ItemList } from '@/components/ItemList';
import { storage } from '@/sync/storage';
import { sync } from '@/sync/sync';
import { Typography } from '@/constants/Typography';
import { Ionicons } from '@/icons/vector-icons';
import { Modal } from '@/modal';

export default function PurchasesDevScreen() {
    // Get purchases directly from storage
    const purchases = storage(state => state.purchases);

    // State for purchase form
    const [productId, setProductId] = React.useState('');
    const [isPurchasing, setIsPurchasing] = React.useState(false);
    const [offerings, setOfferings] = React.useState<any>(null);
    const [loadingOfferings, setLoadingOfferings] = React.useState(false);

    // Sort entitlements alphabetically
    const sortedEntitlements = React.useMemo(() => {
        return Object.entries(purchases.entitlements).sort(([a], [b]) => a.localeCompare(b));
    }, [purchases.entitlements]);

    const handlePurchase = async () => {
        if (!productId.trim()) {
            Modal.alert('오류', '상품 ID를 입력해 주세요');
            return;
        }

        setIsPurchasing(true);
        try {
            const result = await sync.purchaseProduct(productId.trim());
            if (result.success) {
                Modal.alert('성공', '구매가 완료되었습니다');
                setProductId('');
            } else {
                Modal.alert('구매 실패', result.error || '알 수 없는 오류');
            }
        } catch (e) {
            console.error('Error purchasing product', e);
        } finally {
            setIsPurchasing(false);
        }
    };

    const fetchOfferings = async () => {
        setLoadingOfferings(true);
        try {
            const result = await sync.getOfferings();
            if (result.success) {
                setOfferings(result.offerings);

                // Log full offerings data
                console.log('=== RevenueCat Offerings ===');
                console.log('현재 오퍼링:', result.offerings.current?.identifier || '없음');

                if (result.offerings.current) {
                    console.log('\nCurrent Offering Packages:');
                    Object.entries(result.offerings.current.availablePackages || {}).forEach(([key, pkg]: [string, any]) => {
                        console.log(`  - ${key}: ${pkg.product.identifier} (${pkg.product.priceString})`);
                    });
                }

                console.log('\nAll Offerings:');
                Object.entries(result.offerings.all || {}).forEach(([id, offering]: [string, any]) => {
                    console.log(`  - ${id} (${Object.keys(offering.availablePackages || {}).length} packages)`);
                });

                console.log('\nFull JSON:', JSON.stringify(result.offerings, null, 2));
                console.log('===========================');
            } else {
                Modal.alert('오류', result.error || '오퍼링 조회 실패');
            }
        } finally {
            setLoadingOfferings(false);
        }
    };

    return (
        <>
            <Stack.Screen
                options={{
                    title: '구매',
                    headerShown: true
                }}
            />

            <ItemList>
                {/* Active Subscriptions */}
                <ItemGroup
                    title="활성 구독"
                    footer={purchases.activeSubscriptions.length === 0 ? "활성 구독이 없습니다" : undefined}
                >
                    {purchases.activeSubscriptions.length > 0 ? (
                        purchases.activeSubscriptions.map((productId, index) => (
                            <Item
                                key={index}
                                title={productId}
                                icon={<Ionicons name="checkmark-circle" size={29} color="#34C759" />}
                                showChevron={false}
                            />
                        ))
                    ) : null}
                </ItemGroup>

                {/* Entitlements */}
                <ItemGroup
                    title="권한"
                    footer={sortedEntitlements.length === 0 ? "권한 항목이 없습니다" : "녹색=활성, 회색=비활성"}
                >
                    {sortedEntitlements.length > 0 ? (
                        sortedEntitlements.map(([id, isActive]) => (
                            <Item
                                key={id}
                                title={id}
                                icon={
                                    <Ionicons
                                        name={isActive ? "checkmark-circle" : "close-circle"}
                                        size={29}
                                        color={isActive ? "#34C759" : "#8E8E93"}
                                    />
                                }
                                detail={isActive ? "활성" : "비활성"}
                                showChevron={false}
                            />
                        ))
                    ) : null}
                </ItemGroup>

                {/* Purchase Product */}
                <ItemGroup title="상품 구매" footer="구매할 상품 ID를 입력하세요">
                    <View style={{
                        backgroundColor: '#fff',
                        paddingHorizontal: 16,
                        paddingVertical: 12
                    }}>
                        <TextInput
                            value={productId}
                            onChangeText={setProductId}
                            placeholder="상품 ID 입력"
                            style={{
                                fontSize: 17,
                                paddingVertical: 8,
                                paddingHorizontal: 12,
                                backgroundColor: '#F2F2F7',
                                borderRadius: 8,
                                marginBottom: 12,
                                ...Typography.default()
                            }}
                            editable={!isPurchasing}
                            autoCapitalize="none"
                            autoCorrect={false}
                        />
                        <Item
                            title={isPurchasing ? "구매 진행 중..." : "구매"}
                            icon={isPurchasing ?
                                <ActivityIndicator size="small" color="#007AFF" /> :
                                <Ionicons name="card-outline" size={29} color="#007AFF" />
                            }
                            onPress={handlePurchase}
                            disabled={isPurchasing}
                            showChevron={false}
                        />
                    </View>
                </ItemGroup>

                {/* Actions */}
                <ItemGroup title="동작">
                    <Item
                        title="구매 정보 갱신"
                        icon={<Ionicons name="refresh-outline" size={29} color="#007AFF" />}
                        onPress={() => sync.refreshPurchases()}
                    />
                    <Item
                        title={loadingOfferings ? "오퍼링 로딩 중..." : "오퍼링 로그"}
                        icon={loadingOfferings ?
                            <ActivityIndicator size="small" color="#007AFF" /> :
                            <Ionicons name="document-text-outline" size={29} color="#007AFF" />
                        }
                        onPress={fetchOfferings}
                        disabled={loadingOfferings}
                    />
                </ItemGroup>

                {/* Offerings Info */}
                {offerings && (
                    <ItemGroup title="오퍼링" footer="전체 상세 내용은 콘솔 로그를 확인하세요">
                        <Item
                            title="현재 오퍼링"
                            detail={offerings.current?.identifier || '없음'}
                            showChevron={false}
                        />
                        <Item
                            title="전체 오퍼링"
                            detail={Object.keys(offerings.all || {}).length.toString()}
                            showChevron={false}
                        />
                        {offerings.current && (
                            <Item
                                title="사용 가능 패키지"
                                detail={Object.keys(offerings.current.availablePackages || {}).length.toString()}
                                showChevron={false}
                            />
                        )}
                    </ItemGroup>
                )}

                {/* Debug Info */}
                <ItemGroup title="디버그 정보">
                    <Item
                        title="RevenueCat 상태"
                        detail={sync.revenueCatInitialized ? "초기화됨" : "초기화 안 됨"}
                        showChevron={false}
                    />
                    <Item
                        title="사용자 ID"
                        detail={sync.serverID || "사용 불가"}
                        showChevron={false}
                    />
                </ItemGroup>
            </ItemList>
        </>
    );
}
