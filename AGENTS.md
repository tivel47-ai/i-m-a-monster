# Project Rule: Keep Game Documentation Up to Date

You are working on **I'm a Monster**, a 2D tactical strategy game developed in Godot.

From now on, treat documentation maintenance as a permanent requirement for every development task.

## 1. General Rule

Whenever you implement, modify, refactor, or remove game functionality, review the relevant project documentation and update it if necessary.

The GitHub repository must always reflect the latest implemented state of the game.

Documentation updates are part of the definition of done, not an optional follow-up task.

## 2. Documentation Scope

Review existing documents in `docs/`, especially:

- `docs/game_design.md` — game design, mechanics, and approved design decisions.
- `docs/technical_design.md` — technical architecture, systems, implementation details, and dependencies.
- `docs/map_design.md` — map design, navigation, collision, and level structure.
- `docs/village_layout_draft.md` — approved preliminary village layout.
- `docs/village_graybox.md` — implemented graybox village and validation results.

Also review any other documentation relevant to the current task.

Do not create duplicate documents if an existing document can be updated.

## 3. When to Update Documentation

Update the relevant documents whenever changes affect:

- Gameplay mechanics or rules
- Unit behavior and AI
- NPC simulation
- Controls or camera behavior
- Level structure, maps, or navigation
- Scene and script architecture
- Data structures and system dependencies
- UI functionality
- Technical requirements or development tools
- Implemented features, limitations, or known issues
- Previously documented behavior that is no longer accurate

For small internal changes that do not affect documented behavior or architecture, documentation changes may be unnecessary.

## 4. Accuracy Requirements

Always distinguish between:

- **Implemented** — exists in the current codebase.
- **Tested** — verified by tests that were actually executed.
- **Planned** — approved for future development but not implemented.
- **Proposed** — suggested but not yet approved.
- **Deprecated** — replaced or no longer applicable.

Never describe planned functionality as implemented.

Never claim successful validation without executing the relevant tests.

Preserve previously approved game design decisions unless the current task explicitly authorizes changing them.

If implementation and documentation disagree, investigate the discrepancy. Do not silently change approved design requirements to match potentially incorrect code.

## 5. Documentation Quality

Keep documentation:

- Accurate and consistent with the repository
- Clearly structured and easy to navigate
- Concise but sufficiently detailed
- Free of obsolete technical instructions
- Consistent in terminology across files

Avoid unnecessary rewrites, duplication, and speculative information.

Preserve useful historical design decisions where appropriate, clearly identifying them as historical or superseded.

Keep existing documentation in **Russian**, following the project's established convention. Technical identifiers, filenames, class names, and code examples may remain in English.

## 6. Development Workflow

For every future development task:

1. Read the relevant documentation before making changes.
2. Implement the requested functionality.
3. Run available tests and validation.
4. Review whether the implementation affects documented systems.
5. Update all affected documentation.
6. Check consistency between code and documentation.
7. Include documentation changes in the same commit or pull request as the implementation whenever possible.

Do not postpone documentation updates to a separate future task.

## 7. Git and Commit Requirements

When a task changes documented functionality:

- Commit code and related documentation together.
- Use clear, descriptive commit messages.
- Do not create documentation-only commits unless documentation maintenance is the actual task or a separate correction is required.
- Do not overwrite or discard unrelated user changes.
- Avoid unnecessary documentation updates that create noise in Git history.

## 8. Final Task Report

At the end of every development task, include a short **Documentation Status** section containing:

- **Reviewed:** documentation files checked.
- **Updated:** documentation files modified, or `None`.
- **Reason:** why updates were needed or unnecessary.
- **Consistency:** whether the documentation matches the implemented changes.
- **Remaining gaps:** any unresolved documentation issues.

## 9. Permanent Instruction

Apply these rules automatically to all future development tasks in this repository.

Do not wait for the user to explicitly request documentation updates.

**Documentation maintenance is mandatory whenever the codebase changes in a way that affects the documented state of the game.**