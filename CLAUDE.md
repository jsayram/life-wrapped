# Life Wrapped

## Branch rule: `main` is production

`main` is the production branch. Every push to it starts the iOS CI release build, so it is never touched directly.

- Commit and push only to `dev`.
- To get changes into `main`, open a pull request from `dev` to `main`, then stop.
- Jose reviews and merges every pull request to `main` by hand. Never merge, approve, push, force-push or rebase `main`, and never open a pull request that targets `main` from any branch other than `dev`.
- This applies to every change, including docs, the website in `docs/` and the README.

## Project instructions

@.github/copilot-instructions.md
