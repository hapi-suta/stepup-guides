# What Makes It an Agent

This module rests on one idea: an agent is an LLM call inside a loop, plus tools your code runs for it.

Each part is one idea. Read it, think about the question at the end, then say *next*.

## The model can't touch anything

In Module 1 the model only wrote text.

It can't read your disk. It can't open a log file. It can't query a database.

Ask it "how full is my disk?" and the best it can do is guess, or tell you how to check.

*Think:* would you trust a guess about your disk space?

## Tools fix that

A *tool* is a normal Python function you wrote, plus a short description the model can read.

The model still doesn't run anything.

When it needs information, it sends back a *request*: "please run disk_usage on /".

Your code decides whether to run it. Then it runs it and sends the result back.

## A consultant on the phone

Think of the model as a consultant on the phone.

It can't touch your server.

It can say "run df -h and read me the output."

You decide whether to do it. Your code is the person with their hands on the keyboard.

*Think:* who is in control here, the model or your code?

## One round trip, part 1

*1. Your code* sends the question, plus the list of tools it may ask for.

*2. The model* replies: "I want a tool." It names the tool, the inputs, and gives the request an *id*.

*3. Your code* runs that tool with those inputs.

## One round trip, part 2

*4. Your code* sends the result back, carrying the *same id*.

*5. The model* either asks for another tool, or writes its final answer.

## Why the id matters

The id is how the model matches a result to its request.

It's like a transaction id matching a COMMIT to its BEGIN.

Send a result with the wrong id and the whole request is rejected.

*Think:* what would happen if two tool results came back with their ids swapped?

## The loop

Steps 2 to 5 repeat until the model stops asking for tools.

That repetition is the *agent loop*:

1. Call the model with the conversation and the tools.

2. Done asking for tools? Print the answer and stop.

3. Otherwise run every tool it asked for, and add the results to the conversation.

4. Go back to 1.

## No magic

In Build 03 you write this loop yourself, in about 50 lines of plain Python.

Frameworks like LangGraph are this same loop with more features.

Once you have written it by hand, no framework is magic.

## Every loop needs limits, part 1

An agent picks its own next step. So your code sets the limits it can't cross.

*A maximum number of turns.* A confused model can ask for tools forever, and every turn costs money. Think statement_timeout.

*Read-only tools.* The model chooses the inputs. Never give it a tool that changes data. Think of a read-only reporting role.

## Every loop needs limits, part 2

*Capped tool output.* A tool that returns a 2 GB log makes every later turn expensive. Think LIMIT on a query.

*Errors go back to the model.* If a tool fails, tell the model so it can try something else. Don't crash.

*A log of every tool call.* You must be able to prove what the agent did. Think pgaudit.

*Think:* which of these five would you add first, and why?

## The answer can still be wrong

Tools give the model real data. But the model still writes the conclusion.

It can misread a log line. It can overstate a cause.

Two habits protect you:

Make it *show what it checked*. Your tool-call log does this.

Judge it by its *evidence*, not its confidence. A calm answer built on the wrong log line is still wrong.

## Words you will meet

*Tool definition:* the name, description and inputs. This is all the model sees, never your Python.

*tool_use:* the model's request to run a tool.

*tool_result:* your answer, with the matching id.

*Turn:* one call to the model inside the loop.

*Agent:* an LLM that picks tools, in a loop, until the job is done.
