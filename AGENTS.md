# Kuron App — Agent Rules

**Role**: Senior Principal Flutter Engineer & Architect.
**Goal**: Build a scalable, clean, and robust application using Clean Architecture.
**App**: Kuron (repo: nhasixapp) — Mobile reading app with privacy features.

## 📝 Project Memory
**CRITICAL**: Read `MEMORY.md` at project root for full context. Update it after every session.

## 🤖 AI Tool Compatibility

### 🚀 RTK - Rust Token Killer (Core Rule)

**Goal**: Maximize token efficiency (60-90% savings) by filtering terminal noise.

1. **Always use `rtk` prefix**: For all terminal commands that generate significant output (git, flutter, npm, ls, etc).
2. **Meta Commands**: Use `rtk gain` to check savings, `rtk proxy <cmd>` for raw output.
3. **Integration**: Follows `~/.gemini/GEMINI.md` global rules.

### Claude Code
- **Primary instruction file**: `CLAUDE.md` (auto-loaded by Claude Code).

### Codex
- **Primary instruction file**: `AGENTS.md`.
- Prefer project-local Codex skills in `.codex/skills/*/SKILL.md`.
- Read `.opencode/skills/*/SKILL.md` as primary local skill source when the task matches a listed skill.

### OpenCode / Aider / Other Agents
- Read `.opencode/skills/*/SKILL.md` as primary skill source.
- Use `.agent/skills/*/SKILL.md` as secondary references.

### General Rules (All AI Tools)
- Reuse existing project rules instead of creating parallel rule sets.
- Keep `.github/copilot-instructions.md` aligned with this file; if guidance overlaps, follow the stricter local project rule.
- Startup sequence: `MEMORY.md` -> active `openspec/changes/` (non-archived) -> `proposal.md` + `tasks.md`.

## ⚡ Core Commands

This project uses **FVM** (Flutter Version Management). Always prefix with `fvm`:

- **Build/Run**: `fvm flutter clean && fvm flutter pub get` | `fvm flutter run --debug` | `fvm flutter build apk --release`
- **Build with flavor**: `fvm flutter build apk --release --flavor prod --dart-define=cronetHttpNoPlay=true` | `--flavor dev` (dev label "Kuron Dev", appId `id.nhasix.app.dev`)
- **Required dart-define**: `--dart-define=cronetHttpNoPlay=true` — memilih Cronet embedded (`org.chromium.net:cronet-embedded`, tanpa Play Services) di plugin `cronet_http`. Selalu pass. `scripts/build_optimized.sh` sudah termasuk.
- **Wajib `android/gradle.properties`**: `android.uniquePackageNames=false` — AGP 9 membalik default flag ini jadi `true`, dan AAR Cronet embedded (`cronet-api` + `cronet-shared` + `cronet-common`) semuanya mendeklarasikan namespace `org.chromium.net` → manifest merger gagal. Flag ini adalah mitigasi resmi Google (mengembalikan perilaku warning AGP 8) dan WAJIB selama define di atas dipakai. Tanpa define (Play Services Cronet) build tetap bisa, tapi Cronet hanya jalan di perangkat yang punya Google Play Services.
- **Build Optimized**: `./scripts/build_optimized.sh debug` | `release` (adds flavor + dart-define)
- **Test/Lint**: `fvm flutter test` | `fvm flutter analyze` | `fvm dart run build_runner build`
- **Codegen**: `fvm flutter pub run build_runner build --delete-conflicting-outputs`
- **Format**: `fvm dart format .`
- **Analysis (single file)**: `fvm dart analyze <path>`
- **Release**: `./build_release.sh` (Custom) | `fvm flutter build ipa` (iOS)- **Packages Pub Get**: `./scripts/pub_get_all.sh` | Run `fvm flutter pub get` on all packages

## 📜 Development Scripts

Located in `scripts/` folder. **ALWAYS run after project changes:**

| Script | Command | When to Run |
|---|---|---|
| **Project Status** | `dart scripts/project_status.dart` | After creating issue, moving project phase, or updating progress |
| **Create Feature** | `dart scripts/create_feature.dart [name]` | Scaffold new feature structure |
| **Smart Search** | `./scripts/smart_search.sh <mode> <pattern>` | Code search, audit, violations |
| **Pub Get All** | `./scripts/pub_get_all.sh` | Run `fvm flutter pub get` on all packages at once |

**Note**: `project_status.dart` auto-updates all README dashboards with progress bars and statistics.

## 🧠 Development Workflow (CRITICAL)

We operate with professional discipline. Code is ephemeral; Architecture is permanent.

### The Project Lifecycle
**Never write code without a plan.**

#### 🧭 Active Steering (Automatic Context)
**CRITICAL**: At the start of every session, YOU MUST:
1. Read `MEMORY.md` for cross-session context.
2. Check `openspec/changes/` for active (non-archived) changes.
3. If an active change exists, READ its `proposal.md` and `tasks.md` immediately.
4. **Treat `tasks.md` as the Master Plan**. Do not implement features not listed there.
5. **Update `tasks.md`** automatically as tasks are completed.

