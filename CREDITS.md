# Credits & attribution

`claude-projects` builds on the work of others. This file records those sources and reproduces the license notices that require it.

## mattpocock/skills (MIT)

The core idea-to-ship skill loop and several supporting skills are **adapted from** the engineering skills in [mattpocock/skills](https://github.com/mattpocock/skills/tree/main/skills/engineering):

- `grill-with-docs`, `to-prd`, `to-issues`, `tdd` — the original grill → PRD → issues → build loop the scaffold was first based on.
- `codebase-design`, `code-review`, `diagnosing-bugs`, `prototype`, `improve-codebase-architecture` — adopted later, as the upstream repo added them.

These skills have been **modified** to fit this scaffold's conventions — Jira/local routing, HITL/AFK slice taxonomy, observability gating, the `/next` orchestrator and per-task acceptance gate, and per-agent contracts — and in places restructured (e.g. the design vocabulary was consolidated into `codebase-design`, and testing "seams" now thread through `to-prd` → `to-issues` → `tdd`). Any errors introduced by that adaptation are ours, not the upstream author's.

The upstream work is MIT-licensed:

```
MIT License

Copyright (c) 2026 Matt Pocock

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Living-status system (concept)

The `STATUS.md` / `journal.yaml` living-status approach — an LLM-optimized current-state document that eliminates per-session re-orientation cost — is inspired by [Give Your AI Unlimited, Updated Context](https://towardsdatascience.com/give-your-ai-unlimited-updated-context/).
