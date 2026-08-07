import SwiftUI

@main
struct SwiftExampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appDelegate.router)
                .onOpenURL { url in
                    appDelegate.router.handle(url: url)
                }
        }
    }
}
