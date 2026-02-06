import * as React from 'react';
import type { LucideIcon, LucideProps } from 'lucide-react-native';
import {
    Activity,
    Album,
    AlertCircle,
    Atom,
    Archive,
    ArrowDown,
    ArrowLeft,
    ArrowRight,
    ArrowUp,
    ArrowUpDown,
    AtSign,
    Bell,
    Bold,
    BookOpen,
    Bookmark,
    Bug,
    Calculator,
    Calendar,
    Camera,
    ChartLine,
    ChartNoAxesCombined,
    Check,
    CheckCheck,
    CheckCircle2,
    ChevronDown,
    ChevronLeft,
    ChevronRight,
    ChevronUp,
    Clock,
    Cloud,
    Code,
    CodeXml,
    Contrast,
    CornerDownRight,
    Copy,
    CreditCard,
    Cpu,
    DollarSign,
    Download,
    Diamond,
    Ellipsis,
    Eye,
    EyeOff,
    ExternalLink,
    FileDiff,
    FileImage,
    FileText,
    FingerprintPattern,
    FlaskConical,
    Folder,
    Gift,
    Gamepad2,
    GitBranch,
    GitCommitHorizontal,
    Github,
    Globe,
    GripVertical,
    Hammer,
    Heart,
    House,
    Hourglass,
    Image,
    Images,
    Info,
    Italic,
    Key,
    LayoutGrid,
    Laptop,
    Languages,
    Lightbulb,
    Link,
    List,
    ListOrdered,
    Lock,
    LogIn,
    LogOut,
    MapPin,
    MessageCircle,
    MessageSquare,
    Mic,
    Minimize2,
    Minus,
    Monitor,
    Music,
    Paintbrush,
    Palette,
    Paperclip,
    Pencil,
    Phone,
    Play,
    CirclePlay,
    Plus,
    PlusCircle,
    Puzzle,
    QrCode,
    RefreshCw,
    Repeat,
    Rocket,
    Search,
    Send,
    Server,
    Settings,
    Share,
    Shield,
    ShieldCheck,
    Shuffle,
    SkipBack,
    SkipForward,
    Smile,
    Sparkles,
    Smartphone,
    Star,
    StopCircle,
    Square,
    StickyNote,
    Strikethrough,
    Tag,
    Terminal,
    Timer,
    Trash2,
    TriangleAlert,
    Type,
    Underline,
    User,
    UserCircle,
    UserMinus,
    UserPlus,
    Users,
    Video,
    Wrench,
    X,
    XCircle,
    Zap,
    CircleMinus,
    CircleQuestionMark,
    Gauge,
    Box,
} from 'lucide-react-native';

type VectorIconName = string | number | symbol;

// Match @expo/vector-icons' loose prop surface:
// - allow any `style` (vector-icons used TextStyle; Lucide's SvgProps expects ViewStyle)
// - allow `name` values derived from `keyof glyphMap` (string | number | symbol)
type VectorIconProps = Omit<LucideProps, 'color' | 'style'> & {
    name: VectorIconName;
    color?: string;
    style?: any;
};

type VectorIconComponent = ((props: VectorIconProps) => React.ReactElement | null) & {
    glyphMap: Record<string, number>;
};

const missingIconWarnings = new Set<string>();

function normalizeOutlineName(name: VectorIconName): string[] {
    const trimmed = String(name ?? '').trim();
    if (!trimmed) {
        return [];
    }
    const candidates: string[] = [trimmed];
    if (trimmed.endsWith('-outline')) {
        candidates.push(trimmed.slice(0, -'-outline'.length));
    }
    return candidates;
}

function createGlyphMap(keys: string[], opts?: { includeOutlineVariant?: boolean }): Record<string, number> {
    const includeOutlineVariant = opts?.includeOutlineVariant ?? false;
    const glyphMap: Record<string, number> = {};
    let i = 0;
    for (const k of keys) {
        glyphMap[k] = i++;
        if (includeOutlineVariant) {
            glyphMap[`${k}-outline`] = i++;
        }
    }
    return glyphMap;
}

function createVectorIcon(
    packName: string,
    map: Record<string, LucideIcon>,
    fallback: LucideIcon,
    opts?: { includeOutlineVariant?: boolean }
): VectorIconComponent {
    const VectorIcon = function VectorIcon(props: VectorIconProps) {
        const { name, size = 24, color = 'currentColor', ...rest } = props;
        for (const candidate of normalizeOutlineName(name)) {
            const Icon = map[candidate];
            if (Icon) {
                return <Icon size={size} color={color} {...rest} />;
            }
        }
        if (typeof __DEV__ !== 'undefined' && __DEV__) {
            const key = `${packName}:${String(name ?? '')}`;
            if (!missingIconWarnings.has(key)) {
                missingIconWarnings.add(key);
                // Helps expand mappings if we missed an icon in migration.
                console.warn(`[icons] Missing ${packName} icon mapping for name="${String(name ?? '')}"`);
            }
        }
        const Fallback = fallback;
        return <Fallback size={size} color={color} {...rest} />;
    };
    (VectorIcon as any).glyphMap = createGlyphMap(Object.keys(map), opts);
    return VectorIcon as any;
}

