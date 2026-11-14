# How Python Runs Your Tools

Six ideas, each with something you already know from databases. The tutorials use all of them.

Each part is one idea. Read it, think about the question at the end, then say *next*.

## Every value has a type

In Python, every value has a *type*.

"FATAL" is a *str*: text. Like a text column.

5701 is an *int*: a whole number. Like an integer column.

The type decides what you can do with the value.

## Text is not a number

"5701" with quotes is text.

5701 without quotes is a number.

You can add 1 to the number. Adding 1 to the text is an error.

Python never converts for you. You convert on purpose, with int("5701").

*Think:* a log file is read as text. When does its pid become a number?

## A name is a label

pid = 5701 puts a label called pid on the value 5701.

Write pid = 6000 and the label moves to the new value.

That's all the = sign does here. It doesn't compare. Two == signs compare.

## Strings are rows of letters

A string is a row of characters, counted from 0.

line[0] is the first character.

line[:23] is characters 0 up to 23, not including 23.

line[24:] is everything from character 24 to the end.

*Think:* this is substring() in SQL, with different spelling. What would line[0:4] give for "2026-11-04"?

## Cutting at a separator

text.split(":", 1) cuts the text at the first colon only.

You get back two pieces.

The 1 matters. Log messages often contain more colons, and you only want the first cut.

text.strip() removes spaces from both ends.

## Lists hold many things

A *list* keeps values in order: ["LOG", "FATAL", "ERROR"].

You add to the end with .append().

You walk through it with a for loop, one item at a time.

It's like a cursor over a result set.

## Dictionaries look things up

A *dictionary* maps a key to a value: {"pid": 5701, "severity": "FATAL"}.

record["severity"] finds the value by its key. Like looking up a row by its primary key.

A list of dictionaries is a table. Each dictionary is a row.

*Think:* if each log line becomes a dictionary, what does the whole log become?

## Asking politely

record["pid"] on a missing key is an error: *KeyError*.

counts.get("FATAL", 0) asks politely: give me the value, or 0 if there isn't one.

That one habit is how you count things. And counting things is GROUP BY.

## A function does one job

def parse_line(line): starts a *function* called parse_line.

It takes an input, does one job, and hands a result back.

Small functions are what make testing possible. You can't test "the agent". You can test parse_line.

## Return is not print

*print* shows text to a person at a terminal.

*return* hands a value back to the code that called the function.

A tool must return. The thing calling it is your agent loop, not a person.

*Think:* if a tool only prints, what does the agent loop receive?

## When something breaks

When Python can't do what a line says, it *raises an exception*.

ValueError: the right type, but a wrong value.

TypeError: the wrong type.

KeyError: a missing dictionary key.

FileNotFoundError: no such file.

## Reading the error

If nothing catches the exception, the program stops and prints a *traceback*.

Read it from the bottom.

The last line says what went wrong.

The lines above show how the program got there.

## Your own errors

raise ValueError("clear message") fails on purpose, early, in your words.

try and except catch a failure so your program can carry on.

Your agent loop sends a tool's error message to the model. So a clear message is a model that can recover.

*Think:* "not enough values to unpack" or "not a PostgreSQL log line": which one helps?

## A test is a promise

A test is a small function that calls your code and says what must be true.

assert parse_line(LINE)["pid"] == 5701

pytest runs every function whose name starts with test_, and tells you which promises held.

## Why tests matter here

Tests let you change code next week without breaking what worked this week.

They are also how this track checks your work. Nobody reads your code to grade it.

The tests run, and they pass or they don't.

## What to carry into the tutorials

Text stays text until you convert it.

A list of dictionaries is a table.

Return is for code. Print is for people.

Fail early, with a message that names the problem.

A promise without a test is only a hope.
