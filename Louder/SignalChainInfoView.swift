import SwiftUI

/// The signal-chain explainer shown from the toolbar's info button: a little
/// schematic of connected stompboxes describing the chain the voice passes
/// through for the current selection, plus a per-step breakdown of the model
/// and parameters applied. In Compare mode every preset's chain is listed.
///
/// Lives outside `ContentView` so the AppKit toolbar item can present the very
/// same content the in-window button used to.
struct SignalChainInfoView: View {
    let compareMode: Bool
    let preset: ProcessingPreset

    /// Chain schematic plus the per-step breakdown.
    @ViewBuilder
    var body: some View {
        if compareMode {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ProcessingPreset.comparePresets) { preset in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(preset.title, systemImage: preset.iconName)
                                .font(.subheadline.weight(.semibold))
                            signalChainRow(for: preset)
                                .frame(maxWidth: .infinity, alignment: .center)
                            signalChainDetails(for: preset)
                        }
                        if preset != ProcessingPreset.comparePresets.last {
                            Divider()
                        }
                    }
                }
                .padding(18)
            }
            .frame(width: 380, height: 460)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    signalChainRow(for: preset)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Divider()
                    signalChainDetails(for: preset)
                }
                .padding(18)
            }
            .frame(width: 360)
            .frame(maxHeight: 520)
        }
    }

    /// Per-step breakdown: icon, step name, and the model/parameters it applies.
    private func signalChainDetails(for preset: ProcessingPreset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(preset.signalChain.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 9) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.14))
                        Image(systemName: step.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(index + 1). \(step.name)")
                            .font(.subheadline.weight(.semibold))
                        Text(step.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !step.docs.isEmpty {
                            HStack(spacing: 12) {
                                ForEach(step.docs) { doc in
                                    Link(destination: doc.url) {
                                        HStack(spacing: 3) {
                                            Image(systemName: "arrow.up.right.square")
                                            Text(doc.title)
                                        }
                                        .font(.caption2.weight(.medium))
                                    }
                                }
                            }
                            .padding(.top, 1)
                        }
                    }
                }
            }
        }
    }

    /// A horizontal run of pedals connected by a cable, with short in/out stubs
    /// at each end to suggest signal flow.
    private func signalChainRow(for preset: ProcessingPreset) -> some View {
        let steps = preset.signalChain
        return HStack(alignment: .top, spacing: 0) {
            signalCable
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                if index > 0 { signalCable }
                stompbox(step)
            }
            signalCable
        }
        .padding(.vertical, 2)
    }

    /// A short length of patch cable, vertically aligned to a 44pt pedal's center.
    private var signalCable: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.45))
            .frame(width: 12, height: 2)
            .padding(.top, 21)
    }

    private func stompbox(_ step: SignalStep) -> some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.accentColor.opacity(0.14))
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                Image(systemName: step.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 44, height: 44)
            Text(step.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 58)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Toolbar accessory that opens the signal-chain explainer for whatever is
/// currently selected. It reads the preset straight from defaults and the
/// Compare flag from the queue, so the AppKit toolbar can host it without
/// reaching into `ContentView`.
struct SignalChainInfoToolbarButton: View {
    let queue: DropQueue
    @AppStorage(ProcessingPreset.preferenceKey)
    private var presetRawValue = ProcessingPreset.persisted.rawValue
    @State private var isPresented = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 22, height: 22)
                // Plain by default; the usual toolbar backing is drawn only
                // while the pointer is over the button or the popover is open.
                .background {
                    Circle()
                        .fill(Color.primary.opacity(0.09))
                        .opacity(isHovering || isPresented ? 1 : 0)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .help("Show the signal chain applied for this preset")
        .accessibilityLabel("Signal chain")
        .accessibilityHint("Shows the processing applied for the current preset")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SignalChainInfoView(
                compareMode: queue.compareMode,
                preset: ProcessingPreset.selectable(from: presetRawValue)
            )
        }
    }
}
