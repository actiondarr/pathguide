# 領路通 PathGuide 後端與雲端資料流程方案

更新日期：2026 年 10 月 27 日。閱讀入口：[App 與原計劃對照](APP-PLAN-REVIEW.zh-HK.md)。

**後端把已同意的錯誤場景，經覆核、訓練與評估，轉成可回退的私人模型。** 上傳成功只代表收到照片，不代表已學會、變準或可以更新。

## 1. 已有程式與缺口

| 項目 | 現況 |
|---|---|
| 帳號 | Google Auth、本人 profile、選填聯絡人及規則已有程式；聯絡資料不加入訓練 |
| 照片 | getPhotoConsent、setPhotoConsent、submitPhoto、listPhotoProgress 已實作；本機照片開關關閉 |
| 清理 | deletePhotoAccountData、expirePhotoCandidates、removeLatePhotoObjects 已實作；既有文件記錄未部署，本輪未查詢雲端部署清單 |
| 導航 | computeWalkingRoute 已有 Google Routes 代理程式，與照片同意獨立；iPhone MapKit不依賴它 |
| 私人學習 | 管理員覆核、快照匯出、排程、GPU worker、registry及下載授權未接通 |

活動程式來源為 [Functions](../backend/functions/index.js)、[照片政策](../backend/functions/photo_policy.js)、[規則](../backend/firestore.rules)及[第四階段接入](PHASE4-IMPLEMENTATION.zh-HK.md)。舊firebaseCode-2的signed URL原型只作歷史參考，不是目前App接口。

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

App／共用模型完成後先推GitHub commit、tag／Release並核對，再安裝交付。私人照片、權重及含私人資訊報告留在受權限保護的儲存，不進共用repo；私人registry保留歷史版本供本人回退。詳見 [交接](../HANDOFF.md)。

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

本輪只更新文件，沒有部署、開啟照片收集、提交GPU或改App功能。
