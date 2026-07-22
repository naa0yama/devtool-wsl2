# 素の Ubuntu 24.04 への bootstrap 手順

新規の Ubuntu 24.04 環境 (bare metal / cloud VM / WSL2 手動インストール等) に
devtool 環境を構築する手順。

関連ファイル:

- ブートストラップ: [`../../scripts/provision/bootstrap.sh`](../../scripts/provision/bootstrap.sh)
- bootstrap 設計: [`../specs/components/bootstrap.md`](../specs/components/bootstrap.md)

---

## 1. 前提

| 項目         | 値                               |
| ------------ | -------------------------------- |
| OS           | Ubuntu 24.04 LTS (Noble Numbat)  |
| 権限         | sudo 権限のあるユーザー          |
| ネットワーク | GitHub Releases へのアクセス可能 |

---

## 2. bootstrap 実行

```bash
curl -sSL https://github.com/naa0yama/devtool-wsl2/releases/latest/download/devtool-bootstrap.sh | sudo bash
```

スクリプトは以下の順で実行される:

### stage 0: provision tarball の取得

`devtool-bootstrap.sh` 自身が GitHub Releases から `devtool-provision.tar.gz` を fetch し、
`/tmp/devtool-provision/` に展開する。

```
GitHub Releases
  └─ devtool-bootstrap.sh         ← curl で取得・実行
  └─ devtool-provision.tar.gz     ← stage 0 が fetch して /tmp/devtool-provision/ に展開
```

### phase 1: system 層 (root)

uid=0 (root) で system ディレクトリの `.sh` を順に実行する:

- `system/15-user.sh` — uid=1100 の `user` 作成 (shell=`/bin/bash`)
- `system/20-docker-engine.sh` — docker-ce インストール (公式 apt repo)
- `system/40-cleanup-ubuntu.sh` — 不要パッケージ除去

phase 1 完了後、uid=1100 の `user` として phase 2 を `exec sudo -u user` で再実行する。

### phase 2: user 層 (uid=1100)

uid=1100 の `user` として user ディレクトリの `.sh` を順に実行する:

- `user/10-mise-install.sh` — mise インストール
- `user/20-bashrc.sh` — bashrc 設定
- `user/30-fish-config.sh` — fish 設定
- `user/40-mise-config.sh` — mise ツール設定

---

## 3. vestibule パターン

素の Ubuntu では、bootstrap 実行時の sudo ユーザー (例: `ubuntu`) が vestibule 相当になる。
bootstrap 完了後は `sudo su - user` (uid=1100) に切り替えて開発作業を行う。

```bash
# bootstrap 完了後
sudo su - user
```

vestibule ユーザー (`ubuntu`) の削除は任意:

```bash
sudo userdel --remove ubuntu
```

> **注意**: 削除は任意。SSH 鍵を uid=1100 の `user` 側に配置・確認してから行うこと。

---

## 4. トラブルシューティング

### DNS 解決失敗

`systemd-resolved` が設定されていない環境で curl が失敗する場合:

```bash
# DNS 設定確認
resolvectl status

# 一時対処: /etc/resolv.conf を手動設定
echo "nameserver 198.51.100.1" | sudo tee /etc/resolv.conf
```

### curl retry

ネットワーク不安定時は `--retry` オプションを使う:

```bash
curl --retry 3 --retry-delay 5 --location --silent \
  https://github.com/naa0yama/devtool-wsl2/releases/latest/download/devtool-bootstrap.sh \
  | sudo bash
```
