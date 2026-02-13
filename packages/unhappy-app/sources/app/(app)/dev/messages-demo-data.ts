// 참고: 이 데모 데이터의 최종 위치가 아직 정해지지 않았습니다. 임시 저장용입니다.
// 현재는 개발 및 테스트용 모의 메시지 데이터만 들어갑니다.

import { Message, ToolCall } from '@/sync/typesMessage';

// 도구 호출 객체를 타임스탬프로 생성
const createToolCall = (name: string, state: ToolCall['state'], input: any, result?: any, description?: string | null): ToolCall => ({
    name,
    state,
    input,
    createdAt: Date.now() - Math.random() * 10000,
    startedAt: state !== 'running' ? Date.now() - Math.random() * 10000 : null,
    completedAt: state === 'completed' || state === 'error' ? Date.now() - Math.random() * 5000 : null,
    description: description || null,
    result
});

// 읽기 도구 호출 상수(재사용)
const createReadToolCall = (id: string, filePath: string, startLine: number, endLine: number, result: string): Message => ({
    id,
    localId: null,
    createdAt: Date.now() - Math.random() * 10000,
    kind: 'tool-call' as const,
    tool: createToolCall('읽기', 'completed', {
        file_path: filePath,
        start_line: startLine,
        end_line: endLine
    }, result),
    children: []
});

// 설명 역할을 하는 사용자 메시지를 생성
function createSectionTitle(id: string, text: string, timeOffset: number = 0): Message {
    return { id, localId: null, createdAt: Date.now() - timeOffset, kind: 'user-text', text }
}

