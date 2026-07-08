import SwiftUI

/// "Appearance" settings tab: choose the indicator palette used by the Loud /
/// Noise assessment cards, and browse the full OKLCH color set it is drawn
/// from. This replaces the old in-window toolbar palette menu.
struct AppearanceSettingsView: View {
    @AppStorage(IndicatorPalette.storageKey)
    private var paletteID = IndicatorPalette.defaultID

    private var selectedPalette: IndicatorPalette {
        IndicatorPalette.all.first { $0.id == paletteID } ?? IndicatorPalette.defaultPalette
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    previewCard(title: "Loud", value: "On target",
                                detail: "Matches your target", tint: selectedPalette.positive)
                    previewCard(title: "Level", value: "Below target",
                                detail: "A little quiet", tint: selectedPalette.caution)
                    previewCard(title: "Noise", value: "More noise",
                                detail: "Louder than before", tint: selectedPalette.critical)
                }
                .padding(.vertical, 2)
            } header: {
                Text("Preview")
            } footer: {
                Text("How the assessment cards look with **\(selectedPalette.name)** — positive, caution and critical.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(IndicatorPalette.all) { palette in
                    paletteRow(palette)
                }
            } header: {
                Text("Indicator palette")
            } footer: {
                Text("Colors for the assessment cards — positive · caution · critical. Press **↑ / ↓** to step through palettes, or **P** to cycle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(IndicatorHue.Role.allCases) { role in
                    hueGroup(role)
                }
            } header: {
                Text("Color options")
            } footer: {
                Text("Perceptually-uniform OKLCH hues from the Style Explorer palette set (Radix step 9 in light, step 10 in dark). Each palette above pairs one positive, one caution and one critical hue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
        .frame(minHeight: 460)
    }

    // MARK: Preview

    /// A miniature of ContentView's assessment card so the palette can be
    /// judged in context. Mirrors metricCard's dot + tinted-surface styling.
    private func previewCard(title: String, value: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Palette rows

    @ViewBuilder
    private func paletteRow(_ palette: IndicatorPalette) -> some View {
        Button {
            paletteID = palette.id
        } label: {
            HStack(spacing: 12) {
                triadPreview(palette)
                Text(palette.name)
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tint)
                    .opacity(palette.id == paletteID ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func triadPreview(_ palette: IndicatorPalette) -> some View {
        HStack(spacing: 3) {
            ForEach(palette.roleHues, id: \.role) { entry in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(entry.hue.color)
                    .frame(width: 18, height: 18)
                    .help("\(entry.role.label): \(entry.hue.name)")
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
                .padding(-1)
        )
    }

    // MARK: Hue reference

    @ViewBuilder
    private func hueGroup(_ role: IndicatorHue.Role) -> some View {
        let hues = IndicatorHue.hues(in: role)
        VStack(alignment: .leading, spacing: 8) {
            Text(role.label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 84), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(hues) { hue in
                    hueChip(hue)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func hueChip(_ hue: IndicatorHue) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(hue.color)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(.quaternary, lineWidth: 0.5))
            Text(hue.name)
                .font(.caption)
                .lineLimit(1)
        }
        .help("\(hue.name) · light \(hue.lightOKLCH) · dark \(hue.darkOKLCH)")
    }
}

#if DEBUG
#Preview("Appearance") { AppearanceSettingsView() }
#endif
