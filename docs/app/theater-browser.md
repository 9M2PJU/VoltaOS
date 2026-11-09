# Theater, Browser and Web apps

## Theater

A grid launcher for video streaming services, which open in the built-in browser
(Qt WebEngine) inside the UI:

**YouTube · Netflix · Prime Video · Disney+ · Paramount+**

- Tap a tile to open the service; **back** at the top left returns to the launcher.
- You need your own accounts for each service. Music that is playing stops by itself when a
  video starts, and the widget's play button resumes it.
- **Tile images**: put the PNGs (`youtube.png`, `netflix.png`, `prime.png`, `disney.png`,
  `paramount.png`) in `assets/theater/` to replace the labels.
- The header has a menu to switch to **Arcade** and **Toybox**.

## Browser

A full-page car-style browser:

- address bar with **back / forward**, **reload** and URL; type a search and use
  "**Search "…" on Google**";
- **Favorites**: tap ☆ to add the page;
- **Add to apps**: turns the site into a **web app** (see below);
- Google logins work here too.

## Web apps

Sites added from the Browser appear **at the top of the drawer** and open full screen like
an app, without an address bar: at the top only back, icon, name and reload. To remove them,
reopen them in the Browser and use *Add to apps* again ("Removed from apps"). The list is saved to disk.
