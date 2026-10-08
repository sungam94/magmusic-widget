#!/usr/bin/env python3
"""Rewrites the saved Music Assistant answers the MAKit tests read, so they carry no personal data.

    scripts/anonymize_fixtures.py [fixtures-dir]     (default: MAKit/Tests/MAKitTests/Fixtures)

The fixtures are real answers from a Music Assistant server. This script keeps their structure and every value
the tests depend on (availability, hidden flags, playback states, volumes, durations, timestamps, which items
have images) and replaces everything that identifies a home, a person or their taste:

- player ids, by shape: MAC-shaped ids become 02:00:00:00:00:NN, WiiM UUIDs
  wiim_uuid:00000000-0000-0000-0000-0000000000NN, universal-player ids up00000000NN, AirPlay ids
  ap0200000000NN, and any other id playerNN. The same map is used wherever a player id appears
  (queue ids, active sources, groups).
- IP addresses become 192.0.2.NN (the documentation range), player names generic room names. A device
  brand in a name (WiiM, HiFiBerry, ...) is kept, because it is not personal and the tests pick
  speakers by it.
- tracks, artists and albums become Track N, Artist N and Album N; durations and timestamps stay.
- provider instance ids become <domain>--test, TIDAL and SoundCloud user ids and TIDAL mix ids
  become fake numbers, image paths and proxy ids become fake values (our own covers keep the
  "sbcover_" prefix the widget looks for).
- recommendation rows: a row named after the account becomes "Mixed for listener", Blend playlists
  "You + <name>", playlists with personal names (artist mixes and the like) "Mix N"; the owner
  field becomes the service name.
- server_info gets a zero server id, http://192.0.2.10:8095 and the name "Music Assistant".

Fields the widget's decoder never reads are dropped, apart from a few harmless ones kept on purpose,
so the tests still prove that unknown keys are ignored. Every value is mapped by order of appearance,
so the output is the same on every run, and running the script on its own output changes nothing.
"""

import json
import re
import sys
from pathlib import Path

ROOMS = [
    "Living Room", "Kitchen", "Office", "Bedroom", "Hallway", "Bathroom", "Studio", "Garage", "Attic",
    "Dining Room", "Guest Room", "Basement", "Balcony", "Library", "Workshop", "Porch", "Garden", "Loft",
]
BRANDS = ["WiiM", "HiFiBerry", "Sonos", "HomePod", "Chromecast", "Echo"]
FRIENDS = ["Alex", "Sam", "Robin", "Kim", "Jo", "Charlie", "Max", "Lee", "Noa", "Pat"]
SERVICE_NAMES = {"tidal": "TIDAL", "soundcloud": "SoundCloud"}

# Playlist names every account of a service has; anything else in a playlist name is treated as personal.
GENERIC_PLAYLIST = re.compile(
    r"^(Discover Weekly|Release Radar|daylist|On Repeat|Repeat Rewind|Daily Mix \d+|My Daily Discovery"
    r"|My New Arrivals|My Mix \d+|Your Mix \d+|Daily Drops|Weekly Wave|Mix \d+|You \+ \w+)$"
)
OUR_COVER = "sbcover_"
SPOTIFY_PREFIX = "Spotify · "


class Maps:
    """Deterministic replacement values: the n-th distinct original of a kind gets number n."""

    def __init__(self):
        self.maps = {}

    def get(self, kind, original, make):
        table = self.maps.setdefault(kind, {})
        if original not in table:
            table[original] = make(len(table) + 1)
        return table[original]


M = Maps()


def player_id(original):
    if original is None:
        return None

    def make(n):
        if re.fullmatch(r"([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}", original):
            return f"02:00:00:00:00:{n:02x}"
        if original.startswith("wiim_uuid:"):
            return f"wiim_uuid:00000000-0000-0000-0000-{n:012d}"
        if re.fullmatch(r"up[0-9a-f]{8,10}", original):
            return f"up{n:010d}"
        if re.fullmatch(r"ap[0-9a-f]{12}", original):
            return f"ap0200000000{n:02x}"
        return f"player{n:02d}"

    return M.get("player", original, make)


def ip(original):
    if original is None:
        return None
    return M.get("ip", original, lambda n: f"192.0.2.{100 + n}")


def player_name(pid, original):
    def make(n):
        room = ROOMS[(n - 1) % len(ROOMS)]
        brand = next((b for b in BRANDS if b.lower() in (original or "").lower()), None)
        return f"{room} {brand}" if brand else room

    return M.get("player_name", pid, make)


