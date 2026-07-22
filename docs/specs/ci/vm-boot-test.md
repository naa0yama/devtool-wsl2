---
title: kvm-test (VM boot 検証) 設計
status: accepted
date: 2026-07-22
source_spec: ../../../.claude/artifacts/plans/2026-07-22-vm-boot-test.md
---

# kvm-test (VM boot 検証) 設計

## 1. 概要

`build.yml` の `kvm-test` job は stock Ubuntu cloud image を実 KVM boot し、
`bootstrap.sh` の `main()` を `DEVTOOL_ENV=vm` 経路で完走させることで、
「stock cloud image + bootstrap.sh oneliner」配布モデルの完成度を検証する。

qcow2 golden image を guestmount + chroot で焼く旧方式 (`qcow2.yml`) は
1 run 30-60 分かかり一度も成功しなかった (根本原因: guestmount/FUSE の
低速 I/O と非 root UID アクセス拒否)。ADR-0007 に従い焼き工程自体を廃止し、
本 job が実 boot 経路での検証を代替する。

関連 ADR: [`../../adr/latest/0007-vm-bootstrap-oneliner.md`](../../adr/latest/0007-vm-bootstrap-oneliner.md)
関連設計: [`../components/bootstrap.md`](../components/bootstrap.md)

---

## 2. CI チェーン構成

```
build.yml
  ├─ builds job (tier 1, 既存 WSL2 Docker build、変更なし)
  │
  └─ kvm-test job (tier 2, needs: builds, matrix: noble / resolute)
       stock cloud image を KVM boot → bootstrap.sh (main()) 完走を検証
```

- trigger は `builds` と同一 (PR open/synchronize, schedule, workflow_dispatch)
- `if: github.event.action != 'closed'` — merge 時は直前 synchronize で
  同一内容が検証済みのため skip (`builds` の release upload は
  `kvm-test` に依存しないため影響なし)
- `fail-fast: false` — noble/resolute 差分の早期検出を優先し、
  片方の失敗でもう片方の結果を握り潰さない
- `timeout-minutes: 30`

---

## 3. job ステップ (`.github/workflows/build.yml` kvm-test)

1. **checkout**
2. **VM boot tools install** — `qemu-system-x86` + `cloud-image-utils`
3. **KVM 有効化確認** — `/dev/kvm` 存在確認 + `chmod 0666`
4. **cloud image download** — `scripts/image/series-map.sh` の
   `series_to_url` で matrix.series に対応する stock image URL を解決
5. **disk 拡張** — `qemu-img resize image.img +20G`
   (実 boot では cloud-init `growpart` が partition/fs を自動拡張するため、
   旧方式の `virt-resize` (libguestfs) は不要)
6. **PR checkout 配信** — `git archive` で HEAD を tarball 化し、
   `bootstrap.sh` / `verify.sh` と共に `python3 -m http.server 8000` で配信。
   guest からは QEMU user-mode networking のホストゲートウェイ
   `10.0.2.2:8000` で到達する
7. **cloud-init seed 生成** — `cloud-localds seed.img tests/vm/user-data.yaml`
8. **host 側 download スループット probe (control)** — runner 自身から
   `tests/vm/user-data.yaml` の guest 側 control probe と同一 URL パターン
   ・同一 `--max-time` (`dists/${{ matrix.series }}/Release`, 30s) で
   `curl` 取得し `speed_download` を `host-probe.log` へ記録。host/guest
   probe を揃えることで両者を直接比較可能にし、bulk-fetch 停滞が runner
   全体のネットワーク特性 (qemu/SLIRP 経路の外でも再現する) か、
   guest/SLIRP proxy 固有かを切り分ける
