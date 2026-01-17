import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "circle.grid.3x3.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.primary)

                Text("Abacus")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Issue tracking for beads")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 16) {
                Button {
                    signInWithGitHub()
                } label: {
                    HStack {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                        Text("Sign in with GitHub")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.primary)
                    .foregroundStyle(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isLoading)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    private func signInWithGitHub() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authManager.signInWithGitHub()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager.shared)
}
