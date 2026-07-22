# 0007. VM 提供は stock cloud image + bootstrap.sh oneliner (qcow2 焼き工程廃止)

- Status: Accepted
- Date: 2026-07-22
- Deciders: naa0yama

## Context

qcow2 golden image の CI build (guestmount + chroot 方式、ADR-0005) は
1 run 30-60 分かかり一度も成功しなかった。調査の結果、遅さと失敗の両方が
guestmount (FUSE) という同一根本原因に帰着した:

1. **遅さ**: dpkg の unpack/configure は fsync 多発 write であり、全 I/O が
   FUSE → libguestfs appliance を往復する。noble の system layer だけで
   34 分 (apt upgrade 12 分 + base install 11 分)。download は数秒で完了して
   おり、ネットワークではなく I/O が律速。同一 provision scripts は
   Docker (build.yml) では 2m57s で完走する。
2. **失敗**: FUSE mount は `allow_other` なしでは mount した UID (root)
   以外のアクセスを拒否する。user layer の特権降格 (uid 1100) の瞬間に
   `runuser: failed to execute id: Permission denied` で失敗。
   #435→#436→#437→#444 の sudo/su/runuser 差し替えは全て PAM/chroot を
   疑ったもので、真因 (FUSE) に触れていなかった。

さらに要件を再確認した結果、支点は「qcow2 という配布物」ではなく
「WSL2 root tar と同等の out-of-box 体験」であり、展開時の時間コストは
許容できることが判明した。pre-baked である必然性がない。

## Decision

qcow2 の焼き工程と配布を廃止し、以下に置き換える:

- **配布**: release asset の `bootstrap.sh` を stock Ubuntu cloud image 上で
  `curl -fsSL <release asset URL>/bootstrap.sh | bash` する oneliner。
  cloud-init user-data の `runcmd` に書けば完全無人化可能。
- **検証**: build.yml に `needs: builds` の KVM boot テスト job を追加。
  tier 1 (既存 WSL2 Docker build) 完走後、GitHub runner の `/dev/kvm` で
  stock cloud image を実 boot し、配布と同一形状の oneliner で
  bootstrap.sh (`DEVTOOL_ENV=vm`) の完全性を matrix (noble / resolute) 検証。
- **削除**: qcow2.yml、provision-chroot.sh、passt shadow、
  virt-resize / virt-sparsify、chroot 向け特権降格 workaround。

本 ADR は ADR-0003 (2 経路提供) と ADR-0005 (guestmount + chroot) を
supersede する。ADR-0003 の「経路 A は経路 B の実行結果のキャッシュ」原則は、
将来 pre-baked が必要になった際に KVM boot 経路の末尾へ
shutdown + sparsify + upload を追加する形で引き続き有効。

## Consequences

**正の影響**

- CI 時間: 30-60 分 (失敗) → 10 分前後 (見込み)。かつ検証対象が
  「ユーザーが実際に通る配布経路そのもの」になる
- guestmount / FUSE / passt / chroot の workaround 一式が消え、
  保守面積が大幅減
- qcow2 実 boot は FUSE を経由しない (qemu block layer + guest 内 ext4)
  ため、速度・権限問題が構造的に発生しない
- bootstrap.sh が WSL2 (Dockerfile) と VM (oneliner) の
  Single Source of Truth として維持される

**負の影響**

- import 後すぐ使える pre-baked 体験は提供されない (初回 boot で
  10-20 分の構築待ち)
- 構築時にネットワーク接続が必須
- release asset から qcow2 が消える (利用手順の docs 更新が必要)

## Alternatives Considered

**A. guestmount に allow_other を追加して現行継続**
EACCES は解消見込みだが、FUSE の遅さ (成功時 45-60 分/series) と
workaround 山積みが残る。不採用。

**B. QEMU boot bake で pre-baked qcow2 配布を継続**
boot 方式なら bake と検証を同一経路にでき技術的には成立する。ただし
即時利用のニーズが現状なく、release asset の split 配布や
イメージ肥大の管理コストが残る。将来必要になれば本方式の経路末尾に
追加できるため見送り。

**C. Docker container で DEVTOOL_ENV=vm を検証 (実 boot なし)**
高速 (3 分) だが systemd / cloud-init / ubuntu user / snapd など
実 boot との環境差を検証できない。guestmount 問題自体が「実行環境の差」
起因であり、実 boot 検証を欠くと同型の見逃しを再生産する。不採用。

## History

- 2026-07-22: initial version (supersedes ADR-0003, ADR-0005)
