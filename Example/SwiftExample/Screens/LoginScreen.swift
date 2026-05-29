import SwiftUI

struct LoginScreen: View {
    let onSubmit: (String) -> Void
    @State private var distinctID: String = ""

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

                Button(action: {
                    let trimmed = distinctID.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { onSubmit(trimmed) }
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
