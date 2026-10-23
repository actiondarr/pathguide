# 領路通 PathGuide 方案文件索引

更新日期：2026 年 10 月 23 日

最新 Dataset／Backend 對齊討論：[類別整理及字典討論稿](CLASS-DICTIONARY-DISCUSSION.zh-HK.md)，包含 COCO 選用、自訂類別、sign-icon-v1 及合併驗證方法。[候選 JSON](class_dictionary.proposal.json) 供核對，不能直接覆蓋正式字典；最新 OneDrive schema 與正式 ID 尚待組員確認。

最新開發入口：[新版階段安排](IMPLEMENTATION-ROADMAP.zh-HK.md)、[第三階段實作與接入](PHASE3-IMPLEMENTATION.zh-HK.md)。Google 登入優先，緊急聯絡人可選填及主動撥號。

方案已按前端、Dataset 與後端分檔；本頁只提供閱讀入口及交接關係，不再集中存放各部分的詳細規格。

## 1. 三份主要方案

| 文件 | 閱讀內容 |
|---|---|
| [前端與裝置端方案](FRONTEND-DESIGN.zh-HK.md) | 使用者操作、VoiceOver／TalkBack、相機與候選擷取、照片同意、本機佇列、扶手電梯方向分析及粵語回饋 |
| [Dataset 與模型訓練方案](DATASET-TRAINING.zh-HK.md) | 現用九類與候選 20 類、類別合併及防重疊規則、按需圖示／離線 OCR、場景切分、私人微調、方向短片及模型評估發佈 |
| [後端與雲端資料流程方案](BACKEND-DESIGN.zh-HK.md) | Firebase 接口、認證、Storage／Firestore、配額與保留、事件去重、覆核狀態及資料匯出 |

新增專題：[帳號註冊與個人模型流程](ACCOUNT-REGISTRATION.zh-HK.md)，定義 Google 優先登入、選填緊急聯絡人、登入時機、UID 歸屬、個人訓練及帳號管理；實作責任仍分到上述三份方案。

Dataset 附錄：[類別來源與刪減審核](DATASET-CLASS-REVIEW.zh-HK.md)，核對原始工作表、FYP、兩套字典，逐項記錄 52 個舊 ID 的保留、合併、延後及任務分流理由。

扶手電梯方向亦按責任拆分：使用者如何查詢及手機如何分析放在前端；短片如何收集、標註及評估放在 Dataset；雲端只處理已同意的照片，不接收方向查詢的連續畫面。

## 2. 共通交接與開發次序

```text
前端：訪客基本辨識，Google 登入後另行選擇照片用途同意
  → 綁定 Firebase UID 的候選照片
後端：驗證、儲存、去重與覆核進度
  → 已核准影像、標註及來源版本
Dataset：按 UID 切分、批次微調與評估
  → 私人模型、清單及標籤經授權下載；內置基礎模型隨 App 提供
```

先完成現有辨識的無障礙操作與 Google 登入，再接 UID 照片歸屬、覆核、每人批次微調及私人模型下載；扶手電梯方向另作受控研究原型。導航與菜單按後續任務另行實作，模型不在背景自動切換。

新設計尚未實作或通過使用者驗收，低信心門檻、配額與方向觀察窗口均屬待校準預設。階段 1／2 及第三階段帳號程式已加入；Firebase 正式接通及真機驗收待完成。照片、訓練及模型下載尚未接入，現有模型未改。

## 3. 背景與詳細參考

- [專案背景與現況](PROJECT-OVERVIEW.zh-HK.md)：FYP 動機、目前 App 功能及現況限制。
- [無障礙研究與操作設計](ACCESSIBILITY-RESEARCH.zh-HK.md)：公開研究來源、導航／菜單文字線框及完整讀屏驗收。
- [模型說明](MODELS.md)：目前九類模型及歷史版本記錄。
