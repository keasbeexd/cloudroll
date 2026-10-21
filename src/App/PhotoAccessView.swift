import SwiftUI

/// Explains why Cloudroll asks for photo access before iOS shows its own prompt.
struct PhotoAccessView: View {
    let onChoice: (Bool) -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.tint)
            Text("Show this iPhone's photos?")
                .font(.title2.weight(.semibold))
            Text("Cloudroll can show the photos and videos on this iPhone in your Memories timeline. Photos already on your server appear only once. Nothing is uploaded.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                Button {
                    onChoice(true)
                } label: {
                    Text("Allow access").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Not now") { onChoice(false) }
                    .controlSize(.large)
            }
        }
        .padding(24)
    }
}
