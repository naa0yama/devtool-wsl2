---
title: lxc-test (bootstrap 統合検証) 設計
status: accepted
date: 2026-07-22
source_spec: ../../../.claude/artifacts/plans/2026-07-22-lxc-bootstrap-test.md
---

# lxc-test (bootstrap 統合検証) 設計

## 1. 概要

`build.yml` の `lxc-test` job は LXC container 上で `bootstrap.sh` の
`main()` を `DEVTOOL_ENV=vm` 経路で完走させ、「stock cloud image +
bootstrap.sh oneliner」配布モデルのうち「bootstrap.sh 実行 + 実行後状態が
正しいこと」を検証する。

旧方式は stock Ubuntu cloud image を実 KVM boot して検証していたが、
qemu/SLIRP (userspace NAT、connect-and-reissue モデル) 経路の apt
bulk-fetch stall が timeout+kill-after retry wrapper・console.log live
streaming・MTU 修正を重ねても収束せず、検証スコープを
「kernel/GRUB/growpart/cloud-init NoCloud を含む実 boot」から
「bootstrap.sh 実行 + 実行後状態が正しいこと」に絞り直した結果、
qemu 実 boot である必然性が薄れた。LXC container (LXD bridge networking、
runner の通常ネットワーク経路と同系統) に置き換えることで SLIRP 経路自体を
構造的に回避する。ADR-0007 に従い、この転換を実施した。

関連 ADR: [`../../adr/latest/0007-vm-bootstrap-oneliner.md`](../../adr/latest/0007-vm-bootstrap-oneliner.md)
関連設計: [`../components/bootstrap.md`](../components/bootstrap.md)

---

## 2. CI チェーン構成

```
build.yml
  ├─ builds job (tier 1, 既存 WSL2 Docker build、変更なし)
  │
  └─ lxc-test job (tier 2, needs: builds, matrix: noble / resolute)
       LXC container 上で bootstrap.sh (main()) 完走 + verify.sh を検証
```

- trigger は `builds` と同一 (PR open/synchronize, schedule, workflow_dispatch)
- `if: github.event.action != 'closed'` — merge 時は直前 synchronize で
  同一内容が検証済みのため skip (`builds` の release upload は
  `lxc-test` に依存しないため影響なし)
- `fail-fast: false` — noble/resolute 差分の早期検出を優先し、
  片方の失敗でもう片方の結果を握り潰さない
- `timeout-minutes: 15` (qemu 版の 30 分から短縮 — LXC container 起動は
  実 boot よりオーバーヘッドが小さく、SLIRP 経路も経由しない)

---

## 3. job ステップ (`.github/workflows/build.yml` lxc-test)

1. **checkout**
2. **LXD 可用性確認** — `command -v lxc` で未導入なら `snap install lxd`。
   GH-hosted runner イメージは版によって LXD snap の有無が変わるため、
   決め打ちせず probe する。`lxd waitready` + `lxd init --auto` で初期化
3. **PR checkout 配信** — `git archive` で HEAD を tarball 化し、
   `bootstrap.sh` / `verify.sh` と共に `python3 -m http.server 8000` で配信
   (qemu 版と同一形状)。guest からは LXD bridge のデフォルトゲートウェイ
   (`ip route show default` で動的解決) 経由で到達する
   — qemu 版の固定 `10.0.2.2` 相当だが、LXD のブリッジ IP は環境依存の
   ため動的に解決する
4. **container 起動** — `lxc launch ubuntu:${series} c1 -c
   security.nesting=true` (docker-in-LXC に必須の nested containerization
   設定)。`ubuntu:` remote は released series のみ配信するため (qemu 版の
   `cloud-images.ubuntu.com` URL 直接取得と異なり devel/interim series は
   持たない)、`resolute` 等が未リリース状態で matrix に加わっている場合に
   備え、起動失敗時は `ubuntu-daily:${series}` へ fallback する。
   `lxc exec c1 -- cloud-init status --wait` で LXD 自身の
   cloud-init datasource (qemu 版が使っていた NoCloud とは別物) の完了を待つ。
   このステップ内で LXD bridge のデフォルトゲートウェイも一度だけ解決し
   (`ip route show default` → `awk`)、`GITHUB_ENV` 経由で以降のステップに
   引き渡す — job step 6/7 双方で同じ導出を繰り返さないため
