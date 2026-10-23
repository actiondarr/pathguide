> 歷史快照，第三階段更新前版本。現行流程請見 [第三階段實作](../../PHASE3-IMPLEMENTATION.zh-HK.md)。

# 領路通第一版資料契約

日期：2026 年 10 月 22 日。版本：1。供前端、Dataset 及後端實作交接使用。

本文件凍結第一輪共用欄位及責任。第 1 節為已存在的模型格式；雲端記錄屬後續接口規格，尚未建立 Firebase 服務，亦未開始收集照片。欄位名稱在正式接入時以契約版本管理，不能無聲改義。

## 1 模型及類別基線

- 已打包版本 `2026-10-19.hk9.1`，YOLO11n Float32 TFLite，640 輸入。
- 模型長度 10,694,183 bytes，SHA256 `8bbfa43b1fe2b440e608652e75fa86d15e571031c45b7b21f30689852468e3c9`。
- `detector.json` 的 `format` 維持 1。`modelClassIds` 為 `[11, 7, 8, 50, 49, 6, 9, 51, 24]`；陣列位置是模型本地索引，值是專案類別 ID。
- `configs/classes.json` 為專案字典 v6，共 52 個登記項目；不代表模型已訓練 52 類。現有模型仍為九類，不修改權重、輸出數目或映射。
- 未來樓梯合併及 20 類候選使用新 taxonomy／映射版本；原始 Dictionary、現行模型與未來 Dataset 分開管理。個人新增 20 類名額亦不建立空白輸出。

## 2 所有雲端記錄的共同規則

| 欄位 | 定義及來源 |
|---|---|
| `schemaVersion` | 整數 1；不支援的版本拒絕處理 |
| `ownerUid` | 由後端驗證 Firebase ID token 取得，不能信任客戶端自報值 |
| `createdAt`／`updatedAt` | 伺服器時間；UTC。客戶端拍攝時間另存，不作授權依據 |
| `status` | 各記錄的明確狀態，不用單一 `is_trained` 代替全流程 |
| `requestId` | 需重試的建立／更新操作使用穩定識別碼，防止重送建立另一份記錄 |

所有照片、標註、資料集快照、工作及私人模型均可追溯同一 UID。電話、電郵、裝置 ID、專案類別 ID 都不能代替 UID。Google／Apple 是同一 Firebase 帳號的額外登入方式；經連結成功後 UID 不變。後續詳細登入流程見後端 Word 1.1。

## 3 帳號及用途同意

帳號放於 `users/{uid}`，欄位為 `schemaVersion`、`status`、`createdAt`、`updatedAt`、`termsVersion` 及選填顯示名稱。`status` 使用 `active`、`deleting`；停用身分仍需核對 Firebase Auth 狀態。登入方式摘要由伺服器核對 Auth user record，不授權前端自行寫入。

同意另外保存 `ownerUid`、`purpose`、`noticeVersion`、`enabled`、`consentedAt` 及 `revokedAt`，其中 `purpose` 首輪為 `personal_model_photos`。首次建立預設關閉；重新登入、連結 provider 或更新 token 都不重設同意。相機權限、帳號條款及訓練照片同意是不同項目。

關閉收集後不能再上傳待傳照片；已在雲端的資料依刪除／保留流程處理。照片同意不包含影片、定位或其他人的私人訓練用途。新用途及重要說明變更須重新取得相應同意。

## 4 候選照片及覆核

| 欄位 | 定義 |
|---|---|
| `photoId`、`clientCandidateId` | 伺服器綁定的照片 ID 及本機候選 ID；首次請求重試對應同一張照片 |
| `ownerUid`、`sessionId` | 擁有者及收集工作階段；用於存取與按場景分組 |
| `capturedAtClient` | 手機記錄的 UTC 時間，可能不準；與伺服器收到時間分開 |
| `modelVersion`、`classMapVersion` | 產生候選時實際使用的模型及映射；不能事後套最新映射 |
| `trigger` | `manual_report`、`low_confidence` 或 `scene_sample`；低信心不等於新類別 |
| `width`、`height`、`sha256` | 最終已轉正 JPEG 的尺寸及雜湊；不含 UI 物件框、EXIF 或 GPS |
| `predictions` | 可為空的陣列；每項為 `projectClassId`、`score` 及正規化 `cx, cy, w, h`，以最終 JPEG 為座標系 |
| `storagePath`、`objectGeneration` | 伺服器綁定 `unconfirmed_photos/{uid}/{photoId}.jpg` 及實際檔案版本，不能由任意路徑取代 |
| `uploadStatus` | `allocated` → `uploaded` → `validated`，或 `rejected`／`expired` |
| `reviewStatus` | 檔案及中繼資料驗證齊備後 `pending` → `approved`／`rejected`；獨立於上傳狀態 |

