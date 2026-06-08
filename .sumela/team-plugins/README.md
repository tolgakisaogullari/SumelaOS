# Team Plugins

Optional, self-contained **team-collaboration** components — parallel to `memory-plugins/`, but
for cross-developer coordination rather than per-agent recall. Like memory plugins, they are
**opt-in**: a team that declines them installs and runs nothing, and the framework is fully
functional without them.

## Why a separate category?

Memory plugins (`memory-plugins/`) enhance a single agent's recall (semantic search, code graph).
Team plugins coordinate *between* developers/agents and involve a **network service**, so they
have a distinct lifecycle (a server to deploy, per-developer identity, presence) and a distinct
security surface. Keeping them separate keeps the classifier, validation, and update tooling
honest about which is which.

## Available plugins

| Plugin | Purpose | Prerequisites |
|---|---|---|
| [teammate-relay](teammate-relay/) | Real-time, end-to-end-encrypted question relay between teammates (ask the right owner on any branch/network; human+agent co-authored answers) | Python 3.10+, a self-hosted relay server (Docker), team mode |

## Activation

Team plugins are wired by the setup scripts only when explicitly enabled (mirroring the
memory-plugin model): `/initSumela` offers the relay in team mode, captures the server URL,
writes the committed `relay-config.md`, and registers the skill; `/onboardSumela` provisions each
developer's identity + daemon. Decline it and nothing here is installed, registered, or run.

See [teammate-relay/README.md](teammate-relay/README.md) for deployment and the security model.
The operator runbook (`teammate-relay/server/DEPLOY.md`) and the setup wiring land in a later phase.
