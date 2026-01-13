import AVFoundation
import Charts
import HaishinKit
import SwiftUI

enum FPS: String, CaseIterable, Identifiable {
    case fps15 = "15"
    case fps30 = "30"
    case fps60 = "60"

    var frameRate: Float64 {
        switch self {
        case .fps15:
            return 15
        case .fps30:
            return 30
        case .fps60:
            return 60
        }
    }

    var id: Self { self }
}

private func bitrateQuality(_ kbps: Double) -> String {
    switch kbps {
    case ..<1000: return "Low"
    case 1000..<1500: return "SD"
    case 1500..<2500: return "HD"
    case 2500..<3500: return "High"
    default: return "Ultra"
    }
}

enum VideoEffectItem: String, CaseIterable, Identifiable, Sendable {
    case none
    case monochrome
    case warm
    case vivid

    var id: Self { self }

    var displayName: String {
        switch self {
        case .none: return "Normal"
        case .monochrome: return "B&W"
        case .warm: return "Warm"
        case .vivid: return "Vivid"
        }
    }

    func makeVideoEffect() -> VideoEffect? {
        switch self {
        case .none:
            return nil
        case .monochrome:
            return MonochromeEffect()
        case .warm:
            return WarmEffect()
        case .vivid:
            return VividEffect()
        }
    }
}

struct StreamButton: View {
    let readyState: SessionReadyState
    let onStart: () -> Void
    let onStop: () -> Void

    @State private var isPulsing = false
    @State private var countdown = 3
    @State private var countdownTimer: Timer?

