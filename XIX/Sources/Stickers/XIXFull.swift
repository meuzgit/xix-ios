// XIX Full, as far as step 3 needs it: a local flag that says whether this device may throw a callout.
// Nothing is on sale yet, so it is on by default and the contextual gate (Pass 6 6g, entry 2) is what
// a free player would meet. Step 9 replaces this with StoreKit and a server-side entitlement check —
// until then nothing here is proof of purchase, and the server enforces nothing.
import Foundation

enum XIXFull {
    private static let key = "xix.full"

    static var isActive: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
