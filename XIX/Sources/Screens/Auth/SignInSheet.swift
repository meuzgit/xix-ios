// Sign in with Apple (Build Doc 2 C.4), presented lazily by the action that needs an identity. Debug
// builds add a password account on the local stack so two simulators can play a round.
import AuthenticationServices
import SwiftUI
import XIXData
import XIXModels
import XIXUI

struct SignInSheet: View {
    let reason: String
    @Environment(AppEnvironment.self) private var env
    @State private var nonce = AuthService.makeNonce()
    @State private var busy = false
    @State private var error: String?
    #if DEBUG
    @State private var localName = ""
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sign in").font(.system(size: 30, weight: .black)).foregroundStyle(XIXColor.ink).padding(.horizontal, 20).padding(.top, 28)
            Text(reason).font(XIXType.body(14)).foregroundStyle(XIXColor.muted).padding(.horizontal, 20).padding(.top, 4)
            Text("One tap, nothing to fill in. Your name comes from Apple and you can change it later.").font(XIXType.body(12)).foregroundStyle(XIXColor.muted)
                .padding(.horizontal, 20).padding(.top, 10)
            SignInWithAppleButton(.signIn) { request in
                nonce = AuthService.makeNonce()
                request.requestedScopes = [.fullName]
                request.nonce = nonce.hashed
            } onCompletion: { result in
                Task { await complete(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .padding(.horizontal, 12).padding(.top, 24)
            .disabled(busy)
            #if DEBUG
            if env.backend == .local { localAccount }
            #endif
            if let error { Text(error).font(XIXType.body(12)).foregroundStyle(Color(hex: 0xD8332B)).padding(20) }
            Spacer()
        }
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
    }

    private func complete(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let e):
            if (e as? ASAuthorizationError)?.code != .canceled { error = e.localizedDescription }
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8) else {
                error = "Apple returned no identity token"; return
            }
            let name = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
            busy = true; defer { busy = false }
            do {
                let profile = try await env.auth.signInWithApple(idToken: token, nonce: nonce.raw, displayName: name.isEmpty ? nil : name)
                env.signedIn(profile: profile)
                env.finishSignIn(success: true)
            } catch {
                self.error = "Sign-in failed: \(error.localizedDescription)"
            }
        }
    }

    #if DEBUG
    private var localAccount: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Local stack only · debug")
            Text("A password account on the local Supabase, so two simulators can play one round. Not a product path.")
                .font(XIXType.body(11.5)).foregroundStyle(XIXColor.muted).padding(.horizontal, 20)
            HStack(spacing: 10) {
                TextField("Name", text: $localName).font(XIXType.body(15)).autocorrectionDisabled().accessibilityIdentifier("localName")
                Button(busy ? "…" : "Sign in") { Task { await localSignIn() } }.font(XIXType.body(14, weight: .semibold)).foregroundStyle(XIXColor.green)
                    .disabled(busy || localName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16).frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 14).fill(XIXColor.surface)).padding(.horizontal, 12)
        }
        .padding(.top, 10)
    }

    private func localSignIn() async {
        let name = localName.trimmingCharacters(in: .whitespaces)
        let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
        busy = true; defer { busy = false }
        do {
            let profile = try await env.auth.signInLocally(email: "dev-\(slug)@xix.local", password: "xix-local-dev-\(slug)", displayName: name)
            env.signedIn(profile: profile)
            env.finishSignIn(success: true)
        } catch {
            self.error = "Local sign-in failed: \(error.localizedDescription)"
        }
    }
    #endif
}
