import DeezDownKit
import SwiftUI

struct SignInScreen: View {
    @Environment(AppModel.self) private var model
    @State private var method: SignInPage.Method?
    @State private var showsARL = false
    @State private var arl = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.brand)
                    .symbolRenderingMode(.hierarchical)
                Text("DeezDown")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .tracking(-0.5)
                Text("Sign in with your Deezer account to browse and download your library.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button { method = .email } label: {
                    Label("Continue with Email", systemImage: "envelope.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { method = .google } label: {
                    Label("Continue with Google", systemImage: "g.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)

            if showsARL {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("ARL", text: $arl)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($focused)
                        .onSubmit(submitARL)
                        .onAppear { focused = true }
                    Text("Find it in your browser cookies for deezer.com as the `arl` value.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Button("Sign in with an ARL instead") { showsARL = true }
                    .buttonStyle(.link)
                    .foregroundStyle(.brand)
            }

            status.frame(minHeight: 16)
        }
        .disabled(model.signInState == .signingIn)
        .frame(width: 340)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $method) { WebSignInSheet(method: $0) }
    }

    @ViewBuilder
    private var status: some View {
        switch model.signInState {
        case .signingIn:
            ProgressView().controlSize(.small)
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.failure)
        default:
            EmptyView()
        }
    }

    private func submitARL() {
        let value = arl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        Task { await model.signIn(arl: value) }
    }
}

private struct WebSignInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let method: SignInPage.Method

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(SignInPage.title).font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            SignInWebView(method: method) { arl in
                dismiss()
                Task { await model.signIn(arl: arl) }
            }
            .frame(width: SignInPage.size.width, height: SignInPage.size.height)
        }
    }
}

private struct SignInWebView: NSViewRepresentable {
    let method: SignInPage.Method
    let onARL: (String) -> Void

    func makeNSView(context: Context) -> SignInPage { SignInPage(method, onARL: onARL) }
    func updateNSView(_ page: SignInPage, context: Context) {}
}
