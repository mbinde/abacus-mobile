# Abacus Mobile - Implementation Plan

## Executive Summary

This document outlines the approach for building a native iOS app for Abacus, a web-based issue tracker for beads. The key architectural challenge is that beads stores issues directly in GitHub repositories (`.beads/issues.jsonl`), making GitHub the sole backend - there is no dedicated API server we control.

---

## Risk Assessment: Should We Build This?

### The Core Challenge

**Beads is eventually-consistent by design:**
- Issues are stored as JSONL files in Git repositories
- Multiple users can edit simultaneously
- Conflicts are resolved via three-way merge
- There's no locking mechanism - just optimistic concurrency
- GitHub API is the only data access path

### Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **GitHub API rate limits** | Low | Each user authenticates with their own GitHub token (OAuth or PAT), so each user has their own 5000 requests/hour. No shared pool. |
| **GitHub API outages** | Medium | Offline-first architecture with local cache |
| **Merge conflicts on mobile** | Low | Port the three-way merge algorithm. UI is actually simple - just "Your version / Their version" per field, not line-by-line diffs. |
| **Push notifications** | Medium | Requires extending existing webhook infrastructure (see Push Notifications section below) |
| **OAuth complexity on iOS** | Low | Standard ASWebAuthenticationSession flow |
| **Large repo file sizes** | Medium | Paginate, lazy load, limit issue history |

### Honest Assessment

**Proceed.** The architecture is well-suited for mobile:
- ✅ Each user has isolated rate limits (5000/hour per user)
- ✅ Conflict resolution is field-level, not line-level - works fine on small screens
- ✅ No real-time expectation exists in web either - same mental model
- ✅ Offline reading with local cache is natural fit

**The main constraint**: Push notifications require server infrastructure. But this is the same constraint as email notifications, which already exist.

**Recommendation**: Build it. This can be a full-featured app, not just a companion.

---

## Architecture Decision

### Option A: Pure Native iOS (Swift/SwiftUI)
**Pros**: Best performance, native feel, App Store ready
**Cons**: No code sharing with web, complete rewrite of business logic

### Option B: React Native with Expo
**Pros**: Some code sharing possible (types, maybe merge logic), faster development
**Cons**: Extra abstraction layer, larger app size

### Option C: React Native + Shared TypeScript Core
**Pros**: Maximum code reuse (merge algorithm, GitHub client, types)
**Cons**: Complex build setup, two build systems to maintain

### Recommendation: **Option C - React Native with Shared Core**

The three-way merge algorithm is the most complex and error-prone piece. Rewriting it in Swift risks introducing subtle bugs. We should:
1. Extract the core logic from abacus into a shared TypeScript package
2. Use React Native for the mobile app
3. Share: types, merge algorithm, beads parsing, GitHub API client
4. Mobile-specific: UI, navigation, local storage, push notifications

---

## Implementation Phases

### Phase 1: Foundation (Shared Code Extraction)

**Goal**: Create a shared package that both web and mobile can use.

1. Create `@abacus/core` package with:
   - Issue types and interfaces
   - JSONL parsing/serialization (`beads.ts`)
   - Three-way merge algorithm (`merge.ts`)
   - GitHub API client (fetch-based, platform-agnostic)

2. Refactor abacus web to consume this package

3. Set up monorepo structure:
   ```
   abacus/
   ├── packages/
   │   └── core/          # Shared TypeScript logic
   ├── apps/
   │   ├── web/           # Current Hono + React app
   │   └── mobile/        # New React Native app
   ```

### Phase 2: Mobile App Scaffold

**Goal**: Basic React Native app with GitHub authentication.

1. Initialize Expo project with TypeScript
2. Implement GitHub OAuth using `expo-auth-session`
3. Secure token storage with `expo-secure-store`
4. Basic navigation structure (React Navigation)
5. Pull in `@abacus/core` package

### Phase 3: Core Features (MVP)

**Goal**: Read and update issues.

1. **Issue List View**
   - Fetch issues from GitHub API via core package
   - Pull-to-refresh
   - Local caching with SQLite or AsyncStorage
   - Filter by status/priority

