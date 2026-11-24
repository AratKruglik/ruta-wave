import Testing

@MainActor
struct ToastCenterTests {
    @Test func undoRunsOnceAndDismisses() {
        let center = ToastCenter()
        var runs = 0
        center.show("Done", undo: { runs += 1 })
        center.undo()
        center.undo()
        #expect(runs == 1)
        #expect(center.toast == nil)
    }

    @Test func replacementDropsOlderUndo() {
        let center = ToastCenter()
        var runs = 0
        center.show("First", undo: { runs += 1 })
        center.show("Second")
        center.undo()
        #expect(runs == 0)
        #expect(center.message != nil)
    }

    @Test func resetDropsUndo() {
        let center = ToastCenter()
        var runs = 0
        center.show("Done", undo: { runs += 1 })
        center.reset()
        center.undo()
        #expect(runs == 0)
        #expect(center.toast == nil)
    }
}
