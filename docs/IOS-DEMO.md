# iPhone 相機辨識版：安裝與驗收

2026-10-22 操作更新：現以任務首頁啟動；進入即時辨識便自動開始及播報，主畫面只留暫停／繼續與更多操作。中斷後自動恢復，手動暫停則不自動恢復。以下早期操作及驗證紀錄保留作歷史依據；本輪行為與真機驗收以 [第一、二階段實作紀錄](PHASE1-2-IMPLEMENTATION.zh-HK.md) 為準。安裝與簽署步驟仍可參考下文，舊三類效能不可套用於現有模型。

這一版預設先顯示導航首頁；「搜尋目的地」、「我的路線」及「錄製新路線」是清楚標示為開發中的未來功能介面。切換到底部「探索」後，App 使用 iPhone 後置相機，在裝置上執行內置 TFLite 模型，辨識行人、單車、垃圾桶、柱、雪糕筒、落樓梯、扶手電梯、上樓梯及小心地滑牌，並可測試粵語播報。
所有影像只在裝置上即時處理，不錄影、不儲存照片、不上傳；另外保留模擬資料模式供介面驗證。

## 1. 將程式交到 Mac

把專案的 `app/` 資料夾和本文件複製到 Mac，例如放在 `~/Developer/pathguide-iphone-demo/`。保留 `app/assets/models/`、`app/pubspec.yaml` 和 `app/pubspec.lock`。
不要複製 Windows 的 `.tools/`、`app/build/`、`app/.dart_tool/`、`app/ios/Flutter/ephemeral/` 或 `app/ios/Flutter/Generated.xcconfig`；這些會在 Mac 重新生成。
可使用另外提供的 `pathguide-iphone-demo-source.zip`，解壓後進入其中的 `app/`。

## 2. Mac 準備

1. 安裝並啟動 Xcode，完成首次設定及 iOS 元件安裝。
2. 安裝 Flutter **3.47.5 stable**（Dart 3.13.4；與原專案相同版本），或符合 `pubspec.yaml` SDK 要求的相容版本。
3. 執行 `flutter doctor -v`，完成 iOS toolchain 項目。依 Flutter doctor 的提示安裝 CocoaPods（若依賴需要）；保留專案已有的 Swift Package Manager 設定。
4. 用傳輸線連接 iPhone，解鎖並選擇「信任此電腦」。按 Xcode 提示啟用 iPhone 的「設定 → 私隱與保安 → 開發者模式」。

