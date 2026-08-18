import SwiftUI
import SwiftData

@main
struct PomodoroApp: App {
    @State private var settings = SettingsStore()
    @State private var engine: TimerEngine
    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer

    init() {
        let settings = SettingsStore()
        let container: ModelContainer
        do {
            container = try ModelContainer(for: PomodoroSession.self)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
        self.container = container
        _settings = State(initialValue: settings)
        _engine = State(initialValue: TimerEngine(
            settings: settings,
            modelContext: container.mainContext
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(engine)
                .preferredColorScheme(.dark)
                .tint(.pomodoroOrange)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                engine.reconcileWithSystem()
            }
        }
    }
}
