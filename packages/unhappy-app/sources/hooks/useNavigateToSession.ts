import { storage } from "@/sync/storage"
import { useRouter } from "expo-router"

export function useNavigateToSession() {
    const router = useRouter();
    return (sessionId: string) => {
        // Eagerly clear unread state for instant visual feedback
        storage.getState().markSessionRead(sessionId);
        router.navigate(`/session/${sessionId}`, {
            dangerouslySingular(name, params) {
                return 'session'
            },
        });
    }
}
