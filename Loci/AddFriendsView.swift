import SwiftUI
import FirebaseAuth

struct AddFriendsView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var friendsManager = FriendsManager.shared
    @State private var searchText = ""
    @State private var searchResults: [UserProfile] = []
    @State private var isSearching = false
    @State private var selectedSearchType: SearchType = .username
    @State private var errorMessage: String?
    @State private var showingError = false
    
    enum SearchType: String, CaseIterable {
        case username = "Username"
        case email = "Email"
        case displayName = "Name"
        
        var placeholder: String {
            switch self {
            case .username: return "Enter username (e.g., @johndoe)"
            case .email: return "Enter email address"
            case .displayName: return "Enter display name"
            }
        }
        
        var icon: String {
            switch self {
            case .username: return "at"
            case .email: return "envelope.fill"
            case .displayName: return "person.fill"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color(red: 0.1, green: 0.05, blue: 0.15)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search section
                    VStack(spacing: 16) {
                        // Search type selector
                        searchTypeSelector
                        
                        // Search bar
                        searchBar
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Results
                    if isSearching {
                        searchingView
                    } else if searchResults.isEmpty && !searchText.isEmpty {
                        noResultsView
                    } else if !searchResults.isEmpty {
                        resultsView
                    } else {
                        instructionsView
                    }
                }
            }
            .navigationTitle("Add Friends")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .onChange(of: searchText) { newValue in
            searchUsers(query: newValue)
        }
    }
    
    private var searchTypeSelector: some View {
        HStack(spacing: 0) {
            ForEach(SearchType.allCases, id: \.self) { type in
                Button(action: {
                    selectedSearchType = type
                    searchText = ""
                    searchResults = []
                }) {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: type.icon)
                                .font(.system(size: 14, weight: .medium))
                            
                            Text(type.rawValue)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(selectedSearchType == type ? .white : .white.opacity(0.6))
                        
                        Rectangle()
                            .fill(selectedSearchType == type ? Color.blue : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: selectedSearchType.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            
            TextField(selectedSearchType.placeholder, text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .foregroundColor(.white)
                .autocapitalization(.none)
                .keyboardType(selectedSearchType == .email ? .emailAddress : .default)
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    searchResults = []
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var searchingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
            
            Text("Searching...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 50, weight: .light))
                .foregroundColor(.white.opacity(0.3))
            
            VStack(spacing: 8) {
                Text("No Users Found")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Try a different search term or check the spelling")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var instructionsView: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 20) {
                    Image(systemName: "person.2.badge.plus")
                        .font(.system(size: 60, weight: .light))
                        .foregroundColor(.white.opacity(0.3))
                    
                    VStack(spacing: 12) {
                        Text("Find Your Friends")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Search for friends using their username, email, or display name")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
                
                VStack(spacing: 16) {
                    SearchTypeCard(
                        icon: "at",
                        title: "Username",
                        description: "Search by @username (fastest method)",
                        example: "Try: @johndoe"
                    )
                    
                    SearchTypeCard(
                        icon: "envelope.fill",
                        title: "Email",
                        description: "Find friends by their email address",
                        example: "Try: john@example.com"
                    )
                    
                    SearchTypeCard(
                        icon: "person.fill",
                        title: "Display Name",
                        description: "Search by their full name",
                        example: "Try: John Doe"
                    )
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 40)
        }
    }
    
    private var resultsView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(searchResults, id: \.id) { user in
                    UserSearchResultView(user: user)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private func searchUsers(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        // Debounce search to avoid too many requests
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard query == searchText else { return } // Make sure user hasn't changed input
            
            performSearch(query: query)
        }
    }
    
    private func performSearch(query: String) {
        isSearching = true
        errorMessage = nil
        
        Task {
            do {
                let results: [UserProfile]
                
                switch selectedSearchType {
                case .username:
                    if let user = try await friendsManager.searchUsersByUsername(username: query) {
                        results = [user]
                    } else {
                        results = []
                    }
                    
                case .email:
                    if let user = try await friendsManager.searchUsersByEmail(email: query) {
                        results = [user]
                    } else {
                        results = []
                    }
                    
                case .displayName:
                    results = try await friendsManager.searchUsers(query: query)
                }
                
                await MainActor.run {
                    searchResults = results.filter { user in
                        // Filter out current user and existing friends
                        user.id != FirebaseManager.shared.auth.currentUser?.uid &&
                        !friendsManager.isFriend(userId: user.id)
                    }
                    isSearching = false
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isSearching = false
                }
            }
        }
    }
}

struct SearchTypeCard: View {
    let icon: String
    let title: String
    let description: String
    let example: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                
                Text(example)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.blue.opacity(0.8))
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

struct UserSearchResultView: View {
    let user: UserProfile
    @StateObject private var friendsManager = FriendsManager.shared
    @State private var isProcessing = false
    @State private var requestSent = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Profile image
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.8), Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                if let imageURL = user.profileImageURL {
                    AsyncImage(url: URL(string: imageURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Text(String(user.displayName.prefix(1)).uppercased())
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                } else {
                    Text(String(user.displayName.prefix(1)).uppercased())
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("@\(user.username)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Add friend button
            if requestSent {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                    
                    Text("Sent")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.green, lineWidth: 1)
                )
            } else if isProcessing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            } else {
                Button(action: sendFriendRequest) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.blue)
                        )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private func sendFriendRequest() {
        isProcessing = true
        
        Task {
            do {
                try await friendsManager.sendFriendRequest(to: user.id)
                await MainActor.run {
                    requestSent = true
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    print("Error sending friend request: \(error)")
                }
            }
        }
    }
}

