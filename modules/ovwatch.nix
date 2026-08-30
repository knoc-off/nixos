# ov-berlin.info original-language showtime watcher.
#
# Subscriptions are managed over ntfy on a single topic: publish
# "+spiderman imax ov" to watch a film, "?" to list, "-" to drop, "=" to
# replace filters. The daemon records the ids of its own published messages
# and skips them when draining, so sharing one topic does not feed back.
#
# The site is a static Astro build. Each /movies/<id>-<slug>/ page embeds its
# screenings as schema.org ScreeningEvent in one application/ld+json block, so
# no HTML scraping is involved. /diag.json carries a generatedAt stamp that
# changes only on rebuild, which short-circuits the loop: a quiet tick costs
# one small JSON request, and movie pages are pulled only when it changes.
#
# Scoring is optional and entirely local taste: hall quality, how much you
# like the place, its reviews, minus travel cost. The feed carries cinema and
# format but never a hall, so a hall is only identified when a format pins it
# (IMAX, 70mm) or the cinema has a single rated hall; otherwise the range
# across candidates is shown. Thresholding and ordering both use the
# optimistic end, since discarding a good screening over an ambiguous hall is
# the expensive error.
#
# A new subscription records every showing as already-seen, not just the ones
# matching its filters, and notifies a one-line summary. Otherwise subscribing
# to a busy film fires seventy notifications at once, and widening a filter
# later would do it again.
{ ... }:
{
  nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        getExe
        literalExpression
        mkEnableOption
        mkIf
        mkOption
        optional
        types
        ;
      cfg = config.services.ovwatch;

      # The stream's idle read timeout doubles as the sweep clock, so it has to
      # be shorter than the sweep interval or sweeps would drift late. Capped
      # at 5 min so a silently dropped connection is noticed reasonably soon.
      readTimeout = lib.min 300 cfg.siteIntervalSeconds;

      # Unset options are dropped rather than serialised as null, so the
      # Python side can rely on a missing key meaning "inherit".
      pruneNulls = lib.filterAttrs (_: v: v != null);

      scoringJson = builtins.toJSON {
        inherit (cfg.scoring)
          enable
          weights
          neutral
          minScore
          ;
        cinemas = lib.mapAttrs (
          _: c:
          pruneNulls {
            inherit (c)
              match
              bias
              review
              travel
              ;
            halls = map (
              h:
              pruneNulls {
                inherit (h)
                  name
                  score
                  formats
                  bias
                  review
                  travel
                  ;
              }
            ) c.halls;
          }
        ) cfg.scoring.cinemas;
      };

      pollScript =
        pkgs.writers.writePython3Bin "ovwatch"
          {
            flakeIgnore = [ "E501" ];
          }
          ''
            import difflib
            import html
            import json
            import os
            import re
            import sys
            import time
            import urllib.error
            import urllib.parse
            import urllib.request

            BASE = os.environ.get("OVW_BASE", "https://ov-berlin.info")
            UA = os.environ.get("OVW_UA", "ovwatch/1.0 (personal showtime watcher)")
            NTFY_URL = os.environ.get("OVW_NTFY_URL", "https://ntfy.niko.ink")
            TOPIC = os.environ.get("OVW_NTFY_TOPIC", "ovwatch")
            MAX_SUBS = int(os.environ.get("OVW_MAX_SUBS", "50"))
            CRAWL_DELAY = float(os.environ.get("OVW_CRAWL_DELAY", "1"))
            SITE_INTERVAL = float(os.environ.get("OVW_SITE_INTERVAL", "3600"))
            # Idle read timeout on the command stream. Doubles as the sweep clock, so it
            # must be shorter than SITE_INTERVAL to keep the sweep on schedule.
            READ_TIMEOUT = float(os.environ.get("OVW_READ_TIMEOUT", "300"))
            MAX_BACKOFF = 300
            # Past this many changes at once, collapse into one digest rather than
            # spamming the phone and tripping ntfy's rate limit.
            BATCH_THRESHOLD = 5
            BATCH_LIST = 15

            SCORING = None

            INDEX_TTL = 24 * 3600
            INDEX_FEEDS = [
                "/movies.rss",
                "/movies/coming-soon.rss",
                "/movies/classic.rss",
                "/movies/open-air.rss",
            ]
            SELF_ID_KEEP = 300

            LANGS = {"ov", "omu", "omeu"}
            KNOWN_FMTS = {"imax", "3d", "2d", "70mm", "35mm", "screenx", "isense",
                          "dbox", "4dx", "atmos", "dolby"}
            DAYS = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}
            DAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

            _last_request = [0.0]


            def log(*a):
                print(*a, file=sys.stderr, flush=True)


            def read_credential(name):
                d = os.environ.get("CREDENTIALS_DIRECTORY")
                if not d:
                    return None
                p = os.path.join(d, name)
                if not os.path.exists(p):
                    return None
                with open(p) as f:
                    return f.readline().strip()


            def auth_headers():
                h = {"User-Agent": UA}
                token = read_credential("ntfy-token")
                if token:
                    h["Authorization"] = "Bearer " + token
                return h


            def http_get(url, timeout=30):
                """Returns text, or None on failure. None means "do not touch state",
                as distinct from a successful fetch that contains nothing."""
                wait = CRAWL_DELAY - (time.monotonic() - _last_request[0])
                if wait > 0:
                    time.sleep(wait)
                req = urllib.request.Request(url, headers={
                    "User-Agent": UA,
                    "Accept-Encoding": "identity",
                })
                try:
                    with urllib.request.urlopen(req, timeout=timeout) as resp:
                        if resp.status != 200:
                            log("http %s -> %s" % (url, resp.status))
                            return None
                        return resp.read().decode("utf-8", "replace")
                except (urllib.error.URLError, OSError) as e:
                    log("http %s failed: %s" % (url, e))
                    return None
                finally:
                    _last_request[0] = time.monotonic()


            def site_stamp():
                raw = http_get(BASE + "/diag.json")
                if raw is None:
                    return None
                try:
                    j = json.loads(raw)
                except ValueError:
                    return None
                gen = j.get("general") or j.get("General") or {}
                return gen.get("generatedAt")


            LDJSON_RE = re.compile(
                r'<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>', re.S | re.I)
            CANONICAL_RE = re.compile(r'<link[^>]*rel="canonical"[^>]*href="([^"]+)"', re.I)


            def is_soft_404(page):
                """Unknown slugs return HTTP 200 with canonical -> /404/. Without this
                check they look like "every showing vanished"."""
                m = CANONICAL_RE.search(page)
                return bool(m and "/404" in m.group(1))


            def collect_events(node, out):
                if isinstance(node, dict):
                    if node.get("@type") == "ScreeningEvent":
                        out.append(node)
                    for v in node.values():
                        collect_events(v, out)
                elif isinstance(node, list):
                    for v in node:
                        collect_events(v, out)


            def fetch_showings(slug):
                page = http_get("%s/movies/%s/" % (BASE, slug))
                if page is None:
                    return None
                if is_soft_404(page):
                    log("soft-404 for slug %s" % slug)
                    return None
                raw = []
                for block in LDJSON_RE.findall(page):
                    try:
                        collect_events(json.loads(block), raw)
                    except ValueError:
                        continue
                out = []
                for e in raw:
                    loc = e.get("location") or {}
                    out.append({
                        "start": e.get("startDate") or "",
                        "cinema": (loc.get("name") if isinstance(loc, dict) else "") or "",
                        "version": e.get("subtitleLanguage") or "",
                        "url": e.get("url") or "",
                        "title": e.get("name") or "",
                    })
                return out


            def parse_version(raw):
                lang = None
                fmts = set()
                for t in str(raw or "").split():
                    low = t.lower()
                    if low in LANGS and lang is None:
                        lang = low
                    else:
                        fmts.add(low)
                return {"lang": lang, "fmts": fmts}


            def norm_version(raw):
                return " ".join(sorted(str(raw or "").lower().split()))


            def key(s):
                # Not the url: booking ids get reissued and would fake a new showing.
                return (s["start"], s["cinema"], norm_version(s["version"]))


            def parse_start(s):
                try:
                    return time.strptime(s[:19], "%Y-%m-%dT%H:%M:%S")
                except (ValueError, TypeError):
                    return None


            def is_past(start, cutoff):
                t = parse_start(start)
                return t is not None and time.mktime(t) < cutoff


            def empty_filters():
                return {"langs": set(), "fmts": set(), "cinemas": set(),
                        "after": None, "before": None, "days": set()}


            def matches(s, f):
                v = parse_version(s["version"])
                if f["langs"] and v["lang"] not in f["langs"]:
                    return False
                if f["fmts"] and not f["fmts"].issubset(v["fmts"]):
                    return False
                if f["cinemas"]:
                    low = s["cinema"].lower()
                    if not any(c in low for c in f["cinemas"]):
                        return False
                t = parse_start(s["start"])
                if t is None:
                    return not (f["after"] or f["before"] or f["days"])
                mins = t.tm_hour * 60 + t.tm_min
                if f["after"] is not None and mins < f["after"]:
                    return False
                if f["before"] is not None and mins > f["before"]:
                    return False
                if f["days"] and t.tm_wday not in f["days"]:
                    return False
                return True


            def _hhmm(v):
                m = re.fullmatch(r"(\d{1,2}):(\d{2})", v)
                if not m:
                    return None
                h, mi = int(m.group(1)), int(m.group(2))
                if h > 23 or mi > 59:
                    return None
                return h * 60 + mi


            def is_filter_token(t):
                low = t.lower()
                if low in LANGS or low in KNOWN_FMTS or low in DAYS:
                    return True
                if low in ("weekend", "weekday"):
                    return True
                return bool(re.match(r"^(cinema|after|before|at):", low))


            def parse_filters(toks):
                """Returns (filters, unknown). Unknown tokens are reported back so typos
                are not silently ignored."""
                f = empty_filters()
                unknown = []
                for t in toks:
                    low = t.lower()
                    if low in LANGS:
                        f["langs"].add(low)
                    elif low in KNOWN_FMTS:
                        f["fmts"].add(low)
                    elif low in DAYS:
                        f["days"].add(DAYS[low])
                    elif low == "weekend":
                        f["days"].update({5, 6})
                    elif low == "weekday":
                        f["days"].update({0, 1, 2, 3, 4})
                    elif low.startswith("cinema:"):
                        v = low.split(":", 1)[1].strip()
                        f["cinemas"].add(v) if v else unknown.append(t)
                    elif low.startswith("after:") or low.startswith("at:"):
                        v = _hhmm(low.split(":", 1)[1])
                        unknown.append(t) if v is None else f.__setitem__("after", v)
                    elif low.startswith("before:"):
                        v = _hhmm(low.split(":", 1)[1])
                        unknown.append(t) if v is None else f.__setitem__("before", v)
                    else:
                        unknown.append(t)
                return f, unknown


            def describe(f):
                parts = []
                if f["langs"]:
                    parts.append("/".join(sorted(x.upper() for x in f["langs"])))
                if f["fmts"]:
                    parts.append("+" + "+".join(sorted(f["fmts"])))
                if f["cinemas"]:
                    parts.append("@" + "/".join(sorted(f["cinemas"])))
                if f["days"]:
                    parts.append(",".join(DAY_NAMES[d] for d in sorted(f["days"])))
                if f["after"] is not None:
                    parts.append("after %02d:%02d" % (f["after"] // 60, f["after"] % 60))
                if f["before"] is not None:
                    parts.append("before %02d:%02d" % (f["before"] // 60, f["before"] % 60))
                return " ".join(parts) if parts else "no filters"


            def split_title_and_filters(toks):
                """Anchors on the last recognised filter token and extends backwards, so a
                film whose title contains a filter word ("Weekend", "3D") still resolves.
                An explicit '|' overrides. Always keeps at least one title token."""
                if "|" in toks:
                    i = toks.index("|")
                    return toks[:i], toks[i + 1:]
                last = -1
                for i, t in enumerate(toks):
                    if is_filter_token(t):
                        last = i
                if last <= 0:
                    return toks, []
                i = last
                while i > 1 and is_filter_token(toks[i - 1]):
                    i -= 1
                return toks[:i], toks[i:]


            def serialize_filters(f):
                return {
                    "langs": sorted(f["langs"]),
                    "fmts": sorted(f["fmts"]),
                    "cinemas": sorted(f["cinemas"]),
                    "after": f["after"],
                    "before": f["before"],
                    "days": sorted(f["days"]),
                }


            def deserialize_filters(d):
                return {
                    "langs": set(d.get("langs") or []),
                    "fmts": set(d.get("fmts") or []),
                    "cinemas": set(d.get("cinemas") or []),
                    "after": d.get("after"),
                    "before": d.get("before"),
                    "days": set(d.get("days") or []),
                }


            def default_state():
                return {"generated_at": None, "subs": {}, "seen": {},
                        "index_cache": None, "cmd_since": None, "self_ids": [],
                        "last_site_poll": 0}


            def load_state(path):
                if not os.path.exists(path):
                    return default_state()
                try:
                    with open(path) as f:
                        st = json.load(f)
                except (ValueError, OSError) as e:
                    log("state unreadable (%s), starting fresh" % e)
                    return default_state()
                for k, v in default_state().items():
                    st.setdefault(k, v)
                st["seen"] = {k: {tuple(x) for x in v} for k, v in st["seen"].items()}
                return st


            def save_state(path, st):
                out = dict(st)
                out["seen"] = {k: sorted(list(x) for x in v) for k, v in st["seen"].items()}
                tmp = path + ".tmp"
                with open(tmp, "w") as f:
                    json.dump(out, f, indent=1)
                os.replace(tmp, path)


            def action_header(*pairs):
                """Build an ntfy Actions header from (label, url) pairs.

                Values are single-quoted because the field separator is a comma and
                booking URLs are third-party, so one may well contain one.
                """
                out = []
                for label, url in pairs:
                    if not url:
                        continue
                    out.append("view, '%s', '%s'" % (label.replace("'", ""),
                                                     url.replace("'", "%27")))
                # ntfy caps actions at three per message.
                return "; ".join(out[:3])


            def notify(st, msg, title=None, click=None, tags=None, actions=None):
                h = auth_headers()
                if title:
                    h["Title"] = title
                if click:
                    h["Click"] = click
                if tags:
                    h["Tags"] = tags
                if actions:
                    h["Actions"] = actions
                req = urllib.request.Request(
                    "%s/%s" % (NTFY_URL, TOPIC), data=msg.encode("utf-8"), headers=h)
                try:
                    with urllib.request.urlopen(req, timeout=20) as resp:
                        body = resp.read().decode("utf-8", "replace")
                except (urllib.error.URLError, OSError) as e:
                    log("notify failed: %s" % e)
                    return False
                # Remember our own message id so the single shared topic does not read
                # its own output back as a command.
                try:
                    mid = json.loads(body).get("id")
                    if mid:
                        st["self_ids"] = (st.get("self_ids", []) + [mid])[-SELF_ID_KEEP:]
                except ValueError:
                    pass
                return True


            RSS_ITEM_RE = re.compile(r"<item>(.*?)</item>", re.S)
            RSS_TITLE_RE = re.compile(r"<title>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</title>", re.S)
            RSS_LINK_RE = re.compile(r"<link>(.*?)</link>", re.S)


            def slug_from(url):
                m = re.search(r"/movies/([^/?#]+)", url or "")
                return m.group(1) if m else None


            def title_index(st):
                c = st.get("index_cache")
                if c and (time.time() - c.get("fetched_at", 0)) < INDEX_TTL and c.get("entries"):
                    return c["entries"]
                entries = {}
                ok = False
                for feed in INDEX_FEEDS:
                    raw = http_get(BASE + feed)
                    if raw is None:
                        continue
                    ok = True
                    for item in RSS_ITEM_RE.findall(raw):
                        tm = RSS_TITLE_RE.search(item)
                        lm = RSS_LINK_RE.search(item)
                        if not tm or not lm:
                            continue
                        slug = slug_from(lm.group(1).strip())
                        if slug:
                            entries[slug] = html.unescape(tm.group(1).strip())
                if not ok:
                    return (c or {}).get("entries", [])
                out = [{"slug": k, "title": v} for k, v in sorted(entries.items())]
                st["index_cache"] = {"fetched_at": time.time(), "entries": out}
                return out


            def normalize_title(s):
                s = re.sub(r"\(\d{4}\)", " ", s.lower())
                return " ".join(re.sub(r"[^a-z0-9]+", " ", s).split())


            class Ambiguous(Exception):
                def __init__(self, options):
                    self.options = options


            def score(query, title):
                q, t = normalize_title(query), normalize_title(title)
                if not q or not t:
                    return 0.0
                if q == t:
                    return 1.0
                qc, tc = q.replace(" ", ""), t.replace(" ", "")
                if qc == tc:
                    return 0.99
                if qc in tc:
                    return 0.90 + 0.09 * (len(qc) / max(len(tc), 1))
                qt, tt = set(q.split()), set(t.split())
                overlap = len(qt & tt) / max(len(qt), 1)
                ratio = difflib.SequenceMatcher(None, qc, tc).ratio()
                return max(overlap * 0.85, ratio * 0.8)


            def rank(query, entries):
                scored = [(score(query, e["title"]), e) for e in entries]
                scored.sort(key=lambda x: -x[0])
                return scored


            def resolve(query, entries):
                q = query.strip()
                if not q:
                    raise Ambiguous([])
                if q.startswith("http") or "/movies/" in q:
                    s = slug_from(q)
                    if s:
                        return s
                if re.fullmatch(r"\d+-[a-z0-9-]+", q.lower()):
                    return q.lower()
                scored = rank(q, entries)
                if not scored:
                    raise Ambiguous([])
                best_s, best_e = scored[0]
                runner = scored[1][0] if len(scored) > 1 else 0.0
                # Real queries score 0.9+, junk peaks near 0.45; suggesting five random
                # films is worse than saying no.
                if best_s < 0.50:
                    raise Ambiguous([])
                if best_s >= 0.55 and (best_s - runner) >= 0.05:
                    return best_e["slug"]
                # Substring hits must not skip the clearly-ahead test: "odyssey" matches
                # both "The Odyssey" and "2001: A Space Odyssey".
                if best_s >= 0.99:
                    return best_e["slug"]
                raise Ambiguous([e for _, e in scored[:5]])


            def resolve_among(query, subs):
                return resolve(query, [{"slug": k, "title": v.get("title") or k}
                                       for k, v in subs.items()])


            def title_of(slug, st):
                for e in (st.get("index_cache") or {}).get("entries", []) or []:
                    if e["slug"] == slug:
                        return e["title"]
                return slug


            DEFAULT_WEIGHTS = {"hall": 0.60, "bias": 0.25, "review": 0.15, "travel": 1.0}
            DEFAULT_NEUTRAL = {"hall": 5.0, "bias": 5.0, "review": 5.0, "travel": 0.0}


            def load_scoring():
                raw = os.environ.get("OVW_SCORING", "").strip()
                if not raw:
                    return None
                try:
                    cfg = json.loads(raw)
                except ValueError as e:
                    log("scoring config unparseable, disabling: %s" % e)
                    return None
                if not cfg.get("enable"):
                    return None
                cfg["weights"] = dict(DEFAULT_WEIGHTS, **(cfg.get("weights") or {}))
                cfg["neutral"] = dict(DEFAULT_NEUTRAL, **(cfg.get("neutral") or {}))
                for name, c in (cfg.get("cinemas") or {}).items():
                    # Fall back to the attribute name so a cinema whose feed string is
                    # already exact needs no explicit match list.
                    c["match"] = [m.casefold() for m in (c.get("match") or [name])]
                return cfg


            def match_cinema(cfg, cinema):
                """Longest matching substring wins, so 'Delphi Lux' cannot be swallowed
                by a shorter 'Delphi' entry for the Filmpalast."""
                name = (cinema or "").casefold()
                best = None
                for key_, c in (cfg.get("cinemas") or {}).items():
                    for m in c["match"]:
                        if m and m in name and (best is None or len(m) > best[0]):
                            best = (len(m), key_, c)
                return (best[1], best[2]) if best else (None, None)


            FORMAT_TOKENS = ("imax", "70mm", "3d", "isense", "screenx", "dolby", "4dx")


            def version_formats(version):
                v = (version or "").casefold()
                return {t for t in FORMAT_TOKENS if t in v}


            def resolve_halls(cinema_cfg, version):
                """Candidate halls for a showing.

                A format in subtitleLanguage pins the hall wherever only one hall offers
                it (IMAX at UCI, 70mm at Zoo Palast); otherwise every hall that does not
                require a format is a candidate and the caller reports a range.
                """
                halls = cinema_cfg.get("halls") or []
                if not halls:
                    return [], False
                fmts = version_formats(version)
                if fmts:
                    pinned = [h for h in halls
                              if fmts & {f.casefold() for f in (h.get("formats") or [])}]
                    if len(pinned) == 1:
                        return pinned, True
                    if pinned:
                        return pinned, False
                # Halls gated behind a format are not candidates for a screening that
                # named none. If that leaves nothing -- every rated hall at this cinema is
                # a special screen -- the hall is genuinely unknown, so fall through to
                # neutral rather than crediting a plain showing with the 70mm score.
                plain = [h for h in halls if not h.get("formats")]
                return plain, len(plain) == 1


            def score_of(cfg, hall, cinema_cfg):
                """A hall may override any cinema-level value. Bias in particular is
                per-hall in practice -- the same multiplex can have a screen worth going
                out of your way for and one worth avoiding."""
                w = cfg["weights"]
                n = cfg["neutral"]

                def pick(field):
                    if field in hall:
                        return hall[field]
                    return cinema_cfg.get(field, n[field])

                total = w["hall"] * hall.get("score", n["hall"])
                total += w["bias"] * pick("bias")
                total += w["review"] * pick("review")
                total -= w["travel"] * pick("travel")
                return total


            def score_showing(cfg, showing):
                """Return (low, high, rated). low == high means the hall was pinned."""
                if not cfg:
                    return None
                name, cinema_cfg = match_cinema(cfg, showing.get("cinema"))
                if cinema_cfg is None:
                    s = score_of(cfg, {}, {})
                    return (s, s, False)
                halls, _certain = resolve_halls(cinema_cfg, showing.get("version"))
                if not halls:
                    s = score_of(cfg, {}, cinema_cfg)
                    return (s, s, False)
                scores = [score_of(cfg, h, cinema_cfg) for h in halls]
                return (min(scores), max(scores), True)


            def fmt_score(sc):
                if sc is None:
                    return ""
                low, high, rated = sc
                if not rated:
                    return "[?] "
                if high - low < 0.05:
                    return "[%.1f] " % high
                return "[%.1f-%.1f] " % (low, high)


            def passes_score(cfg, showing):
                """Threshold against the optimistic end of the range: dropping a genuinely
                good screening because its hall was ambiguous is the expensive mistake."""
                if not cfg or cfg.get("minScore") is None:
                    return True
                sc = score_showing(cfg, showing)
                return sc is None or sc[1] >= cfg["minScore"]


            def sort_key(cfg, showing):
                """Best first, then soonest. Unrated showings sort on their neutral score
                rather than sinking below everything: not having rated a cinema is not
                evidence against it."""
                sc = score_showing(cfg, showing)
                return (-(sc[1] if sc else 0), showing["start"])


            def human_date(s):
                t = parse_start(s)
                return time.strftime("%a %d %b %H:%M", t) if t else s


            def movie_url(slug):
                return "%s/movies/%s/" % (BASE, slug)


            def fmt(s, cfg=None):
                return "%s%s \u00b7 %s \u00b7 %s\n%s" % (
                    fmt_score(score_showing(cfg, s)) if cfg else "",
                    s["version"] or "?", human_date(s["start"]), s["cinema"], s["url"])


            def cmd_add(rest, st):
                words, ftoks = split_title_and_filters(rest)
                filters, unknown = parse_filters(ftoks)
                query = " ".join(words)
                try:
                    slug = resolve(query, title_index(st))
                except Ambiguous as a:
                    if not a.options:
                        notify(st, "no match for %r" % query, title="ovwatch")
                    else:
                        notify(st, "which one?\n" + "\n".join(
                            "+%s" % e["slug"] for e in a.options), title="ovwatch")
                    return
                if slug not in st["subs"] and len(st["subs"]) >= MAX_SUBS:
                    notify(st, "subscription limit (%d) reached" % MAX_SUBS, title="ovwatch")
                    return
                title = title_of(slug, st)
                st["subs"][slug] = {"title": title,
                                    "filters": serialize_filters(filters),
                                    "seeded": False}
                st["seen"].pop(slug, None)
                msg = "watching %s\n%s" % (title, describe(filters))
                if unknown:
                    msg += "\nignored: %s" % " ".join(unknown)
                notify(st, msg, title="ovwatch")


            def cmd_drop(rest, st):
                query = " ".join(rest)
                try:
                    slug = resolve_among(query, st["subs"])
                except Ambiguous as a:
                    if not a.options:
                        notify(st, "not watching anything like %r" % query, title="ovwatch")
                    else:
                        notify(st, "which one?\n" + "\n".join(
                            "-%s" % e["title"] for e in a.options), title="ovwatch")
                    return
                title = st["subs"].get(slug, {}).get("title", slug)
                st["subs"].pop(slug, None)
                st["seen"].pop(slug, None)
                notify(st, "dropped %s" % title, title="ovwatch")


            def cmd_refilter(rest, st):
                words, ftoks = split_title_and_filters(rest)
                try:
                    slug = resolve_among(" ".join(words), st["subs"])
                except Ambiguous as a:
                    notify(st, "which one?\n" + ("\n".join(
                        "=%s" % e["title"] for e in a.options) or "(nothing watched)"),
                        title="ovwatch")
                    return
                filters, unknown = parse_filters(ftoks)
                st["subs"][slug]["filters"] = serialize_filters(filters)
                # Re-seed so a widened filter does not dump history.
                st["subs"][slug]["seeded"] = False
                st["seen"].pop(slug, None)
                msg = "filters now %s\n%s" % (st["subs"][slug]["title"], describe(filters))
                if unknown:
                    msg += "\nignored: %s" % " ".join(unknown)
                notify(st, msg, title="ovwatch")


            def cmd_list(st):
                if not st["subs"]:
                    notify(st, "watching nothing", title="ovwatch")
                    return
                lines = []
                for slug, sub in sorted(st["subs"].items(), key=lambda kv: kv[1].get("title", "")):
                    f = deserialize_filters(sub["filters"])
                    lines.append("%s\n  %s (%d known)" % (
                        sub.get("title", slug), describe(f), len(st["seen"].get(slug, ()))))
                notify(st, "\n".join(lines), title="ovwatch: watching %d" % len(st["subs"]))


            def handle(msg, st):
                msg = msg.strip()
                if not msg:
                    return
                op, rest = msg[0], msg[1:].split()
                if op == "+":
                    cmd_add(rest, st)
                elif op == "-":
                    cmd_drop(rest, st)
                elif op == "=":
                    cmd_refilter(rest, st)
                elif op == "?":
                    cmd_list(st)


            def sweep(st, force=False):
                """Poll the site and notify about changes. Returns True if state changed."""
                if not st["subs"]:
                    return False
                now = time.time()
                unseeded = any(not s.get("seeded") for s in st["subs"].values())
                if not force and not unseeded:
                    return False

                stamp = site_stamp()
                if stamp is not None:
                    st["last_site_poll"] = now
                changed = stamp is not None and stamp != st.get("generated_at")
                if not changed and not unseeded:
                    log("no rebuild (%s), %d subs" % (stamp, len(st["subs"])))
                    return True

                all_ok = True
                for slug, sub in list(st["subs"].items()):
                    # When the site itself is unchanged only new subscriptions need a fetch.
                    if not changed and sub.get("seeded"):
                        continue
                    showings = fetch_showings(slug)
                    if showings is None:
                        all_ok = False
                        continue
                    f = deserialize_filters(sub["filters"])
                    hits = [s for s in showings if matches(s, f)]
                    current = {key(s) for s in showings}

                    if not sub.get("seeded"):
                        # Seed on all showings, not just hits, so loosening a filter later
                        # stays quiet.
                        st["seen"][slug] = current
                        sub["seeded"] = True
                        shown = [s for s in hits if passes_score(SCORING, s)]
                        notify(st, "%s: watching, %d matching showings already listed"
                               % (sub.get("title", slug), len(shown)), title="ovwatch",
                               click=movie_url(slug),
                               actions=action_header(("All showings", movie_url(slug))))
                        continue

                    seen = st["seen"].setdefault(slug, set())
                    fresh = [s for s in hits if key(s) not in seen]
                    # Showings below the threshold are recorded as seen without notifying,
                    # so a later sweep does not treat them as new all over again.
                    if SCORING and SCORING.get("minScore") is not None:
                        below = [s for s in fresh if not passes_score(SCORING, s)]
                        if below:
                            seen.update(key(s) for s in below)
                            log("%s: %d below minScore" % (slug, len(below)))
                        fresh = [s for s in fresh if passes_score(SCORING, s)]
                    if len(fresh) > BATCH_THRESHOLD:
                        # A schedule drop can add dozens of showings at once. Sending one
                        # notification each buries the phone and trips ntfy's rate limit,
                        # so past a handful they collapse into a single digest.
                        ordered = (sorted(fresh, key=lambda s: sort_key(SCORING, s))
                                   if SCORING else sorted(fresh, key=lambda s: s["start"]))
                        body = "\n".join(
                            "%s%s \u00b7 %s \u00b7 %s" % (
                                fmt_score(score_showing(SCORING, s)) if SCORING else "",
                                s["version"] or "?", human_date(s["start"]), s["cinema"])
                            for s in ordered[:BATCH_LIST])
                        more = len(fresh) - BATCH_LIST
                        if more > 0:
                            body += "\n... and %d more" % more
                        # A digest spans many showings, so the listing is the useful
                        # destination; the first entry (best-scoring when scoring is on)
                        # still gets a direct booking button.
                        pick = next((s for s in ordered if s["url"]), None)
                        if notify(st, "%d new showings\n%s" % (len(fresh), body),
                                  title=sub.get("title", slug),
                                  click=movie_url(slug), tags="clapper",
                                  actions=action_header(
                                      ("All showings", movie_url(slug)),
                                      ("Book top" if SCORING else "Book soonest",
                                       pick["url"] if pick else None))):
                            seen.update(key(s) for s in fresh)
                    else:
                        for s in fresh:
                            # Tapping the body goes straight to the booking page; the
                            # buttons offer that plus the ov-berlin listing for context.
                            # Only recorded as seen once actually delivered, otherwise a
                            # failed publish is silently never retried.
                            if notify(st, fmt(s, SCORING), title=sub.get("title", slug),
                                      click=s["url"] or movie_url(slug), tags="clapper",
                                      actions=action_header(
                                          ("Book", s["url"]),
                                          ("Info", movie_url(slug)))):
                                seen.add(key(s))

                    gone = seen - current
                    vanished = []
                    for g in sorted(gone):
                        t = parse_start(g[0])
                        gs = {"start": g[0], "cinema": g[1], "version": g[2], "url": "",
                              "title": sub.get("title", slug)}
                        if t and time.mktime(t) > now and matches(gs, f):
                            vanished.append(g)
                    if len(vanished) > BATCH_THRESHOLD:
                        body = "\n".join(
                            "%s \u00b7 %s \u00b7 %s" % (g[2] or "?", human_date(g[0]), g[1])
                            for g in vanished[:BATCH_LIST])
                        more = len(vanished) - BATCH_LIST
                        if more > 0:
                            body += "\n... and %d more" % more
                        notify(st, "%d showings dropped from schedule\n%s"
                               % (len(vanished), body),
                               title=sub.get("title", slug), tags="x",
                               click=movie_url(slug),
                               actions=action_header(("All showings", movie_url(slug))))
                    else:
                        for g in vanished:
                            notify(st, "dropped from schedule:\n%s \u00b7 %s \u00b7 %s"
                                   % (g[2] or "?", human_date(g[0]), g[1]),
                                   title=sub.get("title", slug), tags="x",
                                   click=movie_url(slug),
                                   actions=action_header(
                                       ("All showings", movie_url(slug))))
                    seen -= gone

                    cutoff = now - 86400
                    seen -= {k for k in seen if is_past(k[0], cutoff)}
                    st["seen"][slug] = seen

                # Only advance the stamp if every subscription refreshed, otherwise a
                # transient failure would permanently skip this rebuild.
                if all_ok and stamp is not None:
                    st["generated_at"] = stamp
                return True


            def stream_once(st, state_path):
                """Hold one streaming connection, handling commands as they arrive.

                The socket read timeout doubles as the site-poll clock: when it expires we
                sweep if due and reconnect. Returns True if the connection was established,
                so the caller can distinguish a normal cycle from a failure to connect.
                """
                since = st.get("cmd_since") or "all"
                url = "%s/%s/json?since=%s" % (NTFY_URL, TOPIC,
                                               urllib.parse.quote(str(since)))
                req = urllib.request.Request(url, headers=auth_headers())
                try:
                    resp = urllib.request.urlopen(req, timeout=READ_TIMEOUT)
                except (urllib.error.URLError, OSError) as e:
                    if since != "all":
                        # An evicted cursor is rejected; reset so we recover rather than
                        # wedging on it forever.
                        log("stream connect failed (%s), resetting cursor" % e)
                        st["cmd_since"] = None
                        save_state(state_path, st)
                    else:
                        log("stream connect failed: %s" % e)
                    return False

                log("stream open (since=%s)" % since)
                with resp:
                    while True:
                        try:
                            line = resp.readline()
                        except (TimeoutError, OSError):
                            # Idle read timeout: do the periodic work and reconnect.
                            if due_for_sweep(st) and sweep(st, force=True):
                                save_state(state_path, st)
                            return True
                        if not line:
                            return True
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            d = json.loads(line)
                        except ValueError:
                            continue
                        if d.get("event") == "keepalive":
                            if due_for_sweep(st) and sweep(st, force=True):
                                save_state(state_path, st)
                            continue
                        if d.get("event") != "message":
                            continue
                        st["cmd_since"] = d.get("id") or st.get("cmd_since")
                        if d.get("id") in set(st.get("self_ids", [])):
                            save_state(state_path, st)
                            continue
                        text = (d.get("message") or "").strip()
                        if not text or text[0] not in "+-=?":
                            save_state(state_path, st)
                            continue
                        try:
                            handle(text, st)
                        except Exception as e:  # noqa: BLE001
                            log("command %r failed: %s" % (text, e))
                        # A new subscription seeds straight away rather than waiting for
                        # the next scheduled sweep.
                        sweep(st)
                        save_state(state_path, st)


            def due_for_sweep(st):
                return (time.time() - st.get("last_site_poll", 0)) >= SITE_INTERVAL


            def main():
                state_dir = os.environ.get("STATE_DIRECTORY") or os.environ.get(
                    "OVW_STATE_DIR", ".")
                state_path = os.path.join(state_dir, "state.json")

                global SCORING
                SCORING = load_scoring()
                if SCORING:
                    log("scoring on: %d cinemas, minScore=%s"
                        % (len(SCORING.get("cinemas") or {}), SCORING.get("minScore")))

                st = load_state(state_path)
                if due_for_sweep(st):
                    sweep(st, force=True)
                save_state(state_path, st)

                backoff = 1
                while True:
                    st = load_state(state_path)
                    ok = stream_once(st, state_path)
                    save_state(state_path, st)
                    if ok:
                        backoff = 1
                    else:
                        log("reconnecting in %ds" % backoff)
                        time.sleep(backoff)
                        backoff = min(backoff * 2, MAX_BACKOFF)


            if __name__ == "__main__":
                main()
          '';
    in
    {
      options.services.ovwatch = {
        enable = mkEnableOption "ov-berlin.info original-language showtime watcher";

        siteIntervalSeconds = mkOption {
          type = types.ints.positive;
          default = 3600;
          description = ''
            How often ov-berlin.info is polled, in seconds. Commands are
            handled off a held connection and are unaffected by this, so it can
            stay conservative. A due sweep costs one /diag.json request and only
            fetches movie pages when that stamp has changed. New subscriptions
            are seeded immediately regardless of this.
          '';
        };

        baseUrl = mkOption {
          type = types.str;
          default = "https://ov-berlin.info";
          description = ''
            Site to watch, without a trailing slash. The same software serves
            the other cities, so e.g. https://munich.ov-berlin.info also works.
          '';
        };

        userAgent = mkOption {
          type = types.str;
          default = "ovwatch/1.0 (personal showtime watcher)";
          description = ''
            User-Agent sent with every request. Consider adding a contact
            address so they can reach you if this ever causes them trouble.
          '';
        };

        crawlDelay = mkOption {
          type = types.number;
          default = 1;
          description = ''
            Minimum seconds between requests, honouring the `Crawl-delay: 1` in
            their robots.txt. Applies across all fetches in a tick.
          '';
        };

        maxSubscriptions = mkOption {
          type = types.ints.positive;
          default = 50;
          description = ''
            Upper bound on watched films. A rebuild costs one page fetch per
            subscription, serialised by crawlDelay, so this bounds tick length.
          '';
        };

        scoring = {
          enable = mkEnableOption ''
            weighted scoring of showings. Each showing is scored from your own
            ratings of the hall, the cinema, and how far it is; the score is
            shown in the notification, digests are ordered best first, and
            `minScore` can suppress the rest
          '';

          weights = {
            hall = mkOption {
              type = types.number;
              default = 0.60;
              description = "Weight on the hall's own score (screen, sound, seats).";
            };
            bias = mkOption {
              type = types.number;
              default = 0.25;
              description = "Weight on your personal preference for the place.";
            };
            review = mkOption {
              type = types.number;
              default = 0.15;
              description = "Weight on the public review score.";
            };
            travel = mkOption {
              type = types.number;
              default = 1.0;
              description = ''
                Multiplier on travel cost, which is subtracted rather than
                added. With the default weights a travel cost of 1.0 cancels
                out roughly 1.7 points of hall quality.
              '';
            };
          };

          minScore = mkOption {
            type = types.nullOr types.number;
            default = null;
            example = 6.5;
            description = ''
              Suppress showings scoring below this. Compared against the
              optimistic end of a range, so an ambiguous hall is never the
              reason a good screening is withheld. Suppressed showings are
              still recorded, so raising this and lowering it again does not
              replay old ones. Null notifies about everything.
            '';
          };

          neutral = {
            hall = mkOption {
              type = types.number;
              default = 5.0;
              description = "Assumed hall score at an unrated cinema.";
            };
            bias = mkOption {
              type = types.number;
              default = 5.0;
              description = "Assumed bias at an unrated cinema.";
            };
            review = mkOption {
              type = types.number;
              default = 5.0;
              description = "Assumed review score at an unrated cinema.";
            };
            travel = mkOption {
              type = types.number;
              default = 0.0;
              description = "Assumed travel cost at an unrated cinema.";
            };
          };

          cinemas = mkOption {
            default = { };
            description = ''
              Your ratings, keyed by any name you like. Showings whose cinema
              matches none of these are scored from `neutral` and marked "?"
              rather than dropped.

              The feed gives cinema and format but never the hall, so a hall is
              only identified when a format pins it (IMAX, 70mm) or the cinema
              has one rated hall. Otherwise every candidate is scored and the
              notification shows a range. Note that `iSense` and `ScreenX`
              never appear in the feed's format field, so those halls cannot be
              distinguished from a plain screening.

              `bias`, `review` and `travel` may be set per cinema and
              overridden per hall, since one multiplex can hold both a screen
              worth crossing town for and one worth avoiding.
            '';
            example = literalExpression ''
              {
                "Zoo Palast" = {
                  match = [ "zoo palast" ];
                  bias = 9; review = 9.2; travel = 0.60;
                  halls = [ { name = "Saal 1"; score = 8.9; formats = [ "70mm" ]; } ];
                };
                "UCI East Side Gallery" = {
                  match = [ "east side gallery" ];
                  review = 8.3; travel = 1.20;
                  halls = [
                    { name = "Saal 1 IMAX"; score = 10.0; bias = 7; formats = [ "IMAX" ]; }
                    { name = "Saal 2 iSense"; score = 8.0; bias = 7; }
                    { name = "Saal 4 ScreenX"; score = 5.3; bias = 4; }
                  ];
                };
                "CineStar CUBIX" = {
                  match = [ "cubix" ];
                  review = 3.3; travel = 0.12;
                  halls = [
                    { name = "Saal 9"; score = 8.4; bias = 6; }
                    { name = "Saal 7"; score = 6.4; bias = 5; }
                  ];
                };
              }
            '';
            type = types.attrsOf (
              types.submodule (
                { name, ... }:
                {
                  options = {
                    match = mkOption {
                      type = types.listOf types.str;
                      default = [ name ];
                      description = ''
                        Case-insensitive substrings matched against the
                        cinema name in the feed, which is often longer than
                        the everyday one ("UCI Kinowelt Berlin East Side
                        Gallery"). The longest match across all cinemas wins,
                        so a specific venue is not swallowed by a generic
                        prefix. Defaults to the attribute name.
                      '';
                    };
                    bias = mkOption {
                      type = types.nullOr types.number;
                      default = null;
                      description = "How much you like the place, 0-10.";
                    };
                    review = mkOption {
                      type = types.nullOr types.number;
                      default = null;
                      description = "Public review score, 0-10.";
                    };
                    travel = mkOption {
                      type = types.nullOr types.number;
                      default = null;
                      description = ''
                        Cost of getting there, subtracted from the score.
                        Same units as the score itself, so 0.6 means "worth
                        0.6 points of quality to me".
                      '';
                    };
                    halls = mkOption {
                      default = [ ];
                      description = ''
                        Rated halls. A cinema with exactly one is always
                        scored exactly; more than one needs a format to
                        disambiguate, or the score becomes a range.
                      '';
                      type = types.listOf (
                        types.submodule {
                          options = {
                            name = mkOption {
                              type = types.str;
                              description = "Hall name, for your own reference.";
                            };
                            score = mkOption {
                              type = types.number;
                              description = "Quality of the hall itself, 0-10.";
                            };
                            formats = mkOption {
                              type = types.listOf types.str;
                              default = [ ];
                              example = [ "IMAX" ];
                              description = ''
                                Formats only this hall can show. Matched
                                case-insensitively against the feed's format
                                field; recognised tokens are IMAX, 70mm, 3D,
                                iSense, ScreenX, Dolby and 4DX, though only
                                IMAX, 70mm and 3D actually occur there. A hall
                                listing a format is excluded from screenings
                                that name none, so a plain showing never
                                inherits the IMAX hall's score.
                              '';
                            };
                            bias = mkOption {
                              type = types.nullOr types.number;
                              default = null;
                              description = "Overrides the cinema's bias.";
                            };
                            review = mkOption {
                              type = types.nullOr types.number;
                              default = null;
                              description = "Overrides the cinema's review score.";
                            };
                            travel = mkOption {
                              type = types.nullOr types.number;
                              default = null;
                              description = "Overrides the cinema's travel cost.";
                            };
                          };
                        }
                      );
                    };
                  };
                }
              )
            );
          };
        };

        ntfy = {
          url = mkOption {
            type = types.str;
            default = "https://ntfy.niko.ink";
            description = "Base URL of the ntfy server, without a trailing slash.";
          };

          topic = mkOption {
            type = types.str;
            default = "ovwatch";
            description = ''
              Topic used for both notifications and inbound commands. The token
              in `tokenFile` needs read-write access to it.
            '';
          };

          tokenFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = ''
              Path (sops secret) to a file whose first line is an ntfy token
              with read-write access to `topic`. Read access is required, not
              just write: commands arrive on the same topic. Null talks to ntfy
              unauthenticated.
            '';
          };
        };
      };

      config = mkIf cfg.enable {
        systemd.services.ovwatch = {
          description = "ov-berlin.info showtime watch";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];

          environment = {
            OVW_BASE = cfg.baseUrl;
            OVW_UA = cfg.userAgent;
            OVW_NTFY_URL = cfg.ntfy.url;
            OVW_NTFY_TOPIC = cfg.ntfy.topic;
            OVW_CRAWL_DELAY = toString cfg.crawlDelay;
            OVW_SITE_INTERVAL = toString cfg.siteIntervalSeconds;
            OVW_READ_TIMEOUT = toString readTimeout;
            OVW_MAX_SUBS = toString cfg.maxSubscriptions;
            OVW_SCORING = mkIf cfg.scoring.enable scoringJson;
          };

          serviceConfig = {
            # Long-running rather than a timer: the daemon holds an ntfy
            # streaming connection so commands are answered in well under a
            # second, which polling cannot match without a silly tick rate.
            Type = "simple";
            ExecStart = getExe pollScript;
            Restart = "always";
            RestartSec = "10s";
            # Reconnects are handled internally with backoff, so repeated
            # restarts mean something is actually wrong; do not rate-limit the
            # unit into a permanent failed state over a long outage.
            StartLimitIntervalSec = 0;

            DynamicUser = true;
            StateDirectory = "ovwatch";
            LoadCredential = optional (cfg.ntfy.tokenFile != null) "ntfy-token:${toString cfg.ntfy.tokenFile}";

            # Hardening.
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            RestrictSUIDSGID = true;
            RestrictNamespaces = true;
            LockPersonality = true;
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
          };
        };

      };
    };
}
