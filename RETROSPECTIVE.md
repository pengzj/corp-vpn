# RETROSPECTIVE.md — ops_vpn

## AI Tools Used

- **Claude (Anthropic) via Cowork mode** — primary tool for the entire project
- **Claude Agent SDK** — sub-agents for multi-file operations and codebase exploration
- **Claude in Chrome** — browser automation for accessing internal GitLab

No other AI tools were used. The entire project was built in a single Claude Cowork session.

---

## Development Workflow

The workflow was fully conversational and iterative:

1. **Requirements conversation** — Described the project idea; Claude asked clarifying questions about protocols, UI approach, and distribution model before writing a single line of code.

2. **Design review** — Claude presented a full architecture diagram, file layout, and API design before implementation. User approved or adjusted before proceeding. This was enforced by the project instruction: *"before you implement it, show me what you will do and your design."*

3. **Implementation** — Claude wrote all source files using file tools. Multi-file changes were batched via sub-agents.

4. **Build-fix loop** — User ran `zig build`, pasted compiler errors, Claude fixed them. Repeated ~15 times for the Zig 0.16 migration.

5. **Runtime testing** — User ran the binary, tested with `curl`, Chrome, and gost. Errors were pasted and Claude diagnosed them conversationally.

6. **Refinement** — Directory restructuring, README improvements, test coverage, build scripts, release packaging — all through continued conversation.

---

## What Worked Well

### Design-first approach
Requiring Claude to show the design before coding prevented wasted implementation. The upfront architecture conversation surfaced key questions (which protocols? what auth types? web UI or native?) that shaped the final product significantly.

### Zig error messages as specification
Zig's compiler errors are extremely precise. Pasting errors verbatim gave Claude enough information to fix issues accurately — including the complex `std.Io` API migration where the error messages showed the exact expected types.

### Iterative error fixing
The build-fix loop worked better than expected. Even with ~15 iterations for Zig 0.16 migration, each iteration moved meaningfully forward. Claude correctly identified patterns across errors (e.g., "all reader methods need `.interface.`") and fixed multiple occurrences at once.

### Real-time log debugging
Adding structured connection logs (`info: SOCKS5 httpbin.org:443 → [socks5] 127.0.0.1:1080`) gave immediate visibility into whether traffic was routing correctly through the proxy chain.

### Single-binary distribution
`@embedFile` for frontend assets worked cleanly. The mental model of "frontend build outputs to `backend/src/www/`, then zig bakes it in" was straightforward and the result is genuinely useful for distribution.

---

## What Did Not Work Well

### Zig 0.16 knowledge gap
Claude's training data predates Zig 0.16's release. The `std.Io` migration required ~15 build-fix iterations because Claude had to infer the new API from compiler errors rather than knowing it upfront. Each error was a small discovery. A compiled reference document for Zig 0.16 changes would have reduced this significantly.

### File path confusion
Early in the session, files were written to a nested `ops_vpn/ops_vpn/` directory because the workspace path was misidentified. This required manual cleanup and re-creation of files. Lesson: verify the workspace root explicitly at the start of a session.

### Cannot run code in the sandbox
Claude's bash sandbox is Linux-only and doesn't have Zig or the user's npm registry. Claude could not validate builds or run tests — only the user could. This means bugs weren't caught until the user ran `zig build`. A local dev loop with the user running commands and pasting results worked, but added latency.

### HTTP CONNECT buffer aliasing bug
Took significant effort to diagnose without being able to run the binary. Claude had to reason about the buffer lifecycle purely from the symptom ("Proxy CONNECT aborted" + no gost log entries). The fix was correct but took longer than if Claude had a debugger or could add print statements and run directly.

---

## Surprises and Discoveries

**Zig 0.16 is a very different language from 0.13** — the `std.Io` migration touched nearly every file. Networking, file I/O, mutexes, random numbers, ArrayList initialization, and the `main()` signature all changed. This was not anticipated.

**`ArrayList` no longer owns its allocator** in Zig 0.16. Every `append`, `deinit` call now requires passing the allocator explicitly. This was a pleasant design improvement but required many mechanical fixes.

**Chrome ignores `--proxy-server` if already running** — launching Chrome with a proxy flag only works if Chrome is fully closed first. Using `--user-data-dir` creates an isolated profile that bypasses this. A small thing but confusing without knowing it.

**The HTTP CONNECT buffer aliasing bug** was subtle and non-obvious. Passing `rbuf[0..]` to `readSliceShort` when `rbuf` is also the reader's internal buffer caused the read to return 0 immediately (buffer aliasing self-defeat). SOCKS5 worked because it doesn't have the same post-parse pipe setup.

**GitLab Developer role cannot create a default branch** — even for a project you created yourself if the group has a pre-receive hook policy. This was blocking for 30+ minutes.

---

## Estimated Percentage of AI-Generated Code

**~95%** of all code was generated by Claude. The remaining ~5% was user-directed adjustments (e.g., changing directory names, clarifying requirements). No code was written manually outside the AI session.

This includes:
- All Zig source files (backend)
- All TypeScript/React source files (frontend)
- All build scripts (build.sh, build.bat, test.sh, test.bat)
- All configuration files (vite.config.ts, tsconfig.json, build.zig, etc.)
- All documentation (README.md, SPEC.md, ARCHITECTURE.md, this file)

---

## Time Spent

| Phase | Estimated Time |
|-------|---------------|
| Requirements + design | ~30 min |
| Initial implementation | ~45 min |
| Zig 0.16 migration (15 iterations) | ~60 min |
| Runtime debugging (proxy bugs) | ~30 min |
| Directory restructuring + git | ~30 min |
| Tests + documentation | ~30 min |
| **Total** | **~3.5 hours** |

---

## What I Would Do Differently Next Time

1. **Verify Zig version support upfront.** Ask Claude explicitly: "What Zig version do you have reliable training data for?" and match the implementation to that version, or use a version-specific migration guide.

2. **Confirm workspace root at session start.** Run `pwd` and verify the path before writing any files to avoid directory nesting issues.

3. **Use a test harness from day one.** Adding tests after the fact is harder. Starting with at least stub tests for pure functions provides a safety net during the build-fix loop.

4. **Add logging earlier.** The connection logs (`SOCKS5 host:port → endpoint`) should have been there from the start — they would have cut the HTTP CONNECT debugging time in half.

5. **Keep the design document as a living file.** Claude presented the design conversationally, but not as a committed file. A `DESIGN.md` that gets updated as decisions change would be more useful than conversation history.

---

## Key Lessons Learned

**1. Design-before-code is worth the time investment.**
The 30 minutes spent on design clarification prevented multiple wrong-direction implementations. The instruction "show me your design first" should be standard for any non-trivial AI-assisted project.

**2. Compiler errors are AI's best debugging input.**
Pasting the exact compiler output (not paraphrasing it) gave Claude everything needed to fix issues. This is more reliable than describing the error in natural language.

**3. AI-native development has a different velocity profile.**
The first 80% of the project moved very fast. The last 20% (Zig 0.16 migration, runtime bugs, git/permissions issues) took more time than expected. This is typical — AI accelerates greenfield work but debugging still requires deep iteration.

**4. Single binary distribution is achievable with Zig + @embedFile.**
Embedding the frontend at compile time is elegant and the result is genuinely useful. This pattern should be considered for any ops tooling that needs a UI without deployment overhead.

**5. AI-generated code at 95% is practical for a complete project.**
The code quality was sufficient to build, run, pass tests, and distribute. The main limitation was AI knowledge gaps on very recent library versions (Zig 0.16), not code quality.
