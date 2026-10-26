import SwiftUI

struct InputModePicker: View {
    @Binding var selection: InputMode
    let isEnabled: Bool

    var body: some View {
        Picker("Спосіб відображення", selection: $selection) {
            ForEach(InputMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(minHeight: 48)
        .disabled(!isEnabled)
    }
}

