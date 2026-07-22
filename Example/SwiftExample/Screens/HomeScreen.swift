import SwiftUI
import SuprSend

struct HomeScreen: View {
    let distinctID: String
    let onOpenPreferences: () -> Void
    let onOpenInbox: () -> Void
    let onLogout: () -> Void

    @EnvironmentObject private var inboxViewModel: InboxViewModel
    @AppStorage(SuprSendConstants.tenantIDKey) private var tenantID: String = ""
    @State private var loggingOut: Bool = false
    @State private var tenantInput: String = ""
    private let sampleEmail = "user@example.com"

    private var canSwitchTenant: Bool {
        let trimmed = tenantInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != tenantID
    }

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

            tenantSwitcher
                .padding(.bottom, 24)

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
        .onAppear { tenantInput = tenantID }
    }

    /// Switches the active tenant at runtime. The user's token must scope the
    /// target tenant (a `tenant_id` array in the JWT) — no re-identify needed.
    private var tenantSwitcher: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTIVE TENANT")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .kerning(0.5)

            HStack(spacing: 8) {
                TextField("e.g. acme", text: $tenantInput)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )

                Button(action: switchTenant) {
                    Text("Switch")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(canSwitchTenant ? Color.black : Color(.systemGray3))
                        .cornerRadius(8)
                }
                .disabled(!canSwitchTenant)
            }

            Text(tenantID.isEmpty ? "No tenant set" : "Current: \(tenantID)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private func switchTenant() {
        let trimmed = tenantInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != tenantID else { return }

        // Update the SDK's global tenant. Subsequent track/preferences/feed
        // calls are scoped to it.
        SuprSend.shared.changeTenant(tenantId: trimmed)
        tenantID = trimmed

        // Already-running feeds keep their original tenant, so re-initialise the
        // inbox feed to load the new tenant's notifications. Preferences re-fetch
        // on their own when that screen is next opened.
        inboxViewModel.reconnectAndRefresh()

        ToastCenter.shared.show("Switched to tenant \(trimmed)")
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
