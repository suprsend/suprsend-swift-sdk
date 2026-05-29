import Foundation

enum Screen: String {
    case home
    case preferences
    case inbox
}

final class AppRouter: ObservableObject {
    @Published var screen: Screen = .home

    func handle(url: URL) {
        let host = url.host?.lowercased()
        let firstPath = url.pathComponents.first(where: { $0 != "/" })?.lowercased()
        let key = host ?? firstPath
        if let key, let target = Screen(rawValue: key) {
            screen = target
        }
    }
}
