# 路線導航：實作與接入

日期：2026-10-23。230 項 Flutter 測試、11 項後端測試、程式分析及 iOS 無簽署 Release 建置通過。Android 建置因本機缺少 SDK 未能執行；所有真機與實走驗收仍待完成。完整紀錄見 [驗證結果](baselines/2026-10-23.navigation-verification.json)。

## 功能與操作

首頁「路線導航」現已接入真實服務接口：搜尋香港目的地 → 選取並核對名稱／地址 → 預覽步行路線 → 開始導航。支援按鈕啟動的粵語搜尋、重播下一步、目前位置、暫停、繼續、確認結束及本機收藏。選取目的地及開始導航均需有效定位；開始及繼續時從新位置重算。

導航只在前景運作。導航中保持亮屏，切背景立即停止定位與語音，返回不自動恢復；離開導航分頁前確認結束。權限視窗的短暫 inactive 不當作離頁。定位過期、精度不足或路線匹配不明確時停止精確指示，接近終點後仍需使用者確認入口。路線不保證沒有樓梯、升降機可用或入口正確。

本輪沒有鎖屏導航、室內樓層定位、相機同步辨識、避障、公共交通或軌跡錄製。錄製入口繼續標示開發中。沒有以模擬資料替代未配置的服務。

## 架構與資料

`app/lib/navigation` 提供共用 Controller、步行進度引擎、資料契約、服務接口、導航頁及儲存。Flutter 引擎不引用 MKRoute、CLLocation、Google Route 等平台類型。

- iPhone：原生 NavigationPlugin 使用 MKLocalSearch、MKDirections 步行模式、Core Location、MKMapView。語音沿用 NativeMenuReader 的收音引擎，經共用 SpeechInputService 適配；沒有菜單專用字詞處理。
- Android：NavigationPlugin 使用 Maps SDK、Places SDK New 及 Fused Location Provider；SpeechInputPlugin 提供系統語音。Flutter 呼叫獨立的 Routes callable；Android 原生 SDK 不包含伺服器 Routes 憑證。
- 方法通道：`hk.pathguide/navigation`；定位事件：`hk.pathguide/navigation/location`；地圖視圖：`hk.pathguide/navigation/map`；Android 語音：`hk.pathguide/speech`。
- 搜尋、計算及定位事件受任務 generation 保護；取消後不接受遲到回應。停止硬件與取消串流並行，避免等待 EventChannel 回覆期間繼續定位。
- 路線及步驟折線使用 WGS84，距離米、時間秒；步驟起點投影到路線以建立進度範圍。保留供應商的指示與注意事項，不從文字猜測未知轉向。
- Android 定位年齡由 elapsedRealtimeNanos 計算。共用層再使用 Stopwatch 檢查經過時間；不以手機牆鐘時間計算定位新鮮度。
- 收藏使用安全儲存，schemaVersion 1。Apple 收藏保存目的地資料；Google 收藏只保存 Place ID、使用者輸入的名稱及本機時間。最近十個 Google 地點的標籤取自使用者搜尋字詞，重新選取時再查名稱、地址及座標。資料屬此手機，不跟帳號切換，可手動清除。
- Google 路線只顯示於 Google 地圖，Apple 路線只顯示於 Apple 地圖。不承諾兩平台同路。

規則版本 1：有效定位 ≤10 秒且水平誤差 ≤25 米；提前提醒約 50 米，接近提醒約 15 米並需誤差 ≤15 米及連續定位。單點跳動、重複快取定位及交叉／平行路線歧義不推進。偏離需離線距離 >max(35 米,2×誤差)、至少三點及十秒；重算間隔至少三十秒且單一請求。接近目的地需直線約二十五米內、沿路剩餘約三十五米內及連續定位。這些是待實地調校的工程門檻，不是精度保證。

## iPhone 安裝

不需要新增地圖金鑰或 Firebase 部署；導航本身可供訪客使用。沿用現有安裝入口以保留帳號設定：

```sh
cd /Users/darr/Desktop/development/pathguide-iphone-demo-source/app
./tool/run_iphone.sh
```

本次包含原生插件及定位權限說明，需完整重新建置安裝。允許使用 App 期間定位，並在系統設定開啟精確位置。語音輸入未有可確認的離線粵語時，會先詢問是否使用線上服務；拒絕後仍可文字搜尋。

## Android 設定

先安裝 Java 17 及 Android SDK，將 `sdk.dir` 寫入既有 `app/android/local.properties`；不要覆蓋其中的 flutter.sdk。目標 SDK 由現有 Flutter 設定提供，最低 API 24。首版需 Google Play 服務；沒有服務的裝置只停用導航，其他既有功能保留。

固定依賴 Maps 19.2.0、Places 5.1.1、Location 21.3.0。Places 6.0 移除了此版本整合使用的 fetchPlace，故先固定 5.1.1；已加入其 R8 保留規則及 Java library desugaring。這組 Android 依賴仍須在有 SDK 的環境完成實際建置，不能把 Dart 測試當作 Android 編譯通過。

