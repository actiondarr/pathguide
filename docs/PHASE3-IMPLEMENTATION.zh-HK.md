# 第三階段 Google 登入及緊急聯絡人接入

日期：2026 年 10 月 23 日。程式及本機測試已加入，後續已接通測試專案 pathguide-dev；使用者回報帳號及聯絡人真機流程完成。完整階段安排見 [新版開發階段](IMPLEMENTATION-ROADMAP.zh-HK.md)。

## 1 本輪功能

- 訪客辨識保留；首頁、設定及辨識「更多操作」可進入帳號頁。
- Google 登入、SDK 身分恢復、可重試初始化、登出及重新驗證刪除。
- 登入後選填一位聯絡人，可跳過，並可新增、修改、刪除及啟動系統撥號。
- Firebase UID、同帳號安全快取、延遲回應保護；編輯中切換帳號不繼續顯示舊聯絡資料。
- 私人聯絡資料與照片／訓練用途分離；本輪沒有照片收集、上傳或訓練。

未配置 Firebase 時顯示尚未配置，Google 按鈕停用；沒有假登入、測試使用者或虛構雲端成功狀態。舊 `firebaseCode-2` 原型及其中的管理員檔案不載入 App。

## 2 組員設定 Firebase

1. 在 Firebase Console 以自己的 Google 帳戶建立全組共用開發專案。先使用 Spark；Analytics 不是本輪必需。
2. 設定專案協作權限，組員以各自帳戶登入。移交專案管理權不等於移交付款帳戶。
3. Authentication 啟用 Google provider，填妥支援電郵。
4. 註冊 iOS App，bundle ID 使用 `hk.pathguide.pathguide`；若因簽署需改 ID，Xcode、Firebase 註冊及下方指令的 ID 必須一致。
5. 建立 Firestore Standard 資料庫，與組員確認地區。不要使用對所有人開放的測試規則。
6. Google provider 啟用後重新下載 `GoogleService-Info.plist`。這是手機端設定，不是管理員 service-account 私鑰。
7. 覆核 `backend/firestore.rules` 後部署到指定開發專案；現有專案其他資料的規則須先由 backend 組員整合，不能直接覆蓋而不檢查。

在 `app/` 執行：

```sh
python3 tool/configure_firebase_ios.py /完整路徑/GoogleService-Info.plist
flutter run --release --dart-define-from-file=config/firebase.local.json
```

如果改了 bundle ID，加入 `--bundle-id 你的實際ID`。工具驗證必要欄位及 bundle ID，產生已加入忽略清單的本機 JSON 與 Xcode callback scheme 設定；不建立雲端資源、不綁付款及不部署規則。無須把管理員私鑰或 Google 密碼放進 App。

iOS client ID 以 Dart 傳入 Google SDK，reversed client ID 由本機 xcconfig 設定 URL callback。Keychain entitlement 已加入；真機仍需用自己的 Team 簽署並核對 Google callback 可返回 App。

Android 另註冊同一專案的 App，使用其 Android Firebase App ID／API key，填入 Web OAuth client ID，並登記實際 debug／release 簽署 SHA 指紋。不要把 iOS 的 App ID 直接當成 Android App ID。本輪最低 Android API 24；release Internet 權限及私人資料備份限制已加入。Android Google 真機驗收另行記錄。

## 3 介面及資料接口

`AccountAuth` 管理身分、Google 登入、重新驗證、登出及身分刪除；`AccountRepository` 管理本人帳號與聯絡記錄；`ContactCache` 管理安全快取；`ContactDialer` 只交由系統撥號。測試可替換各接口，生產路徑使用 Firebase、Google SDK 及系統安全儲存。

帳號記錄及緊急聯絡欄位見 [帳號方案](ACCOUNT-REGISTRATION.zh-HK.md)。Firestore 磁碟持久快取關閉；聯絡副本在 iOS 使用本機解鎖可讀且不遷移的 Keychain，Android 使用安全儲存。副本含 ownerUid，只在同一 SDK 已恢復身分下使用；安全儲存工作串行，登出清理排在較早的寫入之後。

刪除先重新驗證 Google，再在交易中建立最小刪除保護、移除 profile 及聯絡資料，最後刪除 Firebase Auth 身分。保護記錄僅含版本及時間，不含姓名、電話或電郵，用於拒絕舊 UID 重建。Auth 刪除失敗時可重試，禁止繼續新增聯絡資料。第四階段上傳前須擴充後端完整刪除工作。

## 4 檢查指令及結果範圍

在 `app/` 執行：

```sh
flutter analyze --no-pub
flutter test --no-pub
python3 -m unittest discover -s tool -p 'test_*.py'
flutter build ios --debug --no-codesign --no-pub
```

在 `backend/`、Node 22 以上及 Java 21 以上環境執行：

```sh
pnpm install --ignore-scripts
pnpm test
```

Emulator 使用固定 demo 專案及 localhost，不連接正式 Firebase；預期拒絕的測試會在 log 出現 PERMISSION_DENIED。無簽署建置不能直接安裝。依賴鎖定 Firebase iOS 12 相容系列，避免 Firebase 13 與目前 GoogleSignIn 原生套件的依賴衝突。

本輪 145 項 Flutter 測試、9 項 Firestore Emulator 規則測試及 1 項設定工具測試通過；程式分析無問題，iOS debug 無簽署建置成功。三份新版 Word 共六頁已完成排版檢查。

驗證結果以 [本輪驗證紀錄](baselines/2026-10-23.phase3-verification.json) 為準。自動測試使用假的身分及撥號接口，不會發起電話，亦不能取代真實 Google OAuth 或真機 VoiceOver。

## 5 真機驗收清單

- [ ] 記錄 App 版本、Firebase Project ID、iPhone／iOS 及簽署 Team。
- [ ] 未登入、取消 Google、無網絡及未配置時仍可用基本辨識。
- [ ] Google 返回 App、首次初始化、部分失敗重試及重新開啟恢復同一 UID。
- [ ] 聯絡人可跳過、修改、刪除；同帳號離線可讀；切換帳號及登出不顯示前一人的資料。
- [ ] VoiceOver 讀出稱呼及電話，由使用者啟動系統撥號；拒絕系統操作及無法撥號可理解，App 不稱已接通。
- [ ] VoiceOver 可完成用途確認、Google 返回、表單儲存、返回原任務及刪除確認；大字體可捲動。
- [ ] 刪除重新驗證同一帳號，Firebase Auth 使用者及聯絡／profile 移除，刪除失敗可重試。
- [ ] Release 安裝後拔線、關閉並重新開啟仍能使用。

後續接入 `pathguide-dev`，使用者回報已發佈第三階段規則，並完成帳號及聯絡人真機流程。以上清單未有逐項裝置／VoiceOver／刪除證據，不將口頭完成回報擴大成所有項目已驗收。第四階段照片服務另見接入文件。
