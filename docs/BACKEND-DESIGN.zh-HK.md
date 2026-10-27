# 領路通 PathGuide 後端與雲端資料流程方案

更新：2026年10月27日。唯一Backend文件；[Frontend](FRONTEND-DESIGN.zh-HK.md)管理App，[Dataset Review](DATASET-REVIEW.zh-HK.md)管理資料與品質。功能／接口／部署改動必須同一提交同步更新本檔，不另開交接。

**後端把已同意的錯誤場景，經覆核、訓練與評估，轉成可回退的私人模型。** 上傳成功只代表收到照片，不代表已學會、變準或可以更新。

## 開發階段與目前進度

三份文件共用S0–S7階段編號。狀態只表示可追溯證據：**已有程式**不等於已部署；**待實測**不等於通過；**受阻**需先解依賴；**未開始／未來研究**不是現有功能。沒有足夠工作量與驗收資料前不編造完成百分比或日期。

S5的圖示訓練可與S2、S4並行準備；私人訓練必須先有S0品質基準及S2核准資料，S6整合驗收通過後才擴大S7範圍。當前主線仍是改善準確度，室內畫面不可取代品質驗收。

| 階段 | 本階段後端工作 | 目前進度 | 完成標準 | 下一步／依賴 |
|---|---|---|---|---|
| S0 工程基線與版本保存 | 固定契約、權限、設定、模型發佈及回退 | 規則／callable已有；文件已備份，App／模型未提交工作未成新release | 可由tag＋相符模型重建；配置／密鑰不進Git | 覆核共用版本並以遠端commit／asset核實 |
| S1 現有App核心功能 | Google身分／聯絡與Android路線代理 | 帳號已有程式與使用者回報；Routes有程式但未接通／驗證 | 本人權限、重新驗證刪除與平台導航服務驗收 | 保留iPhone MapKit獨立；補部署及真機證據 |
| S2 照片收集與管理員覆核 | 私人上傳、同意、配額、清理與管理員標註 | 上傳／清理程式已有，本機關閉；管理員覆核服務未接通 | 同意→同幀照片→核准標註可追溯；越權／撤回被拒絕 | 先測試專案部署與權限，再接覆核工具 |
| S3 私人訓練與模型更新 | 快照、排隊、worker、評估、registry、下載 | 未接通；付費GPU預算未定 | 模擬完整流程、真實工作受配額控制、合格模型可本人下載／回退 | 先mock worker、資料接口與取消／刪除，再開付費執行 |
| S4 室內近距離感知與引導 | 只供版本／設定；不把即時深度送雲端推理 | 無室內服務，首版即時運算在手機 | 離線空間感知不依賴後端；無深度／姿態上傳副作用 | 與Frontend確認接口，保留原照片用途界線 |
| S5 圖示／文字與設施理解 | 保存共用B版本／評估及相容性 | 只有本地／Drive實驗產物；正式run中斷，未核准發佈 | B合格後有獨立namespace、映射與手機相容發佈包 | Dataset完成來源／格式／逐類評估；不把失敗當ready |
| S6 HKDI整合驗收與試用發佈 | 日誌、預算、排程、權限／刪除與版本回退 | 完整學習閉環未部署／驗收 | 各種失敗可定位／重試，費用受控、遠端備份先於安裝 | 結合Frontend真機、Dataset品質及角色驗收 |
| S7 多場地、多樓層與平台擴充 | 場地圖／地標版本、選填同步、provider連結 | 未開始／未來設計 | 依場地／UID授權與版本相容性分階段驗收 | 先S6限定場景，未核准場地不開精確室內路由 |

## 各功能計劃如何實現

本節接口名稱若寫「新增」即尚未實作，不能當成目前已可呼叫的API。

