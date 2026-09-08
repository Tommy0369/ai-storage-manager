import SwiftUI
import AppServices

struct OverviewView: View {
    @EnvironmentObject private var viewModel: StorageViewModel

    var body: some View {
        StorageExplorerView(heroMode: true)
    }
}
