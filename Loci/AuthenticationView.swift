import SwiftUI
import GoogleSignIn
import AuthenticationServices

struct AuthenticationView: View {
    @StateObject private var firebaseManager = FirebaseManager.shared
    @State private var authMode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var username = ""
    @State private var showingPasswordReset = false
    @State private var resetEmail = ""
    @State private var showingResetAlert = false
    @State private var resetAlertMessage = ""
    
    enum AuthMode {
        case signIn, signUp
        
        var title: String {
            switch self {
            case .signIn: return "Welcome Back"
            case .signUp: return "Join Loci"
            }
        }
        
        var buttonTitle: String {
            switch self {
            case .signIn: return "Sign In"
            case .signUp: return "Create Account"
            }
        }
        
        var switchPrompt: String {
            switch self {
            case .signIn: return "Don't have an account?"
            case .signUp: return "Already have an account?"
            }
        }
        
        var switchAction: String {
            switch self {
            case .signIn: return "Sign Up"
            case .signUp: return "Sign In"
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color(red: 0.1, green: 0.05, blue: 0.15),
                        Color(red: 0.15, green: 0.1, blue: 0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Animated background elements
                ForEach(0..<20, id: \.self) { i in
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.purple.opacity(0.1),
                                    Color.blue.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: CGFloat.random(in: 20...80))
                        .position(
                            x: CGFloat.random(in: 0...geometry.size.width),
                            y: CGFloat.random(in: 0...geometry.size.height)
                        )
                        .animation(
                            Animation.easeInOut(duration: Double.random(in: 3...8))
                                .repeatForever(autoreverses: true)
                                .delay(Double.random(in: 0...2)),
                            value: UUID()
                        )
                }
                
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer(minLength: 60)
                        
                        // Logo and title
                        VStack(spacing: 16) {
                            // Loci logo
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.purple, Color.blue],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: "music.note.house.fill")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            Text("Loci")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text("Discover music through places")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        // Auth form
                        VStack(spacing: 24) {
                            Text(authMode.title)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                            
                            VStack(spacing: 16) {
                                if authMode == .signUp {
                                    AuthTextField(
                                        title: "Display Name",
                                        text: $displayName,
                                        icon: "person.fill"
                                    )
                                }
                                
                                AuthTextField(
                                    title: "Username",
                                    text: $username,
                                    icon: "at",
                                    keyboardType: .asciiCapable
                                )
                                
                                // Username validation helper text
                                if !username.isEmpty && !isValidUsername(username) {
                                    Text("Username must be 3-20 characters (letters, numbers, underscores only)")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red)
                                        .padding(.horizontal)
                                }
                                
                                AuthTextField(
                                    title: "Email",
                                    text: $email,
                                    icon: "envelope.fill",
                                    keyboardType: .emailAddress
                                )
                                
                                AuthTextField(
                                    title: "Password",
                                    text: $password,
                                    icon: "lock.fill",
                                    isSecure: true
                                )
                                
                                if authMode == .signUp {
                                    AuthTextField(
                                        title: "Confirm Password",
                                        text: $confirmPassword,
                                        icon: "lock.fill",
                                        isSecure: true
                                    )
                                }
                            }
                            
                            // Error message
                            if let errorMessage = firebaseManager.errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            
                            // Auth button
                            Button(action: performAuth) {
                                HStack {
                                    if firebaseManager.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Text(authMode.buttonTitle)
                                            .font(.system(size: 18, weight: .semibold))
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    LinearGradient(
                                        colors: [Color.purple, Color.blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(16)
                            }
                            .disabled(firebaseManager.isLoading || !isFormValid)
                            .opacity(firebaseManager.isLoading || !isFormValid ? 0.6 : 1.0)
                            
                            // Social Sign-In Section (only show if available)
                            if firebaseManager.isGoogleSignInAvailable || firebaseManager.isAppleSignInAvailable {
                                // Divider
                                HStack {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.3))
                                        .frame(height: 1)
                                    
                                    Text("or")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                        .padding(.horizontal, 16)
                                    
                                    Rectangle()
                                        .fill(Color.white.opacity(0.3))
                                        .frame(height: 1)
                                }
                                .padding(.vertical, 8)
                                
                                // Google Sign-In Button
                                if firebaseManager.isGoogleSignInAvailable {
                                    Button(action: signInWithGoogle) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "globe")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundColor(.black)
                                            
                                            Text("Continue with Google")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.black)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 56)
                                        .background(Color.white)
                                        .cornerRadius(16)
                                    }
                                    .disabled(firebaseManager.isLoading)
                                    .opacity(firebaseManager.isLoading ? 0.6 : 1.0)
                                }
                                
