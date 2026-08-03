# SURVIVE: KMS / Secrets Manager Rotation Breaks the App

Your AI application reads its model API key from Secrets Manager, but it PINS a
specific secret version. A scheduled rotation created a new version and disabled
the old one - normal, healthy security hygiene (Concepts 13.1). Because the app
is pinned to the now-disabled old version, it can no longer read the key, and the
feature is down. Rotation is supposed to be transparent; a badly written app
turns it into an outage.

In this runbook you will detect the breakage, diagnose the real cause (a pinned
version instead of the active one), and fix it so rotation is transparent.

**No real cloud and no credentials are involved.** The Secrets Manager and its
versions are a LOCAL JSON store that a mock client reads, so you test the
resilience LOGIC (read the ACTIVE version, survive rotation) for free. In a real
system the same rule applies to a KMS key alias: reference the current key, not a
specific key version that rotation will retire.

This runbook uses the SUTA 3-layer structure:

1. Detect - confirm something is wrong.
2. Diagnose - find the real cause.
3. Fix and verify - repair it and prove the repair.

---

## Layer 1: Detect

First run the injector so you can see the breakage.

On your lab server, as ec2-user:

```
bash inject.sh
```

`bash` runs the script. It writes the secrets store (version v1 active), a mock
secrets client, and an app pinned to v1; runs the app successfully; then ROTATES
the secret (v2 becomes active, v1 disabled) and runs the app again.

Expected output (yours will differ):

```
==> Confirming the app works BEFORE rotation:
RESULT api_key_loaded=key-AAAA-initial

==> ROTATING the secret now (v2 becomes ACTIVE, v1 becomes DISABLED)...

==> Running the app AFTER rotation so you can see it break:
-------------------------------------------------------------
Traceback (most recent call last):
  ...
secrets_client.SecretError: version v1 is DISABLED, cannot read
-------------------------------------------------------------
```

The app worked before rotation and threw `version v1 is DISABLED, cannot read`
after. That is the outage: rotation retired v1, and the app is stuck on v1.

---

## Layer 2: Diagnose

Move into the working directory.

On your lab server, as ec2-user:

```
cd ~/survive-kms-rotation
```

Look at how the app loads the key.

Still on your lab server, as ec2-user:

```
grep -n "PINNED_VERSION\|get_secret" app_secret.py
```

`grep -n` prints matching lines with line numbers.

Expected output (yours will differ):

```
12:PINNED_VERSION = "v1"  # BUG: pinned to a version that rotation will disable
16:    return get_secret(version=PINNED_VERSION)
```

The app calls `get_secret(version="v1")` - it asks for one specific version by
name. Confirm what versions actually exist now.

Still on your lab server, as ec2-user:

```
cat secrets_store.json
```

Expected output (yours will differ):

```
{
  "secret_name": "ai-app/model-api-key",
  "versions": {
    "v1": {"status": "DISABLED", "value": "key-AAAA-initial"},
    "v2": {"status": "ACTIVE", "value": "key-BBBB-rotated"}
  }
}
```

v1 is `DISABLED`; v2 is `ACTIVE`. The real cause is not the rotation - rotation
is correct and necessary. The cause is that the app pins a version instead of
asking for whichever version is currently active. A resilient app reads the
ACTIVE secret, so rotation is invisible to it.

---

## Layer 3: Fix and verify

Change the app to read the active version, not a pinned one.

Still on your lab server, as ec2-user, open the app:

```
vi app_secret.py
```

Press `i` to enter insert mode. Replace the `PINNED_VERSION` line and the
`load_api_key` function so it reads the active version (the mock's `get_secret()`
with no argument returns whichever version is ACTIVE):

```python
from secrets_client import get_secret


def load_api_key() -> str:
    # FIX: read the ACTIVE version, so a rotation transparently picks up the new
    # key instead of pinning to a version that rotation will disable.
    return get_secret()
```

Press `Esc`, type `:wq`, press Enter. Run the app again.

Still on your lab server, as ec2-user:

```
python3 app_secret.py
```

Expected output (yours will differ):

```
RESULT api_key_loaded=key-BBBB-rotated
```

Signs of a rotation-safe app:

- It ran cleanly after rotation instead of crashing.
- It loaded the NEW key (`key-BBBB-rotated`, the v2 value) automatically.
- No code change would be needed for the next rotation - it always reads active.

In a real AWS system this maps to two habits: for Secrets Manager, retrieve the
secret by name (which returns the current version) rather than pinning a version
id; for KMS, reference the key by its alias or key id and let rotation swap the
backing material, rather than caching a specific key version. Design for
rotation, because rotation will happen.

---

## Verify

Run the scenario validator to confirm the fix.

On your lab server, as ec2-user:

```
bash validate.sh
```

`bash` runs the validator. It forces the store into the rotated state (v1
disabled, v2 active), reruns your app, and checks it loaded the new active key.

Expected output (yours will differ):

```
Ensuring the secret is in the rotated state (v1 DISABLED, v2 ACTIVE) ...
Running app_secret.py after rotation ...
RESULT api_key_loaded=key-BBBB-rotated
PASS: after rotation the app loaded the new ACTIVE key (v2) with no downtime.
```

If you see `PASS`, you are done.

---

Prof. Happy (SUTA Labs)
