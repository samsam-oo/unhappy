import * as React from 'react';
import { Ionicons } from '@/icons/vector-icons';
import { Item } from '@/components/Item';
import { ItemGroup } from '@/components/ItemGroup';
import { ItemList } from '@/components/ItemList';
import { Switch } from '@/components/Switch';

export default function ListDemoScreen() {
    const [isEnabled, setIsEnabled] = React.useState(false);
    const [selectedItem, setSelectedItem] = React.useState<string | null>(null);

    return (
        <ItemList>
            {/* Basic Items */}
            <ItemGroup title="기본 항목">
                <Item title="간단한 항목" />
                <Item 
                    title="부제목이 있는 항목"
                    subtitle="필요하면 여러 줄로 표시되는 부제목입니다"
                />
                <Item 
                    title="세부 정보가 있는 항목"
                    detail="세부 정보"
                />
                <Item 
                    title="터치 가능한 항목"
                    onPress={() => console.log('Item pressed')}
                />
            </ItemGroup>

            {/* Items with Icons */}
            <ItemGroup title="아이콘 포함">
                <Item 
                    title="설정"
                    icon={<Ionicons name="settings-outline" size={28} color="#007AFF" />}
                    onPress={() => {}}
                />
                <Item 
                    title="알림"
                    icon={<Ionicons name="notifications-outline" size={28} color="#FF9500" />}
                    detail="5"
                    onPress={() => {}}
                />
                <Item 
                    title="개인정보"
                    icon={<Ionicons name="lock-closed-outline" size={28} color="#34C759" />}
                    subtitle="개인정보 설정을 관리합니다"
                    onPress={() => {}}
                />
            </ItemGroup>

            {/* Interactive Items */}
            <ItemGroup title="인터랙션" footer="이 항목들은 다양한 상호작용 상태를 보여줍니다">
                <Item 
                    title="토글 스위치"
                    rightElement={
                        <Switch
                            value={isEnabled}
                            onValueChange={setIsEnabled}
                        />
                    }
                    showChevron={false}
                />
                <Item 
                    title="선택된 항목"
                    selected={selectedItem === 'item1'}
                    onPress={() => setSelectedItem('item1')}
                />
                <Item 
                    title="로딩 상태"
                    loading={true}
                    onPress={() => {}}
                />
                <Item 
                    title="비활성 항목"
                    disabled={true}
                    onPress={() => {}}
                />
                <Item 
                    title="위험 동작"
                    destructive={true}
                    onPress={() => {}}
                />
            </ItemGroup>

            {/* Custom Styling */}
            <ItemGroup title="커스텀 스타일">
                <Item 
                    title="사용자 지정 색상"
                    subtitle="커스텀 텍스트 색상"
                    titleStyle={{ color: '#FF3B30' }}
                    subtitleStyle={{ color: '#FF9500' }}
                    onPress={() => {}}
                />
                <Item 
                    title="구분선 없음"
                    showDivider={false}
                />
                <Item 
                    title="여백 사용자 지정"
                    dividerInset={60}
                />
                <Item 
                    title="화살표 없음"
                    showChevron={false}
                    onPress={() => {}}
                />
            </ItemGroup>

            {/* Long Press */}
            <ItemGroup title="제스처">
                <Item 
                    title="길게 누르기"
                    subtitle="이 항목을 길게 눌러보세요"
                    onLongPress={() => console.log('Long pressed!')}
                />
                <Item 
                    title="탭 및 롱 프레스"
                    onPress={() => console.log('Pressed')}
                    onLongPress={() => console.log('Long pressed')}
                />
            </ItemGroup>
        </ItemList>
    );
}
