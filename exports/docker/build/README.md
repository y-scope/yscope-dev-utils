# Docker build

Small helpers for assembling a `docker build` command line.

Building an image from inside a company network usually means repeating the same handful of options every time: send your proxy settings into the build, point the package manager at an internal mirror, refresh the base image, and record which commit the image came from. Every project ends up writing that slightly differently. These functions write it once.

They have nothing to do with certificates — for that, see [ca-trust](../ca-trust/README.md).

## Requirements

* `bash` 3.2 or newer (macOS's `/bin/bash` qualifies).
* `docker` with `buildx` (Docker 23 or newer). `docker_build_run` checks for it and fails with a clear message if it's missing.

## Usage

```bash
source tools/yscope-dev-utils/exports/docker/build/host.sh

build_cmd=(docker buildx build --tag <tag> --file <dockerfile> <context>)
docker_build_finalize build_cmd "${repo_root}" APT_MIRROR_URL
```

`docker_build_finalize` runs everything below in order. Call the individual functions instead if you need to leave one out.

## What each function does

`docker_build_add_proxy_args <cmd-array-name>` copies your proxy settings into the build, so downloads that happen while the image is being built go through the same proxy your shell uses. It reads `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, and `NO_PROXY`, in either upper or lower case.

It also handles a trap that's easy to hit: if your proxy runs on your own machine, the build can't reach it by default, because Docker gives the build its own private network where "this machine" means something else. When an address like `localhost`, `127.0.0.1`, or `[::1]` is detected — including when it's written as `http://user:pass@127.0.0.1:8080` — the build is switched to your machine's network so the proxy is reachable. Set `DOCKER_NETWORK` to choose the network yourself.

`docker_build_add_env_build_args <cmd-array-name> [var-name...]` passes named environment variables into the build, skipping any that aren't set. Use it for your own settings — an internal package mirror, say — without this library needing to know what they're called.

`docker_build_add_pull_arg <cmd-array-name>` re-downloads the base image before building, so you don't silently build on a stale local copy. Set `DOCKER_PULL=false` to skip it, e.g. when building offline.

`docker_build_add_oci_labels <cmd-array-name> <repo-dir>` stamps the image with the commit and repository URL it was built from, so a built image can be traced back to its source. Does nothing if `<repo-dir>` isn't a git checkout.

`docker_build_run <cmd-array-name>` checks that `buildx` is available, prints the assembled command, and runs it.

Both drop credentials from URLs first: a remote like `https://user:token@github.com/org/repo` would otherwise be written into an image label that follows the image to every registry, and a proxy password would end up in the build log. The command itself still runs with the real values.

## Why the functions take an array's *name*

Each function is given the name of a bash array — `build_cmd`, not `"${build_cmd[@]}"` — and appends to it in place, so the command stays a list of separate words. Building it as one long string instead would mean the shell re-splitting that text later, and a proxy or mirror URL containing a space, a quote, or a `$` — common in real ones — would come apart.

Appending by name normally calls for a bash "name reference", but those need bash 4.3 and macOS ships 3.2, so `utils.sh` does it with `printf %q` instead: each value is written in a form the shell reads back as exactly the original bytes.
