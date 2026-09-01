---
applyTo: "**"
description: Use when the user wants to clean up, audit, or sync a repo's branches across the board — not just one branch. Triggers on phrases like "cleanup branches", "delete merged branches", "branch audit", "fast-forward staging and my long-lived branch", "prune", "I have N branches, clean them up", "what's the state of the branches", or any request to sweep stale/merged/gone refs and bring long-lived branches up to date. Also use when a repo squash-merges its PRs and `git branch --merged` or a `[gone]`-only sweep reports nothing to delete despite many shipped branches. Do NOT use for: ending the life of ONE branch (use finishing-a-development-branch), or any push-force operation.
---

# Branch hygiene

A working repo accumulates branches: merged ones that never got deleted, ones whose remote is gone, stale experiments, long-lived integration branches that drift behind `main`. This skill sweeps all of them in one pass, with the user approving each category before anything is deleted or fast-forwarded.

## When to use

Fire this skill when the user asks for a **repo-wide** branch operation. Typical openers:

- "cleanup all the feature branches"
- "delete the merged branches"
- "fast-forward staging and my long-lived branch from main"
- "I've got 81 branches, audit them"
- "what's the state of all the branches"
- "prune the dead refs"

**Do NOT fire** when:

- The user is finishing ONE branch's lifecycle (merge/PR/discard) → use `finishing-a-development-branch`.
- The user wants to force-push, rewrite history, or do anything destructive to a remote branch → stop and confirm explicitly; this skill does not own that.
- The user is on a non-git directory → say so and exit.

## The sweep — six steps

Use `TodoWrite` to track. Each step is mandatory; don't skip categorization to save time — silent surprises here cost work.

### Step 1 — Sync with the remote

```bash
git fetch --all --prune
```

The `--prune` removes references to remote branches that no longer exist, which is what makes the gone-tracking category resolvable in Step 3.

**For shared repos** (where more than one person commits — any team or client project), also pull the current branch from origin first so the local view of "what's merged" reflects what teammates have shipped:

```bash
git pull --ff-only
```

If `--ff-only` fails (the local branch has diverged), STOP and report — don't try to resolve a merge conflict inside this skill.

### Step 2 — Inventory

Run `scripts/collect-branch-facts.sh` (or `--json` for parseable output) to capture default branch, locals with upstream-track + committerdate + full tip SHA, remotes, worktrees, and both open and merged `gh pr list` JSON in one shot. The script tolerates `gh` failures (no GitHub remote / `gh` not on PATH) — PR data is omitted, the rest still works.

### Step 3 — Categorize every local branch

Run `scripts/classify-branches.sh` (or `--json`). It applies the table below so you don't hand-roll the logic. `--stale-days N` moves the staleness threshold; `--protect a,b` adds to the protected list.

**`git branch --merged` is not sufficient on its own.** It only knows ancestry. A squash merge rewrites the commits, so the branch tip is never an ancestor of the default branch and the branch looks unmerged forever. On a squash-merge repo this makes ancestry report near-zero deletable branches while most have in fact shipped — measured on one real repo, `--merged` found 0 of 6. The classifier checks merged PRs as well, which is why it needs `merged_prs` from Step 2.

Labels, first match wins:

| Label | Definition | Default action |
|---|---|---|
| **Protected** | Branch is in the protected list (see below). | Never delete. May fast-forward if behind upstream. |
| **Merged** | Tip is an ancestor of the remote default branch. | Delete locally and on remote. |
| **OpenPR** | Has an open PR per `gh pr list`. | Leave alone. Surface mergeable state in the report. |
| **SquashMerged** | A merged PR has this branch as its head **and** the PR's `headRefOid` equals the local tip SHA. | Delete locally. Remote is usually already gone. |
| **MovedSincePR** | A merged PR has this branch as its head but the local tip **differs**. | Never auto-delete. Present to the user — there are local commits after the merge, or the name was reused. |
| **GoneNoProof** | `upstream:track` is `[gone]`, and nothing above matched. | Never auto-delete. Present to the user (see below). |
| **StaleUnmerged** | No merge evidence, no open PR, last commit > 30 days ago. | Present per-branch to user. |
| **Active** | Anything else (recent unmerged work, possibly in flight). | Leave alone, surface in report. |

**Why `headRefOid` and not just the branch name:** a merged PR proves the *name* shipped. Only a tip-SHA match proves *this local branch* is what shipped. Without the SHA guard, a branch carrying unpushed commits on top of a merged PR looks identical to one that shipped cleanly. On a real 28-repo sweep this distinction covered 12 branches that a name-only match would have deleted.

**Why merge evidence is checked before `[gone]`:** a deleted remote branch is not proof of a merge. Remotes get deleted with the work unmerged. Treating `[gone]` as "safe to delete" — which is what a `[gone]`-only sweep does — silently discards those. Check for a merge first; `[gone]` with no merge evidence is a question for the user, not an action.