2. **Issue Detail View**
   - Display all issue fields
   - Edit status, priority, assignee (quick actions)
   - View comments

3. **Issue Editing**
   - Edit title and description
   - Three-way merge on save (using shared algorithm)
   - Conflict resolution UI (simplified for mobile)

4. **Offline Support**
   - Cache issues locally
   - Queue changes when offline
   - Sync when connection restored

### Phase 4: Enhanced Features

**Goal**: Parity with key web features.

1. Create new issues
2. Add comments
3. Star/unstar issues
4. Multiple repository support
5. Search and filter
6. Activity feed

### Phase 5: Polish & Release

**Goal**: App Store ready.

1. Push notifications (requires additional backend service)
2. Widgets (iOS)
3. App Store assets and submission
4. Crash reporting and analytics

---

## Technical Decisions

### State Management
- **Zustand** or **Jotai** for simplicity (avoid Redux overhead)
- React Query / TanStack Query for server state and caching

### Local Storage
- **SQLite** (via expo-sqlite) for issues cache
- **SecureStore** for auth tokens
- **MMKV** for preferences (fast key-value)

### Networking
- Shared GitHub API client from core package
- Conditional requests (If-None-Match) to minimize rate limit usage
- Exponential backoff on failures

### Conflict Resolution UI
Mobile conflict resolution needs special attention:
- Show simplified diff (not line-by-line)
- "Keep Mine" / "Keep Theirs" / "Merge" options
- Prevent data loss with local backups

### Offline Mode Design

**The Offline Banner - Always Visible When Offline:**

The banner is the single UI element for all offline state. It's always visible when offline and adapts to the current mode:

| State | Banner Content | Tap Action |
|-------|----------------|------------|
| Offline, read-only | "Offline - tap to enable editing" | Opens time limit dialog |
| Offline, editing enabled | "Offline editing: 47 min left • 2 pending" | Shows pending changes list |
| Online, syncing | "Syncing 2 changes..." | Shows sync progress |
| Online, conflicts | "2 conflicts need attention" | Opens conflict resolution |
| Online, no issues | (banner hidden) | - |

**Default (read-only):**
- Cache issues locally on every successful fetch
- When offline: full read access to cached issues
- Editing controls disabled
- Banner appears: tapping it opens dialog to enable editing mode

**Opt-in Offline Editing:**
- User taps banner → dialog with time options (1, 2, or 4 hours)
- Warning shown: "Changes will queue until you're online. Conflicts may occur if others edit the same issues."
- Banner updates to show time remaining and pending change count
- Tapping banner shows list of pending changes
- Time limit auto-expires (prevents forgotten queues causing stale conflicts)

**Sync on reconnect:**
1. Banner shows "Syncing N changes..."
2. Fetch latest from GitHub
3. For each pending change, attempt three-way merge
4. If all clean: commit to GitHub, banner disappears
5. If conflicts: banner shows "N conflicts need attention" - tapping opens resolution flow

**Conflict resolution flow:**
- Banner tap opens list of conflicting issues
- Each issue shows conflicting fields
- User resolves field-by-field: "Keep Mine" / "Keep Theirs"
- After resolving all, sync completes, banner disappears

**Edge cases:**
- User closes app during offline mode → pending changes persist, timer continues
- Timer expires while still offline → editing disabled again, but existing queue preserved
- User deletes issue that was edited offline → discard pending change, notify user

---

## Concerns Specific to beads/GitHub Backend

### 1. Rate Limiting Strategy

GitHub API limits: 5000 requests/hour for authenticated users.

