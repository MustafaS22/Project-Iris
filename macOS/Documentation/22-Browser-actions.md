# Browser searches and links

Iris can open a web search or an http/https address in Safari or another registered browser. Ask “Search for Swift tutorials in Safari” or “Open wikipedia.org in Firefox.” Search queries are encoded as a single Google query, preserving Unicode, punctuation and literal plus signs.

Settings → Computer → Open links and searches in stores a browser preference. A browser named in a request overrides it; Default browser follows macOS. Iris discovers URL handlers from macOS and matches their name or bundle identifier. A missing requested browser reports an error instead of silently opening another app.

searchWeb and openURL follow the existing action permission setting. They open browser pages only: they do not extract page contents, search results, browser tabs, cookies or history. Unsupported URL schemes and embedded credentials are rejected.

The implementation uses Apple’s [NSWorkspace URL-opening API](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:configuration:completionhandler:)) and registered application discovery.
