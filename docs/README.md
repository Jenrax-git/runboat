# Jenrax documentation

This fork contains the runboat **code** only: the controller and the build kubefiles
(`src/runboat/kubefiles/`).

Building the `runboat-app` image, releasing and deploying it to Kubernetes is done from the
private infrastructure repository **Jenrax-git/runboat-jenrax**, which includes this repository
as a git submodule pinned to the released commit.

## Development workflow

1. Work on a feature branch, open a PR against `main-jenrax`; the `CI` workflow runs the tests.
2. Merge into `main-jenrax`.
3. Release: in `runboat-jenrax`, update the submodule to the new commit, commit, and push a
   `vX.Y.Z` tag (see its README).

## Build kubefiles

The kubefiles expect, in the target cluster:

- a storage class with `ReadWriteMany` support, passed as `storageClassName` in
  `RUNBOAT_BUILD_TEMPLATE_VARS`,
- the `runboat-builds` PriorityClass,
- the `runboat-wildcard-tls` and `runboat-mailhog-wildcard-tls` secrets in the build namespace.
