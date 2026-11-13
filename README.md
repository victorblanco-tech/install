# VB Tech platform installer

Public bootstrap for the **private** VB Tech platform repository. This repo does
not contain the platform, customer data or credentials. Access to the private
source must be granted separately.

## Before starting

- macOS, a normal user account (do not run with `sudo`).
- Git, Python 3, Node.js 22+ and a running Docker Desktop with Compose v2.
- Enough disk space for source, images and databases (at least 20 GB recommended).
- Your initial owner email, HTTPS origins and configured Cloudflare Access
  applications for MC, Projects and Knowledge Search. Have their team domain and
  audience IDs (AUDs) ready. The CRM audience list must include MC and Projects.
- An expiring, fine-grained GitHub token with **Contents: read** for
  `victorblanco-tech/ai-assistant` only. Never share the token in a slide or chat.

That token grants source read access, not an installation-only license. Use an
individual credential, keep its scope narrow, and revoke it when no longer needed.

## Review, check, install

Prefer downloading and reviewing the script before running it:

```bash
curl --proto '=https' --tlsv1.2 --fail --show-error --location \
  --connect-timeout 10 --max-time 60 \
  https://raw.githubusercontent.com/victorblanco-tech/install/main/install.sh \
  --output install-vbtech.sh
less install-vbtech.sh
bash install-vbtech.sh --check
bash install-vbtech.sh
```

`--check` is local and read-only. It does not test repository access, Cloudflare
or a complete installation. A new destination must not exist yet.
The installer always opens with its banner, then lists missing prerequisites
together with next steps. Missing requirements stop setup without changing files
or services; install them yourself and run the command again.

The shorter interactive command is:

```bash
curl --proto '=https' --tlsv1.2 -fsSL --connect-timeout 10 --max-time 60 \
  https://raw.githubusercontent.com/victorblanco-tech/install/main/install.sh | bash
```

Only run downloaded code from a publisher you trust. The script runs as your user
and the platform setup can build and start containers. HTTPS is transport security,
not independent signature verification. Use the installer release tag in place of
`main` when sharing a versioned command.

The default platform is **v0.26.1**, not moving `main` or `dev`. The bootstrap fetches
one release, resolves its commit and executes setup from that exact checkout.
`--ref=vX.Y.Z` or a full 40-character commit explicitly selects another compatible
version. A tag can be moved by a repository maintainer; use a reviewed full commit
when immutable selection is required. Older releases without the bootstrap
contract are rejected. Naming an instance `test` does not select a dev release.

The default destination is `$HOME/vb-tech/instances/prod`. Another name is accepted:

```bash
bash install-vbtech.sh demo
```

The root may be set with `VB_ROOT=/absolute/path`. Symlinked paths, traversal and
existing instances are refused. Do not use this bootstrap to update or reset an
existing installation; use its supported backup-aware updater.

## Configuration and secrets

The installer asks for public owner/access settings and then for a GitHub token
with hidden input. You may supply public values using `--owner-email=...` and
repeated `--system-env=KEY=value` options. These are **not** secret options; never
pass provider keys there. The selected platform validates the complete identity
configuration before the checkout is moved into its final location.

An inherited `GITHUB_TOKEN` also works, but the silent prompt is preferable. Do
not put a literal token in shell history. `GITHUB_TOKEN=... curl ... | bash` does
not pass the variable across the pipe and is not a supported example.

The token is passed only to the Git fetch process through its environment. It is
not embedded in command arguments, the remote URL or a credential file, and is
not passed to platform setup or saved for future updates. Configure update access
separately through the platform's supported settings. Environment variables are
not a secret vault: the same user or an administrator can inspect process memory.

The subsequent private setup asks for platform service settings. Its `.env` and
runtime data must remain private. External integrations need their own credentials
and policies. BA is optional and starts without customer buildings or device grants.

## Failures and verification

- Failed source fetch, invalid identity or interruption before handoff removes the
  temporary checkout. A newly created empty parent directory may remain.
- Once setup starts, a failure preserves its checkout and any diagnostic/runtime
  state. Do not automatically delete it or rerun bootstrap over it. Inspect the
  error and use the platform's documented recovery path.
- No elevation, firewall changes, existing-instance deletion or Docker restart is
  performed by the bootstrap itself. Private setup starts the requested services.
- Automated checks use disposable local Git fixtures and mocked Docker commands
  on macOS and Linux. They cover secrets handling, immutable handoff, refusal of
  unsafe paths, cancellation, source/setup errors and cleanup.
- These checks do not replace a complete fresh-Mac acceptance installation with
  real Cloudflare login and configured integrations. No live messaging or paid AI
  test calls are performed in CI.
