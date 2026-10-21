# Project Instructions for AI Coding Agents

**Last updated:** 2026-10-22

<!-- {preamble} -->

# ⚠️ Before You Start

Run `/init-session` at the beginning of each new session, OR read this entire file before proceeding.

**DO NOT** make code changes or commits until you have done one of the above.

<!-- {mission} -->

## Mission Statement

Feel the Noize (formerly the working name Manopola) is a macOS menu bar app that turns a Microsoft Surface Dial into a hardware volume knob: turning changes the volume of the default output device, pressing toggles mute, and the Dial's haptic motor clicks on every step.

The full specification is `Docs/DESIGN.md`. Read it before writing code; it is the source of truth for architecture, HID report layouts, Core Audio usage, gestures and milestones.

## Technology Stack

- **Language:** Swift 6 language mode, default actor isolation `MainActor`
- **UI:** AppKit only (NSStatusItem, NSMenu, NSPanel, NSWindowController); no SwiftUI, no storyboards or nibs
- **Frameworks:** IOKit HID and power sources, CoreAudio, AudioToolbox, ServiceManagement, OSLog
- **Dependencies:** none (no Swift packages)
- **Platform:** macOS 15.4+
- **Build System:** XcodeGen (`project.yml`); the `.xcodeproj` is generated and not committed
- **Tests:** Swift Testing, target `FeelTheNoizeTests` in `Tests/FeelTheNoizeTests`, hosted in the app
- **Distribution:** Developer ID, notarized, not sandboxed, Hardened Runtime
- **License:** MIT

## Session Protocol

When starting a new session, read this entire file and confirm you have
understood the project instructions before proceeding. Summarize the project
purpose and key conventions briefly. Do not make changes until you have
confirmed your understanding.

<!-- {principles} -->

## Primary Instructions

- Avoid making assumptions. If you need additional context to accurately answer the user, ask the user for the missing information. Be specific about which context you need.
- Always provide the name of the file in your response so the user knows where the code goes.
- Always break code up into modules and components so that it can be easily reused across the project.
- All code you write MUST be fully optimized. ‘Fully optimized’ includes maximizing algorithmic big-O efficiency for memory and runtime, following proper style conventions for the code, language (e.g. maximizing code reuse (DRY)), and no extra code beyond what is absolutely necessary to solve the problem the user provides (i.e. no technical debt). If the code is not fully optimized, you will be fined $100.
- Follow the module layout in `Docs/DESIGN.md` §12; one primary type per file, file name matches the type.
- Write only the code needed for the current milestone (`Docs/DESIGN.md` §13). No speculative abstractions.
- Hardware facts that M1 verifies (§14) must be written back into `Docs/DESIGN.md` when confirmed or corrected.

### Working Together

This file (`AGENTS.md`) is the primary instructions file for AI coding assistants working on this project. Agent-specific instruction files (such as `CLAUDE.md`, `.github/copilot-instructions.md`, `.cursorrules`) reference this document, maintaining a single source of truth.

When initializing a session or analyzing the workspace, refer to instruction files in this order:

1. `AGENTS.md` (this file - primary instructions and single source of truth)
2. Agent-specific reference file (if present - points back to AGENTS.md)

### Update Protocol (CRITICAL)

**PROACTIVELY update this file (`AGENTS.md`) as we work together.** Whenever you make a decision, choose a technology, establish a convention, or define a standard, you MUST update AGENTS.md immediately in the same response.

**Update ONLY this file (`AGENTS.md`)** when coding standards, conventions, or project decisions evolve. Do not modify agent-specific reference files unless the reference mechanism itself needs changes.

**When to update** (do this automatically, without being asked):

- Technology choices (build tools, languages, frameworks)
- Directory structure decisions
- Coding conventions and style guidelines
- Architecture decisions
- Naming conventions
- Build/test/deployment procedures

**How to update AGENTS.md:**

- Maintain the "Last updated" timestamp at the top
- Add content to the relevant section (Project Overview, Coding Standards, etc.)
- Log every change in the "Recent Updates & Decisions" log in `UPDATES.md` with:
  - Date (with time if multiple updates per day)
  - Brief description
  - Reasoning for the change
- New log entries go directly below the changelog marker in `UPDATES.md`, newest first; load the `recent-updates` skill for the full rules
- Preserve the AGENTS.md structure: title header → timestamp → main instructions

Architecture and behavior changes go into `Docs/DESIGN.md` as well.

## Best Practices

### When Updating This Repository

1. **Maintain Consistency**: Keep code style consistent across the codebase
2. **Test First**: Write tests before implementing features when applicable
3. **Document Changes**: Update documentation when changing functionality
4. **Date Changes**: Update the "Last updated" timestamp in this file when making changes
5. **Log Updates**: Add entries to the "Recent Updates & Decisions" log in `UPDATES.md`

### Security & Safety

- Never include API keys, tokens, or credentials in code
- Always require explicit human confirmation before commits
- Maintain conventional commit message standards
- Keep change history transparent through commit messages

### Testing

