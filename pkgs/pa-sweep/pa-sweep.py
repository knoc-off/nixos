#!/usr/bin/env python3
"""Room-reading self-test: play an exponential sine sweep out the default sink,
record the default source, deconvolve to an impulse response, and report
ring-prone frequencies (ranked by prominence x decay) as paste-ready pa-voice
notch bands. Pick devices with the normal default-sink/source controls."""
import argparse
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime

import numpy as np
from scipy import signal as sps
from scipy.io import wavfile

FS = 48000
OCT = 2 ** (1 / 6)  # 1/6-octave smoothing / peak spacing


def pw_dump():
    return json.loads(subprocess.check_output(["pw-dump"]))


def default_sink(dump):
    return _default(dump, "default.audio.sink")


def default_source(dump):
    return _default(dump, "default.audio.source")


def _default(dump, key):
    for o in dump:
        if o.get("props", {}).get("metadata.name") == "default":
            for m in o.get("metadata", []):
                if m.get("key") == key:
                    return m["value"]["name"]
    return None


def loopback_active(dump):
    for o in dump:
        p = o.get("info", {}).get("props", {})
        if "pa-monitor" in (p.get("node.name", "") + p.get("node.group", "")):
            return True
    return False


def ess(f1, f2, T, fs):
    N = int(T * fs)
    t = np.arange(N) / fs
    R = np.log(f2 / f1)
    x = np.sin(2 * np.pi * f1 * T / R * (np.exp(t * R / T) - 1.0))
    # raised-cosine fades (5 ms) to kill clicks
    nf = int(0.005 * fs)
    w = np.hanning(2 * nf)
    x[:nf] *= w[:nf]
    x[-nf:] *= w[nf:]
    inv = x[::-1] * np.exp(-t * R / T)  # Farina inverse filter (+6 dB/oct)
    return x.astype(np.float32), inv.astype(np.float32)


def capture(sink, mic, sweep, tail, level):
    d = tempfile.mkdtemp(prefix="pa-sweep-")
    swp, rec = os.path.join(d, "sweep.wav"), os.path.join(d, "rec.wav")
    wavfile.write(swp, FS, (sweep * level).astype(np.float32))
    r = subprocess.Popen(
        ["pw-record", "--target", mic, "--rate", str(FS),
         "--channels", "1", "--format", "f32", rec],
        stderr=subprocess.DEVNULL,
    )
    time.sleep(0.5)
    subprocess.run(["pw-play", "--target", sink, swp], stderr=subprocess.DEVNULL)
    time.sleep(tail)
    r.send_signal(signal.SIGINT)
    r.wait()
    _, data = wavfile.read(rec)
    if data.ndim > 1:
        data = data.mean(axis=1)
    return data.astype(np.float64)


def deconvolve(rec, inv):
    ir = sps.fftconvolve(rec, inv)
    pk = int(np.argmax(np.abs(ir)))
    lo = max(0, pk - int(0.005 * FS))
    hi = min(len(ir), pk + int(0.5 * FS))
    seg = ir[lo:hi]
    return seg / (np.max(np.abs(seg)) + 1e-12)


def frac_oct_smooth(f, mag_db):
    out = np.empty_like(mag_db)
    for i, fc in enumerate(f):
        m = (f >= fc / OCT) & (f <= fc * OCT)
        out[i] = mag_db[m].mean() if m.any() else mag_db[i]
    return out


def refine_center(f, mag, fc, lo_b, hi_b):
    """Smoothing biases the peak location; snap back to the true local maximum
    of the unsmoothed magnitude within +-1/8 octave, clamped to the geometric
    midpoints to adjacent peaks so we never grab a neighbouring mode."""
    q = 2 ** (1 / 8)
    lo, hi = max(fc / q, lo_b), min(fc * q, hi_b)
    sel = np.where((f >= lo) & (f <= hi))[0]
    if len(sel) == 0:
        return fc
    j = int(sel[np.argmax(mag[sel])])
    if 0 < j < len(mag) - 1:
        y0, y1, y2 = mag[j - 1], mag[j], mag[j + 1]
        denom = y0 - 2 * y1 + y2
        delta = (y0 - y2) / (2 * denom) if denom != 0 else 0.0
        return float(f[j] + delta * (f[1] - f[0]))
    return float(f[j])


def decay_ms(ir, fc):
    lo, hi = fc / OCT, fc * OCT
    lo = max(lo, 20.0)
    hi = min(hi, FS / 2 * 0.99)
    b, a = sps.butter(2, [lo, hi], btype="band", fs=FS)
    y = sps.lfilter(b, a, ir)
    e = np.cumsum(y[::-1] ** 2)[::-1]  # Schroeder backward integration
    edc = 10 * np.log10(e / (e[0] + 1e-20) + 1e-20)
    idx = np.where((edc <= -5) & (edc >= -25))[0]
    if len(idx) < 5:
        return 0.0
    t = idx / FS
    slope = np.polyfit(t, edc[idx], 1)[0]  # dB/s
    if slope >= 0:
        return 0.0
    return float(-60.0 / slope * 1000.0)  # T60 in ms


