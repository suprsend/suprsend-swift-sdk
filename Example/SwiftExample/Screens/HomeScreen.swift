import SwiftUI
import SuprSend

struct HomeScreen: View {
    let distinctID: String
    let onOpenPreferences: () -> Void
    let onOpenInbox: () -> Void
    let onLogout: () -> Void

    @EnvironmentObject private var inboxViewModel: InboxViewModel
    @State private var loggingOut: Bool = false
    private let sampleEmail = "user@example.com"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Text(distinctID)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .padding(.bottom, 28)

            VStack(spacing: 12) {
                actionButton("Preferences", action: onOpenPreferences)
                inboxButton
                actionButton("Add email") {
                    Task {
                        let r = await SuprSend.shared.user.addEmail(sampleEmail)
                        ToastCenter.shared.show(r.status == .error ? "Add email failed" : "Add email ok")
                    }
                }
                actionButton("Remove email") {
                    Task {
                        let r = await SuprSend.shared.user.removeEmail(sampleEmail)
                        ToastCenter.shared.show(r.status == .error ? "Remove email failed" : "Remove email ok")
                    }
                }
                actionButton("Track event") {
                    Task {
                        let r = await SuprSend.shared.track(
                            event: "home_button_clicked",
                            properties: ["source": "home_screen"]
                        )
                        ToastCenter.shared.show(r.status == .error ? "Track event failed" : "Track event ok")
                    }
                }
            }

            Spacer()

            Button(action: {
                if loggingOut { return }
                loggingOut = true
                onLogout()
            }) {
                HStack {
                    if loggingOut {
                        ProgressView()
                    } else {
                        Text("Logout")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            }
            .opacity(loggingOut ? 0.6 : 1)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemBackground))
    }

    private var inboxButton: some View {
        ZStack(alignment: .topTrailing) {
            actionButton("Inbox") {
                inboxViewModel.resetBadge()
                onOpenInbox()
            }
            if inboxViewModel.badge > 0 {
                Text("\(inboxViewModel.badge)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Color(red: 0.145, green: 0.388, blue: 0.922))
                    .clipShape(Capsule())
                    .offset(x: 8, y: -8)
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.black)
                .cornerRadius(10)
        }
    }
}
