import React from 'react';
import { View, Text, ScrollView, Pressable, ActivityIndicator } from 'react-native';
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { CommonActions, useNavigation } from '@react-navigation/native';
import { Ionicons } from '@/icons/vector-icons';
import { ItemGroup } from '@/components/ItemGroup';
import { Item } from '@/components/Item';
import { Typography } from '@/constants/Typography';
import { useMachine } from '@/sync/storage';
import { machineBash } from '@/sync/ops';
import { resolveAbsolutePath } from '@/utils/pathUtils';
import { t } from '@/text';
import { useUnistyles } from 'react-native-unistyles';
import { layout } from '@/components/layout';
import { joinPathSegment, parentDir, pathRelativeToBase } from '@/utils/basePathUtils';

function bashQuote(value: string): string {
  return `'${value.replace(/'/g, `'\"'\"'`)}'`;
}

async function listChildDirectories(machineId: string, absPath: string): Promise<{ ok: true; dirs: string[] } | { ok: false; error: string }> {
  // Use node (daemon runtime) to list directories safely; run with cwd="/" to bypass daemon cwd validation.
  const script =
    "const fs=require('fs');" +
    "(async()=>{" +
    "try{" +
    "const p=process.argv[1];" +
    "const ents=await fs.promises.readdir(p,{withFileTypes:true});" +
    "const dirs=ents.filter(e=>e.isDirectory()).map(e=>e.name).sort((a,b)=>a.localeCompare(b));" +
    "process.stdout.write(JSON.stringify({success:true,dirs}));" +
    "}catch(e){" +
    "process.stdout.write(JSON.stringify({success:false,error:(e&&e.message)?e.message:String(e)}));" +
    "}" +
    "})();";

  const cmd = `node -e ${bashQuote(script)} ${bashQuote(absPath)}`;
  const result = await machineBash(machineId, cmd, '/');
  const out = (result.stdout || '').trim();
  if (!out) {
    const err = (result.stderr || '').trim();
    return { ok: false, error: err || t('errors.failedToListDirectory') };
  }

  try {
    const parsed = JSON.parse(out);
    if (parsed && parsed.success === true && Array.isArray(parsed.dirs)) {
      return { ok: true, dirs: parsed.dirs.filter((d: any) => typeof d === 'string') };
    }
    return {
      ok: false,
      error:
        parsed && typeof parsed.error === 'string'
          ? parsed.error
          : t('errors.failedToListDirectory'),
    };
  } catch {
    return { ok: false, error: t('errors.failedToParseDirectoryList') };
  }
}

export default function ProjectPickerScreen() {
  const { theme } = useUnistyles();
  const router = useRouter();
  const navigation = useNavigation();
  const params = useLocalSearchParams<{ machineId?: string; basePath?: string }>();

  const machineId = typeof params.machineId === 'string' ? params.machineId : null;
  const machine = useMachine(machineId || '');

  const basePathParam = typeof params.basePath === 'string' ? params.basePath : '';
  const homeDir = machine?.metadata?.homeDir;
  const baseRoot = React.useMemo(() => {
    const fallback = homeDir || '';
    const resolved = resolveAbsolutePath(basePathParam || fallback, homeDir);
    return resolved || fallback;
  }, [basePathParam, homeDir]);

  const [currentPath, setCurrentPath] = React.useState(baseRoot);
  React.useEffect(() => {
    setCurrentPath(baseRoot);
  }, [baseRoot]);

  const [dirs, setDirs] = React.useState<string[]>([]);
  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  const refresh = React.useCallback(async () => {
    if (!machineId) return;
    if (!currentPath) return;
    setLoading(true);
    setError(null);
    try {
      const res = await listChildDirectories(machineId, currentPath);
      if (!res.ok) {
        setDirs([]);
        setError(res.error);
      } else {
        setDirs(res.dirs);
      }
    } finally {
      setLoading(false);
    }
  }, [currentPath, machineId]);

  React.useEffect(() => {
    void refresh();
  }, [refresh]);

  const canGoUp = currentPath && baseRoot && currentPath !== baseRoot;
  const currentPathDisplay = React.useMemo(() => {
    if (!baseRoot) return currentPath;
    return pathRelativeToBase(currentPath, baseRoot);
  }, [baseRoot, currentPath]);

  const selectCurrent = React.useCallback(() => {
    if (!currentPath) return;
    const state = navigation.getState();
    const previousRoute = state?.routes?.[state.index - 1];
    if (state && state.index > 0 && previousRoute) {
      navigation.dispatch({
        ...CommonActions.setParams({ path: currentPath }),
        source: previousRoute.key,
      } as never);
    }
    router.back();
  }, [currentPath, navigation, router]);

  if (!machineId) {
    return (
      <>
        <Stack.Screen
          options={{
            headerShown: true,
            headerTitle: '프로젝트 선택',
            headerBackTitle: t('common.back'),
          }}
        />
        <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center', padding: 16 }}>
          <Text style={[Typography.default(), { color: theme.colors.textSecondary }]}>머신이 선택되지 않았습니다</Text>
        </View>
      </>
    );
  }

  return (
    <>
      <Stack.Screen
        options={{
          headerShown: true,
          headerTitle: '프로젝트 선택',
          headerBackTitle: t('common.back'),
          headerRight: () => (
            <Pressable
              onPress={selectCurrent}
              style={({ pressed }) => ({
                opacity: pressed ? 0.7 : 1,
                padding: 4,
                marginRight: 12,
              })}
            >
              <Ionicons name="checkmark" size={24} color={theme.colors.header.tint} />
            </Pressable>
          ),
        }}
      />

      <ScrollView
        style={{ flex: 1, backgroundColor: theme.colors.groupped.background }}
        contentContainerStyle={{ alignItems: 'center', paddingVertical: 12 }}
        keyboardShouldPersistTaps="handled"
      >
        <View style={{ width: '100%', maxWidth: layout.maxWidth }}>
          <ItemGroup title={t('finishSession.basePath')}>
            <Item
              title={currentPathDisplay || ''}
              subtitleLines={0}
              showChevron={false}
              rightElement={loading ? <ActivityIndicator size="small" color={theme.colors.textSecondary} /> : undefined}
            />
            {error ? (
              <Item
                title="폴더 목록을 불러오지 못했습니다"
                subtitle={error}
                subtitleLines={0}
                showChevron={false}
              />
            ) : null}
          </ItemGroup>

          <ItemGroup title="폴더">
            {canGoUp ? (
              <Item
                title="상위 폴더"
                subtitle="한 단계 위로"
                leftElement={<Ionicons name="arrow-up-outline" size={18} color={theme.colors.textSecondary} />}
                onPress={() => setCurrentPath(parentDir(currentPath))}
                showChevron={false}
              />
            ) : null}

            {dirs.length === 0 && !loading && !error ? (
              <Item
                title="폴더가 없습니다"
                subtitle="이 디렉터리는 하위 폴더가 없습니다."
                showChevron={false}
              />
            ) : null}

            {dirs.map((name, idx) => {
              const isLast = idx === dirs.length - 1;
              return (
                <Item
                  key={name}
                  title={name}
                  leftElement={<Ionicons name="folder-outline" size={18} color={theme.colors.textSecondary} />}
                  onPress={() => setCurrentPath(joinPathSegment(currentPath, name))}
                  showChevron={false}
                  showDivider={!isLast}
                />
              );
            })}
          </ItemGroup>
        </View>
      </ScrollView>
    </>
  );
}
