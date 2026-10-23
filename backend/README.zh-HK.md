# 第三階段 Firestore 規則

目前只提供 Google 帳號、本人緊急聯絡資料及最小刪除保護規則，沒有 Cloud Functions／Storage 部署。App 接入步驟見 [第三階段交接](../docs/PHASE3-IMPLEMENTATION.zh-HK.md)。

本機測試需要 Node 22 以上、Java 21 以上及 pnpm：

```sh
pnpm install --ignore-scripts
pnpm test
```

測試固定使用 `demo-pathguide-phase3`，只啟動 localhost Firestore Emulator，不使用正式專案或管理員私鑰。預期拒絕會在日誌出現 PERMISSION_DENIED。

規則涵蓋本人存取、固定 profile 欄位、Google provider、聯絡資料格式、不可提升權限、重新驗證後刪除及阻止舊 UID 重建。其他集合預設拒絕。

正式部署前由 backend 組員合併現有專案規則；本規則不能直接覆蓋已有其他服務的專案而不覆核。第四階段接入照片之前，須加入同意、上傳、角色及完整後端刪除，不能用本階段有限清理代替。

第四階段增加獨立 `functions/`、私人 `storage.rules`、索引及本機照片整合測試。先在 functions 執行 `pnpm install --ignore-workspace --ignore-scripts`，再在本目錄執行 `pnpm test`；需要 Java 21、Node 22。部署及 App Check／Blaze 要求見 [第四階段交接](../docs/PHASE4-IMPLEMENTATION.zh-HK.md)。尚未部署雲端服務。