1. 在共用 Google Cloud／Firebase 專案啟用計費、Maps SDK for Android、Places API (New)、Routes API。
2. 註冊 Android Firebase App `hk.pathguide.pathguide`，建立自己的開發／發佈簽署設定並登記相應憑證。現有 Gradle release 仍用 debug 簽署，只可作開發；正式發佈前必須更換。
3. Maps／Places 客戶端金鑰加 Android package／簽署憑證限制與 API 限制。把 `MAPS_API_KEY=...` 加入 `app/android/local.properties`，或由建置環境提供 `PATHGUIDE_MAPS_API_KEY`。不要把 Routes 憑證放進 App。
4. 複製 `app/config/navigation.android.example.json` 成 `navigation.android.local.json`，填入 Android Firebase 公開客戶端設定。不要沿用 iOS 的 FIREBASE_APP_ID。帳號需要的 Google OAuth 設定可另填；導航不要求 Firebase Auth 登入。
5. App Check 在共用基礎層初始化，獨立於照片同意及 Google 登入。開發 debug build 才可用 `APP_CHECK_DEBUG=true`，於 Firebase 登記該測試 token；發佈／release 驗證使用 Play Integrity，不開放測試 token。
6. 配置及部署下節的路線代理後，才把 `NAVIGATION_GOOGLE_ENABLED` 設為 `true`。發佈前公開導航條款／私隱文件，填入 `NAVIGATION_PRIVACY_URL` 與 `NAVIGATION_TERMS_URL`；草稿見 [私隱說明](legal/NAVIGATION-PRIVACY.zh-HK.md)與 [使用條款](legal/NAVIGATION-TERMS.zh-HK.md)。

```sh
cd /Users/darr/Desktop/development/pathguide-iphone-demo-source/app
flutter run --debug --dart-define-from-file=config/navigation.android.local.json
```

缺少 Maps 金鑰、Google Play 服務、Firebase／App Check 或路線代理時會回報不可用，不啟動假導航。定位只申請前景 coarse／fine；只有約略權限不能開始逐步導航。沒有背景位置權限或前景服務。

## 路線代理部署

`computeWalkingRoute` 使用 Node 22，asia-east2、App Check 強制驗證、最多兩個實例、每實例並行四個請求、二十秒函數逾時及十二秒上游逾時。Firebase Auth 可以為空；App Check 只證明 App 來源，不識別使用者。

請求 schemaVersion 1：requestId、origin 的 latitude／longitude、destinationPlaceId。後端固定呼叫 Google computeRoutes，WALK、繁體中文 zh-TW、HK、METRIC，僅取所需欄位；回傳共用 WalkingRoute 格式。沒有任意網址代理、Firestore 路線記錄、GPS 軌跡或完整位置日誌。

在已登入且有權限的 Firebase CLI 環境執行：

```sh
cd /Users/darr/Desktop/development/pathguide-iphone-demo-source/backend
firebase functions:secrets:set GOOGLE_ROUTES_API_KEY --project YOUR_PROJECT_ID
firebase deploy --only functions:computeWalkingRoute --project YOUR_PROJECT_ID
```

Routes 金鑰限用 Routes API，由 Secret Manager 注入。若要求來源 IP 限制，需先配置固定出口，不能隨意限制到開發電腦 IP。於 Cloud Console 設定 Routes 與 Places 的每日／每分鐘配額和預算告警；預算告警本身不會停止計費。開啟 App 前先以少量測試流量確認 App Check 接受、無效 App Check 拒絕、配額耗盡能正常回應。此工作區沒有部署或建立任何計費服務。

## 驗收與待辦

自動測試使用人工合成座標，涵蓋雙供應商規格、短路段、交叉／平行道路、GPS 跳點、快取點、偏離與冷卻、過期定位、取消／背景／延遲亮屏、收藏恢復、五次語音搜尋及單一路徑讀屏。後端測試覆蓋 App Check 上下文、訪客、格式、固定上游、polyline、無路線、配額及逾時。菜單、辨識、帳號及照片保留完整回歸。

真機項目仍須執行，不能從建置推定已通過：

- iPhone 及兩個 Android 品牌；至少一部切換精確／約略位置，另測沒有 Play 服務的提示。
- HKDI 周邊開揚、多轉彎、建築遮擋／天橋附近三類路段，各三次。由測試人員陪同行走，記錄指示位置、誤差、漏播、重播及錯誤重算。
- VoiceOver／TalkBack 開關、五次粵語輸入、首次權限、拒絕權限、來電及耳機切換。
- 開始／重算中切背景、手動暫停再移動、斷網、返回前景不補播，以及確認入口／結束。
- 三十分鐘亮屏導航，記錄耗電、發熱及播報表現；測試紀錄不要提交私人軌跡或金鑰。

參考：[Apple MKDirections](https://developer.apple.com/documentation/mapkit/mkdirections)、[Google SDK 版本變更](https://developers.google.com/maps/documentation/places/android-sdk/release-notes)、[Routes 顯示規定](https://developers.google.com/maps/documentation/routes/policies)、[Places 儲存與顯示](https://developers.google.com/maps/documentation/places/android-sdk/policies)。
