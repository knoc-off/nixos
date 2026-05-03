What two Pacific countries are shown?

```map
size = [600, 400]

[layers.base]
features = ["country/NZL", "country/FJI"]

[layers.answer]
highlights = ["country/FJI"]
```

---

**New Zealand and Fiji**.

Both straddle the antimeridian — the renderer picks an optimal
central meridian automatically so the bbox stays tight instead of
spanning ~350° of empty Pacific Ocean.

#geography #pacific
