# 第四階段照片收集及私人上傳

日期：2026 年 10 月 23 日。帳號及聯絡人真機流程由使用者回報完成；本輪加入照片收集與上傳程式。照片服務尚未部署到 `pathguide-dev`，目前 Spark 登入仍可獨立使用。手機設定不會自動開啟照片功能或自動綁定付款。

## 1 可操作流程

1. 首頁或設定進入帳號，選「個人模型照片收集」。
2. 先完成 Google 登入及帳號初始化，閱讀獨立用途說明，選「同意並開啟」。未同意、尚未部署或不支援的平台不能擷取。
3. 返回即時辨識，從「更多操作」按「回報辨識問題並擷取照片」。相機下一個成功推理幀同時產生 JPEG 和候選框，沒有畫框、按鈕或介面截圖。
4. 加密保存在同 UID 待傳佇列。經 Wi-Fi 手動上傳，或即時辨識前景每三十秒嘗試待傳；重試沿用原識別碼。
5. 雲端驗證成功後顯示待人工覆核；不自動訓練、不當成正確標註。照片頁可重新查詢本人最近最多二十筆進度。
6. 自動擷取另設開關，預設關閉。只在辨識運作及面板關閉時嘗試；低信心候選與每分鐘場景抽樣交替執行。離開前景後自動開關關閉，返回後由使用者重開。

目前擷取先支援 iPhone，Android 保留辨識及帳號功能；Android 原生同幀 JPEG 擷取尚未加入，不能以模擬照片代替。

## 2 擷取及本機限制

- JPEG 與候選框由同一個 CVPixelBuffer 推理取得，順時針轉正九十度；模型版本及映射從實際使用的清單讀取，不能寫死九類或十類。
- 只有待擷取時，原生額外保留最低 0.20 的候選；日常顯示／播報仍用使用者門檻。低信心 0.20–0.60 候選在相近中心及同類別維持約一秒才擷取。這是候選穩定性啟發式，不是可靠物件追蹤或未知類別判定。
- JPEG 編碼在獨立工作佇列，辨識來源釋放或任務暫停後，遲到結果不入待傳。
- 自動候選略過過暗／過亮縮圖、近期 dHash 差異小於六個位元的畫面；手動回報保留操作意圖，但完全相同 JPEG 仍去重。模糊、持機品質及實際候選有效率尚待真機校準。
- 本機上限五十張或 50 MB；單張最多 2 MiB；七日到期清除。AES-256-GCM 加密檔案，金鑰放系統安全儲存，原子改名避免半寫入，沒有 EXIF／GPS 資料輸入。
- 佇列綁定 Firebase Project ID、UID 及同意 epoch，切換帳號、登出及進入刪除狀態清除。撤回先停止本機並清除待傳，即使斷網仍保留本機暫停旗標，不能因重新開啟而恢復上傳。
- Wi-Fi 以作業系統回報的連線類型判斷；網絡切換時已送出的請求可能完成，沒有聲稱能撤回已傳送的位元。背景不建立新請求。

## 3 後端接口與狀態

獨立 `backend/functions` 使用 Node 22、Firebase Admin／Functions 及 sharp；不載入舊原型的管理員私鑰。區域 `asia-east2`。所有 callable 要求 Firebase Google 身分及 App Check，管理 SDK 以 token UID 決定擁有者。每個請求另帶 expectedUid，必須與驗證身分一致，避免切換帳號時 SDK 將遲到請求附上另一人的 token；expectedUid 只作一致性檢查，不是授權來源。

| 接口 | 功能 |
|---|---|
| `getPhotoConsent` | 讀取本人用途同意及 epoch，缺省關閉 |
| `setPhotoConsent` | 記錄固定說明版本及伺服器時間；每次操作推進 epoch |
| `submitPhoto` | 驗證 JPEG、雜湊、尺寸、候選框、同意及配額；儲存私人檔案及待覆核記錄 |
| `listPhotoProgress` | 只回傳本人最近最多二十筆識別碼與狀態，不回傳公開照片網址 |
| `deletePhotoAccountData` | 最近五分鐘重新驗證後建立刪除保護、清理本階段照片及所有本人子集合；成功後 App 才刪 Auth 身分 |
| `removeLatePhotoObjects` | Storage 完成事件重新核對同意、帳號及記錄，移除遲到／無效的物件版本 |
| `expirePhotoCandidates` | 每小時最多處理二百張到期未覆核／拒絕候選，刪檔及記錄 |

本輪採小圖 callable 直接提交 Base64，單張限制 2 MiB，沒有另行簽發上傳網址。這替代原先先分配 signed URL 的設計，避免網址外流或關閉收集後舊網址仍可寫入；大型圖／批量傳輸另行設計。圖片仍可能在送達後遇到撤回，因此入庫前及完成事件都重新驗證 epoch。

