import SwiftUI
import FirebaseAuth

struct FriendsView: View {
    @StateObject private var friendsManager = FriendsManager.shared
    @State private var selectedTab = 0
    @State private var showingAddFriends = false
    @State private var showingFriendRequests = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
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
                    // Header
                    headerView
                    
                    // Tab selector
                    tabSelector
                    
                    // Content
                    TabView(selection: $selectedTab) {
                        friendsListView
                            .tag(0)
                        
                        friendActivityView
                            .tag(1)
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingAddFriends) {
            AddFriendsView()
        }
        .sheet(isPresented: $showingFriendRequests) {
            FriendRequestsView()
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Friends")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                
                Text("\(friendsManager.friends.count) friends")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                // Friend requests button
                Button(action: { showingFriendRequests = true }) {
                    ZStack {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        
                        if !friendsManager.friendRequests.isEmpty {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 12, y: -12)
                        }
                    }
                }
                
                // Add friends button
                Button(action: { showingAddFriends = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            TabButton(title: "Friends", isSelected: selectedTab == 0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedTab = 0
                }
            }
            
            TabButton(title: "Activity", isSelected: selectedTab == 1) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedTab = 1
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    private var friendsListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if friendsManager.friends.isEmpty {
                    emptyFriendsView
                } else {
                    ForEach(friendsManager.friends) { friend in
                        FriendRowView(friend: friend)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private var friendActivityView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // TODO: Implement friend activity feed
                Text("Friend Activity Coming Soon")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private var emptyFriendsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(.white.opacity(0.3))
                .padding(.top, 60)
            
            VStack(spacing: 12) {
                Text("No Friends Yet")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Add friends to see their music activity and discover new songs together!")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            Button(action: { showingAddFriends = true }) {
                Text("Add Friends")
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
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
        }
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                
                Rectangle()
                    .fill(isSelected ? Color.blue : Color.clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct FriendRowView: View {
    let friend: Friend
    @State private var showingProfile = false
    
    var body: some View {
        Button(action: { showingProfile = true }) {
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
                    
                    if let imageURL = friend.profileImageURL {
                        AsyncImage(url: URL(string: imageURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Text(String(friend.displayName?.prefix(1) ?? "?").uppercased())
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                    } else {
                        Text(String(friend.displayName?.prefix(1) ?? "?").uppercased())
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    // Online indicator
                    if friend.isOnline {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle()
                                    .stroke(Color.black, lineWidth: 2)
                            )
                            .offset(x: 18, y: 18)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.displayName ?? "Friend")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if friend.isOnline {
                        Text("Online now")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.green)
                    } else if let lastSeen = friend.lastSeen {
                        Text("Last seen \(timeAgoString(from: lastSeen))")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    } else {
                        Text("Offline")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
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
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingProfile) {
            FriendProfileView(friend: friend)
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

struct FriendProfileView: View {
    let friend: Friend
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var friendsManager = FriendsManager.shared
    @State private var showingRemoveAlert = false
    
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
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Profile header
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.purple, Color.blue],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 120, height: 120)
                                
                                Text(String(friend.displayName?.prefix(1) ?? "?").uppercased())
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(spacing: 8) {
                                Text(friend.displayName ?? "Friend")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text("Friends since \(DateFormatter.shortDate.string(from: friend.addedAt))")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding(.top, 40)
                        
                        // Actions
                        VStack(spacing: 16) {
                            Button(action: {
                                // TODO: View friend's music activity
                            }) {
                                HStack {
                                    Image(systemName: "music.note")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.blue)
                                    
                                    Text("View Music Activity")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
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
                            
                            Button(action: { showingRemoveAlert = true }) {
                                HStack {
                                    Image(systemName: "person.badge.minus")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.red)
                                    
                                    Text("Remove Friend")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.red)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer(minLength: 40)
                    }
                }
            }
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
        .alert("Remove Friend", isPresented: $showingRemoveAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                Task {
                    do {
                        try await friendsManager.removeFriend(friend)
                        presentationMode.wrappedValue.dismiss()
                    } catch {
                        print("Error removing friend: \(error)")
                    }
                }
            }
        } message: {
            Text("Are you sure you want to remove \(friend.displayName ?? "this friend")? You can always add them back later.")
        }
    }
}

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}

#Preview {
    FriendsView()
} 