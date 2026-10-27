# 領路通新版開發階段

更新日期：2026 年 10 月 27 日。Google 登入優先；基本離線辨識保留訪客模式。帳號使用共用基礎模型，後續只將該 UID 的核准資料加入個人微調，不混入其他人的私人資料。

最新對照見 [App與原計劃](APP-PLAN-REVIEW.zh-HK.md)。主目標由「增加類別／功能」聚焦為「可量測地改善準確度」；下表保留既有階段編號，新優先次序見第0節。

## 0. 最新交付次序

1. 建立HKDI分組評估基準，改善門漏認及person退化；每輪比較誤報、漏報與限制。
2. 每個完成的App版本先推GitHub commit、共用模型、tag／Release並核對，再安裝；私人產物不進共用repo。
3. 接通同意、UID照片與管理員覆核，建立私人快照、模擬worker及評估／回退；收費GPU在預算設定前關閉。
4. 加入另行預先同意的閒置自動更新；未同意保留手動，任務進行時不切換。
5. 用現有Pro Max在HKDI固定走廊驗證ARKit／LiDAR、鳥瞰與短路徑；指定課室／跨樓層另階段。

新功能未因本次文件更新而實作。舊Word為歷史快照，最新規格以上述入口及Markdown為準。

| 階段 | 交付 | 現況及驗收關卡 |
|---|---|---|
| 1 工程與資料契約 | 模型、類別映射、UID、照片及版本規則 | 基線完成；本輪同步 Google 優先及聯絡人資料契約 |
| 2 即時辨識 | 自動開始與播報、簡潔介面、更多操作、暫停及恢復 | 原階段 127 項測試及 iOS 建置通過；真機及視障使用者驗收待完成 |
| 3 帳號及聯絡 | Google 登入、初始化、恢復、登出、刪除、選填聯絡人及系統撥號 | 已接入 pathguide-dev；使用者回報帳號及聯絡人真機流程完成；逐項 VoiceOver／刪除驗收記錄仍待補齊 |
| 4 收集與上傳 | 獨立照片同意、同幀 JPEG、手動回報、自動抽樣、UID 佇列及私人儲存 | 已加入 iPhone 擷取、同意、加密待傳、配額、私人上傳及清理程式；本機驗證通過／雲端未部署，需 Blaze、Storage 及 App Check |
| 5 HKDI demo Dataset | 定義類別、街道及課室道具補拍、標註、分組切分、訓練及手機驗證 | 可與階段 3 同步；未核准類別不寫入正式字典，不以同一段影片跨集合 |
| 6 個人模型 | 人工覆核、每人快照、自動批次、評估、授權下載與預先同意後閒置更新 | 未接入 App；下載失敗保留可用模型，不能跨 UID 取得資料 |
| 7 後續任務 | Apple／電話登入連結、圖示、牌面 OCR、導航、扶手電梯方向；菜單首版另列 | 菜單及iPhone戶外導航已有程式與安裝紀錄；室內、圖示、方向研究仍待完成，逐項真機依各專題紀錄 |

## 第三階段工作分配

App 工程包括介面、SDK 整合、UID 狀態與延遲回應保護、安全聯絡快取及撥號入口。Backend 交接包括 Firestore 規則及 Emulator 測試，沒有部署至任何正式專案，也沒有使用舊原型管理員私鑰。

使用者／組員負責建立全組共用 Firebase 專案、啟用 Google provider、註冊手機 App、設定協作權限及提供手機端設定，然後進行真機登入／撥號及視障使用者驗收。HKDI 街道和課室拍攝、人工標註及 demo 類別覆核由組員安排。

## 判定完成的方法

工程測試及建置結果與正式服務接通、真機測試分開記錄。第三階段只有在真實 Google 登入、返回原任務、同帳號離線聯絡資料、手動撥號、登出及刪除都通過後，才可稱為完整驗收。

本輪未啟動照片收集、私人訓練、位置分享或自動求助。歷史 Word 文件保留，新版 Word 及 [第三階段接入指引](PHASE3-IMPLEMENTATION.zh-HK.md) 作為目前交接入口。

## 新版 Word 方案

- [前端方案第二版](word/PathGuide-Frontend-Plan.v2.zh-HK.docx)
- [後端方案第二版](word/PathGuide-Backend-Plan.v2.zh-HK.docx)
- [開發階段及分工](word/PathGuide-Implementation-Roadmap.zh-HK.docx)

原有 Word 文件保留，未刪除。

第四階段工程與部署交接見 [照片收集及私人上傳](PHASE4-IMPLEMENTATION.zh-HK.md)。

第四階段同步 Word：[前端第三版](word/PathGuide-Frontend-Plan.v3.zh-HK.docx)、[後端第三版](word/PathGuide-Backend-Plan.v3.zh-HK.docx)、[階段交接第二版](word/PathGuide-Implementation-Roadmap.v2.zh-HK.docx)。

菜單首版見 [菜單閱讀與粵語搜尋](MENU-READING.zh-HK.md)，獨立於 Firebase 照片服務。

## 路線導航第一版（2026-10-23）

已加入共用 Flutter 導航引擎、iPhone MapKit／定位、粵語搜尋、本機收藏，以及 Android Google 適配與獨立 Routes 代理。iPhone 無簽署建置與自動測試不代表實走驗收；Android 尚待 SDK 環境建置、Google 計費／金鑰、App Check 及代理部署。設定與驗收見 [導航接入](NAVIGATION.zh-HK.md)。鎖屏、相機整合、室內路標及路線錄製維持後續階段。