def scrub(text):
    """Replaces account-specific parts inside ids, URIs and paths."""
    if not isinstance(text, str):
        return text

    def instance(m):
        domain = m.group(1)
        return M.get(f"instance {domain}", m.group(0), lambda n: f"{domain}--test" if n == 1 else f"{domain}--test{n}")

    def user(m):
        return m.group(1) + M.get("user", m.group(2), lambda n: str(10000000 + n))

    text = re.sub(r"\b([a-z_]+)--(?!test\b)([A-Za-z0-9]+)", instance, text)
    text = re.sub(r"(system-playlists:[a-z-]+:)(\d+)", user, text)
    text = re.sub(r"(^|/)(\d{5,})(?=_)", user, text)
    text = re.sub(r"\bmix_([0-9a-f]{20,})", lambda m: "mix_" + M.get("mix", m.group(1), lambda n: f"{n:030x}"), text)
    text = re.sub(
        r"layout_section_([A-Za-z0-9]+)",
        lambda m: "layout_section_" + M.get("section", m.group(1), lambda n: f"fake{n:02d}"),
        text,
    )
    return text


def item_id(provider, original):
    """Library ids are the server's own row numbers and stay; ids from a streaming service are replaced."""
    if original is None or provider == "library" or provider == "spotify_bridge":
        return original
    if "system-playlists" in original:
        return scrub(original)
    return M.get("item_id", original, lambda n: str(1000000 + n) if original.isdigit() else f"item{n}")


def uri(original, old_id=None, new_id=None):
    """A media URI with its provider scrubbed and, when it names the item `old_id`, the item's new id."""
    m = re.fullmatch(r"([^:]+)://([a-z_]+)/(.+)", original or "")
    if not m:
        return scrub(original)
    provider, kind, id_part = m.groups()
    return f"{scrub(provider)}://{kind}/{new_id if id_part == old_id else scrub(id_part)}"


def image(img):
    if img is None:
        return None
    path = img.get("path") or ""

    def make(n):
        if path.startswith(OUR_COVER):
            return f"{OUR_COVER}{n:016x}_{n:016x}.jpg"
        if path.startswith("/data/"):
            return f"/data/playlist_metadata_images/{n}_thumb.jpg"
        return f"https://img.example/cover/{n}.jpg"

    out = {
        "type": img.get("type"),
        "path": M.get("image_path", path, make),
        "provider": scrub(img.get("provider")),
        "remotely_accessible": img.get("remotely_accessible"),
    }
    if "proxy_id" in img:
        proxy = img.get("proxy_id")
        out["proxy_id"] = None if proxy is None else M.get("proxy", proxy, lambda n: f"{n:032x}")
    return out


def metadata(meta):
    if meta is None:
        return None
    out = {"images": None if meta.get("images") is None else [image(i) for i in meta["images"]]}
    if "explicit" in meta:
        out["explicit"] = meta["explicit"]
    return out


def named(kind, label, ref):
    """An artist or album reference: a generic name, a fake id, and the service it came from."""
    if ref is None:
        return None
    provider = ref.get("provider")
    new_id = item_id(provider, ref.get("item_id"))
    name = M.get(kind, ref.get("name"), lambda n: f"{label} {n}")
    return {
        "item_id": new_id,
        "provider": scrub(provider),
        "name": name,
        "sort_name": name.lower(),
        "uri": uri(ref.get("uri"), ref.get("item_id"), new_id),
        "media_type": ref.get("media_type"),
    }


def track(media):
    if media is None:
        return None
    provider = media.get("provider")
    new_id = item_id(provider, media.get("item_id"))
    name = M.get("track", media.get("name"), lambda n: f"Track {n}")
    out = {
        "item_id": new_id,
        "provider": scrub(provider),
        "name": name,
        "version": "",
        "sort_name": name.lower(),
        "uri": uri(media.get("uri"), media.get("item_id"), new_id),
        "is_playable": media.get("is_playable"),
        "media_type": media.get("media_type"),
        "duration": media.get("duration"),
        "favorite": media.get("favorite"),
        "metadata": metadata(media.get("metadata")),
        "artists": [named("artist", "Artist", a) for a in media.get("artists") or []],
    }
    if "album" in media:
        out["album"] = named("album", "Album", media.get("album"))
    return out


def queue_item(item):
    if item is None:
        return None
    media = track(item.get("media_item"))
    if media:
        name = f"{', '.join(a['name'] for a in media['artists'])} - {media['name']}"
    else:
        name = M.get("track", item.get("name"), lambda n: f"Track {n}")
    return {
        "queue_id": player_id(item.get("queue_id")),
        "queue_item_id": M.get("queue_item", item.get("queue_item_id"), lambda n: f"{n:032x}"),
        "name": name,
        "duration": item.get("duration"),
        "sort_index": item.get("sort_index"),
        "media_item": media,
        "image": image(item.get("image")),
        "index": item.get("index"),
        "available": item.get("available"),
    }


PLAYER_KEPT = ["type", "available", "playback_state", "elapsed_time", "elapsed_time_last_updated", "powered",
               "volume_level", "volume_muted", "enabled", "hide_in_ui", "icon", "state", "supported_features"]


def player(p):
    pid = player_id(p["player_id"])
    name = player_name(pid, p.get("display_name") or p.get("name"))
    out = {"player_id": pid, "provider": p.get("provider"), "name": name, "display_name": name}
    for key in PLAYER_KEPT:
        if key in p:
            out[key] = p[key]
    info = p.get("device_info")
    out["device_info"] = None if info is None else {"ip_address": ip(info.get("ip_address"))}
    for key in ["active_source", "synced_to"]:
        if key in p:
            out[key] = player_id(p[key])
    for key in ["group_members", "can_group_with"]:
        if key in p:
            out[key] = [player_id(x) for x in p[key] or []]
    return out


