import Foundation

enum AppFeature {
    struct State {
        var lens: PanelLens = .work
        var work = WorkFeature.State()
        var agent = AgentFeature.State()
        var brief = BriefFeature.State()
    }

    enum Action {
        case setLens(PanelLens)
        case work(WorkFeature.Action)
        case agent(AgentFeature.Action)
        case brief(BriefFeature.Action)
    }

    @MainActor
    static func store(client: BriefctlClient = .live) -> Store<State, Action> {
        let store = Store(initialState: State()) { state, action in
            reduce(into: &state, action: action, client: client)
        }
        BriefWatchHost.setHandler {
            store.send(.brief(.diskChanged))
        }
        return store
    }

    static func reduce(
        into state: inout State,
        action: Action,
        client: BriefctlClient
    ) -> Effect<Action> {
        switch action {
        case let .setLens(lens):
            state.lens = lens
            UserDefaults.standard.set(lens.rawValue, forKey: PanelLens.storageKey)
            switch lens {
            case .work:
                return .run { [.work(.onAppear)] }
            case .agent:
                return .run { [.agent(.onAppear)] }
            case .brief:
                let day = state.work.selectedDate
                return .run {
                    [
                        .brief(.syncDateFromWork(day)),
                        .brief(.onAppear),
                    ]
                }
            }

        case let .work(workAction):
            let effect = WorkFeature.reduce(
                into: &state.work,
                action: workAction,
                client: client
            )
            let mapped = mapEffect(effect) { .work($0) }
            if case let .selectDate(day) = workAction {
                return .sequence(mapped, .run { [.brief(.syncDateFromWork(day))] })
            }
            return mapped

        case let .agent(agentAction):
            let effect = AgentFeature.reduce(
                into: &state.agent,
                action: agentAction,
                client: client
            )
            let mapped = mapEffect(effect) { .agent($0) }

            if case .applySucceeded = agentAction {
                let today = BriefPaths.todayDateString()
                state.work.selectedDate = today
                state.work.notice = "Todo 已更新"
                state.agent.notice = nil
                return .sequence(
                    mapped,
                    .run { [.work(.refreshProjection), .setLens(.work)] }
                )
            }

            switch agentAction {
            case .analyzeConfirmedSession, .locateSession, .analyzeClaudeSession,
                 .applySessionAnalysis, .setLimit, .reloadSessions:
                return .sequence(
                    .cancel(id: AgentFeature.summarizeEffectID),
                    mapped
                )
            default:
                return mapped
            }

        case let .brief(briefAction):
            let effect = BriefFeature.reduce(
                into: &state.brief,
                action: briefAction,
                client: client
            )
            return mapEffect(effect) { .brief($0) }
        }
    }

    private static func mapEffect<Child>(
        _ effect: Effect<Child>,
        _ transform: @escaping (Child) -> Action
    ) -> Effect<Action> {
        switch effect.kind {
        case .none:
            return .none
        case let .publisher(id, operation):
            return .run(id: id) {
                let actions = await operation()
                return actions.map(transform)
            }
        case let .cancel(id):
            return Effect(kind: .cancel(id))
        case let .cancelNamed(name):
            return .cancel(id: name)
        case .cancelAll:
            return .cancelAll
        case let .sequence(effects):
            return Effect(kind: .sequence(effects.map { mapEffect($0, transform) }))
        }
    }
}
