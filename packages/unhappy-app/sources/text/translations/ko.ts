import type { TranslationStructure } from '../_default';

/**
 * Korean translations for the Unhappy app
 * Values can be:
 * - String constants for static text
 * - Functions with typed object parameters for dynamic text
 */

export const ko: TranslationStructure = {
  tabs: {
    // Tab navigation labels
    inbox: '수신함',
    sessions: '터미널',
    settings: '설정',
  },

  inbox: {
    // Inbox screen
    emptyTitle: '비어 있는 수신함',
    emptyDescription: '친구와 연결하여 세션 공유를 시작하세요',
    updates: '업데이트',
  },

  common: {
    // Simple string constants
    cancel: '취소',
    authenticate: '인증',
    save: '저장',
    saveAs: '다른 이름으로 저장',
    open: '열기',
    commit: '커밋',
    error: '오류',
    success: '성공',
    ok: '확인',
    continue: '계속',
    back: '뒤로',
    create: '생성',
    rename: '이름 변경',
    reset: '재설정',
    logout: '로그아웃',
    yes: '예',
    no: '아니오',
    discard: '버리기',
    version: '버전',
    copy: '복사',
    copied: '복사됨',
    scanning: '스캔 중...',
    urlPlaceholder: 'https://example.com',
    home: '홈',
    message: '메시지',
    files: '파일',
    fileViewer: '파일 뷰어',
    loading: '로딩 중...',
    retry: '다시 시도',
    delete: '삭제',
    optional: '선택 사항',
  },

  profile: {
    userProfile: '사용자 프로필',
    details: '세부 정보',
    firstName: '이름',
    lastName: '성',
    username: '사용자 이름',
    status: '상태',
  },

  status: {
    connected: '연결됨',
    connecting: '연결 중',
    disconnected: '연결 끊김',
    error: '오류',
    online: '온라인',
    offline: '오프라인',
    lastSeen: ({ time }: { time: string }) => `마지막 접속 ${time}`,
    permissionRequired: '권한 필요',
    activeNow: '현재 활동 중',
    unknown: '알 수 없음',
  },

  time: {
    justNow: '방금',
    minutesAgo: ({ count }: { count: number }) => `${count}분 전`,
    hoursAgo: ({ count }: { count: number }) => `${count}시간 전`,
  },

  connect: {
    restoreAccount: '계정 복원',
    enterSecretKey: '비밀 키를 입력하세요',
    invalidSecretKey: '비밀 키가 올바르지 않습니다. 확인 후 다시 시도하세요.',
    enterUrlManually: 'URL 직접 입력',
  },

  settings: {
    title: '설정',
    connectedAccounts: '연결된 계정',
    connectAccount: '계정 연결',
    github: 'GitHub',
    machines: '머신',
    features: '기능',
    social: '소셜',
    account: '계정',
    accountSubtitle: '계정 정보를 관리',
    appearance: '모양',
    appearanceSubtitle: '앱 외관을 사용자 지정',
    voiceAssistant: '음성 어시스턴트',
    voiceAssistantSubtitle: '음성 상호작용 환경설정',
    featuresTitle: '기능',
    featuresSubtitle: '앱 기능을 켜거나 끄기',
    developer: '개발자',
    developerTools: '개발자 도구',
    about: '정보',
    aboutFooter:
      'Unhappy Coder는 Codex와 Claude Code용 모바일 클라이언트입니다. 종단 간 암호화를 제공하며 계정 정보는 기기에만 저장됩니다. Anthropic과는 관련이 없습니다. slopus/happy가 원작 라이선스 업스트림임을 존중하며 그 출처를 명확히 표기합니다.',
    whatsNew: '새로운 소식',
    whatsNewSubtitle: '최신 업데이트와 개선 사항을 확인하세요',
    reportIssue: '문제 신고',
    privacyPolicy: '개인정보 처리방침',
    termsOfService: '서비스 이용약관',
    eula: 'EULA',
    supportUs: '후원하기',
    supportUsSubtitlePro: '후원해 주셔서 감사합니다!',
    supportUsSubtitle: '프로젝트 개발을 지원',
    scanQrCodeToAuthenticate: 'QR 코드를 스캔하여 인증',
    githubConnected: ({ login }: { login: string }) => `@${login}로 연결됨`,
    connectGithubAccount: 'GitHub 계정을 연결',
    claudeAuthSuccess: 'Claude에 성공적으로 연결되었습니다',
    exchangingTokens: '토큰 교환 중...',
    usage: '사용량',
    usageSubtitle: 'API 사용량과 비용 보기',
    profiles: '프로필',
    profilesSubtitle: '세션용 환경 변수 프로필 관리',

    // Dynamic settings messages
    accountConnected: ({ service }: { service: string }) =>
      `${service} 계정이 연결되었습니다`,
    machineStatus: ({
      name,
      status,
    }: {
      name: string;
      status: 'online' | 'offline';
    }) => `${name}은(는) ${status === 'online' ? '온라인' : '오프라인'}입니다`,
    featureToggled: ({
      feature,
      enabled,
    }: {
      feature: string;
      enabled: boolean;
    }) => `${feature} ${enabled ? '활성화됨' : '비활성화됨'}`,
  },

  settingsAppearance: {
    // Appearance settings screen
    theme: '테마',
    themeDescription: '선호하는 색상 테마를 선택하세요',
    themeOptions: {
      adaptive: '자동',
      light: '라이트',
      dark: '다크',
    },
    themeDescriptions: {
      adaptive: '시스템 설정과 동일하게',
      light: '항상 라이트 테마',
      dark: '항상 다크 테마',
    },
    display: '표시',
    displayDescription: '레이아웃과 간격을 조정',
    inlineToolCalls: '인라인 도구 호출',
    inlineToolCallsDescription: '채팅 메시지에 도구 호출을 바로 표시',
    expandTodoLists: '할 일 목록 펼치기',
    expandTodoListsDescription: '변경 사항만이 아니라 모든 할 일을 표시',
    showLineNumbersInDiffs: 'diff에 줄 번호 표시',
    showLineNumbersInDiffsDescription: '코드 diff에 줄 번호를 표시',
    showLineNumbersInToolViews: '도구 뷰에 줄 번호 표시',
    showLineNumbersInToolViewsDescription: '도구 뷰 diff에 줄 번호를 표시',
    wrapLinesInDiffs: 'diff 줄 바꿈',
    wrapLinesInDiffsDescription: 'diff 뷰에서 긴 줄을 가로 스크롤 대신 줄 바꿈',
    avatarStyle: '아바타 스타일',
    avatarStyleDescription: '세션 아바타 모양을 선택',
    avatarOptions: {
      pixelated: '픽셀',
      gradient: '그라디언트',
      brutalist: '브루탈리즘',
    },
    showFlavorIcons: 'AI 제공자 아이콘 표시',
    showFlavorIconsDescription: '세션 아바타에 AI 제공자 아이콘 표시',
    compactSessionView: '컴팩트 세션 보기',
    compactSessionViewDescription: '활성 세션을 더 컴팩트한 레이아웃으로 표시',
  },

  settingsFeatures: {
    // Features settings screen
    experiments: '실험',
    experimentsDescription:
      '아직 개발 중인 실험 기능을 활성화합니다. 이 기능들은 불안정하거나 예고 없이 변경될 수 있습니다.',
    experimentalFeatures: '실험 기능',
    experimentalFeaturesEnabled: '실험 기능이 활성화되었습니다',
    experimentalFeaturesDisabled: '안정 기능만 사용 중',
    webFeatures: '웹 기능',
    webFeaturesDescription: '앱의 웹 버전에서만 사용 가능한 기능입니다.',
    enterToSend: 'Enter로 전송',
    enterToSendEnabled: 'Enter를 눌러 메시지 전송',
    enterToSendDisabled: '⌘+Enter를 눌러 메시지 전송',
    commandPalette: '커맨드 팔레트',
    commandPaletteEnabled: '⌘K를 눌러 열기',
    commandPaletteDisabled: '빠른 명령 접근이 비활성화됨',
    markdownCopyV2: '마크다운 복사 v2',
    markdownCopyV2Subtitle: '길게 누르면 복사 모달이 열립니다',
    hideInactiveSessions: '비활성 세션 숨기기',
    hideInactiveSessionsSubtitle: '목록에 활성 채팅만 표시',
    enhancedSessionWizard: '향상된 세션 마법사',
    enhancedSessionWizardEnabled: '프로필 우선 세션 런처가 활성화됨',
    enhancedSessionWizardDisabled: '표준 세션 런처 사용 중',
  },

  errors: {
    networkError: '네트워크 오류가 발생했습니다',
    serverError: '서버 오류가 발생했습니다',
    unknownError: '알 수 없는 오류가 발생했습니다',
    connectionTimeout: '연결 시간이 초과되었습니다',
    authenticationFailed: '인증에 실패했습니다',
    permissionDenied: '권한이 거부되었습니다',
    fileNotFound: '파일을 찾을 수 없습니다',
    invalidFormat: '형식이 올바르지 않습니다',
    operationFailed: '작업에 실패했습니다',
    tryAgain: '다시 시도해 주세요',
    contactSupport: '문제가 계속되면 지원팀에 문의하세요',
    sessionNotFound: '세션을 찾을 수 없습니다',
    voiceSessionFailed: '음성 세션 시작에 실패했습니다',
    voiceServiceUnavailable: '음성 서비스를 일시적으로 사용할 수 없습니다',
    oauthInitializationFailed: 'OAuth 흐름 초기화에 실패했습니다',
    tokenStorageFailed: '인증 토큰 저장에 실패했습니다',
    oauthStateMismatch: '보안 검증에 실패했습니다. 다시 시도해 주세요',
    tokenExchangeFailed: '인증 코드를 교환하는 데 실패했습니다',
    oauthAuthorizationDenied: '권한 부여가 거부되었습니다',
    webViewLoadFailed: '인증 페이지 로드에 실패했습니다',
    failedToLoadProfile: '사용자 프로필 로드에 실패했습니다',
    userNotFound: '사용자를 찾을 수 없습니다',
    sessionDeleted: '세션이 삭제되었습니다',
    sessionDeletedDescription: '이 세션은 영구적으로 제거되었습니다',

    // Error functions with context
    fieldError: ({ field, reason }: { field: string; reason: string }) =>
      `${field}: ${reason}`,
    validationError: ({
      field,
      min,
      max,
    }: {
      field: string;
      min: number;
      max: number;
    }) => `${field}은(는) ${min}에서 ${max} 사이여야 합니다`,
    retryIn: ({ seconds }: { seconds: number }) => `${seconds}초 후 다시 시도`,
    errorWithCode: ({
      message,
      code,
    }: {
      message: string;
      code: number | string;
    }) => `${message} (오류 ${code})`,
    disconnectServiceFailed: ({ service }: { service: string }) =>
      `${service} 연결 해제에 실패했습니다`,
    connectServiceFailed: ({ service }: { service: string }) =>
      `${service} 연결에 실패했습니다. 다시 시도해 주세요.`,
    failedToLoadFriends: '친구 목록 로드에 실패했습니다',
    failedToAcceptRequest: '친구 요청 수락에 실패했습니다',
    failedToRejectRequest: '친구 요청 거절에 실패했습니다',
    failedToRemoveFriend: '친구 삭제에 실패했습니다',
    searchFailed: '검색에 실패했습니다. 다시 시도해 주세요.',
    failedToSendRequest: '친구 요청 전송에 실패했습니다',
  },

  newSession: {
    // Used by new-session screen and launch flows
    title: '새 세션 시작',
    noMachinesFound:
      '머신을 찾을 수 없습니다. 먼저 컴퓨터에서 Unhappy 세션을 시작하세요.',
    allMachinesOffline: '모든 머신이 오프라인인 것 같습니다',
    machineDetails: '머신 세부 정보 보기 →',
    directoryDoesNotExist: '디렉터리를 찾을 수 없음',
    createDirectoryConfirm: ({ directory }: { directory: string }) =>
      `디렉터리 ${directory}이(가) 존재하지 않습니다. 생성하시겠습니까?`,
    sessionStarted: '세션이 시작되었습니다',
    sessionStartedMessage: '세션이 성공적으로 시작되었습니다.',
    sessionSpawningFailed:
      '세션 생성에 실패했습니다 (세션 ID가 반환되지 않았습니다).',
    startingSession: '세션 시작 중...',
    startNewSessionInFolder: '여기서 새 세션',
    failedToStart:
      '세션 시작에 실패했습니다. 대상 머신에서 데몬이 실행 중인지 확인하세요.',
    sessionTimeout:
      '세션 시작 시간이 초과되었습니다. 머신이 느리거나 데몬이 응답하지 않을 수 있습니다.',
    notConnectedToServer:
      '서버에 연결되지 않았습니다. 인터넷 연결을 확인하세요.',
    noMachineSelected: '세션을 시작할 머신을 선택하세요',
    noPathSelected: '세션을 시작할 디렉터리를 선택하세요',
    sessionType: {
      title: '세션 유형',
      simple: '단순',
      worktree: '워크트리',
      comingSoon: '준비 중',
    },
    worktree: {
      nameLabel: '워크트리 이름',
      namePlaceholder: '예: swift-island',
      nameHint: 'git 브랜치 이름으로 사용됩니다. 워크트리 폴더 이름은 안전하게 변환됩니다.',
      creating: ({ name }: { name: string }) => `워크트리 '${name}' 생성 중...`,
      notGitRepo: '워크트리는 Git 저장소가 필요합니다',
      failed: ({ error }: { error: string }) =>
        `워크트리 생성에 실패했습니다: ${error}`,
      success: '워크트리가 성공적으로 생성되었습니다',
    },
  },

  sessionHistory: {
    // Used by session history screen
    title: '세션 기록',
    empty: '세션이 없습니다',
    today: '오늘',
    yesterday: '어제',
    daysAgo: ({ count }: { count: number }) => `${count}일 전`,
    viewAll: '모든 세션 보기',
  },

  session: {
    inputPlaceholder: '메시지를 입력하세요 ...',
  },

  commandPalette: {
    placeholder: '명령을 입력하거나 검색하세요...',
  },

  server: {
    // Used by Server Configuration screen (app/(app)/server.tsx)
    serverConfiguration: '서버 설정',
    enterServerUrl: '서버 URL을 입력하세요',
    notValidHappyServer: '유효한 Unhappy Server가 아닙니다',
    changeServer: '서버 변경',
    continueWithServer: '이 서버로 계속할까요?',
    resetToDefault: '기본값으로 재설정',
    resetServerDefault: '서버를 기본값으로 재설정할까요?',
    validating: '검증 중...',
    validatingServer: '서버 검증 중...',
    serverReturnedError: '서버에서 오류를 반환했습니다',
    failedToConnectToServer: '서버에 연결하지 못했습니다',
    currentlyUsingCustomServer: '사용자 지정 서버를 사용 중입니다',
    customServerUrlLabel: '사용자 지정 서버 URL',
    advancedFeatureFooter:
      '이 기능은 고급 기능입니다. 무엇을 하는지 알고 있을 때만 서버를 변경하세요. 서버 변경 후에는 로그아웃 후 다시 로그인해야 합니다.',
  },

  sessionInfo: {
    // Used by Session Info screen (app/(app)/session/[id]/info.tsx)
    killSession: '세션 종료',
    killSessionConfirm: '이 세션을 종료하시겠습니까?',
    archiveSession: '세션 보관',
    archiveSessionConfirm: '이 세션을 보관하시겠습니까?',
    happySessionIdCopied: 'Unhappy 세션 ID가 클립보드에 복사되었습니다',
    failedToCopySessionId: 'Unhappy 세션 ID 복사에 실패했습니다',
    happySessionId: 'Unhappy 세션 ID',
    claudeCodeSessionId: 'Claude Code 세션 ID',
    claudeCodeSessionIdCopied:
      'Claude Code 세션 ID가 클립보드에 복사되었습니다',
    codexSessionId: 'Codex 세션 ID',
    codexSessionIdCopied: 'Codex 세션 ID가 클립보드에 복사되었습니다',
    aiProvider: 'AI 제공자',
    failedToCopyClaudeCodeSessionId: 'Claude Code 세션 ID 복사에 실패했습니다',
    failedToCopyCodexSessionId: 'Codex 세션 ID 복사에 실패했습니다',
    metadataCopied: '메타데이터가 클립보드에 복사되었습니다',
    failedToCopyMetadata: '메타데이터 복사에 실패했습니다',
    failedToKillSession: '세션 종료에 실패했습니다',
    failedToArchiveSession: '세션 보관에 실패했습니다',
    connectionStatus: '연결 상태',
    created: '생성됨',
    lastUpdated: '마지막 업데이트',
    sequence: '시퀀스',
    quickActions: '빠른 작업',
    viewMachine: '머신 보기',
    viewMachineSubtitle: '머신 세부 정보와 세션 보기',
    killSessionSubtitle: '세션을 즉시 종료',
    archiveSessionSubtitle: '이 세션을 보관하고 중지',
    metadata: '메타데이터',
    host: '호스트',
    path: '경로',
    operatingSystem: '운영체제',
    processId: '프로세스 ID',
    happyHome: 'Unhappy 홈',
    copyMetadata: '메타데이터 복사',
    agentState: '에이전트 상태',
    controlledByUser: '사용자가 제어 중',
    pendingRequests: '대기 중인 요청',
    activity: '활동',
    thinking: '생각 중',
    thinkingSince: '생각 시작',
    cliVersion: 'CLI 버전',
    cliVersionOutdated: 'CLI 업데이트 필요',
    cliVersionOutdatedMessage: ({
      currentVersion,
      requiredVersion,
    }: {
      currentVersion: string;
      requiredVersion: string;
    }) =>
      `설치된 버전: ${currentVersion}. ${requiredVersion} 이상으로 업데이트하세요`,
    updateCliInstructions: 'npm install -g unhappy-coder@latest 를 실행하세요',
    deleteSession: '세션 삭제',
    deleteSessionSubtitle: '이 세션을 영구적으로 제거',
    deleteSessionConfirm: '세션을 영구적으로 삭제할까요?',
    deleteSessionWarning:
      '이 작업은 되돌릴 수 없습니다. 이 세션과 관련된 모든 메시지와 데이터가 영구적으로 삭제됩니다.',
    failedToDeleteSession: '세션 삭제에 실패했습니다',
    sessionDeleted: '세션이 성공적으로 삭제되었습니다',
  },

  components: {
    emptyMainScreen: {
      // Used by EmptyMainScreen component
      readyToCode: '코딩할 준비가 되셨나요?',
      installCli: 'Unhappy CLI 설치',
      runIt: '실행하기',
      scanQrCode: 'QR 코드를 스캔하세요',
      openCamera: '카메라 열기',
    },
  },

  agentInput: {
    permissionMode: {
      title: '권한 모드',
      default: '기본',
      acceptEdits: '수정 허용',
      plan: '플랜 모드',
      bypassPermissions: 'YOLO 모드',
      badgeAcceptAllEdits: '모든 수정 허용',
      badgeBypassAllPermissions: '모든 권한 우회',
      badgePlanMode: '플랜 모드',
    },
    agent: {
      claude: 'Claude',
      codex: 'Codex',
      gemini: 'Gemini',
    },
    model: {
      title: '모델',
      configureInCli: 'CLI 설정에서 모델을 구성하세요',
    },
    codexPermissionMode: {
      title: 'CODEX 권한 모드',
      default: 'CLI 설정',
      readOnly: '읽기 전용 모드',
      safeYolo: '안전 YOLO',
      yolo: 'YOLO',
      badgeReadOnly: '읽기 전용 모드',
      badgeSafeYolo: '안전 YOLO',
      badgeYolo: 'YOLO',
    },
    codexModel: {
      title: 'CODEX 모델',
      gpt5CodexLow: 'gpt-5-codex low',
      gpt5CodexMedium: 'gpt-5-codex medium',
      gpt5CodexHigh: 'gpt-5-codex high',
      gpt5Minimal: 'GPT-5 Minimal',
      gpt5Low: 'GPT-5 Low',
      gpt5Medium: 'GPT-5 Medium',
      gpt5High: 'GPT-5 High',
    },
    geminiPermissionMode: {
      title: 'GEMINI 권한 모드',
      default: '기본',
      readOnly: '읽기 전용',
      safeYolo: '안전 YOLO',
      yolo: 'YOLO',
      badgeReadOnly: '읽기 전용',
      badgeSafeYolo: '안전 YOLO',
      badgeYolo: 'YOLO',
    },
    context: {
      remaining: ({ percent }: { percent: number }) => `${percent}% 남음`,
    },
    suggestion: {
      fileLabel: '파일',
      folderLabel: '폴더',
    },
    noMachinesAvailable: '사용 가능한 머신 없음',
  },

  machineLauncher: {
    showLess: '접기',
    showAll: ({ count }: { count: number }) => `모두 보기 (${count}개 경로)`,
    enterCustomPath: '사용자 지정 경로 입력',
    offlineUnableToSpawn: '오프라인 상태에서는 새 세션을 만들 수 없습니다',
  },

  sidebar: {
    sessionsTitle: 'Unhappy',
  },

  toolView: {
    input: '입력',
    output: '출력',
  },

  tools: {
    fullView: {
      description: '설명',
      inputParams: '입력 파라미터',
      output: '출력',
      error: '오류',
      completed: '도구가 성공적으로 완료되었습니다',
      noOutput: '출력이 없습니다',
      running: '도구 실행 중...',
      rawJsonDevMode: 'Raw JSON (개발자 모드)',
    },
    taskView: {
      initializing: '에이전트 초기화 중...',
      moreTools: ({ count }: { count: number }) => `+${count}개 더`,
    },
    multiEdit: {
      editNumber: ({ index, total }: { index: number; total: number }) =>
        `${total}개 중 ${index}번째 편집`,
      replaceAll: '모두 바꾸기',
    },
    names: {
      task: '작업',
      terminal: '터미널',
      searchFiles: '파일 검색',
      search: '검색',
      searchContent: '내용 검색',
      listFiles: '파일 목록',
      planProposal: '플랜 제안',
      readFile: '파일 읽기',
      editFile: '파일 편집',
      writeFile: '파일 쓰기',
      fetchUrl: 'URL 가져오기',
      readNotebook: '노트북 읽기',
      editNotebook: '노트북 편집',
      todoList: '할 일 목록',
      webSearch: '웹 검색',
      reasoning: '추론',
      applyChanges: '파일 업데이트',
      viewDiff: '현재 파일 변경 사항',
      question: '질문',
    },
    askUserQuestion: {
      submit: '답변 제출',
      multipleQuestions: ({ count }: { count: number }) => `${count}개 질문`,
      other: '기타',
      otherDescription: '직접 답변을 입력하세요',
      otherPlaceholder: '답변을 입력하세요...',
    },
    desc: {
      terminalCmd: ({ cmd }: { cmd: string }) => `터미널 \u2022 ${cmd}`,
      searchPattern: ({ pattern }: { pattern: string }) =>
        `검색(pattern: ${pattern})`,
      searchPath: ({ basename }: { basename: string }) =>
        `검색(path: ${basename})`,
      fetchUrlHost: ({ host }: { host: string }) =>
        `URL 가져오기(url: ${host})`,
      editNotebookMode: ({ path, mode }: { path: string; mode: string }) =>
        `노트북 편집(file: ${path}, mode: ${mode})`,
      todoListCount: ({ count }: { count: number }) =>
        `할 일 목록(count: ${count})`,
      webSearchQuery: ({ query }: { query: string }) =>
        `웹 검색(query: ${query})`,
      grepPattern: ({ pattern }: { pattern: string }) =>
        `grep(pattern: ${pattern})`,
      multiEditEdits: ({ path, count }: { path: string; count: number }) =>
        `${path} (${count}개 편집)`,
      readingFile: ({ file }: { file: string }) => `${file} 읽는 중`,
      writingFile: ({ file }: { file: string }) => `${file} 쓰는 중`,
      modifyingFile: ({ file }: { file: string }) => `${file} 수정 중`,
      modifyingFiles: ({ count }: { count: number }) =>
        `${count}개 파일 수정 중`,
      modifyingMultipleFiles: ({
        file,
        count,
      }: {
        file: string;
        count: number;
      }) => `${file} 외 ${count}개`,
      showingDiff: '변경 사항 표시 중',
    },
  },

  files: {
    searchPlaceholder: '파일 검색...',
    detachedHead: 'detached HEAD',
    summary: ({ staged, unstaged }: { staged: number; unstaged: number }) =>
      `${staged}개 스테이징 • ${unstaged}개 미스테이징`,
    notRepo: 'Git 저장소가 아닙니다',
    notUnderGit: '이 디렉터리는 Git 버전 관리 하에 있지 않습니다',
    searching: '파일 검색 중...',
    noFilesFound: '파일을 찾을 수 없습니다',
    noFilesInProject: '프로젝트에 파일이 없습니다',
    tryDifferentTerm: '다른 검색어를 사용해 보세요',
    searchResults: ({ count }: { count: number }) => `검색 결과 (${count})`,
    projectRoot: '프로젝트 루트',
    stagedChanges: ({ count }: { count: number }) =>
      `스테이징된 변경 사항 (${count})`,
    unstagedChanges: ({ count }: { count: number }) =>
      `미스테이징 변경 사항 (${count})`,
    // File viewer strings
    loadingFile: ({ fileName }: { fileName: string }) =>
      `${fileName} 로딩 중...`,
    binaryFile: '바이너리 파일',
    cannotDisplayBinary: '바이너리 파일 내용은 표시할 수 없습니다',
    diff: 'diff',
    file: '파일',
    fileEmpty: '파일이 비어 있습니다',
    noChanges: '표시할 변경 사항이 없습니다',
  },

  settingsVoice: {
    // Voice settings screen
    languageTitle: '언어',
    languageDescription:
      '음성 어시스턴트와의 상호작용에 사용할 언어를 선택하세요. 이 설정은 모든 기기에서 동기화됩니다.',
    preferredLanguage: '선호 언어',
    preferredLanguageSubtitle: '음성 어시스턴트 응답에 사용되는 언어',
    language: {
      searchPlaceholder: '언어 검색...',
      title: '언어',
      footer: ({ count }: { count: number }) => `${count}개 언어 사용 가능`,
      autoDetect: '자동 감지',
    },
  },

  settingsAccount: {
    // Account settings screen
    accountInformation: '계정 정보',
    status: '상태',
    statusActive: '활성',
    statusNotAuthenticated: '인증되지 않음',
    anonymousId: '익명 ID',
    publicId: '공개 ID',
    notAvailable: '사용할 수 없음',
    linkNewDevice: '새 기기 연결',
    linkNewDeviceSubtitle: 'QR 코드를 스캔하여 기기를 연결',
    profile: '프로필',
    name: '이름',
    github: 'GitHub',
    tapToDisconnect: '탭하여 연결 해제',
    server: '서버',
    backup: '백업',
    backupDescription:
      '비밀 키는 계정을 복구할 수 있는 유일한 방법입니다. 비밀번호 관리자 같은 안전한 장소에 저장해 두세요.',
    secretKey: '비밀 키',
    tapToReveal: '탭하여 표시',
    tapToHide: '탭하여 숨기기',
    secretKeyLabel: '비밀 키 (탭하여 복사)',
    secretKeyCopied:
      '비밀 키가 클립보드에 복사되었습니다. 안전한 곳에 보관하세요!',
    secretKeyCopyFailed: '비밀 키 복사에 실패했습니다',
    privacy: '개인정보',
    privacyDescription:
      '익명 사용 데이터를 공유하여 앱 개선에 도움을 주세요. 개인 정보는 수집되지 않습니다.',
    analytics: '분석',
    analyticsDisabled: '데이터가 공유되지 않습니다',
    analyticsEnabled: '익명 사용 데이터가 공유됩니다',
    dangerZone: '위험 구역',
    logout: '로그아웃',
    logoutSubtitle: '로그아웃하고 로컬 데이터를 삭제',
    logoutConfirm: '로그아웃하시겠습니까? 비밀 키를 백업했는지 확인하세요!',
  },

  settingsLanguage: {
    // Language settings screen
    title: '언어',
    description:
      '앱 인터페이스에 사용할 언어를 선택하세요. 이 설정은 모든 기기에서 동기화됩니다.',
    currentLanguage: '현재 언어',
    automatic: '자동',
    automaticSubtitle: '기기 설정에서 감지',
    needsRestart: '언어가 변경되었습니다',
    needsRestartMessage: '새 언어 설정을 적용하려면 앱을 재시작해야 합니다.',
    restartNow: '지금 재시작',
  },

  connectButton: {
    authenticate: '터미널 인증',
    authenticateWithUrlPaste: 'URL 붙여넣기로 터미널 인증',
    pasteAuthUrl: '터미널에서 제공된 인증 URL을 붙여넣으세요',
  },

  updateBanner: {
    updateAvailable: '업데이트가 있습니다',
    pressToApply: '눌러서 업데이트를 적용하세요',
    whatsNew: '새로운 소식',
    seeLatest: '최신 업데이트와 개선 사항 보기',
    nativeUpdateAvailable: '앱 업데이트 가능',
    tapToUpdateAppStore: '탭하여 App Store에서 업데이트',
    tapToUpdatePlayStore: '탭하여 Play Store에서 업데이트',
  },

  changelog: {
    // Used by the changelog screen
    version: ({ version }: { version: number }) => `버전 ${version}`,
    noEntriesAvailable: '변경 로그 항목이 없습니다.',
  },

  terminal: {
    // Used by terminal connection screens
    webBrowserRequired: '웹 브라우저가 필요합니다',
    webBrowserRequiredDescription:
      '보안상의 이유로 터미널 연결 링크는 웹 브라우저에서만 열 수 있습니다. QR 코드 스캐너를 사용하거나 컴퓨터에서 이 링크를 여세요.',
    processingConnection: '연결 처리 중...',
    invalidConnectionLink: '연결 링크가 올바르지 않습니다',
    invalidConnectionLinkDescription:
      '연결 링크가 없거나 올바르지 않습니다. URL을 확인하고 다시 시도하세요.',
    connectTerminal: '터미널 연결',
    terminalRequestDescription:
      '터미널이 Unhappy Coder 계정에 연결을 요청하고 있습니다. 이 연결을 통해 터미널이 안전하게 메시지를 송수신할 수 있습니다.',
    connectionDetails: '연결 세부 정보',
    publicKey: '공개 키',
    encryption: '암호화',
    endToEndEncrypted: '종단 간 암호화',
    acceptConnection: '연결 수락',
    connecting: '연결 중...',
    reject: '거절',
    security: '보안',
    securityFooter:
      '이 연결 링크는 브라우저에서 안전하게 처리되었으며 어떤 서버로도 전송되지 않았습니다. 개인 데이터는 안전하게 유지되며 메시지를 복호화할 수 있는 사람은 당신뿐입니다.',
    securityFooterDevice:
      '이 연결은 기기에서 안전하게 처리되었으며 어떤 서버로도 전송되지 않았습니다. 개인 데이터는 안전하게 유지되며 메시지를 복호화할 수 있는 사람은 당신뿐입니다.',
    clientSideProcessing: '클라이언트 측 처리',
    linkProcessedLocally: '브라우저에서 로컬로 링크 처리됨',
    linkProcessedOnDevice: '기기에서 로컬로 링크 처리됨',
  },

  modals: {
    // Used across connect flows and settings
    authenticateTerminal: '터미널 인증',
    pasteUrlFromTerminal: '터미널의 인증 URL을 붙여넣으세요',
    deviceLinkedSuccessfully: '기기가 성공적으로 연결되었습니다',
    terminalConnectedSuccessfully: '터미널이 성공적으로 연결되었습니다',
    invalidAuthUrl: '인증 URL이 올바르지 않습니다',
    developerMode: '개발자 모드',
    developerModeEnabled: '개발자 모드가 활성화되었습니다',
    developerModeDisabled: '개발자 모드가 비활성화되었습니다',
    disconnectGithub: 'GitHub 연결 해제',
    disconnectGithubConfirm: 'GitHub 계정 연결을 해제하시겠습니까?',
    disconnectService: ({ service }: { service: string }) =>
      `${service} 연결 해제`,
    disconnectServiceConfirm: ({ service }: { service: string }) =>
      `계정에서 ${service} 연결을 해제하시겠습니까?`,
    disconnect: '연결 해제',
    failedToConnectTerminal: '터미널 연결에 실패했습니다',
    cameraPermissionsRequiredToConnectTerminal:
      '터미널을 연결하려면 카메라 권한이 필요합니다',
    failedToLinkDevice: '기기 연결에 실패했습니다',
    cameraPermissionsRequiredToScanQr:
      'QR 코드를 스캔하려면 카메라 권한이 필요합니다',
  },

  navigation: {
    // Navigation titles and screen headers
    connectTerminal: '터미널 연결',
    linkNewDevice: '새 기기 연결',
    restoreWithSecretKey: '비밀 키로 복원',
    whatsNew: '새로운 소식',
    friends: '친구',
  },

  welcome: {
    // Main welcome screen for unauthenticated users
    title: 'Codex 및 Claude Code 모바일 클라이언트',
    subtitle: '종단 간 암호화되며 계정은 기기에만 저장됩니다.',
    createAccount: '계정 만들기',
    linkOrRestoreAccount: '연결 또는 복원',
    loginWithMobileApp: '모바일 앱으로 로그인',
  },

  review: {
    // Used by utils/requestReview.ts
    enjoyingApp: '앱이 마음에 드시나요?',
    feedbackPrompt: '의견을 들려주시면 감사하겠습니다!',
    yesILoveIt: '네, 정말 좋아요!',
    notReally: '그다지요',
  },

  items: {
    // Used by Item component for copy toast
    copiedToClipboard: ({ label }: { label: string }) =>
      `${label}이(가) 클립보드에 복사되었습니다`,
  },

  machine: {
    launchNewSessionInDirectory: '디렉터리에서 새 세션 실행',
    offlineUnableToSpawn: '머신이 오프라인이면 런처를 사용할 수 없습니다',
    offlineHelp:
      '• 컴퓨터가 온라인인지 확인하세요\n• `unhappy daemon status`를 실행하여 진단하세요\n• 최신 CLI 버전인가요? `npm install -g unhappy-coder@latest`로 업그레이드하세요',
    daemon: '데몬',
    status: '상태',
    stopDaemon: '데몬 중지',
    lastKnownPid: '마지막으로 알려진 PID',
    lastKnownHttpPort: '마지막으로 알려진 HTTP 포트',
    startedAt: '시작 시간',
    cliVersion: 'CLI 버전',
    daemonStateVersion: '데몬 상태 버전',
    activeSessions: ({ count }: { count: number }) => `활성 세션 (${count})`,
    machineGroup: '머신',
    host: '호스트',
    machineId: '머신 ID',
    username: '사용자 이름',
    homeDirectory: '홈 디렉터리',
    platform: '플랫폼',
    architecture: '아키텍처',
    lastSeen: '마지막 접속',
    never: '없음',
    metadataVersion: '메타데이터 버전',
    untitledSession: '제목 없는 세션',
    back: '뒤로',
  },

  message: {
    switchedToMode: ({ mode }: { mode: string }) =>
      `${mode} 모드로 전환했습니다`,
    unknownEvent: '알 수 없는 이벤트',
    usageLimitUntil: ({ time }: { time: string }) =>
      `${time}까지 사용량 제한이 적용됩니다`,
    unknownTime: '알 수 없는 시간',
  },

  codex: {
    // Codex permission dialog buttons
    permissions: {
      yesForSession: '예 (이 세션)',
      stopAndExplain: '중지하고 설명',
    },
  },

  claude: {
    // Claude permission dialog buttons
    permissions: {
      yesAllowAllEdits: '예 (이번 세션만)',
      yesForTool: '예 (이 툴에 대해서만)',
      noTellClaude: '아니오 (메시지 보내기)',
    },
  },

  textSelection: {
    // Text selection screen
    selectText: '텍스트 범위 선택',
    title: '텍스트 선택',
    noTextProvided: '제공된 텍스트가 없습니다',
    textNotFound: '텍스트를 찾을 수 없거나 만료되었습니다',
    textCopied: '텍스트가 클립보드에 복사되었습니다',
    failedToCopy: '텍스트 클립보드 복사에 실패했습니다',
    noTextToCopy: '복사할 텍스트가 없습니다',
  },

  markdown: {
    // Markdown copy functionality
    codeCopied: '코드가 복사되었습니다',
    copyFailed: '복사에 실패했습니다',
    mermaidRenderFailed: 'Mermaid 다이어그램 렌더링에 실패했습니다',
  },

  artifacts: {
    // Artifacts feature
    title: '아티팩트',
    countSingular: '아티팩트 1개',
    countPlural: ({ count }: { count: number }) => `아티팩트 ${count}개`,
    empty: '아직 아티팩트가 없습니다',
    emptyDescription: '첫 번째 아티팩트를 만들어 보세요',
    new: '새 아티팩트',
    edit: '아티팩트 편집',
    delete: '삭제',
    updateError: '아티팩트 업데이트에 실패했습니다. 다시 시도해 주세요.',
    notFound: '아티팩트를 찾을 수 없습니다',
    discardChanges: '변경 사항을 버릴까요?',
    discardChangesDescription:
      '저장되지 않은 변경 사항이 있습니다. 정말로 버리시겠습니까?',
    deleteConfirm: '아티팩트를 삭제할까요?',
    deleteConfirmDescription: '이 작업은 되돌릴 수 없습니다',
    titleLabel: '제목',
    titlePlaceholder: '아티팩트 제목을 입력하세요',
    bodyLabel: '내용',
    bodyPlaceholder: '여기에 내용을 작성하세요...',
    emptyFieldsError: '제목 또는 내용을 입력하세요',
    createError: '아티팩트 생성에 실패했습니다. 다시 시도해 주세요.',
    save: '저장',
    saving: '저장 중...',
    loading: '아티팩트 로딩 중...',
    error: '아티팩트 로드에 실패했습니다',
  },

  friends: {
    // Friends feature
    title: '친구',
    manageFriends: '친구와 연결을 관리하세요',
    searchTitle: '친구 찾기',
    pendingRequests: '친구 요청',
    myFriends: '내 친구',
    noFriendsYet: '아직 친구가 없습니다',
    findFriends: '친구 찾기',
    remove: '삭제',
    pendingRequest: '대기 중',
    sentOn: ({ date }: { date: string }) => `${date}에 보냄`,
    accept: '수락',
    reject: '거절',
    addFriend: '친구 추가',
    alreadyFriends: '이미 친구입니다',
    requestPending: '요청 대기 중',
    searchInstructions: '사용자 이름을 입력하여 친구를 검색하세요',
    searchPlaceholder: '사용자 이름 입력...',
    searching: '검색 중...',
    userNotFound: '사용자를 찾을 수 없습니다',
    noUserFound: '해당 사용자 이름의 사용자가 없습니다',
    checkUsername: '사용자 이름을 확인하고 다시 시도하세요',
    howToFind: '친구 찾는 방법',
    findInstructions:
      '사용자 이름으로 친구를 검색하세요. 친구 요청을 보내려면 나와 친구 모두 GitHub 연결이 필요합니다.',
    requestSent: '친구 요청을 보냈습니다!',
    requestAccepted: '친구 요청이 수락되었습니다!',
    requestRejected: '친구 요청이 거절되었습니다',
    friendRemoved: '친구가 삭제되었습니다',
    confirmRemove: '친구 삭제',
    confirmRemoveMessage: '이 친구를 삭제하시겠습니까?',
    cannotAddYourself: '자기 자신에게 친구 요청을 보낼 수 없습니다',
    bothMustHaveGithub:
      '두 사용자 모두 GitHub가 연결되어 있어야 친구가 될 수 있습니다',
    status: {
      none: '연결되지 않음',
      requested: '요청 보냄',
      pending: '요청 대기',
      friend: '친구',
      rejected: '거절됨',
    },
    acceptRequest: '요청 수락',
    removeFriend: '친구 삭제',
    removeFriendConfirm: ({ name }: { name: string }) =>
      `${name}을(를) 친구에서 삭제하시겠습니까?`,
    requestSentDescription: ({ name }: { name: string }) =>
      `${name}에게 친구 요청을 보냈습니다`,
    requestFriendship: '친구 요청',
    cancelRequest: '친구 요청 취소',
    cancelRequestConfirm: ({ name }: { name: string }) =>
      `${name}에게 보낸 친구 요청을 취소할까요?`,
    denyRequest: '친구 요청 거절',
    nowFriendsWith: ({ name }: { name: string }) =>
      `${name}과(와) 친구가 되었습니다`,
  },

  usage: {
    // Usage panel strings
    today: '오늘',
    last7Days: '최근 7일',
    last30Days: '최근 30일',
    totalTokens: '총 토큰',
    totalCost: '총 비용',
    tokens: '토큰',
    cost: '비용',
    usageOverTime: '기간별 사용량',
    byModel: '모델별',
    noData: '사용량 데이터가 없습니다',
  },

  feed: {
    // Feed notifications for friend requests and acceptances
    friendRequestFrom: ({ name }: { name: string }) =>
      `${name}님이 친구 요청을 보냈습니다`,
    friendRequestGeneric: '새 친구 요청',
    friendAccepted: ({ name }: { name: string }) =>
      `${name}님과 친구가 되었습니다`,
    friendAcceptedGeneric: '친구 요청이 수락되었습니다',
  },

  finishSession: {
    title: '세션 완료',
    subtitle: '머지, PR 생성 또는 워크트리 정리',
    branchName: '브랜치',
    basePath: '기본 저장소',
    uncommittedWarning: '이 워크트리에 커밋되지 않은 변경 사항이 있습니다',
    commitChanges: '변경 사항 커밋',
    commitChangesSubtitle: '모든 변경 사항을 스테이징하고 커밋합니다',
    commitMessageTitle: '커밋 메시지',
    commitMessagePrompt: '커밋 메시지를 입력하세요:',
    commitConfirm: '커밋',
    commitMessageRequired: '커밋 메시지가 필요합니다.',
    noChangesToCommit: '커밋할 변경 사항이 없습니다.',
    mustCommitBeforePush:
      '커밋되지 않은 변경 사항이 있습니다. 푸시 전에 커밋 또는 스태시하세요.',
    nothingToPush: '푸시할 커밋이 없습니다. 먼저 변경 사항을 커밋하세요.',
    commitSuccess: '커밋 완료',
    commitSuccessMessage: '변경 사항이 성공적으로 커밋되었습니다.',
    actions: '작업',
    mergeInto: ({ branch }: { branch: string }) => `${branch}에 머지`,
    mergeSubtitle: ({ branch }: { branch: string }) =>
      `이 브랜치를 ${branch}에 머지`,
    mergeConfirmTitle: '브랜치 머지',
    mergeConfirmMessage: ({
      branch,
      target,
    }: {
      branch: string;
      target: string;
    }) => `'${branch}'를 '${target}'에 머지하시겠습니까?`,
    merge: '머지',
    pushAfterMerge: '머지 후 푸시',
    mergeSuccess: '머지 완료',
    mergeSuccessMessage: '브랜치가 성공적으로 머지되었습니다.',
    mergeAndPushSuccessMessage: '브랜치가 성공적으로 머지 및 푸시되었습니다.',
    createPR: 'Pull Request 생성',
    createPRSubtitle: '브랜치를 푸시하고 GitHub에서 PR 열기',
    prCreated: 'Pull Request 생성됨',
    copyUrl: 'URL 복사',
    dangerZone: '위험 영역',
    deleteWorktree: '워크트리 삭제',
    deleteWorktreeSubtitle: '워크트리 제거, 브랜치 삭제 및 정리',
    deleteConfirmTitle: '워크트리 삭제',
    deleteConfirmMessage: ({ branch }: { branch: string }) =>
      `'${branch}' 워크트리를 제거하고 브랜치를 삭제합니다. 이 작업은 취소할 수 없습니다.`,
    deleteSuccess: '워크트리 삭제됨',
    deleteSuccessMessage: '워크트리와 브랜치가 제거되었습니다.',
    notAWorktree: '이 세션은 워크트리 세션이 아닙니다.',
    resolvingBranch: '메인 브랜치 확인 중...',
  },

  profiles: {
    // Profile management feature
    title: '프로필',
    subtitle: '세션용 환경 변수 프로필을 관리',
    noProfile: '프로필 없음',
    noProfileDescription: '기본 환경 설정 사용',
    defaultModel: '기본 모델',
    addProfile: '프로필 추가',
    profileName: '프로필 이름',
    enterName: '프로필 이름을 입력하세요',
    baseURL: 'Base URL',
    authToken: '인증 토큰',
    enterToken: '인증 토큰을 입력하세요',
    model: '모델',
    tmuxSession: 'Tmux 세션',
    enterTmuxSession: 'tmux 세션 이름을 입력하세요',
    tmuxTempDir: 'Tmux 임시 디렉터리',
    enterTmuxTempDir: '임시 디렉터리 경로를 입력하세요',
    tmuxUpdateEnvironment: '환경 자동 업데이트',
    nameRequired: '프로필 이름이 필요합니다',
    deleteConfirm: '프로필 "{name}"을(를) 삭제하시겠습니까?',
    editProfile: '프로필 편집',
    addProfileTitle: '새 프로필 추가',
    delete: {
      title: '프로필 삭제',
      message: ({ name }: { name: string }) =>
        `"${name}"을(를) 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.`,
      confirm: '삭제',
      cancel: '취소',
    },
  },
} as const;