9. **qemu 起動 + sentinel 待機** — foreground boot
   (`-enable-kvm -cpu host -smp 4 -m 8G -serial file:console.log`)、
   `timeout --signal=KILL 1500` で保護。`console.log` から
   `DEVTOOL_VM_TEST: PASS` sentinel を grep

   guest netdev は `-netdev user,id=net0 -device
   virtio-net-pci,netdev=net0,host_mtu=1280` (`-nic user,model=virtio-net-pci`
   から変更)。MTU は `-netdev user` に直接指定できない (`Invalid parameter
   'mtu'`) ため `-device virtio-net-pci` の `host_mtu`
   (VIRTIO_NET_F_MTU 経由の negotiation) で guest へ伝える。この変更は
   QEMU CLI パラメータの構文誤り (旧 `-nic` 指定では MTU を渡す経路が
   存在しない) を修正するものであり、host→internet 経路の apt bulk-fetch
   停滞そのものの原因ではない (SLIRP は connect-and-reissue モデルで
   host 側 TCP スタックへ委譲するため、guest 側 MTU 設定は host→internet
   leg の PMTU に影響しない)。

   apt bulk-fetch (`universe amd64 Packages` 15MB 取得) の停滞は
   `archive.ubuntu.com` 側の既知・未解決の runner/mirror flakiness
   (`actions/runner-images#12949`, `orgs/community/discussions/172048`) と
   一致することを確認した。同一リポジトリの WSL2 Docker build 経路
   (plain `archive.ubuntu.com`、mirror 切替なし) が約 9 割成功している
   実績から、mirror 切替 (別 regional mirror への変更) は輻輳先を
   移すだけで根本対策にならないと判断し、不採用とした。

   代わりに `scripts/provision/system/10-apt-base.sh` の
   `apt-get update` 呼び出しを `timeout 300` + 最大 3 回リトライで
   包む (`_apt_get_update`)。apt 自身の `Acquire::http::Timeout` は
   dead-connection (0 byte 受信) 検知のみで、生きてはいるが極端に遅い
   trickle 転送は検知できない — shell 側 timeout は転送状態に関わらず
   強制中断し、リトライで新規コネクションを張り直すことで trickle にも
   対応する。この修正は全 provisioning target 共通 (bare/wsl2/vm/container)
   に適用され、CI guest 限定ではない。`tests/vm/user-data.yaml` の
   `/etc/apt/apt.conf.d/80-devtool-vm-test-retries`
   (`Acquire::Retries`/`Acquire::http::Timeout`) は CI guest 限定のまま
   併用し、update 以外の apt 操作 (upgrade/install) の一時的な mirror
   不調からの復帰を早める。
10. **timing summary** (`if: always()`) — `host-probe.log` の内容 + sentinel 行を
    `GITHUB_STEP_SUMMARY` へ
11. **console.log artifact upload** (`if: always()`) — `console.log` と
    `host-probe.log` を artifact として upload、失敗時の一次調査用

---

## 4. guest 内フロー (`tests/vm/user-data.yaml`)

fork PR のゲスト SSH 検証は成立しない
(`40-cleanup-ubuntu.sh` が `DEVTOOL_ENV=vm` で stock `ubuntu` user を
mid-provision で削除するため)。代わりに serial-sentinel 方式を採る:

```
cloud-init runcmd (root)
  └─ /opt/devtool-vm-test.sh
       ├─ exec > /dev/ttyS0 2>&1  (全出力を serial へ)
       ├─ net probe (/etc/os-release の VERSION_CODENAME で
       │    archive.ubuntu.com の Release を破棄取得し speed_download を
       │    出力。guest→internet 経路のスループット計測、bootstrap 停止時
       │    に guest→host (UPSTREAM) 障害と切り分ける)
       ├─ curl UPSTREAM/scripts/provision/bootstrap.sh | \
       │    DEVTOOL_SRC_URL=UPSTREAM/devtool-src.tar.gz bash
       │    (main() が system 層 → user 層を実行)
       ├─ curl UPSTREAM/tests/vm/verify.sh → 実行
       ├─ 成功時 "DEVTOOL_VM_TEST: PASS" 出力
       ├─ 失敗時 (EXIT trap) cloud-init-output.log tail + "DEVTOOL_VM_TEST: FAIL"
       └─ poweroff
```

`DEVTOOL_SRC_URL` は `bootstrap.sh` の `main()` に追加した full-URL override
seam (`docs/specs/components/bootstrap.md` 参照)。fork PR の merge commit は
github.com から取得不能なため、runner の checkout をそのまま配信する。

---

## 5. 検証 script (`tests/vm/verify.sh`)

provision の内部実装に依存しない「完成状態契約」として検証する
(bootstrap.sh のリファクタで壊れないようにする狙い):

| 検証項目                      | 期待                                   |
| ----------------------------- | -------------------------------------- |
| `user` (uid/gid) 存在         | `1100`/`1100`                          |
| login shell                   | `/usr/bin/fish`                        |
| docker group 所属             | 有                                     |
| fish / docker / mise 実行可能 | 有 (mise は user PATH fallback 込み)   |
| `docker` service              | active                                 |
| `/etc/devtool-release`        | 存在                                   |
| `ubuntu` user                 | 不在 (`40-cleanup-ubuntu.sh` 完了確認) |

---

## 6. 参照

- [`.github/workflows/build.yml`](../../../.github/workflows/build.yml) (`kvm-test` job)
- [`tests/vm/user-data.yaml`](../../../tests/vm/user-data.yaml)
- [`tests/vm/verify.sh`](../../../tests/vm/verify.sh)
- [`scripts/provision/bootstrap.sh`](../../../scripts/provision/bootstrap.sh)
- [`docs/specs/components/bootstrap.md`](../components/bootstrap.md)
- [`docs/adr/latest/0007-vm-bootstrap-oneliner.md`](../../adr/latest/0007-vm-bootstrap-oneliner.md)
