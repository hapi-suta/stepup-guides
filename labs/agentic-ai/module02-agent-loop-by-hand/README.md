# Module 02 - The Agent Loop by Hand

Part of the Agentic AI Engineering track. Turn a single LLM call into an agent: give the model read-only tools, catch its tool requests, run them, send the results back, and loop until it is done. About 50 lines of plain Python, no framework, every tool call logged.

**Environment:** the same **ai-lab** server and `~/agentic-ai` workspace as Module 01, user **ec2-user**. The tools read a sample PostgreSQL log (`data/postgresql.log`) and the server's disk usage. Nothing the agent can call changes anything.

**Time:** 2-3 hours

## Concepts
- What Makes It an Agent

## Build
- Build 01 - Tools the Model Can Ask For
- Build 02 - One Round Trip
- Build 03 - The Agent Loop
- Build 04 - When a Tool Fails

## Use
- Assignment 01 - Give Your Agent a Third Tool

## Survive
- Challenge 01 - The Result Nobody Asked For
