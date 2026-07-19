import json
import os
import urllib.request
from datetime import date, datetime
from email.utils import parsedate_to_datetime

SLOT_TAGS = ("breakfast", "lunch", "dinner")


def read_credential(name):
    creds = os.environ["CREDENTIALS_DIRECTORY"]
    with open(os.path.join(creds, name)) as f:
        return f.readline().strip()


def fetch_plans(api_base, household_id, token):
    url = f"{api_base}/api/household/{household_id}/planner"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.load(resp)


def parse_date(raw):
    if raw is None:
        return None

    # KitchenOwl always serialises datetimes as milliseconds since epoch.
    # Unscheduled ("planned, no date") entries use a date.min sentinel,
    # which serialises to a huge negative value - not a real date.
    if isinstance(raw, (int, float)):
        try:
            return datetime.fromtimestamp(raw / 1000).date()
        except (OverflowError, OSError, ValueError):
            return None

    # ISO-8601 date
    if isinstance(raw, str):
        try:
            return date.fromisoformat(raw[:10])
        except ValueError:
            pass

        # RFC2822/HTTP date
        try:
            return parsedate_to_datetime(raw).date()
        except (TypeError, ValueError):
            pass
    return None


def recipe_slots(recipe):
    # Which meal slots a recipe belongs to, based on its tags. Untagged
    # (no recognised meal tag) defaults to dinner.
    tags = {t.get("name", "").strip().lower() for t in recipe.get("tags") or []}
    slots = {s for s in SLOT_TAGS if s in tags}
    return slots or {"dinner"}


def load_state(path):
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return {tuple(pair) for pair in json.load(f)}


def save_state(path, keys):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(sorted(keys), f)
    os.replace(tmp, path)


def publish(ntfy_url, topic, token, title, message, tags, click_url):
    req = urllib.request.Request(
        f"{ntfy_url}/{topic}",
        data=message.encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Title": title,
            "Priority": "3",
            "Tags": tags,
            "Click": click_url,
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        resp.read()


def current_slot(times):
    # Pick the latest configured meal time that is <= now; fall back to the
    # earliest slot if now precedes all of them.
    now = datetime.now().strftime("%H:%M")
    ordered = sorted(times.items(), key=lambda kv: kv[1])
    selected = ordered[0][0]
    for slot, t in ordered:
        if t <= now:
            selected = slot
    return selected


def main():
    api_base = os.environ["KO_API_BASE"]
    household_id = os.environ["KO_HOUSEHOLD_ID"]
    ntfy_url = os.environ["KO_NTFY_URL"]
    topic = os.environ["KO_NTFY_TOPIC"]
    state_dir = os.environ.get("STATE_DIRECTORY", "/var/lib/kitchenowl-meal-plan")
    times = {
        "breakfast": os.environ["KO_TIME_BREAKFAST"],
        "lunch": os.environ["KO_TIME_LUNCH"],
        "dinner": os.environ["KO_TIME_DINNER"],
    }

    click_url = f"https://app.kitchenowl.org/household/{household_id}/planner"
    baseline_path = os.path.join(state_dir, "planner_baseline.json")

    def click_for(recipe_ids):
        # Deep-link to the recipe when a notification is about a single
        # meal; otherwise fall back to the planner overview.
        ids = {r for r in recipe_ids if r}
        if len(ids) == 1:
            rid = next(iter(ids))
            return f"https://app.kitchenowl.org/household/{household_id}/recipes/details/{rid}"
        return click_url

    api_token = read_credential("api-token")
    ntfy_token = read_credential("ntfy-token")

    plans = fetch_plans(api_base, household_id, api_token)

    # --- Newly added recipes -------------------------------------------
    current = {}
    for p in plans:
        recipe = p.get("recipe") or {}
        key = (str(p.get("recipe_id")), str(p.get("cooking_date")))
        current[key] = recipe.get("name", "")

    baseline = load_state(baseline_path)
    if baseline is None:
        # First run: silent baseline, no "added" notification.
        save_state(baseline_path, current.keys())
    else:
        added_keys = current.keys() - baseline
        if added_keys:
            lines = sorted(current[k] for k in added_keys if current[k])
            publish(
                ntfy_url,
                topic,
                ntfy_token,
                "Added to meal plan",
                "\n".join(lines),
                "date",
                click_for(k[0] for k in added_keys),
            )
            print(f"kitchenowl-meal-plan: {len(lines)} added")
        save_state(baseline_path, current.keys())

    # --- Today's meals for the current slot -----------------------------
    slot = current_slot(times)
    today = date.today()
    due = [
        (str(p.get("recipe_id")), (p.get("recipe") or {}).get("name", ""))
        for p in plans
        if parse_date(p.get("cooking_date")) == today
        and slot in recipe_slots(p.get("recipe") or {})
    ]
    names = sorted({name for _, name in due if name})
    if names:
        publish(
            ntfy_url,
            topic,
            ntfy_token,
            f"{slot.capitalize()} today",
            "\n".join(names),
            "cooking",
            click_for(rid for rid, _ in due),
        )
        print(f"kitchenowl-meal-plan: {len(names)} due for {slot}")


if __name__ == "__main__":
    main()
