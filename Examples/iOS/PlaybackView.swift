import AVFoundation
import HaishinKit
import SwiftUI

struct PlaybackView: View {
    @EnvironmentObject var preference: PreferenceViewModel
    @StateObject private var model = PlaybackViewModel()

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

            VStack {
                Spacer()

                if model.hasError {
                    VStack(spacing: 16) {
                        Image(systemName: "tv.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.7))

                        Text("Can't connect to stream")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text(model.friendlyErrorMessage)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Button(action: {
                            model.dismissError()
                        }) {
                            Text("Try Again")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(16)
                }

                Spacer()

                HStack {
                    Spacer()
                    switch model.readyState {
                    case .connecting:
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                            .frame(width: 64, height: 64)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(32)
                            .padding(16)
                    case .open:
                        Button(action: {
                            Task {
                                await model.stop()
                            }
                        }) {
                            Image(systemName: "stop.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 24))
                        }
                        .frame(width: 64, height: 64)
                        .background(Color.red)
                        .cornerRadius(32)
                        .padding(16)
                    case .closed, .closing:
                        if !model.hasError {
                            Button(action: {
                                Task {
                                    await model.start()
                                }
                            }) {
                                Image(systemName: "play.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 24))
                            }
                            .frame(width: 64, height: 64)
                            .background(Color.blue)
                            .cornerRadius(32)
                            .padding(16)
                        }
                    }
                }
            }
        }
        .background(Color.black)
        .task {
            await model.makeSession()
        }
    }
}

#Preview {
    PlaybackView()
}
