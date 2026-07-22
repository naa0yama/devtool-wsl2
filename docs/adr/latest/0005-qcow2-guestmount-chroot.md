# 0005. qcow2 プロビジョニングに guestmount+chroot を採用

- Status: Superseded by ADR-0007
- Date: 2026-07-22
- Deciders: naa0yama

## Context

qcow2 golden image のプロビジョニングで `virt-customize` (libguestfs 1.52)
の DNS 解決が失敗したため、guestmount + chroot 方式に切り替えた。
経緯の全文は archive 版を参照:
[archive/0005/qcow2-guestmount-chroot-20260722.md](../archive/0005/qcow2-guestmount-chroot-20260722.md)

## Decision

**ADR-0007 により supersede された。**

guestmount (FUSE) が本 ADR 採用後に判明した 2 つの致命的問題の
共通根本原因だった:

1. dpkg の fsync 多発 write が FUSE → appliance 往復で 10 倍超遅い
   (noble system layer だけで 34 分、CI 1 run 30-60 分)
2. FUSE mount は `allow_other` なしで非 root UID のアクセスを拒否し、
   user layer の特権降格 (uid 1100) が EACCES で失敗 (一度も成功せず)

qcow2 焼き工程そのものが廃止され、guestmount + chroot 方式は削除された。
現行方式 (stock cloud image + bootstrap.sh oneliner + KVM boot 検証) は
ADR-0007 を参照。

## Consequences

- 本 ADR が解決した DNS 問題 (libguestfs appliance) は、libguestfs 自体を
  使わなくなったため問題ごと消滅した

## Alternatives Considered

archive 版を参照。

## History

- 2026-07-20: initial version
  ([archive/0005/qcow2-guestmount-chroot-20260722.md](../archive/0005/qcow2-guestmount-chroot-20260722.md))
- 2026-07-22: superseded by ADR-0007
  ([0007-vm-bootstrap-oneliner.md](0007-vm-bootstrap-oneliner.md))
