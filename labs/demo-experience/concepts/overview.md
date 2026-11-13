# Concepts: demo cache HA (engine proof fixture)

This tiny doc exists to prove the CBUSI engine teaches a second experience from a
different manifest + content, with no engine code change (docs/loops/cbusi-engine-loop.md, E7).

## Overview

We are building a small in-memory cache tier that must stay available for a demo
service. The point of this fixture is that the tutor grounds on THIS document, not
the Patroni concept doc.

## The cache tier

Two cache nodes and one coordinator keep a hot key-value set available. If a cache
node drops, the coordinator promotes the survivor so reads keep working.
