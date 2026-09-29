---
name: python-professional
description: Use for any Python work in this workspace — LogueOS-Orchestrator kernel services (Starlette/ASGI, asyncio, the MCP gateway), seedbox-mcp, or any other Python script/service. Applies this codebase's actual conventions (ruff config, structured concurrency, Starlette lifespan pattern, the append-only jsonl rule) instead of generic Python advice. Make sure to use this whenever the user asks for a Python script, service, route, migration, test, or refactor, or mentions asyncio, Starlette, FastAPI-adjacent work, uvicorn, or a `.py` file in these repos — even if they don't say "Python" explicitly.
---

# Python Professional Developer Skill (entry / quick reference)

Lightweight entry tier — cheap on context. Pairs with the API/language-mechanics
knowledge base under Links; load both before writing non-trivial Python here.

Version anchors: Python 3.11/3.12 (per-repo — check `pyproject.toml`
`requires-python`/`target-version` before assuming). `LogueOS-Orchestrator`
gateway pins `starlette==1.1.0`, `uvicorn==0.48.0`. `seedbox-mcp` locks
`starlette==1.2.0` via `uv.lock` even though its `pyproject.toml` floor
historically read `>=0.37` — the lockfile, not the loose floor, is the source
of truth for what's actually running.

## When to use

Any Python route, service, migration, script, test, or refactor in this
workspace — the Orchestrator kernel's Starlette services
(`services/session_memory`, `services/governance_kernel`, `services/lspd`,
`tools/logueos_mcp_gateway/`), `seedbox-mcp`, or any other `.py` file. Not for
Swift/TypeScript work — use the sibling professional-practices skills for
those.

## 10 most important rules

1. Verify Starlette/asyncio APIs against current docs when unsure; do not
   write from memory. Starlette jumped 0.x → 1.x in 2026 with real breaking
   changes (`on_startup`/`on_event` removed) — training data may still
   assume the old surface.
2. **Never write a bare `except: pass`.** This isn't style — it's CWE-390
   (error condition detected, then silently discarded), and this codebase
   shipped six of them in one year, each one turning a broken safety check
   into a clean-looking one: an admission gate that failed open for weeks,
   a monitor that returned `[]` and read as "no errors," an alarm that
   could never fire, and a ledger that silently never got written. Ruff's
   `S110` catches this; don't suppress the rule to make a diff pass.
3. Every Starlette app uses the `lifespan=` async-context-manager pattern.
   Never reach for `on_startup=`/`on_event()` from an old tutorial — Starlette
   1.x removed both; the code would silently not run at all.
4. Structured concurrency first: `asyncio.TaskGroup` over bare
   `create_task`/`gather` when tasks share a failure domain, so one task's
   exception doesn't leave siblings running unsupervised. Never call
   blocking sync I/O directly inside an async function — offload via
   `asyncio.to_thread`/`run_in_threadpool`.
5. Match this repo's logger pattern: `logging.getLogger(__name__)` per
   module (see `tools/logueos_mcp_gateway/server.py`), not `print()` and not
   inventing a new logging setup per file.
6. Ruff config is real and enforced: line length 100, target `py311`. Run
   `ruff check`/`ruff format` before calling Python work done; don't
   hand-format against a different style.
7. This repo has no `basedpyright`/`mypy` config wired into CI as of this
   writing — write modern type hints anyway (they're read by humans and
   agents even without a type-checker gate), but don't invent a
   type-checking requirement that isn't actually enforced.
8. `data/*.jsonl` files in `LogueOS-Orchestrator` are **strictly
   append-only** — never edit, truncate, sort, dedupe, or read-modify-write
   one, even in a script. Only append (`fs.appendFileSync`-equivalent, or
   the `tools/emit/emit_*.py` helpers). This is a kernel hard rule, not a
   style preference.
9. Match tests to what's already there: `pytest`, repo-root `conftest.py`
   (Orchestrator) or a `uv`-managed venv with its own test suite
   (`seedbox-mcp`) — read the existing test file's imports/fixtures before
   writing a new one in an unfamiliar style.
10. Packaging is not uniform across repos: `seedbox-mcp` is `uv`-managed
    (`uv.lock` is the real pin); the Orchestrator gateway uses a plain
    `python3.12 -m venv .venv && pip install -r requirements-gateway.txt`.
    Check which one a repo actually uses before running the wrong tool.

## Verification checklist

- [ ] `ruff check` / `ruff format` clean.
- [ ] No bare `except: pass` anywhere in the diff.
- [ ] Any new Starlette app/route uses `lifespan=`, not `on_startup=`.
- [ ] Tests pass with the repo's actual test runner, not an assumed one.
- [ ] Any `data/*.jsonl` touch is append-only.
- [ ] Never mark confirmed on a hunch; name the check that was actually run.

## Links

- **API/framework knowledge base** (how asyncio/Starlette/Python actually
  work — `TaskGroup` vs `gather`, `ExceptionGroup`, timeouts, the 0.x→1.x
  Starlette migration, dataclasses/typing/context-manager mechanics):
  `~/dev/knowledge-base/python/SKILL.md`. Load this alongside the rules
  above — this skill is house style/architecture; the knowledge base is
  API/language mechanics.

## Context Load Policy

- Default load: this file only.
- For implementation, review, or anything touching asyncio/Starlette
  specifically: this file + the knowledge base's relevant doc
  (`02-asyncio-patterns.md` or `03-starlette.md`).
- Never assume a Starlette/asyncio API from memory when the knowledge base
  or current docs are one read away — the version-jump risk is real here.
