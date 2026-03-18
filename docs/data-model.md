# Data Model & Database Schema

Detour uses two separate SQLite databases via [GRDB](https://github.com/groue/GRDB.swift):

- **Session database** (`browser.db`) -- spaces, tabs, profiles, downloads, and app state
- **History database** (`history.db`) -- visited URLs and per-visit records with full-text search

Both are stored in `~/Library/Application Support/Detour/`.

---

## Session Database

**Singleton**: `AppDatabase.shared` (`Storage/Database.swift`)

### Tables

#### `space`

Container for tabs. Each space belongs to a profile.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PRIMARY KEY | UUID |
| `name` | TEXT | NOT NULL | Display name |
| `emoji` | TEXT | NOT NULL | Space icon emoji |
| `colorHex` | TEXT | NOT NULL | Hex color code (e.g. "007AFF") |
| `sortOrder` | INTEGER | NOT NULL | Position in space list |
| `selectedTabID` | TEXT | | UUID of the currently selected tab |
| `profileID` | TEXT | NOT NULL, FK -> profile | Associated profile |

#### `tab`

Active tabs within a space.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PRIMARY KEY | UUID |
| `spaceID` | TEXT | NOT NULL, FK -> space (CASCADE) | Parent space |
| `url` | TEXT | | Current URL (nil for blank tabs) |
| `title` | TEXT | NOT NULL, default "New Tab" | Page title |
| `faviconURL` | TEXT | | URL of the tab's favicon |
| `interactionState` | BLOB | | Serialized WKWebView state for session restore |
| `sortOrder` | INTEGER | NOT NULL | Position within the space's tab list |
| `lastDeselectedAt` | DOUBLE | | Timestamp when tab was last deselected (for archiving) |
| `parentID` | TEXT | | UUID of parent tab (for child tab grouping) |
| `peekURL` | TEXT | | URL being previewed in peek mode |
| `peekInteractionState` | BLOB | | Serialized state for peek preview |

Cascade delete: when a space is deleted, all its tabs are removed.

#### `pinnedTab`

Bookmarked tabs that persist at the top of a space's sidebar.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PRIMARY KEY | UUID |
| `spaceID` | TEXT | NOT NULL, FK -> space (CASCADE) | Parent space |
| `pinnedURL` | TEXT | NOT NULL | Original bookmarked URL ("home") |
| `pinnedTitle` | TEXT | NOT NULL | Display name for the pin |
| `url` | TEXT | | Current navigated URL |
| `title` | TEXT | | Current page title |
| `faviconURL` | TEXT | | Current favicon URL |
| `interactionState` | BLOB | | Serialized WKWebView state |
| `sortOrder` | INTEGER | NOT NULL | Position in pinned section |
| `folderID` | TEXT | FK -> pinnedFolder (SET NULL) | Parent folder (nil = top level) |
| `peekURL` | TEXT | | Peek preview URL |
| `peekInteractionState` | BLOB | | Peek serialized state |

#### `pinnedFolder`

Hierarchical folders for organizing pinned tabs. Self-referential for nesting.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PRIMARY KEY | UUID |
| `spaceID` | TEXT | NOT NULL, FK -> space (CASCADE) | Parent space |
| `parentFolderID` | TEXT | FK -> pinnedFolder (SET NULL) | Parent folder for nesting |
| `name` | TEXT | NOT NULL | Folder display name |
| `isCollapsed` | BOOLEAN | NOT NULL, default false | UI collapse state |
| `sortOrder` | INTEGER | NOT NULL | Position among siblings |

#### `profile`

Per-space browser settings. Spaces reference profiles; multiple spaces can share one.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PRIMARY KEY | UUID |
| `name` | TEXT | NOT NULL | Display name |
| `userAgentMode` | INTEGER | NOT NULL, default 0 | 0=Detour, 1=Safari, 2=Custom |
| `customUserAgent` | TEXT | | Custom UA string (when mode=2) |
| `archiveThreshold` | DOUBLE | NOT NULL, default 43200 | Seconds before auto-archive (0=never) |
| `sleepThreshold` | DOUBLE | NOT NULL, default 3600 | Seconds before auto-sleep (0=never) |
| `searchEngine` | INTEGER | NOT NULL, default 0 | 0=Google, 1=DDG, 2=Bing, 3=Yahoo, 4=Ecosia, 5=Kagi |
| `searchSuggestionsEnabled` | BOOLEAN | NOT NULL, default true | Show search suggestions in palette |
| `isPerTabIsolation` | BOOLEAN | NOT NULL, default false | Each tab gets non-persistent data store |
| `isAdBlockingEnabled` | BOOLEAN | NOT NULL, default true | Master content blocking toggle |
| `isEasyListEnabled` | BOOLEAN | NOT NULL, default true | EasyList ad filter |
| `isEasyPrivacyEnabled` | BOOLEAN | NOT NULL, default true | EasyPrivacy tracker filter |
| `isEasyListCookieEnabled` | BOOLEAN | NOT NULL, default true | Cookie notice filter |
| `isMalwareFilterEnabled` | BOOLEAN | NOT NULL, default true | Malicious URL filter |

#### `contentBlockerWhitelist`

Per-profile domain exceptions for content blocking.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `profileID` | TEXT | NOT NULL, FK -> profile (CASCADE) | Profile this exception belongs to |
| `host` | TEXT | NOT NULL | Domain to whitelist (e.g. "example.com") |

Composite unique key: `(profileID, host)`

#### `closedTab`

Stack of recently closed tabs for undo/reopen. Capped at 100 entries (oldest removed first).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY (auto-increment) | Stack ordering key |
| `tabID` | TEXT | NOT NULL | Original tab UUID |
| `spaceID` | TEXT | NOT NULL | Space the tab belonged to |
| `url` | TEXT | | Last URL |
| `title` | TEXT | NOT NULL | Last title |
| `faviconURL` | TEXT | | Last favicon URL |
| `interactionState` | BLOB | | Serialized WKWebView state |
| `sortOrder` | INTEGER | NOT NULL | Original position in tab list |
| `archivedAt` | DOUBLE | | Timestamp if auto-archived (vs manually closed) |

#### `download`

File download records with progress tracking.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PRIMARY KEY | UUID |
| `filename` | TEXT | NOT NULL | Downloaded file name |
| `sourceURL` | TEXT | | Original download URL |
| `destinationURL` | TEXT | NOT NULL | Local file path |
| `totalBytes` | INTEGER | NOT NULL, default -1 | Total size (-1 = unknown) |
| `bytesWritten` | INTEGER | NOT NULL, default 0 | Bytes downloaded so far |
| `state` | TEXT | NOT NULL | "downloading", "completed", "failed", or "cancelled" |
| `createdAt` | DATETIME | NOT NULL | When download started |
| `completedAt` | DATETIME | | When download finished |

#### `appState`

Key-value store for app-level state.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `key` | TEXT | PRIMARY KEY | State key |
| `value` | TEXT | | State value |

Currently stores: `lastActiveSpaceID` -- the UUID of the most recently active space, used for session restoration.

### Migration History

| Version | Changes |
|---------|---------|
| v1 | Core tables: `space`, `tab`, `appState` |
| v2 | `closedTab` stack for undo |
| v3 | `download` table |
| v4 | `pinnedTab` table |
| v5 | `lastDeselectedAt` on tab, `archivedAt` on closedTab (archiving support) |
| v6 | `parentID` on tab (child tab grouping) |
| v7 | `profile` table + `profileID` on space (cookie isolation) |
| v8 | `searchEngine`, `searchSuggestionsEnabled` on profile |
| v9 | `pinnedFolder` table + `folderID` on pinnedTab (folder hierarchy) |
| v10 | `isPerTabIsolation` on profile |
| v11 | `sleepThreshold` on profile |
| v12 | Content blocker toggles on profile + `contentBlockerWhitelist` table |
| v13 | `isMalwareFilterEnabled` on profile |
| v14 | `peekURL`, `peekInteractionState` on tab and pinnedTab |

### Persistence Strategy

Session saves use a **clear-and-reinsert** approach within a transaction:

1. Delete all `SpaceRecord`s (cascades to tabs)
2. Re-insert all spaces and their tabs in order
3. Upsert `lastActiveSpaceID` in `appState`
4. Separately save pinned folders then pinned tabs per space (respecting FK order)

Saves are **debounced** -- mutations call `scheduleSave()` which waits 1 second before writing. Multiple rapid changes coalesce into a single write. `saveNow()` is called on app termination.

### Record Types

Each table has a corresponding GRDB `Record` struct in `Storage/Models/`:

| Record | File |
|--------|------|
| `SpaceRecord` | `SpaceRecord.swift` |
| `TabRecord` | `TabRecord.swift` |
| `PinnedTabRecord` | `PinnedTabRecord.swift` |
| `PinnedFolderRecord` | `PinnedFolderRecord.swift` |
| `ProfileRecord` | `ProfileRecord.swift` |
| `ClosedTabRecord` | `ClosedTabRecord.swift` |
| `DownloadRecord` | `DownloadRecord.swift` |
| `ContentBlockerWhitelistRecord` | `ContentBlockerWhitelistRecord.swift` |

---

## History Database

**Singleton**: `HistoryDatabase.shared` (`Storage/HistoryDatabase.swift`)

Deliberately separate from the session database for privacy (incognito spaces never write to it) and to allow independent history clearing.

### Tables

#### `historyURL`

Unique URLs with aggregate visit stats.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY (auto-increment) | Row ID |
| `url` | TEXT | NOT NULL, UNIQUE | Full URL |
| `title` | TEXT | NOT NULL | Most recent page title |
| `faviconURL` | TEXT | | Most recent favicon URL |
| `visitCount` | INTEGER | NOT NULL | Total visit count |
| `lastVisitTime` | DOUBLE | NOT NULL | Unix timestamp of last visit |

Index: `historyURL_lastVisitTime` on `lastVisitTime`

#### `historyVisit`

Individual visit records, scoped to a space.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PRIMARY KEY (auto-increment) | Row ID |
| `urlID` | INTEGER | NOT NULL, FK -> historyURL (CASCADE) | URL reference |
| `spaceID` | TEXT | NOT NULL | Space where the visit occurred |
| `visitTime` | DOUBLE | NOT NULL | Unix timestamp |

Indexes: `historyVisit_urlID`, `historyVisit_visitTime`

#### `historySearch` (FTS5 Virtual Table)

Full-text search index synchronized with `historyURL`.

| Column | Source |
|--------|--------|
| `url` | historyURL.url |
| `title` | historyURL.title |

Tokenizer: `unicode61` (handles international text)

### Key Behaviors

**Recording visits**: Uses `INSERT ... ON CONFLICT DO UPDATE ... RETURNING id` to upsert the URL and get the row ID in a single query. The visit is then inserted referencing that URL.

**Deduplication**: TabStore maintains an in-memory cache (`"url|spaceID" -> timestamp`). If the same URL+space combination is recorded within 30 seconds, the duplicate is skipped.

**Search**: Queries tokenize input and use FTS5 `MATCH` with prefix matching (`term*`). Results are ranked by FTS relevance and visit count, scoped to the querying space.

**Expiration**: On app launch, visits older than 90 days are deleted. Orphaned URLs (no remaining visits) are cleaned up in the same transaction.

---

## In-Memory Model Classes

The database records are plain structs. The live in-memory model uses richer classes:

| Class | Purpose | Key State |
|-------|---------|-----------|
| `Space` | Workspace container | `tabs: [BrowserTab]`, `pinnedTabs: [BrowserTab]`, `pinnedFolders: [PinnedFolder]`, `profile: Profile?` |
| `BrowserTab` | Tab with optional WebView | `@Published` properties for title, url, loading, favicon, audio; sleep/wake lifecycle |
| `Profile` | Browser settings | `lazy var dataStore: WKWebsiteDataStore` (per-profile or non-persistent) |
| `PinnedFolder` | Folder in pin hierarchy | `parentFolderID`, `isCollapsed`, `sortOrder` |

### Record <-> Model Conversion

- **Save**: `TabStore.saveNow()` converts in-memory models to records and writes them
- **Restore**: `TabStore.restoreSession()` loads records from DB and constructs model objects
- **Profile**: `Profile.toRecord()` and `Profile.from(record:)` handle conversion

The selected tab in each space gets a live `WKWebView` on restore. All other tabs are created in a sleeping state (no WebView) with cached `interactionState` for later restoration.
