import SwiftUI

enum AppTab: Hashable {
    case focus, progress, settings
}

struct RootView: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(SettingsStore.self) private var settings
    @State private var selectedTab: AppTab = .focus

    var body: some View {
        @Bindable var engine = engine

        TabView(selection: $selectedTab) {
            FocusView()
                .tabItem { Label("Focus", systemImage: "timer") }
                .tag(AppTab.focus)

            ProgressScreen(selectedTab: $selectedTab)
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
                .tag(AppTab.progress)

            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .fullScreenCover(isPresented: $engine.isAlarmPresented) {
            TimesUpView()
        }
        .onChange(of: settings.alertStyle) {
            engine.handleAlertStyleDidChange()
        }
    }
}
