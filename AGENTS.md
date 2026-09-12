# hydra-infra — agent guide

> **Read first:** this repo is a **legacy path being superseded by
> `cluster-api-provider-hydra`.** Default to *not* extending it. Never restore an automatic apply.
>
> PR titles are `[PET-xx] Title`. Never put AI attribution in commits or PR bodies, but **do**
> prefix every PR comment you write with `**<Agent> (<Model>)**`. See
> [Working agreements](#working-agreements).

## What this repo is

Terraform plus a GitHub Actions pipeline that declaratively manages **libvirt/KVM worker VMs** and
joins them to the hand-built home Kubernetes control plane with `kubeadm join`.

```text
main.tf / variables.tf / outputs.tf / versions.tf   # libvirt VMs from a `workers` map
terraform.tfvars(.example)                          # the fleet definition
templates/user-data.tpl, meta-data.tpl              # cloud-init
scripts/sync-nodes.sh                               # drain removed → apply → join new → label
.github/workflows/manage-nodes.yml                  # plan on PR, apply only by hand
Makefile                                            # init / plan / apply / destroy / fmt / validate
```

Editing the `workers` map adds, removes, or resizes a worker. A resize **recreates** the VM
(drain → destroy → create → join).

## Status — read this before planning any work here

**Cluster API is taking this repo's job over.** Machine lifecycle now belongs to
`cluster-api-provider-hydra`, which provisions VMs from `HydraMachine` objects with no SSH
orchestration at all. Two systems reconciling the same worker fleet is exactly the split-brain
**ADR-002 (single-writer worker lifecycle)** forbids.

**Terraform has never actually run against this infrastructure.** There is no state file anywhere,
no `terraform` binary on the hypervisor, and no backend block. Nothing on the host was created by
this code. Treat the config as unproven — it has never been executed, so "it worked before" is not
available as evidence for anything here.

Practical consequence: prefer landing a capability in the provider over adding it here. Changes to
this repo should be confined to correcting what is wrong, documenting it, or retiring it.

## Never restore the automatic apply

`manage-nodes.yml` deliberately has **no `push` trigger**. It used to run `sync-nodes.sh apply` —
which creates, joins, and destroys worker VMs — on every push to `main` touching `main.tf`,
`variables.tf`, `terraform.tfvars`, or `templates/`. That is an unattended mutation of machine
lifecycle (PET-29, ADR-002).

What remains, and must remain:

- `pull_request` → **plan only**
- `workflow_dispatch` → `plan` / `apply` / `destroy`, chosen **by a human**

Do not add a `push` trigger, an auto-approve, or an `apply` on any automatic event, however
convenient. The comment block at the top of that workflow explains why — keep it.

Because Terraform manages local libvirt VMs, the workflow runs on a **self-hosted runner on the
hypervisor host**, with real SSH keys and a real kubeconfig in its environment.

## Known-wrong values — fix these, do not copy them

**The control-plane address in this repo is stale, and the stale value is now dangerous.**

Both `.github/workflows/manage-nodes.yml` (`CONTROL_PLANE_IP`) and `terraform.tfvars.example`
(`control_plane_ip`) say `192.168.15.10`.

- The home control plane is actually at **`192.168.16.10`**.
- `192.168.15.10` is now the **kube-vip VIP of the `hydra-wl0` workload cluster**, held by its
  control-plane nodes.

So a `sync-nodes.sh apply` with the checked-in defaults would try to join workers to a cluster that
is not the one intended. Verify the address against the live cluster before any apply, and never
treat these files as the source of truth for it.

Also note the storage pool: this repo's VMs live in the libvirt pool `/var/lib/libvirt/k8s-workers`,
while the hand-built `wk1`/`wk2`/`wk3` VMs on the host sit at `/home/yibofu/vms/<name>` and were
**not** created by this code.

## Local workflow

```bash
make fmt        # terraform fmt -recursive
make validate   # terraform init + validate  (safe, no cloud/host state)
make plan       # ./scripts/sync-nodes.sh plan
```

`make apply` and `make destroy` mutate real VMs and real cluster membership. **Do not run either
without explicit human instruction for that specific run**, and never as a step in a larger task.
`terraform.tfvars` is not committed; start from `terraform.tfvars.example`.

## Project context

**Hydra** is an open-source on-prem Kubernetes lifecycle platform built on
[Cluster API](https://cluster-api.sigs.k8s.io/), with libvirt/KVM as the first infrastructure
provider and workload-driven node autoscaling via Cluster Autoscaler. It lives on the
[`Petatron`](https://github.com/Petatron) GitHub org across five repositories:

| Repo | Role |
|---|---|
| [`hydra`](https://github.com/Petatron/hydra) | Umbrella / namesake repo. Effectively empty today. |
| [`cluster-api-provider-hydra`](https://github.com/Petatron/cluster-api-provider-hydra) | The Cluster API **infrastructure provider**. Go, kubebuilder. This is where product code lives. |
| [`hydra-bootstrap`](https://github.com/Petatron/hydra-bootstrap) | **Documentation only.** Runbooks for standing up hosts, the CAPI management cluster, and workload clusters. |
| [`hydra-gitops`](https://github.com/Petatron/hydra-gitops) | Argo CD configuration. **A merge to `main` changes live clusters.** |
| [`hydra-infra`](https://github.com/Petatron/hydra-infra) | Terraform for the pre-Hydra, hand-built worker VMs. Legacy path, being superseded by the provider. |

**Where truth lives — three systems, deliberately separated:**

- **Notion** (PETATRON teamspace → *Project Hydra*) — architecture, ADRs, design docs, runbooks,
  worklogs, validation evidence. This is the source of truth for **engineering knowledge**.
- **Linear** (workspace `petatron`, team key `PET`) — issues `PET-5`..`PET-46+`. Source of truth
  for **delivery status**. `PET-1`..`PET-4` are onboarding stubs, not real work.
- **GitHub** — code, PRs, CI. Not a place to record decisions.

Durable findings go in Notion, **not** Linear comments. Every Linear issue must have a matching
Notion page, linked both ways.

## Working agreements

These are instructions, not suggestions.

### 1. PR titles carry the ticket; commit messages do not

```
PR title:  [PET-27] Publish template capacity for scale-from-zero
Commit:    feat: publish template capacity for scale-from-zero
```

The ticket goes in **square brackets at the front** of the PR title. Commit messages stay in
conventional style (`feat:` / `fix:` / `docs:` / `chore:` / `ci:`) with **no** ticket prefix.
`feat: … (PET-27)` is the wrong shape for a PR title — do not copy it.

**Every PR needs a ticket. If there isn't one, stop and ask.** When the work has no Linear (or Jira)
issue, do not open the PR on your own judgment — ask whether to create a ticket first or to open
this one without a prefix, and let the user decide. **Never invent or guess a number:** a wrong
`[PET-xx]` silently attaches the PR to somebody else's work and corrupts the tracking both systems
exist to provide.

### 2. Never put AI attribution in git history

Commit messages, commit trailers, PR titles, and PR bodies must **never** mention Claude, Codex,
Cursor, Copilot, or any AI assistant. Git history records what changed and why, not which tool
typed it. Never emit:

```
Co-Authored-By: Claude <noreply@anthropic.com>
Co-authored-by: Cursor <cursoragent@cursor.com>
🤖 Generated with [Claude Code](https://claude.com/claude-code)
Made with [Cursor](https://cursor.com)
```

Nor phrases like "AI-assisted", "generated by AI", or a model name anywhere in a commit message or
PR description. Write them as the human author would.

**Some tools inject attribution after the fact — always verify.** Writing a clean message is not
enough:

```bash
ATTRIB='^Co-authored-by:|Generated with|Made with \[|AI-assisted|generated by AI|Claude Code|claude\.ai|cursor\.com|noreply@anthropic\.com'
git cat-file -p HEAD | grep -iE "$ATTRIB" && echo DIRTY || echo clean
gh pr view <n> --json body --jq '.body' | grep -iE "$ATTRIB" && echo DIRTY || echo clean
```

Match those patterns, **not** the bare words `claude` or `cursor` — `CLAUDE.md` is a legitimate
filename and a loose grep reports every commit that mentions it as dirty.

`git commit --amend` re-injects the trailer and cannot fix this; rebuild the commit object with
`git commit-tree` instead. If the bad commit was already pushed, **ask before force-pushing**, then
use `--force-with-lease=<branch>:<old-sha>`.

### 3. DO attribute yourself in PR comments

This is the exception to rule 2, and it is required. Multiple agents (and the human maintainer)
review the same PRs; the comment thread has to say who is speaking.

**Prefix every GitHub PR comment, review comment, review summary, and reply you write with your
agent name and model in bold:**

```
**Claude (Opus 5)** — the informer starts on the first cached Get, so declining
the Watch bought nothing here. Read the Secret through mgr.GetAPIReader().
```

```
**Codex (GPT-5)** — agreed, but the RBAC verb also needs narrowing to `get`.
```

Format is `**<Agent> (<Model>)**` followed by an em dash. Use the name a reader would recognise —
`Claude (Opus 5)`, `Codex (GPT-5)`, `Cursor (Composer)`. If you genuinely do not know your model
identity, use `**<Agent>**` alone rather than guessing.

This applies to **comments only** — the conversation surface. It does **not** apply to the PR body,
the PR title, or commit messages, which stay clean under rule 2.

GitHub still attributes the comment to whichever account is authenticated. The prefix says which
agent wrote the text; do **not** claim the displayed GitHub author has changed.

### 4. Keep the record current continuously, not at the end

Whenever a ticket, a test, or a meaningful piece of progress completes, update **both**:

- **Linear** — status, plus a comment stating what was proven and, just as importantly, what was
  **not**.
- **Notion** — the linked page's worklog section and its Doc Status property.

Write down what was *learned* — especially anything that turned out different from what was
assumed — not just what shipped. The goal is that a future session resumes with no lost context.

Every operation performed against real infrastructure gets recorded as it happens, in both.

### 5. Read PR review comments via GraphQL, never REST

The REST endpoint `/pulls/N/comments` **silently omits threads** — it missed all eight of the
maintainer's review comments on one PR. Always use `reviewThreads`:

```bash
gh api graphql -f query='{repository(owner:"Petatron",name:"<repo>"){pullRequest(number:N){
  reviewThreads(last:80){nodes{isResolved path line
    comments(first:1){nodes{author{login} createdAt body}}}}}}}'
```

Filter by `createdAt` to find new threads. Do not slice by index against the REST count.

### 6. Expect several review rounds, and verify every comment

Copilot reviews every PR and has found dozens of real defects — several that would only have
surfaced in production as orphaned VMs or wedged finalizers. **Expect 3–5 review rounds per PR.**

Verify each comment against the actual file before acting on it. Some have been stale test
assumptions rather than code bugs, and at least one was a linter firing on a conversion that was
genuinely required. A review comment is evidence, not a verdict.

### 7. Generic design beats lab convenience

The reference lab (an XPS 13 control plane at home, a workstation at the office, ~30 ms apart) is
one person's setup, **not a requirement Hydra should be shaped around**. Hydra must assume nothing
about that hardware, topology, or site count.

When lab convenience and generic design diverge, **generic wins** — unless the shortcut is provably
free, meaning a config value that can change later, not a code path that would have to be undone.

Architecture decisions carry a **Scope** property in Notion: `Product` binds Hydra for everyone,
`Reference lab` describes only that setup. Do not read a lab ADR as a product constraint.
