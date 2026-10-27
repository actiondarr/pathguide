# PathGuide Dataset 覆核與準確度改善

更新：2026年10月27日。唯一Dataset Review文件；[Frontend](FRONTEND-DESIGN.zh-HK.md)管理App，[Backend](BACKEND-DESIGN.zh-HK.md)管理服務與版本。資料、類別、模型或訓練進度改動必須同一提交更新此檔，不另開日期化狀態稿。私人訓練服務尚未接通。

## 1. 實際基線

目標是用新場景改善辨識，以獨立資料回答：哪些類別／場景變好、誤報與漏報有何變化、其他類別有沒有退步。

| 模組 | 已核對狀態 | 缺口 |
|---|---|---|
| A 主物件 | 2026-10-27.mixed10.experimental.1，十類；九類另作備援 | 門 precision 28.6%、recall 11.1%，僅18個小型外國驗證框；gate=false |
| A 其他類別 | person AP50 56.13%，baseline 61.01%；樓梯已合併 | 檢查遺忘；圍欄無獨立驗證，不填虛假準確率 |
| B 圖示 | sign-icon-demo11-v1，11類；2,301／469／557張 train／val／test | 未確認完成訓練；exit train僅13框；樣式／實體獨立性不足 |
| OCR | iPhone 菜單已有系統文字辨識 | 不能代替牌面、樓層及文字／箭嘴配對驗收 |
| 室內幾何 | 尚無 ARKit／LiDAR 評估流程 | 距離、地面、落差及路徑另設真值，不由 A 的 mAP 推定 |

A 十類順序為 person、bicycle、bin、bollard、traffic_cone、caution_slippery、stairs、escalator、fence、door，專案 ID 為 `[6,11,7,8,9,24,1,49,26,18]`。私人首版不自行擴 class。

B 一般 toilet_symbol 延後，活動11類與原12類路線圖分開保存。現有 snapshot 只准實驗訓練；含插圖與來源增強，抽樣篩查不能寫成全量人工覆核。最新13:56交接回報：12項本機測試與11圖CPU流程試跑完成，兩輪GPU smoke後已啟動正式run並備份epoch1。這是交接證據，本輪文件整併未重新讀取Colab，不能當作即時進度或訓練完成。

## 2. 覆核工作流程

1. 只接收有同意、來源與 UID 可追溯的候選；保留拍攝時模型、原始預測與觸發原因。低信心不是新類別，高分也可能錯。
2. 檢查影像、授權、旋轉、重複與場景；同一門、牌、連拍、影片、裁圖及增強歸同組。獨立性不明時保守同組或只進 train。
3. 模型預標註後，由管理員逐張補漏修框；人工答案另存，記錄覆核者、時間、定義與標註版本，不覆蓋原始預測。
4. 私人首版要求十類全圖覆核；只有確認當次目標全部不存在的圖才作完整背景負樣本。
5. 外部部分標註資料只有在 coverage manifest 明確、遮罩損失／評估測試通過時才加入實驗。未知類別不當負樣本，也不在該來源評分；不可直接把 partial 改 approved。
6. 按 UID 與場景凍結 train／val／test，附影像／標註 SHA256、映射、來源授權及基礎資料版本。訓練開始後不再加入照片。

門需統一完整門口／門板框定義，單列木門、玻璃、半開、側視、逆光、遮擋及櫃門／窗反例。室內「未觀測」與「已觀測無障礙」分開記錄，不從沒有物件框推導可行走。

## 3. 訓練與改善判定

核准資料 → 條件檢查 → 排隊 → 微調 → validation → 凍結候選 → 獨立驗收 → 匯出一致性 → 私人發佈。Colab 保留作受人監督的實驗；雲端付費提交在預算設定前關閉。

以下是首輪工程預設，需記錄版本及限制，不是已驗證的產品準確率：

| 項目 | 規則 |
|---|---|
| 排隊 | 至少50張新增核准圖、三個場景，另有與 train 不同組的個人驗證資料；不足顯示資料不足 |
| 回放 | 固定相同 taxonomy 的基礎權重與獲授權資料，不只訓練新圖，不混其他 UID 私人資料 |
| 比較 | 同一資料、conf0.30／IoU0.50比較現用與候選，逐類報TP／FP／FN、precision／recall、AP與樣本量 |
| 更新候選門檻 | 目標類別precision≥80%、recall≥70%，recall至少增加五個百分點；所有可評分類別precision／recall均不得下降超過兩個百分點 |
| 證據不足 | 目標缺真值或不能獨立比較，不自動核准；只列候選／待驗收，不填零或宣稱改善 |
| test | validation選參數，test不參與訓練或選門檻；反覆開發消耗的test需另建保留集並記錄歷史 |
| 手機 | PyTorch／TFLite數值、映射與播報門檻一致；發佈前有延遲、耗電及任務驗收 |