官方步驟：[Flutter iOS 開發設定](https://docs.flutter.dev/platform-integration/ios/setup)。

## 3. 先測試及建置

在 Mac 的 `app/` 資料夾執行：

```sh
flutter pub get
flutter analyze
flutter test
flutter build ios --debug --no-codesign
open ios/Runner.xcworkspace
```

無簽署建置只驗證工程能否編譯；不能直接安裝到 iPhone。
Windows 可以跑 Flutter 靜態檢查及自動測試，iOS 建置必須在 Mac 執行。

## 4. 簽署並安裝

1. 在 Xcode 的 Settings → Accounts 加入你的 Apple 帳戶。
2. 在 Runner → Signing & Capabilities 勾選 Automatically manage signing，Team 選擇你的帳戶／Personal Team。
3. 保留 bundle ID `hk.pathguide.pathguide`；若該帳戶不能使用此 ID，只在本機把它改為帳戶可使用的唯一 ID，並讓 RunnerTests 的 ID 一併更新。
4. 選擇已連接的 iPhone 作為執行裝置，按 Run。
5. 如 iPhone 要求信任開發者，按系統提示到「設定 → 一般 → VPN 與裝置管理」信任你的開發者憑證。

個人真機測試可使用免費 Personal Team；這份交付不包括 App Store／TestFlight 發佈或開發者憑證。
最低 iOS 版本仍為 **15.0**。請記錄實際 iPhone 型號、iOS、Xcode 和 Flutter 版本。

## 5. 驗收清單

- [ ] 首次啟動顯示導航首頁，三張未來功能卡均標示為「開發中」。
- [ ] 首次切換到「探索」才要求相機權限；允許後顯示後置相機即時畫面。
- [ ] 對準行人、單車或垃圾桶時顯示相符的繁體中文標籤，框與物件位置一致。
- [ ] 「探索」頁的相機預覽填滿底部導覽列以上的空間；主畫面只常駐狀態膠囊和右下設定按鈕。
- [ ] 點擊右下設定按鈕後，FPS、推理耗時和辨識物件數正常；展開「技術資料」後，分析幀數持續增加且沒有持續增加的分析錯誤。
- [ ] 拒絕相機權限會顯示可操作的繁體中文原因，仍可切換到模擬資料。
- [ ] 相機與模擬資料按鈕都可用，切換時舊來源會停止。
- [ ] 調高顯示閾值可以減少框；隱藏／顯示標籤按鈕正常。
- [ ] 確認語音顯示 `zh-HK` 或 `yue-HK`，並親耳確認是粵語。若系統未提供粵語，介面會列出實際語音或故障原因。
- [ ] 關閉播報會立即停止目前語音，之後沒有新播報；重新開啟可再次播報。
- [ ] 切到其他 App／鎖屏後停止演示及播報；返回前台重新出現模擬框。
- [ ] 底部「探索／導航／設定」均可使用；離開探索頁後相機畫面停止。
- [ ] 在直向及較大字體下，操作按鈕和關鍵提示沒有被截斷。
- [ ] 沒有網絡時仍能演示；語音能否離線使用須按 iPhone 實際安裝的語音測試。

語音失敗時，先確認手機音量及可用粵語語音，重新開啟 App 再試。
語音插件或語音初始化故障不應阻止模擬畫面運作。

## 6. 驗證紀錄

2026-10-05，Windows／Flutter 3.47.5／Dart 3.13.4：

| 項目 | 結果 |
|---|---|
| Flutter 自動測試 | 96 個全部通過，包含導航首頁、底部導覽、iOS 演示及 Android 相機接口回歸 |
| Flutter 靜態檢查 | 沒有問題 |
| 介面測試預覽 | 檢視 390×844，以及 320×568、1.5 倍文字的畫面；小螢幕控制區可捲動 |
| iOS 設定與資源 | 名稱、直向、最低 iOS 15 通過檢查；既有類別 ID 及平台接口保留；模型版本及 SHA256 隨九類模型更新 |
| Mac iOS 建置 | Xcode 27.0 無簽署 debug build 通過；iPhone Simulator 原生測試 3/3 通過 |
| iPhone 安裝及實際播報語言 | 待驗收 |
| Android 相機真機回歸 | 待驗收 |

請完成上述清單後記錄結果；在此之前，只能稱為「iOS 相機與推理已實作、編譯及自動測試通過」，不能稱為「已在 iPhone 驗證」。
2026-10-19 更新：內置模型已換成香港九類 YOLO11n（640 Float32），既有類別 ID 保留，新增 50/51 為落樓梯/上樓梯。詳見 MODELS.md；舊版效能數字不適用於新模型。

## 7. Android 回歸驗收

自動測試會確認 Android 仍呼叫原生相機啟動及模型載入接口；它不能代替 CameraX 真機測試。
在可用的 Android 手機執行 `flutter run`，確認相機權限、即時預覽、真實辨識框、閾值調節及粵語播報。
切到背景再返回前台，確認相機可重新開啟；測試相機／模擬來源切換及繁體中文提示。

## 九類模型啟動及播報修正（2026-10-19）

模型現在一次載入清單映射，完成類別數核對前不發出辨識幀，避免把模型本地索引 0/5 誤當作舊天橋入口/欄杆 ID。輸出亦限制為目前模型清單聲明的類別。

探索 → 辨識設定現有兩個獨立滑桿：辨識信心門檻控制畫框，語音播報門檻控制發聲並儲存於手機。物件必須同時達到兩個門檻才有機會播報，並仍受播報開關及冷卻影響。語音預設 0.70 是舊值，尚未以九類模型重新校準，不能當作準確率或安全保證。
