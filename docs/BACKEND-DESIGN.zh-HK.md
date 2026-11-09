# Backend：PathGuide 資料、服務契約與交付

更新：2026年11月10日。只維護服務／本機資料契約與部署；使用者流程及模型品質分別見Frontend與Dataset。
## 最新狀態摘要（2026-11-10，依版本收據；非即時雲端查詢）

- 手機已交付 **1.11.0+29**，來源f2e13e3；不可變tag／prerelease先核遠端，再原位安裝、獨立核版本及正常啟動，未清資料。599項Flutter／7項略過、錄路相關53項及analyze通過；兩個模型及兩份manifest的SHA不變。見[交付收據](../verification/release-receipts/app-1.11.0+29.json)。
- 已有：六類錄路標記、三方向鍵取相／自動命名、復原、免打字保存草稿、captured schema4，以及單開關場景UI與固定內容拒絕分類。這些是工程及裝機證據，未代替實地／VoiceOver驗收。
- 未完成：更多標記、錄音／文字備註、重行使用已存方向、完整失敗歷史及無障礙焦點。系統截圖後即時辨識全頁無回應仍未定位；廚廁內容拒絕、實際起音及場景品質仍待新真人結果。
- 場景試驗最近已批准累計100次／估算US$0.50，至香港時間2026-11-14 03:22:40；不是保證可用100次或供應商帳單硬上限。已用／未知花費保留，未自動續期；歷史餘額不作現時餘額。見[許可證據](../verification/scene-100-five-days-20261109.json)。
- A十類品質gate=false，三個修正候選拒用；B11未完成發佈。Dataset採集／標註／新訓練仍暫停。錄路、雲端分析、回報及訓練用途分開。
- Codex負責實作／檢查及交付；真人決定內容與任務驗收。舊DSH派工、票據及預算不作現行指令。

<a id="service-scope"></a>
## 1. 服務目標與責任

後端把已同意的問題，經覆核、修正與獨立評估，轉成可追溯、可回退的改善。共用模型與私人微調分開授權及驗證；上傳成功只代表收到資料。

| 資料／能力 | 邊界 |
|---|---|
| 基本辨識及已錄室內路線 | 本機優先，不以帳號、雲端問答或私人訓練為前置 |
| 私人路線 | 已走路標／有向路段及版本；不自動同步或加入訓練 |
| 雲端看圖 | 另取用途同意，只送必要內容；場景採固定Qwen及有界許可；其他擴展及供應商保留政策另核 |
| 問題回報及覆核 | UID／同意版本／角色隔離；核准資料不等於模型改善或發佈許可 |
| 模型更新 | 獨立品質及相容性通過後提供；保留閒置切換及回退 |

<a id="service-state"></a>
## 2. 現況與已確認限制

手機現為1.11.0+29；場景服務狀態及許可以上方最近證據為準，本輪未作雲端查詢。錄路schema4是本機資料契約，不新增雲端錄路或訓練服務。

<a id="1-已有程式與缺口"></a>

### 已有程式與缺口

| 項目 | 現況 |
|---|---|
| 帳號 | Google Auth、本人 profile、選填聯絡人及規則已有程式；聯絡資料不加入訓練 |
| 照片 | getPhotoConsent、setPhotoConsent、submitPhoto、listPhotoProgress 已實作；本機照片開關關閉 |
| 清理 | deletePhotoAccountData、expirePhotoCandidates、removeLatePhotoObjects 已實作；既有文件記錄未部署，本輪未查詢雲端部署清單 |
| 導航 | computeWalkingRoute 已有 Google Routes 代理程式，與照片同意獨立；iPhone MapKit不依賴它 |
| 人工覆核 | 七個問題／覆核callable與本機工作台已有；有分頁待辦及修訂歷史，預設關閉；真實人員／容量／部署未驗收 |
| 場景描述 | describeScene最近部署與試驗許可已留證；內容／真人任務待驗，見場景契約 |
| 私人學習 | 快照匯出、排程、GPU worker、registry及下載授權未接通 |

活動程式來源為 [Functions](../backend/functions/index.js)、[照片政策](../backend/functions/photo_policy.js)、[規則](../backend/firestore.rules)。舊firebaseCode-2的signed URL原型只作歷史參考，不是目前App接口。

下一版三任務驗收不依賴新增私人訓練服務。現有16個Functions export中，七個問題／覆核API涵蓋問題接收、本人進度／撤回、人工覆核、分頁待辦及修訂歷史；均未部署、預設關閉。本機工作台已完成合成操作驗證，容量／抽覆／爭議裁定、修正案例後半段及私人模型拒用／撤回仍是規劃；既有照片上傳開關保持關閉。

<a id="route-landmark-learning"></a>
### 已錄路標私人批次訓練契約（2026-11-06，規格已確認／未接通）

2026-11-07 L1來源檢查點（#20，仍進行中）：新增獨立route_learning_v1加密候選儲存API及裝置專用金鑰／iOS受保護且排除備份的scope；候選保留route/version、trip、session/sequence、原結果、JPEG／特徵SHA及profile。支援pending／verified／needsInformation／rejected的版本化覆核紀錄、CAS衝突、同趟相片SHA去重、每趟12／全庫48及64MiB磁碟上限、七日到期讀取阻擋及明確cleanup。覆核只為本機操作者聲明，不是後端角色驗證／獨立真值。刪路線API先寫tombstone，取消在catalog切換前作廢寫入；候選失敗不碰穩定路線庫。

本片未接錄路控制器、選填收集／覆核UI、實際刪路線流程或自動到期排程，尚未產生真實候選；亦未接記憶補強、雲端、快照／訓練／更新。不得將API存在當成用戶可用／已學會；#19及#20保持未完成。

L1的8項候選儲存測試、analyze及Swift語法檢查有[工程證據](../verification/route-learning-store-20261107.json)；儲存核心其後隨App保留，完整收集流程及原生保護真機驗收仍待完成。

