---
title: bootstrap.sh 設計
status: accepted
date: 2026-07-20
source_spec: ../../../.claude/artifacts/plans/2026-07-20-qcow2-fixed-user-ciuser-redirect.md
---

# bootstrap.sh 設計

## 1. 概要

`scripts/provision/bootstrap.sh` は devtool-wsl2 の 2 経路
(WSL2 baked / bare Ubuntu・VM) 共通の provisioning entry point。
`main()` が source 取得 → system 層 → user 層 の順で実行する
(stage 0 / phase 1 / phase 2 は bare Ubuntu の curl oneliner 経路のみが使う自己再実行モデル、下記「3. 実行フロー」参照)。

関連 ADR: [`../../adr/latest/0006-common-bootstrap-vestibule-user.md`](../../adr/latest/0006-common-bootstrap-vestibule-user.md)、
[`../../adr/latest/0007-vm-bootstrap-oneliner.md`](../../adr/latest/0007-vm-bootstrap-oneliner.md)

呼び出し元:

| 経路                             | 呼び出し方法                                                                                                                                                        |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| WSL2 / Docker                    | Dockerfile / build.yml の `RUN` loop (provision scripts を直接実行)                                                                                                 |
| bare Ubuntu / VM (Proxmox VE 等) | `curl … \| sudo bash` 直接 (`main()` 実行)                                                                                                                          |
| CI 検証 (lxc-test)               | build.yml が `main()` を LXC container 上で実行し、`DEVTOOL_SRC_URL` で PR checkout を配信して完成度を検証 (詳細: [`../ci/vm-boot-test.md`](../ci/vm-boot-test.md)) |

---

## 2. 環境変数

| 変数                           | デフォルト              | 説明                                                                                                                                                                                                                    |
| ------------------------------ | ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DEVTOOL_ENV`                  | auto-detect             | 実行環境 (`wsl2`/`vm`/`container`/`bare`)                                                                                                                                                                               |
| `PROVISION_ROOT`               | (unset)                 | テスト seam: provision dir を直接指定するとfetch をスキップ                                                                                                                                                             |
| `DEVTOOL_USER_SHELL`           | `/bin/bash`             | phase 1 で作成するユーザーのシェル                                                                                                                                                                                      |
| `DEVTOOL_PHASE2_UID`           | `${EUID}`               | phase 2 実行 UID 検証値 (CI seam 用)                                                                                                                                                                                    |
| `DEFAULT_USERNAME`             | `user`                  | 作成するユーザー名                                                                                                                                                                                                      |
| `DEVTOOL_TAG`                  | `main`                  | Release tarball 取得タグ                                                                                                                                                                                                |
| `DEVTOOL_REPO`                 | `naa0yama/devtool-wsl2` | GitHub リポジトリ                                                                                                                                                                                                       |
| `DEVTOOL_SRC_URL`              | (unset)                 | `main()` の source archive 取得先 full-URL override。未設定時は `https://github.com/${DEVTOOL_REPO}/archive/${DEVTOOL_TAG}.tar.gz`。lxc-test が fork PR の checkout を `git archive` + `http.server` で配信する際に使用 |
| `DEVTOOL_SRC_ROOT`             | (unset)                 | テスト seam: source root を直接指定すると archive fetch をスキップ                                                                                                                                                      |
| `DEVTOOL_SKIP_PROVISION_FETCH` | (unset)                 | 設定時 tarball fetch をスキップ (stage 0 経路)                                                                                                                                                                          |

---

## 3. 実行フロー

`curl | sudo bash` の oneliner (bare Ubuntu / VM / lxc-test) は自己再実行後、
`DEVTOOL_BOOTSTRAP_PHASE` 未設定なら `main()` を実行する
(`DEVTOOL_BOOTSTRAP_PHASE=1`/`2` は system/user 層を分割再実行する legacy な
dispatch で、現行の呼び出し元はいずれも使用しない — 未設定時の `main()` が
唯一の実運用パス)。

