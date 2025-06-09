# Loci - Music Discovery Through Places

## Recent Updates

### New Features Added:
1. **Username Support**: Users can now choose unique usernames during sign up
2. **Profile Pictures**: Users can upload and manage profile pictures
3. **Enhanced User Search**: Search by username (@username), name, or email

### Dependencies Required:
- Firebase Core
- Firebase Auth
- Firebase Firestore
- Firebase Storage (NEW - for profile picture uploads)

### Installation Notes:
Add Firebase Storage to your project through Swift Package Manager:
1. In Xcode, go to File > Add Package Dependencies
2. Add: https://github.com/firebase/firebase-ios-sdk
3. Select Firebase Storage from the list

Make sure your Firebase project has Storage enabled and properly configured security rules. 