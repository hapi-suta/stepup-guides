# How an LLM Call Works

Read this before Build 01. It explains the words the tutorials use, with a DBA comparison for each one. No code.

---

## 1. What an LLM is, in one paragraph

A **large language model (LLM)** is a program that reads text and writes the most likely next text, one small piece at a time. It was trained on a huge amount of writing, so "the most likely next text" is often a useful answer, an explanation, or a block of code. It does not look anything up and it does not run anything by itself. It only reads what you send and writes back.

That last sentence matters for the whole course. In Module 2 you give the model **tools** (your code that does look things up), and that is what turns a text writer into an **agent**.

---

## 2. The pieces of one call

| Term | Meaning | DBA comparison |
|---|---|---|
| **API** | A web address that accepts requests and returns responses | A database listener on port 5432 |
| **Client library** (`anthropic`) | Python code that formats the request and parses the response for you | `psycopg` or `libpq` |
| **API key** | A secret that identifies who is calling and who pays | A password, stored like `.pgpass` (mode 600, never shared) |
| **Base URL** | Where the requests go. For this course: the SUTA proxy | The host in your connection string |
| **Model** | Which LLM answers (`claude-haiku-5-5` in this course) | Which database you connect to |
| **Messages** | The conversation: a list of `user` and `assistant` turns | The SQL you send |
| **System prompt** | Standing instructions for the whole conversation | Session settings (`SET search_path`, `SET statement_timeout`) |
| **Response content** | A list of **blocks**: text, and later tool requests | The result set |
| **Stop reason** | Why the model stopped writing | The command tag (`SELECT 3`, or an error) |
| **Usage** | Tokens in and tokens out for this call | The cost line of `EXPLAIN ANALYZE` |

---

## 3. Tokens

Models do not read letters or words. They read **tokens**: small chunks of text. In English a token is roughly three quarters of a word, so 100 words is about 130 tokens. Code, numbers and other languages usually take more tokens per word.

Tokens matter for three reasons:

1. **Cost.** You pay per token, input and output priced separately.
2. **Limits.** `max_tokens` caps how much the model may write in one call. If it hits the cap, the answer is cut off and `stop_reason` is `max_tokens`.
3. **Context.** Everything you send in one call (system prompt, all messages, tool results) is counted as input. A long conversation means many input tokens on every call.

You can count tokens before sending with `count_tokens`. It is free, and it is the `EXPLAIN` to the call's `EXPLAIN ANALYZE`.

---

## 4. Cost

For `claude-haiku-5-5`:

| | Price per million tokens | Price per token |
|---|---|---|
| Input | $0.10 | $0.0000001 |
| Output | $0.50 | $0.0000005 |

Cost of one call = input tokens x input price + output tokens x output price.

A typical question in this course: about 30 tokens in and 200 out, so about $0.0001. Your $5 cap covers tens of thousands of calls like that. Agents are more expensive, because one question becomes several calls, and every call resends the growing conversation.

Output tokens include the model's **thinking**. Claude models can reason before they answer, and that reasoning is billed as output even when you do not see it. `output_config={"effort": "low"}` keeps that thinking short for simple questions.

---

## 5. Stateless: the model remembers nothing

Each call is independent. The model does not remember your last call, your name, or your database. If a chat seems to remember, it is because the program **resends the whole conversation** every time.

DBA comparison: each call is a separate `psql -c` session. Session state (temporary tables, `SET` values) is gone the moment the session ends.

Consequence: conversation cost grows with every turn, because turn 10 resends turns 1 to 9.

---

## 6. Stop reasons you will see in this course

| Stop reason | What happened | What your program should do |
|---|---|---|
| `end_turn` | The model finished its answer | Use the answer |
| `max_tokens` | The cap cut it off | Do not trust it as complete; raise `max_tokens` or ask for less |
| `tool_use` | The model wants you to run a tool (Module 2) | Run the tool, send the result back |
| `refusal` | The model declined | Show the refusal; do not retry blindly |

---

## 7. Why a proxy, and why your key has a cap

Every call costs real money. Instead of sharing one paid key (which nobody could revoke or limit), each student gets a **personal key** that only works through the **SUTA LLM proxy**:

- The real paid key stays on SUTA's server. Your server never sees it.
- Your key has a **$5 cap**. When you hit it, calls fail with a "budget exceeded" error until Prof. Happy raises it.
- Every call is logged with your key's name, tokens and cost. Prompts are not stored.

DBA comparison: PgBouncer in front of PostgreSQL. Applications connect to the pooler, the pooler holds the real connection and enforces limits. If you have used connection limits per role (`ALTER ROLE ... CONNECTION LIMIT`), the per-key cap is the same idea, for money.

---

## 8. Your answers will differ

The model chooses its words fresh on every call, so two runs of the same program give two different answers. That is why every tutorial says "Expected output (yours will differ)", and why SutaAI checks your work by looking at **side effects** (files, log lines, exit codes), never by matching the exact words the model wrote.

You will build the same habit: judge an AI program by what it did and what it logged, not by how its answer sounds.
