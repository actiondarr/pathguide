# 領路通 PathGuide 文件索引

更新日期：2026年10月27日。

**先讀 [目前App與原計劃對照](APP-PLAN-REVIEW.zh-HK.md)**：包含實作現況、證據限制、差距與下一輪優先次序。

| 文件 | 閱讀內容 |
|---|---|
| [前端與裝置端](FRONTEND-DESIGN.zh-HK.md) | 學習進度、照片回報、私人更新、室內鳥瞰與短路徑 |
| [後端與雲端](BACKEND-DESIGN.zh-HK.md) | 活動callable、覆核、worker、registry、預算與刪除 |
| [Dataset覆核與改善](DATASET-REVIEW.zh-HK.md) | 十類A／十一類B、人工答案、分組、品質門檻與版本報告 |
| [Dataset訓練方案](DATASET-TRAINING.zh-HK.md) | 模型分工、歷史候選、覆核／訓練及方向研究 |
| [類別來源審核](DATASET-CLASS-REVIEW.zh-HK.md) | 52個登記項目的來源及去留；不是52類已訓練能力 |
| [階段安排](IMPLEMENTATION-ROADMAP.zh-HK.md) | 交付優先次序、現況與完成條件 |
| [資料契約](DATA-CONTRACT.v1.zh-HK.md) | 歷史v1、現行照片附錄與新接口待實作邊界 |
| [交接與GitHub規則](../HANDOFF.md) | 每版先備份再安裝，保留共用及私人模型的不同回退方式 |

核心流程：同意收集 → 候選照片 → 管理員覆核 → UID快照 → 批次訓練 → 獨立比較 → 合格才更新 → 保留回退。收費GPU在預算設定前不提交；私人照片／權重不進共用GitHub。

目前有十類試驗與九類備援、Google帳號、照片程式、戶外導航及菜單OCR；室內感知、私人訓練／下載仍待實作。程式存在不等於雲端接通、真機驗收或已證明更準。

操作與實作證據另見 [照片第四階段](PHASE4-IMPLEMENTATION.zh-HK.md)、[導航](NAVIGATION.zh-HK.md)、[菜單](MENU-READING.zh-HK.md)、[帳號](ACCOUNT-REGISTRATION.zh-HK.md)。舊Word及日期化驗收紀錄保留原快照，本輪未更新Word。