```
bootstrap.sh (top-level exec, curl | sudo bash)
  │
  ├─ self-download → /tmp/devtool-bootstrap.sh へ保存し再 exec
  │
  └─ main()
       ├─ source 取得
       │    ├─ DEVTOOL_SRC_ROOT 指定時 → そのディレクトリを使用 (fetch skip)
       │    └─ 未指定時 → DEVTOOL_SRC_URL (未設定なら GitHub archive URL) を
       │         curl で取得し ${DEVTOOL_CACHE}/src に展開
       │
       ├─ system 層 (EUID=0, sudo/root)
       │    └─ scripts/provision/system/*.sh を sort 順に全実行
       │         (15-user.sh で uid=1100 user 作成、20-docker-engine.sh で
       │         docker-ce install、40-cleanup-ubuntu.sh で不要パッケージ除去 等)
       │
       └─ user 層 (runuser -u user)
            └─ scripts/provision/user/*.sh を sort 順に全実行
                 (10-mise-install.sh / 20-bashrc.sh / 30-fish-config.sh /
                 40-mise-config.sh 等)
```

---

## 4. 環境検出 (seam-2)

`detect_env()` が `/proc/version` / `/.dockerenv` / `systemd-detect-virt` を検査して
`DEVTOOL_ENV` を自動設定する。テスト時は環境変数で上書き可能 (seam-2)。

| 判定条件                                                        | 値          |
| --------------------------------------------------------------- | ----------- |
| `/.dockerenv` 存在 または cgroup に `docker`/`containerd`/`lxc` | `container` |
| `/proc/version` に `microsoft` または `WSL`                     | `wsl2`      |
| `systemd-detect-virt` が `kvm`/`qemu`/`vmware` 等               | `vm`        |
| いずれにも該当しない                                            | `bare`      |

---

## 5. main() の source 取得

`DEVTOOL_SRC_ROOT` が未設定の場合、`main()` は archive を curl で取得し
`${DEVTOOL_CACHE}/src` (root 実行時 `/var/cache/devtool`、それ以外
`~/.cache/devtool`) へ展開する。

```
url=${DEVTOOL_SRC_URL:-https://github.com/${DEVTOOL_REPO}/archive/${DEVTOOL_TAG}.tar.gz}
```

sha256 が前回取得時と同じ場合は再展開をスキップする。lxc-test は
`DEVTOOL_SRC_URL=http://<LXD bridge gateway>:8000/...` で fork PR の
checkout を guest から取得させる (詳細: [`../ci/vm-boot-test.md`](../ci/vm-boot-test.md))。

legacy な `DEVTOOL_BOOTSTRAP_PHASE=1`/`2` 経路 (現行呼び出し元は未使用) は
別途 `PROVISION_ASSET_URL` (`devtool-provision.tar.gz`, `latest` タグ固定)
から取得し `chmod -R a+rX` で phase 2 (uid=1100) から読取可能にする。

---

## 6. Release asset

`release.yml` が以下の 2 asset を GitHub Releases にアップロードする:

| ファイル                   | 内容                                      |
| -------------------------- | ----------------------------------------- |
| `devtool-bootstrap.sh`     | bootstrap.sh のコピー (curl 直接実行可能) |
| `devtool-provision.tar.gz` | `scripts/provision/` のアーカイブ         |

---

## 7. 参照

- [`scripts/provision/bootstrap.sh`](../../../scripts/provision/bootstrap.sh)
- [`docs/adr/latest/0006-common-bootstrap-vestibule-user.md`](../../adr/latest/0006-common-bootstrap-vestibule-user.md)
- [`docs/guides/bare-ubuntu.md`](../../guides/bare-ubuntu.md)
- [`docs/guides/pve-import.md`](../../guides/pve-import.md)
- [`.github/workflows/release.yml`](../../../.github/workflows/release.yml)
- [`.github/workflows/build.yml`](../../../.github/workflows/build.yml) (`lxc-test` job)
- [`docs/specs/ci/vm-boot-test.md`](../ci/vm-boot-test.md)