**Gotcha:** `git branch -v | grep '\[gone\]'` never matches. `-v` prints SHA and subject only; tracking state needs `-vv` or `--format='%(upstream:track)'`. A sweep built on the `-v` form silently finds nothing and reports a clean repo.

**Protected list (never auto-delete):**

```
main, master, develop, dev, staging, production, prod, release, stable
```

Add any long-lived personal or integration branch the user relies on (a personal working branch, a team integration branch) to this list before sweeping — ask if you're unsure which branches are long-lived.

If a Protected branch is behind its upstream (e.g., `staging` is 7 commits behind `origin/staging`, or a long-lived integration branch is 12 commits behind `origin/main`), add it to a "fast-forward candidates" list to confirm in Step 4.

**Default branch detection** is included in `scripts/collect-branch-facts.sh` (the `default branch` section). It tries `git symbolic-ref refs/remotes/origin/HEAD`, then falls back to `main`, then `master`.

### Step 4 — Present the plan and get approval

Use `AskUserQuestion` **once per non-empty category**, with the count + sample. Don't ask 50 separate questions.

For **Merged**, **SquashMerged**, and **fast-forward candidates**, batch into a single yes/no per category:

```
SquashMerged (N branches): fix/old-bug (PR #33), chore/thing (PR #7), ...
- Delete all locally?  [Yes / Show list first / Skip]
```

For **MovedSincePR** and **GoneNoProof**, never batch a delete — these are the two labels that can hide unmerged work. List each with its reason and ask per branch:

```
MovedSincePR (N branches — PR merged, but local tip has moved since):
- feat/thing   (PR #41 merged 2026-06-13, 2 local commits since)
Action?  [Show the extra commits / Delete anyway / Keep]

GoneNoProof (N branches — remote deleted, no merged PR found):
- old/experiment   (remote gone, no PR under this name)
Action?  [Show log / Delete / Keep]
```

A `GoneNoProof` branch is often just a PR older than the 200-PR fetch limit, but it can equally be a branch whose remote was deleted without merging. Offer the log before the delete.

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

1. **Delete Merged local + remote**:
   ```bash
   git branch -d <name>           # safe delete
   git push origin --delete <name>
   ```
   If `git branch -d` refuses on a branch labelled **Merged**, STOP and surface it — the ancestry claim and Git disagree, and that needs a human.

2. **Delete SquashMerged local-only**:
   ```bash
   git branch -D <name>           # -d WILL refuse here; see below
   ```
   `git branch -d` refuses every SquashMerged branch, because its commits genuinely are not ancestors of the default branch. That refusal is expected and is **not** a danger signal. The evidence that the work shipped is the merged PR plus the `headRefOid` match, verified in Step 3 — not Git's ancestry check.

   `-D` is only ever correct for the SquashMerged label. Never reach for it because `-d` refused on some other category; that refusal means what it says.

   The remote branch is usually already deleted (that's why these often also show `[gone]`). Only run `git push origin --delete` if the remote ref still exists.

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

Deleted: N merged (local + remote), N squash-merged (local)
Fast-forwarded: <list of protected branches and their commit delta>
Worktrees removed: <list>

Still around:
  Active: N branches with recent unmerged work
  Open PRs: N (mergeable: <count>, conflicts: <count>, draft: <count>)
  Stale (kept per your choice): N
  Needs your call: N MovedSincePR, N GoneNoProof

Stale PR list (no commits in 14+ days):
  - #123 feat/foo (28 days, mergeable) — <author>
  - #145 fix/bar  (19 days, CONFLICTING) — <teammate>
```

Keep it under 20 lines. If counts are zero in a section, omit the section.

## Safety rules

These are non-negotiable. They exist because each one represents a real way to lose work or break a teammate's workflow.

- **Never `push --force` or `push --force-with-lease`** from this skill. If the user wants to overwrite a remote ref, they'll ask explicitly outside this flow.
- **`git branch -D` is allowed for exactly one label: SquashMerged**, where `-d` refuses by design and the merged PR + `headRefOid` match is the real evidence. Everywhere else `-d` is the default, and a refusal means the branch isn't merged — surface it, don't escalate.
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

- **Supersedes a `[gone]`-only sweep** such as `commit-commands:clean_gone`. Two reasons: `[gone]` alone is not merge evidence (see Step 3), and the common `git branch -v | grep '\[gone\]'` form never matches anything because `-v` omits tracking state. Prefer this skill.
- **Pairs with `finishing-a-development-branch`** — that skill is per-branch (after a feature ships). This skill is the periodic janitorial pass for everything that built up between those.
- **Pairs with `project-onboarding`** — onboarding may surface a stale branch count; this skill is the natural follow-up.
- **Pairs with `using-git-worktrees`** — orphaned worktrees from prior worktree-based work are exactly what Step 5 cleans up.