                                // Apple Sign-In Button
                                if firebaseManager.isAppleSignInAvailable {
                                    SignInWithAppleButton(
                                        onRequest: { request in
                                            // This will be handled by our custom implementation
                                        },
                                        onCompletion: { result in
                                            // This will be handled by our custom implementation
                                        }
                                    )
                                    .signInWithAppleButtonStyle(.white)
                                    .frame(height: 56)
                                    .cornerRadius(16)
                                    .overlay(
                                        Button(action: signInWithApple) {
                                            Color.clear
                                        }
                                        .disabled(firebaseManager.isLoading)
                                    )
                                    .disabled(firebaseManager.isLoading)
                                    .opacity(firebaseManager.isLoading ? 0.6 : 1.0)
                                }
                            }
                            
                            // Forgot password (sign in only)
                            if authMode == .signIn {
                                Button("Forgot Password?") {
                                    showingPasswordReset = true
                                }
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.blue)
                            }
                            
                            // Switch auth mode
                            HStack {
                                Text(authMode.switchPrompt)
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Button(authMode.switchAction) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        authMode = authMode == .signIn ? .signUp : .signIn
                                        clearForm()
                                    }
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal, 32)
                        
                        Spacer(minLength: 40)
                    }
                }
            }
        }
        .sheet(isPresented: $showingPasswordReset) {
            PasswordResetView(
                email: $resetEmail,
                isPresented: $showingPasswordReset,
                onReset: { email in
                    Task {
                        do {
                            try await firebaseManager.resetPassword(email: email)
                            resetAlertMessage = "Password reset email sent to \(email)"
                            showingResetAlert = true
                        } catch {
                            resetAlertMessage = "Failed to send reset email: \(error.localizedDescription)"
                            showingResetAlert = true
                        }
                    }
                }
            )
        }
        .alert("Password Reset", isPresented: $showingResetAlert) {
            Button("OK") { }
        } message: {
            Text(resetAlertMessage)
        }
    }
    
    private var isFormValid: Bool {
        switch authMode {
        case .signIn:
            return !email.isEmpty && !password.isEmpty
        case .signUp:
            return !email.isEmpty && 
                   !password.isEmpty && 
                   !displayName.isEmpty && 
                   !username.isEmpty &&
                   isValidUsername(username) &&
                   password == confirmPassword &&
                   password.count >= 6
        }
    }
    
    private func isValidUsername(_ username: String) -> Bool {
        // Username should be 3-20 characters, alphanumeric and underscores only
        let regex = "^[a-zA-Z0-9_]{3,20}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
        return predicate.evaluate(with: username)
    }
    
    private func performAuth() {
        Task {
            do {
                switch authMode {
                case .signIn:
                    try await firebaseManager.signIn(email: email, password: password)
                case .signUp:
                    try await firebaseManager.signUp(email: email, password: password, displayName: displayName, username: username)
                }
            } catch {
                // Error is handled by FirebaseManager
            }
        }
    }
    
    private func signInWithGoogle() {
        Task {
            do {
                try await firebaseManager.signInWithGoogle()
            } catch {
                // Error is handled by FirebaseManager
                print("Google Sign-In error: \(error)")
            }
        }
    }
    
    private func signInWithApple() {
        Task {
            do {
                try await firebaseManager.signInWithApple()
            } catch {
                // Error is handled by FirebaseManager
                print("Apple Sign-In error: \(error)")
            }
        }
    }
    
    private func clearForm() {
        email = ""
        password = ""
        confirmPassword = ""
        displayName = ""
        username = ""
        firebaseManager.errorMessage = nil
    }
}

struct AuthTextField: View {
    let title: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 20)
                
                if isSecure {
                    SecureField("", text: $text)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.white)
                } else {
                    TextField("", text: $text)
                        .textFieldStyle(PlainTextFieldStyle())
                        .keyboardType(keyboardType)
                        .autocapitalization(.none)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
}

struct PasswordResetView: View {
    @Binding var email: String
    @Binding var isPresented: Bool
    let onReset: (String) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Reset Password")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("Enter your email address and we'll send you a link to reset your password.")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                AuthTextField(
                    title: "Email",
                    text: $email,
                    icon: "envelope.fill",
                    keyboardType: .emailAddress
                )
                
                Button("Send Reset Email") {
                    onReset(email)
                    isPresented = false
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [Color.purple, Color.blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .disabled(email.isEmpty)
                .opacity(email.isEmpty ? 0.6 : 1.0)
                
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    AuthenticationView()
} 