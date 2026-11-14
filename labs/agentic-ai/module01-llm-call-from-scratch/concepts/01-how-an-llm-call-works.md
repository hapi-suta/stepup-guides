# How an LLM Call Works

Before you write any code, let's get the words straight.

Each part is one idea. Read it, think about the question at the end, then say *next*.

## What an LLM actually does

An LLM reads your text.

Then it writes the text most likely to come next.

That is all it does. It learned this from a huge amount of writing, so "the most likely next text" is often a good answer.

*Think:* if it only predicts text, can it be wrong and still sound sure?

## It cannot do anything by itself

An LLM does not look things up.

It does not run commands. It cannot see your server.

It only reads what you send and writes back.

In Module 2 you give it *tools*: small pieces of your own code it can ask you to run. That is what turns a text writer into an *agent*.

## One call, start to finish

Your program sends a request over the internet.

The model sends back a response.

That's one call.

You already know this shape. It is your app sending a query to PostgreSQL and getting rows back.

## Where the call goes

*The API* is the address that answers. Think of the PostgreSQL listener on port 5432.

*The base URL* is where your calls are sent. In this course, that is the SUTA proxy.

*The client library* is the Python package that builds the request for you. Think psycopg.

## Your key

Your *API key* is a secret that says who is calling, and who pays.

Treat it like a database password.

It lives in one private file on your server. You never paste it in chat or show it to anyone.

*Think:* where do you keep PostgreSQL passwords today?

## What you send

Three things go into every call:

*The model:* which LLM answers. Here, claude-haiku-5-5.

*The system prompt:* standing instructions, like SET statement_timeout for a session.

*The messages:* the conversation so far. Your question goes here.

## What comes back

*The answer:* the text the model wrote.

*The stop reason:* why it stopped writing. Like the tag after a query: SELECT 3, or an error.

*The usage:* how much text went in and out. Like the cost line in EXPLAIN ANALYZE.

## Tokens

Models don't read words. They read *tokens*: small chunks of text.

A rough rule: 100 English words is about 130 tokens.

Code and numbers use more tokens than plain English.

*Think:* would a long SQL error message be many tokens or few?

## Why tokens matter

*Money.* You pay for every token you send and every token you get back.

*Length.* max_tokens caps how much the model may write. If it hits the cap, the answer is cut off.

*Size.* Everything you send in one call is counted. A long conversation costs more on every turn.

## What one call costs

On claude-haiku-5-5:

Text you send: 10 cents per million tokens.

Text you get back: 50 cents per million tokens.

A typical question here costs about one hundredth of a cent.

Your $5 cap covers tens of thousands of questions like that.

## Thinking costs too

The model can think before it answers.

You may never see that thinking, but you pay for it as output.

For simple questions, the tutorials ask it to keep its thinking short. That keeps the cost down.

## It remembers nothing

Every call starts from zero.

The model does not remember your last question, your name, or your server.

When a chat seems to remember, your program is resending the whole conversation every time.

It's like running psql -c again and again. Nothing from the last session survives.

*Think:* why does a long chat get more expensive with every message?

## Why it stopped

*end_turn:* it finished. Use the answer.

*max_tokens:* it hit the cap. The answer is cut off, so don't trust it as complete.

*tool_use:* it wants you to run one of your tools. You meet this in Module 2.

*refusal:* it declined. Show that to the user. Don't just retry.

## Why your calls go through a proxy

Calls cost real money.

SUTA's paid key stays on SUTA's server. Your server never sees it.

Instead, you get a *personal key* that only works through the SUTA proxy.

You already know this pattern. It is PgBouncer: apps talk to the pooler, and only the pooler holds the real connection.

## Your $5 cap

Your key can spend up to $5.

When you reach it, calls fail with "budget exceeded" until Prof. Happy raises it.

It's the same idea as a role's CONNECTION LIMIT, only for money.

Every call is logged with your key name, the tokens and the cost. What you write is not stored.

*Think:* why is a cap per student safer than one shared key?

## Your answers will differ

Ask the same question twice and you get two different answers.

That's normal. The model picks its words fresh every time.

So nobody checks your work by the exact words the AI wrote.

We check what your program *did*: the files it made, the log lines it wrote, the exit codes.

That's the habit you're building: judge an AI program by what it did, not by how it sounds.
