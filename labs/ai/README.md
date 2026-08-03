# AI Mastery Curriculum

A hands-on AI learning path built with the CBUSI methodology (Concepts, BUILD, USE, SURVIVE, Interview). Every command tested on real hardware. Every output verified.

## Curriculum Structure

### Phase 0: Python Through the DBA Lens (Prerequisites)
| Module | Topic | Time |
|--------|-------|------|
| 00a | [Python from Scratch](module00a-python-from-scratch/) | 1 week |
| 00b | [Data Structures](module00b-data-structures/) | 1 week |
| 00c | [Python DBA Automation](module00c-python-dba-automation/) | 1 week |
| 00d | [Python DBA Toolkit](module00d-python-dba-toolkit/) | 3 weeks |

Module 00d teaches every Python concept by automating a real PostgreSQL DBA task - 18 BUILD guides mapping Python concepts to stepup-guides/postgres modules (installation, users, backup, replication, monitoring, upgrades, partitioning, etc.). You finish with a complete `~/pgdba/` toolkit of 18 working scripts.

### Phase 1: Ship First (Months 1-2)
| Module | Topic | Time |
|--------|-------|------|
| 01 | [Python for AI](module01-python-for-ai/) | 1 week |
| 02 | [Prompt Engineering](module02-prompt-engineering/) | 1 week |
| 03 | [RAG Systems](module03-rag-systems/) | 2 weeks |
| 04 | [AI Agents & MCP](module04-agents-and-mcp/) | 2 weeks |

### Phase 2: Go Deeper (Months 3-4)
| Module | Topic | Time |
|--------|-------|------|
| 05 | [Math for AI](module05-math-for-ai/) | 2 weeks |
| 06 | [Classical Machine Learning](module06-classical-ml/) | 2 weeks |
| 07 | [Neural Networks](module07-neural-networks/) | 2 weeks |
| 08 | [Transformers & Attention](module08-transformers-and-attention/) | 2 weeks |

### Phase 3: Production Skills (Months 5-6)
| Module | Topic | Time |
|--------|-------|------|
| 09 | [Fine-Tuning](module09-fine-tuning/) | 1 week |
| 10 | [Evaluation & Testing](module10-evaluation-and-testing/) | 1 week |
| 11 | [Vector DBs Deep Dive](module11-vector-dbs/) | 1 week |
| 12 | [AI Pipelines](module12-ai-pipelines/) | 1 week |
| 13 | [Model Serving & Deployment](module13-model-serving/) | 2 weeks |
| 14 | [MLOps](module14-mlops/) | 2 weeks |

### Phase 4: Specialize & Ship (Months 7-8)
| Module | Topic | Time |
|--------|-------|------|
| 15 | [AI Security & Guardrails](module15-ai-security/) | 1 week |
| 16 | [Multi-Modal AI](module16-multi-modal/) | 1 week |
| 17 | [AI for Databases (dbaBrain)](module17-ai-for-databases/) | 2 weeks |
| 18 | [Multi-Agent Systems](module18-multi-agent/) | 2 weeks |
| 19 | [Capstone: Ship an AI Product](module19-capstone/) | 2 weeks |

## Each Module Contains

```
module-XX-topic/
  concepts/    - What it is, why it matters, how it connects to what you know
  build/       - Step-by-step hands-on guides (tested, with expected output)
  use/         - Progressive exercises (task, hints, solution)
  survive/     - Break it, debug it, fix it (real failure scenarios)
  interview/   - Questions and model answers for AI engineering interviews
```

## Environment

- macOS (Apple Silicon)
- Python 3.13 (Anaconda)
- NumPy, Pandas, Matplotlib, scikit-learn (pre-installed)
- PostgreSQL 14 (Homebrew)
- Anthropic/OpenAI SDKs (installed in Module 02)
- Ollama (installed in Module 13)

## Methodology

Built using the SUTA Labs CBUSI methodology:
- Written for complete beginners to AI (not to programming)
- Every concept explained with DBA analogies first
- Every command tested and output captured on real hardware
- Progressive difficulty within and across modules
- SURVIVE scenarios based on real production failures
