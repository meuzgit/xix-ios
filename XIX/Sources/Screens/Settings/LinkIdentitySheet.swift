// "Add another sign-in method": attach Apple or Google (their id token through linkIdentity) or an
// email address (Auth mails a code to the new address; the code confirms it) to the signed-in account.
import AuthenticationServices
import SwiftUI
import XIXData
import XIXUI

struct LinkIdentitySheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var nonce = AuthService.makeNonce()
    @State private var busy = false
    @State private var done: String?
    @State private var error: String?
    @State private var email = ""
    @State private var code = ""
    @State private var codeSentTo: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Add a sign-in method").font(.system(size: 26, weight: .black)).foregroundStyle(XIXColor.ink).padding(.horizontal, 20).padding(.top, 28)
                Text("Same account, one more way in. Handy when Apple gave us a relay address.").font(XIXType.body(13)).foregroundStyle(XIXColor.muted)
                    .padding(.horizontal, 20).padding(.top, 6)
                if let done {
                    Text(done).font(XIXType.body(14, weight: .semibold)).foregroundStyle(XIXColor.green).padding(20)
                    SecondaryButton(title: "Done") { dismiss() }.padding(.horizontal, 12)
                } else {
                    SignInWithAppleButton(.continue) { request in
                        nonce = AuthService.makeNonce()
                        request.requestedScopes = []
                        request.nonce = nonce.hashed
                    } onCompletion: { result in Task { await linkApple(result) } }
                    .signInWithAppleButtonStyle(.black).frame(height: 50).padding(.horizontal, 12).padding(.top, 24).disabled(busy)
                    GoogleButton(title: "Continue with Google") { Task { await linkGoogle() } }.padding(.horizontal, 12).padding(.top, 8).disabled(busy)
                    emailBlock
                }
                if let error { Text(error).font(XIXType.body(12)).foregroundStyle(Color(hex: 0xD8332B)).padding(20) }
                Spacer(minLength: 30)
            }
        }
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
    }

    private var emailBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Or an email address")
            if let to = codeSentTo {
                Text("A code is on its way to \(to).").font(XIXType.body(12)).foregroundStyle(XIXColor.muted).padding(.horizontal, 20)
                HStack(spacing: 10) {
                    TextField("Code from the email", text: $code).font(XIXType.number(17)).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    Button(busy ? "…" : "Verify") { Task { await verifyEmail() } }.font(XIXType.body(14, weight: .semibold)).foregroundStyle(XIXColor.green)
                        .disabled(busy || code.filter(\.isNumber).count < 6)
                }
                .padding(.horizontal, 16).frame(height: 50).background(RoundedRectangle(cornerRadius: 14).fill(XIXColor.surface)).padding(.horizontal, 12)
            } else {
                HStack(spacing: 10) {
                    TextField("Email", text: $email).font(XIXType.body(15)).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(busy ? "…" : "Send code") { Task { await sendEmail() } }.font(XIXType.body(14, weight: .semibold)).foregroundStyle(XIXColor.green)
                        .disabled(busy || !email.contains("@"))
                }
                .padding(.horizontal, 16).frame(height: 50).background(RoundedRectangle(cornerRadius: 14).fill(XIXColor.surface)).padding(.horizontal, 12)
            }
        }
        .padding(.top, 6)
    }

    private func linkApple(_ result: Result<ASAuthorization, Error>) async {
        guard case .success(let auth) = result, let c = auth.credential as? ASAuthorizationAppleIDCredential,
              let data = c.identityToken, let token = String(data: data, encoding: .utf8) else {
            if case .failure(let e) = result, (e as? ASAuthorizationError)?.code != .canceled { error = e.localizedDescription }
            return
        }
        busy = true; defer { busy = false }
        do { try await env.auth.linkApple(idToken: token, nonce: nonce.raw); done = "Apple is attached to this account." }
        catch { self.error = "Could not attach Apple: \(error.localizedDescription)" }
    }

    private func linkGoogle() async {
        busy = true; defer { busy = false }
        do {
            let g = try await GoogleSignInBridge.signIn()
            try await env.auth.linkGoogle(idToken: g.idToken, accessToken: g.accessToken)
            done = "Google is attached to this account."
        } catch { if !GoogleSignInBridge.isCancel(error) { self.error = "Could not attach Google: \(error.localizedDescription)" } }
    }

    private func sendEmail() async {
        busy = true; defer { busy = false }
        do { try await env.auth.requestEmailLink(email: email); codeSentTo = email.trimmingCharacters(in: .whitespaces); error = nil }
        catch { self.error = "Could not send the code: \(error.localizedDescription)" }
    }

    private func verifyEmail() async {
        guard let to = codeSentTo else { return }
        busy = true; defer { busy = false }
        do { try await env.auth.verifyEmailLink(email: to, code: code); done = "\(to) is attached to this account." }
        catch { self.error = "That code did not work: \(error.localizedDescription)" }
    }
}
