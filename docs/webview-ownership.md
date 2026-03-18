# WebView Ownership & Multi-Window

The most critical architectural invariant in Detour: **only one window at a time "owns" a tab's WKWebView**. Non-owning windows display a static snapshot image.

## Why

WebKit's `WKWebView` can only have one superview. When multiple windows need to display the same tab (because spaces are global but windows are independent), the non-owning windows need an alternative. Detour uses `NSImageView` snapshots as that alternative.

## Ownership State

Each `BrowserWindowController` tracks:

```swift
private var ownsWebView = false          // Does this window own the displayed tab's WebView?
private var snapshotImageView: NSImageView?  // Fallback display when not owning
private var localSnapshot: NSImage?      // Cached snapshot image
```

A `BrowserTab` has:

```swift
private(set) var webView: WKWebView?     // nil when sleeping
```

## Transfer Mechanism

When a window becomes the key window (gains focus):

1. `NSWindow.didBecomeKeyNotification` fires
2. The window posts `Notification.Name.webViewOwnershipChanged`
3. **All windows** receive this notification and re-evaluate ownership
4. The newly focused window takes ownership: attaches the tab's `webView` to its `contentContainerView`
5. Other windows showing the same tab switch to displaying `snapshotImageView`

Before releasing the WebView, the departing owner takes a snapshot via `tab.takeSnapshot()` and caches it locally for display.

## Snapshot System

```
tab.takeSnapshot(completion:)
  -> webView.takeSnapshot(with: nil)
     -> completion(NSImage?)
```

Snapshots are taken:
- When a window loses WebView ownership (before the WebView is moved)
- When switching tabs within a window (snapshot of the departing tab)
- On demand for peek overlays

If a tab's WebView is nil (sleeping) or unavailable, the snapshot is nil and the window shows an empty state.

## Sleeping Tabs

Sleeping is separate from ownership. A sleeping tab has `webView == nil`:

```
sleep()
  1. Serialize webView.interactionState -> cachedInteractionState (Data)
  2. Remove KVO observers, cancel Combine subscriptions
  3. webView.removeFromSuperview()
  4. self.webView = nil
  5. isSleeping = true

wake()
  1. Create fresh WKWebView via space.makeWebViewConfiguration()
  2. Restore interactionState OR reload URL
  3. Re-setup KVO observers and Combine subscriptions
  4. isSleeping = false
```

When a window selects a sleeping tab, `wake()` is called before the WebView is attached. This means the window that selects the tab becomes its owner automatically (it's the one that created the new WebView).

## Interaction State

WebKit's `interactionState` property captures the full browsing state (scroll position, back/forward history, form data). Detour serializes it via `NSKeyedArchiver` for:

- **Session persistence** -- saved to `tab.interactionState` BLOB in the database
- **Sleep/wake** -- cached in memory as `cachedInteractionState: Data?`
- **Closed tab restoration** -- stored in `closedTab.interactionState`

The `currentInteractionStateData()` method returns the live state from the WebView if available, or falls back to the cached data if the tab is sleeping.

## Rules of Thumb

1. **Never assume `tab.webView` is non-nil** -- it's nil for sleeping tabs and for tabs in non-owning windows
2. **Never add a tab's WebView to multiple superviews** -- always check/transfer ownership first
3. **The window that calls `selectTab()` after becoming key gets ownership** -- this is the standard flow
4. **Snapshot before releasing** -- always capture a snapshot before moving or removing a WebView from a window
5. **Wake before display** -- selecting a sleeping tab triggers `wake()`, which creates a fresh WebView
