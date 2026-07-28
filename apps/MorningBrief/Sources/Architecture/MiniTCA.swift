import Foundation
import SwiftUI

/// Minimal TCA-shaped runtime (no SPM). Mirrors Store/Effect for a later TCA swap.
@MainActor
final class Store<State, Action>: ObservableObject {
    @Published private(set) var state: State

    private let reducer: (inout State, Action) -> Effect<Action>
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var namedTasks: [String: UUID] = [:]

    init(initialState: State, reducer: @escaping (inout State, Action) -> Effect<Action>) {
        self.state = initialState
        self.reducer = reducer
    }

    func send(_ action: Action) {
        var next = state
        let effect = reducer(&next, action)
        state = next
        run(effect)
    }

    func cancelAll() {
        for (id, task) in tasks {
            task.cancel()
            tasks[id] = nil
        }
        namedTasks.removeAll()
    }

    func cancel(id: String) {
        guard let uuid = namedTasks.removeValue(forKey: id) else { return }
        tasks[uuid]?.cancel()
        tasks[uuid] = nil
    }

    private func run(_ effect: Effect<Action>) {
        switch effect.kind {
        case .none:
            return
        case let .publisher(name, operation):
            if let name {
                cancel(id: name)
            }
            let id = UUID()
            if let name {
                namedTasks[name] = id
            }
            let task = Task { @MainActor in
                defer {
                    tasks[id] = nil
                    if let name, namedTasks[name] == id {
                        namedTasks.removeValue(forKey: name)
                    }
                }
                let actions = await operation()
                guard !Task.isCancelled else { return }
                for action in actions {
                    send(action)
                }
            }
            tasks[id] = task
        case let .cancel(id):
            tasks[id]?.cancel()
            tasks[id] = nil
        case let .cancelNamed(name):
            cancel(id: name)
        case .cancelAll:
            cancelAll()
        case let .sequence(effects):
            for child in effects {
                run(child)
            }
        }
    }
}

struct Effect<Action> {
    enum Kind {
        case none
        case publisher(id: String?, () async -> [Action])
        case cancel(UUID)
        case cancelNamed(String)
        case cancelAll
        case sequence([Effect<Action>])
    }

    let kind: Kind

    static var none: Effect { Effect(kind: .none) }

    static var cancelAll: Effect { Effect(kind: .cancelAll) }

    static func cancel(id: String) -> Effect {
        Effect(kind: .cancelNamed(id))
    }

    static func sequence(_ effects: Effect<Action>...) -> Effect {
        Effect(kind: .sequence(effects))
    }

    static func run(
        id: String? = nil,
        _ operation: @escaping () async -> Action?
    ) -> Effect {
        Effect(kind: .publisher(id: id) {
            if let action = await operation() { return [action] }
            return []
        })
    }

    static func run(
        id: String? = nil,
        _ operation: @escaping () async -> [Action]
    ) -> Effect {
        Effect(kind: .publisher(id: id, operation))
    }
}

struct WithStore<State, Action, Content: View>: View {
    @ObservedObject var store: Store<State, Action>
    let content: (Store<State, Action>) -> Content

    init(
        _ store: Store<State, Action>,
        @ViewBuilder content: @escaping (Store<State, Action>) -> Content
    ) {
        self.store = store
        self.content = content
    }

    var body: some View {
        content(store)
    }
}
