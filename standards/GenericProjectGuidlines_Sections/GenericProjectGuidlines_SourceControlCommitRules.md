# Chapter 16 — Source Control & Commit Rules

> *Section file for `GenericProjectGuidlines_V1.10_20260323.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.10_20260323.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
>
> **TOC Maintenance:** If this section is renamed or deleted, update both the parent document's Contents list AND the `GenericProjectGuidlines_TOC.md` file. See the TOC file for detailed maintenance instructions.

---

Source control discipline makes it possible to trace why a change was made, roll back a broken release, and collaborate without conflicts.

## Repository Structure

- One Git repository per solution. Do not split into separate repos unless organizational scale demands it.
- The `docs/` folder at the solution root stores architecture documents, ERDs, generated `openapi.json`, and this guidelines file.
- `.gitignore` must exclude: `bin/`, `obj/`, `.vs/`, `*.user`, and all credential-containing files.
- `.copilotignore` must list the same credential files as `.gitignore` to prevent AI tools from reading secrets.

## Branch Strategy

| Branch | Purpose | Who Creates |
|--------|---------|-------------|
| `master` / `main` | Production-ready code only. Deployments triggered from this branch. | Protected — merged via PR only |
| `develop` | Integration branch. Completed features merged here first. | Protected — merged via PR only |
| `feature/{description}` | One branch per feature or story. | Developer |
| `fix/{issue}-{description}` | Bug fix branches, referencing an issue number. | Developer |
| `release/{version}` | Release preparation: version bumps and changelog only. | Release manager |

## Commit Message Format

```
{type}({scope}): {short description in present tense, under 72 chars}

Body: explain WHY the change was made, not what was changed.
The diff already shows what changed.

Refs: #{issue-number}

Types: feat | fix | refactor | docs | test | chore
```

## Source Control Rules

- **MUST** Credentials and secrets are never committed. Period.
- **MUST** Every commit must build cleanly and pass all existing tests.
- **MUST** Commit messages describe *why* the change was made, not what changed.
- **SHOULD** Commit at logical stopping points: a completed feature, a passing test, a fixed bug. Avoid mixing unrelated changes in one commit.
- **SHOULD** Commit at least once every 4 active working days on a feature branch to reduce merge conflict risk.
- **SHOULD** Tag releases on the main branch: `git tag -a v1.3.0 -m "Release 1.3.0"`

> **✅ Note:** Add a `.copilotignore` file in the solution root that mirrors `.gitignore` entries for all files containing credentials, to prevent GitHub Copilot from reading or suggesting edits to those files.
