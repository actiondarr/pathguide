# 文件整理待覆核清單

盤點日期：2026 年 10 月 22 日。狀態：只盤點，未刪除、移動或歸檔任何原有文件。需使用者檢查後另行確認清理範圍。

本次以內容是否仍適用、能否追溯來源、是否有其他文件引用為準；沒有單憑日期刪除。範圍為目前 App 專案的文字文件及三份 Word，另檢查工作區根層的舊交付 ZIP。未全面檢查原始照片、所有 Colab 產物或訓練權重。

## 1 建議刪除或重新打包的候選

| 項目 | 核對結果 | 建議 | 執行條件 |
|---|---|---|---|
| `../../pathguide-iphone-demo-source.zip` | 舊交付包，643,011,232 bytes。內有 2,622 個檔案，解壓約 1.81 GB；其中 `app/build/` 約 1.25 GB、`app/.dart_tool/` 約 465.51 MB，均是解壓後大小。包含舊版導航首頁說明，亦不包含其後新增的方案與本輪程式修改 | 優先候選。新交付包排除建置快取後，再考慮刪除舊 ZIP；ZIP 本身仍原封保留 | 先確認沒有只存在於 ZIP 的原始資料、程式修改或模型，再由使用者批准；本次只抽查，尚未證明全包可替代 |
| `app/README.md` | Flutter 自動產生的「A new Flutter project」教學範本，沒有領路通專屬說明；目前根 README 已提供工程入口 | 可改寫成 App 操作／開發入口，或經批准刪除範本文字；不建議直接刪去整個 App 目錄 | 使用者選擇改寫或刪除；本次保留 |
| `docs/word/~$thGuide-Frontend-Plan.zh-HK.docx`、Dataset／Backend 的同類檔 | 三個約 162 bytes 的 Word owner／鎖定檔，不是完整 Word 文件；目前有開啟文件的可能 | 關閉 Word 後確認是否自行消失；若確認為殘留，才列入刪除 | 不能在文件仍開啟時當作舊副本刪除；本次保留 |

## 2 需要更新或歸檔的內容

| 文件 | 問題及依據 | 建議處理 |
|---|---|---|
| `docs/MODELS.md` | 開頭九類清單仍有用；其後混有舊三類「目前發佈」、18 類「目前最優候選」、48／50 類字典假設及本源碼包不存在的訓練腳本。尾段「143,784 幀中 2,358 幀即 98%」亦算術不符 | 保留九類現況及限制；舊實驗另存歷史附錄並標日期，不再作現行部署指令。舊數據未核實前不沿用，亦不自行猜改數字 |
| `docs/IOS-DEMO.md` | 安裝步驟及已有驗證紀錄仍有用；目前描述進探索即啟動、全屏預覽及前景自動恢復，與本輪第二階段的新操作目標不同。96 個測試為當時紀錄，本輪改動前基線為 107 個通過 | 更新操作與新驗收清單；保留舊驗證日期及測試平台，不把過往結果當本輪結果 |
| `README.md` | 導航首頁描述是改動前行為 | 隨任務首頁實作更新入口；不刪除 |
| `docs/PROJECT-OVERVIEW.zh-HK.md` | 記錄整理當日現況，包括設定頁舊模型大小；程式更新後將成為有日期的背景資料 | 保留 FYP 背景，另連結最新實作紀錄，避免讀者當作即時功能表 |
| `docs/ACCOUNT-REGISTRATION.zh-HK.md`、`docs/BACKEND-DESIGN.zh-HK.md` | 手機登入及 UID 原則仍適用，但 Google／Apple 登入的新增規劃目前只完整反映於後端 Word 1.1 | 後續同步 Markdown 與 Word；不能因兩種格式共存便刪除其中一份 |
| `app/pubspec.yaml` 模型註解、設定頁模型大小 | 註解仍寫 int8／416／2.87 MB；實際清單為九類 Float32／640／10,694,183 bytes | 屬工程現況修正，第一、二階段實作時更正；模型檔本身不刪不換 |

## 3 應保留的來源及有效文件

- `../../FinalYearProject-3.docx`：FYP 原始背景；不是 App 功能已完成的證明。
- `../../labelObject_workload 20260920-2.xlsx`：初期未訓練的類別需求來源，仍支援刪減審核的追溯。
- `docs/THIRD-PARTY-DATA.md`：來源與署名記錄。雖涉及舊實驗，也不能隨意刪除；目前九類是否沿用各來源仍需逐項核對。
- `docs/DATASET-CLASS-REVIEW.zh-HK.md`、`docs/DATASET-TRAINING.zh-HK.md`：類別去留、模型分工與訓練規格，仍被其他方案引用。
- `docs/ACCESSIBILITY-RESEARCH.zh-HK.md`、`docs/FRONTEND-DESIGN.zh-HK.md`：研究來源、讀屏規格、流程與待驗證假設。
- `docs/INTEGRATED-DESIGN.zh-HK.md`：三部分方案的交接索引。
- `docs/word/PathGuide-Frontend-Plan.zh-HK.docx`、Dataset 方案及 Backend 方案：目前交付給導師／組員的可閱讀版本。後端為 1.1，其餘為 1.0；不是可刪除的舊備份。
- `app/assets/models/detector.json`、`detector.tflite`、`configs/classes.json` 及現有自動測試：執行資產與版本依據，不能當舊文件清理。
- `../../pathguide-colab/`、`../../pathguide-hk-8classes/`、`../../firebaseCode-2/`：訓練、資料及後端起點；未做完整可替代性檢查，不列為刪除候選。

## 4 建議覆核次序

1. 先決定舊 ZIP 是否需要保留作原始交付備份，再核對其獨有檔案。
2. 選擇把 Flutter README 改寫，或刪除範本文字。
3. 確認是否把舊模型實驗抽成歷史附錄；現行模型入口繼續保留。
4. Word 關閉後再確認鎖定檔是否殘留。

使用者批准前，以上清理建議均不執行。正常開發所需的程式、操作說明及新增驗收紀錄，與歷史文件刪除分開處理。
