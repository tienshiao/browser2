# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Regenerate Xcode project (required after adding/removing files)
xcodegen generate

# Build
xcodebuild -scheme MyBrowser -configuration Debug build

# Run tests
xcodebuild -scheme MyBrowserTests -configuration Debug test

# Run a single test
xcodebuild -scheme MyBrowserTests -configuration Debug test -only-testing:MyBrowserTests/SuggestionProviderTests/testExample
```

## Architecture

macOS native browser (Swift 5.10, macOS 14+) using WebKit. Organized around **Spaces** (workspaces with isolated cookie stores) containing **Tabs**.

### Key Architectural Decisions

**State management**: `TabStore` singleton owns all spaces and tabs. Controllers observe changes via `TabStoreObserver` protocol (not Combine). `BrowserTab` exposes `@Published` properties for per-tab reactive updates consumed by `BrowserWindowController`.

**WebView ownership**: Only one window at a time "owns" a tab's WKWebView. Other windows showing the same tab display a snapshot (NSImageView). Ownership transfers on window focus via `webViewOwnershipChanged` notification. This is critical — never assume a tab's webView is attached.

**Two databases**: Session state (`Database.swift` — spaces, tabs, closed tabs) is separate from browsing history (`HistoryDatabase.swift` — URLs, visits with FTS5 search). Both use GRDB with SQLite.

**Per-window space state**: Each `BrowserWindowController` tracks its own `activeSpaceID`. Spaces are global in `TabStore` but the active space is per-window.

**Incognito**: Creates an isolated `Space` with a non-persistent `WKWebsiteDataStore`. No history recording. Space removed on window close.

### Component Relationships

```
BrowserWindowController (per window)
  ├── TabSidebarViewController (sidebar: spaces, tabs, nav, faux address bar)
  │     └── FauxAddressBar (read-only hostname display, opens CommandPalette on click)
  ├── CommandPaletteView (URL input + suggestions overlay)
  │     └── SuggestionProvider (merges: open tabs + history FTS + web search)
  ├── FindBarView (Cmd+F find-in-page)
  └── WKWebView (owned tab) or NSImageView (snapshot)

TabStore.shared (singleton)
  ├── Space[] (each with tabs[], WKWebsiteDataStore)
  ├── TabStoreObserver[] (weak references)
  ├── Database.shared (session persistence, 1s debounced saves)
  └── HistoryDatabase.shared (visit recording, 30s dedup window)
```

### Delegate Flow

Sidebar actions flow through `TabSidebarDelegate` → `BrowserWindowController` → `TabStore`. The command palette uses `CommandPaletteDelegate`. The palette has two modes: "new tab" (Cmd+T) and "navigate in place" (Cmd+L or clicking the faux address bar), controlled by `commandPaletteNavigatesInPlace`.

### Tab List Offset

The table view's row 0 is always the "New Tab" cell. Actual tabs start at row 1. All index conversions between table rows and tab array indices account for this +1 offset.
