import AVFoundation
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

enum VideoEffectItem: String, CaseIterable, Identifiable, Sendable {
    case none
    case monochrome

    var id: Self { self }

    func makeVideoEffect() -> VideoEffect? {
        switch self {
        case .none:
            return nil
        case .monochrome:
            return MonochromeEffect()
        }
    }
}

struct PublishView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject var preference: PreferenceViewModel
    @StateObject private var model = PublishViewModel()

    var body: some View {
        ZStack {
            ScreenObjectEditingPreview(mixer: model.mixer, gravity: .resizeAspect) {
                MTHKViewRepresentable(previewSource: model)
            }
            VStack(alignment: .trailing) {
                Picker("FPS", selection: $model.currentFPS) {
                    ForEach(FPS.allCases) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .onChange(of: model.currentFPS) { tag in
                    model.setFrameRate(tag.frameRate)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .padding()
                Spacer()
            }
        }
        .onAppear {
            model.startRunning(preference)
        }
        .onDisappear {
            model.stopRunning()
        }
        .navigationTitle("Publish")
        .toolbar {
            switch model.readyState {
            case .connecting:
                ToolbarItem(placement: .primaryAction) {
                }
            case .open:
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        model.stopPublishing()
                    }) {
                        Image(systemName: "stop.circle")
                    }
                }
            case .closed:
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        model.startPublishing(preference)
                    }) {
                        Image(systemName: "record.circle")
                    }
                }
            case .closing:
                ToolbarItem(placement: .primaryAction) {
                }
            }
        }
        .alert(isPresented: $model.isShowError) {
            Alert(
                title: Text("Error"),
                message: Text(model.error?.localizedDescription ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

#Preview {
    PublishView()
}
