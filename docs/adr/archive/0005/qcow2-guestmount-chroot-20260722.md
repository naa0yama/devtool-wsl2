# 0005. qcow2 プロビジョニングに guestmount+chroot を採用

- Status: Accepted
- Date: 2026-07-20
- Deciders: naa0yama

## Context

qcow2 golden image のプロビジョニングに `virt-customize` を使用していたが、
libguestfs 1.52 (ubuntu-24.04 以降) では DNS 解決が失敗する問題が発生した。

具体的な障害連鎖:

1. libguestfs 1.52+ は passt を優先検出する。passt は自身の uid を `nobody`
   にドロップするが、libguestfs の tmpdir は 0700 root:root のため pidfile
   書き込みが EACCES → "passt exited status 1" で appliance 起動失敗。
2. passt shadow stub (`/usr/local/bin/passt`, exit 2) で passt を無効化し
   slirp fallback を強制した後も、appliance は host の `/etc/resolv.conf`
   (127.0.0.53 = systemd-resolved stub) を継承するが、appliance の netns
   からはこのアドレスに到達できない → `Temporary failure resolving 'archive.ubuntu.com'`。
3. libguestfs 1.52 に DNS を上書きする公式 API は存在しない
   (`--dns` flag なし、`LIBGUESTFS_APPLIANCE_OPTIONS` なし、
   `/etc/libguestfs-tools.conf` に DNS 設定項目なし)。

ゲストイメージの `/etc/resolv.conf` を provisioning 中に書き換えて外部 DNS
に向ける案も検討したが、デプロイ後の Ubuntu が stock Ubuntu と異なる DNS
挙動を示すことになり利用者の混乱を招くため採用しなかった。

## Decision

`virt-customize` を廃止し `guestmount` + `chroot` 方式でプロビジョニングを実施する。

- `guestmount --inspector --rw` でゲストイメージを host ファイルシステムにマウント
- `chroot` でゲスト環境に入る。`chroot` は host の netns を継承するため
  systemd-resolved (127.0.0.53) に到達可能 → apt-get が正常動作
- DNS 解決に必要なのは host netns の継承だけであり、ゲスト fs 上の
  `/etc/resolv.conf` (→ `../run/systemd/resolve/stub-resolv.conf` symlink)
  には一切書き込まない
- symlink が指す実体 (`/run/systemd/resolve/stub-resolv.conf`) を
  `bind mount` で一時提供し、chroot 内から symlink 経由で参照可能にする
- `trap 'cleanup_mounts "$MNT"' ERR EXIT` で bind mount を確実に解除し
  ゲスト fs の状態を provisioning 前と bit-identical に保つ

## Consequences

**正の影響**

- ゲストイメージは stock Ubuntu と `/etc/resolv.conf` 含め bit-identical
  (provisioning 差分除く)
- ubuntu-22.04 pin 不要 → ubuntu-latest 継続、26.04 以降も無負債
- libguestfs の DNS 制御機構非依存 → upstream 変更に対してロバスト
- `provision-chroot.sh` は libguestfs 非依存で単体試験可能 (bats)
- chroot 環境で直接デバッグ可能 (`guestmount` してから手動 `chroot`)

**負の影響**

- `virt-customize` の `--copy-in` / `--mkdir` / `--run-command` の宣言的 API
  が使えなくなり、bind mount と cleanup の命令的コードが増える (~60 LOC)
- `guestmount` は FUSE ベースのため、`virt-customize` より若干低速
- `sudo` + FUSE + bind mount の権限要件が明示的に必要

## Alternatives Considered

**A. runner の /etc/resolv.conf を一時書き換え**
appliance boot 時点で libguestfs が resolv.conf を snapshot するか都度参照するか
不明確。実証コストが高く、runner の DNS 設定変更は他ジョブへの副作用リスクあり。不採用。

**B. virt-customize --run-command で先に resolv.conf を書き換え → finalize で symlink 復元**
書き換え忘れや finalize 失敗時にゲストイメージが汚染される。bit-identity の
事後検証コストも高い。利用者が stock Ubuntu との差異に惑わされるリスクがある。不採用。

**C. LIBGUESTFS_BACKEND=direct**
qemu launcher の選択であり network backend (passt/slirp) の選択ではない。
passt は依然プローブされる。DNS 問題は解決しない。不採用。

**D. ubuntu-22.04 pin**
libguestfs 1.50 系 (passt なし) を使い続ける技術的負債を蓄積する。
Ubuntu 26.04 対応時に必ず対処が必要になる先送り。不採用。

## History

- 2026-07-20: initial version
