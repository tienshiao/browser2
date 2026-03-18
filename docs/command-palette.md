# Command Palette

The command palette is Detour's unified interface for URL entry, tab switching, history search, and web search suggestions.

## Two Modes

The palette operates in two modes, controlled by `commandPaletteNavigatesInPlace`:

| Mode | Trigger | Behavior |
|------|---------|----------|
| **New tab** | Cmd+T | Opens a new tab with the entered URL/search |
| **Navigate in place** | Cmd+L, or clicking the faux address bar | Navigates the current tab to the entered URL/search |

Both modes use the same `CommandPaletteView` and `SuggestionProvider`.

## UI Structure

```
CommandPaletteView (full-window overlay)
  +-- GlassContainerView (frosted glass popup, 500px wide)
       +-- Search icon (magnifying glass)
       +-- CommandPaletteTextField (text input)
       +-- Separator line
       +-- NSScrollView + NSTableView (suggestion list, max 6 visible rows)
```

The palette is displayed as an overlay on top of the content area. Clicking outside the glass container dismisses it. Pressing Escape also dismisses.

### Positioning

- **Centered** (default): vertically centered in the window assuming max suggestion height (6 rows), horizontally centered
- **Anchored**: when opened from the faux address bar, positioned at the address bar's location. Switches to centered mode if the user clears the input.

## Suggestion Pipeline

`SuggestionProvider` merges three sources:

### 1. Open Tabs (max 3)

Searches across all spaces' tabs (both regular and pinned) for URL or title matches against the query. Results show a "Switch to Tab" badge. Activating switches to the matching tab's space and selects it.

### 2. History Search (max 8)

Uses the history database's FTS5 index. Queries are tokenized and matched with prefix expansion (`term*`). Results are ranked by FTS relevance and visit count, scoped to the active space. URLs already shown as open tabs are excluded.

### 3. Web Search Suggestions (max 4)

Fetched asynchronously from the profile's configured search engine API. Can be disabled per-profile via `searchSuggestionsEnabled`. The search engine is configured in the profile (Google, DuckDuckGo, Bing, Yahoo, Ecosia, Kagi).

### Default Suggestions

When the palette opens with an empty query, `defaultSuggestions()` shows recent history for the active space (up to 12 entries), with open tabs promoted to show as "Switch to Tab" items.

### Debouncing

Text input is debounced at 150ms before triggering suggestion fetches. Each fetch cancels the previous async task to prevent stale results.

## Suggestion Types

```swift
enum SuggestionItem {
    case historyResult(url: String, title: String, faviconURL: String?)
    case openTab(tabID: UUID, spaceID: UUID, url: String, title: String, favicon: NSImage?)
    case searchSuggestion(text: String)
}
```

## Activation

When a suggestion is selected (Enter or click):

| Type | Action |
|------|--------|
| `historyResult` | Submit the URL to the delegate |
| `searchSuggestion` | Submit the search text to the delegate |
| `openTab` | Request tab switch via `didRequestSwitchToTab` delegate method |

The delegate (`BrowserWindowController`) then either navigates the current tab or creates a new one, depending on the mode.

For raw text input (no suggestion selected), the delegate receives the text and determines whether it's a URL (loads directly) or a search query (wraps in the search engine URL).

## Keyboard Navigation

- **Up/Down arrows**: Move through suggestions with visual highlight
- **Enter**: Activate selected suggestion, or submit text if none selected
- **Escape**: Dismiss palette

## Delegate Protocol

```swift
protocol CommandPaletteDelegate: AnyObject {
    func commandPalette(_ palette: CommandPaletteView, didSubmitInput input: String)
    func commandPaletteDidDismiss(_ palette: CommandPaletteView)
    func commandPalette(_ palette: CommandPaletteView, didRequestSwitchToTab tabID: UUID, in spaceID: UUID)
}
```

## Integration with Sidebar

The `FauxAddressBar` in the sidebar displays the current tab's hostname as a read-only label. Clicking it opens the command palette in "navigate in place" mode, anchored at the address bar's position, pre-filled with the current URL.
