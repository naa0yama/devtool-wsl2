---
title: bootstrap.sh 設計
status: accepted
date: 2026-07-20
source_spec: ../../../.claude/artifacts/plans/2026-07-20-qcow2-fixed-user-ciuser-redirect.md
---

# bootstrap.sh 設計

## 1. 概要

`scripts/provision/bootstrap.sh` は devtool-wsl2 の 3 経路
(WSL2 baked / qcow2 baked / bare Ubuntu) 共通の provisioning entry point。
stage 0 (provision tarball 取得) → phase 1 (system 層) → phase 2 (user 層) の順で実行する。

関連 ADR: [`../../adr/latest/0006-common-bootstrap-vestibule-user.md`](../../adr/latest/0006-common-bootstrap-vestibule-user.md)

呼び出し元:

| 経路 | 呼び出し方法 |
|------|-------------|
| qcow2 baked | `scripts/image/provision-chroot.sh` 経由 (guestmount+chroot) |
| WSL2 / Docker | Dockerfile / build.yml の `RUN` loop |
| bare Ubuntu | `curl … | sudo bash` 直接 |

---

## 2. 環境変数

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `DEVTOOL_ENV` | auto-detect | 実行環境 (`wsl2`/`vm`/`container`/`bare`) |
| `PROVISION_ROOT` | (unset) | テスト seam: provision dir を直接指定するとfetch をスキップ |
| `DEVTOOL_USER_SHELL` | `/bin/bash` | phase 1 で作成するユーザーのシェル |
| `DEVTOOL_PHASE2_UID` | `${EUID}` | phase 2 実行 UID 検証値 (CI seam 用) |
| `DEFAULT_USERNAME` | `user` | 作成するユーザー名 |
| `DEVTOOL_TAG` | `main` | Release tarball 取得タグ |
| `DEVTOOL_REPO` | `naa0yama/devtool-wsl2` | GitHub リポジトリ |
| `DEVTOOL_SKIP_PROVISION_FETCH` | (unset) | 設定時 tarball fetch をスキップ |

---

## 3. 実行フロー

```
bootstrap.sh
  │
  ├─ stage 0 (bare Ubuntu 経路のみ)
  │    ├─ devtool-provision.tar.gz を GitHub Releases から fetch
  │    ├─ /tmp/devtool-provision/ に展開
  │    └─ chmod -R a+rX /tmp/devtool-provision/  (umask 逸脱対策)
  │
  ├─ phase 1 (EUID=0, system 層)
  │    ├─ system/15-user.sh  — uid=1100 user 作成 (shell=/bin/bash)
  │    ├─ system/20-docker-engine.sh  — docker-ce インストール
  │    ├─ system/40-cleanup-ubuntu.sh  — 不要パッケージ除去
  │    └─ exec sudo -u user ... bootstrap.sh  (phase 2 へ再実行)
  │
  └─ phase 2 (EUID=1100, user 層)
       ├─ user/10-mise-install.sh
       ├─ user/20-bashrc.sh
       ├─ user/30-fish-config.sh
       └─ user/40-mise-config.sh
```

---

## 4. 環境検出 (seam-2)

`detect_env()` が `/proc/version` / `/.dockerenv` / `systemd-detect-virt` を検査して
`DEVTOOL_ENV` を自動設定する。テスト時は環境変数で上書き可能 (seam-2)。

| 判定条件 | 値 |
|----------|----|
| `/.dockerenv` 存在 または cgroup に `docker`/`containerd`/`lxc` | `container` |
| `/proc/version` に `microsoft` または `WSL` | `wsl2` |
| `systemd-detect-virt` が `kvm`/`qemu`/`vmware` 等 | `vm` |
| いずれにも該当しない | `bare` |

---

## 5. stage 0: self-download (bare Ubuntu 経路のみ)

`PROVISION_ROOT` が未設定かつ `DEVTOOL_SKIP_PROVISION_FETCH` が未設定の場合、
GitHub Releases から provision tarball を fetch する。

```
PROVISION_ASSET_URL=
  https://github.com/${DEVTOOL_REPO}/releases/download/${DEVTOOL_TAG}/devtool-provision.tar.gz
```

fetch 後に `chmod -R a+rX` を実行して、umask 逸脱環境でも phase 2 (uid=1100) から
読取可能にする。

---

## 6. Release asset

`release.yml` が以下の 2 asset を GitHub Releases にアップロードする:

| ファイル | 内容 |
|----------|------|
| `devtool-bootstrap.sh` | bootstrap.sh のコピー (curl 直接実行可能) |
| `devtool-provision.tar.gz` | `scripts/provision/` のアーカイブ |

---

## 7. 参照

- [`scripts/provision/bootstrap.sh`](../../../scripts/provision/bootstrap.sh)
- [`docs/adr/latest/0006-common-bootstrap-vestibule-user.md`](../../adr/latest/0006-common-bootstrap-vestibule-user.md)
- [`docs/guides/bare-ubuntu.md`](../guides/bare-ubuntu.md)
- [`docs/guides/pve-import.md`](../guides/pve-import.md)
- [`.github/workflows/release.yml`](../../../.github/workflows/release.yml)
- [`.github/workflows/qcow2.yml`](../../../.github/workflows/qcow2.yml)