| 功能／階段 | 目前狀態 | 實現方法與輸入／輸出 | 依賴／完成標準 |
|---|---|---|---|
| B01 帳號、角色與私人聯絡／S1–S2 | Google／聯絡規則已有；覆核角色未接 | 驗證token取得UID，以可重試交易建profile；聯絡資料保持獨立。新增覆核角色由受權Admin設定custom claims，服務端驗證，不接受前端自報admin或ownerUid | 本人／覆核者／一般訪客權限分開；角色變更與token刷新／撤銷有測試 |
| B02 照片同意與提交／S2 | callable已有，未啟用 | 沿用get／setPhotoConsent與submitPhoto；檢查UID、epoch、配額／尺寸，解碼重編碼、綁photoId／objectGeneration，再原子更新validated／pending。sourceSha與清理後sha分開 | 前端F05同幀資料；重試冪等、無效App Check／舊epoch拒絕，不改成公開Storage |
| B03 管理員覆核／S2 | 未接通 | 新增受權覆核操作，輸入photoId、版本、完整annotations與coverage及核准／拒絕理由；先提供可匯入覆核清單與原圖檢視的內部工具，服務端寫reviewedBy／time／version。模型預測另存，不能覆寫人工答案 | Dataset D02；不能只改狀態approved，全圖答案／來源／雜湊須有效；延遲AI寫入不破壞核准版本 |
| B04 私人快照匯出／S3 | 未接通 | 依ownerUid＋仍有效用途查核准版本，合併獲授權基礎回放，固定影像／標註版本、場景split、coverage與SHA，輸出不可變manifest；重送同一請求沿用snapshot ID | Dataset D03／D07；同實物不跨split，其他UID資料不得混入，資料變動建新snapshot |
| B05 排程、去重與佇列／S3 | 未實作 | 每日03:00香港時間檢查新核准資料與獨立驗證條件；以UID＋snapshot＋config建唯一job，交易取lease，綁GPU預算／單次時限。建立GCP Batch工作，記provider job ID，狀態由受權事件／查詢更新 | 缺預算不提交；同UID單工作、重複事件不重開；UTC照片配額日界保持不變 |
| B06 GPU訓練worker／S3 | 現有Colab實驗；服務未實作 | 容器固定工具／權重／設定，最小IAM讀指定snapshot，執行preflight→smoke→正式run；每輪備份checkpoint／optimizer／CSV及心跳。相同快照中斷才resume，改資料開新run；逾時／取消不發佈 | Dataset提供D04／D05／D07腳本；先mock成功／失敗／重試，再配置GPU；不把免費Colab當可靠無人服務 |
| B07 品質門檻與獨立評估／S3 | 只有本地A／B評估工具 | worker產生候選與現用模型的同資料逐類比較、樣本量、export parity及手機結果；核准服務驗完整報告並套版本化門檻，不能由worker一句success直接寫ready | Dataset第3節為門檻唯一來源；目標無真值或其他類別退化則不核准；測試集不拿來反覆調參 |
| B08 Registry與發佈包／S3–S5 | 未實作 | 新增不可變模型record：ownerUid／shared scope、job／snapshot、A或B namespace、權重／manifest SHA與大小、taxonomy、App相容性、評估與狀態；核准才設可下載，發布指標另指向可回退版本 | A／B映射不得互換；現行內置format:1不無聲改義；共用模型與私人模型有不同存取範圍 |
| B09 本人下載、自動更新與回退／S3 | 未接通 | 新增本人模型offer與限時下載授權；發票前重驗身分／用途／刪除狀態，URL只指向核准物件且不記完整URL日誌。App下載暫存、核對offer、SHA與映射後在任務停止時切換；保留上一版／內置版 | Frontend F08；逾時重取授權，跨UID／不相容／損壞拒絕。已簽網址有有效期，撤回後仍須處理過期窗口與物件清理 |
| B10 撤回、取消、帳號刪除與到期／S2–S3 | 第四階段清理已有；訓練資源未覆蓋 | 沿用tombstone／deleting，先禁止新上傳／job／下載，取消並等待或隔離worker，再按清單刪照片、annotations、snapshot、外部副本及私人模型，最後Auth；每步可重試並拒絕遲到重建 | 擴充現有deletePhotoAccountData；基礎共用資料不因單UID刪除而誤刪，處理中狀態可理解 |
| B11 Android搜尋／步行代理／S1 | computeWalkingRoute已有，未部署／驗證 | App Check驗應用，訪客可用；固定Google Routes WALK、HK／繁中與回傳欄位，Secret Manager供金鑰，逾時／配額分類；不接受任意網址代理、不持久保存軌跡 | Google配置、預算、簽署限制及真機；iPhoneMapKit不改走此代理 |
| B12 發佈、診斷與預算／S0–S6 | Git提交已有；完整App版本checkpoint未齊 | 記匿名request／job ID、階段、耗時與錯誤類別，監察心跳、清理積壓、評估失敗與花費；提交前配額／worker時限與預算配置缺一拒絕。App發佈依第7節先GitHub再安裝 | 日誌無照片／私人位置／憑證；告警不等於硬性花費上限；回退演練與版本報告可追溯 |
| B13 室內即時資料邊界／S4 | 未有深度服務，規劃本機處理 | 深度／pose／網格留手機，不新增即時雲端避障API；只提供相容模型與設定。若日後要上傳序列，需獨立用途、保留／刪除及安全設計，不能沿用照片同意 | Frontend F09–F12與Dataset D09；關閉網絡不影響已載入的本機感知 |
| B14 拓撲graph、觀察序列與場地版本／S7 | 概念討論，未實作 | 先手動node／edge驗證；永久地圖、node內容與行程觀察分開版本化，圖片只產生候選對照。不吻合先保留未知與待覆核，核准後才更新地圖；量測座標／幾何校準及樓層連接後續加入 | F14／D09；不用GPS猜樓層，無場地資料不提供指定課室；場地更新不破壞舊App |
| B15 路線錄製／場景摘要同步／S7 | 後續構想 | 先本機功能；自願同步才新增UID版本化路標序列與刪除。場景摘要預設本機有效證據，不自動新增雲端影像描述或追蹤紀錄 | F17；另行確認用途與授權，不能因訓練照片同意便錄影／上傳路線 |
| B16 Apple／電話連結與跨平台／S7 | Google現行；其他未接 | 使用Firebase明確provider linking，在驗證後維持原UID與私人資料，處理已有帳號衝突，不以同電郵猜合併；Android與iOS使用各自App／簽署設定 | F18；重新登入、登出、刪除與相同UID恢復有雙平台證據 |

