import React, { useState } from 'react';
import { View, Text, ScrollView, Pressable, Platform, NativeModules } from 'react-native';
import { Stack } from 'expo-router';
import Constants from 'expo-constants';
import * as Updates from 'expo-updates';
import { Ionicons } from '@/icons/vector-icons';
import { Item } from '@/components/Item';
import { ItemGroup } from '@/components/ItemGroup';
import { ItemList } from '@/components/ItemList';
import { Typography } from '@/constants/Typography';
import * as Clipboard from 'expo-clipboard';
import { Modal } from '@/modal';
import { requireOptionalNativeModule } from 'expo-modules-core';
import { config } from '@/config';

interface JsonViewerProps {
    title: string;
    data: any;
    defaultExpanded?: boolean;
}

function JsonViewer({ title, data, defaultExpanded = false }: JsonViewerProps) {
    const [isExpanded, setIsExpanded] = useState(defaultExpanded);
    
    const handleCopy = async () => {
        try {
            await Clipboard.setStringAsync(JSON.stringify(data, null, 2));
            Modal.alert('복사됨', 'JSON 데이터가 클립보드에 복사되었습니다');
        } catch (error) {
            Modal.alert('오류', '클립보드 복사에 실패했습니다');
        }
    };
    
    if (!data) {
        return (
                <Item
                title={title}
                detail="사용 불가"
                showChevron={false}
            />
        );
    }
    
    return (
        <View style={{ marginBottom: 12 }}>
            <Pressable
                style={{
                    flexDirection: 'row',
                    alignItems: 'center',
                    paddingHorizontal: 16,
                    paddingVertical: 12,
                    backgroundColor: 'white',
                }}
                onPress={() => setIsExpanded(!isExpanded)}
            >
                <Ionicons
                    name={isExpanded ? 'chevron-down' : 'chevron-forward'}
                    size={20}
                    color="#8E8E93"
                    style={{ marginRight: 8 }}
                />
                <Text style={{ flex: 1, fontSize: 16, ...Typography.default('semiBold') }}>
                    {title}
                </Text>
                <Pressable
                    onPress={handleCopy}
                    hitSlop={10}
                    style={{ padding: 4 }}
                >
                    <Ionicons name="copy-outline" size={20} color="#007AFF" />
                </Pressable>
            </Pressable>
            
            {isExpanded && (
                <View style={{ 
                    backgroundColor: '#F2F2F7', 
                    paddingHorizontal: 16, 
                    paddingVertical: 12,
                    marginHorizontal: 16,
                    borderRadius: 8,
                    marginTop: -4,
                }}>
                    <ScrollView horizontal showsHorizontalScrollIndicator={true}>
                        <Text style={{ 
                            fontFamily: Platform.select({ ios: 'Menlo', android: 'monospace' }), 
                            fontSize: 12,
                            color: '#000',
                        }}>
                            {JSON.stringify(data, null, 2)}
                        </Text>
                    </ScrollView>
                </View>
            )}
        </View>
    );
}

