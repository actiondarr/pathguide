# 領路通：iPhone 無障礙導航與環境辨識 Demo

2026-10-27 最新閱讀入口：[App與原計劃對照](docs/APP-PLAN-REVIEW.zh-HK.md)。已對齊前端、後端、Dataset覆核與私人學習規格；目前十類模型仍為試驗版，室內感知及私人自動訓練尚未實作。每個完成版本先備份GitHub再交付，見 [交接](HANDOFF.md)。

第三階段已加入 Google 登入與選填緊急聯絡人；Firebase 設定及真機驗收待完成。請見 [接入指引](docs/PHASE3-IMPLEMENTATION.zh-HK.md) 及 [新版階段安排](docs/IMPLEMENTATION-ROADMAP.zh-HK.md)。未配置時可繼續訪客辨識，沒有照片上傳或訓練。

請先閱讀 [第一、二階段實作與驗收](docs/PHASE1-2-IMPLEMENTATION.zh-HK.md)，然後在 Mac 的 `app/` 資料夾執行 Flutter 檢查及建置。安裝步驟仍見 [iPhone 說明](docs/IOS-DEMO.md)。

App 現以任務首頁啟動，提供即時辨識、路線導航、讀取菜單及設定與使用教學。選擇「即時辨識」便會啟動相機及自動播報。主畫面以相機預覽為主，底部只留「暫停／繼續辨識」及「更多操作」；重播、播報開關及辨識設定集中在面板內。讀屏與 TTS 共用單一輸出路徑。目前預設十類試驗TFLite，九類備援及模擬模式保留。最低 iOS 15。

導航現已接入 iPhone MapKit 搜尋、步行路線及前景定位；Android 適配與 Google 路線代理已加入程式，仍需設定及 Android 建置驗證。導航不保存行走軌跡；離頁或切背景停止定位。菜單功能狀態見下文。進入背景或離開辨識頁會停止辨識；中斷前正在辨識的任務返回前景會自動恢復，手動暫停則保持暫停。

第一階段交接文件：[資料契約 v1](docs/DATA-CONTRACT.v1.zh-HK.md)、[工程基線](docs/baselines/2026-10-22.phase1.json)。文件清理建議見 [待覆核清單](docs/DOCUMENT-AUDIT.zh-HK.md)，未經使用者批准不刪除原有文件。

PathGuide: Flutter accessibility navigation and on-device object recognition app.

Dataset 工作入口：[2026 年 10 月 22 日資料盤點、標註手冊及訓練準備](docs/dataset-work/2026-10-22/README.zh-HK.md)。已完成全量程式檢查及試標草稿；該日盤點為歷史基線；後續十類混合試驗已完成，B十一類實驗快照已準備，品質限制與最新進度以閱讀入口為準。

第四階段照片收集／私人上傳程式及部署要求：[接入說明](docs/PHASE4-IMPLEMENTATION.zh-HK.md)。帳號測試專案已接通；照片服務缺省關閉，尚未部署。iPhone 安裝請使用 `app/tool/run_iphone.sh` 以保留 Firebase 設定。

菜單閱讀首版：首頁「菜單閱讀與語音搜尋」，iPhone 本機 OCR、粵語菜名搜尋及自動讀價，毋須 Firebase。功能及真機測試清單見 [菜單閱讀](docs/MENU-READING.zh-HK.md)。

地圖導航第一版：[功能、雙平台架構、Android／Routes 設定及實地驗收](docs/NAVIGATION.zh-HK.md)。iPhone 需重新完整安裝及實走驗收；Android／Google 服務沒有部署或接通，不能把工程測試當作真機通過。
