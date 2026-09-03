# Survive: bounded failure scenarios

Each fault is isolated, approval-gated and followed by full recovery. These actions
remain locked in the owner preview until the dedicated failure canary passes.

```bash
suta-lab scenario run primary-process-loss
```

```bash
suta-lab scenario run etcd-minority-loss
```

```bash
suta-lab scenario run haproxy-loss
```