// Ionicons name strings (kebab-case) mapped to Lucide icons.
const IONICONS_MAP: Record<string, LucideIcon> = {
    'add': Plus,
    'add-circle': PlusCircle,
    'albums': Album,
    'alert-circle': AlertCircle,
    'analytics': ChartNoAxesCombined,
    'apps': LayoutGrid,
    'archive': Archive,
    'arrow-back': ArrowLeft,
    'arrow-down': ArrowDown,
    'arrow-forward': ArrowRight,
    'arrow-up': ArrowUp,
    'at': AtSign,
    'attach': Paperclip,
    'book': BookOpen,
    'bookmark': Bookmark,
    'brush': Paintbrush,
    'bug': Bug,
    'bulb': Lightbulb,
    'calendar': Calendar,
    'call': Phone,
    'camera': Camera,
    'card': CreditCard,
    'chatbox': MessageSquare,
    'chatbubble': MessageCircle,
    'chatbubbles': MessageSquare,
    'checkbox': CheckCircle2,
    'checkmark': Check,
    'checkmark-circle': CheckCircle2,
    'checkmark-done': CheckCheck,
    'chevron-back': ChevronLeft,
    'chevron-down': ChevronDown,
    'chevron-forward': ChevronRight,
    'chevron-up': ChevronUp,
    'close': X,
    'close-circle': XCircle,
    'code': Code,
    'code-slash': CodeXml,
    'code-working': Code,
    'color-palette': Palette,
    'cloud': Cloud,
    'construct': Wrench,
    'contract': Minimize2,
    'contrast': Contrast,
    'copy': Copy,
    'create': Pencil,
    'cube': Box,
    'desktop': Monitor,
    'diamond': Diamond,
    'document-text': FileText,
    'download': Download,
    'ellipse': Ellipsis,
    'exit': LogOut,
    'extension-puzzle': Puzzle,
    'eye': Eye,
    'eye-off': EyeOff,
    'finger-print': FingerprintPattern,
    'flask': FlaskConical,
    'folder': Folder,
    'game-controller': Gamepad2,
    'git-branch': GitBranch,
    'git-commit': GitCommitHorizontal,
    'globe': Globe,
    'hammer': Hammer,
    'happy': Smile,
    'hardware-chip': Cpu,
    'heart': Heart,
    'help-circle': CircleQuestionMark,
    'home': House,
    'hourglass': Hourglass,
    'image': Image,
    'images': Images,
    'information-circle': Info,
    'key': Key,
    'keypad': Calculator,
    'language': Languages,
    'laptop': Laptop,
    'link': Link,
    'list': List,
    'location': MapPin,
    'lock-closed': Lock,
    'log-in': LogIn,
    'log-out': LogOut,
    'logo-github': Github,
    'logo-react': Atom,
    'mic': Mic,
    'musical-notes': Music,
    'notifications': Bell,
    'open': ExternalLink,
    'people': Users,
    'person': User,
    'person-add': UserPlus,
    'person-circle': UserCircle,
    'person-remove': UserMinus,
    'phone-landscape': Smartphone,
    'phone-portrait': Smartphone,
    'play': Play,
    'play-circle': CirclePlay,
    'play-skip-back': SkipBack,
    'play-skip-forward': SkipForward,
    'pulse': Activity,
    'qr-code': QrCode,
    'refresh': RefreshCw,
    'remove-circle': CircleMinus,
    'rocket': Rocket,
    'repeat': Repeat,
    'reorder-three': GripVertical,
    'remove': Minus,
    'return-down-forward': CornerDownRight,
    'search': Search,
    'send': Send,
    'server': Server,
    'settings': Settings,
    'share': Share,
    'shield': Shield,
    'shield-checkmark': ShieldCheck,
    'shuffle': Shuffle,
    'sparkles': Sparkles,
    'star': Star,
    'stats-chart': ChartLine,
    'stop-circle': StopCircle,
    'speedometer': Gauge,
    'swap-vertical': ArrowUpDown,
    'terminal': Terminal,
    'text': Type,
    'time': Clock,
    'timer': Timer,
    'trash': Trash2,
    'videocam': Video,
    'warning': TriangleAlert,
    'flash': Zap,
};

// Octicons name strings mapped to Lucide icons.
const OCTICONS_MAP: Record<string, LucideIcon> = {
    'arrow-right': ArrowRight,
    'arrow-up': ArrowUp,
    'cpu': Cpu,
    'diff-added': Plus,
    'diff-modified': FileDiff,
    'diff-removed': Minus,
    'eye': Eye,
    'file': FileText,
    'file-diff': FileDiff,
    'file-directory': Folder,
    'gear': Settings,
    'git-branch': GitBranch,
    'light-bulb': Lightbulb,
    'pencil': Pencil,
    'rocket': Rocket,
    'search': Search,
    'stop': Square,
    'terminal': Terminal,
};

const MATERIAL_ICONS_MAP: Record<string, LucideIcon> = {
    'attach-money': DollarSign,
    'code': Code,
    'format-bold': Bold,
    'format-color-text': Palette,
    'format-italic': Italic,
    'format-list-bulleted': List,
    'format-list-numbered': ListOrdered,
    'format-underlined': Underline,
    'gif': FileImage,
    'link': Link,
    'more-horiz': Ellipsis,
    'send': Send,
    'sticky-note-2': StickyNote,
    'strikethrough-s': Strikethrough,
    'tag': Tag,
};

const FEATHER_MAP: Record<string, LucideIcon> = {
    'gift': Gift,
};

const MATERIAL_COMMUNITY_MAP: Record<string, LucideIcon> = {
    'drag': GripVertical,
};

// @expo/vector-icons compatible exports (drop-in replacement)
export const Ionicons = createVectorIcon('Ionicons', IONICONS_MAP, CircleQuestionMark, { includeOutlineVariant: true });
export const Octicons = createVectorIcon('Octicons', OCTICONS_MAP, CircleQuestionMark);
export const MaterialIcons = createVectorIcon('MaterialIcons', MATERIAL_ICONS_MAP, CircleQuestionMark);
export const Feather = createVectorIcon('Feather', FEATHER_MAP, CircleQuestionMark);
export const MaterialCommunityIcons = createVectorIcon('MaterialCommunityIcons', MATERIAL_COMMUNITY_MAP, CircleQuestionMark);
