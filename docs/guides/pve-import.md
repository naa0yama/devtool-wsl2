# PVE への stock cloud image 取り込み + bootstrap 手順

Proxmox VE (PVE) 環境へ stock Ubuntu cloud image を取り込み、
`bootstrap.sh` oneliner で devtool-wsl2 環境を構築し VM テンプレートを作成する手順。

qcow2 golden image の事前焼き込みは廃止した (ADR-0007)。stock image +
oneliner により、CI (`lxc-test` job) と同一の provisioning 経路を検証できる。

関連ファイル:

- ブートストラップ: [`../../scripts/provision/bootstrap.sh`](../../scripts/provision/bootstrap.sh)
- 設計: [`../specs/components/bootstrap.md`](../specs/components/bootstrap.md)
- ADR: [`../adr/latest/0006-common-bootstrap-vestibule-user.md`](../adr/latest/0006-common-bootstrap-vestibule-user.md)、
  [`../adr/latest/0007-vm-bootstrap-oneliner.md`](../adr/latest/0007-vm-bootstrap-oneliner.md)

---

## 1. 前提

| 項目           | 値                                                      |
| -------------- | ------------------------------------------------------- |
| PVE バージョン | 8.x                                                     |
| ストレージ名   | 環境に合わせて読み替え (例: `local-lvm`)                |
| VMID           | 利用可能な任意の整数 (例: `9000`)                       |
| ベースイメージ | Ubuntu 24.04 Noble (stock cloud image、無加工)          |
| UID/GID        | `1100` 固定 (bootstrap.sh 実行時に system 層で焼き込み) |

PVE ノードに `qm` コマンドと KVM が利用可能であること。

---

## 2. stock cloud image 取得

Ubuntu 公式 cloud image をそのまま使用する (devtool 側の加工なし)。

```bash
curl --location --output noble-server-cloudimg-amd64.img \
  "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
```

---

## 3. PVE ノードへの転送

ローカルマシンから PVE ノード (`pve.example.net`) へ scp で転送する。

```bash
PVE_HOST="pve.example.net"
PVE_USER="root"
PVE_DEST="/var/lib/vz/images/"

scp noble-server-cloudimg-amd64.img \
    "${PVE_USER}@${PVE_HOST}:${PVE_DEST}"
```

PVE ノード側での確認:

```bash
ls -lh /var/lib/vz/images/noble-server-cloudimg-amd64.img
```

---

## 4. VM 作成 → qm importdisk → cloud-init アタッチ → テンプレート化

PVE ノード上で以下を実行する。変数は環境に合わせて変更すること。

```bash
VMID=9000
TEMPLATE_NAME="devtool-noble-amd64"
STORAGE="local-lvm"
IMAGE="/var/lib/vz/images/noble-server-cloudimg-amd64.img"
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

### 4-4. ディスク拡張 (任意)

stock cloud image は数 GB しかない。cloud-init `growpart` が起動時に自動拡張するため、
必要サイズを事前に確保する。

```bash
qm resize "${VMID}" scsi0 +20G
```

### 4-5. テンプレート化

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

## 6. cloud-init 設定 + bootstrap 実行

stock image は devtool-wsl2 の uid=1100 `user` を含まない。cloud-init の
username (vestibule) で初回ログインし、`bootstrap.sh` oneliner を実行して
初めて uid=1100 の `user` が作成される (ADR-0006 vestibule パターン)。

### 6a. PVE GUI / qm set での注入

```bash
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519.pub"

qm set "${NEW_VMID}" \
  --ciuser ubuntu \
  --sshkey "${SSH_KEY_PATH}" \
  --ipconfig0 ip=dhcp
```

> `--ciuser ubuntu` はデフォルトを明示する例。PVE テンプレート利用者は
> 好みの username に変更可能。

### 6b. bootstrap.sh oneliner 実行

VM 起動後、cloud-init username (vestibule、例: `ubuntu`) で SSH ログインし、
release asset の `bootstrap.sh` を curl で取得・実行する。

```bash
# vestibule (cloud-init username) でログイン
ssh ubuntu@198.51.100.10

# bootstrap.sh oneliner (main() が system 層 → user 層を実行)
curl --location --silent --show-error \
  "https://github.com/naa0yama/devtool-wsl2/releases/latest/download/devtool-bootstrap.sh" \
  | sudo bash
```

`bootstrap.sh` の system 層 (`15-user.sh`) が uid=1100 の `user` を作成し、
`40-cleanup-ubuntu.sh` が vestibule (`ubuntu`) を自動削除する
(`DEVTOOL_ENV=vm` 検出時のみ)。削除は provisioning 内で自動実行されるため、
手動 cleanup は不要。

> **重要**: vestibule アカウントは自動削除されるため、以後 `ubuntu` での
> 再ログインはできなくなる。同一 SSH セッション内で次項 6c を実施すること。

### 6c. vestibule から uid=1100 への切り替え

vestibule アカウント削除後もログイン中の SSH セッション自体は有効なため、
同一セッションから `sudo su - user` で uid=1100 の `user` へ切り替える。

```bash
sudo su - user
```

以後の直接 SSH ログインのため、`user` の `~/.ssh/authorized_keys` に鍵を
配置しておく (bootstrap.sh は SSH 鍵配布を行わないため手動対応)。

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA...(公開鍵)..." >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

---

## 7. 検証項目

VM 起動後、以下を確認する。

```bash
ssh user@198.51.100.10
```

| 項目               | コマンド         | 期待結果               |
| ------------------ | ---------------- | ---------------------- |
| UID 確認           | `id`             | `uid=1100(user)`       |
| シェル確認         | `echo $SHELL`    | `/usr/bin/fish`        |
| mise 動作          | `mise --version` | バージョン文字列が返る |
| docker 動作        | `docker info`    | エラーなし             |
| fish 動作          | `fish --version` | バージョン文字列が返る |
| vestibule 削除確認 | `id ubuntu`      | `no such user`         |