有限樣本只支持該評估範圍。現用十類 gate=false，不得自動升格為核准基礎模型；後續訓練可作實驗，發佈仍需完整檢查。

## 4. 每版報告與還原

保存現用／候選版本、目標類別、來源與實體數、split與分組雜湊、覆核範圍、逐類比較、失敗例、格式檢查、真機結果、限制與發佈判定。先提供誤報／漏報，再提供平均mAP，不用單一「準確率」概括所有任務。

共用 App／模型先完成 GitHub commit、tag／Release與遠端核對，再安裝交付；保留上一版模型、映射與安裝說明。私人照片／權重留在受授權私人儲存，不進共用repo。版本程序集中在Backend第7節。

## 5. B11訓練交接（持續在本節更新）

| 欄位 | 最近已記錄證據 |
|---|---|
| 正式run | 20261027T055450Z-full，獨立YOLO11n預訓練起點 |
| 最近checkpoint | epoch1/60，UTC 2026-10-27T05:55:35.603562+00:00，交接回報備份成功 |
| 已完成smoke | 20261027T055254Z-smoke，兩輪及validation；不能當正式結果 |
| 正式設定 | Ultralytics8.4.182、640、batch16、最多60 epochs、patience12，不翻轉／旋轉 |
| Drive輸出 | MyDrive/PathGuide/sign-icon-models/sign-icon-demo11-v1/20261027T055450Z-full/，本人授權空間 |
| 跟進 | 已有每15分鐘跟進；其舊文件路徑更新被工具用量限制阻擋，尚未執行，需額度恢復後修改既有跟進；不要因此重啟訓練 |
| 尚未確認 | 正式完成、best.pt評估、獨立test及App整合，不部署未驗證B |

不要Run all、重跑launcher／force_remount、刪launcher-state或混用A／smoke結果。中斷先查活躍程序與checkpoint、optimizer、CSV、SHA及UTC，再確認正確resume；資料或taxonomy改變需新run。私人帳戶／Notebook識別只留既有受權跟進，不寫公開文件。

現行工具：dataset_pipeline/colab_train_sign_icons.py、coverage_training.py及evaluate_sign_icons.py；配置在dataset_pipeline/configs/sign-icon-demo11-v1.json。A變更資料後應從相容十類權重開始新fine-tune，不用resume改快照，也不套回舊HK9 head重排。只有相同資料／設定的中斷才續跑。

## 6. 下一輪清單

- [ ] 建立 HKDI 不同門與走廊的分組基準，補暗光、玻璃、半開門與反例。
- [ ] 分析門 FP／FN及person退化，驗證新資料是否改善未見場景。
- [ ] 核對B全圖coverage、exit資料與場景獨立性；先smoke再正式訓練，不沿用A全域ID。
- [ ] 用模擬worker驗證私人覆核、訓練、發佈與回退；預算未定不提交付費GPU。
- [ ] 為室內距離、地面及路徑另建真值、失效與拒答案例。


## 7. 來源、授權與可重現資料

原始影像／標籤保留，不因文件清理而改成已覆核。類別字典、資料集本地索引、專案ID及外部COCO／Firebase ID分開映射；52項登記與20／23類候選不代表模型已支援。歷史提案僅供查考，不直接覆蓋活動映射。

