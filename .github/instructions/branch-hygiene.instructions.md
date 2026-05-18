---
applyTo: "**"
description: Use when the user wants to clean up, audit, or sync a repo's branches across the board — not just one branch. Triggers on phrases like "cleanup branches", "delete merged branches", "branch audit", "fast-forward justins-branch and staging", "prune", "I have N branches, clean them up", "what's the state of the branches", or any request to sweep stale/merged/gone refs and bring long-lived branches up to date. Categorizes every local branch (merged, gone-tracking, stale-unmerged, long-lived, active), presents a plan, executes after approval, cleans associated worktrees, and surfaces stale open PRs. Do NOT use for: ending the life of ONE branch (use finishing-a-development-branch), deleting only [gone]-marked branches (commit-commands:clean_gone already does that one cleanly), or any push-force operation.
---

# Branch hygiene

A working repo accumulates branches: merged ones that never got deleted, ones whose remote is gone, stale experiments, long-lived integration branches that drift behind `main`. This skill sweeps all of them in one pass, with the user approving each category before anything is deleted or fast-forwarded.

## When to use

Fire this skill when the user asks for a **repo-wide** branch operation. Typical openers:

- "cleanup all the feature branches"
- "delete the merged branches"
- "fast-forward justins-branch and staging from main"
- "I've got 81 branches, audit them"
- "what's the state of all the branches"
- "prune the dead refs"

**Do NOT fire** when:

- The user is finishing ONE branch's lifecycle (merge/PR/discard) → use `finishing-a-development-branch`.
- The user only wants to delete `[gone]`-tracking branches → `commit-commands:clean_gone` is already scoped to that and is faster.
- The user wants to force-push, rewrite history, or do anything destructive to a remote branch → stop and confirm explicitly; this skill does not own that.
- The user is on a non-git directory → say so and exit.

## The sweep — six steps

Use `TodoWrite` to track. Each step is mandatory; don't skip categorization to save time — silent surprises here cost work.

### Step 1 — Sync with the remote

```bash
git fetch --all --prune
```

The `--prune` removes references to remote branches that no longer exist, which is what makes the gone-tracking category resolvable in Step 3.

**For shared repos** (where someone other than Justin commits — `TheCTIAgent` with `chrisurline`, any client project), also pull the current branch from origin first so the local view of "what's merged" reflects what teammates have shipped:

```bash
git pull --ff-only
```

If `--ff-only` fails (the local branch has diverged), STOP and report — don't try to resolve a merge conflict inside this skill.

### Step 2 — Inventory

Run `scripts/collect-branch-facts.sh` (or `--json` for parseable output) to capture default branch, locals with upstream-track + committerdate, remotes, worktrees, and `gh pr list` JSON in one shot. The script tolerates `gh` failures (no GitHub remote / `gh` not on PATH) — PR data is omitted, the rest still works.

### Step 3 — Categorize every local branch

Apply these labels in order; first match wins.

| Label | Definition | Default action |
|---|---|---|
| **Protected** | Branch is in the protected list (see below). | Never delete. May fast-forward if behind upstream. |
| **Gone** | `upstream:track` shows `[gone]`. | Delete locally. (Same as `commit-commands:clean_gone`.) |
| **Merged** | `git branch --merged main` (or default branch) includes it AND not Protected AND no open PR points to it. | Delete locally and on remote. |
| **OpenPR** | Has an open PR per `gh pr list`. | Leave alone. Surface mergeable state in the report. |
| **StaleUnmerged** | Not merged, no open PR, last commit > 30 days ago. | Present per-branch to user. |
| **Active** | Anything else (recent unmerged work, possibly in flight). | Leave alone, surface in report. |

**Protected list (never auto-delete):**

```
main, master, develop, dev, staging, production, prod,
justins-branch, justins-desktop, release, stable
```

If a Protected branch is behind its upstream (e.g., `staging` is 7 commits behind `origin/staging`, or `justins-branch` is 12 commits behind `origin/main`), add it to a "fast-forward candidates" list to confirm in Step 4.

**Default branch detection** is included in `scripts/collect-branch-facts.sh` (the `default branch` section). It tries `git symbolic-ref refs/remotes/origin/HEAD`, then falls back to `main`, then `master`.

### Step 4 — Present the plan and get approval

Use `AskUserQuestion` **once per non-empty category**, with the count + sample. Don't ask 50 separate questions.

For **Gone**, **Merged**, and **fast-forward candidates**, batch into a single yes/no per category:

```
Gone-tracking (N branches): feat/old-thing, fix/old-bug, ...
- Delete all locally?  [Yes / Show list first / Skip]
```

For **StaleUnmerged**, list the branches with their age and last commit subject; ask:

