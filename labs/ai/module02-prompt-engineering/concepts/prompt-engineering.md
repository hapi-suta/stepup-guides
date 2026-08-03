# Concepts: Prompt Engineering

## What Is This Module?

Prompt engineering is how you talk to AI models to get useful results. It's the difference between getting garbage and getting gold - same model, same data, different instructions.

You already do this. When you write a runbook for a junior DBA, you don't say "fix the database." You say "SSH into pg-primary as ec2-user, run `pg_isready`, check the output for 'accepting connections', and if it says 'no response' then check if the service is running with `systemctl status postgresql`." That level of specificity is prompt engineering.

## Why This Matters

Prompt engineering is the #1 most immediately useful AI skill because:

- **No training data needed** - you get results in seconds, not days
- **No GPU needed** - runs on API calls from your laptop
- **No math needed** - it's about clear communication, not calculus
- **Directly applicable** - everything you learn here feeds into RAG (Module 03), Agents (Module 04), and dbaBrain

Every AI application - chatbots, code generators, data analyzers, agent systems - starts with a well-crafted prompt.

## The Anatomy of a Prompt

Every API call to Claude has up to three parts:

```
SYSTEM PROMPT (optional but critical)
  "You are a PostgreSQL DBA with 15 years of experience..."
  Sets the persona, rules, and constraints.
  Think of it as the job description.

USER MESSAGE (required)
  "Why is my replication lagging by 30 seconds?"
  The actual question or task.

ASSISTANT MESSAGE (the response)
  Claude's answer, shaped by the system prompt + user message.
```

## Key Techniques (Preview)

| Technique | What It Is | DBA Analogy |
|-----------|-----------|-------------|
| System prompt | Set the AI's role and rules | Writing a runbook's "Prerequisites" section |
| Few-shot | Give examples of good input/output | Showing a junior DBA example tickets before they start |
| Chain-of-thought | Ask the AI to reason step by step | "Walk me through your troubleshooting steps" |
| Structured output | Force JSON/specific format responses | Query results in a table, not a paragraph |
| Temperature | Control randomness (0=deterministic, 1=creative) | Strict mode vs brainstorming mode |
| ReAct | Reason then Act - think before doing | "Tell me what you'll do BEFORE you run the command" |

## The Prompt Engineering Spectrum

```
Vague prompt          -->  Specific prompt
"Help with database"      "You are a PostgreSQL 16 DBA. Analyze this
                           pg_stat_activity output and identify the
                           query causing lock contention. Return your
                           answer as JSON with fields: blocking_pid,
                           blocked_query, recommended_action."
```

The more specific your prompt, the more useful the output. This module teaches you to go from left to right on that spectrum.

## Common Mistakes

1. **Being too vague** - "Summarize this" vs "Summarize this in 3 bullet points, focusing on performance impact"
2. **Not setting a system prompt** - The model has no context about what you need
3. **Asking for everything at once** - Break complex tasks into steps
4. **Not providing examples** - Show the model what good output looks like
5. **Ignoring temperature** - Using temperature=1 for factual tasks (causes hallucination)

## How It Connects to Later Modules

- **Module 03 (RAG):** The prompt includes retrieved documents as context
- **Module 04 (Agents):** The prompt tells the agent what tools it has and how to use them
- **Module 09 (Fine-tuning):** When prompt engineering isn't enough, you train the model
- **Module 17 (AI for Databases):** dbaBrain's Sage engine is built on carefully engineered prompts

## Prerequisites

- An Anthropic API key (free tier gives you some credits)
- Python 3.x with the `anthropic` SDK installed
- A terminal
