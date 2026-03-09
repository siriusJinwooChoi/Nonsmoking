# iOS 설정 가이드

이 문서는 금연 앱의 iOS 버전을 설정하는 방법을 안내합니다.

## 필수 설정 단계

### 1. GoogleService-Info.plist 파일 추가

Firebase를 사용하기 위해 `GoogleService-Info.plist` 파일이 필요합니다.

1. [Firebase Console](https://console.firebase.google.com/)에 접속
2. 프로젝트 선택 (nonsmoking-ef941)
3. iOS 앱이 없다면 추가 (Bundle ID: `com.example.nonsmoking`)
4. `GoogleService-Info.plist` 파일 다운로드
5. 파일을 `ios/Runner/` 폴더에 복사

### 2. CocoaPods 의존성 설치

터미널에서 다음 명령어를 실행하세요:

```bash
cd ios
pod install
cd ..
```

### 3. Xcode에서 프로젝트 열기

```bash
open ios/Runner.xcworkspace
```

**중요:** `.xcodeproj`가 아닌 `.xcworkspace` 파일을 열어야 합니다.

### 4. Xcode에서 추가 설정 확인

#### Bundle Identifier 확인
- 프로젝트 선택 → Runner → General 탭
- Bundle Identifier가 `com.example.nonsmoking`인지 확인

#### Signing & Capabilities
- 자동 서명(Automatic signing) 활성화
- 개발팀(Team) 선택

#### Info.plist 확인
- 알림 권한 설명이 추가되어 있는지 확인
- AdMob App ID가 설정되어 있는지 확인

### 5. 알림 권한

앱 실행 시 알림 권한을 요청합니다. iOS 시뮬레이터에서는 알림이 제대로 작동하지 않을 수 있으므로, 실제 기기에서 테스트하는 것을 권장합니다.

## 참고사항

### WorkManager (Android 전용)

이 앱은 Android에서 WorkManager를 사용하여 백그라운드 알림을 처리합니다. iOS에서는 WorkManager를 지원하지 않으므로, 알림은 `flutter_local_notifications`와 `timezone` 패키지를 통해 처리됩니다.

iOS에서도 로컬 알림은 정상적으로 작동하지만, 백그라운드 스케줄링 방식이 Android와 다를 수 있습니다.

### Google Mobile Ads (AdMob)

- AdMob App ID는 `Info.plist`에 이미 설정되어 있습니다: `ca-app-pub-2294312189421130~6391485933`
- 광고 단위 ID는 Dart 코드(`lib/ad_manager.dart`)에서 관리됩니다.

### Firebase

- Firebase 설정은 `lib/firebase_options.dart`에 이미 포함되어 있습니다.
- `GoogleService-Info.plist` 파일만 추가하면 됩니다.

## 빌드 및 실행

### 개발 모드
```bash
flutter run -d ios
```

### 릴리스 빌드
```bash
flutter build ios --release
```

## 문제 해결

### Podfile 관련 오류
```bash
cd ios
rm -rf Pods Podfile.lock
pod install
```

### Xcode 빌드 오류
- Xcode에서 Product → Clean Build Folder
- Flutter clean 실행: `flutter clean`
- 다시 빌드: `flutter pub get && flutter build ios`

### Firebase 관련 오류
- `GoogleService-Info.plist` 파일이 `ios/Runner/` 폴더에 올바르게 있는지 확인
- Firebase Console에서 iOS 앱이 올바른 Bundle ID로 등록되어 있는지 확인