分數必須有限且在 0–1；框須有限、正寬高並在已定義座標範圍內。`predictions` 是模型猜測，人工確認答案另存 `annotations`、`annotationVersion`、`reviewedBy`、`reviewedAt` 及分類手冊版本。

沒有預測時可以空陣列，不以 0、999 或任意新 ID 假裝「未知物件」類別。訓練用 YOLO TXT 的類別是該 Dataset 的連續本地索引，匯出時附映射；不可直接把專案 ID 寫進 TXT。

每張核准圖需完成該次目標集合的全圖標註；部分標註不能直接當完整 YOLO 訓練樣本。覆核後被拒絕的圖片不進訓練，延遲 AI 回寫不能覆蓋人工答案。

## 5 資料集快照及訓練工作

`datasetSnapshotId` 固定 `ownerUid`、核准照片／標註版本、來源與授權、taxonomy、類別映射及 train／validation／test 的場景群組。相同實物、連拍或影片不能跨集合。訓練開始後不把新上傳直接加入快照。

訓練工作保存 `jobId`、`ownerUid`、`datasetSnapshotId`、`baseModelVersion`、`trainingConfigVersion`、輸出版本、評估來源及失敗原因。狀態為 `queued` → `running` → `evaluating` → `approved`／`failed`／`cancelled`。組員確認後批次啟動；上傳成功及完成註冊都不自動觸發 GPU 訓練。

首輪私人微調只使用獲授權基礎資料及該 UID 的核准照片，不混入其他人的私人資料。來源 PyTorch 評估、匯出一致性及手機實測分開保存；模型是否有改善由獨立評估決定，不能因為訓練成功就宣稱更準確。

## 6 私人模型發佈及刪除

個人模型放在 `personal_models/{uid}/{modelVersion}/`。後續發佈記錄另包 `ownerUid`、`jobId`、`datasetSnapshotId`、狀態、檔案及 manifest 的 SHA256／大小、`classMapVersion`、App 相容版本和評估摘要；不把這些欄位假裝已存在於目前 `format: 1` 清單。

只有已核准、相容、屬目前帳號的模型才可授權下載。App 暫存、檢查完整性及映射，使用者在辨識暫停時選擇啟用；第一版不背景自動切換。下載或驗證失敗保留原模型。登出／切換 UID 清除私人快取及待傳工作，回到內置基礎模型。

刪除先重新驗證並標記 `deleting`，拒絕新上傳、下載授權及訓練，清理 Firebase 與 Roboflow／Colab 私人副本及產物，最後移除身分與 profile。已連結 Apple 時一併協調授權撤銷。重試及延遲事件不得重新建立已刪資料；已簽發網址及離線裝置快取有失效延遲，不能承諾立即遠端抹除。

## 7 第二階段裝置端介面契約

任務狀態依序為尚未開始、準備中、辨識中、已暫停或暫時不可用。只有使用者開始後才初始化 `VisionSource`；暫停／離頁／進背景停止來源並清空結果，返回前景不自動恢復。

UI 接收 `Detection.id` 時已是專案 ID；框為轉正後的正規化座標，不能再旋轉一次。每幀框及 FPS 不加入日常讀屏次序。手動結果只包括符合播報門檻的支援類別，不從框推測距離、扶手電梯方向或安全性；超過三秒未更新的結果不當作目前結果讀出。

所有環境結果經同一輸出層：讀屏開啟時使用系統無障礙播報，否則使用 TTS；無系統 announcement 支援時保留可朗讀結果，避免再用 TTS 重複讀同一句。自動播報預設關閉，使用者可開啟；開啟讀屏時回到按需模式。技術設定面板打開期間不自動播報。
