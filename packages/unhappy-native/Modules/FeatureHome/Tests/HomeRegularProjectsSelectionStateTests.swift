import Testing
@testable import FeatureHome

struct HomeRegularProjectsSelectionStateTests {
    @Test
    func retainedSelectionKeepsNilWhenNothingWasSelected() {
        #expect(
            HomeRegularProjectsSelectionState.retainedSelectionID(
                currentSelectionID: nil,
                availableProjectIDs: ["project-1"]
            ) == nil
        )
    }

    @Test
    func retainedSelectionClearsMissingProject() {
        #expect(
            HomeRegularProjectsSelectionState.retainedSelectionID(
                currentSelectionID: "project-2",
                availableProjectIDs: ["project-1"]
            ) == nil
        )
    }

    @Test
    func retainedSelectionKeepsExistingProject() {
        #expect(
            HomeRegularProjectsSelectionState.retainedSelectionID(
                currentSelectionID: "project-1",
                availableProjectIDs: ["project-1", "project-2"]
            ) == "project-1"
        )
    }
}
