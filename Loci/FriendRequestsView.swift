import SwiftUI

struct FriendRequestsView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var friendsManager = FriendsManager.shared
    @State private var selectedTab = 0
    
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
                    // Tab selector
                    tabSelector
                    
                    // Content
                    TabView(selection: $selectedTab) {
                        incomingRequestsView
                            .tag(0)
                        
                        sentRequestsView
                            .tag(1)
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                }
            }
            .navigationTitle("Friend Requests")
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
    }
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            TabButton(
                title: "Received (\(friendsManager.friendRequests.count))",
                isSelected: selectedTab == 0
            ) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedTab = 0
                }
            }
            
            TabButton(
                title: "Sent (\(friendsManager.sentRequests.count))",
                isSelected: selectedTab == 1
            ) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedTab = 1
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    private var incomingRequestsView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if friendsManager.friendRequests.isEmpty {
                    emptyIncomingView
                } else {
                    ForEach(friendsManager.friendRequests) { request in
                        IncomingRequestView(request: request)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private var sentRequestsView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if friendsManager.sentRequests.isEmpty {
                    emptySentView
                } else {
                    ForEach(friendsManager.sentRequests) { request in
                        SentRequestView(request: request)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private var emptyIncomingView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(.white.opacity(0.3))
                .padding(.top, 60)
            
            VStack(spacing: 12) {
                Text("No Friend Requests")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("When someone sends you a friend request, it will appear here.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
    }
    
    private var emptySentView: some View {
        VStack(spacing: 24) {
            Image(systemName: "paperplane")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(.white.opacity(0.3))
                .padding(.top, 60)
            
            VStack(spacing: 12) {
                Text("No Sent Requests")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Friend requests you send will appear here until they're accepted or declined.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
    }
}

struct IncomingRequestView: View {
    let request: FriendRequest
    @StateObject private var friendsManager = FriendsManager.shared
    @State private var isProcessing = false
    
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
                
                if let imageURL = request.fromUserImageURL {
                    AsyncImage(url: URL(string: imageURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Text(String(request.fromUserName?.prefix(1) ?? "?").uppercased())
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                } else {
                    Text(String(request.fromUserName?.prefix(1) ?? "?").uppercased())
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(request.fromUserName ?? "Unknown User")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Sent \(timeAgoString(from: request.createdAt))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Action buttons
            if isProcessing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            } else {
                HStack(spacing: 8) {
                    // Decline button
                    Button(action: declineRequest) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color.red.opacity(0.2))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.red, lineWidth: 1)
                                    )
                            )
                    }
                    
                    // Accept button
                    Button(action: acceptRequest) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color.green.opacity(0.2))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.green, lineWidth: 1)
                                    )
                            )
                    }
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
    
    private func acceptRequest() {
        isProcessing = true
        
        Task {
            do {
                try await friendsManager.acceptFriendRequest(request)
                await MainActor.run {
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    print("Error accepting request: \(error)")
                }
            }
        }
    }
    
    private func declineRequest() {
        isProcessing = true
        
        Task {
            do {
                try await friendsManager.declineFriendRequest(request)
                await MainActor.run {
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    print("Error declining request: \(error)")
                }
            }
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

struct SentRequestView: View {
    let request: FriendRequest
    
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
                
                Text("?")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Friend Request")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Sent \(timeAgoString(from: request.createdAt))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Status
            Text("Pending")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange, lineWidth: 1)
                )
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

#Preview {
    FriendRequestsView()
} 