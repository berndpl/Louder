import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct TrafficLightDropBorder: Shape {
    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = 1
        // A slightly broader arc visually follows AppKit's continuous
        // (squircle-like) window corner better than a strict inset circle.
        let radius: CGFloat = 18
        let topStart: CGFloat = 88
        let leftEnd: CGFloat = 56
        let left = rect.minX + inset
        let top = rect.minY + inset
        let right = rect.maxX - inset
        let bottom = rect.maxY - inset

        var path = Path()
        path.move(to: CGPoint(x: left + topStart, y: top))
        path.addLine(to: CGPoint(x: right - radius, y: top))
        path.addArc(
            center: CGPoint(x: right - radius, y: top + radius),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: right, y: bottom - radius))
        path.addArc(
            center: CGPoint(x: right - radius, y: bottom - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: left + radius, y: bottom))
        path.addArc(
            center: CGPoint(x: left + radius, y: bottom - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: left, y: top + leftEnd))
        return path
    }
}

struct ContentView: View {
    private static let compareSelection = "compare"

    let queue: DropQueue
    let comparisonPlayer: ComparisonPlayer
    @State private var isTargeted = false
    @State private var hoveredSeriesID: UUID?
    @State private var selectedVersionID: UUID?
    @AppStorage(ProcessingPreset.preferenceKey)
    private var selectedPresetRawValue = ProcessingPreset.persisted.rawValue

    private var selectedPreset: ProcessingPreset {
        let stored = ProcessingPreset(rawValue: selectedPresetRawValue) ?? .gentleBoostDenoise
        return ProcessingPreset.pickerCases.contains(stored)
            ? stored
            : (ProcessingPreset.pickerCases.first ?? .gentleBoostDenoise)
    }

    private var processingItem: DropQueue.Item? {
        queue.items.first {
            if case .processing = $0.status { true } else { false }
        }
    }

    private var latestCompletedItem: DropQueue.Item? {
        queue.items.last {
            if case .done = $0.status { true } else { false }
        }
    }

    private var issueItems: [DropQueue.Item] {
        queue.items.filter {
            switch $0.status {
            case .failed: true
            case .done(let detail): detail != nil
            case .waiting, .processing: false
            }
        }
    }

    private var focusedSeries: LoudnessSeries? {
        if let hoveredSeriesID {
            return queue.series.first { $0.id == hoveredSeriesID }
        }
        if let activeSeriesID = comparisonPlayer.activeSeriesID {
            return queue.series.first { $0.id == activeSeriesID }
        }
        if let selectedVersionID,
           let selected = queue.series.first(where: { $0.id == selectedVersionID }) {
            return selected
        }
        return queue.series.last { $0.preset == highlightedPreset }
            ?? queue.series.last
    }

    /// Newly created output files for the currently focused source, in Compare
    /// display order. Excludes the untouched original / backup.
    private var focusedSourceOutputs: [LoudnessSeries] {
        guard let sourceID = focusedSeries?.sourceID else { return [] }
        let order = ProcessingPreset.comparePresets
        return queue.series
            .filter { $0.sourceID == sourceID && !$0.isOriginal }
            .sorted { lhs, rhs in
                let li = lhs.preset.flatMap { order.firstIndex(of: $0) } ?? Int.max
                let ri = rhs.preset.flatMap { order.firstIndex(of: $0) } ?? Int.max
                return li < ri
            }
    }

    /// Among the current batch's generated outputs, the one whose integrated
    /// loudness sits closest to its preset target. `nil` unless there are at
    /// least two outputs to compare.
    private var bestLoudnessSeriesID: UUID? {
        let outputs = focusedSourceOutputs
        guard outputs.count > 1 else { return nil }
        return outputs.min { lhs, rhs in
            loudnessDistance(for: lhs) < loudnessDistance(for: rhs)
        }?.id
    }

    /// Among the current batch's generated outputs, the one with the highest
    /// signal-to-noise ratio (least audible background noise). `nil` unless at
    /// least two outputs expose an SNR estimate.
    private var bestNoiseSeriesID: UUID? {
        let rated = focusedSourceOutputs.filter { $0.metrics.estimatedSNR != nil }
        guard rated.count > 1 else { return nil }
        return rated.max { lhs, rhs in
            (lhs.metrics.estimatedSNR ?? -.infinity) < (rhs.metrics.estimatedSNR ?? -.infinity)
        }?.id
    }

