# DivineWall – Hindu God Wallpapers App Architecture

## App Overview
DivineWall is an Android wallpaper app featuring Hindu deity wallpapers with Firebase Authentication (Google Sign-In), role-based access control, and integrated wallpaper management. Admins can upload and manage wallpapers, while users can browse, download, favorite, and set wallpapers directly from the app.

## Tech Stack
- **Frontend**: Flutter (Material 3)
- **Backend**: Firebase (Authentication, Firestore, Storage)
- **State Management**: Provider
- **Ad Integration**: Google AdMob
- **Platform Integration**: Android WallpaperManager API

## Color Scheme (Devotional Theme)
- **Saffron/Orange**: `Color(0xFFFF9933)` - Primary brand color
- **White**: `Color(0xFFFFFFFF)` - Background and text
- **Gold**: `Color(0xFFFFD700)` - Accents and highlights
- **Deep Orange**: `Color(0xFFFF6F00)` - Secondary actions
- **Cream**: `Color(0xFFFFF8DC)` - Card backgrounds (light mode)
- **Dark Brown**: `Color(0xFF3E2723)` - Dark mode surface

## Firebase Data Models

### 1. Users Collection (`users`)
```dart
class UserModel {
  String id;
  String name;
  String email;
  String role; // 'admin' or 'user'
  DateTime createdAt;
  DateTime updatedAt;
}
```

### 2. Categories Collection (`categories`)
```dart
class CategoryModel {
  String id;
  String name;
  String imageUrl;
  int wallpaperCount;
  DateTime createdAt;
  DateTime updatedAt;
}
```

### 3. Wallpapers Collection (`wallpapers`)
```dart
class WallpaperModel {
  String id;
  String categoryId;
  String imageUrl;
  String thumbnailUrl; // Lower resolution for grid
  String uploaderId;
  String uploaderName;
  int downloadCount;
  int favoriteCount;
  DateTime timestamp;
  DateTime updatedAt;
}
```

### 4. Favorites Collection (`favorites`)
```dart
class FavoriteModel {
  String id;
  String userId;
  String wallpaperId;
  DateTime createdAt;
}
```

## File Structure (MVP - 12 files max)

### Core Files (3)
1. `lib/main.dart` - App entry point with Firebase initialization
2. `lib/theme.dart` - Devotional theme with saffron/gold colors
3. `lib/auth_wrapper.dart` - Route based on auth state

### Models (4)
4. `lib/models/user_model.dart`
5. `lib/models/category_model.dart`
6. `lib/models/wallpaper_model.dart`
7. `lib/models/favorite_model.dart`

### Services (3)
8. `lib/services/auth_service.dart` - Firebase Auth + Google Sign-In
9. `lib/services/firestore_service.dart` - All Firestore operations
10. `lib/services/storage_service.dart` - Firebase Storage upload/download
11. `lib/services/wallpaper_service.dart` - Android WallpaperManager integration

### Screens (5)
12. `lib/screens/login_screen.dart` - Google Sign-In UI
13. `lib/screens/home_screen.dart` - Category grid display
14. `lib/screens/gallery_screen.dart` - Wallpaper grid for category
15. `lib/screens/wallpaper_detail_screen.dart` - Full screen preview + actions
16. `lib/screens/admin_panel_screen.dart` - Upload & manage wallpapers

### Widgets (2)
17. `lib/widgets/category_card.dart` - Reusable category display
18. `lib/widgets/wallpaper_grid_item.dart` - Reusable wallpaper thumbnail

### Utils (1)
19. `lib/utils/constants.dart` - AdMob IDs, strings, default categories

## Implementation Steps (Priority Order)

### Phase 1: Firebase Setup & Authentication
1. Setup Firebase project and add configuration files
2. Implement `AuthService` with Google Sign-In
3. Create `UserModel` and Firestore user management
4. Build `LoginScreen` with Google Sign-In button
5. Create `AuthWrapper` to route authenticated users

### Phase 2: Data Models & Services
6. Create `CategoryModel`, `WallpaperModel`, `FavoriteModel`
7. Implement `FirestoreService` for CRUD operations
8. Implement `StorageService` for image upload/download
9. Seed initial categories in Firestore (Shiva, Ganesha, Lakshmi, Vishnu, Hanuman)

