import KeyboardCore
import SwiftUI

struct KeyboardPreview: View {
    let settings: KeyboardSettings

    var body: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(Color(white: 0.09))
            .aspectRatio(1.55, contentMode: .fit)
            .overlay(Text("Hex").foregroundStyle(.secondary))
    }
}