服務現況不變：[已錄路標持續改善規格](https://github.com/actiondarr/pathguide/issues/19)已發布，路標訓練、快照／worker／registry／更新尚未實作或部署。新增路標用途獨立於A物件認錯／漏認，不能直接擴用現有照片同意、十類coverage或A／B模型namespace。基本本機路線不依賴此服務，普通重行不累積影像；只有明確改善模式才留有界候選，真人行程後核實。

擴充時沿用UID／App Check、purpose及consent epoch、request／revision、SHA／generation、到期／撤回／刪除契約；提交另綁route／version、trip、candidate及review revision。只收另同意的必要已核實資料，不自動上傳全部記憶或影片，不跨UID混訓。原預測與人工答案分離；覆核A物件的現有API不冒充路標真值服務。

先人監督的單批實驗與效益比較，再接排隊／worker。不可變快照及owner＋snapshot＋config去重，單owner有效lease、取消／恢復及預算檢查需可驗；不套用舊A模型03:00／50張三場景規則。真實provider、限額、時限及並發未配置不提交付費GPU，本次也未開啟任何服務。

核准registry／offer綁本人scope、模型／index／profile SHA、訓練來源及獨立評估。若特徵空間變更，先由合法原始關鍵幀重建相容索引；缺資料保留舊組合。導航停止後完整驗證並原子切換model＋index＋profile；失敗回退完整舊組合，不將不同特徵空間互相比。撤回阻止新快照、在途發佈及新下載；受影響候選停用／回退，不聲稱已訓練權重可精確移除單張影響。離線副本限制明示。

服務驗收沿用Emulator外部權限／revision／重試／撤回先例，新增核實提交→snapshot→worker→評估→offer→App更新／回退的整合邊界；資料不足／不合格不出offer。模型hash改變、job完成或收到照片均不是品質證據。私人原圖、權重及評估內容不得上共享Git。

### 本輪核對的服務邊界

Functions來源現有16個export：原有computeWalkingRoute、getPhotoConsent、setPhotoConsent、submitPhoto、listPhotoProgress、deletePhotoAccountData、expirePhotoCandidates、removeLatePhotoObjects，加上submitPhotoIssue、getPhotoIssue、getPhotoReviewItem、submitPhotoReview、withdrawPhotoIssue、listPhotoReviewQueue、listPhotoReviewHistory，另有describeScene。問題／覆核API及工作台只完成本機／合成驗證，預設關閉、未部署；容量／抽覆、snapshot、排程、GPU worker、registry及私人下載尚未接通。本機照片／Google導航開關未設，沿用false；iPhone MapKit獨立。

照片部署最近證據為[2026-10-23紀錄](../verification/baselines/2026-10-23.phase4-verification.json)，不能當今日雲端清單。每日03:00、50張／三場景是規劃條件，未有運行中的排程；付費GPU不提交是目前政策與未建服務的狀態，不能稱已有經驗收的預算阻擋器。

### 目前問題：A10改善流程與發佈界線（2026-10-31）

本機兩個4 epoch候選及免費T4的6 epoch候選均未通過品質比較；訓練／保存／評估可完成，不等於模型變準。現階段問題是資料及驗收證據不足，未有可發佈的新權重；沒有新registry／offer、App模型更新或私人訓練服務。詳細問題及數字見[Dataset目前問題總結](DATASET-REVIEW.zh-HK.md#目前問題總結2026-10-31)。

Colab在本次明確授權後掛載Drive，固定run `20261030T162638Z`已完成，候選、設定、evaluation及summary保存在原擁有者的`PathGuide/a10-repair-20261030-v1/runs`。只新增56張既有CC BY 2公開來源照片；私人legacy影像沿用已有壓縮檔，未重新上傳、未進共享Git。原run及B11未操作；這次掛載授權不等於私人訓練服務的永久授權。

後續先完成資料覆核與獨立驗收定義，再決定下一個修正實驗。Colab只作互動實驗，不能冒充B06可靠無人worker；付費GPU仍停用。LLM用量主要來自改程式、看圖及讀工具輸出，訓練迴圈不呼叫LLM；雲端運算不會自動減少token，採批量執行／最後摘要以減少中途讀取。本次review整理沒有新增訓練或部署。

歷史隔離smoke不是App服務部署證據。既有回報／工作台以本機及Emulator驗證為主，正式部署及真人閉環仍待確認。

<a id="data-contracts"></a>
## 3. 資料流與實作契約

2026-11-08手機首次實試：Auth／App Check有效；503約1.635秒，後續429。帳本count=1、halted=true、inFlight=false、usage未知；保留2458 microUSD估算，不能宣稱已扣款。現有錯誤統一為unavailable，未保留上游HTTP狀態／傳輸分類，故不能據此斷言Key錯誤、端點故障或模型不可用；本機無憑證GET models可連通且401，只證明本機DNS／TLS／HTTP，不能代替雲端認證與模型驗證。先核對供應商usage及改善安全錯誤分類，未核清不重設試驗或付費重試。

2026-11-08診斷修補：舊503紀錄缺上游分類，不能憑推測解除帳本。新增顯式SCENE_PROVIDER_PREFLIGHT=true後端啟動診斷，只GET固定香港/models、10秒逾時、不讀response body；輸出HTTP數字或allowlist傳輸分類，不送圖／prompt、不生成、不讀出Key，不改試驗帳本／額度。預設不啟動，診斷完移除開關。新增兩項mock，連同場景／帳本24項通過；部署後實際結果另記機器證據。官方QwenCloud區域／模型文件確認香港域名及qwen3-vl-plus；此確認不能證明所存Secret具正確區域及權限。

2026-11-08診斷部署實測：後端使用現有Secret GET香港/models回200，匿名callable仍401，帳本仍1次／halted且無inFlight。這只證明模型清單端點認證，不能證明圖片推理成功或帳戶無計費限制。補上後續失敗的安全分類：只記HTTP狀態數字或allowlist網絡碼，仍不保留上游body／Key／圖片／回答；25項離線測試通過。

2026-11-08供應商根因核對：已登入QwenCloud香港PAYG Usage／Logs；唯一qwen3-vl-plus請求在香港時間04:04:02回HTTP400，Request Details明示Model.Unsupported，latency 0.02秒，usage為「—」，成功0／請求1。這是模型服務拒絕，不是手機斷網；後端原將非429上游錯誤歸unavailable→503，令UI誤導。官方仍列香港支援此model，不能直接斷言Key錯誤或帳戶欠費；具體alias／workspace／provider配置需供應商確認。不把usage「—」或控制台四捨五入US$0.00當零費證明，帳本不解鎖、不新增推理。

### 場景描述服務：目前契約與限制

最近部署證據：Firebase pathguide-dev的describeScene，asia-east2、Node22、40秒、maxInstances2；固定新加坡 `https://ap-southeast-1.maas.qwencloudapi.com/compatible-mode/v1`、qwen3-vl-plus、Secret Manager v2，provider preflight關閉。本輪文件整理沒有重新查雲端、部署或呼叫模型。證據見[內容診斷](../verification/scene-content-detail-20261109.json)及[最近許可](../verification/scene-100-five-days-20261109.json)。香港端點及未部署步驟已被取代。

Google身分、expectedUid、App Check、指定帳戶、active profile及account_deletions guard維持。私人Profile使用已註冊的開發驗證配置；正式DeviceCheck仍待驗收，不能把私人包或token上傳公開Release。

單次v1送當前有界JPEG，回兩至三句；v2帶overview／update，首次兩至三句、更新一句，含observations。輸入≤512KiB、長寬≤1280，伺服器剝EXIF後縮至512px；不接受client URL、prompt、模型或Key。固定非串流、非thinking、max_tokens512，body≤32KiB；整段驗證完成才回有效內容，拒絕不交局部文字或補發修復請求。

category僅person／door／stairs／table／chair／passage／vehicle／sign／other，position僅left／centre／right。同類同位置不可重複，detail≤40字且不用句末標點；prompt只要求最多三項重點，validator仍容許最多六項。物件／食物／顏色的指定米／層詞例外與手機同步；數字、距離、樓層、目的地、安全、方向指令、建議及簡體字限制保留。固定text／observation分類只報首個類別，不保存命中字、原文或位置；舊text-content不能追溯細分類，未確認第33／34次實際觸發詞。

transaction先預留，再呼叫供應商；累計上限100、總估算額500000 microUSD、下一次保守預留2458 microUSD，窗口上界五天，一次recovery仍一天。v1冷卻45秒、v2三秒；這是限流而非定時上傳。跨日／登入／開關不重設帳本；一在途、重複ID、預算預留不足、到期及未知用量均停止新分析。新設定fingerprint不符即拒絕，許可修改須明確批准及審計CAS；未知用量停止不能自動解除，拒絕嘗試不退花費。費用為工程估算，Firebase及供應商帳單另計。

`operation:status`只讀安全數值與最近三次固定結果，不讀provider key、取相、預留或呼叫模型。UTC日計數與跨日trial分開；lastResult／recentResults以頂層mergeFields整體替換，避免舊拒絕鍵殘留，其他counter保留。晚回覆寫數值前再驗active／刪除guard，不重建已刪帳戶。不存照片、描述或觀察原文；usage不完整保留未知，不填零。

啟用及私密配置沿用`scene_function.js`／`scene_entry.js`／`scene_trial.js`，App與後端預設旗標關閉，私人測試配置才開啟。後續部署只選describeScene，先驗來源、身分／App Check／帳戶／限額與Secret引用；不因文件中有命令而授權推理或續期。

### 錄路本機契約：目前格式

一般iPhone普通相機是基本來源，不要求LiDAR、YOLO品質通過、帳號或訓練服務。capture／Vision特徵／OCR／路線資料留本機；錄路與明確更新才存必要影像，普通重行不累積照片。影像觀察、路標身份、使用者標記、樓層來源、路線版本及重行提示各自有來源，不由外觀相似或按鍵自動認證位置。

captured schema4增加markType（landmark／junction／door／stairs／lift／toilet）及markDirection（left／right／straight，僅junction），並保留schema3的floorEvidence、floorAnchor及floorContextAnchor。schema1–3仍可讀；舊schema帶新欄位拒絕，舊App拒讀schema4，不靜默丟資料。當前方向只保存，重行播報未接；錄音／文字備註亦未接。詳見[核心證據](../verification/route-mark-core-20261110.json)。

復原移除最近手動標記及其未被其他記錄引用媒體，背景節點保留；跨過被刪節點重接的路段保持未確認，不因復原認證新路段。樓層未知可存草稿；沿用來源不是逐點真值，改樓層／設備或發現矛盾須撤回相關確認。重行仍要新鮮影像、版本／方向／樓層及歧義檢查，不能只讀保存的左轉字樣就導航。


### #18 樓層上下文及必要位置確認（2026-11-06，1.8.0+15候選）

在#17自動草稿上，明確按樓層按鈕會補拍有身份的確認點；其後候選只「沿用上下文」，與此點確認、整段核實及未知分開。確認面板開啟時只取最近10秒內分析完成的最多5個樓層文字候選作快照；G／1F／2F／3F快捷按鈕、其他樓層選填及「唔肯定繼續草稿」均可讀屏，未接App語音輸入。轉層入口可選升降機／樓梯／扶手電梯補拍；入口之後撤回目前上下文，到出口須明確再確認。文字矛盾（即使相片重複）、未知、暫停、背景、保存或重開均不沿用目前樓層；過往證據保留作歷史，不等於現在位置。

樓層來源始於captured schema3；現行有標記路線採schema4，記floorEvidence（unknown／confirmed／inherited／segmentConfirmed）、floorAnchor及確認點角色。schema1／2仍可讀，沒有來源的新舊語意不混用；舊App拒讀schema3，不能靜默丟掉來源後變完整路線。沿用或整段核實必須引用較早的有效確認點、相同樓層身份／標籤，不能跨非步行設備；未知來源／自指／缺anchor／不符樓層拒絕。schema1／2帶新來源欄位亦拒絕，避免降格丟資料。原加密、媒體配額、CAS、舊版／回退及刪除不變；新版本引用舊照片的捕捉版本不改義。

沿用樓層的點仍不完整。站定暫停後可明確核實「由確認點起這一段全部同層並按錄製方向實際走過」，只核實該界線內的步行段，保留整段確認來源；不核准其他確認點以外的未知段或轉層連接。轉層連接仍須明確修正確認，不能只憑出口樓層自動認證設備／路徑。改名不改樓層來源；更改確認點／中間點的樓層或路段種類會令相關沿用資料及確認失效。這是錄路上下文，不是已定位或每點真值。

本輪516項Flutter、54項原生、analyze及兩軸覆核已通過；涵蓋G確認→自動沿用→未核實不能啟用→整段核實→schema3加密保存／重開、轉層／矛盾／未知撤回、修改來源點失效、舊格式及錯誤新格式，以及中英文320×568兩倍字體實際樓層／設備按鈕流程。簽署及交付狀態見verification/floor-context-20261106.json；1.8.0+15已通過簽署建置／簽章／模型雜湊核對，分支及不可變tag／prerelease核對後已更新安裝／正常啟動。場地／無LiDAR／VoiceOver真人及自動取樣覆蓋、物件提示／VLM／P4語音仍未驗收，不把本片當#16全完成。

### 自動草稿錄路契約（已隨後續版本交付，參數未校準）

使用者已確認：樓層無法確認時繼續未確認草稿，稍後補資料。#17先接開始一次→試驗每5秒候選→光線／細節篩選及去重→自動編號候選路標→結束自動命名草稿→明確保存／重開（改名選填）。本片所有自動樓層及路段保留未知／未確認，不能啟用為完整重行路線；相似度不是位置證明。品質screen只在最長邊64px評估曝光15–240及鄰接亮度差≥4，與上一保留特徵distance<2或同JPEG則略過；這些是未校準工程參數，不是已凍結選幀政策、清晰度或轉角覆蓋保證。

沿用單相機／單工作、取消與世代隔離；不追補忙碌期間取樣。自動最多48視角，沿用原64上限並預留16視角手動補記；達上限明示停止自動取樣。手動標記／選填編輯與待重試輸入期間暫停自動取樣，背景／離頁／暫停／保存／dispose停止排程，失敗停下供明確繼續；沒有自動刪除／上雲。僅保留選中候選JPEG／特徵，重行仍不存新照片。自動名稱非AI語意名稱，標記及繼承樓層來源已接，完整事件與重行驗收仍屬後續；重要轉角／轉層仍須手動補記。不是只增加Timer便稱自動建路完成。

自動草稿已隨後續手機版本交付，現為1.11.0+29；原工程證據見[自動草稿](../verification/automatic-draft-20261106.json)。必要樓層確認、標記與免打字保存已補入，實地轉角覆蓋、選幀參數、模型比較及完整真人任務仍未驗。

#### P3-B特徵及候選資料契約（2026-11-05，工程及手機fixture已驗）

**2026-11-06基本版硬件範圍已確認（#16）：** 普通相機為基本來源，先提供物件名稱、畫面方位及本機路標重認，精確測距選填。缺ARKit／LiDAR／有效深度不得成為基本路線資料讀寫或物件名稱提示的服務前置；無距離保留未知，不填零或由框／VLM推定米數。畫面位置、手機姿態與量測距離的來源／有效性分開；有選填深度時仍核同幀及新鮮度，過期撤回，不將一般觀察升格碰撞或通行答案。沒有新增schema、endpoint、雲端處理或資料同步，既有加密、版本與相機owner規則保留。

**2026-11-06自動錄路邊界（[規格#16](https://github.com/actiondarr/pathguide/issues/16)）：** 候選照片、正式路標身份、可後補名稱、樓層上下文及確認來源須分開。自動取相／沿用樓層不新增human_approved或已確認路段。約5秒取樣已有工程設定，選幀仍未校準；未知樓層已確認可繼續未確認草稿。有標記路線採schema4，舊版相容依上方契約，不作靜默遷移。沿用版本相容、CAS／epoch／刪除／quota、加密與備份排除；現行4／64視角上限不得自行放大，需先提出有界保留策略。私人路線不新增上雲、同步、訓練或外部匯出授權；抽特徵／OCR不更新權重，本地VLM候選亦不新增雲端endpoint。補名／樓層變更須遵守版本及穩定版保護，未確認轉層不得導航。現行服務狀態不變。

P3-B原生核心產生真正Vision feature print revision1，固定upright JPEG／scaleFit；有界secure archive外包schema1、featureRevision=vision-featureprint-v1、preprocessRevision=upright-jpeg-v1及Vision revision，整包≤64KiB。比較驗包內／呼叫版本及VN observation實際revision，損壞或不相容不回部分結果；距離不是正確率。P3-A仍把完整feature blob作opaque bytes加密並綁SHA，未更改已存synthetic v1或金鑰。

OCR按runtime版本／語言能力提供有界文字候選，永不直接寫actual floor。Dart核心把同building/floor/node多視角合併後判斷未知／歧義／錯層；需fresh ticket加明確樓層與方向確認；跨層出口還要綁定已錄exit node／connector role，房間路標不能代替出口。工程門檻8／gap2／5秒不代表行走可靠，caller須傳保守frameAge；camera／store／平台通道及旅程UI接線由P3-C處理。沒有新endpoint、雲端服務、私人照片採集或訓練。驗證及硬件fixture結果見[P3-B證據](../verification/codex-p3b-landmarks-20261105.json)。

#### P3-A媒體版本、容量與裝置政策（2026-11-05）

新增schema2 captured及獨立加密JPEG／feature blob，schema1 synthetic、原目錄／路線金鑰／既有AAD保持可讀，既有route身份不改source。node/view引用綁明文SHA及byte count、JPEG實際尺寸、保存UTC、捕捉來源元資料與feature/preprocess revision；catalog綁每個版本／blob的cipher SHA，媒體AAD另綁route/version/media SHA。儲存層把feature視為有revision的有界opaque bytes；Vision提取及重認其後由P3-B／C接入，但結構啟用不等於實地導航通過。

明確錄製／更新才寫媒體，重行read/readMedia不增加影像。先作完整引用／JPEG／SHA及配額預檢，再寫各加密暫存／版本，最後切catalog；中斷、取消、刪除及未知提交結果沿用CAS／epoch／tombstone語意。刪除涵蓋所有媒體版本；明確歷史清理保留active／有效fallback／draft的blob引用，損壞但仍被引用的檔案不靜默清走。

固定JPEG512KiB、feature64KiB、node4視角、route64視角、JSON256KiB、route8版本；route磁碟64MiB、整庫256MiB，連加密開銷、草稿／歷史／暫存／catalog計算。整庫上限內留最多2MiB供catalog維護；額滿保留穩定pointer、拒絕新增，沒有自動上雲或刪歷史。凍結設定見[媒體儲存政策](../configs/planning/codex-p3a-storage-20261105.json)。

iOS原生通道只接受App support路線／隔離probe命名空間及已知檔名，拒絕路徑穿越、symlink、任意穩定檔覆寫及超大寫入。新檔建立即Complete保護，寫入／rename後重設備份排除，既有P1只補政策不改密文。金鑰沿用WhenUnlockedThisDeviceOnly／不同步；資料屬裝置本機且排除OS備份，不承諾重裝／跨裝置還原。依據Apple [檔案加密與保護](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files)及[備份排除屬性](https://developer.apple.com/documentation/foundation/urlresourcevalues/isexcludedfrombackup)，仍須用真機檢查實際屬性，不用Simulator不可用的保護等級冒充通過。

工程probe只用人工生成JPEG及opaque feature fixture，目錄與Keychain purpose均獨立，分app process寫入／重開／刪除後清理probe；只回報屬性／計數及結果，不讀取或上傳私人照片／金鑰。此票沒有endpoint、雲端部署、照片訓練或新權重。實際結果見[P3-A證據](../verification/codex-p3a-route-media-20261105.json)，完整錄路／定位／導航及人手驗收留P3-B～P5。

#### 跨樓層步行導航資料與服務契約（P0合成子集已實作）

本節是Frontend P0–P5的資料及生命周期邊界；下表完整格式仍不是雲端API或已完成的持久schema。N0的RouteMemory／LandmarkNode保持無floor，獨立P0新增FloorRef／FloorNode／FloorEdge／FloorRoute、FloorObservation、PerceptionFrame、GuidanceEvent與CrossFloorController。FloorRoute只接受building一致的相鄰有向邊，walk不能跨floor，其他邊需connectorId；不推斷反向。觀察分location／perception序列，綁journey／generation／routeId/version／clockEpoch及單調捕捉時間；跨session、版本、方向、未來／過期回覆被拒。P0固定p0-synthetic-v1，沒有圖像blob、模型推論或真確認來源；正式序列化／加密／ownership於P1、取幀與來源版本於P2–P3、真播音於P4補齊。不能把mock的version=1當正式持久格式。

P0分開expected／candidate／actual floor；先確認fresh樓層候選，再確認fresh出口及方向才更新actual。轉層撤回舊樓層及事件；障礙優先級3覆蓋路線級2，過期frame轉perceptionUnavailable，不復播舊指令。缺有效深度不允許米數；分類與深度信心未接真模型。背景／暫停／刪除作廢兩支序列，前景只刷新控制，不恢復導航；子頁owner dispose亦作廢。2秒／500ms只是合成測試窗，畫面時鐘凍結，不能接真實行走輸入。沒有讀帳戶、寫磁碟或新增endpoint。27項P0／全App380項及analyze通過，見[P0覆核](../verification/dsh-p0-cross-floor-20261104.json)。

| 規劃資料 | 最少欄位／規則 |
|---|---|
| RoutePackage | schemaVersion、routeId／routeVersion、device-local owner scope、buildingId、路線名稱、起終點、方向變體、nodes／edges／observations索引、feature／preprocess版本、draft或可重行範圍、manifest SHA。穩定版不可變，active pointer另存 |
| FloorRef | buildingId＋穩定floorId、顯示名稱、確認來源與時間；未知為null／unconfirmed。G、M、UG、B1等只是標籤，不按字串／高度自動排序 |
| LandmarkNode | 固定nodeId、FloorRef、名稱／固定objects、內容版本、不同方向／光線觀察引用；相似外觀但不同樓層不可合併 |
| RouteEdge | edgeId、from／to node、walk或stairs／elevator／escalator類型、實際已走方向、通行／關閉狀態、connectorId、來源／目的floor引用；實測長度可空。walk不能無聲跨floor，缺轉層端點的edge不得導航 |
| FloorTransition | connectorId、入口／出口node、來源／預期目的floor、目前已確認floor、設備類型、方向／可行性來源及版本。預期目的地與目前樓層分欄，升降機可跳層，樓梯平台不等於樓層 |
| RouteObservation | observationId、journey／session／generation、sequence、單調捕捉時間及clockEpoch、保存UTC、source／方向、routeVersion、frame／JPEG SHA、feature request revision／preprocess／尺寸、OCR候選、可選pose／tracking／相對高度；自動候選不寫成確認答案 |
| MatchResult／FloorEstimate | matched／unknown／ambiguous、候選node與floor、不同來源證據、當前版本／時間／方向、有效期／失效原因。跨樓層續行需已確認floor及出口路標；路線先驗不壓過相似樓層歧義 |
| PerceptionFrame | 同幀session／seq／捕捉時間、模型SHA／profile、detections及短時track、可選深度／pose及其有效性；分類score不是深度信心。缺距離為null，不使用未知class ID代填 |
| GuidanceEvent | eventId、journey／generation／routeVersion、eventKind、priority、目標node／floor／track、來源seq、monotonic expiry、reasonCode及本地化參數。文字由受控規則產生；AI自由文字不直接成步行指令 |

轉層狀態：walkingOnFloor→approachingConnector→transitioning→awaitingFloorConfirmation→relocalizingExit→walkingOnFloor；任一步可到unknown／paused／cancelled。離開設備不代表到達預期層；錯層、相似出口、AR重設、氣壓漂移或OCR衝突（包括路線未錄但有明確樓層格式的字樣）會阻止續行。原則上可在已確認的中途路標重定位，不把N0回起點mock變成正式跨層恢復策略。回程需另驗視角／方向，不能默認所有連線雙向可靠。

原生CameraCoordinator管理取用權；新增RouteObservationSource與WalkingPerception adapter，但不是另開競爭相機。現有VisionFrame只有偵測結果，新的原生觀察契約另建，保持舊辨識／菜單／測距方法語意。Swift處理最新幀偵測／可用深度及節流後關鍵幀OCR／features，Flutter只接必要精簡事件；session、取消、時序與停止屏障由Codex維護。普通ARKit與LiDAR分開能力檢查；無AR／無Motion授權時仍可明示路標及樓層確認。

旅程級GuidanceArbiter接路由及感知：有效急需障礙／感知失效提示優先於當前轉層／轉彎，再到一般環境。每次派發及播出前重驗來源、世代、版本與有效期；停止／背景／新路線作廢舊事件，恢復後不補播queue。VoiceOver／TTS擇一路，現有僅environment／navigation的coordinator需擴充而不能宣稱已具危險優先。

##### 本機保存、刪除與資料用途

- 選App私有route-memory命名空間，以已裝path_provider、cryptography的AES-GCM及flutter_secure_storage／Keychain作裝置端版本保存；路線金鑰與照片佇列分開。此為新store，不直接複製目前會刪無效照片的queue實作。
- 新版本先寫暫存blob與manifest，核SHA／schema／引用完整性，最後原子切換active pointer；中斷保留最後穩定版。draft未確認轉層不得顯示整條可導航。清晰關鍵幀與feature blob只保存用途必要部分，原始影片／持續音訊不預設保存。
- feature revision／前處理不符時拒比；可從仍獲授權的本機關鍵幀明確重建features為候選新版本，不能無聲改永久node、floor或路線。無法重建時提示補錄，不猜相容。
- 刪除先作廢route epoch及所有observer／語音／儲存回覆，再移active pointer及路線檔案；原子寫入／回退／刪除操作串行，晚到寫入不能復活。重啟不得將殘存暫存檔當可用路線；不刪不相干照片、收藏、模型或其他路線。
- 訪客基本版是明示的本機路線庫，不綁Google登入，不因登入自動遷移／上傳。若日後提供UID私人同步，須獨立owner namespace、授權及登出／刪除規則；不複用現有personal_model_photos同意。裝置金鑰遺失／重裝恢復限制要在P1驗證並說明，不能默認已可iCloud／跨裝置還原。
- 本輪不新增Firebase endpoint、VPS、藍牙信標、LLM每幀推理或付費GPU。可選雲端仍依原同意／provider／配額計劃；已建立本機路線不以雲端回覆作繼續行走前置。室外新搜尋／重新規劃斷網能力另驗，不因室內本機運作而承諾整個MapKit流程離線。

##### 實作與證據責任

Codex直接維護相機、資料、語音與版本接縫；工程來源／測試、裝機、真人場地及視障任務各自記錄。舊DSH交付方式與付費票據不再作現行工作指令，不重新發送請求。

<a id="2-現行照片流程與資料"></a>

### 現行照片流程與資料

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
| 問題／覆核 | 已有服務程式：users/{uid}/photoIssues/{reportId}及其revisions／requests；部署未啟用 |
| 快照 | 未實作；不能直接把approved回報當訓練或發佈許可 |
| 工作／registry | 規劃以ownerUid綁定，App只讀本人進度 |
| 私人模型 | 規劃 personal_models/{uid}/{modelVersion}/，僅授權相符UID |

<a id="3-管理員覆核與自動批次覆核api本機驗證部署排程未啟用"></a>

### 管理員覆核與自動批次（覆核API本機驗證；部署／排程未啟用）

管理員透過受權限保護的工具補漏修框；原始預測與人工答案分開。保存覆核者、時間、定義、授權及影像／標註雜湊。只有核准且用途仍有效的資料可進快照；流程依 [Dataset覆核](DATASET-REVIEW.zh-HK.md)。

#### 最小覆核工作台與問題追蹤

先指定受權管理員負責接件／初覆、複核角色負責抽查及爭議裁定；尚未指定處理者、沒有覆核容量或覆核定義不完整時，保持待處理。小型試驗可由同一管理員分兩次覆核並記限制，重要爭議需另人裁定；AI預標或Codex視覺篩查不等於human_approved。

工作台最低提供：私人原圖、拍攝時預測／模型與profile版本、問題主張、同源群組；修框／補漏／改類，逐類coverage及全圖檢查；退回／拒絕理由、編輯歷史、抽樣複核與待辦排序。只有來源／用途有效、幾何及映射有效、指定覆蓋類別全圖標完、無待裁爭議、reviewer及版本齊備才可核准。不能只把pending改approved。資料充分性與品質gate仍由Dataset判定。

| 規劃狀態／操作 | 規則、責任及失敗後去向 |
|---|---|
| submitted→pending_review | 驗證成功才入待辦；以UID＋reportId冪等，傳送成功只顯示已收到。照片現有validated／pending不等於已完成人工覆核 |
| in_review→needs_information／disputed | 編輯綁expectedRevision，衝突回報並重讀，不覆蓋他人結果；歧義列明缺甚麼證據。使用者不補資料可保留待評估或撤回，不影響基本辨識 |
| in_review→approved／rejected | 核准固定annotationRevision、coverage、定義、reviewer／time；拒絕用可理解理由。晚到AI預測不能覆寫人工答案，修訂核准版本需新revision並重驗引用快照 |
| approved→development→candidate→evaluated→device_retested→closed | 每一步保存issueId、資料／模型版本及證據連結；訓練完成不是問題已解決。不合格可回development，與無效／授權撤回的終止狀態分開 |
| retryable_failed／cancelled／withdrawn | 網絡失敗以原requestId重試，核准修訂用新版本；取消／撤回即阻止新快照／工作，晚到事件不能復活。需人工裁定／權限失敗不自動無限重試 |

問題callable首版只接reportKind=misclassified／missed，與原照片的samplingTrigger、預測結果分開；App尚未呼叫。距離不對／文字配錯仍是後續契約，現有submitPhoto繼續只支援manual_report／low_confidence／scene_sample。距離回報另附自願提供的裝置／讀數／量測真值來源，文字回報另附OCR與配對修訂；無真值只算待查主張。任何AR幀、深度、序列或菜單影像用途須另明定，不能無聲擴大現有JPEG照片同意或將產品截圖當訓練圖。

保存每張實際處理時間、待辦量／最老待辦時間、退回／爭議率、複核不一致率及抽樣漏標；用途到期、撤回及刪除與工作台清理相連。抽樣複核先涵蓋每位reviewer／各問題類型及高風險類別，比例與放行規則在試驗前固定，低一致性重開相關批次。啟用前按人手配置待辦上限與告警；積壓達上限可停自動抽樣，手動回報明示待處理，不承諾即時修復，也不影響核心辨識。這些服務與指標尚未運行。

#### 已實作的問題／覆核API及本機工作台（2026-10-29，預設關閉）

程式：[photo_review.js](../backend/functions/photo_review.js)、[review_policy.js](../backend/functions/review_policy.js)。B03的接件／覆核契約已接本機工作台；待辦與修訂歷史以相同權限檢查讀取。沒有實作容量／抽樣複核服務、訓練、模型更新或已解決案例。

| callable | 身分／主要輸入 | 行為與界線 |
|---|---|---|
| submitPhotoIssue | 本人Google＋App Check；expectedUid、reportId、photoId、consentEpoch、reportKind、appVersion、modelSha256、inferenceProfile | 綁現有validated且未到期的私人JPEG；UID＋reportId冪等，每照片限一件。只收misclassified／missed，空預測可收漏認；回pending_review／revision=0，沒有自動判定FP／FN |
| getPhotoIssue | 本人Google＋App Check；expectedUid、reportId | 讀目前status／revision、photoId／reportKind及退回理由，供重試／撤回；不回覆核者身份、標註草稿或原圖 |
| getPhotoReviewItem | 指定覆核人員；expectedUid、ownerUid、reportId、選填includeImage | 回拍攝預測／模型、回報主張及目前標註；includeImage=true才以base64回指定generation且SHA相符的私人JPEG，下載後再驗角色／同意／revision，沒有公開下載URL |
| submitPhotoReview | 指定覆核人員；ownerUid、reportId、requestId、expectedRevision、action、humanReviewed=true及expectedUid | start接件，save另存標註，needs_information／dispute／reject須理由，approve由另一位adjudicator複核。衝突回aborted及currentRevision，不能靜默覆蓋；AI無權透過預測欄位覆寫標註 |
| withdrawPhotoIssue | 本人Google＋App Check；expectedUid、reportId、requestId、expectedRevision | 撤回問題並作廢核准指標；舊請求重試只回目前狀態及原appliedRevision，不恢復舊approved狀態。另行撤回全部照片用途仍走setPhotoConsent |
| listPhotoReviewQueue | 指定覆核人員；expectedUid、status、limit（1–25）、選填cursor | createdAt／隨機queueKey最舊優先；每件在交易內重驗同意、照片及刪除guard，跳過撤回／過期／本人回報。游標只含時間、隨機key及status，不含UID／路徑；無效候選可能造成空頁，仍可繼續下一頁 |
| listPhotoReviewHistory | 指定覆核人員；expectedUid、ownerUid、reportId、limit（1–20）、選填beforeRevision | 由新到舊讀不可覆寫修訂及當時標註；每頁重驗角色、用途／epoch及期限，不因曾讀過原圖而略過檢查 |

服務須明確設定PHOTO_REVIEW_ENABLED=true才接請求，預設false。覆核者須同時具token及當前Auth的photoReviewer=true custom claim、未停用／撤銷登入，以及server-only的photo_review_operators/{uid}紀錄（enabled=true，role=reviewer或adjudicator）。紀錄及問題／revisions／requests由現有規則一律拒絕客戶端直讀／寫，角色只可由受權Admin設定；本輪未指定人員或開啟旗標。不得自覆本人的照片；此首版採兩位人員分工，尚未實作同一管理員兩次覆核的選項。

save的annotation含taxonomyVersion=pathguide.a.mixed10.v1、definitionVersion、sourceGroup、coverage（專案ID）、fullImageReviewed及annotations；每框只收projectClassId／cx／cy／w／h且須在原圖內。核准要求十類全coverage＋全圖人工確認、有效定義／來源群組欄位及不同標註者的複核角色。humanReviewed是受權操作者的聲明，服務不能自行證明人已逐圖檢查；來源定義、分組真實性及覆核抽查仍須人工驗收。爭議保持disputed，本輪無自動裁定；無development／candidate／closed操作，核准不等於已修正或可發佈。

每個變更以單一Firestore交易保存目前revision、不可覆寫的revisions/{revision}、requestId雜湊收據及照片進度；原圖generation／SHA、原預測與回報主張不改寫。重開已裁定結果須adjudicator及理由，產生新revision並撤銷當前核准指標，舊核准修訂保留。未實作snapshot引用失效服務，因此不能將這些記錄接入真實訓練。

全部回報只限既有personal_model_photos用途，sharedTrainingAllowed=false，核准scope=personal_development_only；不授予共用訓練權。模型SHA／inferenceProfile等新增拍攝資訊標為client_reported，不能作已驗證的手機執行證據。距離／文字回報、AR／菜單影像／深度、私人模型發佈另訂契約。

問題、修訂及重試收據沿用原照片30日expiresAt；核准不延長保存。每次讀／改先驗有效用途、epoch、帳號刪除guard、照片到期及generation／SHA綁定；到期工作遞迴刪問題及子記錄，再刪指定generation原圖及照片。帳號刪除沿用UID樹遞迴清理。撤回即阻止服務存取，實體資料按刪除／到期流程清理，不宣稱即時抹除所有副本。

本機測試證據見[backend-photo-review.json](../verification/backend-photo-review.json)。使用Firestore／Storage Emulator及合成JPEG，Auth當前角色查詢用測試替身；不代表真實App Check閘道、Auth撤銷傳播、真人覆核、工作台的真人操作、積壓控制或雲端部署已驗收。啟用前仍須指定人員／定義／capacity、完成真實角色／App Check／工作台及刪除驗收，再選一個真實問題由Dataset接續。

#### 本機覆核工作台的操作與連線

來源在backend/workbench/，沒有新增對外網站或Hosting部署。提供狀態篩選／最舊優先／分頁、私人原圖與唯讀預測框、拖曳新增框、數值改框／改類／刪框、同源群組與定義、逐類coverage及全圖確認、接件／退回／爭議／拒絕／雙人核准，以及分頁修訂歷史。不能由此直接訓練、關單或發佈模型。

在backend目錄，使用Node22、Java21與已安裝依賴：

```sh
pnpm workbench:build
pnpm workbench:demo
```

Demo只允許demo-pathguide-phase3及127.0.0.1的Firestore／Storage Emulator，啟動後於[本機工作台](http://127.0.0.1:4176/)提供三張明示合成JPEG及兩個模擬人員。它呼叫同一createPhotoReview服務，角色／Auth為測試替身，不修改真實PHOTO_REVIEW_ENABLED、不讀真實帳戶或照片；重開只重設workbench-demo專用UID的合成資料，不清整個Emulator。pnpm的esbuild安裝腳本保持false；由已安裝平台binary建置Firebase瀏覽器adapter已通過。

正式連線另用pnpm workbench:serve。須先在ignored的backend/workbench/config.local.json填Firebase Web公開設定（firebase.apiKey／authDomain／projectId／appId、選填messagingSenderId）及appCheckSiteKey，authDomain須為相符projectId.firebaseapp.com。server拒絕管理員私鑰或其他未知欄位；只供本機靜態頁，正式呼叫由瀏覽器Firebase SDK經Google登入及App Check直接送往asia-east2 callable，不經本機Admin代理。登入用inMemoryPersistence，沒有token貼上欄位，不把token、原圖、標註或草稿寫入localStorage／IndexedDB。

正式使用前仍須部署新增Functions及photoIssues的status／createdAt／queueKey複合索引、指定兩位人員、固定定義／抽覆規則及人手容量、登記正式Web App／App Check及核對IAM／授權網域，最後驗真人Google登入、App Check閘道及撤權。這些尚未執行；本機可操作不代表正式服務已可用。

儲存以原requestId重試不明結果；revision衝突保留本機草稿，重讀及比較後才明確再提交。換帳號／登出／離頁會清除原圖URL、狀態、標註及隱藏DOM；舊帳號的遲到回覆不套入新畫面。草稿及待確認請求只在記憶體，重開後不保證保留，須重讀伺服器；已取得的影像離線時不能保證即時得知遠端撤回。部分coverage可保存草稿，但工作台與服務均不讓它核准。

本機server只綁127.0.0.1，拒絕錯誤Host、跨站請求、非同源JSON寫入及超過256KiB的demo body；檔案使用白名單，回覆no-store及CSP。正式模式沒有demo寫入代理。瀏覽器已驗合成接件、完整coverage、數值修框保存、拖曳畫框保存、換人核准與固定歷史；390px畫面無水平溢出，1280px雙欄版面已目視。證據在verification/backend-photo-review.json及verification/ui/backend-review-workbench.jpg；這不是實拍人工覆核、資料獨立性或品質改善證據。

#### 先完成一個可追溯修正案例

首例可選「某類門經常漏認」，實際issue與資料尚未選定，不能宣稱已完成。人工回報→獨立真值覆核→同源分組→用途有效的開發快照→候選→與現用模型在另一批未訓練場景比較→手機重測；每步用上述ID及版本串起。私人資料預設只在本人授權範圍，若要共用模型使用須另有共用訓練授權；授權不足仍可做私人研究，不能混入共享產物。完整驗收方法見Dataset。

第一個案例先人工觸發及mock驗錯誤／取消／回退，證明流程有效後才接自動排程。私人微調另外先與現用及改善共用模型做對照；若額外效益不足或證據不確定，保持共用改善路線及本人資料隔離，不擴大每UID worker／registry服務。

#### 自動批次的後續啟用條件

每日香港時間03:00、每UID至少50張新增核准圖／三場景是後續規劃的排隊檢查起點，**不是樣本充分或可發佈的證據**。另須有Dataset預先固定的獨立實體／場景覆蓋、不確定範圍及任務指標規則；未達即資料不足／待評估。排程需在修正案例、私人效益、mock閉環、權限／刪除與預算驗收通過後才啟用，目前未運行。

採Firebase記錄／排程、私人Cloud Storage及GCP Batch容器GPU worker。首版私人微調限相容十類A與獲授權基礎資料回放，不混別人的私人照片；B保持獨立共用模型。

工作保存jobId、ownerUid、快照、基礎權重、設定／容器版本、run ID、checkpoint、心跳、取消旗標、評估及錯誤。以UID＋快照＋設定去重，交易取得lease；同UID不得同時訓練兩份。恢復使用同一快照，資料改動另建run。

狀態區分資料不足、待覆核、queued、running、evaluating、ready、failed、cancelled；評估不合格不能寫ready。門檻見Dataset覆核，不憑訓練成功自動發佈。現用十類gate=false只屬試驗，不自動升格為已核准基礎模型。

**GPU預算待定，付費提交預設關閉。** 先完成模擬worker的成功、失敗、重試與取消。部署前設定專案、可用區域／GPU、單次時限、每日額度、併發及預算；缺設定即拒絕提交，不能用告警冒充停止計費。

<a id="4-私人發佈自動更新與回退待實作"></a>

### 私人發佈、自動更新與回退（待實作）

訓練 → validation比較 → 凍結候選／獨立驗收 → 格式及映射檢查 → 核准registry → 本人授權下載。不合格保留原版本，報告同時寫改善與退化。

發佈記錄含ownerUid、jobId、snapshot、模型與manifest雜湊／大小、taxonomy、相容App及評估版本。私人發佈envelope與現行內置format:1分開，不假稱目前parser已支援新欄位的完整驗證。

使用者可另行預先同意自動更新；未同意則手動選擇。僅App前景且辨識／導航等相機任務停止時下載至暫存，驗UID／雜湊／映射／相容性，試載入後原子切換。保留上一個私人版本與內置備援，失敗回退。此決定取代「每次都必須手動啟用」。

#### 能載入、效果合格及使用者接受分開記錄

規劃registry分候選／評估通過／核准可提供／撤回版本，裝置另外記下載／試載入／啟用及使用者拒用狀態；載入成功不能改寫評估結果或滿意度。offer綁owner scope、modelVersion／SHA、evaluationProfile、資料／報告版本及有效期；宣稱改善必須對應Dataset同條件報告，更新說明列實際改動與限制。

| 失敗或回退情境 | 規劃處理與驗收 |
|---|---|
| 下載中斷／空間不足／SHA錯／不相容 | 保持原active pointer，暫存可清理／依版本重取；不重複排工作或假顯示已啟用。重開App核實最後有效版本 |
| 更新成功但體驗變差 | 讓使用者選回上一版或內置，在任務停止後原子切換；選填原因，未提供也可回退。記from／to SHA、profile、App版本、時間及結果；不要求上傳影像 |
| 拒用後再次輪詢／改名offer | App以UID安全保存scope＋SHA的拒用紀錄，呈現offer及啟用前均過濾；同內容換版本名仍不再自動提供／啟用，明確恢復才解除。服務端僅在本人另行同意同步偏好後過濾offer；本機無網絡亦可回退，未同步不保證跨安裝延續拒用紀錄 |
| 發佈者撤回版本 | 核准者提供原因與撤回版本；停止新offer／授權／重試，已下載裝置下次得知撤回時提示並停用受影響任務，閒置切到仍核准上版或內置。離線無法保證即時收到撤回，不宣稱已即時清除所有副本 |
| 切帳號／登出／授權失效 | 作廢下載與啟用世代，清UID私人快取，回內置；拒用及原因不跨UID。若同步偏好，另定本人存取、同意、到期與刪除，不新增默認行為日誌 |

拒用同一SHA只阻止該版本，不能自行判定所有後續候選失敗；新候選仍須獨立評估，不靠改名重新提供。模型回退與「部署、設定與版本回退」App程式的tag／重建／簽署回退分開。現有內置選擇器不等於此私人registry與撤回服務已實作。

App／共用模型完成後先推GitHub commit、tag／Release並核對，再安裝交付。私人照片、權重及含私人資訊報告留在受權限保護的儲存，不進共用repo；私人registry保留歷史版本供本人回退。完整版本程序見本檔「部署、設定與版本回退」。

#### 合成graph與正式路線的界線

舊12-node無向graph／N0只作測試夾具，未量測的layout不作米制座標或真實路線。正式錄路採有向連接、影像特徵版本與樓層來源；新增觀察不得自動改已核實場地或權重。未來共用地圖、同步與私人更新另需用途／版本／獨立驗收。

<a id="5-撤回刪除與失效"></a>
### 撤回、刪除與失效

- 關閉收集停止本機擷取／待傳；另提供個人訓練及自動更新控制，worker在排隊、取資料、續跑與發佈前重驗授權。
- 刪除先建保護、停止新工作／下載，取消並等待或隔離worker，再清理照片、標註、快照、第三方匯出及私人權重，最後移除身分。遲到事件不得重建資料。
- 現有deletePhotoAccountData只涵蓋第四階段；加入worker／registry後必須擴充，不能假稱已涵蓋未有資源。
- 室內深度、姿態、網格留本機；照片同意不擴大為持續影片、GPS或軌跡上傳。方向短片另行授權。

<a id="8-導航資料與使用說明發佈前草稿重點"></a>

### 導航資料與使用說明（發佈前草稿重點）

導航只在使用者啟動與App前景取得位置；暫停、背景或結束停止定位，不建立／上傳行走軌跡。Apple／Google會收到完成搜尋及路線所需查詢、起點／目的地；代理不持久保存完整座標／路線，診斷避免私人位置。

語音按鈕才收音；優先裝置端，線上服務先取得本次同意，不把導航或錄音加入模型訓練。收藏／最近十個地點在本機安全儲存，可清除，不跟帳號同步；Google項目以Place ID、使用者標籤與時間保存，再查地點。

路線可能有誤差、延遲或入口不符，不保證樓梯／升降機可用，不提供過路時機、室內樓層或鎖屏導航。接近終點仍需確認入口，資訊不代替白杖、導盲犬或定向技能。Android需已配置服務、網絡與適當權限。

供應商參考：[Google Maps條款](https://maps.google.com/help/terms_maps/)、[Google私隱](https://policies.google.com/privacy)、[Apple地圖條款](https://www.apple.com/legal/internet-services/maps/terms-en.html)、[Apple私隱](https://www.apple.com/legal/privacy/)。正式政策需補聯絡及變更通知方式，不能以本章冒充已公開條款。

### 裝置端深度契約（現行，非雲端服務）

2026-10-28 物件距離版：1.4.0+5延伸本機hk.pathguide/depth契約，start帶objects模式、threshold、已校驗的內置權重cache路徑／SHA／bytes／classIds／classes／inputSize；原生再次核對才建立模型。不是外部下載／私人模型offer，不新增Cloud API。靜態內置權重快取放App support的PathGuideDepth，以SHA命名；只寫共用模型，沒有照片／深度／pose／UID資料。背景停止會作廢尚未完成的準備或啟動。

物件事件status=objects，附同session／timestamp／ageMs、viewWidth／viewHeight／rotation及最多5個objects：專案class id、score、已裁切預覽box、reason，可用時另帶rangeM／planeZM／accepted／total／spreadM。score是物件模型分數，不是距離可信度或正確率；rangeM是框內代表表面的徑向米數。短時track ID只在Dart當次session作配對，不寫永久graph／觀察資料庫。原有sample準星事件保留，兩種模式不能混用米數。資料不持久保存／上傳；訓練照片用途／同意／配額及PHOTO_UPLOAD_ENABLED=false不變，無付費GPU工作。


2026-10-28 1.4.1+6修正版：物件本機事件新增samplePoint（當次預覽normalized座標）、validDepth／depthTotal與細分reason；前端展示原因與點數，不把它們當正確率。深度信心／量程／混合表面／過期門檻不變，僅改框內局部取樣選擇及遮擋檢查；取樣位置改變重新累積時序證據。本機不新增影像／深度記錄或Cloud API、照片上傳仍關閉，無GPU／訓練工作。使用者提供測試截圖未放GitHub／dataset。

### 自動模型調度的服務界線（新增方案，未實作）

意圖辨識與模型路由優先放裝置端，基本操作不新增雲端依賴。不同能力可由已下載的A／B／OCR／視覺語言模型執行；不要求使用者選模型名稱。現有服務沒有這個調度器或視覺語言模型下載服務。

模型包規劃另記能力、格式／runtime、語言、裝置相容性、SHA、大小及驗收profile。只向調度器提供已驗證且可用的能力；不可把A的class映射套到生成文字。大型模型首次下載顯示大小／可用空間，允許取消、重試及刪除；固定版本驗證後才啟用。具體模型／大小待選型，不能把第三方宣傳數字當本App需求。

自動選擇已載入的運算能力與私人模型自動更新是兩個操作：後者繼續遵守UID、同意、閒置原子切換與回退。路由失敗不默默轉雲端；若未來加入雲端，圖片用途及傳送另行同意。查詢影像預設僅暫存記憶體，不自動進照片訓練流程。

最小診斷記request/session、路由能力、版本、取消／超時／降級原因及耗時，不預設收集圖片／聲音／完整提問。驗收離線、未下載、損壞包、空間不足、遲到結果、切帳號及重啟；未接服務先mock，不開付費推理或GPU。

<a id="service-acceptance"></a>
## 4. 服務驗收規格

**2026-11-07三地／CSDI規格確認（#16）：** 總範圍為彩明商場、調景嶺站出入口及非付費大堂、HKDI與三地選定步行接駁；首輪排除付費區／月台／乘車。CSDI為可選來源，先評估調景嶺站資料，不要求新後端或替換MapKit，不能成為本機錄路前置。地圖／路網候選、私人已走路段、當下位置及樓層證據分開，官方資料不得轉成已走／human_approved。請求及解析須有界，服務／目的地取消作廢晚回覆；斷網、空結果、錯誤坐標／樓層及缺圖層明示限制。沿用導航服務邊界注入成功／失敗資料，不另造跨層框架；驗室外→入口→室內及反向交接，只有有效位置才出對應提示。

外部查詢只傳用途必要的公開地點／坐標，不默認上傳路標JPEG、特徵、私人路線或訓練資料；坐標與高程不直接當實際樓層／手機距離。provider版本、署名及快取／離線政策於接入前核對，本輪未凍結新schema、同步或快取保留期，亦未新增API、雲端部署或資料傳送。既有加密／權限／版本與容量規則保持不變。

**2026-11-07交付優先（[規格#16](https://github.com/actiondarr/pathguide/issues/16)已確認）：** 自動錄路、減少填表與可靠保存／重開先作完整交付驗收，模型比較獨立。沿用#17／#18本機實作，不要求新模型、雲端或訓練先完成。首輪固定大廈的同層及跨層路線驗保存→離頁重開→另趟再走；另驗錯層、相似出口、暫停／背景及保存失敗，未知不得升格。既有相機／分析與加密版本庫故障注入接縫繼續使用，資料完整性、CAS／配額、穩定版保護與刪除規則不變。普通相機基本版、測距選填及未知樓層草稿依已確認規格處理。本輪不改schema、服務／雲端狀態，也不將工程或裝機證據當真人通過。

使用者已確認：服務／儲存邊界沿用外部行為驗收，與旅程功能及真機場地結果分開。優先覆蓋越權、同意epoch、冪等、撤回／刪除競態、逾時、損壞及回退；不以內部函式呼叫次數代替行為。

<a id="6-後端驗收"></a>

### 無障礙整合的後端責任（持續適用）

VoiceOver／TalkBack、語意樹、讀屏焦點、系統縮放及快捷動作在裝置端，不為此新增AccessibilityService、雲端讀屏或強制帳號。系統是否開啟讀屏不作身分／能力判定，不預設上傳輔助科技使用狀態。

服務回覆提供結構化stage、reasonCode、可重試／可取消狀態及必要進度，由Frontend本地化成可理解文字；不把原始exception或百分比假進度直接播出。狀態以job／request／session及版本對應，重試不產生重複通知；過期下載／核准結果不得觸發舊任務播音。帳號驗證、刪除、模型下載、同意及撤回頁也須能用讀屏／替代輸入完成。

無障礙偏好預設本機，不能由「使用VoiceOver」推定同意上傳、常開麥克風或下載模型。診斷如需保存測試語音／畫面另取用途同意；共用報告只保存去識別結果。驗收錯誤碼／狀態映射、取消／斷網／重送與語言切換；官方研究與平台差異見Frontend「跨平台無障礙驗收」。


### 後端驗收

- [ ] 身分／App Check、跨UID、舊epoch、影像及額度會拒絕；重送不重複照片或工作。
- [ ] AI不能覆寫人工答案；未核准／拒絕／授權不明的資料不入快照。
- [ ] 缺預算不提交；lease、逾時、心跳失效、checkpoint續跑及取消有測試。
- [ ] 不合格不發佈；本人下載、閒置切換、損壞回退與切帳號正確。
- [ ] 刪除與訓練／下載競爭不復活舊資料；私人產物不進GitHub。
- [ ] 共用版本遠端備份完成才交付，舊tag與對應模型可重建。
- [ ] 覆核人員／完整性／coverage／revision衝突及抽樣複核有證據；積壓上限不影響核心辨識。
- [ ] 一個issue可追溯至獨立資料比較及手機重測；回報照片不冒充驗收集，未評估不關單。
- [ ] 斷網／空間不足／重開／切帳號後active版本正確；體驗變差能主動回退，同SHA拒用與發佈者撤回不被重試繞過。

<a id="service-plan"></a>
## 5. 開發階段與逐功能計劃

### 開發階段與目前進度

三份文件共用S0–S7階段編號。狀態只表示可追溯證據：**已有程式**不等於已部署；**待實測**不等於通過；**受阻**需先解依賴；**未開始／未來研究**不是現有功能。沒有足夠工作量與驗收資料前不編造完成百分比或日期。

S5的圖示訓練可與S2、S4並行準備；私人訓練必須先有S0品質基準及S2核准資料，S6對本次納入能力的整合驗收通過後才擴大S7範圍。當前主線為一般iPhone路線錄製、跨樓層步行導航及即時障礙／語音整合；Dataset／訓練工作仍暫停。S4包含基本跨樓層路線，S7才擴更多場地／複雜網絡與平台；ARKit追蹤與LiDAR深度分開，物件、定位及實地任務品質各自驗收。

| 階段 | 工作 | 證據支持的現況 | 完成標準 | 下一步／依賴 |
|---|---|---|---|---|
| S0 工程基線與版本保存 | 來源、模型、版本及回退 | 1.11.0+29已原位裝機／核版本／啟動；599項Flutter通過、7項略過；模型未換 | tag、來源、模型及相容資料可追溯；文件整理不是新App版本 | 保留收據與舊版；schema4舊App拒讀 |
| S1 現有App核心功能 | 辨識、菜單、戶外導航、場景描述及讀屏 | 有程式／部分真人結果；場景拒絕、VoiceOver與系統截圖卡住仍待驗 | 逐任務真機、取消／恢復及內容品質驗收 | 先修阻擋及收集可定位診斷 |
| S2 照片收集與人工覆核 | 同意、私人資料、標註及清理 | API／本機工作台及合成驗證已有；預設關閉，部署／真人閉環未驗 | 權限、撤回、全圖coverage、修訂及獨立覆核可追溯 | 明確用途及角色後才接真實案例 |
| S3 私人訓練與模型更新 | 快照、worker、比較、registry及回退 | L1只有本機候選儲存核心；UI／真實訓練未接，效益未驗 | 與共用／記憶補強比較有額外效益，配額及回退可驗 | 資料及預算未具備前不提交付費GPU |
| S4 室內錄路與引導 | 普通相機、樓層／轉層、重認、障礙及語音 | 錄路／儲存／影像分析及1.11.0標記核心已有；方向播報／備註／完整實地驗收未完 | 錄製→保存重開→另趟重行，分報未知／錯層／漏報／恢復 | 完成標記餘項、VoiceOver及同層／跨層驗收；測距選填 |
| S5 圖示／文字與設施理解 | B11、牌面OCR及箭嘴配對 | B11最後記錄epoch22後中斷；未重新查活躍程序，未完成發佈／入App | 正式run、獨立留集、格式及手機任務通過 | 先核既有run與checkpoint，不Run all或盲目重訓 |
| S6 限定場地整合驗收 | 三地路線、讀屏、資源與版本 | 完整任務及學習閉環未驗；不編完成百分比 | 按獨立趟次記內容、操作、時效、拒答與恢復 | 彩明／調景嶺非付費區／HKDI及選定接駁分驗 |
| S7 場地與平台擴充 | 更多場地、複雜網絡及Android | 完整擴充未實作；不把基本跨層排除出S4 | 每項有資料、相容及獨立任務證據 | S6通過後逐項擴展 |

### 功能計劃索引（按依賴取用，不代表同時開工）

本節接口名稱若寫「新增」即尚未實作，不能當成目前已可呼叫的API。

| 功能／階段 | 目前狀態 | 實現方法與輸入／輸出 | 依賴／完成標準 |
|---|---|---|---|
| B01 帳號、角色與私人聯絡／S1–S2 | Google／聯絡規則已有；覆核API已有角色／當前Auth及server-only人員檢查，本機替身測試通過，未部署／指定真人 | 驗證token取得UID，以可重試交易建profile；聯絡資料保持獨立。新增覆核角色由受權Admin設定custom claims，服務端驗證，不接受前端自報admin或ownerUid | 本人／覆核者／一般訪客權限分開；角色變更與token刷新／撤銷有測試 |
| B02 照片同意與提交／S2 | callable已有，未啟用 | 沿用get／setPhotoConsent與submitPhoto；檢查UID、epoch、配額／尺寸，解碼重編碼、綁photoId／objectGeneration，再原子更新validated／pending。sourceSha與清理後sha分開 | 前端F05同幀資料；重試冪等、無效App Check／舊epoch拒絕，不改成公開Storage |
| B03 管理員覆核與問題追蹤／S2 | 七個API、本機工作台及版本／權限／到期測試完成；預設關閉、真人／容量／案例未完成 | 依「管理員覆核與自動批次」建立原圖／預測／修框工作台，指定接件與複核角色，驗全圖coverage；expectedRevision防覆蓋，疑義退回，固定核准版本。以issueId串開發快照／候選／獨立評估／手機重測，記處理時間與積壓 | Dataset D02；人工完整答案及抽覆有效、衝突可恢復、撤回不復活；未重測不關單，AI篩查不冒充人工核准 |
| B04 私人快照匯出／S3 | 未接通 | 依ownerUid＋仍有效用途查核准版本，合併獲授權基礎回放，固定影像／標註版本、場景split、coverage與SHA，輸出不可變manifest；重送同一請求沿用snapshot ID | Dataset D03／D07；同實物不跨split，其他UID資料不得混入，資料變動建新snapshot |
| B05 排程、去重與佇列／S3 | 未實作；先案例與效益驗證 | 通過「管理員覆核與自動批次」啟用條件後才設03:00排程；50張／三場景只作候選檢查，仍驗樣本充分性。以UID＋snapshot＋config唯一job及lease，綁預算／時限與GCP Batch ID | 修正案例、私人效益、mock／權限／刪除及預算先驗收；資料不足不排，重複事件不重開；UTC照片配額不變 |
| B06 GPU訓練worker／S3 | 現有Colab實驗；服務未實作 | 容器固定工具／權重／設定，最小IAM讀指定snapshot，執行preflight→smoke→正式run；每輪備份checkpoint／optimizer／CSV及心跳。相同快照中斷才resume，改資料開新run；逾時／取消不發佈 | Dataset提供D04／D05／D07腳本；先mock成功／失敗／重試，再配置GPU；不把免費Colab當可靠無人服務 |
| B07 品質門檻與獨立評估／S3 | 只有本地A／B評估工具 | worker產生候選與現用模型的同資料逐類比較、樣本量、export parity及手機結果；核准服務驗完整報告並套版本化門檻，不能由worker一句success直接寫ready | Dataset「訓練與改善判定」為門檻唯一來源；目標無真值或其他類別退化則不核准；測試集不拿來反覆調參 |
| B08 Registry與發佈包／S3–S5 | 未實作 | 新增不可變模型record：ownerUid／shared scope、job／snapshot、A或B namespace、權重／manifest SHA與大小、taxonomy、App相容性、評估與狀態；核准才設可下載，發布指標另指向可回退版本 | A／B映射不得互換；現行內置format:1不無聲改義；共用模型與私人模型有不同存取範圍 |
| B09 本人下載、自動更新與回退／S3 | 未接通 | 新增綁scope／SHA／profile的offer與限時授權，重驗用途及版本核准；閒置原子切換，保留上版／內置。依「私人發佈、自動更新與回退」加入主動回退、選填原因、同SHA拒用及發佈者撤回 | Frontend F08；驗斷網、重開、空間不足、切帳號、重複offer及撤回競爭；signed URL有效期／離線撤回限制須如實呈現 |
| B10 撤回、取消、帳號刪除與到期／S2–S3 | 照片及新增問題／修訂／重試收據的到期、刪除已本機驗證；訓練資源未覆蓋 | 沿用tombstone／deleting，先禁止新上傳／job／下載，取消並等待或隔離worker，再按清單刪照片、annotations、snapshot、外部副本及私人模型，最後Auth；每步可重試並拒絕遲到重建 | 擴充現有deletePhotoAccountData；基礎共用資料不因單UID刪除而誤刪，處理中狀態可理解 |
| B11 Android搜尋／步行代理／S1 | computeWalkingRoute已有，未部署／驗證 | App Check驗應用，訪客可用；固定Google Routes WALK、HK／繁中與回傳欄位，Secret Manager供金鑰，逾時／配額分類；不接受任意網址代理、不持久保存軌跡 | Google配置、預算、簽署限制及真機；iPhoneMapKit不改走此代理 |
| B12 發佈、診斷與預算／S0–S6 | 1.11.0+29簽署、不可變tag／prerelease、原位安裝及獨立版本／啟動核對完成；真人任務待驗 | 日誌只留安全ID、階段、耗時、固定錯誤與估算；App先GitHub核遠端再安裝；預算／時限不足不提交付費工作 | 收據與模型SHA可追溯；文件提交不是App回退版本；費用估算非帳單硬上限 |
| B13 室內即時資料邊界／S4 | 1.4.1+6辨識框與深度已本機處理，無雲端服務 | 深度／pose／網格留手機，不新增即時雲端避障API；只提供相容模型與設定。若日後要上傳序列，需獨立用途、保留／刪除及安全設計，不能沿用照片同意 | Frontend F09–F12與Dataset D09；關閉網絡不影響已載入的本機感知 |
| B14 個人路線記憶、觀察及場地版本／S4–S7 | 本機floor／connector、路標重認及旅程已有工程流程；完整perception與實地品質待驗，無正式雲端API | RouteMemory／LandmarkNode／RouteObservation／MatchResult分開身份、時序、版本與樓層來源；有向已走路段不套無向BFS假設；未知與歧義不強出方向 | F14／D09；基本版本機無帳戶；不能把AI候選或GPS當樓層真值 |
| B15 路線錄製／場景理解與選填同步／S1–S4 | 1.11.0+29已交付相機、加密媒體／特徵、樓層來源及schema4標記核心；完整真人任務待驗 | 本機draft、CAS保存重開、回退／刪除與容量保護；首次錄路／更新存必要媒體，普通重行不落新影像。方向僅保存，備註、同步及訓練閉環未接 | F17；補標記餘項及VoiceOver／實地驗收，再推P4／P5；雲端／訓練另同意及預算 |
| B16 Apple／電話連結與跨平台／S7 | Google現行；其他未接 | 使用Firebase明確provider linking，在驗證後維持原UID與私人資料，處理已有帳號衝突，不以同電郵猜合併；Android與iOS使用各自App／簽署設定 | F18；重新登入、登出、刪除與相同UID恢復有雙平台證據 |
| B17 Qwen場景描述／S1 | 固定新加坡服務與內容拒絕分類最近部署已留證；1.11.0+29單開關已裝機 | Auth／App Check／active與刪除guard→預留→有界JPEG→完整驗證；頂層替換最近三次固定結果，其他counter保留；status只讀不推理 | 100次／估算500000 microUSD、2026-11-14 03:22:40香港時間到期；用量未知停止，不列歷史餘額作現值。廚廁內容、起音及VoiceOver待驗 |

管理員角色依據：[Firebase custom claims](https://firebase.google.com/docs/auth/admin/custom-claims)；GPU工作／時限依據：[Batch GPU工作](https://docs.cloud.google.com/batch/docs/create-run-job-gpus)、[工作時限](https://docs.cloud.google.com/batch/docs/create-run-basic-job)。這些是規劃所用平台能力，未表示本專案服務已部署。

產品及導航次序集中在[Frontend開發次序](FRONTEND-DESIGN.zh-HK.md#delivery-plan)；本檔B項目只維護服務依賴與驗收，不再複製已結束的派工表。

<a id="release-process"></a>
## 6. 部署、版本保存與回退

<a id="7-部署設定與版本回退"></a>

### 部署、設定與版本回退

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

2026-11-05已確認保存頻率：每張工作票通過檢查及程式覆核後，先commit／push相關來源、文件及機器證據到feature/cross-platform-navigation並核對遠端，再標完成。這類原始碼檢查點不等於App交付，不要求每票增加App版本。P2-D、P3-C、P4-B及P5各準備手機prerelease；P3-A另安排Keychain、檔案保護／備份排除、重開及刪除的工程真機檢查。任何裝機均遵循上列版本程序，實測結果再更新收據及文件，不能以關閉Issue或推送成功代替人工驗收。

倉庫為https://github.com/actiondarr/pathguide，既有工作分支feature/cross-platform-navigation。小型共用模型隨Git，過大共用產物用Release asset並記SHA及精確版本；私人照片／權重不得進共用repo。保留舊tag、模型及相容資料；回退App需重建並有效簽署，必要時用新的遞增iOS build號。私人模型則由本人授權registry保留上一版。

文件提交不構成App還原點；當前1.11.0+29與歷史App／模型版本均以不可變tag及交付收據追溯，不移動舊標籤。

版本發佈使用正常Git推送，以及有效的gh登入或GitHub已登入網頁流程；不從OS憑證庫抽出Git token作API登入。Release列模型SHA、試驗限制、測試、重建與回退方法；現有本機Firebase設定不入Git。CLI登入無效時，本版用正常GitHub網頁建立prerelease。

<a id="1438-相機前處理修正版github已保存iphone已安裝啟動"></a>
<a id="1427-前端恢復修正的契約與版本已交付試用"></a>
### 持續適用的裝置契約

前處理採雙線性／恰半取偶數letterbox，模型與映射不因此更換；自然影像PT↔TFLite一致性不代表模型品質通過。權限、openSettings及相機交接仍須取消舊generation並等待來源釋放，從設定返回不自動開相機。這些是本機契約，沒有新增雲端用途；歷史逐版檢查與安裝細節由[收據目錄](../verification/release-receipts/)追溯。

## 7. 範圍限制與待定事項

[已錄路標持續改善規格](https://github.com/actiondarr/pathguide/issues/19)確認私人已錄路標的批次訓練方向，不授權本次上傳、GPU或部署；供應商、可驗預算／配額、保留及清理期限與評估profile仍須落實。舊A十類私人微調條件不代替路標服務條件。

已交付場景服務採固定Qwen與有界試驗；其他雲端問答擴展的provider、額度、最少傳送欄位及保存期限另定；分析、回報及訓練用途分開授權。陌生室內探索只接受方向，無線索時停定掃描及保留未知已確認，具體線索搜尋／定位及正式接口未定，不把自由文字回答轉成已確認位置。私人訓練及付費GPU沒有因本規格獲得啟動授權。

## 8. 維護與追溯

2026-11-10：移除舊香港端點／20或50次許可、未部署指示、已結束派工及重複版本日誌；更新當前服務與schema4，保留資料保護、配額、覆核、訓練／更新的未完成契約。部署／許可依verification，不用歷史日誌作即時餘額。清理沒有部署或改帳本。

歷史細節由Git與[verification](../verification/)追溯；機器紀錄見[文件整理證據](../verification/docs-current-cleanup-20261110.json)。
