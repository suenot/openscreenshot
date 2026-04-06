import SwiftUI

struct ToolbarView: View {
    @Binding var selectedScale: ScalePreset
    @State private var showOptions = false
    var onClose: () -> Void
    var onCapture: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // Close
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)

            Divider().frame(height: 20)

            // Region select mode (only mode — always active)
            Image(systemName: "selection.pin.in.out")
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.2))
                .cornerRadius(6)
                .padding(.horizontal, 4)

            Divider().frame(height: 20)

            // Options
            Button(action: { showOptions.toggle() }) {
                HStack(spacing: 2) {
                    Text("Options")
                        .font(.system(size: 13))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showOptions, arrowEdge: .top) {
                OptionsPopover(selectedScale: $selectedScale)
            }

            // Capture
            Button(action: onCapture) {
                Text("Capture")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.accentColor)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .frame(height: 44)
        .background(.regularMaterial)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
    }
}

struct OptionsPopover: View {
    @Binding var selectedScale: ScalePreset

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Scale")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.top, 8)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ForEach(ScalePreset.allCases, id: \.self) { preset in
                Button(action: {
                    selectedScale = preset
                    preset.save()
                }) {
                    HStack {
                        if selectedScale == preset {
                            Image(systemName: "checkmark")
                                .frame(width: 14)
                        } else {
                            Spacer().frame(width: 14)
                        }
                        Text(preset.displayName)
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
        .frame(minWidth: 130)
    }
}
