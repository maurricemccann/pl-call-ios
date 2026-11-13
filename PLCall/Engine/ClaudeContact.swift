import Contacts
import UIKit

/// The address every call to and from Claude uses. It is not a real mailbox: it only lets the Phone app match
/// the call to a contact card, so Recents shows "Claude" with his heart mark instead of an unknown caller.
enum ClaudeContact {
    static let handle = "claude@call.local"

    /// Adds (or refreshes) the Claude card. Returns nil when done, else why not.
    static func add() async -> String? {
        let store = CNContactStore()
        do {
            guard try await store.requestAccess(for: .contacts) else { return "Allow Contacts for Call in Settings to add the card." }
        } catch {
            return "Contacts did not answer: \(error.localizedDescription)"
        }
        let keys = [CNContactEmailAddressesKey as CNKeyDescriptor, CNContactGivenNameKey as CNKeyDescriptor]
        let match = CNContact.predicateForContacts(matchingEmailAddress: handle)
        let save = CNSaveRequest()
        if let found = try? store.unifiedContacts(matching: match, keysToFetch: keys + [CNContactImageDataKey as CNKeyDescriptor]).first,
           let card = found.mutableCopy() as? CNMutableContact {
            card.imageData = photo()
            save.update(card)
        } else {
            let card = CNMutableContact()
            card.givenName = "Claude"
            card.emailAddresses = [CNLabeledValue(label: "Call", value: handle as NSString)]
            card.imageData = photo()
            card.note = "Calls from the Call app."
            save.add(card, toContainerWithIdentifier: nil)
        }
        do {
            try store.execute(save)
            return nil
        } catch {
            return "The card could not be saved: \(error.localizedDescription)"
        }
    }

    /// His heart mark in house orange on near-black, the app icon's art.
    private static func photo() -> Data? {
        UIImage(named: "ContactPhoto")?.pngData()
    }
}