5. **guest→internet apt スループット probe (診断用)** — 低コストで
   bulk-fetch stall 再発時の切り分けに有用なため維持。host 側 probe
   (qemu 版にあった) は削除 — 同一 runner で `builds` job (WSL2 Docker
   build) が host egress を毎回検証しているため冗長
6. **bootstrap.sh 実行** — `lxc exec c1 -- bash -c '... | DEVTOOL_SRC_URL=...
   DEVTOOL_ENV=vm bash'`。`lxc exec` は同期実行で exit code を直接返すため、
   qemu 版で必要だった serial console sentinel (`DEVTOOL_VM_TEST: PASS`)
   の grep は不要 — このステップの exit code がそのまま pass/fail になる。
   `DEVTOOL_ENV=vm` は明示指定であり `bootstrap.sh` の `detect_env()` に
   よる自動判定には委ねない — `detect_env()`/`is_vm()` の virt 種別判定
   (`kvm|qemu|vmware|xen|hyperv|parallels`) は `lxc` を含まないため、
   自動判定に任せると LXC container は `vm` として認識されない
   (`: "${DEVTOOL_ENV:=$(detect_env)}"` は未設定時のみ発火するため、
   明示指定が優先される)
7. **verify.sh 実行** — `lxc exec c1 -- bash -c '... verify.sh'`。同じく
   同期 exit code で判定
8. **timing summary** (`if: always()`) — probe/bootstrap/verify の
   begin/end epoch を `GITHUB_STEP_SUMMARY` へ
9. **container log artifact upload** (`if: always()`) — `lxc exec c1 --
   journalctl` の出力と probe log を artifact として upload、失敗時の
   一次調査用

---

## 4. guest 内フロー

qemu 版は `tests/vm/user-data.yaml` (NoCloud cloud-init + serial sentinel
script) 経由で guest 内フローを組み立てていたが、この方式は削除した。
LXD ubuntu image は kernel を共有し bootloader を経由しないため NoCloud
datasource が使えず (ADR-0007 参照)、また `lxc exec` の同期呼び出しにより
sentinel 文字列を経由しない直接的な pass/fail 判定が可能になったため、
runner 側の各 CI step (job ステップ 6, 7) がそのまま guest 内フローの
呼び出し元になる:

```
runner (lxc exec, 同期)
  ├─ [job step 6] bootstrap.sh 実行
  │    curl UPSTREAM/scripts/provision/bootstrap.sh | \
  │      DEVTOOL_SRC_URL=UPSTREAM/devtool-src.tar.gz DEVTOOL_ENV=vm bash
  │    (main() が system 層 → user 層を実行。exit code が pass/fail)
  │
  └─ [job step 7] verify.sh 実行
       curl UPSTREAM/tests/vm/verify.sh → 実行 (exit code が pass/fail)
```

`DEVTOOL_SRC_URL` は `bootstrap.sh` の `main()` に追加した full-URL override
seam (`docs/specs/components/bootstrap.md` 参照)。fork PR の merge commit は
github.com から取得不能なため、runner の checkout をそのまま配信する。

---

## 5. 検証 script (`tests/vm/verify.sh`)

provision の内部実装に依存しない「完成状態契約」として検証する
(bootstrap.sh のリファクタで壊れないようにする狙い)。qemu 版から変更なし
— LXC container でも同一契約が成立する (kernel を共有するため systemd
service の起動確認等はそのまま機能する):

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

## 6. Non-Goals

- kernel / GRUB / bootloader / cloud-init NoCloud datasource / growpart の
  実 boot 経路検証 (LXC container は kernel を共有し bootloader を経由
  しないため、これらの層の不具合は検出できない — ADR-0007 参照)
- pre-baked image 配布の復活 (ADR-0007 のスコープ外のまま)
- `bats (vm)` / `bats (container)` (`bats.yml`, unit-level) の置き換え —
  provisioning script のロジックを runner 上で直接 (mock 込み) 検証する
  ものであり、本 job (別 rootfs 上で curl\|bash を完走させる統合検証) とは
  役割・粒度が異なる。両立させる

---

## 7. 参照

- [`.github/workflows/build.yml`](../../../.github/workflows/build.yml) (`lxc-test` job)
- [`tests/vm/verify.sh`](../../../tests/vm/verify.sh)
- [`scripts/provision/bootstrap.sh`](../../../scripts/provision/bootstrap.sh)
- [`docs/specs/components/bootstrap.md`](../components/bootstrap.md)
- [`docs/adr/latest/0007-vm-bootstrap-oneliner.md`](../../adr/latest/0007-vm-bootstrap-oneliner.md)
