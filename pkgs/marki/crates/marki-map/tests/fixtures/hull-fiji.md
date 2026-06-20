Which tiny Pacific island nation is highlighted?

```map
size = [600, 400]

[layers.base]
features = ["country/NZL", "country/FJI"]

[layers.halo]
[layers.halo.hull]
features = ["country/FJI"]

[layers.answer]
highlights = ["country/FJI"]
```

---

**Fiji**.

The `halo` is a *hull layer*: it wraps Fiji in a rounded convex hull —
one smooth, padded shape enclosing the whole archipelago — so the answer
is easy to spot against the much larger New Zealand. It sits above the
base and below the answer in source order, so the real islands draw on
top of their hull. Like any overlay layer it fades in on the back. Fiji
straddles the antimeridian; the hull is computed in the same rotated
frame the rest of the pipeline uses, so it lands correctly.

#geography #pacific