def analyze(ir, band, prom):
    H = np.fft.rfft(ir)
    f = np.fft.rfftfreq(len(ir), 1 / FS)
    mag = 20 * np.log10(np.abs(H) + 1e-12)
    sm = frac_oct_smooth(f, mag)
    m = (f >= band[0]) & (f <= band[1])
    fb, sb = f[m], sm[m]
    df = fb[1] - fb[0]
    dist = max(1, int((band[0] * (OCT - 1)) / df))  # ~1/6-oct min spacing
    pk, props = sps.find_peaks(sb, prominence=prom, distance=dist)
    peaks = []
    for order, i in enumerate(pk):
        fsm = float(fb[i])
        lo_b = float(np.sqrt(fb[pk[order - 1]] * fsm)) if order > 0 else fsm / OCT
        hi_b = float(np.sqrt(fb[pk[order + 1]] * fsm)) if order < len(pk) - 1 else fsm * OCT
        fc = refine_center(f, mag, fsm, lo_b, hi_b)
        pr = float(props["prominences"][order])
        half = sb[i] - 3.0  # -3 dB bandwidth -> Q
        left = i
        while left > 0 and sb[left] > half:
            left -= 1
        right = i
        while right < len(sb) - 1 and sb[right] > half:
            right += 1
        bw = max(fb[right] - fb[left], df)
        q = fc / bw
        dcy = decay_ms(ir, fc)
        peaks.append({"freq": fc, "prom_db": pr, "q_est": q, "decay_ms": dcy})
    for p in peaks:
        p["ring_score"] = p["prom_db"] * (1 + np.log10(1 + p["decay_ms"] / 100))
    peaks.sort(key=lambda x: x["ring_score"], reverse=True)
    return peaks


def suggest(pk):
    g = -min(12.0, max(4.0, pk["prom_db"] + min(2.0, pk["decay_ms"] / 300)))
    q = min(14.0, max(8.0, pk["q_est"]))
    return round(g, 1), round(q, 1)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--level", type=float, default=0.25, help="playback amplitude 0-1 (~-12 dBFS)")
    ap.add_argument("--duration", type=float, default=6.0, help="sweep length (s)")
    ap.add_argument("--f-lo", type=float, default=50.0, help="sweep start freq")
    ap.add_argument("--f-hi", type=float, default=10000.0, help="sweep end freq")
    ap.add_argument("--band", type=float, nargs=2, default=[120.0, 6000.0], help="analysis band")
    ap.add_argument("--prominence", type=float, default=3.0, help="min peak prominence (dB)")
    ap.add_argument("--repeats", type=int, default=2, help="sweeps to average")
    ap.add_argument("--tail", type=float, default=1.0, help="reverb-tail capture (s)")
    ap.add_argument("--out", default=os.path.expanduser("~/pa-sweep"), help="report dir")
    a = ap.parse_args()

    dump = pw_dump()
    if loopback_active(dump):
        sys.exit("pa-sweep: pa-monitor/pw-loopback is running -- stop it first "
                 "(measuring with the live loop = real feedback).")
    sink = default_sink(dump)
    mic = default_source(dump)
    if not sink or not mic:
        sys.exit(f"pa-sweep: could not resolve default sink={sink} / source={mic}")
    print(f"pa-sweep: sink={sink}\n          mic ={mic}")
    print("Place mic & speakers in final positions, quiet room, hands off. Sweeping...")
    for c in (3, 2, 1):
        print(f"  {c}...")
        time.sleep(1)

    x, inv = ess(a.f_lo, a.f_hi, a.duration, FS)
    irs = []
    for n in range(a.repeats):
        rec = capture(sink, mic, x, a.tail, a.level)
        irs.append(deconvolve(rec, inv))
        print(f"  captured {n + 1}/{a.repeats}")
    length = min(len(i) for i in irs)
    ir = np.mean([i[:length] for i in irs], axis=0)

    peaks = analyze(ir, a.band, a.prominence)
    print(f"\n  {'#':>2}  {'freq':>7}  {'prom':>6}  {'Qest':>5}  {'decay':>7}  {'-> notch':>14}")
    bands = []
    for i, p in enumerate(peaks, 1):
        g, q = suggest(p)
        bands.append({**p, "sug_gain": g, "sug_q": q})
        print(f"  {i:>2}  {p['freq']:>6.0f}H  {p['prom_db']:>5.1f}d  {p['q_est']:>5.1f}  "
              f"{p['decay_ms']:>6.0f}m  g={g:>5} q={q:>4}")

    print("\n  Paste-ready pa-voice notch bands (sorted by freq; prune as you like):")
    for j, p in enumerate(sorted(bands, key=lambda x: x["freq"]), 1):
        print(f'    band{j} = band {{freq = {p["freq"]:.0f}.0; gain = {p["sug_gain"]}; '
              f'q = {p["sug_q"]}; type = "Bell";}};')
    print(f'    # + band0 Hi-pass, final Hi-shelf; num-bands = {len(bands) + 2}')

    os.makedirs(a.out, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    safe = sink.replace("/", "_")
    path = os.path.join(a.out, f"reading-{safe}-{stamp}.json")
    with open(path, "w") as fh:
        json.dump({"sink": sink, "mic": mic, "params": vars(a), "peaks": bands}, fh, indent=2)
    print(f"\n  saved: {path}")


if __name__ == "__main__":
    main()
