# PVE への qcow2 ゴールデンイメージ取り込み手順

Proxmox VE (PVE) 環境へ devtool-wsl2 ゴールデンイメージを取り込み、
VM テンプレートを作成する手順。

関連ファイル:
- ビルドワークフロー: [`../../.github/workflows/qcow2.yml`](../../.github/workflows/qcow2.yml)
- ブートストラップ: [`../../scripts/provision/bootstrap.sh`](../../scripts/provision/bootstrap.sh)
- qcow2 後処理: [`../../scripts/image/finalize.sh`](../../scripts/image/finalize.sh)

---

## 1. 前提

| 項目 | 値 |
|------|----|
| PVE バージョン | 8.x |
| ストレージ名 | 環境に合わせて読み替え (例: `local-lvm`) |
| VMID | 利用可能な任意の整数 (例: `9000`) |
| ベースイメージ | Ubuntu 24.04 Noble (cloud image) |
| UID/GID | `1100` 固定 (uid:1100 を system 層で焼き込み済み) |

PVE ノードに `qm` コマンドと KVM が利用可能であること。
ゴールデンイメージは [`finalize.sh`](../../scripts/image/finalize.sh) により
cloud-init / machine-id / SSH ホストキーをリセット済み。

---

## 2. qcow2 取得

### 2a. GitHub Actions artifact から取得

1. リポジトリの **Actions** タブを開く
2. **qcow2 Golden Image Build** ワークフローを選択
3. **Run workflow** (workflow_dispatch) を実行
4. 完了後、サマリーページの **Artifacts** から
   `devtool-noble-amd64-qcow2` をダウンロード
5. zip を展開して以下を取り出す:
   ```
   devtool-noble-amd64.qcow2
   devtool-noble-amd64.qcow2.sha256
   ```
6. チェックサム確認:
   ```bash
   sha256sum --check devtool-noble-amd64.qcow2.sha256
   ```

### 2b. GitHub Release から取得 (リリース版)

```bash
VERSION="v0.1.0"
curl --location --output devtool-noble-amd64.qcow2 \
  "https://github.com/naa0yama/devtool-wsl2/releases/download/${VERSION}/devtool-noble-amd64.qcow2"
curl --location --output devtool-noble-amd64.qcow2.sha256 \
  "https://github.com/naa0yama/devtool-wsl2/releases/download/${VERSION}/devtool-noble-amd64.qcow2.sha256"
sha256sum --check devtool-noble-amd64.qcow2.sha256
```

---

## 3. PVE ノードへの転送

ローカルマシンから PVE ノード (`pve.example.net`) へ scp で転送する。

```bash
PVE_HOST="pve.example.net"
PVE_USER="root"
PVE_DEST="/var/lib/vz/images/"

scp devtool-noble-amd64.qcow2 \
    "${PVE_USER}@${PVE_HOST}:${PVE_DEST}"
```

PVE ノード側での確認:

```bash
ls -lh /var/lib/vz/images/devtool-noble-amd64.qcow2
```

---

## 4. VM 作成 → qm importdisk → cloud-init アタッチ → テンプレート化

PVE ノード上で以下を実行する。変数は環境に合わせて変更すること。

```bash
VMID=9000
TEMPLATE_NAME="devtool-noble-amd64"
STORAGE="local-lvm"
IMAGE="/var/lib/vz/images/devtool-noble-amd64.qcow2"
```

### 4-1. VM 作成

```bash
qm create "${VMID}" \
  --name "${TEMPLATE_NAME}" \
  --memory 4096 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0
```

### 4-2. ディスクインポート

```bash
qm importdisk "${VMID}" "${IMAGE}" "${STORAGE}"
```

### 4-3. ディスク / デバイス設定

```bash
qm set "${VMID}" \
  --scsihw virtio-scsi-pci \
  --scsi0 "${STORAGE}:vm-${VMID}-disk-0"

qm set "${VMID}" --ide2 "${STORAGE}:cloudinit"

qm set "${VMID}" --boot c --bootdisk scsi0

qm set "${VMID}" --serial0 socket --vga serial0

qm set "${VMID}" --agent enabled=1
```

### 4-4. テンプレート化

```bash
qm template "${VMID}"
```

---

## 5. clone による VM 作成

テンプレートから作業 VM を作成する。

```bash
NEW_VMID=101
NEW_NAME="devtool-dev-01"

qm clone "${VMID}" "${NEW_VMID}" \
  --name "${NEW_NAME}" \
  --full \
  --storage "${STORAGE}"
```

フルクローン (`--full`) により、テンプレートディスクへの依存なしで
独立した VM が作成される。

---

## 6. cloud-init 設定

ゴールデンイメージは uid:1100 の `user` を system 層で焼き込み済み。
cloud-init の username は任意に設定可能 (デフォルト `ubuntu` 維持を推奨)。

**vestibule パターン**: cloud-init 側ユーザー (例: `ubuntu`) を玄関 (vestibule) として使い、
初回ログイン後に `sudo su - user` で uid=1100 の焼き込みユーザーへ切り替える。
uid=1100 の `user` は cloud-init とは独立して system 層で焼き込み済みのため、
cloud-init 設定で username を `user` に合わせる必要はない。

### 6a. PVE GUI / qm set での注入

```bash
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519.pub"

qm set "${NEW_VMID}" \
  --ciuser ubuntu \
  --sshkey "${SSH_KEY_PATH}" \
  --ipconfig0 ip=dhcp
```

> `--ciuser ubuntu` はデフォルトを明示する例。PVE テンプレート利用者は
> 好みの username に変更可能。`--ciuser user` は不要。

### 6b. vestibule から uid=1100 への切り替え

VM 起動後、cloud-init username (例: `ubuntu`) で SSH ログインし、
`sudo su - user` で uid=1100 の焼き込みユーザーへ redirect する。

```bash
# vestibule (cloud-init username) でログイン
ssh ubuntu@198.51.100.10

# uid=1100 の焼き込みユーザーへ切り替え
sudo su - user
```

### 6c. vestibule cleanup (任意)

uid=1100 の `user` 側で SSH 鍵配置が確認できたら、vestibule ユーザーは不要になる。
root 権限で手動削除する。

```bash
sudo userdel --remove ubuntu
```

> **注意**: 削除は任意。自動化は行わない — 運用中の vestibule を
> false positive で削除するリスクがあるため。

---

## 7. 検証項目

VM 起動後、以下を確認する。

```bash
# vestibule (cloud-init username) で SSH ログイン
ssh ubuntu@198.51.100.10

# uid=1100 ユーザーへ切り替え
sudo su - user
```

| 項目 | コマンド | 期待結果 |
|------|----------|----------|
| UID 確認 | `id` | `uid=1100(user)` |
| シェル確認 | `echo $SHELL` | `/bin/bash` |
| mise 動作 | `mise --version` | バージョン文字列が返る |
| docker 動作 | `docker info` | エラーなし |
| fish 動作 | `fish --version` | バージョン文字列が返る |
