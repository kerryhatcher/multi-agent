---
name: setup-dev-team
description: Set up a dev team of coding agents for a project in herdr. Use when the user asks to set up, start, or spin up a dev team, product owner, manager, architect, dev team, or review team in herdr for a project.
---

# Set up a dev team in herdr

This skill opens four new tabs in the current herdr workspace and starts a team of Claude agents for one project. Run it from inside a herdr pane (`HERDR_ENV=1`).

## What it builds

| Tab | Agents | Panes |
|---|---|---|
| 1 | `<project>-product-owner` | 1 |
| 2 | `<project>-manager`, `<project>-architect` | 2 |
| 3 | `<project>-dev-lead`, `<project>-dev-1`, `-dev-2`, `-dev-3` | 4 |
| 4 | `<project>-review-lead`, `<project>-reviewer-1`, `-reviewer-2`, `-reviewer-3` | 4 |

In the dev and review tabs, the lead takes the left column and the three members stack down the right.

The product owner is the only agent the user talks to. The script focuses tab 1 when it finishes.

## Who may message whom

| Agent | May message |
|---|---|
| product owner | user, manager, architect |
| manager | product owner, architect, dev lead, review lead |
| architect | product owner, manager |
| dev lead | manager, dev-1, dev-2, dev-3 |
| developers | dev lead only |
| review lead | manager, reviewer-1, reviewer-2, reviewer-3 |
| reviewers | review lead only |

The manager is the only agent that crosses tabs to the leads. The two leads never message each other directly.

Each agent's role prompt lives in `agents/*.md`, and `scripts/messaging-protocol.md` adds the shared messaging rules and the roster. These limits are instructions to the agents, not enforced by herdr.

## Run it

1. Get the project name from the user if they have not given one. It must be lowercase letters, digits, and dashes, start with a letter, and be at most 18 characters, because agent names are capped at 32 characters.
2. Optionally, preview the plan first:

   ```sh
   scripts/setup-dev-team.sh <project> --dry-run
   ```

3. Run it from the plugin root, for the directory the team should work in:

   ```sh
   scripts/setup-dev-team.sh <project> --cwd <project-dir>
   ```

   Extra arguments after `--` go to every `claude` agent, for example `-- --permission-mode acceptEdits`.

Options: `--cwd DIR` sets the working directory for every pane (default: the current directory). `--no-agents` builds only the tabs and panes, which is useful for checking the layout.

## Things to know

- **Refusal on name clashes.** The script checks every agent name before it creates anything. If one is already running, it stops with no tabs created. To re-run, close the old team's tabs first.
- **Role prompts go in as the first message.** herdr rejects multi-line agent arguments, so the script starts each `claude` with no role and then sends the role as a message. Each agent replies with one line confirming its role.
- **Pane prompts block the team.** A new directory can trigger Claude's trust prompt, and tool approvals can block an agent. A blocked pane shows as `blocked`. Approve it in the pane yourself. Do not answer another agent's dialog for it.
- **Changing roles.** Edit `agents/*.md` or `scripts/messaging-protocol.md`, then re-run in a new session. Running agents keep the prompt they started with.
- **Tear down.** Close the four tabs only when the user asks. Closing a tab stops its agents.
- The `agents/*.md` files also load as Claude Code subagents named `dev-team-*`. That is expected; the tabs use the same prompts as messaged agents.