### Phase 3: User Interface (Home & Gallery)
10. Update `theme.dart` with saffron/gold devotional colors
11. Build `HomeScreen` with category grid
12. Create `CategoryCard` widget with shimmer loading effect
13. Build `GalleryScreen` with 3-column wallpaper grid
14. Create `WallpaperGridItem` with lazy loading images
15. Add search bar to filter categories/wallpapers

### Phase 4: Wallpaper Detail & Actions
16. Build `WallpaperDetailScreen` with full-screen image preview
17. Implement `WallpaperService` for Android WallpaperManager API
18. Add "Set as Wallpaper" button with bottom-sheet choices (home, lock, both + lock-screen tone)
19. Add "Download" button to save to gallery
20. Add "Favorite" toggle with Firestore sync

#### Wallpaper Apply Modes
- `WallpaperScreenTarget` + `WallpaperColorTone` enums drive both manual apply flow and auto-wallpaper background workers.
- Users always pick Home/Lock/Both; if Lock is involved they can set the lock screen to Normal or Black & White. The same preference is stored in SharedPreferences for the 7-day auto-wallpaper schedule.
- Mobile implementation normalizes EXIF orientation for every download. Home-screen wallpapers reuse the full image (no cropping), while lock-screen variants are center-cropped to the device aspect ratio (and optional grayscale) so the focal point stays aligned when locking; web remains a no-op.
- The Workmanager background dispatcher calls `WidgetsFlutterBinding.ensureInitialized()` and Android registers a Workmanager plugin registrant callback so platform plugins (wallpaper setter, SharedPreferences) remain available even when the device is locked.

### Phase 5: Admin Panel
21. Build `AdminPanelScreen` with role-based access check
22. Implement category creation/deletion UI
23. Add image picker for wallpaper upload
24. Integrate category assignment on upload
25. Add wallpaper deletion functionality

### Phase 6: Additional Features
26. Implement Favorites screen (bottom nav)
27. Add offline caching for recently viewed wallpapers
28. Integrate Google AdMob (banner + interstitial ads)
29. Add dark mode toggle with theme persistence
30. Create splash screen with Om symbol animation

### Phase 7: Testing & Polish
31. Add loading states and error handling
32. Configure Android permissions (INTERNET, SET_WALLPAPER, WRITE_EXTERNAL_STORAGE)
33. Test role-based access control
34. Optimize image loading and caching
35. Run `compile_project` to fix any Dart errors

## Key Technical Decisions

### State Management
- Use Provider for auth state and favorites management
- StreamBuilder for real-time Firestore data

### Image Optimization
- Store thumbnails (300x400) and full-size images separately
- Use cached_network_image for automatic caching
- Lazy load images in grids with pagination

### Wallpaper Setting (Android)
```dart
// Platform channel to Android WallpaperManager
WallpaperManager.setWallpaperFromUrl(imageUrl, WallpaperLocation.homeScreen);
```

### Ad Strategy
- Banner ads: Category page, Gallery page (bottom)
- Interstitial ads: After every 3 category navigations
- No ads in wallpaper detail view for better UX

### Role-Based Access
- Check `user.role == 'admin'` in HomeScreen to show/hide admin button
- Server-side validation in Firestore Security Rules

## Firebase Security Rules
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == userId;
    }
    
    match /categories/{categoryId} {
      allow read: if true;
      allow write: if request.auth != null && 
                     get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }
    
    match /wallpapers/{wallpaperId} {
      allow read: if true;
      allow create: if request.auth != null && 
                      get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
      allow delete: if request.auth != null && 
                      get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }
    
    match /favorites/{favoriteId} {
      allow read: if request.auth != null && request.auth.uid == resource.data.userId;
      allow write: if request.auth != null && request.auth.uid == request.resource.data.userId;
    }
  }
}
```

## MVP Scope Constraints
To stay within 12 files, we're combining:
- All Firestore operations in one service
- Category & wallpaper management in admin panel
- Search functionality integrated in existing screens
- Simple state management without separate provider files

## Next Steps
1. User must connect Firebase project via Dreamflow Firebase panel
2. Implement authentication flow
3. Build UI screens with devotional theme
4. Integrate wallpaper manager
5. Add admin capabilities
6. Test and deploy
