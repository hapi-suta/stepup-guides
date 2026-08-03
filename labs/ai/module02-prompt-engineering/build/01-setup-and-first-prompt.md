# Build 01: Setup and Your First Prompt

Get the Anthropic SDK installed, send your first API call, and understand the request/response structure.

---

## Step 1. Install the Anthropic SDK

On your **Mac terminal**, run:

```bash
pip3 install anthropic
```

Expected output (yours will differ):
```
Successfully installed anthropic-0.107.1
```

Verify it installed:

```bash
python3 -c "import anthropic; print(f'Anthropic SDK version: {anthropic.__version__}')"
```

Expected output:
```
Anthropic SDK version: 0.107.1
```

---

## Step 2. Set your API key

You need an API key from Anthropic. Go to https://console.anthropic.com/settings/keys and create one.

Set it as an environment variable so your scripts can use it without hardcoding:

```bash
export ANTHROPIC_API_KEY="sk-ant-your-key-here"
```

To make it permanent (survives terminal restarts), add it to your shell profile:

```bash
echo 'export ANTHROPIC_API_KEY="sk-ant-your-key-here"' >> ~/.zshrc
```

Verify it's set:

```bash
echo $ANTHROPIC_API_KEY | head -c 10
```

Expected output:
```
sk-ant-api
```

- Never hardcode API keys in scripts. Always use environment variables.
- Never commit API keys to git. Add `.env` to your `.gitignore`.

---

## Step 3. Send your first prompt

The simplest possible API call - one question, one answer.

```bash
python3 << 'PYEOF'
import anthropic

client = anthropic.Anthropic()

message = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=256,
    messages=[
        {"role": "user", "content": "What is PostgreSQL replication in one sentence?"}
    ]
)

print(message.content[0].text)
PYEOF
```

Expected output (yours will differ):
```
PostgreSQL replication is a feature that copies data from a primary
database server to one or more standby servers to provide high
availability, load balancing for read queries, and data redundancy.
```

Let's break down what happened:

- `anthropic.Anthropic()` creates a client - it reads `ANTHROPIC_API_KEY` from your environment automatically
- `model="claude-sonnet-4-20250514"` picks which Claude model to use. Sonnet is fast and cheap - good for learning.
- `max_tokens=256` limits the response length. 1 token is roughly 4 characters.
- `messages` is a list of conversation turns. Each has a `role` ("user" or "assistant") and `content`.
- `message.content[0].text` extracts the text from the response.

---

## Step 4. Examine the full response object

The API returns more than just text. Let's see everything.

```bash
python3 << 'PYEOF'
import anthropic

client = anthropic.Anthropic()

message = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=256,
    messages=[
        {"role": "user", "content": "What is VACUUM in PostgreSQL? One sentence."}
    ]
)

print(f'Model:        {message.model}')
print(f'Role:         {message.role}')
print(f'Stop reason:  {message.stop_reason}')
print(f'Input tokens: {message.usage.input_tokens}')
print(f'Output tokens:{message.usage.output_tokens}')
print(f'Response:     {message.content[0].text}')
PYEOF
```

Expected output (yours will differ):
```
Model:        claude-sonnet-4-20250514
Role:         assistant
Stop reason:  end_turn
Input tokens: 18
Output tokens: 42
Response:     VACUUM is a PostgreSQL maintenance operation that reclaims
              storage occupied by dead tuples...
```

- `stop_reason: end_turn` means the model finished naturally. Other values: `max_tokens` (hit the limit), `tool_use` (wants to call a tool - Module 04).
- `input_tokens` is how many tokens YOUR prompt used (you pay for these)
- `output_tokens` is how many tokens the RESPONSE used (you pay for these too)
- Pricing: input tokens are cheaper than output tokens. Keep prompts focused but don't sacrifice clarity to save tokens.

---

## Step 5. Control the temperature

Temperature controls how random/creative the output is. It's a number from 0 to 1.

- **0.0** = deterministic. Same input always gives (nearly) the same output. Use for factual tasks.
- **1.0** = creative. More varied, surprising outputs. Use for brainstorming, creative writing.

```bash
python3 << 'PYEOF'
import anthropic

client = anthropic.Anthropic()

prompt = "Name one PostgreSQL extension."

print("=== Temperature 0 (deterministic) ===")
for i in range(3):
    msg = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=50,
        temperature=0,
        messages=[{"role": "user", "content": prompt}]
    )
    print(f'  Run {i+1}: {msg.content[0].text.strip()}')

print()
print("=== Temperature 1 (creative) ===")
for i in range(3):
    msg = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=50,
        temperature=1,
        messages=[{"role": "user", "content": prompt}]
    )
    print(f'  Run {i+1}: {msg.content[0].text.strip()}')
PYEOF
```

Expected output (yours will differ):
```
=== Temperature 0 (deterministic) ===
  Run 1: PostGIS - a spatial database extension...
  Run 2: PostGIS - a spatial database extension...
  Run 3: PostGIS - a spatial database extension...

=== Temperature 1 (creative) ===
  Run 1: pg_trgm - provides trigram matching...
  Run 2: PostGIS for geospatial data...
  Run 3: pgcrypto for cryptographic functions...
```

Notice:
- Temperature 0 gives the same answer 3 times (deterministic)
- Temperature 1 gives different answers each time (creative)

**Rule of thumb:**
- Data analysis, code generation, factual Q&A: temperature 0
- Brainstorming, creative writing, generating variations: temperature 0.7-1.0

---

## Step 6. Handle errors gracefully

API calls can fail. Network issues, rate limits, invalid keys. Always handle errors.

```bash
python3 << 'PYEOF'
import anthropic

client = anthropic.Anthropic()

try:
    message = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=100,
        messages=[
            {"role": "user", "content": "Hello"}
        ]
    )
    print(f'Success: {message.content[0].text}')

except anthropic.AuthenticationError:
    print('ERROR: Invalid API key. Check ANTHROPIC_API_KEY.')

except anthropic.RateLimitError:
    print('ERROR: Rate limited. Wait a moment and retry.')

except anthropic.APIConnectionError:
    print('ERROR: Cannot reach API. Check your internet connection.')

except anthropic.APIError as e:
    print(f'ERROR: API error - {e.message}')
PYEOF
```

Expected output:
```
Success: Hello! How can I help you today?
```

- Always wrap API calls in try/except
- `AuthenticationError` means bad API key
- `RateLimitError` means you're sending too many requests - back off and retry
- `APIConnectionError` means network issue
- These are the same error patterns you'd handle with any external service (like a database connection)

---

## What You Learned

| Concept | What It Does | When to Use |
|---------|-------------|-------------|
| `anthropic.Anthropic()` | Creates API client | Once per script |
| `messages.create()` | Sends prompt, gets response | Every API call |
| `max_tokens` | Limits response length | Always set - prevents runaway costs |
| `temperature` | Controls randomness (0-1) | 0 for facts, 0.7+ for creativity |
| `usage.input_tokens` | Tokens in your prompt | Monitor costs |
| `usage.output_tokens` | Tokens in response | Monitor costs |
| `stop_reason` | Why the model stopped | Debug truncated responses |
| Error handling | Catch API failures | Always - production requirement |
