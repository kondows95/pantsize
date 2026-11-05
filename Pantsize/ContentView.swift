import SwiftUI

/// アプリ起動時のルート（計測プロジェクト一覧）。
struct ContentView: View {
    var body: some View {
        ProjectListView()
    }
}

#Preview {
    ContentView()
        .environment(ProjectStore())
}
