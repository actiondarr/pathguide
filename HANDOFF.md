# PathGuide handoff

Updated: 2026-10-27 (Asia/Hong_Kong).

User review entry: [App versus previous plan](docs/APP-PLAN-REVIEW.zh-HK.md).
Updated frontend, backend, dataset review/training and contract documents are linked there.
This is a documentation update, not an implementation or model release.

## User-confirmed priorities

- The main goal is for recognition accuracy to improve with use. FSD-style
  visualization supports that goal. Do not equate more photos or completed
  training with proven improvement.
- Personal learning uses consented, UID-isolated photos, administrator-reviewed
  annotations, versioned training snapshots, and independent evaluation against
  the current model. Retain the previous model when evaluation fails.
- Indoor v1 targets the existing iPhone 15 Pro Max on a fixed HKDI single-floor
  route: a bird's-eye scene and short-range guidance over observed space.
  Room-to-room destination routing is a later step.
- Users may opt into personal model updates during idle time, with validation
  and rollback. Cloud GPU deployment is to be prepared with paid execution
  disabled until a budget is agreed.

## Required GitHub version checkpoint

The user explicitly requires every completed version to be uploaded to GitHub
before installing or handing over the new version, so an older version remains
recoverable if the new version does not work.

- Repository: https://github.com/actiondarr/pathguide.git (`origin`).
- Use a unique increasing App version/build number and an immutable annotated
  tag `v<version>+<build>` for each completed App version. Never move or replace
  an existing release tag, and never force-push version history.
- Commit the reviewed source, dependency lockfiles, model manifest/mapping, and
  applicable tests/docs. Do not include credentials, private user photos,
  training datasets, or generated build directories.
- This GitHub rule covers App source and shared models only. Never put private
  photos, per-user weights, or private evaluation content in the shared repository.
  Preserve private rollback versions in authenticated UID-scoped storage instead.
- Preserve the exact shared model binaries referenced by that version: include small
  models in Git as already used here; use GitHub Release assets for binaries too
  large for normal Git. Record SHA256 and an exact asset reference when external.
  A code tag without its matching model is not a complete rollback checkpoint.
- Create a GitHub Release for the tag with changes, known limitations, validation
  results, model versions/hashes, and rebuild/reinstall instructions. Mark
  experimental versions as prereleases; do not describe them as validated stable.
- Push the commit and tag, then verify the remote tag resolves to the intended
  commit and any model assets are available. Only then install/deliver the new
  version. If upload is blocked, report that and keep the version pending.
- Keep previous releases and models. Roll back by rebuilding/reinstalling the
  chosen tag with its matching model; use a fresh increasing iOS build number
  where distribution requires it. GitHub source history alone does not provide
  a one-tap iPhone downgrade or preserve the validity of signing credentials.

## Observed baseline

- Working branch: `feature/cross-platform-navigation`; existing uncommitted
  changes and untracked work must be preserved and reviewed before any release.
- Bundled A model: `2026-10-27.mixed10.experimental.1`, ten classes. Its local
  TFLite SHA256 matches its manifest. Door validation precision is 28.6% and
  recall 11.1%; the validation gate failed. This is a user-requested trial.
- B currently has a prepared eleven-class experimental snapshot/package, not
  twelve active classes. No completed B training was verified in this session.
- Existing navigation is MapKit outdoor walking navigation. Indoor depth,
  spatial tracking, local path guidance, personal training orchestration and
  private model downloads still need implementation.
- Earlier, `gh auth status` reported an invalid GitHub CLI token. Git push
  nevertheless succeeded through Git's existing authentication after explicit
  user approval; do not assume the GitHub CLI token was repaired.
- Documentation audit commit: `3eec3a3` (12 selected documentation files only).
  Read-only `git ls-remote` confirmed the existing branch at `7aa84b3`.
  The initial push was rejected by automatic approval review; the user then
  explicitly approved these 12 documents and this repository/branch.
  Push succeeded and `git ls-remote` verified the remote branch at
  `8a2e7ed6ccd47e151a45199b18b893e26d3a9b0e` (including the audit and B11
  handoff notes). This is a documentation checkpoint only, not an App release;
  App/model changes remain uncommitted. Later uncommitted changes to the B11
  handoff were preserved and were not included in this upload.
- Detailed evidence: `docs/dataset-work/2026-10-26/MODEL-STATUS.zh-HK.md`,
  `dataset_pipeline/snapshots/sign-icon-demo11-v1-20261027/summary.json`, and
  `docs/baselines/2026-10-27.iphone-navigation-phase-b.md`. The snapshot is local
  ignored data and must be archived separately when required, not assumed to
  exist in a Git checkout.