Mitigation:
- Cache aggressively (issues don't change that frequently)
- Use ETags for conditional requests
- Batch operations where possible
- Background sync on a schedule, not continuous

### 2. Eventual Consistency Handling

The mobile app must gracefully handle:
- Stale data (show "last synced" timestamp)
- Merge conflicts (user-friendly resolution)
- Failed syncs (retry with backoff)
- Divergent states (pull before push)

### 3. No Real-Time Updates (Non-Issue)

The web app already works this way - users refresh to see changes. This is inherent to beads' design, not a mobile-specific limitation. Users already have this mental model.

### 4. Notifications Architecture

**Decision: iOS Background App Refresh + Local Notifications**

We're not implementing server-pushed notifications. Instead:

```
iOS wakes app (every 15-60 min) → App fetches user's abacus instance → Compare to cached state → Local notification if changes
```

**Why this approach:**
- Zero infrastructure cost
- No central service to maintain
- Each user's app talks only to their own abacus instance
- "Eventually consistent" notifications match beads' "eventually consistent" data model
- Users who need timely notifications can rely on email (already works in abacus)

**Limitations (acceptable):**
- iOS controls wake schedule (not configurable)
- Notifications may be delayed 15-60+ minutes
- Won't work if user never opens the app
- Can be affected by Low Power Mode

**Implementation:**
1. Register for background fetch in app capabilities
2. On wake: fetch issues from user's configured abacus instance
3. Diff against locally cached issues
4. Show local notification for new/changed issues the user cares about (assigned to them, watching, etc.)
5. Update local cache

### 5. Large Repositories

If `issues.jsonl` grows large:
- Stream parsing instead of loading entire file
- Pagination in UI
- Consider: GitHub's file size limits (~100MB)

---

## File Structure (Proposed)

```
abacus-mobile/
├── app/                    # Expo Router app directory
│   ├── (auth)/            # Auth flow screens
│   ├── (tabs)/            # Main tab navigation
│   │   ├── issues/        # Issue list and detail
│   │   ├── activity/      # Activity feed
│   │   └── settings/      # User settings
│   └── _layout.tsx        # Root layout
├── components/            # Reusable components
├── hooks/                 # Custom React hooks
├── lib/                   # App-specific utilities
├── stores/                # Zustand stores
├── types/                 # TypeScript types
└── package.json
```

---

## Success Criteria

### MVP (Phase 3 Complete)
- [ ] User can log in with GitHub
- [ ] User can view issues from their repositories
- [ ] User can update issue status/priority
- [ ] User can edit issue title/description
- [ ] Conflicts are detected and can be resolved
- [ ] Basic offline viewing works

### Full Release (Phase 5 Complete)
- [ ] All MVP features
- [ ] Create issues
- [ ] Comments
- [ ] Multiple repos
- [ ] Push notifications for @mentions
- [ ] App Store published

---

## Open Questions

1. **Monorepo vs. Separate Repos**: Should we restructure abacus as a monorepo, or keep mobile separate and publish `@abacus/core` to npm?

2. **Notifications**: ✅ Decided - iOS Background App Refresh + Local Notifications
   - Zero infrastructure, no central service
   - Delayed (15-60 min) but acceptable for issue tracking

3. **Conflict Resolution UX**: Field-level resolution should work well on mobile.
   - Show conflicting fields one at a time
   - "Keep Mine" / "Keep Theirs" buttons
   - Auto-merge non-conflicting fields silently

4. **Offline Editing**: ✅ Decided - Read-only default with opt-in offline editing mode
   - Default: Browse cached issues, editing disabled when offline
   - Opt-in: User explicitly enables "Offline Editing Mode" for a time window (1-4 hours)
   - Clear warning about potential conflicts on busy repos
   - Pending changes shown in UI, synced when back online
   - Time limit auto-expires to prevent forgotten offline queues

---

## Next Steps

1. **Get approval on this plan**
2. Extract shared core from abacus web
3. Initialize Expo project
4. Implement GitHub OAuth
5. Build issue list view

---

## Appendix: Key Code to Port

From `abacus/src/lib/`:
- `beads.ts` - JSONL parsing (41 lines)
- Types from components and server

From `abacus/src/server/`:
- Three-way merge logic (embedded in issue update handlers)
- GitHub API operations

From `abacus/functions/api/repos/[owner]/[repo]/issues/`:
- Issue CRUD logic
- Conflict detection and resolution