    private func loudnessDistance(for series: LoudnessSeries) -> Double {
        let target = Double(series.preset?.targetLUFS ?? -16)
        return abs(series.metrics.integratedLUFS - target)
    }

    private var processingSelection: Binding<String> {
        Binding(
            get: {
                queue.compareMode
                    ? Self.compareSelection
                    : selectedPreset.rawValue
            },
            set: { selection in
                guard queue.isIdle else { return }
                if selection == Self.compareSelection {
                    queue.compareMode = true
                    if let original = currentOriginal {
                        comparisonPlayer.stop()
                        queue.enqueue(
                            [original.url],
                            preset: selectedPreset,
                            compare: true,
                            addFades: AudioFades.persisted,
                            trimSilence: TrimSilence.persisted,
                            renameOriginal: RenameOriginal.persisted,
                            stages: StudioBoothStages.all
                        )
                    }
                } else if queue.compareMode {
                    // Leaving Compare: drop the comparison artifacts, then regenerate
                    // the single chosen preset for the active file.
                    let source = currentOriginal?.url
                    comparisonPlayer.stop()
                    queue.discardComparison()
                    queue.compareMode = false
                    selectedPresetRawValue = selection
                    reprocess(source, with: selection)
                } else if selection != selectedPresetRawValue {
                    // Switching between presets: rerun generation with the new preset
                    // and clean up the previously generated output.
                    let source = pristineSourceURL
                    comparisonPlayer.stop()
                    queue.undoLatestBatch()
                    selectedPresetRawValue = selection
                    reprocess(source, with: selection)
                }
            }
        )
    }

    /// The pristine, unprocessed source file for the active item, regardless of
    /// whether the last run replaced the original in place or saved a new file.
    private var pristineSourceURL: URL? {
        if let operations = queue.latestTransaction?.operations {
            for operation in operations {
                if case .restore(let originalURL, _) = operation {
                    return originalURL
                }
            }
        }
        return currentOriginal?.url
    }

    private func reprocess(_ source: URL?, with selection: String) {
        guard let source, let preset = ProcessingPreset(rawValue: selection) else { return }
        queue.enqueue(
            [source],
            preset: preset,
            compare: false,
            addFades: AudioFades.persisted,
            trimSilence: TrimSilence.persisted,
            renameOriginal: RenameOriginal.persisted,
            stages: StudioBoothStages.all
        )
    }

    private var currentOriginal: LoudnessSeries? {
        if let focusedSeries {
            if focusedSeries.isOriginal {
                return focusedSeries
            }
            if let match = queue.series.first(where: {
                $0.sourceID == focusedSeries.sourceID && $0.isOriginal
            }) {
                return match
            }
        }
        return queue.series.last(where: { $0.isOriginal })
    }

    private var highlightedPreset: ProcessingPreset? {
        if queue.series.contains(where: { $0.preset == selectedPreset }) {
            return selectedPreset
        }
        return queue.series.last(where: { !$0.isOriginal })?.preset
    }

    private var matchingOriginal: LoudnessSeries? {
        guard let focusedSeries, !focusedSeries.isOriginal else { return nil }
        return queue.series.first {
            $0.sourceID == focusedSeries.sourceID && $0.isOriginal
        }
    }

    var body: some View {
        dropZone
            .padding(4)
            .frame(width: 460)
            .frame(minHeight: 350)
            .background(.background)
            .ignoresSafeArea(.container, edges: .top)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
            .onExitCommand {
                if queue.canCancel {
                    queue.cancelProcessing()
                }
            }
    }

