import React from 'react';
import { View, Text, ScrollView, Dimensions, Platform, PixelRatio } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Stack } from 'expo-router';
import { Typography } from '@/constants/Typography';
import { ItemGroup } from '@/components/ItemGroup';
import { Item } from '@/components/Item';
import { ItemList } from '@/components/ItemList';
import Constants from 'expo-constants';
import { useIsTablet, getDeviceType, calculateDeviceDimensions, useHeaderHeight } from '@/utils/responsive';
import { layout } from '@/components/layout';
import { isRunningOnMac } from '@/utils/platform';

export default function DeviceInfo() {
    const insets = useSafeAreaInsets();
    const { width, height } = Dimensions.get('window');
    const screenDimensions = Dimensions.get('screen');
    const pixelDensity = PixelRatio.get();
    const isTablet = useIsTablet();
    const deviceType = getDeviceType();
    const headerHeight = useHeaderHeight();
    const isRunningOnMacCatalyst = isRunningOnMac();
    
    // Calculate device dimensions using the correct function
    const dimensions = calculateDeviceDimensions({
        widthPoints: screenDimensions.width,
        heightPoints: screenDimensions.height,
        pointsPerInch: Platform.OS === 'ios' ? 163 : 160
    });
    
    const { widthInches, heightInches, diagonalInches } = dimensions;
    
    return (
        <>
            <Stack.Screen
                options={{
                    title: '기기 정보',
                    headerLargeTitle: false,
                }}
            />
            <ItemList>
                <ItemGroup title="안전 영역 인셋">
                    <Item
                        title="상단"
                        detail={`${insets.top}px`}
                    />
                    <Item
                        title="하단"
                        detail={`${insets.bottom}px`}
                    />
                    <Item
                        title="왼쪽"
                        detail={`${insets.left}px`}
                    />
                    <Item
                        title="오른쪽"
                        detail={`${insets.right}px`}
                    />
                </ItemGroup>

                <ItemGroup title="기기 감지">
                    <Item
                        title="기기 종류"
                        detail={deviceType === 'tablet' ? '태블릿' : '휴대폰'}
                    />
                    <Item
                        title="감지 방식"
                        // @ts-ignore - isPad is not in the type definitions but exists at runtime on iOS
                        detail={Platform.OS === 'ios' && Platform.isPad ? 'iOS iPad' : `${diagonalInches.toFixed(1)}" 대각선`}
                    />
                    <Item
                        title="Mac 카탈리스트"
                        detail={isRunningOnMacCatalyst ? '예' : '아니오'}
                    />
                    <Item
                        title="헤더 높이"
                        detail={`${headerHeight} 포인트`}
                    />
                    <Item
                        title="대각선 크기"
                        detail={`${diagonalInches.toFixed(2)} 인치`}
                    />
                    <Item
                        title="너비 (인치)"
                        detail={`${widthInches.toFixed(2)}"`}
                    />
                    <Item
                        title="높이 (인치)"
                        detail={`${heightInches.toFixed(2)}"`}
                    />
                    <Item
                        title="픽셀 밀도"
                        detail={`${pixelDensity}x`}
                    />
                    <Item
                        title="인치당 포인트"
                        detail={Platform.OS === 'ios' ? '163' : '160'}
                    />
                    <Item
                        title="최대 레이아웃 너비"
                        detail={`${layout.maxWidth}px`}
                    />
                </ItemGroup>

                <ItemGroup title="화면 크기">
                    <Item
                        title="창 너비"
                        detail={`${width} 포인트`}
                    />
                    <Item
                        title="창 높이"
                        detail={`${height} 포인트`}
                    />
                    <Item
                        title="화면 너비"
                        detail={`${screenDimensions.width} 포인트`}
                    />
                    <Item
                        title="화면 높이"
                        detail={`${screenDimensions.height} 포인트`}
                    />
                    <Item
                        title="실제 픽셀 (너비)"
                        detail={`${Math.round(screenDimensions.width * pixelDensity)}px`}
                    />
                    <Item
                        title="실제 픽셀 (높이)"
                        detail={`${Math.round(screenDimensions.height * pixelDensity)}px`}
                    />
                    <Item
                        title="가로 세로 비율"
                        detail={`${(height / width).toFixed(3)}`}
                    />
                </ItemGroup>

                <ItemGroup title="플랫폼 정보">
                    <Item
                        title="플랫폼"
                        detail={Platform.OS}
                    />
                    <Item
                        title="버전"
                        detail={Platform.Version?.toString() || '해당 없음'}
                    />
                    {Platform.OS === 'ios' && (
                        <>
                            <Item
                                title="iOS 인터페이스"
                                // @ts-ignore - isPad is not in the type definitions but exists at runtime on iOS
                                detail={Platform.isPad ? 'iPad' : 'iPhone'}
                            />
                            <Item
                                title="iOS 버전"
                                detail={Platform.Version?.toString() || '해당 없음'}
                            />
                        </>
                    )}
                    {Platform.OS === 'android' && (
                        <Item
                            title="API 레벨"
                            detail={Platform.Version?.toString() || '해당 없음'}
                        />
                    )}
                </ItemGroup>

                <ItemGroup title="앱 정보">
                    <Item
                        title="앱 버전"
                        detail={Constants.expoConfig?.version || '해당 없음'}
                    />
                    <Item
                        title="SDK 버전"
                        detail={Constants.expoConfig?.sdkVersion || '해당 없음'}
                    />
                    <Item
                        title="빌드 번호"
                        detail={Constants.expoConfig?.ios?.buildNumber || Constants.expoConfig?.android?.versionCode?.toString() || '해당 없음'}
                    />
                </ItemGroup>
            </ItemList>
        </>
    );
}
