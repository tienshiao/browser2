# MyBrowser

A native macOS web browser built with Swift and WebKit.

## Features

- **Spaces** — Organize tabs into color-coded workspaces, each with isolated cookie/storage via separate `WKWebsiteDataStore` instances. Swipe between spaces in the sidebar.
- **Command Palette** — Cmd+T for new tab, Cmd+L to navigate. Searches open tabs, browsing history (FTS5), and web suggestions in one unified input.
- **Multi-Window** — Each window tracks its own active space. WebView ownership transfers automatically on window focus; inactive windows show tab snapshots.
- **Incognito** — Private browsing with non-persistent data stores. No history recorded. Cleaned up on window close.
- **Session Restore** — Tabs persist across launches with full scroll position and form state via WebKit interaction state archiving.
- **Find in Page** — Cmd+F with match counting and prev/next navigation.
- **Tab Management** — Drag-and-drop reordering, close tabs, reopen recently closed tabs (Cmd+Z).
- **Sidebar Auto-Hide** — Toggle sidebar auto-hide; reopens on edge hover.

## Requirements

- macOS 14.0+
- Xcode with Swift 5.10
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Getting Started

```bash
# Generate the Xcode project
xcodegen generate

# Build
xcodebuild -scheme MyBrowser -configuration Debug build

# Run tests
xcodebuild -scheme MyBrowserTests -configuration Debug test
```

Or open `MyBrowser.xcodeproj` in Xcode after running `xcodegen generate`.

## Dependencies

- [GRDB.swift](https://github.com/groue/GRDB.swift) — SQLite database for session and history storage
