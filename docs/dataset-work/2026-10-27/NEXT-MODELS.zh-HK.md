# A 模型改善與 B 模型啟動紀錄

2026-10-27，依用戶指示先將完成的新版 A 放入 App，再繼續準備原定第二個 B 模型。用戶明確批准以未通過門品質門檻的候選作 App 試用；不代表模型品質已達標。

## 2026-10-27後續核對（取代下方早上狀態）

- A為十類試驗版，門precision28.6%、recall11.1%、gate=false；下一輪優先錯誤分析與HKDI評估，不盲目增加epochs。
- B活動實驗設定已改sign-icon-demo11-v1，一般toilet_symbol延後，原12類路線圖保留。
- 已有本地實驗snapshot：3,327圖，2,301 train／469 val／557 test，來源含插圖與增強，抽樣篩查不等於完整人工覆核；exit train僅13框。
- 已有Colab訓練套件與入口，尚未核實完成B訓練或App整合。下方「缺快照／未下載」描述為早上歷史狀態，不再代表最新進度；不由舊GPU限制推斷目前額度。
- 私人學習、評估、更新及GitHub回退規則依 [Dataset覆核](../../DATASET-REVIEW.zh-HK.md)與[總對照](../../APP-PLAN-REVIEW.zh-HK.md)。

## 原定分工

- A：即時物件偵測，目前十類；後續候選共23類，未標齊的類別不能當已訓練。
- B：牌內多圖示／箭嘴偵測，獨立 sign-icon-v1 共12類；不是另訓練室內／室外或專門門模型。
- OCR：使用現成文字辨識，不為路名逐個新增class。
- 依據：docs/DATASET-TRAINING.zh-HK.md 第3節、docs/dataset-work/2026-10-22/TRAINING-STRATEGY-v2.zh-HK.md。

## A 的下一步

1. 門現有驗證18框只有TP2/FP5/FN16，與校園來源340張訓練圖存在明顯跨來源落差；先用 validation 看錯誤樣式、尺寸及分數，不用test挑參數。
2. 篩選更多不同校園／課室木門、半開、側面及背光的既有框資料。以實體門／影片／來源場景分組去重；不得只靠增加同一門影格或重複抽樣充數。
3. 核對「門板／完整門口」框定義及漏標；保留未知類別遮罩。櫃門／窗等反例須核實啟用類別標註完整性，不能把未標門當背景。
4. person AP50從61.01降至56.13，需分小物件／遮擋分析；加入新門資料時保留舊類 replay及逐類退化比較。
5. 固定新snapshot後先短試跑，再由本次十類best.pt開始新fine-tune run，不用resume改資料，也不再套舊HK9 head重排。

## B 已完成的準備與缺口

- 用戶已批准首輪訓練成熟11類，保留原12類計劃；通用洗手間圖示暫緩。首輪設定 `dataset_pipeline/configs/sign-icon-demo11-v1.json`，namespace `sign-icon-demo11-v1`。
- 已下載並篩選 RnE pictogram_detection v2、eyeway subway-guide v10、arrowsicons arrows_icons-pmnkv v2、icons-wrs49 icons-vbuao v3 的既有偵測標註；不把實體樓梯／升降機當圖示，不把WC文字當通用洗手間圖示。
- snapshot `dataset_pipeline/snapshots/sign-icon-demo11-v1-20261027`：3,327張匯出圖片；候選場景／相似雜湊群組2,997；train 2,301、val 469、test 557。這些不是香港實景測試資料，部分來源僅抽樣人工檢查。
- 資料SHA、標籤、類別覆蓋、場景／像素分割檢查通過；12項單元測試通過。11張圖片的CPU單輪整合試跑完成，只證明流程可執行，不能作準確率或部署依據。
- 出口圖示仍薄弱：train12／val5／test5，不能因為已納入就稱為成熟。
- 可執行入口 `dataset_pipeline/colab_train_sign_icons.py`：Ultralytics8.4.182、YOLO11n獨立預訓練起點、2 epoch smoke後60 epoch正式run、patience12；禁止翻轉／旋轉，逐輪備份。
- 使用者要求複製至另一個登入帳戶，已建立副本及上傳套件；GPU已連到T4。目前等待新帳戶Drive掛載，尚未確認正式訓練開始。詳見 [B11目前狀態](B11-CURRENT-STATUS.zh-HK.md)。
- 完成後核對逐類AP50及conf0.30的TP／FP／FN；不以fitness稱準確率，不部署未驗證的B模型。