export const debugMessages: Message[] = [
    // 사용자 메시지
    {
        id: 'user-1',
        localId: null,
        createdAt: Date.now() - 200000,
        kind: 'user-text',
        text: '내 애플리케이션을 디버그하고 개선할 수 있도록 도와줄 수 있나요?'
    },
    
    // 에이전트 메시지
    {
        id: 'agent-1',
        localId: null,
        createdAt: Date.now() - 190000,
        kind: 'agent-text',
        text: '코드베이스를 검토하고 여러 분석 도구를 실행해 문제를 먼저 파악한 다음 개선안을 제시하겠습니다.'
    },

    // 에이전트 메시지 + 마크다운 테이블 예시(모바일 렌더 이슈 재현)
    {
        id: 'agent-table-demo',
        localId: null,
        createdAt: Date.now() - 185000,
        kind: 'agent-text',
        text: `분석 결과 요약입니다:

| 파일 | 오류 | 경고 | 상태 |
|------|------|------|--------|
| App.tsx | 0 | 2 | ✓ 통과 |
| Button.tsx | 3 | 1 | ✗ 다중 타입 오류로 검증 실패 |
| helpers.ts | 1 | 0 | ✗ 실패 |
| VeryLongComponentNameThatMightCauseLayoutIssues.tsx | 0 | 0 | ✓ 통과 |

주요 이슈는 Button.tsx와 helpers.ts에 있습니다.`
    },

    // 간단한 표 예시
    {
        id: 'agent-table-minimal',
        localId: null,
        createdAt: Date.now() - 184000,
        kind: 'agent-text',
        text: `간단한 표 렌더링 테스트:

| A | B |
|---|---|
| 1 | 2 |`
    },

    // 코드 스니펫 예시 - 가로 스크롤 테스트
    {
        id: 'agent-code-demo',
        localId: null,
        createdAt: Date.now() - 183000,
        kind: 'agent-text',
        text: `복잡한 데이터 변환을 처리하는 함수 예시입니다:

\`\`\`typescript
export async function processUserDataWithValidationAndTransformation(
    userData: UserData,
    options: ProcessingOptions = { validate: true, transform: true, normalize: true }
): Promise<ProcessedUserData> {
    const { validate, transform, normalize } = options;

    if (validate) {
        const validationResult = await validateUserData(userData);
        if (!validationResult.isValid) {
            throw new ValidationError(validationResult.errors.join(', '));
        }
    }

    let processedData = { ...userData };

    if (transform) {
        processedData = applyTransformations(processedData, TRANSFORMATION_RULES);
    }

    if (normalize) {
        processedData = normalizeFieldNames(processedData, FIELD_MAPPING);
    }

    return processedData as ProcessedUserData;
}
\`\`\`

이 함수는 검증, 변환, 정규화를 한 번에 처리합니다.`
    },
    createSectionTitle('missing-tool-call-title', '도구 호출이 비어 있을 때는 어떻게 표시되나요? 빈 도구 배열이 렌더되면 이 두 메시지 사이에 표시됩니다\nvvvvvvvvvvvvvvvvvvvv'),
    
    // 참고: 이 메시지 타입은 더 이상 유효하지 않습니다.
    // 도구 호출은 도구 호출 타입이어야 하므로, 참고용으로 남겨둡니다.
    createSectionTitle('missing-tool-call-after', '^^^^^^^^^^^^^^^^^^^^'),

    // 배시 도구 - 실행 중
    {
        id: 'bash-running',
        localId: null,
        createdAt: Date.now() - 180000,
        kind: 'tool-call',
        tool: createToolCall('배시(Bash)', 'running', {
            description: '테스트 실행 중',
            command: 'npm test -- --coverage'
        }, undefined, '테스트 실행 중'),
        children: []
    },

    // 배시 도구 - 완료됨
    {
        id: 'bash-completed',
        localId: null,
        createdAt: Date.now() - 170000,
        kind: 'tool-call',
        tool: createToolCall('배시(Bash)', 'completed', {
            command: 'npm run build'
        }, '애플리케이션이 성공적으로 빌드되었습니다\n\n> app@1.0.0 build\n> webpack --mode=production\n\nHash: 4f2b42c7bb332e42ef96\nVersion: webpack 5.74.0\nTime: 2347ms\nBuilt at: 12/07/2024 2:34:15 PM'),
        children: []
    },

    // 배시 도구 - 오류
    {
        id: 'bash-error',
        localId: null,
        createdAt: Date.now() - 160000,
        kind: 'tool-call',
        tool: createToolCall('배시(Bash)', 'error', {
            description: 'TypeScript 오류 확인',
            command: 'npx tsc --noEmit'
        }, 'Error: TypeScript compilation failed\n\nsrc/components/Button.tsx(23,5): error TS2322: Type \'string\' is not assignable to type \'number\'.\nsrc/utils/helpers.ts(45,10): error TS2554: Expected 2 arguments, but got 1.', 'TypeScript 오류 확인'),
        children: []
    },

    // 편집 도구 - 실행 중
    {
        id: 'edit-running',
        localId: null,
        createdAt: Date.now() - 150000,
        kind: 'tool-call',
        tool: createToolCall('편집', 'running', {
            file_path: '/src/components/Button.tsx',
            old_string: 'const count: number = "0";',
            new_string: 'const count: number = 0;'
        }),
        children: []
    },

    // 편집 도구 - 완료됨
    {
        id: 'edit-completed',
        localId: null,
        createdAt: Date.now() - 140000,
        kind: 'tool-call',
        tool: createToolCall('편집', 'completed', {
            file_path: '/src/components/Button.tsx',
            old_string: 'const count: number = "0";',
            new_string: 'const count: number = 0;'
        }, '파일이 성공적으로 업데이트되었습니다'),
        children: []
    },

    // 편집 도구 - 완료됨 (큰 변경 분량)
    {
        id: 'edit-large',
        localId: null,
        createdAt: Date.now() - 130000,
        kind: 'tool-call',
        tool: createToolCall('편집', 'completed', {
            file_path: '/src/utils/helpers.ts',
            old_string: 'export function calculateTotal(items) {\n  return items.reduce((sum, item) => sum + item.price, 0);\n}',
            new_string: 'export function calculateTotal(items: Item[]): number {\n  return items.reduce((sum, item) => sum + item.price, 0);\n}'
        }, '파일이 성공적으로 업데이트되었습니다'),
        children: []
    },

    // 편집 도구 - 오류
    {
        id: 'edit-error',
        localId: null,
        createdAt: Date.now() - 120000,
        kind: 'tool-call',
        tool: createToolCall('편집', 'error', {
            file_path: '/src/utils/nonexistent.ts',
            old_string: 'something',
            new_string: 'something else'
        }, '오류: 파일을 찾을 수 없습니다: /src/utils/nonexistent.ts'),
        children: []
    },

    // 읽기 도구 - 실행 중
    {
        id: 'read-running',
        localId: null,
        createdAt: Date.now() - 110000,
        kind: 'tool-call',
        tool: createToolCall('읽기', 'running', {
            file_path: '/src/index.tsx',
            start_line: 1,
            end_line: 50
        }),
        children: []
    },

    // 읽기 도구 예시
    createReadToolCall('read-1', '/src/index.tsx', 1, 20, 
`import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';

const root = ReactDOM.createRoot(
  document.getElementById('root') as HTMLElement
);

root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);`),

    createReadToolCall('read-2', '/src/App.tsx', 10, 30,
`function App() {
  const [count, setCount] = useState(0);
  
  return (
    <div className="App">
      <header className="App-header">
        <p>Count: {count}</p>
        <button onClick={() => setCount(count + 1)}>
          Increment
        </button>
      </header>
    </div>
  );
}`),

    // 쓰기 도구
    {
        id: 'write-completed',
        localId: null,
        createdAt: Date.now() - 80000,
        kind: 'tool-call',
        tool: createToolCall('쓰기', 'completed', {
            file_path: '/src/components/NewComponent.tsx',
            content: `import React from 'react';

interface NewComponentProps {
  title: string;
  description?: string;
}

export const NewComponent: React.FC<NewComponentProps> = ({ title, description }) => {
  return (
    <div className="new-component">
      <h2>{title}</h2>
      {description && <p>{description}</p>}
    </div>
  );
};`
        }, '파일이 성공적으로 생성되었습니다'),
        children: []
    },

    // 쓰기 도구 - 오류
    {
        id: 'write-error',
        localId: null,
        createdAt: Date.now() - 70000,
        kind: 'tool-call',
        tool: createToolCall('쓰기', 'error', {
            file_path: '/restricted/file.txt',
            content: 'Some content'
        }, '오류: 권한이 없어 /restricted/file.txt에 쓸 수 없습니다'),
        children: []
    },

    // 검색 도구 - 실행 중
    {
        id: 'grep-running',
        localId: null,
        createdAt: Date.now() - 60000,
        kind: 'tool-call',
        tool: createToolCall('검색', 'running', {
            pattern: 'TODO|FIXME',
            include_pattern: '*.ts,*.tsx',
            output_mode: 'lines',
            '-n': true
        }),
        children: []
    },

    // 검색 도구 - 결과 있음
    {
        id: 'grep-completed',
        localId: null,
        createdAt: Date.now() - 50000,
        kind: 'tool-call',
        tool: createToolCall('검색', 'completed', {
            pattern: 'TODO|FIXME',
            include_pattern: '*.ts,*.tsx',
            output_mode: 'lines',
            '-n': true
        }, {
            mode: 'lines',
            numFiles: 3,
            filenames: ['/src/App.tsx', '/src/utils/helpers.ts', '/src/components/Button.tsx'],
            content: `/src/App.tsx:15:  // 할 일: 오류 경계 처리 추가
/src/App.tsx:23:  // 참고: 로딩 상태 처리 추가
/src/utils/helpers.ts:8:  // 할 일: 입력값 검증 추가
/src/components/Button.tsx:12:  // 할 일: 비활성 상태 스타일 추가`,
            numLines: 4
        }),
        children: []
    },

    // 검색 도구 - 검색 결과 없음
    {
        id: 'grep-empty',
        localId: null,
        createdAt: Date.now() - 40000,
        kind: 'tool-call',
        tool: createToolCall('검색', 'completed', {
            pattern: 'DEPRECATED',
            include_pattern: '*.ts,*.tsx',
            output_mode: 'lines',
            '-n': true
        }, {
            mode: 'lines',
            numFiles: 0,
            filenames: [],
            content: '일치 항목이 없습니다',
            numLines: 0
        }),
        children: []
    },

    // 할 일 목록 도구
    {
        id: 'todo-write',
        localId: null,
        createdAt: Date.now() - 30000,
        kind: 'tool-call',
        tool: createToolCall('할 일 목록', 'completed', {
            todos: [
                { id: '1', content: 'Button 컴포넌트의 TypeScript 오류 수정', status: 'completed', priority: 'high' },
                { id: '2', content: 'App 컴포넌트에 오류 경계 추가', status: 'in_progress', priority: 'medium' },
                { id: '3', content: '로딩 상태 구현', status: 'pending', priority: 'medium' },
                { id: '4', content: 'helpers에 입력값 검증 추가', status: 'pending', priority: 'low' }
            ]
        }, undefined),
        children: []
    },

    // 패턴 매칭 도구(파일 패턴 매칭)
    {
        id: 'glob-completed',
        localId: null,
        createdAt: Date.now() - 20000,
        kind: 'tool-call',
        tool: createToolCall('패턴 매칭', 'completed', {
            pattern: '**/*.test.{ts,tsx}'
        }, [
            '/src/App.test.tsx',
            '/src/components/Button.test.tsx',
            '/src/utils/helpers.test.ts',
            '/src/utils/validators.test.ts'
        ]),
        children: []
    },

    // 경로 목록 조회 도구
    {
        id: 'ls-completed',
        localId: null,
        createdAt: Date.now() - 10000,
        kind: 'tool-call',
        tool: createToolCall('목록 조회', 'completed', {
            path: '/src/components'
        }, `- Button.tsx
- Button.test.tsx
- Button.css
- Header.tsx
- Header.test.tsx
- Header.css
- Footer.tsx
- Footer.test.tsx
- Footer.css
- index.ts`),
        children: []
    },

    // 복합 예시 - 하위 작업을 가진 작업 도구
    {
        id: 'task-with-children',
        localId: null,
        createdAt: Date.now() - 5000,
        kind: 'tool-call',
        tool: createToolCall('작업', 'completed', {
            description: '코드베이스 분석',
            prompt: '잠재적 개선점을 찾아 코드베이스를 분석해주세요'
        }, undefined, '코드베이스 분석'),
        children: [
            {
                id: 'task-child-1',
                localId: null,
                createdAt: Date.now() - 4000,
                kind: 'tool-call',
                tool: createToolCall('검색', 'completed', {
                    pattern: 'TODO',
                    output_mode: 'count'
                }, { count: 15 }),
                children: []
            },
            {
                id: 'task-child-2',
                localId: null,
                createdAt: Date.now() - 3000,
                kind: 'tool-call',
                tool: createToolCall('읽기', 'completed', {
                    file_path: '/package.json'
                }, '{\n  "name": "my-app",\n  "version": "1.0.0"\n}'),
                children: []
            }
        ]
    }
];
