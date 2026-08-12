import SwiftUI
import SuprSend

struct HomeScreen: View {
    let distinctID: String
    let onOpenPreferences: () -> Void
    let onOpenInbox: () -> Void
    let onLogout: () -> Void

    @EnvironmentObject private var inboxViewModel: InboxViewModel
    @AppStorage(StorageKeys.tenantID) private var tenantID: String = ""
    @State private var loggingOut: Bool = false
    @State private var tenantInput: String = ""
    private let sampleEmail = "user@example.com"
    private let samplePhone = "+15555550100"
    private let samplePushToken = "sample-apns-device-token"

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

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    tenantSwitcher

                    VStack(spacing: 12) {
                        actionButton("Preferences", action: onOpenPreferences)
                        inboxButton
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

                    userMethodsSection
                    channelMethodsSection
                }
                .padding(.bottom, 16)
            }

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

    /// Every user-property method in both call styles: the single key/value
    /// convenience and the dictionary form. Both funnel into the same
    /// `UserProperty` encoding path, so this doubles as a live regression
    /// check for the PR #7 crash.
    private var userMethodsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("USER METHODS — KEY/VALUE VS DICTIONARY")
            HStack(spacing: 8) {
                testButton("set (k,v)") {
                    await SuprSend.shared.user.set(key: "plan", value: "pro")
                }
                testButton("set {dict}") {
                    await SuprSend.shared.user.set(properties: ["plan": "pro", "trial": false])
                }
            }
            HStack(spacing: 8) {
                testButton("setOnce (k,v)") {
                    await SuprSend.shared.user.setOnce(key: "signup_source", value: "ios_example")
                }
                testButton("setOnce {dict}") {
                    await SuprSend.shared.user.setOnce(properties: ["signup_source": "ios_example"])
                }
            }
            HStack(spacing: 8) {
                testButton("increment (k,v)") {
                    await SuprSend.shared.user.increment(key: "login_count", value: 1)
                }
                testButton("increment {dict}") {
                    await SuprSend.shared.user.increment(properties: ["login_count": 1, "session_count": 2])
                }
            }
            HStack(spacing: 8) {
                testButton("append (k,v)") {
                    await SuprSend.shared.user.append(key: "tags", value: "swift")
                }
                testButton("append {dict}") {
                    await SuprSend.shared.user.append(properties: ["tags": "sdk-test"])
                }
            }
            HStack(spacing: 8) {
                testButton("remove (k,v)") {
                    await SuprSend.shared.user.remove(key: "tags", value: "swift")
                }
                testButton("remove {dict}") {
                    await SuprSend.shared.user.remove(properties: ["tags": "sdk-test"])
                }
            }
            HStack(spacing: 8) {
                testButton("unset (key)") {
                    await SuprSend.shared.user.unset(key: "plan")
                }
                testButton("unset [keys]") {
                    await SuprSend.shared.user.unset(keys: ["plan", "trial"])
                }
            }
        }
    }

    /// Add/remove pairs for every channel method, plus the two channel setters.
    private var channelMethodsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("CHANNEL METHODS — ADD / REMOVE")
            HStack(spacing: 8) {
                testButton("add email") {
                    await SuprSend.shared.user.addEmail(sampleEmail)
                }
                testButton("remove email") {
                    await SuprSend.shared.user.removeEmail(sampleEmail)
                }
            }
            HStack(spacing: 8) {
                testButton("add SMS") {
                    await SuprSend.shared.user.addSMS(samplePhone)
                }
                testButton("remove SMS") {
                    await SuprSend.shared.user.removeSMS(samplePhone)
                }
            }
            HStack(spacing: 8) {
                testButton("add WhatsApp") {
                    await SuprSend.shared.user.addWhatsapp(samplePhone)
                }
                testButton("remove WhatsApp") {
                    await SuprSend.shared.user.removeWhatsapp(samplePhone)
                }
            }
            HStack(spacing: 8) {
                testButton("add Slack") {
                    await SuprSend.shared.user.addSlack(["email": sampleEmail])
                }
                testButton("remove Slack") {
                    await SuprSend.shared.user.removeSlack(["email": sampleEmail])
                }
            }
            HStack(spacing: 8) {
                testButton("add MS Teams") {
                    await SuprSend.shared.user.addMSTeams(["user_id": "ms-user-1"])
                }
                testButton("remove MS Teams") {
                    await SuprSend.shared.user.removeMSTeams(["user_id": "ms-user-1"])
                }
            }
            HStack(spacing: 8) {
                testButton("add iOS push") {
                    await SuprSend.shared.user.addiOSPush(samplePushToken)
                }
                testButton("remove iOS push") {
                    await SuprSend.shared.user.removeiOSPush(samplePushToken)
                }
            }
            HStack(spacing: 8) {
                testButton("set language (en)") {
                    await SuprSend.shared.user.setPreferredLanguage("en")
                }
                testButton("set timezone") {
                    await SuprSend.shared.user.setTimezone("America/Los_Angeles")
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
            .kerning(0.5)
    }

    /// A compact button that fires one SDK call and toasts the outcome.
    @ViewBuilder
    private func testButton(_ title: String, call: @escaping () async -> APIResponse) -> some View {
        Button {
            Task {
                let r = await call()
                ToastCenter.shared.show(r.status == .error ? "\(title) failed" : "\(title) ok")
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
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
