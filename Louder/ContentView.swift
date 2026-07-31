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

/// A radial ring of small arrows that all point inward toward the center.
/// Driven by `progress` (0 → 1): at 0 the arrows sit on the outer radius; as
/// progress climbs they slide inward at a constant size, fading in then back
/// out, so a single eased run reads as arrows that appear and move toward the
/// center before disappearing. Only the upper arc is drawn (the bottom three
/// positions are skipped) so the arrows never crowd the wider lower half of the
/// illustration.
private struct DropBeacon: View {
    /// 0 = outer (just appearing), 1 = inner & faded out.
    var progress: CGFloat

    private let count = 8
    // Skip the bottom three slots (bottom-right, bottom, bottom-left) so arrows
    // only beckon from the top and sides.
    private let skipped: Set<Int> = [3, 4, 5]
    // Kept further out and stopped early so even at the end of the run the arrow
    // tips never overlap the illustration inside the ring.
    private let outerRadius: CGFloat = 60
    private let innerRadius: CGFloat = 44

    var body: some View {
        let radius = outerRadius + (innerRadius - outerRadius) * progress
        // Fade in then out across the run so the arrows "appear" and move inward
        // rather than starting at full strength. Size never changes.
        let opacity = sin(Double(progress) * .pi) * 0.55

        ZStack {
            ForEach(0..<count, id: \.self) { i in
                if !skipped.contains(i) {
                    let angle = (CGFloat(i) / CGFloat(count)) * 2 * .pi
                    Image(systemName: "arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        // Rotate each arrow so its "down" direction points at the
                        // center: top→down, right→left, left→right.
                        .rotationEffect(.radians(Double(angle)))
                        .offset(x: radius * sin(angle), y: -radius * cos(angle))
                }
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

struct ContentView: View {
    private static let compareSelection = "compare"

    let queue: DropQueue
    let comparisonPlayer: ComparisonPlayer
    @State private var isTargeted = false
    @State private var hoveredSeriesID: UUID?
    /// Whether the idle screen's compact file options are disclosed. View-local
    /// on purpose: the switches themselves persist, but the screen always opens
    /// in its calm, collapsed form.
    @State private var showFileOptions = false
    /// Which verb of the idle sentence is under the pointer, if any.
    @State private var hoveredDropActionID: String?
    /// Bumped to (re)play the one-shot drop-beacon animation: on appear, when
    /// the app returns to the foreground, and on a window tap in the idle state.
    @State private var beaconTrigger = 0
    @State private var filenameHoveredSeriesID: UUID?
    @State private var selectedVersionID: UUID?
    /// Snapshot of the external toolchain (ffmpeg/ffprobe/Homebrew). Re-checked
    /// on launch and whenever the app returns to the foreground, so installing
    /// the tools in Terminal dismisses the setup card without a relaunch.
    @State private var toolchain: FFmpeg.ToolchainStatus = FFmpeg.status()
    @AppStorage(ProcessingPreset.preferenceKey)
    private var selectedPresetRawValue = ProcessingPreset.persisted.rawValue
    @AppStorage(OutputResolution.preferenceKey)
    private var outputResolutionRawValue = OutputResolution.persisted.rawValue
    // The idle screen surfaces file handling directly. These bind to the same
    // keys as Settings ▸ Files, so both stay in sync.
    @AppStorage(MoveToFolder.preferenceKey) private var moveToFolder = false
    @AppStorage(FilenameOption.preferenceKey)
    private var filenameOptionRaw = FilenameOption.persisted.rawValue
    // Read-only here, but observed so the idle sentence re-renders the moment
    // any of them changes in Settings ▸ Files.
    @AppStorage(TargetFolder.preferenceKey) private var targetFolderPath = ""
    @AppStorage(RelocationMode.preferenceKey)
    private var relocationModeRawValue = RelocationMode.move.rawValue
    @AppStorage(AppendDate.preferenceKey) private var appendDate = false
    // Re-render the assessment cards when the indicator palette is switched or
    // cycled, so .positive / .caution / .critical pick up the new colors.
    @AppStorage(IndicatorPalette.storageKey)
    private var indicatorPaletteID = IndicatorPalette.defaultID

    private var selectedPreset: ProcessingPreset {
        ProcessingPreset.selectable(from: selectedPresetRawValue)
    }

    private var outputResolution: OutputResolution {
        OutputResolution(rawValue: outputResolutionRawValue) ?? .uhd4k
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
        // Hovering a filename focuses that line for the assessment cards and
        // raises it to the top of the graph (via selected styling), but keeps
        // the real, undistorted line view — only the graph itself spreads.
        if let filenameHoveredSeriesID {
            return queue.series.first { $0.id == filenameHoveredSeriesID }
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
        guard let target = series.preset?.targetLUFS else { return .infinity }
        return abs(series.metrics.integratedLUFS - Double(target))
    }

    /// Among the current batch's re-encoded outputs, the smallest file. `nil`
    /// unless at least two outputs were actually re-encoded (so the star marks a
    /// genuine size winner in a Compare batch).
    private var bestSizeSeriesID: UUID? {
        let sized = focusedSourceOutputs.filter {
            $0.metrics.videoReencoded && $0.metrics.outputBytes != nil
        }
        guard sized.count > 1 else { return nil }
        return sized.min { lhs, rhs in
            (lhs.metrics.outputBytes ?? .max) < (rhs.metrics.outputBytes ?? .max)
        }?.id
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
                            fileHandling: .disabled,
                            resolution: outputResolution,
                            stages: StudioBoothStages.all,
                            isReprocessing: true
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
                    // and clean up the previously generated output. Only the audio
                    // artifacts are reversed — any relocation stays in place so the
                    // already-moved/renamed file is reprocessed where it now lives.
                    let source = pristineSourceURL
                    comparisonPlayer.stop()
                    queue.undoOutputForReprocess()
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
            fileHandling: .disabled,
            resolution: outputResolution,
            stages: StudioBoothStages.all,
            isReprocessing: true
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
            .contentShape(Rectangle())
            // Tapping anywhere in the idle window replays the drop beacon.
            .onTapGesture {
                if isInitialState { playDropBeacon() }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
            .onExitCommand {
                if queue.canCancel {
                    queue.cancelProcessing()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                recheckToolchain()
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

            Group {
                if isInitialState && !toolchain.isReady {
                    // Dependencies missing: replace the drop UI with a guided
                    // setup card so the user fixes the toolchain before trying a
                    // drop that would only fail.
                    SetupCardView(status: toolchain, onRecheck: recheckToolchain)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isInitialState {
                    // Idle: keep the picker + quality pair at the window's exact
                    // vertical center by giving the regions above (illustration)
                    // and below (drop hint) equal flexible height.
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            loudnessChart
                        }
                        .frame(maxHeight: .infinity)

                        VStack(spacing: 12) {
                            processingControls
                            outputQualityControl
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 16)

                        // Footer slot: a fixed height sized for its tallest
                        // state (options disclosed plus a two-line hover
                        // detail), so the footer can never squeeze the controls
                        // above it. The summary is pinned to the bottom and the
                        // file options grow upward into the empty space.
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            if showFileOptions {
                                fileOptionsGroup
                                    .transition(.opacity)
                                    .padding(.bottom, 12)
                            }
                            statusDescription
                        }
                        .frame(height: 128, alignment: .bottom)
                    }
                    // Reserve room at the bottom so the two-line hover detail
                    // always clears the dashed drop border. With the footer at a
                    // fixed height, the illustration above absorbs whatever is
                    // left over, which keeps the picker and quality control at a
                    // constant position in every idle state.
                    .padding(.bottom, 40)
                    .offset(y: 44)
                } else {
                    VStack(spacing: 12) {
                        loudnessChart

                        if processingItem != nil {
                            // While processing, keep the filename + progress on top.
                            statusDescription
                            processingControls
                        } else {
                            // Results: the preset picker sits right under the chart,
                            // above the list of generated files.
                            processingControls
                            statusDescription
                        }

                        if let focusedSeries {
                            metrics(for: focusedSeries)
                        }
                    }
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
            // Idle empty state: a ring of small arrows points inward at the app
            // icon's foreground mark. On foreground (or a window tap) the arrows
            // appear and travel toward the center once, beckoning the user to
            // drop a file. A keyframe animator samples the motion each frame so
            // the arrows can fade in then out without changing size.
            ZStack {
                DropBeacon(progress: 1)
                    .keyframeAnimator(initialValue: CGFloat(1), trigger: beaconTrigger) { _, value in
                        DropBeacon(progress: value)
                    } keyframes: { _ in
                        KeyframeTrack {
                            MoveKeyframe(0)
                            CubicKeyframe(1, duration: 0.9)
                        }
                    }
                IconForegroundMark()
                    .frame(width: 58, height: 40)
            }
            .frame(height: 88)
            .padding(.horizontal, 8)
            .onAppear { playDropBeacon() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                playDropBeacon()
            }
        }
        // While processing with no series yet, render nothing so the status and
        // picker stay vertically centered instead of being pushed down by an
        // empty chart placeholder.
    }

    /// Plays the drop-beacon arrows once: each run, the arrows appear at the
    /// outer radius, travel inward at a constant size, and fade out.
    private func playDropBeacon() {
        beaconTrigger += 1
    }

    /// Re-evaluates the external toolchain. Called from the setup card's
    /// Re-check button and on foreground so installing the tools dismisses the
    /// card automatically.
    private func recheckToolchain() {
        toolchain = FFmpeg.status()
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
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(focusedSourceOutputs) { series in
                                fileRow(for: series)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else if let focusedSeries {
                        revealInFinderButton(for: focusedSeries)
                    } else if let completedItem = latestCompletedItem {
                        revealInFinderButton(
                            url: completedItem.url,
                            title: completedItem.url.lastPathComponent,
                            preset: completedItem.preset
                        )
                    } else {
                        dropSummary
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

    // MARK: - Idle drop summary

    /// One verb in the idle sentence, naming a step a dropped file goes
    /// through, with the detail revealed on hover.
    private struct DropAction: Identifiable {
        let id: String
        let verb: String
        let detail: String
        /// Set when the step is switched on but can't run yet, so the sentence
        /// flags it instead of quietly promising something that won't happen.
        var needsAttention = false
    }

    /// The steps a dropped file will actually go through, in reading order.
    /// Steps that are switched off are left out entirely, so the sentence only
    /// ever names what is really going to happen.
    private var dropActions: [DropAction] {
        var actions = [DropAction(id: "encode", verb: "encode", detail: encodeDetail)]
        // Renaming is performed as part of relocation, so it is only promised
        // when the file is being moved or copied somewhere.
        if moveToFolder && filenameOption != .keepFilename {
            actions.append(DropAction(id: "rename", verb: "rename", detail: renameDetail))
        }
        if moveToFolder {
            actions.append(DropAction(
                id: "relocate",
                verb: relocationMode == .move ? "move" : "copy",
                detail: relocateDetail,
                needsAttention: targetFolderPath.isEmpty
            ))
        }
        return actions
    }

    private var relocationMode: RelocationMode {
        RelocationMode(rawValue: relocationModeRawValue) ?? .move
    }

    private var filenameOption: FilenameOption {
        FilenameOption(rawValue: filenameOptionRaw) ?? .keepFilename
    }

    private var filenameOptionSelection: Binding<FilenameOption> {
        Binding(
            get: { filenameOption },
            set: { filenameOptionRaw = $0.rawValue }
        )
    }

    private var encodeDetail: String {
        let cap = outputResolution.label
        return "\(processingPathDescription). Video taller than \(cap) is downscaled to "
            + "\(cap); anything smaller is copied untouched."
    }

    private var renameDetail: String {
        let dateSuffix = appendDate ? " \(AppendDate.formatter.string(from: Date()))" : ""
        return "Names the file “\(filenameOption.renameBody ?? "")\(dateSuffix)”"
    }

    private var relocateDetail: String {
        guard !targetFolderPath.isEmpty else {
            return "No target folder chosen yet — pick one in Settings ▸ Files"
        }
        let folder = (targetFolderPath as NSString).abbreviatingWithTildeInPath
        return relocationMode == .move
            ? "Moves the file into \(folder)"
            : "Copies the file into \(folder), leaving the original where it is"
    }

    /// The idle hint, written as a sentence that names exactly what will happen
    /// to a dropped file. Hovering a verb explains that step underneath.
    private var dropSummary: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                Text("Drop video to ")
                ForEach(Array(dropActions.enumerated()), id: \.element.id) { index, action in
                    Text(joiner(before: index))
                    dropVerb(action)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            // Height is reserved so revealing a detail never nudges the layout.
            // An empty string collapses the reservation, so a space stands in
            // for the resting state.
            Text(dropDetail.isEmpty ? " " : dropDetail)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: 300)
                .animation(.easeInOut(duration: 0.15), value: dropDetail)
        }
    }

    /// Detail line: the hovered step's explanation, blank at rest.
    private var dropDetail: String {
        guard let hoveredDropActionID,
              let action = dropActions.first(where: { $0.id == hoveredDropActionID }) else {
            return ""
        }
        return action.detail
    }

    private func joiner(before index: Int) -> String {
        guard index > 0 else { return "" }
        return index == dropActions.count - 1 ? " and " : ", "
    }

    private func dropVerb(_ action: DropAction) -> some View {
        let isHovered = hoveredDropActionID == action.id
        let tint: Color = action.needsAttention ? .caution : (isHovered ? .accentColor : .primary)
        return Text(action.verb)
            .fontWeight(.medium)
            .foregroundStyle(tint)
            .underline(isHovered, pattern: .dot)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    hoveredDropActionID = action.id
                } else if hoveredDropActionID == action.id {
                    hoveredDropActionID = nil
                }
            }
            .help(action.detail)
            .accessibilityLabel("\(action.verb): \(action.detail)")
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
                comparisonPlayer.toggle(series)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: iconName)
                        .foregroundStyle(iconColor)
                    Text(series.url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
        .fontWeight(isFocused ? .medium : .regular)
        .opacity(isFocused ? 1 : 0.5)
        // Pad the whole row and give it a contiguous hit area so the hover
        // highlight is edge-to-edge with no dead gaps between rows.
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isFocused ? Color.primary.opacity(0.06) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                filenameHoveredSeriesID = series.id
            } else if filenameHoveredSeriesID == series.id {
                filenameHoveredSeriesID = nil
            }
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
            // "Keep Audio" stands apart: it is the only option that leaves the
            // audio alone, so it gets its own section above the enhancements.
            ForEach(ProcessingPreset.pickerCases.filter(\.preservesOriginalAudio)) { preset in
                Label(preset.pickerTitle, systemImage: preset.iconName).tag(preset.rawValue)
            }
            Divider()
            ForEach(ProcessingPreset.enhancementPickerCases) { preset in
                Label(preset.pickerTitle, systemImage: preset.iconName).tag(preset.rawValue)
            }
            Divider()
            Text("Compare").tag(Self.compareSelection)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .disabled(!queue.isIdle)
        // Float the file options toggle just to the right of the (centered)
        // dropdown so it never shifts the dropdown off the window's horizontal
        // center. It is an idle-only affordance; the signal-chain info now
        // lives permanently in the window's toolbar.
        .overlay(alignment: .trailing) {
            if isInitialState {
                fileOptionsButton
                    .offset(x: 28)
            }
        }
    }

    /// Discloses the compact file options on the idle screen. Filled while open
    /// so the button reads as an active toggle rather than a one-shot action.
    private var fileOptionsButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) {
                showFileOptions.toggle()
            }
        } label: {
            Image(systemName: showFileOptions ? "receipt.fill" : "receipt")
                .font(.system(size: 14))
                .foregroundStyle(showFileOptions ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.borderless)
        .help(showFileOptions ? "Hide file options" : "Show file options")
        .accessibilityLabel("File options")
        .accessibilityValue(showFileOptions ? "Shown" : "Hidden")
        .accessibilityHint("Shows the move and rename options applied to dropped files")
    }

    /// The compact file handling controls exposed on the idle screen.
    private var fileOptionsGroup: some View {
        VStack(spacing: 0) {
            fileOptionCell(
                "Move to target folder",
                systemImage: "arrow.forward.folder",
                isOn: $moveToFolder,
                help: "Relocates each dropped file into the target folder chosen in Settings ▸ Files."
            )
            Divider()
                .padding(.leading, 34)
            HStack(spacing: 8) {
                Label("Filename", systemImage: "character.cursor.ibeam")
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Picker("Filename", selection: filenameOptionSelection) {
                    ForEach(FilenameOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .help("Sets the filename convention used when relocating dropped files.")
        }
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 0.5)
        )
        .frame(width: 260)
    }

    private func fileOptionCell(
        _ title: String,
        systemImage: String,
        isOn: Binding<Bool>,
        help: String
    ) -> some View {
        // Built as an explicit row so both cells share one leading text column
        // and one trailing switch column, instead of each hugging its own width.
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .help(help)
    }


    /// True before any file has been processed — the idle drop screen. The
    /// output-quality control only appears here so it reads as a global setting.
    private var isInitialState: Bool {
        queue.series.isEmpty && queue.isIdle && processingItem == nil
    }

    private var outputQualityControl: some View {
        Picker("Output quality", selection: Binding(
            get: { outputResolution },
            set: { outputResolutionRawValue = $0.rawValue }
        )) {
            ForEach(OutputResolution.allCases) { resolution in
                Text(resolution.label).tag(resolution)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .fixedSize()
        .help("Maximum output resolution. Recordings above the cap are downscaled and re-encoded to H.264; anything at or below it is copied untouched.")
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
        // Reading the palette id here registers a SwiftUI dependency, and the
        // .id() below forces the cards to rebuild with the new .positive /
        // .caution / .critical colors whenever the palette is switched or cycled.
        let paletteID = indicatorPaletteID
        return HStack(spacing: 8) {
            metricCard(
                title: "Loud",
                value: loudnessSummary(for: series),
                detail: loudnessAssessment(for: series),
                tint: loudnessTint(for: series),
                isBest: series.id == bestLoudnessSeriesID,
                help: "Perceived loudness versus the original. Roughly every 10 LU doubles or halves how loud it sounds, so the percentage reflects the audible change, not the raw level."
            )
            metricCard(
                title: isolationTitle(for: series),
                value: isolationSummary(for: series),
                detail: isolationDetail(for: series),
                tint: isolationTint(for: series),
                isBest: series.id == bestNoiseSeriesID,
                help: "How much of the prepared audio the isolation model removed as non-voice sound — background, hiss, the tail of a room — measured by comparing the audio just before and after the model ran. A higher figure means the model did more work; it isn't a voice-quality score. The note adds the change in background noise versus the original where there are enough quiet gaps to estimate it."
            )
            trimmedCard(for: series)
            sizeCard(for: series)
        }
        .fixedSize(horizontal: false, vertical: true)
        .id(paletteID)
    }

    /// Shown only when the video stream was actually re-encoded (downscale to the
    /// chosen quality, or a trim re-encode), reporting the file-size change.
    @ViewBuilder
    private func sizeCard(for series: LoudnessSeries) -> some View {
        if series.metrics.videoReencoded,
           let originalBytes = series.metrics.originalBytes,
           let outputBytes = series.metrics.outputBytes {
            let formatter = ByteCountFormatter()
            let before = formatter.string(fromByteCount: originalBytes)
            let after = formatter.string(fromByteCount: outputBytes)
            let delta = outputBytes - originalBytes
            let shrank = delta < 0
            metricCard(
                title: "Size",
                value: "\(before) → \(after)",
                detail: sizeDetail(for: series, delta: delta, shrank: shrank),
                tint: shrank ? .positive : .secondary,
                isBest: series.id == bestSizeSeriesID,
                help: "How the output file size compares to the original. Shown only when the video was re-encoded — downscaled to the chosen output quality or re-encoded for a silence trim. Files at or below the quality cap are copied untouched and have no size change."
            )
        }
    }

    private func sizeDetail(for series: LoudnessSeries, delta: Int64, shrank: Bool) -> String {
        guard let original = series.metrics.originalBytes, original > 0 else {
            return shrank ? "Smaller after re-encode" : "Re-encoded"
        }
        let percent = abs(Double(delta) / Double(original) * 100)
        if percent < 0.5 {
            return "About the same after re-encode"
        }
        let rounded = Int(percent.rounded())
        return shrank ? "\(rounded)% smaller after re-encode" : "\(rounded)% larger after re-encode"
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
                // Reserve two lines so cards keep a constant height whether the
                // value wraps or not, so the layout doesn't jump between files.
                .lineLimit(2, reservesSpace: true)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .help(help)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // Block drops until the toolchain is ready; the setup card stays up and
        // a re-check reflects anything just installed.
        guard toolchain.isReady else {
            recheckToolchain()
            return false
        }
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
                        fileHandling: FileHandling.persisted,
                        resolution: outputResolution,
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
        if hoveredSeriesID == series.id || filenameHoveredSeriesID == series.id
            || comparisonPlayer.activeSeriesID == series.id {
            return series.displayName
        }
        guard let preset = series.preset else { return "Original recording" }
        guard let target = preset.targetLUFS else { return "Kept as recorded" }
        let distance = series.metrics.integratedLUFS - Double(target)
        if abs(distance) <= 1 {
            return "On target"
        }
        return distance < 0 ? "Below target" : "Above target"
    }

    private func loudnessTint(for series: LoudnessSeries) -> Color {
        guard let target = series.preset?.targetLUFS else { return .secondary }
        let distance = abs(series.metrics.integratedLUFS - Double(target))
        // On target is a positive result; a little off is a caution; badly off
        // target (loudnorm couldn't reach it) is a genuine negative outcome.
        if distance <= 1 { return .positive }
        if distance <= 3 { return .caution }
        return .critical
    }

    private func isolationTitle(for series: LoudnessSeries) -> String {
        "Noise"
    }

    private func isolationSummary(for series: LoudnessSeries) -> String {
        if series.isOriginal { return "Untouched" }
        guard series.preset?.isolationLabel != nil else { return "No isolation" }
        guard let removal = series.metrics.isolationRemoval else { return "—" }
        let percent = removal * 100
        if percent < 1 { return "<1% removed" }
        return "≈\(percentString(percent)) removed"
    }

    private func isolationDetail(for series: LoudnessSeries) -> String {
        if series.isOriginal { return "Original recording" }
        // Prefer the concrete background-noise change versus the original when we
        // could estimate it; otherwise describe the magnitude of the cleanup.
        if let snr = series.metrics.estimatedSNR,
           let originalSNR = matchingOriginal?.metrics.estimatedSNR {
            let change = snr - originalSNR
            if abs(change) <= 0.5 {
                return "About as noisy as the original"
            }
            let percent = abs(perceivedPercent(fromDecibels: -change))
            return "≈\(percentString(percent)) \(change > 0 ? "less" : "more") background noise"
        }
        guard let removal = series.metrics.isolationRemoval else {
            return "Cleaned non-voice sound"
        }
        // Removed non-voice content is low-energy even when clearly audible (a
        // noise floor ~20 dB down is only ~1% of the energy), so these buckets
        // are scaled to that reality rather than to a flat percentage.
        switch removal {
        case 0.10...: return "Heavy cleanup"
        case 0.04..<0.10: return "Moderate cleanup"
        case 0.01..<0.04: return "Light cleanup"
        default: return "Light touch — source was clean"
        }
    }

    private func isolationTint(for series: LoudnessSeries) -> Color {
        if series.isOriginal { return .secondary }
        // The raw amount removed isn't inherently good or bad. But when we can
        // estimate it, a measurable drop in background noise versus the original
        // is a genuinely positive outcome (green); an increase is a caution.
        // Without a reliable estimate, stay neutral.
        if let snr = series.metrics.estimatedSNR,
           let originalSNR = matchingOriginal?.metrics.estimatedSNR {
            let change = snr - originalSNR
            if change > 0.5 { return .positive }
            if change < -2 { return .critical }
            if change < -0.5 { return .caution }
        }
        return .secondary
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

// Semantic indicator colors (.positive / .caution / .critical) live in
// IndicatorPalette.swift, where they resolve from the selected OKLCH palette.
