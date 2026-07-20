# 0006. 共通 bootstrap.sh と vestibule user パターンで 3 経路を統一

- Status: Accepted
- Date: 2026-07-20
- Deciders: naa0yama

## Context

devtool-wsl2 は 3 経路で配布される:

1. **WSL2 baked** — `build.yml` が生成する `install.tar.gz` を WSL 側で展開
2. **qcow2 baked** — `qcow2.yml` が生成する golden image を PVE 等へ取り込み
3. **bare Ubuntu bootstrap** — 素の Ubuntu 24.04/26.04 に対して bootstrap 実行

ADR-0004 で uid=1100/gid=1100 の user を system 層で焼き込む方針を採用したが、
経路ごとに provisioning コードが分岐し、以下の問題が顕在化した:

- WSL2 と qcow2 で package install / user 作成のコードが二重管理
- bare Ubuntu 経路が未整備 → 3 経路目のみ手動運用
- cloud-init が任意 username (default `ubuntu`) を要求するため、
  `--ciuser user` を強制すると PVE テンプレート利用者側の naming 自由度が失われる
- devcontainer.json は uid=1100 前提でポータビリティを担保しているため、
  cloud-init 側 username を uid=1100 と結合させたくない

`--ciuser user` 強制と非強制の間で妥協点が必要。かつ 3 経路で provisioning
コードを DRY にまとめる仕組みが必要。

## Decision

**共通 bootstrap.sh** を GitHub Release asset として配布し、3 経路全てが
これを実行する。加えて **vestibule user** パターンで cloud-init username と
uid=1100 焼き込み user を分離する。

### 共通 bootstrap.sh

- `scripts/provision/bootstrap.sh` を単一 source-of-truth とし、
  `install.tar.gz` / qcow2 provisioning / bare Ubuntu 全経路が呼ぶ
- Release asset として `devtool-bootstrap.sh` + `devtool-provision.tar.gz` を配布
- bare Ubuntu 経路は `curl … | bash` で self-download → provision tarball
  展開 → 実行の 3 段
- phase 1 (sudo, system + user 層) → phase 2 (uid=1100, user 層) の 2-phase 構成

### vestibule user

- cloud-init は任意 username で VM を立ち上げる (default `ubuntu` のまま)
- その username を **vestibule (玄関)** として使い、初回ログイン後に
  `sudo su - user` で uid=1100 の焼き込み user へ redirect
- devcontainer.json など uid ハードコード箇所は uid=1100 のまま無変更
- PVE テンプレート利用者は `--ciuser` を任意に設定可能 → naming 自由度確保

### 補助決定

- shell は `/bin/bash` 固定 (fish は user 選択に委譲)
- docker-ce (公式 apt repo) を 3 経路統一 (docker.io / snap は不採用)
- mise は per-user install (`curl https://mise.run | sh`)
- provision tarball 展開先 `/tmp/devtool-provision/` は stage 0 末尾で
  `chmod -R a+rX` 実行 → uid=1100 phase 2 からの読取を umask 逸脱環境でも保証

## Consequences

**正の影響**

- provisioning コードが 3 経路で単一化 → 修正・テストが 1 箇所で完結
- bare Ubuntu 経路が正式サポート化 → `curl … | bash` で環境構築可能
- cloud-init username と uid=1100 が疎結合 → PVE テンプレート naming 自由
- devcontainer.json のポータビリティ維持 (uid=1100 前提が全経路で成立)
- bats seam-α (PATH stub) / seam-β (real docker container) で TDD 可能

**負の影響**

- vestibule user の 2 段ログインは初見利用者に説明が必要
  (docs/guides で明示)
- Release asset が 2 つに増える (bootstrap.sh + provision.tar.gz)
- stage 0 の self-download / chmod 実装が umask 逸脱環境で破綻しないよう
  bats で保険テストが必要 (Cycle 7)

## Alternatives Considered

**A. cloud-init `--ciuser user` 強制**
PVE テンプレート利用者の naming 自由度を奪う。default `ubuntu` を残すことで
stock Ubuntu との親和性を保つべき。不採用。

**B. uid=1100 焼き込みを廃止し cloud-init 側 uid で吸収**
devcontainer.json など uid ハードコード箇所が経路ごとに壊れる。
ADR-0004 で確立した方針を後退させる。不採用。

**C. bare Ubuntu 経路を非サポート**
手動運用が続き、3 経路間で挙動が発散する。CI で bare Ubuntu 経路も
テスト可能な構成が中長期的に必要。不採用。

**D. bootstrap.sh を repo からその都度 curl (release asset 化しない)**
tag 固定不可 → 再現性が損なわれる。Release asset なら SHA256 検証と
バージョン pin が可能。不採用。

**E. shell に fish を焼き込み**
user 層の選択に委譲すべき。system 層に fish を焼くと bare Ubuntu 経路で
不要な依存が入る。`/bin/bash` 固定 + user が mise で fish 導入可能。不採用。

## History

- 2026-07-20: initial version
