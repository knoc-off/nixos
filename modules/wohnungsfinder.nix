# inberlinwohnen.de Wohnungsfinder — new-listing notifier.
#
# The apartment finder is server-rendered Laravel Livewire. Every listing
# ships its full database row as JSON in the `wire:snapshot` attribute of an
# `apartment-finder.item.apartment-item` component, so a plain HTTP GET with
# a cookie jar yields strictly more than the rendered DOM shows (object id,
# deeplink, image path, coordinates, district). No browser is involved.
#
# Pagination is a Livewire round trip: POST /livewire/update replaying the
# parent component's snapshot string verbatim (it is HMAC-signed with the app
# key, so it must not be edited) with a `gotoPage` call. Default sort is
# newest-first, so routine polling only needs page 1; deeper paging exists for
# the initial backfill.
#
# State (SQLite) lives in StateDirectory. New listings are pushed to ntfy;
# the publish token is read via LoadCredential so it never enters the store.
{...}: {
  nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) getExe mkEnableOption mkIf mkOption optional types;
    cfg = config.services.wohnungsfinder;

    pollScript = pkgs.writers.writePython3Bin "wohnungsfinder" {
      flakeIgnore = ["E501"];
    } ''
      import html
      import http.cookiejar
      import json
      import os
      import re
      import sqlite3
      import sys
      import time
      import urllib.request

      BASE = "https://www.inberlinwohnen.de"
      PAGE_URL = BASE + "/wohnungsfinder"
      UPDATE_URL = BASE + "/livewire/update"
      UA = (
          "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
          "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
      )
      SNAPSHOT_RE = re.compile(r'wire:snapshot="([^"]*)"')
      CSRF_RE = re.compile(r'name="csrf-token"\s+content="([^"]+)"')
      ITEM_COMPONENT = "apartment-finder.item.apartment-item"
      LIST_COMPONENT = "apartment-finder.rentable-apartment-finder"

      FIELDS = [
          "id", "object_id", "title", "deeplink", "image_url", "company",
          "rooms", "area", "rent_net", "extra_costs", "heating_costs",
          "rent_total", "wbs", "heating_type", "street", "zip_code",
          "district", "lat", "lon", "level", "levels_total", "bathrooms",
          "construction_year", "occupation_date", "created_at",
      ]


      def log(*a):
          print(*a, file=sys.stderr, flush=True)


      def unwrap(x):
          """Livewire 3 encodes every PHP array as [value, {"s": "arr"}]."""
          if isinstance(x, list) and len(x) == 2 and x[1] == {"s": "arr"}:
              return unwrap(x[0])
          if isinstance(x, list):
              return [unwrap(i) for i in x]
          if isinstance(x, dict):
              return {k: unwrap(v) for k, v in x.items()}
          return x


      def de_num(s):
          """German money/decimal format: '1.424,92' -> 1424.92."""
          if s is None:
              return None
          if isinstance(s, (int, float)):
              return float(s)
          s = str(s).replace("\u00a0", "").replace("€", "").strip()
          if not s:
              return None
          try:
              return float(s.replace(".", "").replace(",", "."))
          except ValueError:
              return None


      def plain_num(s):
          """Coordinates already use a dot decimal separator, unlike prices."""
          try:
              return float(s)
          except (TypeError, ValueError):
              return None


      class Session:
          """Cookie-jar HTTP session presenting itself as a browser."""

          def __init__(self, timeout=30):
              self.jar = http.cookiejar.CookieJar()
              self.opener = urllib.request.build_opener(
                  urllib.request.HTTPCookieProcessor(self.jar)
              )
              self.timeout = timeout
              self.csrf = ""

          def _headers(self, extra=None):
              h = {
                  "User-Agent": UA,
                  "Accept-Language": "de-DE,de;q=0.9,en;q=0.8",
                  "Accept-Encoding": "identity",
              }
              if extra:
                  h.update(extra)
              return h

          def get_page(self):
              req = urllib.request.Request(PAGE_URL, headers=self._headers({
                  "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                  "Upgrade-Insecure-Requests": "1",
              }))
              with self.opener.open(req, timeout=self.timeout) as r:
                  body = r.read().decode("utf-8", "replace")
              m = CSRF_RE.search(body)
              if m:
                  self.csrf = m.group(1)
              return body

          def livewire_call(self, snapshot, method, params):
              """Replay the snapshot verbatim; it is HMAC-signed upstream."""
              payload = {
                  "_token": self.csrf,
                  "components": [{
                      "snapshot": snapshot,
                      "updates": {},
                      "calls": [{"path": "", "method": method, "params": params}],
                  }],
              }
              req = urllib.request.Request(
                  UPDATE_URL,
                  data=json.dumps(payload).encode("utf-8"),
                  headers=self._headers({
                      "Content-Type": "application/json",
                      "Accept": "text/html, application/xhtml+xml",
                      "X-Livewire": "true",
                      "X-CSRF-TOKEN": self.csrf,
                      "Origin": BASE,
                      "Referer": PAGE_URL,
                  }),
              )
              with self.opener.open(req, timeout=self.timeout) as r:
                  return json.loads(r.read().decode("utf-8", "replace"))


      def iter_snapshots(text):
          for m in SNAPSHOT_RE.finditer(text):
              raw = html.unescape(m.group(1))
              try:
                  yield raw, json.loads(raw)
              except json.JSONDecodeError:
                  continue


      def find_list_snapshot(text):
          for raw, doc in iter_snapshots(text):
              if doc.get("memo", {}).get("name") == LIST_COMPONENT:
                  return raw
          return None


      def normalise(item):
          # `details` is a list of groups of {label, value} dicts. It carries the
          # only human-readable copy of WBS and Gesamtmiete.
          labels = {}
          for group in item.get("details") or []:
              if not isinstance(group, list):
                  continue
              for d in group:
                  if isinstance(d, dict) and d.get("label") is not None:
                      labels[d["label"]] = d.get("value")

          addr = item.get("address") or {}
          company = item.get("company") or {}

          # rentGross == rent_net + extra_costs and excludes heating, while the
          # displayed Gesamtmiete includes it. There is no heating field in the
          # payload at all, so derive it from the difference.
          rent_gross = de_num(item.get("rentGross"))
          total = de_num(labels.get("Gesamtmiete"))
          heating = None
          if total is not None and rent_gross is not None:
              heating = round(total - rent_gross, 2)

          street = (addr.get("street") or "").strip()
          number = (addr.get("number") or "").strip()
          image = item.get("imagePath")

          return {
              "id": item.get("id"),
              "object_id": item.get("objectId"),
              "title": item.get("title"),
              "deeplink": item.get("deeplink"),
              "image_url": (BASE + "/" + image) if image else None,
              "company": (company.get("name") or "").strip() or None,
              "rooms": de_num(item.get("rooms")),
              "area": de_num(item.get("area")),
              "rent_net": de_num(item.get("rentNet")),
              "extra_costs": de_num(item.get("extraCosts")),
              "heating_costs": heating,
              "rent_total": total if total is not None else rent_gross,
              "wbs": labels.get("WBS"),
              "heating_type": labels.get("Heizung"),
              "street": (street + " " + number).strip() or None,
              "zip_code": addr.get("zipCode"),
              "district": addr.get("district"),
              "lat": plain_num(addr.get("lat")),
              "lon": plain_num(addr.get("lon")),
              "level": item.get("level"),
              "levels_total": item.get("levelsTotal"),
              "bathrooms": item.get("bathrooms"),
              "construction_year": item.get("constructionYear"),
              "occupation_date": item.get("occupationDate"),
              "created_at": item.get("createdAt"),
          }


      def parse_listings(text):
          out = []
          for _, doc in iter_snapshots(text):
              if doc.get("memo", {}).get("name") != ITEM_COMPONENT:
                  continue
              data = unwrap(doc.get("data") or {})
              item = data.get("item") if isinstance(data, dict) else None
              if isinstance(item, dict) and item.get("id") is not None:
                  out.append(normalise(item))
          return out


      def response_text(resp):
          parts = []
          for comp in resp.get("components") or []:
              effects = comp.get("effects") or {}
              if isinstance(effects.get("html"), str):
                  parts.append(effects["html"])
              if isinstance(comp.get("snapshot"), str):
                  parts.append(comp["snapshot"])
          return "\n".join(parts)


      def response_list_snapshot(resp):
          for comp in resp.get("components") or []:
              snap = comp.get("snapshot")
              if not isinstance(snap, str):
                  continue
              try:
                  doc = json.loads(snap)
              except json.JSONDecodeError:
                  continue
              if doc.get("memo", {}).get("name") == LIST_COMPONENT:
                  return snap
          return None


      def scrape(max_pages, delay=1.5):
          sess = Session()
          page = sess.get_page()
          listings = {r["id"]: r for r in parse_listings(page)}
          log("page 1: %d listings" % len(listings))
          if not listings:
              raise SystemExit("no listings parsed - page layout probably changed")

          snapshot = find_list_snapshot(page)
          n = 2
          while snapshot and n <= max_pages:
              time.sleep(delay)
              try:
                  resp = sess.livewire_call(snapshot, "gotoPage", [n, "page"])
              except Exception as e:
                  log("page %d: request failed (%s); stopping" % (n, e))
                  break
              text = response_text(resp)
              # Nested snapshots inside returned HTML are escaped a second time.
              found = parse_listings(text) + parse_listings(html.unescape(text))
              fresh = {r["id"]: r for r in found if r["id"] not in listings}
              if not fresh:
                  log("page %d: nothing new; stopping" % n)
                  break
              listings.update(fresh)
              log("page %d: +%d (total %d)" % (n, len(fresh), len(listings)))
              snapshot = response_list_snapshot(resp) or snapshot
              n += 1
          return listings


      def open_db(path):
          db = sqlite3.connect(path)
          cols = ", ".join(f + (" INTEGER PRIMARY KEY" if f == "id" else "") for f in FIELDS)
          db.execute("CREATE TABLE IF NOT EXISTS listings (%s, first_seen TEXT, last_seen TEXT, gone_at TEXT)" % cols)
          db.commit()
          return db


      def euro(v):
          if v is None:
              return "?"
          return ("%.2f" % v).replace(".", ",") + " €"


      def wbs_required(rec):
          """Site renders exactly 'erforderlich' or 'nicht erforderlich'."""
          v = (rec["wbs"] or "").strip().lower()
          if not v:
              return False
          return "erforderlich" in v and "nicht erforderlich" not in v


      def matches(rec, flt):
          """Notification filter. Storage is unfiltered, so the database stays
          a complete picture and changing a filter needs no re-scrape."""
          if flt["min_area"] is not None:
              if rec["area"] is None or rec["area"] <= flt["min_area"]:
                  return False
          if flt["max_level"] is not None:
              if rec["level"] is not None and rec["level"] > flt["max_level"]:
                  return False
          if flt["exclude_wbs"] and wbs_required(rec):
              return False
          return True


      def notify(rec, ntfy_url, topic, title, token):
          if not ntfy_url or not topic:
              return
          bits = []
          if rec["rooms"]:
              bits.append("%g Zi" % rec["rooms"])
          if rec["area"]:
              bits.append(("%.0f" % rec["area"]) + " m²")
          bits.append(euro(rec["rent_total"]) + " warm")
          if rec["level"] is not None:
              bits.append("EG" if rec["level"] == 0 else "%d. OG" % rec["level"])
          body = " · ".join(bits)
          if rec["street"]:
              body += "\n" + rec["street"]
          # Region goes in the title: ntfy shows it in the notification list
          # without having to expand the message.
          head = rec["district"] or title
          headers = {
              "Title": (head + ": " + (rec["title"] or ""))[:200],
              "Tags": "house",
              "Content-Type": "text/plain; charset=utf-8",
          }
          if rec["deeplink"]:
              headers["Actions"] = "view, Angebot öffnen, " + rec["deeplink"]
          if token:
              headers["Authorization"] = "Bearer " + token
          req = urllib.request.Request(
              ntfy_url.rstrip("/") + "/" + topic,
              data=body.strip().encode("utf-8"),
              headers=headers,
          )
          try:
              urllib.request.urlopen(req, timeout=20).close()
          except Exception as e:
              log("ntfy publish failed for %s: %s" % (rec["id"], e))


      def opt_float(name):
          """An unset or empty variable disables that filter entirely."""
          v = os.environ.get(name, "").strip()
          return float(v) if v else None


      def opt_int(name):
          v = os.environ.get(name, "").strip()
          return int(v) if v else None


      def read_credential(name):
          d = os.environ.get("CREDENTIALS_DIRECTORY")
          if not d:
              return None
          try:
              with open(os.path.join(d, name)) as f:
                  return f.readline().strip()
          except OSError:
              return None


      def main():
          state = os.environ.get("STATE_DIRECTORY", ".")
          db_path = os.path.join(state, "wohnungsfinder.sqlite3")
          first_run = not os.path.exists(db_path)
          max_pages = int(os.environ.get("WF_MAX_PAGES", "1"))
          if first_run:
              # Seed the whole catalogue so the first poll does not notify ~300
              # listings that were already there before we started watching.
              max_pages = int(os.environ.get("WF_BACKFILL_PAGES", "40"))
              log("no state yet: backfilling up to %d pages" % max_pages)

          listings = scrape(max_pages)
          db = open_db(db_path)
          now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
          known = {r[0] for r in db.execute("SELECT id FROM listings")}

          ntfy_url = os.environ.get("WF_NTFY_URL", "")
          topic = os.environ.get("WF_NTFY_TOPIC", "")
          title = os.environ.get("WF_NTFY_TITLE", "Neue Wohnung")
          token = read_credential("ntfy-token")
          flt = {
              "min_area": opt_float("WF_MIN_AREA"),
              "max_level": opt_int("WF_MAX_LEVEL"),
              "exclude_wbs": os.environ.get("WF_EXCLUDE_WBS", "1") == "1",
          }

          placeholders = ", ".join("?" for _ in FIELDS)
          updates = ", ".join(f + "=?" for f in FIELDS if f != "id")
          new = 0
          sent = 0
          for rec in sorted(listings.values(), key=lambda r: r["created_at"] or ""):
              values = [rec[f] for f in FIELDS]
              if rec["id"] in known:
                  db.execute(
                      "UPDATE listings SET %s, last_seen=?, gone_at=NULL WHERE id=?" % updates,
                      [rec[f] for f in FIELDS if f != "id"] + [now, rec["id"]],
                  )
                  continue
              db.execute(
                  "INSERT INTO listings (%s, first_seen, last_seen) VALUES (%s, ?, ?)"
                  % (", ".join(FIELDS), placeholders),
                  values + [now, now],
              )
              new += 1
              if not first_run and matches(rec, flt):
                  notify(rec, ntfy_url, topic, title, token)
                  sent += 1

          # A listing missing from page 1 has merely scrolled off; only treat it
          # as gone when a full sweep did not see it.
          gone = 0
          if max_pages >= int(os.environ.get("WF_BACKFILL_PAGES", "40")):
              seen = tuple(listings)
              cur = db.execute(
                  "UPDATE listings SET gone_at=? WHERE gone_at IS NULL AND id NOT IN (%s)"
                  % ", ".join("?" for _ in seen),
                  (now,) + seen,
              )
              gone = cur.rowcount

          db.commit()
          db.close()
          log("scraped=%d new=%d notified=%d gone=%d%s" % (
              len(listings), new, sent, gone,
              " (seeded, no alerts)" if first_run else ""))


      if __name__ == "__main__":
          main()
    '';
  in {
    options.services.wohnungsfinder = {
      enable = mkEnableOption "inberlinwohnen.de Wohnungsfinder new-listing notifier";

      interval = mkOption {
        type = types.str;
        default = "3m";
        description = ''
          Poll cadence, in systemd `OnUnitActiveSec` syntax. With ~300 active
          offers sorted newest-first, page 1 alone catches everything as long as
          fewer than ten listings appear between two polls.
        '';
      };

      maxPages = mkOption {
        type = types.ints.positive;
        default = 1;
        description = ''
          Pages to walk on a routine poll. Each page beyond the first costs one
          Livewire round trip, so 1 is right for notification; raise it only to
          re-sync disappearances.
        '';
      };

      backfillPages = mkOption {
        type = types.ints.positive;
        default = 40;
        description = ''
          Pages to walk on the very first run (when no database exists) to seed
          the catalogue without alerting on pre-existing listings. Paging stops
          early once a page returns nothing new.
        '';
      };

      filters = {
        minArea = mkOption {
          type = types.nullOr types.number;
          default = 55;
          description = ''
            Only notify about listings with a Wohnflaeche strictly greater than
            this, in square metres. Null disables the check.
          '';
        };

        maxLevel = mkOption {
          type = types.nullOr types.int;
          default = 1;
          description = ''
            Only notify about listings on this floor or below, where 0 is
            Erdgeschoss. Null disables the check. Listings that do not state a
            floor are never excluded by this.
          '';
        };

        excludeWbsRequired = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Skip listings that require a Wohnberechtigungsschein.
          '';
        };
      };

      ntfy = {
        url = mkOption {
          type = types.str;
          default = "https://ntfy.niko.ink";
          description = ''
            Base URL of the ntfy server (no trailing slash). Defaults to the
            public instance since this service usually does not run on the same
            host as ntfy itself.
          '';
        };
        topic = mkOption {
          type = types.str;
          default = "wohnungen";
          description = "ntfy topic that new listings are published to.";
        };
        title = mkOption {
          type = types.str;
          default = "Neue Wohnung";
          description = "Notification title prefix; the listing title is appended.";
        };
        tokenFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = ''
            Path (sops secret) to a file whose first line is an ntfy token with
            write access to `ntfy.topic`. Null publishes unauthenticated.
          '';
        };
      };
    };

    config = mkIf cfg.enable {
      systemd.services.wohnungsfinder = {
        description = "inberlinwohnen.de Wohnungsfinder poll";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        # Not wantedBy: the timer owns activation.

        environment = {
          WF_MAX_PAGES = toString cfg.maxPages;
          WF_BACKFILL_PAGES = toString cfg.backfillPages;
          WF_NTFY_URL = cfg.ntfy.url;
          WF_NTFY_TOPIC = cfg.ntfy.topic;
          WF_NTFY_TITLE = cfg.ntfy.title;
          WF_MIN_AREA = if cfg.filters.minArea == null then "" else toString cfg.filters.minArea;
          WF_MAX_LEVEL = if cfg.filters.maxLevel == null then "" else toString cfg.filters.maxLevel;
          WF_EXCLUDE_WBS =
            if cfg.filters.excludeWbsRequired
            then "1"
            else "0";
        };

        serviceConfig = {
          Type = "oneshot";
          ExecStart = getExe pollScript;

          DynamicUser = true;
          StateDirectory = "wohnungsfinder";
          LoadCredential = optional (cfg.ntfy.tokenFile != null)
            "ntfy-token:${toString cfg.ntfy.tokenFile}";

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
          RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        };
      };

      systemd.timers.wohnungsfinder = {
        description = "inberlinwohnen.de Wohnungsfinder poll timer";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "2m";
          OnUnitActiveSec = cfg.interval;
          # Do not hit them on a metronome.
          RandomizedDelaySec = "45s";
          Persistent = true;
        };
      };
    };
  };
}
