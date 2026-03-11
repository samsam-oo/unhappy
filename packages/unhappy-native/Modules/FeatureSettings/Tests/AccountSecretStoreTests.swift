import Foundation
import Testing
@testable import FeatureSettings

struct AccountSecretStoreTests {
    @Test
    func storesCanonicalBase64URLWhenGivenBase32Secret() async {
        let key = "secret"
        let store = UserDefaultsAccountSecretStore(accountSecretKey: key)
        let original = UserDefaults.standard.string(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        await store.setSecretBase64URL("AEBAGBAFAYDQQCIKBMGA2DQPCAIREEYUCULBOGAZDINRYHI6D4QA")

        #expect(await store.loadSecretBase64URL() == "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8")
    }
}