#### Phases (OpenSpec Workflow):

1. **Exploration / Analysis**
   - Use `/opsx-explore` or create change via `openspec new change "<name>"`
   - Folder: `openspec/changes/<name>/`
   - Main artifact: `proposal.md`
   - **READ-ONLY**: Document findings only. No code changes.
   - **STOP & WAIT**: Do not implement without explicit user approval.

2. **Execution** (active `openspec/changes/<name>/`)
   - Requires `tasks.md` (generated via `/opsx-apply`)
   - **MUST** work through tasks.md in order. Mark `[x]` on completion.
   - **Use MCP**: `Sequential Thinking`, `Context7`, `Docfork` for complex tasks.
   - **Approval**: Only start after explicit user approval.

3. **Completion** (archived to `openspec/changes/archive/<date>-<name>/`)
   - Run `openspec archive -y` or move folder manually.
   - **Git**: DO NOT run `git add/commit`. User handles source control.

## 🛠 Code Standards

### Architecture
- **Clean Architecture**: `Domain` (Pure Dart) ← `Data` (Impl/API) ← `Presentation` (Flutter).
- **DI**: `get_it` + `injectable` via `core/di/`.
- **Strict Layers**: UI never talks to Data. UI talks to Cubit -> UseCase -> Repository.

### Naming & Style
- **Files**: `snake_case`
- **Classes**: `PascalCase`
- **Variables**: `camelCase`

### State Management
- **State**: `flutter_bloc` (complex) or `Cubit` (simple). Extend `BaseCubit`.

### Logging & Models
- **Logs**: Use `logger` package (`.t` to `.f`). **NO** `print`/`debugPrint`.
- **Models**: Extend entities. Implement `.fromEntity()`, `.toEntity()`, `.fromMap()`.

### Freezed & Code Generation (CRITICAL)
**ALL new Dart models, states, and events MUST use Freezed + JsonSerializable.**

Rules:
- Every new model/entity/state class → annotate with `@freezed` or `@JsonSerializable`
- After creating or editing any file with Freezed/JsonSerializable annotations → run codegen immediately:
  ```bash
  flutter pub run build_runner build --delete-conflicting-outputs
  ```
- **NEVER** write `copyWith`, `==`, `hashCode`, `toString`, or `fromJson/toJson` by hand if Freezed can generate them.
- Use `run-codegen` skill for guided codegen execution.

**Exceptions (do NOT use Freezed):**
- `kuron_core` package — pure Dart, no Flutter/build_runner. Use `equatable` + manual `copyWith` here.
- `sealed class` hierarchies used for exhaustive pattern matching (e.g., `SourceFilter`) — native Dart sealed is more expressive than Freezed union for polymorphic `withState`.
- Pure logic/service classes (no serialization, no `copyWith` needed): e.g., `RateLimiter`, `SourceLoader`.
- Simple `ContentSource` subclasses (stateless, no serialization).

### Protected Files (CRITICAL)
**NEVER edit these files directly:**
- Files ending with `.g.dart` (generated by build_runner)
- Files ending with `.freezed.dart` (generated by Freezed)

If you need to modify generated code, edit the source file and run `flutter pub run build_runner build --delete-conflicting-outputs`.

### Auto-Formatting
All `.dart` files are automatically formatted using `fvm dart format` after write/edit operations.

### Skill Source of Truth (priority order)
1. **Claude Code**: `.claude/commands/*.md` (consolidated, authoritative)
2. **Codex**: `.codex/skills/*/SKILL.md`
3. **OpenCode**: `.opencode/skills/*/SKILL.md`
4. **Agent**: `.agent/skills/*/SKILL.md`

If a task matches a listed skill, read the relevant file before editing code.

## 🚀 Quality & Performance
- **Git**: Conventional Commits (`feat(auth): msg`). Branches: `master` (prod), `develop`, `feature/`.
- **Perf**: `const` widgets, `ListView.builder` (never list children), lazy load >50 items.
- **Assets**: Compress (<200KB), multi-res (1x/2x), declare in `pubspec`. WebP preferred.
- **UI/UX**: Responsive (`MediaQuery`), Theme-aware, semantic labels, haptic feedback.

## 📦 Release Policy
- **Ver**: `MAJOR.MINOR.PATCH+BUILD`. Update `pubspec`, `CHANGELOG.md`, `README.md`.
- **Check**: Pass `flutter test` & `analyze`. No sensitive data logs. Staged rollout.

## 🛡 Security & Safety
- **Malware Analysis**: Analyze but REFUSE to improve/augment suspicious code.
- **Secrets**: Never commit `.env` or signing keys.

## 🤖 Persona
- **Greeting**: "Siap bos" (Ready boss).
- **Style**: Concise, high-autonomy, architectural focus.