    private var dropZone: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted ? Color.accentColor.opacity(0.05) : .clear)

            TrafficLightDropBorder()
                .stroke(
                    isTargeted ? Color.accentColor : .secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8])
                )

            VStack(spacing: 12) {
                loudnessChart
                statusDescription
                processingControls

                if let focusedSeries {
                    metrics(for: focusedSeries)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cancelButton: some View {
        Button(role: .cancel) {
            queue.cancelProcessing()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Cancel")
        .disabled(!queue.canCancel)
    }

    @ViewBuilder
    private var loudnessChart: some View {
        if !queue.series.isEmpty {
            CompactWaveformView(
                series: queue.series,
                highlightedPreset: highlightedPreset,
                selectedSeriesID: focusedSeries?.id,
                hoveredSeriesID: hoveredSeriesID,
                activeSeriesID: comparisonPlayer.activeSeriesID,
                playbackProgress: comparisonPlayer.progress,
                onHover: { hoveredSeriesID = $0 },
                onSelect: { comparisonPlayer.toggle($0) }
            )
            .frame(height: 86)
            .padding(.horizontal, 8)
        } else if processingItem == nil {
            // Idle empty state: show the glyph as a centered anchor.
            Image("LouderForeground")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 50, height: 50)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
                .frame(height: 86)
                .padding(.horizontal, 8)
        }
        // While processing with no series yet, render nothing so the status and
        // picker stay vertically centered instead of being pushed down by an
        // empty chart placeholder.
    }

    @ViewBuilder
    private var statusDescription: some View {
        if let processingItem {
            VStack(spacing: 2) {
                Text(processingItem.url.lastPathComponent)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if case .processing(let message) = processingItem.status {
                    Text(queue.isCancelling ? "Cancelling…" : message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    // Invisible twin of the cancel button balances the real one
                    // on the right so the progress bar stays centered.
                    cancelButton.hidden()
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 250)
                    cancelButton
                }
                .padding(.top, 5)
            }
        } else {
            VStack(spacing: 5) {
                if statusNotices.isEmpty {
                    if !focusedSourceOutputs.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(focusedSourceOutputs) { series in
                                fileRow(for: series)
                            }
                        }
                    } else if let focusedSeries {
                        revealInFinderButton(for: focusedSeries)
                    } else if let completedItem = latestCompletedItem {
                        revealInFinderButton(
                            url: completedItem.url,
                            title: completedItem.url.lastPathComponent,
                            preset: completedItem.preset
                        )
                    } else {
                        Text("\(processingPathDescription)\nDrop videos here or on the Dock icon")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    ForEach(statusNotices) { notice in
                        statusNotice(title: notice.title, detail: notice.detail)
                    }
                }
            }
            .frame(maxWidth: 330)
        }
    }

    /// Seconds of silence trimmed for the currently focused source, if any.
    @ViewBuilder
    private func trimmedCard(for series: LoudnessSeries) -> some View {
        if let seconds = queue.trimmedSecondsBySource[series.sourceID] {
            metricCard(
                title: "Clip",
                value: "\(formattedTrim(seconds)) trimmed",
                detail: "Removed silence at the start and end of the clip.",
                tint: .gray,
                help: "Leading and trailing silence trimmed from the recording before processing."
            )
        }
    }

    private func formattedTrim(_ seconds: Double) -> String {
        if seconds >= 60 {
            let minutes = Int(seconds) / 60
            let remainder = seconds - Double(minutes * 60)
            return String(format: "%d:%04.1f", minutes, remainder)
        }
        return String(format: "%.1fs", seconds)
    }

    private struct StatusNotice: Identifiable {
        let id: String
        let title: String
        let detail: String
    }

    private var statusNotices: [StatusNotice] {
        var notices: [StatusNotice] = []
        if let undoError = queue.undoError {
            notices.append(.init(id: "undo", title: "Undo failed", detail: undoError))
        }
        if let playbackError = comparisonPlayer.errorMessage {
            notices.append(.init(id: "playback", title: "Playback failed", detail: playbackError))
        }
        for item in issueItems {
            switch item.status {
            case .failed(let detail):
                notices.append(.init(
                    id: item.id.uuidString,
                    title: item.url.lastPathComponent,
                    detail: detail
                ))
            case .done(let detail):
                if let detail {
                    notices.append(.init(
                        id: item.id.uuidString,
                        title: item.url.lastPathComponent,
                        detail: detail
                    ))
                }
            case .waiting, .processing:
                break
            }
        }
        return notices
    }

    /// One row in the created-files list: tap the name to focus that version
    /// (highlighted curve + metric cards); the folder icon reveals it in Finder.
    private func fileRow(for series: LoudnessSeries) -> some View {
        let isFocused = focusedSeries?.id == series.id
        let iconName = series.preset?.iconName ?? "checkmark.circle.fill"
        let iconColor = series.preset?.tint ?? .positive
        return HStack(spacing: 7) {
            Button {
                selectedVersionID = series.id
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: iconName)
                        .foregroundStyle(iconColor)
                    Text(series.url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                }
                .fontWeight(isFocused ? .medium : .regular)
                .opacity(isFocused ? 1 : 0.5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    hoveredSeriesID = series.id
                } else if hoveredSeriesID == series.id {
                    hoveredSeriesID = nil
                }
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([series.url])
            } label: {
                Image(systemName: "folder")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Reveal in Finder")
        }
    }

    private func revealInFinderButton(for series: LoudnessSeries) -> some View {
        // Avoid duplicating the symbol when the picker already shows this file's preset.
        let pickerShowsSameIcon = !queue.compareMode && series.preset == selectedPreset
        return revealInFinderButton(
            url: series.url,
            title: series.url.lastPathComponent,
            isOriginal: series.isOriginal,
            preset: series.preset,
            showIcon: !pickerShowsSameIcon
        )
    }

    private func revealInFinderButton(
        url: URL,
        title: String,
        isOriginal: Bool = false,
        preset: ProcessingPreset? = nil,
        showIcon: Bool = true
    ) -> some View {
        let iconName: String
        let iconColor: Color
        if isOriginal {
            iconName = "waveform.circle.fill"
            iconColor = .secondary
        } else if let preset {
            iconName = preset.iconName
            iconColor = preset.tint
        } else {
            iconName = "checkmark.circle.fill"
            iconColor = .positive
        }
        return Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            HStack(spacing: 7) {
                if showIcon {
                    Image(systemName: iconName)
                        .foregroundStyle(iconColor)
                }
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.callout.weight(.medium))
        .help("Show \(title) in Finder")
        .accessibilityLabel("Show \(title) in Finder")
    }

    private func statusNotice(title: String, detail: String) -> some View {
        VStack(alignment: .center, spacing: 1) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.caution)
                Text(title)
                    .lineLimit(1)
            }
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .font(.caption)
        .frame(maxWidth: 330, alignment: .center)
    }

    private var processingControls: some View {
        Picker("Preset", selection: processingSelection) {
            ForEach(ProcessingPreset.pickerCases) { preset in
                Label(preset.pickerTitle, systemImage: preset.iconName).tag(preset.rawValue)
            }
            Divider()
            Text("Compare").tag(Self.compareSelection)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .disabled(!queue.isIdle)
    }

    /// Subtitle describing the processing path that will run for the current
    /// selection (or the Compare fan-out).
    private var processingPathDescription: String {
        if queue.compareMode {
            return "Generates Louder and Studio to compare"
        }
        return selectedPreset.pathDescription
    }

    private func metrics(for series: LoudnessSeries) -> some View {
        HStack(spacing: 8) {
            metricCard(
                title: "Loudness · \(signed(series.metrics.integratedLUFS, digits: 1)) LUFS",
                value: loudnessSummary(for: series),
                detail: loudnessAssessment(for: series),
                tint: loudnessTint(for: series),
                isBest: series.id == bestLoudnessSeriesID,
                help: "Perceived loudness versus the original. Roughly every 10 LU doubles or halves how loud it sounds, so the percentage reflects the audible change, not the raw level."
            )
            metricCard(
                title: noiseTitle(for: series),
                value: noiseSummary(for: series),
                detail: noiseAssessment(for: series),
                tint: noiseTint(for: series),
                isBest: series.id == bestNoiseSeriesID,
                help: "Perceived background noise versus the original, estimated from active and quiet sections. The percentage reflects how much more or less noise you'd hear; this is a practical estimate, not a clean-reference measurement."
            )
            trimmedCard(for: series)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func metricCard(
        title: String,
        value: String,
        detail: String,
        tint: Color,
        isBest: Bool = false,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(title)
                    .lineLimit(1)
                if isBest {
                    Spacer(minLength: 4)
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .help("Best value in this batch")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .help(help)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    queue.enqueue(
                        [url],
                        preset: selectedPreset,
                        compare: queue.compareMode,
                        addFades: AudioFades.persisted,
                        trimSilence: TrimSilence.persisted,
                        renameOriginal: RenameOriginal.persisted,
                        stages: StudioBoothStages.all
                    )
                }
            }
        }
        return !providers.isEmpty
    }

    private func loudnessSummary(for series: LoudnessSeries) -> String {
        guard !series.isOriginal,
              let original = matchingOriginal else {
            return "Original level"
        }
        let change = series.metrics.integratedLUFS - original.metrics.integratedLUFS
        if abs(change) <= 0.5 {
            return "About the same"
        }
        let percent = abs(perceivedPercent(fromDecibels: change))
        return "≈\(percentString(percent)) \(change > 0 ? "louder" : "quieter")"
    }

    /// Perceived loudness change for a level difference in dB/LU, using the
    /// psychoacoustic rule of thumb that ~10 dB doubles perceived loudness.
    private func perceivedPercent(fromDecibels delta: Double) -> Double {
        (pow(2, delta / 10) - 1) * 100
    }

    private func percentString(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func loudnessAssessment(for series: LoudnessSeries) -> String {
        if hoveredSeriesID == series.id || comparisonPlayer.activeSeriesID == series.id {
            return series.displayName
        }
        guard let preset = series.preset else { return "Original recording" }
        let distance = series.metrics.integratedLUFS - Double(preset.targetLUFS)
        if abs(distance) <= 1 {
            return "On target"
        }
        return distance < 0 ? "Below target" : "Above target"
    }

    private func loudnessTint(for series: LoudnessSeries) -> Color {
        guard let preset = series.preset else { return .secondary }
        let distance = abs(series.metrics.integratedLUFS - Double(preset.targetLUFS))
        return distance <= 1 ? .positive : .caution
    }

    private func noiseTitle(for series: LoudnessSeries) -> String {
        guard let snr = series.metrics.estimatedSNR else {
            return "Noise estimate"
        }
        return "Noise estimate · \(signed(snr, digits: 0, showPlus: false)) dB SNR"
    }

    private func noiseSummary(for series: LoudnessSeries) -> String {
        guard let snr = series.metrics.estimatedSNR else {
            return "Unknown"
        }
        if !series.isOriginal,
           let originalSNR = matchingOriginal?.metrics.estimatedSNR {
            let change = snr - originalSNR
            if abs(change) <= 0.5 {
                return "About the same"
            }
            // Higher SNR means a lower noise level, so the noise change in dB is -change.
            let percent = abs(perceivedPercent(fromDecibels: -change))
            return "≈\(percentString(percent)) \(change > 0 ? "less noise" : "more noise")"
        }
        switch snr {
        case 30...: return "Barely audible"
        case 20..<30: return "Slight"
        case 15..<20: return "Noticeable"
        default: return "Prominent"
        }
    }

    private func noiseAssessment(for series: LoudnessSeries) -> String {
        guard let snr = series.metrics.estimatedSNR else {
            return "Not enough quiet gaps to judge"
        }
        switch snr {
        case 30...: return "Low concern"
        case 20..<30: return "Usually fine"
        case 15..<20: return "May distract"
        default: return "Likely distracting"
        }
    }

    private func noiseTint(for series: LoudnessSeries) -> Color {
        guard let snr = series.metrics.estimatedSNR else { return .secondary }
        switch snr {
        case 20...: return .positive
        case 15..<20: return .caution
        default: return .critical
        }
    }

    private func signed(
        _ value: Double,
        digits: Int,
        showPlus: Bool = true
    ) -> String {
        let format = showPlus ? "%+.\(digits)f" : "%.\(digits)f"
        return String(format: format, locale: Locale(identifier: "en_US_POSIX"), value)
            .replacingOccurrences(of: "-", with: "−")
    }

}

#Preview {
    ContentView(queue: DropQueue(), comparisonPlayer: ComparisonPlayer())
}

extension ProcessingPreset {
    /// All generated versions share one prominent brand tint (system blue ≈ #0080FF),
    /// which also adapts to the user's chosen accent color and to dark mode.
    var tint: Color { .generated }
}

extension Color {
    /// Prominent brand tint reused for every generated version.
    static let generated = Color.accentColor
    /// Positive assessment — on target / low noise.
    static let positive = Color.green
    /// Caution assessment — slightly off / some noise.
    static let caution = Color.orange
    /// Negative assessment — problematic / distracting.
    static let critical = Color.red
}
