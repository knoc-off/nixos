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

The `halo` is a *hull layer*: it draws a scale-aware halo circle at
Fiji's centroid so the answer is easy to spot against the much larger
New Zealand. It sits above the base and below the answer in source
order, so the real island draws on top of its halo. Like any overlay
layer it fades in on the back. Fiji straddles the antimeridian; the
halo centroid is computed in the same rotated frame the rest of the
pipeline uses, so it lands correctly.

#geography #pacific
