# Podcasts

**iTunes** catalog and RSS feeds, played by `podcast_service.py` (port 8094) with mpv.
No account and no key: subscriptions and history stay on the PC.

## Tabs

- **Home** — *Up next* (episodes to resume or listen to, with time left), *Latest episodes*,
  *Most listened*, featured episodes and categories.
- **New** — new episodes of the podcasts you are subscribed to. If you have no subscriptions an
  invitation appears to search for one and tap **✓** to subscribe.
- **Charts** — **Top podcasts** and **Top episodes**, with the choice of **category** (News,
  Society, Comedy…) and *All categories*.
- **Library** — **Subscribed**, **Saved** (bookmarked episodes) and **History**.

## Search

The magnifier searches **podcasts, episodes and topics**. If you do too many searches in a row a
notice appears: iTunes limits requests, try again after a few seconds.

## A podcast's page

Cover, author, **Subscribe / Subscribed**, **Listen**, the **Trailer**, **Hosts and guests**, the episodes
(*Show all*, order **newest first / oldest first**) and related categories.

On each episode you can: play it, **save** it (bookmark), mark it as **listened** or **to
listen**. The episode count and the progress bar tell you where you left off.

## Player

It opens full screen by tapping the widget or the player icon:

- play/pause, **skip forward/back** a few seconds, seeking within the episode;
- playback **speed** (cycles through the values, shown as `1×`, `1.25×`…; you also find it in the widget);
- **sleep timer**: it stops by itself after the chosen time ("Stops in …");
- **queue**: the following episodes of the series ("Up next from…").

Title, cover and controls also reach the **music widget** (system player "Podcast").

## If it does not start

- "Podcast service starting…": the service starts a few seconds after the interface, it retries by itself.
- "Playback not available (python-mpv missing)": install the [Python dependencies](../installation.md#python-requirementstxt).
