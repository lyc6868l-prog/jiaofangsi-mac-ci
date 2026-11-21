# AGENTS.md

This repository contains multiple apps and support directories. The active desktop UI work in this repo currently lives in:

- `apps/dj_flutter`

Treat `apps/dj_flutter` as the primary working package unless the task explicitly targets another area.

## Scope and workflow

- Make the smallest safe change that solves the task.
- Prefer editing existing files over creating new ones.
- Do not create docs files unless requested.
- Do not introduce new dependencies unless clearly necessary.
- Preserve existing layout, copy, ordering, and route behavior unless the task explicitly requires changes.
- For UI interaction work, verify behavior with tests when possible instead of relying only on static analysis.

## Repository structure

Top-level directories commonly seen here:

- `apps/` - application code
- `apps/dj_flutter/` - Flutter Desktop app
- `crates/` - Rust crates
- `docs/` - project documentation
- `scripts/` - automation scripts
- `runtime/`, `protocol/`, `logs/`, `test_assets/` - supporting project assets
- `6玻璃卡片参考/` - local reference material, not production app code

## Existing agent guidance discovered in repo

There is no root `AGENTS.md` yet.
There are no repo-level Cursor rules found in:

- `.cursorrules`
- `.cursor/rules/`

There are no repo-level Copilot instructions found in:

- `.github/copilot-instructions.md`

Reference-only guidance exists in:

- `6玻璃卡片参考/reference_repos/cupertino_native_better/AGENTS.md`
- `6玻璃卡片参考/reference_repos/cupertino_native_plus/AGENTS.md`

Those reference files are not authoritative for production code, but one useful rule is worth carrying over:

- After writing Flutter code, run `flutter analyze`.

## Environment assumptions

- Flutter app package root: `apps/dj_flutter`
- Dart SDK constraint: `^3.11.4`
- Lints: `flutter_lints`
- Target verified in this repo: macOS desktop

## Build, lint, and test commands

Run all Flutter commands from:

- `apps/dj_flutter`

### Install dependencies

```bash
flutter pub get
```

### Static analysis

```bash
flutter analyze
```

Analyze specific files:

```bash
flutter analyze lib/app/shell/app_shell_page.dart
flutter analyze test/widget_test.dart
```

### Run app

```bash
flutter run -d macos
```

### Build macOS app

Debug build:

```bash
flutter build macos --debug
```

Release build:

```bash
flutter build macos --release
```

### Run all tests

```bash
flutter test
```

### Run a single test file

```bash
flutter test test/widget_test.dart
```

### Run a single test by name

```bash
flutter test test/widget_test.dart --plain-name "renders shell placeholder layout"
flutter test test/widget_test.dart --plain-name "pressing card immediately changes visual bounds"
```

### Run one specific package test after editing UI interaction code

Use this minimum sequence:

```bash
flutter analyze
flutter test test/widget_test.dart
```

For interaction-heavy UI work on desktop, prefer this fuller sequence:

```bash
flutter analyze
flutter test
flutter build macos --debug
```

## Code style guidelines

### General

- Follow `flutter_lints` from `analysis_options.yaml`.
- Keep code concise and local.
- Prefer clear, direct implementations over abstraction-heavy designs.
- Do not add comments unless they prevent real confusion.
- Do not add speculative error handling or architecture.

### Formatting

- Use `dart format` style conventions.
- Keep imports ordered and minimal.
- Remove unused imports.
- Prefer trailing commas where Flutter formatting benefits readability.

### Imports

- Prefer package imports for external packages.
- Use relative imports inside `lib/app/...` when the code already follows that pattern.
- Do not leave reference-repo imports or dead imports behind.

### Types

- Use explicit types when they improve readability in widget trees, state, and controller code.
- Use `final` for values that do not change.
- Use `const` constructors and literals wherever possible.
- Avoid `dynamic` unless unavoidable.

### Naming

- Types: `UpperCamelCase`
- Methods/variables/fields: `lowerCamelCase`
- Constants: `lowerCamelCase` for Dart `const` fields unless existing code uses another style
- Private Flutter widgets/classes: leading underscore, e.g. `_FeatureFunctionCard`
- Keep names aligned with current file conventions

### Widgets and UI

- Preserve existing layout and copy unless the task explicitly changes them.
- For desktop pointer interactions, verify actual pointer behavior, not just tap behavior.
- Prefer testing visible geometry changes for interaction feedback instead of assuming internal transforms are correct.
- Keep decorative layers wrapped with `IgnorePointer` when they should not affect hit testing.
- Use the lowest interaction layer that matches the need:
  - `MouseRegion` for hover
  - `Listener` for raw pointer down/up/cancel
  - `GestureDetector` for semantic tap handling
- Do not assume `InkWell` alone is sufficient for custom desktop press-feedback systems.

### State and animation

- Keep animation state transitions deterministic.
- Avoid overlapping animation paths that can race with each other.
- If release behavior depends on a press phase, ensure the pressed state is visually observable before resetting.
- For interaction fixes, test both:
  - state transitions
  - visible bounds/position changes

### Error handling

- Handle only realistic failure points.
- Use early returns for guard clauses.
- Swallow platform-channel failures only when they are explicitly optional, as done for macOS window-state checks.
- Do not add generic try/catch wrappers without reason.

### Testing expectations

- Update tests when UI intentionally uses layered duplicate text or glow text.
- Prefer assertions on visible geometry or resulting UI state over fragile internal implementation details.
- When fixing UI interactions, add or update at least one test that proves the visual state changed.

## Files commonly touched for desktop shell interaction work

- `apps/dj_flutter/lib/app/shell/app_shell_page.dart`
- `apps/dj_flutter/lib/app/shell/feature_card/feature_card_interaction_controller.dart`
- `apps/dj_flutter/lib/app/shell/feature_card/feature_card_interaction_tokens.dart`
- `apps/dj_flutter/lib/app/shell/feature_card/feature_card_shell.dart`
- `apps/dj_flutter/test/widget_test.dart`

## Practical guardrails for agents

- Do not edit files under `6玻璃卡片参考/` unless the task explicitly asks for reference-repo changes.
- Treat reference repos as inspiration only, not direct implementation sources.
- Before claiming a UI issue is fixed, verify with:
  1. `flutter analyze`
  2. a targeted widget test
  3. a full `flutter test`
  4. `flutter build macos --debug` for desktop-impacting changes

## Definition of done for Flutter UI interaction tasks

A task is not done until all of the following are true:

- The code builds
- Static analysis passes
- Relevant widget tests pass
- The interaction is verified by an assertion on visible UI behavior or final UI state
- No unrelated layout, copy, or ordering regressions were introduced
