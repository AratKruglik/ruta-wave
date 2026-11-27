import Testing

@MainActor
struct ToastCenterTests {
    private final class Sleeps {
        var durations: [Duration] = []
    }

    private func makeCenter(_ sleeps: Sleeps) -> ToastCenter {
        ToastCenter { sleeps.durations.append($0) }
    }

    @Test func actionToastLastsAtLeastSixSeconds() async {
        let sleeps = Sleeps()
        let center = makeCenter(sleeps)
        center.show("Done", undo: {})
        await center.dismissal?.value
        center.show("Plain")
        await center.dismissal?.value
        #expect(sleeps.durations == [Motion.toastActionDuration, Motion.toastDuration])
        #expect(Motion.toastActionDuration >= .seconds(6))
    }

    @Test func heldToastSurvivesUntilReleased() async {
        let center = makeCenter(Sleeps())
        center.show("Done", undo: {})
        center.setHeld(true)
        await center.dismissal?.value
        #expect(center.toast != nil)
        center.setHeld(false)
        await center.dismissal?.value
        #expect(center.toast == nil)
    }

    @Test func toastShownWhileHeldStartsNoTimer() async {
        let sleeps = Sleeps()
        let center = makeCenter(sleeps)
        center.setHeld(true)
        center.show("Done", undo: {})
        await center.dismissal?.value
        #expect(center.toast != nil)
        #expect(sleeps.durations.isEmpty)
    }

    @Test func replacementCancelsOlderTimer() async {
        let center = ToastCenter { duration in
            if duration == Motion.toastActionDuration { try? await Task.sleep(for: .seconds(60)) }
        }
        center.show("First")
        let first = center.dismissal
        center.show("Second", undo: {})
        await first?.value
        #expect(center.toast != nil)
        center.reset()
    }

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
