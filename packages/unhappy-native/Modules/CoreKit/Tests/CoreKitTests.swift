import Testing
import UIFoundation

struct CoreKitTests {
    @Test
    func accentColorIsDefined() {
        _ = AppPalette.accent
    }
}
