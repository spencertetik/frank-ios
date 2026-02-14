import Foundation
import Observation

@Observable
@MainActor
final class FrankStatusModel {
    var currentTask: String

    init(currentTask: String = "Waiting for instructions") {
        self.currentTask = currentTask
    }

    func update(task: String) {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        currentTask = trimmed.isEmpty ? "Waiting for instructions" : trimmed
    }
}