管理員角色依據：[Firebase custom claims](https://firebase.google.com/docs/auth/admin/custom-claims)；GPU工作／時限依據：[Batch GPU工作](https://docs.cloud.google.com/batch/docs/create-run-job-gpus)、[工作時限](https://docs.cloud.google.com/batch/docs/create-run-basic-job)。這些是規劃所用平台能力，未表示本專案服務已部署。

## 1. 已有程式與缺口

| 項目 | 現況 |
|---|---|
| 帳號 | Google Auth、本人 profile、選填聯絡人及規則已有程式；聯絡資料不加入訓練 |
| 照片 | getPhotoConsent、setPhotoConsent、submitPhoto、listPhotoProgress 已實作；本機照片開關關閉 |
| 清理 | deletePhotoAccountData、expirePhotoCandidates、removeLatePhotoObjects 已實作；既有文件記錄未部署，本輪未查詢雲端部署清單 |
| 導航 | computeWalkingRoute 已有 Google Routes 代理程式，與照片同意獨立；iPhone MapKit不依賴它 |
| 私人學習 | 管理員覆核、快照匯出、排程、GPU worker、registry及下載授權未接通 |

活動程式來源為 [Functions](../backend/functions/index.js)、[照片政策](../backend/functions/photo_policy.js)、[規則](../backend/firestore.rules)。舊firebaseCode-2的signed URL原型只作歷史參考，不是目前App接口。

## 2. 現行照片流程與資料

獨立照片同意 → 同幀JPEG與預測 → 綁定project／UID／consent epoch的加密待傳 → Wi-Fi callable提交 → 伺服器驗證與重編碼 → 私人儲存與待覆核進度。

- 單張JPEG最多2 MiB，沒有signed URL分配。相同UID＋photoId＋來源雜湊與epoch重試不重複扣額，物件禁止覆寫。
- 驗證Google身分、App Check、帳號狀態、同意epoch、解碼／大小及配額。移除EXIF／GPS／XMP；sourceSha256與最終雲端sha256分開。
- 配額以UTC計日：總候選100、自動50、場景10；自動至少相隔30秒、場景至少60秒。香港時間的訓練排程不更改UTC配額日界。
- 本機最多50張／50 MB、七日到期；未覆核雲端圖預設三十日，按小時每批最多200張清理。須監察錯誤與積壓。
- 本人只讀進度，不能寫核准標註、訓練或發佈狀態。預測可空、零分合法，不假造未知class。

| 資料 | 位置／狀態 |
|---|---|
| 照片同意 | 現行 users/{uid}/private/photoConsent |
| 照片／配額 | 現行 users/{uid}/photos/{photoId}、photoQuotas/{UTC日期} |
| 未確認JPEG | 現行私人 unconfirmed_photos/{uid}/{photoId}.jpg |
| 覆核／快照 | 規劃受權覆核服務寫入的版本化核准記錄 |
| 工作／registry | 規劃以ownerUid綁定，App只讀本人進度 |
| 私人模型 | 規劃 personal_models/{uid}/{modelVersion}/，僅授權相符UID |

## 室內graph與照片序列資料設計（討論方案，待驗證）

先做手動graph＋模擬observation的原型，再接AI；不需要先完成大型VPS或向量資料庫。以下是設計分層，不是現有API／Firestore已支援的格式：

| 資料層 | 保存內容 | 更新規則 |
|---|---|---|
| graph | building／floor、mapVersion、node ID、實際通路edge及限制 | 只有核准的地點／連通性變更才發新版本 |
| node內容 | 同位置的objects、店名／別名、參考圖片、特徵版本、有效時間與證據 | 改店名不換位置ID；動態物件只作觀察，不當永久錨點 |
| 觀察queue | session、seq、capturedAt、圖片／特徵及候選node／可信度 | 是行程序列，按拍攝順序，不按Server回覆先後或預測node排序 |
| 配對結果 | matched／uncertain、候選、證據、mapVersion、觀察時間 | 低信心保留未知；不存在的精準位置／朝向不填假值 |
| 地圖變更候選 | 新地標、店名疑似改變、封閉或不吻合證據 | 覆核後才升格；模型自己猜的結果不直接變地圖真值 |

最小node示例（尚未量測的位置保留null）：

```json
{"id":"L1_N03","floor":"L1","position":null,"objects":[{"type":"shop","name":"店面A"}],"referenceImages":[],"contentVersion":1}
```

渲染用的示意layout與真實公尺座標分開；若加入x,y，必須同時記原點、座標系、單位及量測來源。edge先驗實際連通，同層雙向用無向邊；單向、封閉、樓梯與升降機後續獨立屬性，不一律當雙向。

定位處理流程：觀察入queue → 用最後可信node／樓層／路線選graph鄰域 → 比較最近多筆候選與允許轉移 → matched或uncertain → 需要時擴大搜尋。保留停留、跳node、倒行和分岔，遲到回應不能覆蓋新位置；不確定時不強制選「預測的下一個node」。

每5秒上傳屬新增的定位用途，不能直接套私人訓練照片API：現有自動照片冷卻30秒、場景60秒且有日額。後續若採Server定位，須獨立同意／session／限流／短保留策略；定位圖片預設不加入私人訓練或共用地圖，地圖建庫與私人模型亦非同一批資料。

後續AI可加入全局檢索、局部特徵及OCR；純圖片鄰近node只能支持拓撲候選，精確PnP仍要已知3D點與相機內參，不能由node ID直接求得公尺級pose。[OpenCV PnP](https://docs.opencv.org/4.x/d5/d1f/calib3d_solvePnP.html)；完整3D建圖／匹配路線可參考 [hloc](https://github.com/cvg/Hierarchical-Localization)。iPhone沒有通用Wi-Fi掃描API，因此初版粗篩先用使用者選定場地／樓層與可信起點，不把任意SSID指紋當既有能力。[Apple Wi-Fi API說明](https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview)

## 3. 管理員覆核與自動批次（待實作）

管理員透過受權限保護的工具補漏修框；原始預測與人工答案分開。保存覆核者、時間、定義、授權及影像／標註雜湊。只有核准且用途仍有效的資料可進快照；流程依 [Dataset覆核](DATASET-REVIEW.zh-HK.md)。

每天香港時間03:00檢查：每UID至少50張新增核准圖、三個場景及獨立驗證資料；滿足才建立不可變快照及工作。資料不足、未同意或預算未設定時不提交GPU。

採Firebase記錄／排程、私人Cloud Storage及GCP Batch容器GPU worker。首版私人微調限相容十類A與獲授權基礎資料回放，不混別人的私人照片；B保持獨立共用模型。

工作保存jobId、ownerUid、快照、基礎權重、設定／容器版本、run ID、checkpoint、心跳、取消旗標、評估及錯誤。以UID＋快照＋設定去重，交易取得lease；同UID不得同時訓練兩份。恢復使用同一快照，資料改動另建run。

狀態區分資料不足、待覆核、queued、running、evaluating、ready、failed、cancelled；評估不合格不能寫ready。門檻見Dataset覆核，不憑訓練成功自動發佈。現用十類gate=false只屬試驗，不自動升格為已核准基礎模型。

**GPU預算待定，付費提交預設關閉。** 先完成模擬worker的成功、失敗、重試與取消。部署前設定專案、可用區域／GPU、單次時限、每日額度、併發及預算；缺設定即拒絕提交，不能用告警冒充停止計費。

## 4. 私人發佈、自動更新與回退（待實作）

訓練 → validation比較 → 凍結候選／獨立驗收 → 格式及映射檢查 → 核准registry → 本人授權下載。不合格保留原版本，報告同時寫改善與退化。

發佈記錄含ownerUid、jobId、snapshot、模型與manifest雜湊／大小、taxonomy、相容App及評估版本。私人發佈envelope與現行內置format:1分開，不假稱目前parser已支援新欄位的完整驗證。

使用者可另行預先同意自動更新；未同意則手動選擇。僅App前景且辨識／導航等相機任務停止時下載至暫存，驗UID／雜湊／映射／相容性，試載入後原子切換。保留上一個私人版本與內置備援，失敗回退。此決定取代「每次都必須手動啟用」。

App／共用模型完成後先推GitHub commit、tag／Release並核對，再安裝交付。私人照片、權重及含私人資訊報告留在受權限保護的儲存，不進共用repo；私人registry保留歷史版本供本人回退。完整版本程序見本檔第7節。

## 5. 撤回、刪除與失效

- 關閉收集停止本機擷取／待傳；另提供個人訓練及自動更新控制，worker在排隊、取資料、續跑與發佈前重驗授權。
- 刪除先建保護、停止新工作／下載，取消並等待或隔離worker，再清理照片、標註、快照、第三方匯出及私人權重，最後移除身分。遲到事件不得重建資料。
- 現有deletePhotoAccountData只涵蓋第四階段；加入worker／registry後必須擴充，不能假稱已涵蓋未有資源。
- 室內深度、姿態、網格留本機；照片同意不擴大為持續影片、GPS或軌跡上傳。方向短片另行授權。

## 6. 後端驗收

- [ ] 身分／App Check、跨UID、舊epoch、影像及額度會拒絕；重送不重複照片或工作。
- [ ] AI不能覆寫人工答案；未核准／拒絕／授權不明的資料不入快照。
- [ ] 缺預算不提交；lease、逾時、心跳失效、checkpoint續跑及取消有測試。
- [ ] 不合格不發佈；本人下載、閒置切換、損壞回退與切帳號正確。
- [ ] 刪除與訓練／下載競爭不復活舊資料；私人產物不進GitHub。
- [ ] 共用版本遠端備份完成才交付，舊tag與對應模型可重建。

## 7. 部署、設定與版本回退

帳號與照片服務分開配置；目前本機照片開關關閉，既有紀錄未部署照片服務，本輪未讀取雲端清單，不以文件代替部署驗收。

- iOS：啟用Google provider並註冊相符bundle ID，取得手機端GoogleService-Info.plist。在app目錄執行下方設定工具；不用管理員私鑰，不能把本機設定提交Git。

```sh
python3 tool/configure_firebase_ios.py /完整路徑/GoogleService-Info.plist
./tool/run_iphone.sh
```

- 上傳：先確認計費／預算、Storage bucket、Functions區域（現有callable為asia-east2）及App Check，再覆核Firestore／Storage規則與索引。測試用debug attestation只限測試；正式版不發佈debug token或放寬規則。部署與實際測試通過前PHOTO_UPLOAD_ENABLED保持false。
- 在backend/functions安裝依賴後執行pnpm test；backend根目錄的pnpm test跑Firestore／Storage Emulator，需Node22、Java21及pnpm。Emulator與真實專案分開，呼叫handler的測試不代表雲端App Check閘道已通過。
- Android：需Java17與Android SDK、Google Play服務、相符Firebase Android App及簽署SHA、Maps／Places受限金鑰，設定範本在app/config/navigation.android.example.json。現有SDK固定Maps19.2.0、Places5.1.1、Location21.3.0，實際建置仍待驗證。
- Google Routes憑證放Secret Manager，代理設定GOOGLE_ROUTES_API_KEY；只在服務與App Check驗證後啟用NAVIGATION_GOOGLE_ENABLED。iPhone MapKit不需Google Routes部署。Google路線只顯示在Google地圖，Apple路線在Apple地圖。
- 正式公開導航前，補營運者／聯絡方式及可用政策網址，設定NAVIGATION_PRIVACY_URL與NAVIGATION_TERMS_URL。下方草稿重點不能當已發佈政策。

每個App／共用模型版本：完成檢查 → 增加App版本／build → 提交程式、lockfile、對應模型／映射及三份文件更新 → 建不可變tag（v版本+build）／Release → 推送並核對遠端 → 才安裝交付。Release記錄模型SHA、評估、限制與重裝方法；實驗版標prerelease，不覆寫tag、不force push。

倉庫為https://github.com/actiondarr/pathguide，既有工作分支feature/cross-platform-navigation。小型共用模型隨Git，過大共用產物用Release asset並記SHA及精確版本；私人照片／權重不得進共用repo。保留舊tag、模型及相容資料；回退App需重建並有效簽署，必要時用新的遞增iOS build號。私人模型則由本人授權registry保留上一版。

文件整併是文件提交，不冒充App還原點；現有未提交App／模型仍須另行完成版本備份。

## 8. 導航資料與使用說明（發佈前草稿重點）

導航只在使用者啟動與App前景取得位置；暫停、背景或結束停止定位，不建立／上傳行走軌跡。Apple／Google會收到完成搜尋及路線所需查詢、起點／目的地；代理不持久保存完整座標／路線，診斷避免私人位置。

語音按鈕才收音；優先裝置端，線上服務先取得本次同意，不把導航或錄音加入模型訓練。收藏／最近十個地點在本機安全儲存，可清除，不跟帳號同步；Google項目以Place ID、使用者標籤與時間保存，再查地點。

路線可能有誤差、延遲或入口不符，不保證樓梯／升降機可用，不提供過路時機、室內樓層或鎖屏導航。接近終點仍需確認入口，資訊不代替白杖、導盲犬或定向技能。Android需已配置服務、網絡與適當權限。

供應商參考：[Google Maps條款](https://maps.google.com/help/terms_maps/)、[Google私隱](https://policies.google.com/privacy)、[Apple地圖條款](https://www.apple.com/legal/internet-services/maps/terms-en.html)、[Apple私隱](https://www.apple.com/legal/privacy/)。正式政策需補聯絡及變更通知方式，不能以本章冒充已公開條款。

## 9. 維護紀錄

2026-10-27：帳號／照片契約、部署、隱私草稿重點、訓練／更新及GitHub回退整合於此。本輪沒有部署、開收集、提交GPU或改App功能。每次功能／接口／部署變更直接更新本檔現況、設定、驗證與限制。


2026-10-27階段化補充：加入S0–S7分工及B01–B16實現路線，標示現有callable與待新增的覆核／快照／worker／registry／場地服務，列明輸入、輸出、依賴與驗收。下一輪先S2權限／部署與覆核，再用mock完成S3；預算未定不提交付費GPU。本次沒有部署或改接口程式。

2026-10-27 graph討論補充：為B14定義graph、node內容、observations queue及覆核變更的分層；5秒Server定位需另立用途與配額，不能冒充既有照片服務。新增schema僅供概念驗證，本輪未實作／部署。
