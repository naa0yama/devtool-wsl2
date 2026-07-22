# 0003. Ubuntu 向けは 2 経路 (golden image + bootstrap)

- Status: Superseded by ADR-0007
- Date: 2026-07-22
- Deciders: naa0yama

## Context

PVE VM 上に devtool-wsl2 相当の環境を再現する手段として、
経路 A (構築済み qcow2 golden image 配布) と経路 B (bootstrap.sh 直接実行)
の 2 経路並行提供を決定していた。全文は archive 版を参照:
[archive/0003/ubuntu-two-paths-20260722.md](../archive/0003/ubuntu-two-paths-20260722.md)

## Decision

**ADR-0007 により supersede された。**

経路 A (golden image 配布) は廃止され、経路 B (bootstrap.sh oneliner) に
一本化された。qcow2 焼き工程 (guestmount + chroot) が CI で一度も成功せず、
支点の再確認で「pre-baked 配布」ではなく「out-of-box 体験」が本質と
判明したため。

ただし本 ADR の中核原則「**経路 A は経路 B の実行結果のキャッシュ**」は
生きている: 将来 pre-baked 配布が必要になれば、ADR-0007 の KVM boot
検証経路の末尾に shutdown + sparsify + upload を追加する形で、
実装共有を保ったまま経路 A を復活できる。

## Consequences

- bootstrap.sh の Single Source of Truth 地位は維持
  (消費者: WSL2 Dockerfile / VM oneliner / KVM boot CI)
- finalize.sh の管理コストは経路 A 廃止に伴い消滅

## Alternatives Considered

archive 版を参照。

## History

- 2026-07-19: initial version
  ([archive/0003/ubuntu-two-paths-20260722.md](../archive/0003/ubuntu-two-paths-20260722.md))
- 2026-07-22: superseded by ADR-0007
  ([0007-vm-bootstrap-oneliner.md](0007-vm-bootstrap-oneliner.md))
