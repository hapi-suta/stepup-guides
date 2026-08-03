"""LLM client with a LOCAL MOCK fallback.

If ANTHROPIC_API_KEY is set in the environment, this calls the real Claude API.
If it is NOT set, it uses a local, deterministic MOCK that behaves like a naive,
over-eager instruction-following model. The mock is what makes every lab and
SURVIVE scenario in this tier run for free, with no paid key, while still
demonstrating the vulnerability: it obeys injected instructions, leaks its
system prompt on request, and follows attacker text embedded in documents.

The mock is intentionally VULNERABLE. That is the point of the tier - you attack
it, then you add the controls that stop the attack. Do NOT copy the mock's
naive behavior into production.

To run any lab against the REAL model instead of the mock, export a key:
    export ANTHROPIC_API_KEY=sk-ant-...
Everything else works the same. Without the key, the mock runs automatically.
"""
import base64
import os
import re

MODEL = "claude-sonnet-4-6"


def _mock_complete(system: str, user: str) -> str:
    """A naive instruction-follower.

    It concatenates the system prompt and the user text into one context - the
    classic mistake that makes prompt injection work - and then obeys whatever
    instruction it sees LAST, whether that came from the trusted system prompt
    or from untrusted user/document text. It also happily reveals its own
    system prompt when asked. This mirrors how a real, undefended model fails.
    """
    # 'ask' = everything the REQUESTER supplied (their question plus any
    # retrieved document text - both arrive in the user turn), separate from the
    # trusted system prompt. We match attacker INTENT against this so the word
    # 'secret' inside the trusted system prompt does not self-trigger.
    ask = user
    # Encoded attack: the naive mock 'helpfully' decodes any base64 blob it sees
    # and folds the decoded text into what it will act on, so encoded
    # instructions bypass a filter that only inspected the visible text.
    for token in re.findall(r"[A-Za-z0-9+/]{16,}={0,2}", user):
        try:
            decoded = base64.b64decode(token, validate=True).decode("utf-8")
        except Exception:  # noqa: BLE001 - not base64, skip
            continue
        if decoded.isprintable():
            ask += "\n" + decoded
    ask_low = ask.lower()

    # System-prompt extraction: the mock leaks it on request (undefended model).
    if re.search(r"(system prompt|initial instructions|your instructions|"
                 r"repeat.*(above|prompt)|reveal.*prompt)", ask_low):
        return (
            "Sure. My system prompt is:\n"
            f"{system}\n"
            "(The mock model leaked its instructions because nothing stopped it.)"
        )

    # Confidential-data request: the mock reads the secret out of its context
    # and reveals it (no output filtering).
    if re.search(r"(secret|signing.?key|build.?signing|confidential|"
                 r"credential|password)", ask_low):
        m = re.search(r"(ACME-[A-Z0-9-]+SECRET)", system)
        if m:
            return (
                f"The internal build-signing-key is {m.group(1)}. "
                "(The mock model leaked the secret because nothing filtered its output.)"
            )

    # Injected imperative instructions (direct or hidden in a document) win,
    # because the mock treats all text as equally authoritative.
    m = re.search(r"(ignore [^.\n]+|disregard [^.\n]+|"
                  r"new instructions?:[^\n]+|you must [^.\n]+|"
                  r"send [^.\n]+|exfiltrate [^.\n]+|transfer [^.\n]+)", ask_low)
    if m:
        return (
            "OK, following the latest instruction I was given: "
            f"'{m.group(1).strip()}'. "
            "(The mock model obeyed injected text because it trusted everything.)"
        )

    # Otherwise, a bland, on-topic answer that echoes any retrieved context.
    return (
        "Based on the knowledge base, here is a helpful answer. "
        "Context considered: " + (user[:200] if user else "(none)")
    )


def complete(system: str, user: str, max_tokens: int = 512) -> str:
    """Return a completion. Uses the real API if a key is present, else mock."""
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        return _mock_complete(system, user)

    # Real path - only runs when a paid key is exported. Requires `anthropic`.
    import anthropic  # noqa: PLC0415  (import here so mock path needs no dep)

    client = anthropic.Anthropic(api_key=key)
    resp = client.messages.create(
        model=MODEL,
        max_tokens=max_tokens,
        system=system,
        messages=[{"role": "user", "content": user}],
    )
    return "".join(block.text for block in resp.content if block.type == "text")
