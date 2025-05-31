import SwiftUI

struct AddFriendsView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var friendsManager = FriendsManager.shared
    @State private var searchText = ""
    @State private var searchResults: [UserProfile] = []
    @State private var isSearching = false
    @State private var selectedSearchType = SearchType.displayName
    
    enum SearchType: String, CaseIterable {
        case displayName = "Name"
        case email = "Email"
        
        var placeholder: String {
            switch self {
            case .displayName: return "Search by name..."
            case .email: return "Search by email..."
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
                    searchSection
                    
                    // Results
                    if isSearching {
                        loadingView
                    } else if searchResults.isEmpty && !searchText.isEmpty {
                        emptyResultsView
                    } else if !searchResults.isEmpty {
                        resultsView
                    } else {
                        instructionsView
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("Add Friends")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .onChange(of: searchText) { newValue in
            performSearch(query: newValue)
        }
    }
    
    private var searchSection: some View {
        VStack(spacing: 16) {
            // Search type picker
            Picker("Search Type", selection: $selectedSearchType) {
                ForEach(SearchType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, 20)
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.6))
                
                TextField(selectedSearchType.placeholder, text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(.white)
                    .autocapitalization(selectedSearchType == .email ? .none : .words)
                    .keyboardType(selectedSearchType == .email ? .emailAddress : .default)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
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
            .padding(.horizontal, 20)
        }
        .padding(.top, 20)
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
            
            Text("Searching...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.top, 60)
    }
    
    private var emptyResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.white.opacity(0.3))
            
            Text("No users found")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Try searching with a different \(selectedSearchType.rawValue.lowercased())")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .padding(.horizontal, 40)
    }
    
    private var resultsView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(searchResults) { user in
                    UserSearchResultView(user: user)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private var instructionsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(.white.opacity(0.3))
            
            VStack(spacing: 12) {
                Text("Find Friends")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Search for friends by their name or email address to connect and share music discoveries!")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.top, 80)
    }
    
    private func performSearch(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        guard query.count >= 2 else { return }
        
        isSearching = true
        
        Task {
            do {
                let results: [UserProfile]
                
                switch selectedSearchType {
                case .displayName:
                    results = try await friendsManager.searchUsers(query: query)
                case .email:
                    if let user = try await friendsManager.searchUsersByEmail(email: query) {
                        results = [user]
                    } else {
                        results = []
                    }
                }
                
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.searchResults = []
                    self.isSearching = false
                    print("Search error: \(error)")
                }
            }
        }
    }
}

struct UserSearchResultView: View {
    let user: UserProfile
    @StateObject private var friendsManager = FriendsManager.shared
    @State private var requestStatus: RequestStatus = .none
    @State private var isLoading = false
    
    enum RequestStatus {
        case none
        case sending
        case sent
        case alreadyFriends
        case error(String)
    }
    
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
                
                Text(user.email)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                
                Text("Joined \(DateFormatter.shortDate.string(from: user.joinedDate))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            // Action button
            actionButton
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
        .onAppear {
            checkFriendshipStatus()
        }
    }
    
    @ViewBuilder
    private var actionButton: some View {
        switch requestStatus {
        case .none:
            Button(action: sendFriendRequest) {
                Text("Add")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color.purple, Color.blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(20)
            }
            .disabled(isLoading)
            
        case .sending:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.8)
            
        case .sent:
            Text("Sent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.green)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.green, lineWidth: 1)
                )
            
        case .alreadyFriends:
            Text("Friends")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.blue, lineWidth: 1)
                )
            
        case .error(let message):
            Button(action: sendFriendRequest) {
                Text("Retry")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.red, lineWidth: 1)
                    )
            }
        }
    }
    
    private func checkFriendshipStatus() {
        if friendsManager.isFriend(userId: user.id) {
            requestStatus = .alreadyFriends
        }
    }
    
    private func sendFriendRequest() {
        requestStatus = .sending
        isLoading = true
        
        Task {
            do {
                try await friendsManager.sendFriendRequest(to: user.id)
                await MainActor.run {
                    requestStatus = .sent
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    requestStatus = .error(error.localizedDescription)
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    AddFriendsView()
} 