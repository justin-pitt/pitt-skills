---
name: shipping-work
description: Use when a unit of work is finished and needs to reach the remote - the user says "commit and push", "commit, push, PR", "ship it", "open a PR for this", or has just approved work that is complete and verified. Also use proactively once a task's changes are done and tests pass, instead of waiting to be asked each time. Do NOT use to merge a PR, to push to a shared long-lived branch, or when the integration path is still undecided.
license: MIT
---

# Shipping work

Take finished work from the working tree to an open pull request: preflight, stage, commit, push, PR. Then stop.

**Core principle:** the PR is the terminus. This skill never merges.

## When to use

Fire once a unit of work is complete and verified, whether or not the user asks. Typical openers: "commit and push", "commit, push, PR, merge", "ship it", "get that up", or simply approving finished work.

**Do NOT fire** when:

- The integration path hasn't been decided → use `finishing-a-development-branch`, which presents the options.
- The work isn't verified yet → run the project's checks first, per `verification-before-completion`.
- The target is a shared long-lived branch (`main`, `staging`, a team integration branch) → that's a merge decision, not a ship.
- The user asked to merge an existing PR → that's outside this skill.

## The stop rule

**This skill ends at "PR opened". It does not merge, and it does not ask whether to merge.**

Report the PR URL and stop. If the user wants it merged they will say so, and that is a separate action they own.

This holds even when the user's own phrasing included "merge":

| They said | You do |
|---|---|
| "commit, push, PR, merge" | commit, push, PR. Report the URL. Say the merge is theirs to call. |
| "ship it and get it in" | same |
| "just merge it when green" | same — say you've opened it and won't merge |

A PR that merges itself removes the last place a human sees the change before it lands. That review point is the reason the PR exists; do not skip it, and do not treat an earlier "merge" in the sentence as authorization to skip it now.

## Steps

### Step 1 — Preflight

```bash
scripts/preflight.sh
```

Six gates. Any FAIL stops the ship — fix it, don't work around it.

| Gate | Fails when | Why it matters |
|---|---|---|
| `branch` | on the default branch, or detached HEAD | commits land somewhere a PR can't be opened from |
| `worktree` | rebase / merge / cherry-pick in progress | you'd commit a half-finished operation |
| `email` | no repo-local `user.email` | on a machine hosting repos for more than one identity, the global address is wrong for at least one of them, and it only shows after the push |
| `account` | active `gh` account lacks WRITE on this repo | multi-account machines silently keep whichever account a previous task left active |
| `secrets` | staged files match `.env*`, `*.pem`, private keys, `.npmrc`, `.pypirc` | unrecoverable once pushed |

`account` asks `gh repo view --json viewerPermission` what the **active** account may do on **this** repo. That needs no table mapping accounts to owners, and it catches the common case where an earlier task switched accounts. `READ`, `TRIAGE`, `NONE`, or an unresolvable repo all mean stop: a private repo is simply invisible to an account that cannot see it, so "not found" and "wrong account" look the same and are handled the same.

Run preflight again after staging — the `secrets` gate reports SKIP until there is something staged.

### Step 2 — Stage explicitly

```bash
git add <path> <path> ...
```

**Never `git add -A`, `git add .`, or `git commit -a`.** Name every path.

Working trees routinely hold things that are not part of this change: another session's files, local scratch scripts, preimage and state dumps from a tool run, editor droppings. `-A` sweeps all of it into your commit, and in a tree shared with a concurrent session it can also commit someone else's half-finished work.

Before staging, run `git status --porcelain` and account for every line. If you cannot say which change a file belongs to, it does not go in this commit.

### Step 3 — Commit

Write the message as a human engineer would: what changed and why, with the reasoning that isn't visible in the diff.

**No AI authorship markers.** No `Co-Authored-By` naming an assistant, no "generated with" footer, no robot emoji. The diff and the message are what matter.

**Never `--no-verify`, `--no-gpg-sign`, or any other hook/signing bypass.** Hooks exist for a reason; a failing hook is a finding, not an obstacle. Fix the cause.

If the repo runs a build or codegen step whose output is committed, run it before committing so CI's drift check has nothing to catch.

### Step 4 — Push

```bash
git push -u origin <branch>
```

**Never `--force` or `--force-with-lease` from this skill.** If history needs rewriting, that is a deliberate separate act the user drives.

### Step 5 — Open the PR

```bash
gh pr create --title "<title>" --body "<body>"
```

Body covers: the problem, what changed, and how it was verified. State what you actually ran and what it produced. If part of the change is unverified, say which part — a PR body that overstates verification is worse than one that admits a gap.

Same authorship rule as the commit message.

### Step 6 — Report and stop

Give the user the PR URL and the one-line summary. If CI hasn't reported yet, say so rather than implying it passed.

Then stop. Do not merge.

## Common mistakes

| Mistake | Consequence |
|---|---|
| `git add -A` "just this once" | commits a concurrent session's files, or a state dump you meant to keep local |
| Committing before preflight | wrong-identity commit discovered after the push, when fixing it means a rewrite |
| Treating "not found" as "repo missing" | it's the wrong account; switching fixes it |
| Merging because the user said "merge" earlier in the sentence | removes the only human review point |
| `--no-verify` to get past a failing hook | ships the thing the hook was built to catch |
| Claiming CI passed before checks reported | the next person trusts it and doesn't look |

## Integration

- **`finishing-a-development-branch`** decides *whether* to merge, PR, keep, or discard. This skill executes the PR path once that's settled. If the path is genuinely open, use that skill first.
- **`verification-before-completion`** owns proving the work is done. Ship after it, not instead of it.
- **`branch-hygiene`** cleans up afterwards, once PRs have merged and local branches have gone stale.
