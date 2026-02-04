import SwiftUI

struct VisualizationView: View {
    var body: some View {
        ContentUnavailableView(
            "Visualization",
            systemImage: "chart.bar.xaxis",
            description: Text("This area will host visualizations. For now, use Explore Data from the top bar.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