```
Stale-unmerged (N branches, no commits in 30+ days, not merged, no open PR):
- feat/abandoned-experiment      (87 days, "wip: trying X")
- fix/half-done-thing            (54 days, "first pass")
Action?  [Delete all / Keep all / Decide per branch / Show diffs first]
```

If the user picks "Decide per branch", loop with one `AskUserQuestion` per branch (label "Delete / Keep / Show diff"). Don't loop silently — show progress.

For **OpenPR**, do not ask — just surface in the final report.

### Step 5 — Execute approved actions

Run in this order. Stop on any error; don't auto-recover.

1. **Delete merged local + remote**:
   ```bash
   git branch -d <name>           # safe delete; -D only on explicit user override
   git push origin --delete <name>
   ```
   If `git branch -d` refuses (Git thinks it's unmerged but we judged it merged from PR state), STOP and surface the branch back to the user — don't escalate to `-D` on your own.

2. **Delete gone local-only**:
   ```bash
   git branch -d <name>
   ```

3. **Fast-forward protected branches** (only the ones the user confirmed):
   ```bash
   git checkout <protected>
   git merge --ff-only <upstream>
   git checkout <original-branch>
   ```
   If `--ff-only` fails, STOP and report. Never `--no-ff`, never reset, never force.

4. **Worktree cleanup**: for any deleted branch that had a worktree, remove it:
   ```bash
   git worktree remove <path>
   ```
   If the worktree has uncommitted changes, `git worktree remove` will fail — surface it to the user and let them decide whether to `git worktree remove --force` (don't do it for them).

5. **Skip stale PRs**: this skill does not close PRs. Surface them with their last-updated date and mergeable state in the final report.

### Step 6 — Final report

Print a compact summary:

```
## Branch hygiene report — <repo-name>

Deleted: N gone, N merged (local + remote)
Fast-forwarded: <list of protected branches and their commit delta>
Worktrees removed: <list>

Still around:
  Active: N branches with recent unmerged work
  Open PRs: N (mergeable: <count>, conflicts: <count>, draft: <count>)
  Stale (kept per your choice): N

Stale PR list (no commits in 14+ days):
  - #123 feat/foo (28 days, mergeable) — Justin
  - #145 fix/bar  (19 days, CONFLICTING) — chrisurline
```

Keep it under 20 lines. If counts are zero in a section, omit the section.

## Safety rules

These are non-negotiable. They exist because each one represents a real way to lose work or break a teammate's workflow.

- **Never `push --force` or `push --force-with-lease`** from this skill. If the user wants to overwrite a remote ref, they'll ask explicitly outside this flow.
- **Never `git branch -D`** (force delete) unless the user explicitly overrides for a specific branch. `-d` is the default; if Git refuses, that's a signal the branch isn't actually merged.
- **Never delete a Protected branch**, even if it looks "merged" — `staging` merged into `main` doesn't mean staging is disposable.
- **Never resolve a merge conflict inside this skill.** If `--ff-only` or `pull --ff-only` fails, stop and report — the user should drive that resolution intentionally.
- **For shared repos, pull first** (Step 1). Otherwise you may delete a branch the partner just merged and assumed was still around.
- **Read-only by default for PRs** — this skill surfaces PR state but does not close, merge, or comment.

## Edge cases

- **Detached HEAD or rebase in progress** — abort immediately and tell the user to finish the in-flight operation first.
- **No upstream tracking on any local branch** — fall back to "merged into default branch" using `git branch --merged` only; mark everything else as Active.
- **No `gh` / no GitHub remote** — skip PR categorization. OpenPR becomes empty; StaleUnmerged stays as-is.
- **Worktree on a branch the user wants to delete** — confirm worktree removal before branch deletion (deleting the branch first leaves an orphaned worktree).
- **The current branch is in the delete list** — never delete the current branch. Switch to default branch first, then delete, then optionally switch back to wherever the user wants.
- **Many branches (50+)** — render the StaleUnmerged list as a truncated sample (10 oldest) with total count, not the full list, in the `AskUserQuestion` body — `AskUserQuestion` bodies should stay readable.

## Integration

- **Complements `commit-commands:clean_gone`** — that skill handles the Gone category only and is faster for that single case. This skill is the right tool when the user wants the full sweep.
- **Pairs with `finishing-a-development-branch`** — that skill is per-branch (after a feature ships). This skill is the periodic janitorial pass for everything that built up between those.
- **Pairs with `project-onboarding`** — onboarding may surface a stale branch count; this skill is the natural follow-up.
- **Pairs with `using-git-worktrees`** — orphaned worktrees from prior worktree-based work are exactly what Step 5 cleans up.
