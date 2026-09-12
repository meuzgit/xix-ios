// Sign in (Build Doc 2 C.4, step 1 amendment): Apple first, then Google, then an email one-time code.
// Presented lazily by the action that needs an identity. No passwords, no magic links. Debug builds
// add a password account on the local stack so two simulators can play a round.
import AuthenticationServices
import GoogleSignIn
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
    @State private var email = ""
    @State private var name = ""
    @State private var code = ""
    @State private var codeSentTo: String?
    #if DEBUG
    @State private var localName = ""
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Sign in").font(.system(size: 30, weight: .black)).foregroundStyle(XIXColor.ink).padding(.horizontal, 20).padding(.top, 28)
                Text(reason).font(XIXType.body(14)).foregroundStyle(XIXColor.muted).padding(.horizontal, 20).padding(.top, 4)
                Text("Nothing to fill in beyond a name. No passwords.").font(XIXType.body(12)).foregroundStyle(XIXColor.muted)
                    .padding(.horizontal, 20).padding(.top, 10)

                SignInWithAppleButton(.signIn) { request in
                    nonce = AuthService.makeNonce()
                    request.requestedScopes = [.fullName]
                    request.nonce = nonce.hashed
                } onCompletion: { result in Task { await completeApple(result) } }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.horizontal, 12).padding(.top, 24)
                .disabled(busy)
                .accessibilityIdentifier("signInApple")

                GoogleButton(title: "Continue with Google") { Task { await google() } }
                    .padding(.horizontal, 12).padding(.top, 8)
                    .disabled(busy)

                emailCode
                #if DEBUG
                if env.backend == .local { localAccount }
                #endif
                if let error { Text(error).font(XIXType.body(12)).foregroundStyle(Color(hex: 0xD8332B)).padding(20) }
                Spacer(minLength: 30)
            }
        }
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
    }

    // MARK: Email one-time code

    private var emailCode: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Or an email code")
            if let to = codeSentTo {
                Text("A code is on its way to \(to). It expires in an hour.").font(XIXType.body(12)).foregroundStyle(XIXColor.muted).padding(.horizontal, 20)
                HStack(spacing: 10) {
                    TextField("Code from the email", text: $code).font(XIXType.number(17)).keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .accessibilityIdentifier("emailCode")
                    Button(busy ? "…" : "Verify") { Task { await verify() } }.font(XIXType.body(14, weight: .semibold)).foregroundStyle(XIXColor.green)
                        .disabled(busy || code.filter(\.isNumber).count < 6)
                }
                .padding(.horizontal, 16).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14).fill(XIXColor.surface)).padding(.horizontal, 12)
                Button("Use a different address") { codeSentTo = nil; code = "" }.font(XIXType.body(12)).foregroundStyle(XIXColor.muted).padding(.horizontal, 20)
            } else {
                TextField("Your name, as it shows on the card", text: $name).font(XIXType.body(15)).textContentType(.name).autocorrectionDisabled()
                    .accessibilityIdentifier("emailName")
                    .padding(.horizontal, 16).frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14).fill(XIXColor.surface)).padding(.horizontal, 12)
                HStack(spacing: 10) {
                    TextField("Email", text: $email).font(XIXType.body(15)).keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("emailField")
                    Button(busy ? "…" : "Send code") { Task { await send() } }.font(XIXType.body(14, weight: .semibold)).foregroundStyle(XIXColor.green)
                        .disabled(busy || !email.contains("@") || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 16).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14).fill(XIXColor.surface)).padding(.horizontal, 12)
            }
        }
        .padding(.top, 6)
    }

    private func send() async {
        busy = true; defer { busy = false }
        do { try await env.auth.sendEmailCode(email: email); codeSentTo = email.trimmingCharacters(in: .whitespaces); error = nil }
        catch { self.error = "Could not send the code: \(error.localizedDescription)" }
    }

    private func verify() async {
        guard let to = codeSentTo else { return }
        busy = true; defer { busy = false }
        do {
            let profile = try await env.auth.verifyEmailCode(email: to, code: code, displayName: name.trimmingCharacters(in: .whitespaces))
            env.signedIn(profile: profile); env.finishSignIn(success: true)
        } catch { self.error = "That code did not work: \(error.localizedDescription)" }
    }

    // MARK: Apple

    private func completeApple(_ result: Result<ASAuthorization, Error>) async {
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
                env.signedIn(profile: profile); env.finishSignIn(success: true)
            } catch { self.error = "Sign-in failed: \(error.localizedDescription)" }
        }
    }

    // MARK: Google

    private func google() async {
        busy = true; defer { busy = false }
        do {
            let g = try await GoogleSignInBridge.signIn()
            let profile = try await env.auth.signInWithGoogle(idToken: g.idToken, accessToken: g.accessToken, displayName: g.name)
            env.signedIn(profile: profile); env.finishSignIn(success: true)
        } catch {
            if !GoogleSignInBridge.isCancel(error) { self.error = "Google sign-in failed: \(error.localizedDescription)" }
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
            env.signedIn(profile: profile); env.finishSignIn(success: true)
        } catch { self.error = "Local sign-in failed: \(error.localizedDescription)" }
    }
    #endif
}

/// The Google button in the system's weight: white, hairline, the G mark drawn by the SDK is not bundled, so a plain label.
struct GoogleButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("G").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(XIXColor.ink)
                Text(title).font(XIXType.body(16, weight: .semibold)).foregroundStyle(XIXColor.ink)
            }
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(Capsule().fill(XIXColor.sheet).overlay(Capsule().strokeBorder(XIXColor.ink, lineWidth: 1)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("signInGoogle")
    }
}

/// The native Google Sign-In SDK, presented from the key window; returns the tokens Supabase exchanges.
enum GoogleSignInBridge {
    struct Tokens { let idToken: String; let accessToken: String?; let name: String? }

    @MainActor
    static func signIn() async throws -> Tokens {
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else {
            throw NSError(domain: "xix.google", code: 1, userInfo: [NSLocalizedDescriptionKey: "no window to present from"])
        }
        var top = root
        while let p = top.presentedViewController { top = p }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: top)
        guard let idToken = result.user.idToken?.tokenString else {
            throw NSError(domain: "xix.google", code: 2, userInfo: [NSLocalizedDescriptionKey: "Google returned no identity token"])
        }
        return Tokens(idToken: idToken, accessToken: result.user.accessToken.tokenString, name: result.user.profile?.name)
    }

    static func isCancel(_ error: Error) -> Bool { (error as NSError).code == GIDSignInError.canceled.rawValue && (error as NSError).domain == "com.google.GIDSignIn" }

    static func handle(_ url: URL) -> Bool { GIDSignIn.sharedInstance.handle(url) }
}
