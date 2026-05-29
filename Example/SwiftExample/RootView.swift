import SwiftUI
import SuprSend

struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @AppStorage(SuprSendConstants.distinctIDKey) private var distinctID: String = ""
    @State private var isIdentified: Bool = false

    var body: some View {
        Group {
            if distinctID.isEmpty {
                LoginScreen { id in
                    Task {
                        await SuprSendTokenService.identify(distinctID: id)
                        distinctID = id
                        isIdentified = true
                        router.screen = .home
                    }
                }
            } else if !isIdentified {
                ProgressView()
                    .task {
                        await SuprSendTokenService.identify(distinctID: distinctID)
                        isIdentified = true
                    }
            } else {
                AuthenticatedRootView(
                    distinctID: distinctID,
                    onLogout: handleLogout
                )
            }
        }
        .background(Color(.systemBackground))
        .overlay(ToastOverlay())
    }

    private func handleLogout() {
        Task {
            await SuprSend.shared.push.removePushSubscription()
            _ = await SuprSend.shared.reset()
            await MainActor.run {
                distinctID = ""
                isIdentified = false
                router.screen = .home
            }
        }
    }
}

private struct AuthenticatedRootView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var inboxViewModel = InboxViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasBackgrounded: Bool = false

    let distinctID: String
    let onLogout: () -> Void

    var body: some View {
        Group {
            switch router.screen {
            case .home:
                HomeScreen(
                    distinctID: distinctID,
                    onOpenPreferences: { router.screen = .preferences },
                    onOpenInbox: { router.screen = .inbox },
                    onLogout: onLogout
                )
            case .preferences:
                SubScreen(title: "Preferences", onBack: { router.screen = .home }) {
                    PreferenceScreen()
                }
            case .inbox:
                SubScreen(title: "Inbox", onBack: { router.screen = .home }) {
                    InboxScreen()
                }
            }
        }
        .environmentObject(inboxViewModel)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                wasBackgrounded = true
            } else if newPhase == .active && wasBackgrounded {
                wasBackgrounded = false
                inboxViewModel.reconnectAndRefresh()
            }
        }
    }
}

struct SubScreen<Content: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Text("‹ Back")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(minWidth: 70, alignment: .leading)
                }
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                Spacer().frame(minWidth: 70)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
            .overlay(Divider(), alignment: .bottom)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
