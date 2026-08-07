import SwiftUI

struct LoginScreen: View {
    /// Called with the trimmed distinct id, tenant id, and whether user-token
    /// auth is enabled. The tenant id is empty when the field is left blank
    /// (no global tenant). When `enableUserToken` is false the user is
    /// identified with just the distinct id — no JWT fetch, no refresh callback.
    let onSubmit: (String, String, Bool) -> Void
    @State private var distinctID: String = ""
    @State private var tenantID: String = ""
    @State private var enableUserToken: Bool = true

    private var canSubmit: Bool {
        !distinctID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("Sign in")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                Text("Enter a distinct id to identify this user with SuprSend.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 12)

                Text("DISTINCT ID")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .kerning(0.5)
                    .padding(.top, 10)

                TextField("e.g. user@example.com", text: $distinctID)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textContentType(.username)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )

                Text("TENANT ID (OPTIONAL)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .kerning(0.5)
                    .padding(.top, 14)

                TextField("e.g. acme", text: $tenantID)
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

                Toggle(isOn: $enableUserToken) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable user token")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("Fetch a JWT and auto-refresh it. When off, identifies with just the distinct id.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 16)

                Button(action: {
                    let trimmedID = distinctID.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedTenant = tenantID.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedID.isEmpty { onSubmit(trimmedID, trimmedTenant, enableUserToken) }
                }) {
                    Text("Continue")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(canSubmit ? Color.black : Color(.systemGray3))
                        .cornerRadius(8)
                }
                .disabled(!canSubmit)
                .padding(.top, 20)
            }
            .padding(20)
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color(.secondarySystemBackground))
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}