| 來源 | 狀態／需保留的來源資料 |
|---|---|
| HK9原來源 | 準備後9,549 train／1,374 val／620 test；歷史split可能有場景重疊，不宣稱全獨立 |
| 新室內門 | 340圖／403原門框作實驗train，來源只宣告door覆蓋；不是340個獨立實體門 |
| 澳門圍欄 | 436來源圖作實驗；保留原框定義，沒有新獨立圍欄benchmark |
| Open Images門 | 27圖：14 val／13 test；逐圖作者與圖像CC BY2.0、框CC BY4.0資料隨來源保留；外國小樣本不是HKDI準確率 |
| [icons-wrs49/icons-vbuao v3](https://universe.roboflow.com/icons-wrs49/icons-vbuao/dataset/3) | B來源，聲明CC BY4.0；與其他來源按像素／相似群組隔離 |
| [arrowsicons/arrows_icons-pmnkv v2](https://universe.roboflow.com/arrowsicons/arrows_icons-pmnkv/dataset/2) | B既有偵測框來源，聲明CC BY4.0；不把分類標籤當整圖框 |
| [eyeway/subway-guide v10](https://universe.roboflow.com/eyeway/subway-guide/dataset/10) | B來源，聲明CC BY4.0；實體設施與牌內圖示分開 |
| [rne/pictogram_detection v2](https://universe.roboflow.com/rne/pictogram_detection/dataset/2) | B來源，聲明CC BY4.0；方向／別名需明確映射 |
| [Everyday Object Finder v3](https://universe.roboflow.com/chris-law/everyday-object-finder/dataset/3) | 歷史來源聲明CC BY4.0，但含網絡／素材來源疑點，不宣稱逐圖權利已核實；原用法只train，不把舊實驗統計當本輪結果 |
| [People Detection v1](https://universe.roboflow.com/chris-law/people-detection-o4rdr-nlryq/dataset/1) | 歷史聚合導出聲明Private、部分上游未聲明；保留研究限定與不重分發記錄，不因清理而自動核准新用途 |
| Wikimedia候選 | 歷史記錄901圖、16類、尚未用；CC BY／BY-SA／CC0等逐圖作者、license與URL必須隨資料保留，只有整圖標籤不作偵測真值 |

People Detection原附README的上游署名保留如下；這是來源記錄，不表示所有上游已重新核准或納入目前訓練：

| 上游项目 | 许可 |
|---|---|
| [First Pedestrian Test](https://universe.roboflow.com/safer-strides/first-pedestrian-test) | CC BY 4.0 |
| [person_camera_security1](https://universe.roboflow.com/chinh/person_camera_security1) | CC BY 4.0 |
| [Human Action Recognition 2000](https://universe.roboflow.com/skripsi-u18dy/human-action-recognition-2000) | CC BY 4.0 |
| [People Detection](https://universe.roboflow.com/chris-kydks/people-detection-2csbw) | CC BY 4.0 |
| [contador-de-gente teste 3](https://universe.roboflow.com/mackleaps/contador-de-gente-teste-3) | CC BY 4.0 |
| [OD3](https://universe.roboflow.com/object-detection-tuphv/od3-fq4yp) | CC BY 4.0 |
| [Person Detection](https://universe.roboflow.com/illimited/person-detection-gbuka) | CC BY 4.0 |
| [MOT17-03-DPM](https://universe.roboflow.com/bhu-ykklm/mot17-03-dpm-udorc) | ⚠️ **未声明** |
| [The Curve](https://universe.roboflow.com/people-8gcmt/the-curve-02) | CC BY 4.0 |
| [pedestrain safety](https://universe.roboflow.com/intel-9horw/pedestrian-safety-obyfo) | CC BY 4.0 |
| [People Detection](https://universe.roboflow.com/jmedel/people-detection-f0fgt) | CC BY 4.0 |
| [people、rabish](https://universe.roboflow.com/cpk-wow-k5nlf/people-rabish) | CC BY 4.0 |
| [Pascal VOC 2012](https://universe.roboflow.com/jacob-solawetz/pascal-voc-2012) | CC BY 4.0 |
| [Person Detection (General)](https://universe.roboflow.com/mohamed-traore-2ekkp/people-detection-general) | CC BY 4.0 |

模型來源記錄：YOLO11／YOLO-World為Ultralytics（原記錄AGPL-3.0），SAM2.1為Meta（Apache-2.0），Grounding DINO為IDEA-Research（Apache-2.0），LocateAnything依其模型卡。實際使用版本的授權與逐圖署名保留，不將歷史來源聲明當成新權利審查。

快照保留影像／標註SHA、授權、coverage、場景分組與split；LICENSE-SOURCES.json及audit.json跟snapshot。原docs內機器證據移到verification/，候選提案移到configs/planning/，本機覆核CSV／圖片等移到dataset_pipeline/review_artifacts/；工具新輸出不得再寫進docs。舊文件已移出工作閱讀區，Git內已提交版本可由歷史還原，本機未提交舊稿另有清理前備份。

## 8. 維護紀錄

2026-10-27：將訓練方案、類別審核、A／B狀態、來源署名與評估整合為本文件；修正B正式run已啟動的交接資訊。本輪未改模型、未重跑訓練，不把進度交接當成新checkpoint驗證。舊稿已刪，清理前原檔另有可恢復本機備份；資料／驗證檔移位後雜湊一致，資料工具路徑已同步調整且Python語法檢查通過。背景跟進的文件路徑更新因自動審批工具用量限制未執行，未繞過限制。後續結果直接覆寫現況並記日期、run、證據與限制，不再新增第四份文件。