- Unit tests: target `FeelTheNoizeTests` in `Tests/FeelTheNoizeTests`, hosted in the app; the app does not install `AppDelegate` while hosting tests, so a test run never seizes the Dial or touches the audio device
- Test layout mirrors `Sources/FeelTheNoize`: a suite for `Sources/FeelTheNoize/<Group>/Foo.swift` lives in `Tests/FeelTheNoizeTests/<Group>/FooTests.swift`; shared fakes and fixtures in `Tests/FeelTheNoizeTests/Fixtures/` (the move of the existing flat suites is milestone 2.4 of `Docs/CODE_REVIEW.md`)
- Hardware checks: the manual test checklist in `Docs/DESIGN.md` §11.2
- Open review findings and the fix plan: `Docs/CODE_REVIEW.md`; its Decisions table settles the questions the plan raised, so execute it without re-asking
- Testing framework: Swift Testing

### Documentation

- Specification: `Docs/DESIGN.md` is the source of truth; architecture and behavior changes go there
- Code comments: explain why, not what; `///` for documentation comments, `// MARK: -` to group sections
- Diagrams: PlantUML in `Docs/diagrams/`, styled with the shared `visio2003.iuml` include, rendered to SVG and embedded in `Docs/DESIGN.md`
- README: written for users
- Changelog: maintained in `UPDATES.md` (see the `recent-updates` skill)

<!-- {languages} -->

## Swift Coding Standards

Load the `swift-coding-conventions` skill before writing, reviewing, or refactoring Swift code.
Load the `swift-build-commands` skill when building or running the project.

### Build Commands

`build.sh` is the entry point; prefer `./build.sh build`, `test`, `lint`, `format`, `diagrams`, `icon`, `release` and `notarize`. Several commands run in order (`./build.sh lint test`); `./build.sh help` lists them. `TEAM_ID`, `DEVELOPER_ID` and `NOTARY_PROFILE` are overridden through the environment.

- `build` and `test` run `xcodegen generate` first; run `./build.sh gen` after changing `project.yml` or adding or removing files when not building.
- swift-format ships with the Xcode toolchain and runs through `xcrun`.
- Watch the app log, including raw HID reports:

```sh
log stream --style compact --level debug --predicate 'subsystem == "com.panjas.FeelTheNoize"'
```

### Project-Specific Rules

Architecture rules of this app that supplement the `swift-coding-conventions` skill; the skill wins where they disagree.

- Concurrency: everything is main-actor isolated. IOKit and Core Audio callbacks run on the main run loop / main queue and enter the actor with `MainActor.assumeIsolated`. No `@unchecked Sendable`, no locks. The single exception to main-actor isolation is the software volume IO block (`SoftwareVolume`), which runs on the HAL IO thread and shares only the gain through `Synchronization.Atomic` in a `nonisolated final class`; it must not allocate, lock or log. C callbacks resolve the main-actor owner from the context pointer before entering the actor; a non-Sendable CF argument such as `IOHIDDevice` is handed over through a commented `nonisolated(unsafe) let`, the only permitted unsafe opt-out.
- Logging via `os.Logger(subsystem: "com.panjas.FeelTheNoize", category:)` with categories `dial`, `audio`, `control`, `ui`, defined in `Support/Log.swift`. A category is added with the milestone that first uses it.
- Undeclared system APIs are allowed only where their failure degrades a non-essential feature, looked up with `dlsym` and recorded in `Docs/DESIGN.md`. Currently only `IOPSCopyPowerSourcesByType` for the battery levels of the Dial and audio accessories (`AccessoryBattery`).
- Milestone spike code that must not ship is wrapped in `#if DEBUG` and named in `Docs/DESIGN.md` §13 together with the milestone that removes it.

<!-- {integration} -->

## Commit Protocol

- **NEVER commit automatically** — always wait for explicit user confirmation
- Confirmation is per milestone of `Docs/CODE_REVIEW.md`: one go-ahead for a milestone (or a list of them) covers every commit and push inside it; outside that plan, confirm each commit
- Stage changes, write a conventional commits message (max 50-char subject, 72-char body lines), then commit
- Load the `git-workflow` skill for the full message format, character limits, and examples before committing
- Never add co-authorship trailers or any attribution naming an AI coding agent to commit messages
- Commits are authored as the developer (`Heiko Panjas <heiko@panjas.com>`); in a cloud session set `git config user.name` and `user.email` locally in the repository before the first commit, since the container's global identity is an agent name

## Recent Updates & Decisions

Project decisions and notable changes are logged in `UPDATES.md`, below its changelog marker. The log is append-only: add new entries at the top, never edit or delete existing ones, and keep the "Last updated" timestamp in `AGENTS.md` in sync. Load the `recent-updates` skill for the entry format and full rules.

## Semantic Versioning

Automatically bump the project version after every code change and include it in the same commit. Load the `semantic-versioning` skill for the full PATCH/MINOR/MAJOR decision rules.

The version manifest is `project.yml`: semantic version in `MARKETING_VERSION`; bump `CURRENT_PROJECT_VERSION` for every distributed build.
