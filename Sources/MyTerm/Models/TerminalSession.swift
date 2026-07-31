import MyTermCore
import SwiftUI

class TerminalSession: Identifiable, ObservableObject, Equatable {
    enum ProcessState: Equatable {
        case starting
        case running
        case exited(Int32?)
        case failed(String)
        case disconnected
    }

    let id: UUID
    @Published var title: String = "Shell"
    @Published var isAgent: Bool = false
    @Published var customDirectory: String? = nil
    @Published var agentPreset: String? = nil
    @Published var hasUnseenOutput = false
    @Published var processState: ProcessState = .starting
    var agentAccessMode: AgentAccessMode = .standard

    init(id: UUID = UUID()) {
        self.id = id
    }

    var launchDescriptor: AgentLaunchDescriptor? {
        guard isAgent,
            let agentPreset,
            let preset = AgentPreset(rawValue: agentPreset)
        else {
            return nil
        }
        return preset.launchDescriptor(accessMode: agentAccessMode)
    }

    static func == (lhs: TerminalSession, rhs: TerminalSession) -> Bool {
        lhs.id == rhs.id
    }
}
