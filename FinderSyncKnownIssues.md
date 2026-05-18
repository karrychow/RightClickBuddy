FinderSync known issues

- iCloud Drive (File Provider) directories may not render FinderSync extension menu items even when Finder does call menu(for:) and the extension returns a non-empty NSMenu.
  - Observed behavior:
    - Logs show menu(for:) called with creationDir under ~/Library/Mobile Documents/com~apple~CloudDocs
    - Extension returns a menu with items (itemCount > 0)
    - Finder UI still does not show the extension menu in some contexts (root and/or child directories).
  - Current workaround (debug/experimental):
    - Add a top-level no-op NSMenuItem ("RightClickBuddy") as an anchor before adding real items.
    - Finder is more likely to render the extension menu when at least one explicit action item exists at the top level.
  - Follow-up:
    - Re-evaluate whether to keep the anchor item, switch to a submenu-based UI, or provide alternative entry points (e.g. Services/Quick Action/Toolbar) for File Provider locations.
