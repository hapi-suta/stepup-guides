# SURVIVE: Provider deprecated a model - cut over with no downtime

Your LLM app was pinned to a specific provider model version. The provider
retired that version. Overnight, every call started failing and your app went
down - even though your code never changed. This is a model-provider change
(Concepts 10.5), a failure mode classical models do not have: you do not own the
model, so the vendor can pull it out from under you.

Your job is to detect the deprecation, cut over to a supported model version
through the model registry - with no code change and no downtime - prove the app
can reach its model again, and document the cutover. Everything runs offline; a
mock provider simulates the deprecation.

Before you start, run the injector if you have not already:

```
bash inject.sh
```

That builds `~/survive-model-deprecation`, registers three model versions, pins
the app to the (now deprecated) 2024 version, and runs the health probe so you
can see the app is down.

---

## Layer 1: Detect

On your lab server, as ec2-user, move into the working directory. `cd` changes
your current directory so the commands find the files.

```
cd ~/survive-model-deprecation
```

Activate the virtual environment. `source` loads the venv.

```
source .venv/bin/activate
```

Run the health probe. It calls the active model version once - this is what an
uptime check or deploy gate uses to know the app can reach its model.

```
python probe.py
```

Expected output (yours will differ):

```
PROBE: FAIL - active model support-model-2024-01 unusable: model support-model-2024-01 has been deprecated by the provider
```

The probe fails and tells you exactly why: the provider deprecated
support-model-2024-01, which the app is pinned to. This is a vendor-side change,
not a bug in your code. Find out what the registry has active.

```
python model_registry.py active
```

Expected output (yours will differ):

```
active model version: support-model-2024-01
```

The active version is the dead one. You need to cut over to a version the
provider still serves.

---

## Layer 2: Diagnose

List all registered model versions to see what you can cut over to.
`model_registry.py list` prints each version and its status.

```
python model_registry.py list
```

Expected output (yours will differ):

```
support-model-2024-01      active
support-model-2025-06      standby
support-model-2025-11      standby
```

Two newer versions are on standby. Before you promote one, confirm it actually
works at the provider, so you do not cut over into a second dead model.
`python -c` runs a one-line program that calls the 2025-11 model directly.

```
python -c "import provider; print(provider.call('support-model-2025-11', 'test'))"
```

Expected output (yours will differ):

```
[support-model-2025-11] answer: refunds are within 30 days with a receipt.
```

The 2025-11 version answers. It is a safe cutover target. Notice you did not have
to edit any application code to check this - the model version is data in the
registry, which is exactly why the cutover will be clean.

---

## Layer 3: Correct and validate

Cut over. `model_registry.py promote` demotes the current active version to
standby and makes the new version active. Because the app reads the active
version from the registry at call time, this switches all traffic to the
supported model with no code change and no restart.

```
python model_registry.py promote support-model-2025-11
```

Expected output (yours will differ):

```
cut over: support-model-2025-11 is now the active model version
```

Prove the app can reach its model again. Run the same probe that failed before.

```
python probe.py
```

Expected output (yours will differ):

```
PROBE: OK - active model support-model-2025-11 answered
```

The probe passes on the new version. The app is back up. Confirm the active
pointer:

```
python model_registry.py active
```

Expected output (yours will differ):

```
active model version: support-model-2025-11
```

Now document the cutover. Open the file with vi.

```
vi deprecation_cutover.md
```

In vi, press `i` to enter insert mode, type your write-up, then press `Esc` and
type `:wq` and press Enter to save and quit. Make sure you mention the
deprecation, describe the cutover to a new version, and name a prevention
(abstraction, fallback, or versioning). Something like:

```markdown
# Cutover: provider deprecated support-model-2024-01

## What happened
The provider deprecated support-model-2024-01, the model version our app was
pinned to. The health probe failed because that version no longer exists at the
provider.

## Response
Cut over via the model registry: promoted support-model-2025-11 to active. No
code change and no downtime - the app reads the active version from the
registry, so flipping the pointer switched all traffic to the supported model.
The probe passed on the new version.

## Prevention
Keep a provider abstraction so model versions are configuration, not code. Keep
a standby version registered and a fallback path. Track provider deprecation
notices ahead of time. Do not lock the app to a single hardcoded model version.
```

Now validate your work. This runs the checker, which confirms the active version
is a supported one, the probe passes, and your write-up covers the right points.

```
bash validate.sh
```

Expected output (yours will differ):

```
=== Validating SURVIVE: provider-model-deprecation ===
OK:   active version is support-model-2025-11 (cut over off the deprecated model)
OK:   health probe passes (app can reach its model again)
OK:   deprecation_cutover.md exists
OK:   write-up mentions the deprecation
OK:   write-up describes the cutover to a new version
OK:   write-up names a prevention (abstraction/fallback/versioning)
RESULT: PASS - cut over to a supported model version, probe healthy, documented
```

If you see RESULT: PASS you have survived the scenario.

Note: promoting support-model-2025-06 instead of 2025-11 is equally correct -
the validator accepts any supported version.

---

## The lesson

The reason this outage lasted one command instead of an emergency code deploy is
that the model version was configuration in a registry, not a string hardcoded in
the app. When you do not own the model, the vendor's roadmap is your risk: they
deprecate versions, change behaviour, and raise prices on their schedule, not
yours. The consulting takeaway from Tier 6 carries straight into operations -
keep a provider abstraction, register a standby version, and have a fallback, so
a deprecation is a pointer flip, not a fire drill. Being able to cut providers or
versions cleanly is also your client's exit strategy against vendor lock-in.

Prof. Happy (SUTA Labs)
