import DeezDownKit
import SwiftUI

struct SignInScreen: View {
    @Environment(AppModel.self) private var model
    @State private var arl = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.brand)
                        .symbolRenderingMode(.hierarchical)
                    Text("DeezDown")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .tracking(-0.5)
                    Text("Sign in with your Deezer ARL to browse and download your library.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SecureField("ARL", text: $arl)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($focused)
                        .onSubmit(submit)
                        .frame(width: 380)

                    if case .failed(let reason) = model.signInState {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.failure)
                            .frame(width: 380, alignment: .leading)
                    } else {
                        Text("Find it in your browser cookies for deezer.com as the `arl` value.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 380, alignment: .leading)
                    }
                }

                Button(action: submit) {
                    if model.signInState == .signingIn {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Sign In").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(width: 380)
                .disabled(arl.isEmpty || model.signInState == .signingIn)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focused = true }
    }

    private func submit() {
        let value = arl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        Task { await model.signIn(arl: value) }
    }
}
