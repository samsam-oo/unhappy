import Foundation

enum HomeRegularProjectsSelectionState {
    static func retainedSelectionID(
        currentSelectionID: String?,
        availableProjectIDs: [String]
    ) -> String? {
        guard let currentSelectionID else { return nil }
        return availableProjectIDs.contains(currentSelectionID) ? currentSelectionID : nil
    }
}