    var body: some View {
        Button(action: {
            switch readyState {
            case .closed:
                onStart()
            case .open:
                onStop()
            default:
                break
            }
        }) {
            ZStack {
                if readyState == .open {
                    Circle()
                        .stroke(Color.red.opacity(0.5), lineWidth: 3)
                        .frame(width: 76, height: 76)
                        .scaleEffect(isPulsing ? 1.2 : 1.0)
                        .opacity(isPulsing ? 0 : 0.8)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                            value: isPulsing
                        )
                }

                Circle()
                    .fill(buttonBackground)
                    .frame(width: 70, height: 70)
                    .shadow(color: shadowColor, radius: 8, x: 0, y: 4)

                VStack(spacing: 2) {
                    switch readyState {
                    case .connecting:
                        Text("\(countdown)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    case .closing:
                        Text("...")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    case .open:
                        Image(systemName: "stop.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        Text("END")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    case .closed:
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        Text("GO LIVE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .disabled(readyState == .connecting || readyState == .closing)
        .onAppear {
            if readyState == .open {
                isPulsing = true
            }
        }
        .onChange(of: readyState) { newState in
            isPulsing = (newState == .open)
            if newState == .connecting {
                startCountdown()
            } else {
                stopCountdown()
            }
        }
        .onDisappear {
            stopCountdown()
        }
    }

    private func startCountdown() {
        countdown = 3
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdown > 1 {
                countdown -= 1
            }
        }
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdown = 3
    }

    private var buttonBackground: LinearGradient {
        switch readyState {
        case .open:
            return LinearGradient(
                colors: [Color.red, Color.red.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .connecting, .closing:
            return LinearGradient(
                colors: [Color.orange, Color.orange.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .closed:
            return LinearGradient(
                colors: [Color.green, Color.green.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var shadowColor: Color {
        switch readyState {
        case .open:
            return Color.red.opacity(0.5)
        case .connecting, .closing:
            return Color.orange.opacity(0.5)
        case .closed:
            return Color.green.opacity(0.5)
        }
    }
}

private func formatDuration(_ duration: TimeInterval) -> String {
    let hours = Int(duration) / 3600
    let minutes = (Int(duration) % 3600) / 60
    let seconds = Int(duration) % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}

private func thermalStateText(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal: return "Cool"
    case .fair: return "Warm"
    case .serious: return "Hot"
    case .critical: return "Critical"
    @unknown default: return "Unknown"
    }
}

private func thermalStateColor(_ state: ProcessInfo.ThermalState) -> Color {
    switch state {
    case .nominal: return .green
    case .fair: return .yellow
    case .serious: return .orange
    case .critical: return .red
    @unknown default: return .white
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color
    var textColor: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color)
            .cornerRadius(4)
    }
}

struct SmallIconButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.3))
                .cornerRadius(22)
        }
    }
}

struct PublishView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject var preference: PreferenceViewModel
    @StateObject private var model = PublishViewModel()
    @State private var showFilterHint = true
    @State private var showFilterChange = false
    @State private var filterChangeId = 0

    var body: some View {
        ZStack {
            VStack {
                switch preference.viewType {
                case .metal:
                    MTHKViewRepresentable(previewSource: model, videoGravity: .resizeAspectFill)
                case .pip:
                    PiPHKViewRepresentable(previewSource: model, videoGravity: .resizeAspectFill)
                }
            }

            if model.isLoading {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("Loading Camera...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }

            if showFilterHint && !model.isLoading {
                VStack(spacing: 10) {
                    VStack(spacing: 8) {
                        HStack(spacing: 16) {
                            Image(systemName: "chevron.left")
                            Text(model.visualEffectItem.displayName)
                                .font(.system(size: 14, weight: .medium))
                            Image(systemName: "chevron.right")
                        }
                        Text("Swipe to change filter")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.35))
                    .cornerRadius(12)
                    HStack(spacing: 6) {
                        ForEach(VideoEffectItem.allCases) { effect in
                            Circle()
                                .fill(effect == model.visualEffectItem ? Color.white : Color.white.opacity(0.4))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .transition(.opacity)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation(.easeOut(duration: 0.5)) {
                            showFilterHint = false
                        }
                    }
                }
            }

            if !showFilterHint {
                VStack(spacing: 10) {
                    Text(model.visualEffectItem.displayName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color.black.opacity(0.35))
                        .cornerRadius(12)
                    HStack(spacing: 6) {
                        ForEach(VideoEffectItem.allCases) { effect in
                            Circle()
                                .fill(effect == model.visualEffectItem ? Color.white : Color.white.opacity(0.4))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .opacity(showFilterChange ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: showFilterChange)
            }

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        if model.readyState == .open {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                Text(formatDuration(model.streamDuration))
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                        }

                        if !model.isLoading {
                            Text("720p")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(4)
                        }

                        if !model.audioSources.isEmpty {
                            Picker("AudioSource", selection: $model.audioSource) {
                                ForEach(model.audioSources, id: \.description) { source in
                                    Text(source.description).tag(source)
                                }
                            }
                            .frame(width: 180)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(8)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 6) {
                            if model.readyState == .open {
                                StatusBadge(text: "LIVE", color: .red)
                            }
                            if model.isRecording {
                                StatusBadge(text: "REC", color: .orange)
                            }
                            if preference.isHDREnabled {
                                StatusBadge(text: "HDR", color: .purple)
                            }
                            if model.isAudioMuted {
                                StatusBadge(text: "MUTED", color: .gray)
                            }
                            if model.isTorchEnabled {
                                StatusBadge(text: "TORCH", color: .yellow, textColor: .black)
                            }
                            if model.visualEffectItem != .none {
                                StatusBadge(text: model.visualEffectItem.displayName.uppercased(), color: .cyan)
                            }
                        }

                        if model.isVolumeOn {
                            Text("Volume up causes echo")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(16)

                Spacer()

                VStack(spacing: 10) {
                    if model.readyState == .open && !model.stats.isEmpty {
                        HStack(spacing: 8) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 9, weight: .bold))
                                Text("\(model.currentUploadKBps)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                Text("KB/s")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.6))
                            }

                            Chart(model.stats) {
                                LineMark(
                                    x: .value("time", $0.date),
                                    y: .value("bytes", $0.currentBytesOutPerSecond)
                                )
                                .foregroundStyle(Color.cyan)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                            }
                            .chartYAxis(.hidden)
                            .chartXAxis(.hidden)
                            .frame(height: 28)

                            HStack(spacing: 3) {
                                Image(systemName: "thermometer.medium")
                                    .font(.system(size: 9))
                                Text(thermalStateText(model.thermalState))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(thermalStateColor(model.thermalState))
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(8)
                    }

                    HStack(spacing: 0) {
                        HStack(spacing: 4) {
                            ForEach(FPS.allCases) { fps in
                                Button(action: {
                                    model.currentFPS = fps
                                    model.setFrameRate(fps.frameRate)
                                }) {
                                    Text(fps.rawValue)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(model.currentFPS == fps ? .white : .white.opacity(0.5))
                                        .frame(width: 44, height: 44)
                                        .background(model.currentFPS == fps ? Color.white.opacity(0.25) : Color.black.opacity(0.3))
                                        .cornerRadius(22)
                                }
                            }
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            SmallIconButton(icon: model.isRecording ? "record.circle.fill" : "record.circle",
                                            color: model.isRecording ? .orange : .white) {
                                model.toggleRecording()
                            }
                            .disabled(model.readyState != .open)
                            .opacity(model.readyState == .open ? 1.0 : 0.4)

                            SmallIconButton(icon: model.isAudioMuted ? "mic.slash.fill" : "mic.fill",
                                            color: model.isAudioMuted ? .red : .white) {
                                model.toggleAudioMuted()
                            }

                            SmallIconButton(icon: "arrow.triangle.2.circlepath.camera",
                                            color: .white) {
                                model.flipCamera()
                            }

                            SmallIconButton(icon: model.isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill",
                                            color: model.isTorchEnabled ? .yellow : .white) {
                                model.toggleTorch()
                            }
                            .disabled(model.currentCamera == "Front")
                            .opacity(model.currentCamera == "Front" ? 0.4 : 1.0)

                            SmallIconButton(icon: model.isDualCameraEnabled ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle",
                                            color: model.isDualCameraEnabled ? .cyan : .white) {
                                model.toggleDualCamera()
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("\(Int(model.videoBitRates))")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white)
                                Text("kbps")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.5))
                                Text("•")
                                    .foregroundColor(.white.opacity(0.3))
                                Text(bitrateQuality(model.videoBitRates))
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.cyan)
                            }
                            Slider(value: $model.videoBitRates, in: 500...4000, step: 100)
                                .tint(.cyan)
                        }

                        StreamButton(
                            readyState: model.readyState,
                            onStart: { model.showPreLiveDialog = true },
                            onStop: { model.stopPublishing() }
                        )
                        .confirmationDialog("Ready to Go Live?", isPresented: $model.showPreLiveDialog, titleVisibility: .visible) {
                            Button("Go Live with Recording") {
                                model.startPublishing(preference, withRecording: true)
                            }
                            Button("Go Live without Recording") {
                                model.startPublishing(preference, withRecording: false)
                            }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("Recording saves a copy of your stream to Photos at \(Int(model.videoBitRates)) kbps.")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.25), .black.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .onAppear {
            model.startRunning(preference)
        }
        .onDisappear {
            model.stopRunning()
        }
        .onChange(of: horizontalSizeClass) { _ in
            model.orientationDidChange()
        }.alert(isPresented: $model.isShowError) {
            Alert(
                title: Text("Error"),
                message: Text(String(describing: model.error)),
                dismissButton: .default(Text("OK"))
            )
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    if abs(value.translation.width) > abs(value.translation.height) {
                        let effects = VideoEffectItem.allCases
                        guard let currentIndex = effects.firstIndex(of: model.visualEffectItem) else { return }
                        let newIndex: Int
                        if value.translation.width < 0 {
                            newIndex = (currentIndex + 1) % effects.count
                        } else {
                            newIndex = (currentIndex - 1 + effects.count) % effects.count
                        }
                        let newEffect = effects[newIndex]
                        model.visualEffectItem = newEffect
                        model.setVisualEffet(newEffect)
                        filterChangeId += 1
                        showFilterChange = true
                        let currentId = filterChangeId
                        Task {
                            try? await Task.sleep(for: .milliseconds(800))
                            if filterChangeId == currentId {
                                showFilterChange = false
                            }
                        }
                    }
                }
        )
    }
}

#Preview {
    PublishView()
}
