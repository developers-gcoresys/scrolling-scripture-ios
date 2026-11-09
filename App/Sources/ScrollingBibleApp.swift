import SwiftUI

@main
struct ScrollingBibleApp: App {
    @StateObject private var model: ReaderModel
    @StateObject private var pro: ProManager
    @StateObject private var ads: AdsManager

    init() {
        FirebaseRuntime.configure()
        let pro = ProManager(appId: ReaderModel.appId)
        let ads = AdsManager()
        _pro = StateObject(wrappedValue: pro)
        _ads = StateObject(wrappedValue: ads)
        _model = StateObject(wrappedValue: ReaderModel(pro: pro, ads: ads))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(pro)
                .environmentObject(ads)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: ReaderModel
    @EnvironmentObject private var pro: ProManager

    var body: some View {
        Group {
            if let error = model.loadError {
                ContentUnavailableView(
                    "Edition unavailable",
                    systemImage: "book.closed",
                    description: Text(error)
                )
            } else {
                ReaderScreen()
            }
        }
        .task {
            model.start()
            await pro.refreshEntitlement()
        }
    }
}
