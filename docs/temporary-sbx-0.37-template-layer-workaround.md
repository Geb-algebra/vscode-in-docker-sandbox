# Temporary workaround for docker/sbx-releases#366

## Why this exists

Docker Sandboxes 0.37.x can create a sandbox whose root filesystem omits the
upper layers of a custom image when the base chain was already cached. The
custom image itself is correct in Docker, but tools and files added by this
repository's Dockerfile can be absent from the sandbox.

Upstream issue:

- https://github.com/docker/sbx-releases/issues/366

Until the issue is fixed and verified locally, `sbx-vscode` leaves
`--template` unspecified so sbx selects its built-in `codex-docker` template.
The launcher mounts a locally generated, architecture-specific toolchain
artifact directory, and the mixin Kit uses a marker-guarded startup hook to
verify and extract it once when each sandbox is created. Extracted files and
the completion marker live in the sandbox writable state and persist across
stop/start.
Removing the sandbox removes them.

The artifact cannot be injected as a Kit static file: sbx 0.37 transports each
file through a 4 MiB RPC and writes content through a shell argument, which is
also unsuitable for arbitrary binary. The launcher therefore mounts the local
artifact directory as an additional direct mount. A small generated Kit file
records that absolute path, and the startup installer hashes, validates, and
extracts the mounted archive.

On sbx 0.37.0, `commands.install` runs before Kit static files are placed in
`/home/agent`, so it cannot invoke a script bundled under `files/home`. The
startup wrapper runs after static file placement. Although it is invoked at
each start, it exits immediately when the persistent completion marker exists.
`sbx-vscode` waits for that marker before opening VS Code.

This workaround does not place credentials in the artifact or sandbox. The
browser and language toolchain are downloaded only while building the local
artifact. Sandbox startup uses network access only for apt runtime packages.

## Temporary code

The exact temporary ranges are marked with:

```text
BEGIN TEMPORARY WORKAROUND: docker/sbx-releases#366
END TEMPORARY WORKAROUND: docker/sbx-releases#366
```

They currently exist in:

- `sbx-vscode`: use the built-in template unless `SBX_TEMPLATE_NAME` is set.
- `spec.yaml`: invoke the marker-guarded toolchain installer at startup.
- `sbx-vscode`: wait for the toolchain completion marker.

The following supporting changes are also temporary:

- The Kit injects `mise-config.toml` under
  `/home/agent/.local/share/vscode-in-sandbox/`.
- `install-toolchain-once.sh` owns the completion/failure markers and log.
- `build-toolchain-artifact.sh` builds the native architecture artifact locally;
  generated archives and checksums are intentionally ignored by Git.
- `install-tools.sh` verifies and extracts that artifact, installs apt runtime
  packages, creates launchers, and verifies the completed environment.
- The normal launcher flow does not call `build-template.sh`.

## Verification before removal

After Docker ships a fix:

1. Build and load the custom template with `./build-template.sh`.
2. Generate the toolchain artifact with `./build-toolchain-artifact.sh`.
3. Create a disposable sandbox with
   `SBX_TEMPLATE_NAME=local/vscode-codex:1`.
4. Verify that `zsh`, the pinned mise tools, Playwright browser, oh-my-zsh,
   VS Code settings, and the Playwright CLI skill are present without the
   startup installer.
5. Verify stop/start and official SSH access.

Do not remove the workaround based only on the upstream issue being closed.
Verify the complete custom rootfs on the local macOS installation first.

## Removal steps

1. Restore `local/vscode-codex:1` as the default `TEMPLATE_NAME` in
   `sbx-vscode` and remove its temporary marker block.
2. Remove the temporary startup command block from `spec.yaml`.
3. Remove the matching marker-wait block from `sbx-vscode`.
4. Delete `install-toolchain-once.sh` and decide whether the local artifact
   remains the source for the custom image or is replaced by normal image layers.
5. Keep `PLAYWRIGHT_BROWSERS_PATH` and `PLAYWRIGHT_MCP_BROWSER` available in
   the custom image or Kit environment.
6. Update README setup so `./build-template.sh` is required again.
7. Rebuild/load the template, remove old sandboxes, and recreate them.
8. Delete this memo after the migration is complete.