export default function ExpoConstantsScreen() {
    // Get ExponentConstants native module directly
    const ExponentConstants = requireOptionalNativeModule('ExponentConstants');
    const ExpoUpdates = requireOptionalNativeModule('ExpoUpdates');
    
    // Get raw manifests from native modules (replicating Constants.ts logic)
    let rawExponentManifest = null;
    let parsedExponentManifest = null;
    if (ExponentConstants && ExponentConstants.manifest) {
        rawExponentManifest = ExponentConstants.manifest;
        // On Android, manifest is passed as JSON string
        if (typeof rawExponentManifest === 'string') {
            try {
                parsedExponentManifest = JSON.parse(rawExponentManifest);
            } catch (e) {
                parsedExponentManifest = { parseError: e instanceof Error ? e.message : String(e) };
            }
        } else {
            parsedExponentManifest = rawExponentManifest;
        }
    }
    
    // Get Updates manifest from native module
    let rawUpdatesManifest = null;
    let parsedUpdatesManifest = null;
    if (ExpoUpdates) {
        if (ExpoUpdates.manifest) {
            rawUpdatesManifest = ExpoUpdates.manifest;
            parsedUpdatesManifest = rawUpdatesManifest;
        } else if (ExpoUpdates.manifestString) {
            rawUpdatesManifest = ExpoUpdates.manifestString;
            try {
                parsedUpdatesManifest = JSON.parse(ExpoUpdates.manifestString);
            } catch (e) {
                parsedUpdatesManifest = { parseError: e instanceof Error ? e.message : String(e) };
            }
        }
    }
    
    // Get DevLauncher manifest if available
    let rawDevLauncherManifest = null;
    let parsedDevLauncherManifest = null;
    if (NativeModules.EXDevLauncher && NativeModules.EXDevLauncher.manifestString) {
        rawDevLauncherManifest = NativeModules.EXDevLauncher.manifestString;
        try {
            parsedDevLauncherManifest = JSON.parse(rawDevLauncherManifest);
        } catch (e) {
            parsedDevLauncherManifest = { parseError: e instanceof Error ? e.message : String(e) };
        }
    }
    
    // Get various manifest types from Constants API
    const expoConfig = Constants.expoConfig;
    const manifest = Constants.manifest;
    const manifest2 = Constants.manifest2;
    
    // Get Updates manifest if available
    let updatesManifest = null;
    try {
        // @ts-ignore - manifest might not be typed
        updatesManifest = Updates.manifest;
    } catch (e) {
        // expo-updates might not be available
    }
    
    // Get update ID and channel
    let updateId = null;
    let releaseChannel = null;
    let channel = null;
    let isEmbeddedLaunch = null;
    try {
        // @ts-ignore
        updateId = Updates.updateId;
        // @ts-ignore
        releaseChannel = Updates.releaseChannel;
        // @ts-ignore
        channel = Updates.channel;
        // @ts-ignore
        isEmbeddedLaunch = Updates.isEmbeddedLaunch;
    } catch (e) {
        // Properties might not be available
    }
    
    // Check if running embedded update
    const isEmbedded = ExpoUpdates?.isEmbeddedLaunch;
    
    return (
        <>
            <Stack.Screen
                options={{
                    title: 'Expo 상수',
                    headerLargeTitle: false,
                }}
            />
            <ItemList>
                {/* Main Configuration */}
                <ItemGroup title="Constants API 설정">
                    <JsonViewer
                        title="expoConfig (현재)"
                        data={expoConfig}
                        defaultExpanded={true}
                    />
                    <JsonViewer
                        title="매니페스트 (레거시)"
                        data={manifest}
                    />
                    <JsonViewer
                        title="manifest2"
                        data={manifest2}
                    />
                    {updatesManifest && (
                        <JsonViewer
                            title="Updates 매니페스트"
                            data={updatesManifest}
                        />
                    )}
                </ItemGroup>
                
                {/* Raw Native Module Manifests */}
                <ItemGroup title="네이티브 모듈 매니페스트(원본)">
                    <Item
                        title="임베디드 런치 여부"
                        detail={isEmbedded !== undefined ? (isEmbedded ? '예' : '아니오') : '사용 불가'}
                        showChevron={false}
                    />
                    {parsedExponentManifest && (
                        <JsonViewer
                            title="ExponentConstants 매니페스트 (임베디드)"
                            data={parsedExponentManifest}
                        />
                    )}
                    {parsedUpdatesManifest && (
                        <JsonViewer
                            title="ExpoUpdates 매니페스트 (OTA)"
                            data={parsedUpdatesManifest}
                        />
                    )}
                    {parsedDevLauncherManifest && (
                        <JsonViewer
                            title="DevLauncher 매니페스트"
                            data={parsedDevLauncherManifest}
                        />
                    )}
                </ItemGroup>
                
                {/* Raw String Manifests (for debugging) */}
                <ItemGroup title="매니페스트 원본 문자열">
                    {typeof rawExponentManifest === 'string' && (
                        <JsonViewer
                            title="ExponentConstants 매니페스트 (원본 문자열)"
                            data={{ raw: rawExponentManifest }}
                        />
                    )}
                    {typeof rawUpdatesManifest === 'string' && (
                        <JsonViewer
                            title="ExpoUpdates 원본 문자열"
                            data={{ raw: rawUpdatesManifest }}
                        />
                    )}
                    {rawDevLauncherManifest && (
                        <JsonViewer
                            title="DevLauncher 원본 문자열"
                            data={{ raw: rawDevLauncherManifest }}
                        />
                    )}
                </ItemGroup>
                
                {/* Resolved App Config */}
                <ItemGroup title="해석된 앱 설정">
                        <JsonViewer
                        title="설정 파일에서 불러온 앱 설정 (@/config)"
                        data={config}
                        defaultExpanded={true}
                    />
                </ItemGroup>
                
                {/* System Constants */}
                <ItemGroup title="시스템 상수">
                    <Item
                        title="디바이스 ID"
                        detail={Constants.deviceId || '사용 불가'}
                        showChevron={false}
                    />
                    <Item
                        title="세션 ID"
                        detail={Constants.sessionId}
                        showChevron={false}
                    />
                    <Item
                        title="설치 ID"
                        detail={Constants.installationId}
                        showChevron={false}
                    />
                    <Item
                        title="디바이스 여부"
                        detail={Constants.isDevice ? '예' : '아니오'}
                        showChevron={false}
                    />
                    <Item
                        title="디버그 모드"
                        detail={Constants.debugMode ? '예' : '아니오'}
                        showChevron={false}
                    />
                    <Item
                        title="앱 소유권"
                        detail={Constants.appOwnership || '해당 없음'}
                        showChevron={false}
                    />
                    <Item
                        title="실행 환경"
                        detail={Constants.executionEnvironment || '해당 없음'}
                        showChevron={false}
                    />
                </ItemGroup>
                
                {/* Updates Information */}
                <ItemGroup title="업데이트 정보">
                    <Item
                        title="업데이트 ID"
                        detail={updateId || '사용 불가'}
                        showChevron={false}
                    />
                    <Item
                        title="릴리스 채널"
                        detail={releaseChannel || '사용 불가'}
                        showChevron={false}
                    />
                    <Item
                        title="채널"
                        detail={channel || '사용 불가'}
                        showChevron={false}
                    />
                    <Item
                        title="임베디드 런치 여부"
                        detail={isEmbeddedLaunch !== undefined ? (isEmbeddedLaunch ? '예' : '아니오') : '사용 불가'}
                        showChevron={false}
                    />
                </ItemGroup>
                
                {/* Platform Info */}
                <ItemGroup title="플랫폼 상수">
                    <JsonViewer
                        title="플랫폼 상수"
                        data={Constants.platform}
                    />
                </ItemGroup>
                
                {/* System Fonts */}
                <ItemGroup title="시스템 폰트">
                    <JsonViewer
                        title="사용 가능한 폰트"
                        data={Constants.systemFonts}
                    />
                </ItemGroup>
                
                {/* Native Modules Info */}
                <ItemGroup title="네이티브 모듈">
                    <Item
                        title="ExponentConstants"
                        detail={ExponentConstants ? '사용 가능' : '사용 불가'}
                        showChevron={false}
                    />
                    <Item
                        title="ExpoUpdates"
                        detail={ExpoUpdates ? '사용 가능' : '사용 불가'}
                        showChevron={false}
                    />
                    <Item
                        title="EXDevLauncher"
                        detail={NativeModules.EXDevLauncher ? '사용 가능' : '사용 불가'}
                        showChevron={false}
                    />
                    {ExponentConstants && (
                        <JsonViewer
                            title="ExponentConstants (전체 모듈)"
                            data={ExponentConstants}
                        />
                    )}
                    {ExpoUpdates && (
                        <JsonViewer
                            title="ExpoUpdates (전체 모듈)"
                            data={ExpoUpdates}
                        />
                    )}
                </ItemGroup>
                
                {/* Raw Constants Object */}
                <ItemGroup title="전체 상수(디버그)">
                    <JsonViewer
                        title="전체 상수 객체"
                        data={Constants}
                    />
                </ItemGroup>
            </ItemList>
        </>
    );
}
