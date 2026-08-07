import SwiftUI

final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    @Published var message: String? = nil

    func show(_ text: String) {
        message = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.message == text {
                self?.message = nil
            }
        }
    }
}

struct ToastOverlay: View {
    @ObservedObject private var center = ToastCenter.shared

    var body: some View {
        VStack {
            Spacer()
            if let message = center.message {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: center.message)
        .allowsHitTesting(false)
    }
}