QUEUE_KEPT = ["active", "available", "items", "shuffle_enabled", "repeat_mode", "current_index", "elapsed_time",
              "elapsed_time_last_updated", "playback_speed", "state"]


def queue(q):
    qid = player_id(q["queue_id"])
    out = {"queue_id": qid, "display_name": M.maps.get("player_name", {}).get(qid) or player_name(qid, None)}
    for key in QUEUE_KEPT:
        if key in q:
            out[key] = q[key]
    out["current_item"] = queue_item(q.get("current_item"))
    out["next_item"] = queue_item(q.get("next_item"))
    return out


ROW_KEPT = ["version", "is_playable", "media_type", "image", "icon", "subtitle", "type", "enabled_by_default",
            "supports_provider_filter"]


def row(r):
    name = r["name"]
    if name.lower().startswith("mixed for "):
        name = "Mixed for listener"
    out = {"item_id": scrub(r["item_id"]), "provider": scrub(r["provider"]), "name": name, "sort_name": name.lower(),
           "uri": scrub(r.get("uri")), "path": scrub(r.get("path"))}
    for key in ROW_KEPT:
        if key in r:
            out[key] = r[key]
    if not re.fullmatch(r"From [\w ]+ • \d+ items", out.get("subtitle") or ""):
        out["subtitle"] = None   # a subtitle can name a playlist or a person; only the generic kind stays
    return out


def playlist_name(name):
    prefix = SPOTIFY_PREFIX if name.startswith(SPOTIFY_PREFIX) else ""
    base = name[len(prefix):]
    if GENERIC_PLAYLIST.match(base):
        return name
    if " + " in base:
        return prefix + "You + " + M.get("friend", base, lambda n: FRIENDS[(n - 1) % len(FRIENDS)])
    return prefix + M.get("playlist", base, lambda n: f"Mix {n}")


def playlist(item):
    provider = item.get("provider")
    new_id = item_id(provider, item.get("item_id"))
    name = playlist_name(item["name"])
    domain = (scrub(provider) or "").split("--")[0]
    out = {
        "item_id": new_id,
        "provider": scrub(provider),
        "name": name,
        "version": item.get("version", ""),
        "sort_name": name.lower(),
        "uri": None if item.get("uri") is None else uri(item["uri"], item.get("item_id"), new_id),
        "is_playable": item.get("is_playable"),
        "media_type": item.get("media_type"),
        "owner": SERVICE_NAMES.get(domain, "Spotify"),
        "is_editable": item.get("is_editable"),
        "is_dynamic": item.get("is_dynamic"),
        "favorite": item.get("favorite"),
        "metadata": metadata(item.get("metadata")),
    }
    if "image" in item:
        out["image"] = image(item["image"])
    return out


SERVER_KEPT = ["server_version", "schema_version", "min_supported_schema_version", "homeassistant_addon",
               "onboard_done", "status", "has_remote_access"]


def server_info(s):
    neutral = {"server_id": "0" * 32, "base_url": "http://192.0.2.10:8095", "internal_url": "http://192.0.2.10:8095",
               "external_url": None, "name": "Music Assistant"}
    return {key: neutral.get(key, value) for key, value in s.items() if key in neutral or key in SERVER_KEPT}


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "MAKit/Tests/MAKitTests/Fixtures"

    def load(name):
        return json.loads((root / f"{name}.json").read_text(encoding="utf-8"))

    def save(name, data):
        (root / f"{name}.json").write_text(json.dumps(data, ensure_ascii=False) + "\n", encoding="utf-8")

    # Order matters: players first, so ids, addresses and names are numbered by the players list.
    players = load("players_all")
    for p in players["result"]:
        player_id(p["player_id"])   # number the players in list order before any reference to them
    players["result"] = [player(p) for p in players["result"]]
    queues = load("queues_all")
    queues["result"] = [queue(q) for q in queues["result"]]
    rows = load("recommendations")
    items = load("recommendation_items")
    new_items = {}
    for r in rows["result"]:
        old_key = f"{r['provider']}|{r['item_id']}"
        new_row = row(r)
        if old_key in items:
            new_items[f"{new_row['provider']}|{new_row['item_id']}"] = [playlist(i) for i in items[old_key]]
    for key in items:
        if key not in {f"{r['provider']}|{r['item_id']}" for r in rows["result"]}:
            provider, _, row_id = key.partition("|")
            new_items[f"{scrub(provider)}|{scrub(row_id)}"] = [playlist(i) for i in items[key]]
    rows["result"] = [row(r) for r in rows["result"]]
    info = server_info(load("server_info"))

    save("players_all", players)
    save("queues_all", queues)
    save("recommendations", rows)
    save("recommendation_items", new_items)
    save("server_info", info)


if __name__ == "__main__":
    main()