照片識別碼由本機產生三十二位十六進制隨機值，伺服器綁定 UID；相同 UID＋ID＋來源雜湊重試共用同一筆記錄及 Storage object，檔案禁止覆寫。JPEG 必須真正解碼，伺服器重編碼移除 EXIF／GPS／XMP，`sourceSha256` 是提交來源，`sha256` 是最終雲端 JPEG。重編碼不改尺寸及框座標。

Firestore：`users/{uid}/private/photoConsent`、`users/{uid}/photos/{photoId}`、`users/{uid}/photoQuotas/{UTC日期}`。Storage：`unconfirmed_photos/{uid}/{photoId}.jpg`。一般客戶端不能直接讀寫 Storage，也不能寫同意、照片狀態、配額或覆核結果；本人只可讀取相應進度。緊急聯絡資料不進照片中繼資料。

每日 UTC 上限一百張總候選，其中自動最多五十張、場景最多十張；伺服器另限制自動至少三十秒、場景至少六十秒。重試已分配照片不重扣配額。模型猜測及零分／空候選不自動轉成標註。

雲端未覆核照片三十日到期，清理按小時排程及每批二百張處理，可能有排程延遲；需監察清理錯誤及積壓。未覆核、拒絕及尚未完成驗證的照片不得進訓練。尚未提供審批／匯出操作介面，不能先寫入 approved 來繞過後續流程。

## 4 部署前由使用者或組員完成

1. 確認是否為測試專案啟用 Blaze。Cloud Storage 及 Cloud Functions 需要相應付款方案；設定費用預算提示，提示不等同硬性停止收費。此步未代辦。
2. 在同一 `pathguide-dev` 專案建立 Storage bucket，與 Functions 選用相容區域；首輪建議香港 `asia-east2`。確認桶名稱及生命週期設定，不開放公開存取。
3. Firebase App Check 登記 iOS App。測試機可使用 debug provider，把私密 debug token 登記至該 App；正式版使用 DeviceCheck 並由擁有者配置 Apple Team 所需憑證。不能把測試 token 發佈或加入 Git。
4. 在 `backend/` 安裝根目錄測試依賴及獨立 `functions/` 執行 `pnpm install --ignore-workspace --ignore-scripts`。在自己帳號登入 Firebase CLI，先核對顯示的 Project ID。
5. 覆核後以明確目標專案部署 `firestore:rules,firestore:indexes,storage,functions`，包括所有七個 endpoint／排程／事件。此步會改動雲端存取及建立服務，不會由本輪自動執行。
6. 在本機 `app/config/firebase.local.json` 加入 `PHOTO_UPLOAD_ENABLED: "true"`。僅測試環境另加 `APP_CHECK_DEBUG: "true"`；正式設定省略／關閉 debug。原來 Google 設定保留。
7. 執行 `app/tool/run_iphone.sh`（可加 `-d 裝置ID`），重新安裝 Release。此工具固定帶本機 Firebase 設定，避免普通 flutter run 覆蓋成未配置登入版本。

沒有完成部署時，保持 PHOTO_UPLOAD_ENABLED 缺省 false。不能為了讓畫面顯示成功而關掉 App Check、開放 Storage 或把規則改成所有人可寫。第三階段原有 Spark 帳號／聯絡功能繼續使用。

## 5 驗證與尚待項目

自動檢查見 [第四階段驗證紀錄](baselines/2026-10-23.phase4-verification.json)。本機 Emulator 使用 demo 專案，與真實 `pathguide-dev` 分開；整合測試直接執行 callable handler，因此 App Check 真實憑證交換及雲端閘道仍需部署後驗收。

真機清單：

- [ ] 未同意、未登入、未配置及撤回後不擷取；基本辨識仍可用。
- [ ] 手動拍攝內容、旋轉方向、預測框座標與 JPEG 一致，無畫框及介面。
- [ ] VoiceOver 可完成用途說明、拒絕、手動回報、查看狀態及關閉；兩倍字體可捲動。
- [ ] Wi-Fi 上傳、斷網保留、重新開啟恢復及重試不重複；網絡切換及前後台可理解。
- [ ] A／B 帳號隔離；登出清理；遲到照片不進另一人佇列。
- [ ] 真實 App Check 拒絕無效應用；規則拒絕直接讀寫 Storage。
- [ ] 真正刪除帳號會清理照片、同意、配額及聯絡資料；重試不復活舊資料。
- [ ] 排程到期清理、錯誤監察、配額及費用提示可正常運作。
- [ ] 自動擷取的候選有效率、暗光、重複率及手機效能實測。

照片不代表未知類別已被辨識；本階段不提供訓練、個人模型下載或避障保證。
