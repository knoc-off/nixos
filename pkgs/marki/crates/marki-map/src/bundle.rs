//! Parallel strands for lines sharing track (transit-map style).
//!
//! Works on projected pixel polylines. Each strand (one per
//! `bundle_key`) is resampled every [`STEP`] px; at every sample the
//! other strands running parallel within `snap_px` form its sharing
//! set, and its rank in that set (by slot order) picks an offset
//! across the track. Offsets are eased along the line and applied along
//! the line's normal.
//!
//! Lines can run the same track in opposite directions, so each offset
//! is signed against the direction of the lowest-ranked strand present,
//! not against the line's own direction -- otherwise a reversed line
//! would swap sides.
//!
//! ponytail: each strand ranks against the strands *it* sees, so where
//! A sees {A,B,C} but B only {A,B} (C near A's edge of the snap
//! distance) their slots can briefly disagree; easing hides most of it.
//! Upgrade path: cluster samples into shared runs and rank once per run.

use crate::dsl::BundleSpec;
use std::collections::HashMap;

pub type Line = Vec<(f64, f64)>;

/// Resampling interval, px.
const STEP: f64 = 2.0;
/// Parallel if |cos angle| exceeds this.
const PARALLEL: f64 = 0.9;
/// Output simplification tolerance, px.
const TIDY: f64 = 0.25;

/// Shift `strands` (each a set of polylines, given in slot order) into
/// parallel strands. Returns the same shape; lines that share no track
/// come back unchanged.
pub fn bundle(strands: &[Vec<Line>], p: &BundleSpec) -> Vec<Vec<Line>> {
    let cell = p.snap_px.max(STEP);
    let key = |(x, y): (f64, f64)| ((x / cell).floor() as i64, (y / cell).floor() as i64);
    // Samples per (strand, line): points and unit directions. Lines of
    // one strand that overlap are turned to run the same way, so the
    // strand has one direction on shared track (else its own lines
    // would take opposite sides).
    let samples: Vec<Vec<(Line, Line)>> = strands
        .iter()
        .map(|ls| {
            let mut own: HashMap<(i64, i64), Vec<((f64, f64), (f64, f64))>> = HashMap::new();
            ls.iter()
                .map(|l| {
                    let mut pts = resample(l);
                    let mut d = directions(&pts);
                    let mut agree = 0i64;
                    for (&pt, &dir) in pts.iter().zip(&d) {
                        let (cx, cy) = key(pt);
                        let hit = (cx - 1..=cx + 1)
                            .flat_map(|gx| (cy - 1..=cy + 1).map(move |gy| (gx, gy)))
                            .filter_map(|c| own.get(&c))
                            .flatten()
                            .find(|(q, qd)| dist(*q, pt) <= p.snap_px && dot(dir, *qd).abs() > PARALLEL);
                        if let Some((_, qd)) = hit {
                            agree += if dot(dir, *qd) > 0.0 { 1 } else { -1 };
                        }
                    }
                    if agree < 0 {
                        pts.reverse();
                        d.reverse();
                        d.iter_mut().for_each(|v| *v = (-v.0, -v.1));
                    }
                    for (&pt, &dir) in pts.iter().zip(&d) {
                        own.entry(key(pt)).or_default().push((pt, dir));
                    }
                    (pts, d)
                })
                .collect()
        })
        .collect();
    let mut grid: HashMap<(i64, i64), Vec<(usize, usize, usize)>> = HashMap::new();
    for (s, lines) in samples.iter().enumerate() {
        for (l, (pts, _)) in lines.iter().enumerate() {
            for (i, &pt) in pts.iter().enumerate() {
                grid.entry(key(pt)).or_default().push((s, l, i));
            }
        }
    }
    let min_run = (p.min_run_px / STEP).ceil() as usize;
    let half_window = (p.ease_px / (2.0 * STEP)).round() as usize;

    samples
        .iter()
        .enumerate()
        .map(|(a, lines)| {
            lines
                .iter()
                .zip(&strands[a])
                .map(|((pts, dirs), orig)| {
                    // Per other strand: its nearest parallel sample's direction, if within snap.
                    let mut near: HashMap<usize, Vec<Option<(f64, f64)>>> = HashMap::new();
                    for (i, (&pt, &d)) in pts.iter().zip(dirs).enumerate() {
                        let (cx, cy) = key(pt);
                        let mut best: HashMap<usize, (f64, (f64, f64))> = HashMap::new();
                        for gx in cx - 1..=cx + 1 {
                            for gy in cy - 1..=cy + 1 {
                                for &(b, bl, bi) in grid.get(&(gx, gy)).map(Vec::as_slice).unwrap_or(&[]) {
                                    if b == a {
                                        continue;
                                    }
                                    let q = samples[b][bl].0[bi];
                                    let dist = ((q.0 - pt.0).powi(2) + (q.1 - pt.1).powi(2)).sqrt();
                                    let bd = samples[b][bl].1[bi];
                                    if dist <= p.snap_px
                                        && dot(d, bd).abs() > PARALLEL
                                        && best.get(&b).is_none_or(|(bd0, _)| dist < *bd0)
                                    {
                                        best.insert(b, (dist, bd));
                                    }
                                }
                            }
                        }
                        for (b, (_, bd)) in best {
                            near.entry(b).or_insert_with(|| vec![None; pts.len()])[i] = Some(bd);
                        }
                    }
                    for v in near.values_mut() {
                        drop_short_runs(v, min_run);
                    }
                    let mut off: Vec<f64> = (0..pts.len())
                        .map(|i| {
                            let mut members: Vec<usize> =
                                near.iter().filter(|(_, v)| v[i].is_some()).map(|(b, _)| *b).collect();
                            if members.is_empty() {
                                return 0.0;
                            }
                            members.push(a);
                            members.sort_unstable();
                            let n = members.len() as f64;
                            let rank = members.iter().position(|&m| m == a).unwrap_or(0) as f64;
                            let lowest = members[0];
                            let reference = if lowest == a { dirs[i] } else { near[&lowest][i].unwrap_or(dirs[i]) };
                            let sign = if dot(dirs[i], reference) < 0.0 { -1.0 } else { 1.0 };
                            let cap = p.snap_px * n / 2.0;
                            ((rank - (n - 1.0) / 2.0) * p.spacing_px * sign).clamp(-cap, cap)
                        })
                        .collect();
                    if off.iter().all(|o| *o == 0.0) {
                        return orig.clone();
                    }
                    let closed = pts.len() > 2 && dist(pts[0], pts[pts.len() - 1]) < 1e-6;
                    // Two box passes: a ramp roughly `ease_px` long.
                    for _ in 0..2 {
                        off = box_filter(&off, half_window, closed);
                    }
                    let shifted: Line = pts
                        .iter()
                        .zip(dirs)
                        .zip(&off)
                        .map(|((&(x, y), &(dx, dy)), &o)| (x - dy * o, y + dx * o))
                        .collect();
                    crate::simplify::simplify(&shifted, TIDY)
                })
                .collect()
        })
        .collect()
}

fn dot(a: (f64, f64), b: (f64, f64)) -> f64 {
    a.0 * b.0 + a.1 * b.1
}

fn dist(a: (f64, f64), b: (f64, f64)) -> f64 {
    ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt()
}

/// Points every [`STEP`] px along `line`, plus its last point.
fn resample(line: &Line) -> Line {
    let Some(&first) = line.first() else { return Vec::new() };
    let mut out = vec![first];
    let mut carry = 0.0; // distance walked since the last emitted sample
    for w in line.windows(2) {
        let (a, b) = (w[0], w[1]);
        let len = dist(a, b);
        let mut t = STEP - carry;
        while t <= len {
            out.push((a.0 + (b.0 - a.0) * t / len, a.1 + (b.1 - a.1) * t / len));
            t += STEP;
        }
        carry = (carry + len) % STEP;
    }
    let last = line[line.len() - 1];
    if dist(out[out.len() - 1], last) > 1e-9 {
        out.push(last);
    }
    out
}

/// Unit tangent at each sample (central difference).
fn directions(pts: &Line) -> Line {
    let n = pts.len();
    (0..n)
        .map(|i| {
            let (a, b) = (pts[i.saturating_sub(1)], pts[(i + 1).min(n - 1)]);
            let (dx, dy) = (b.0 - a.0, b.1 - a.1);
            let len = (dx * dx + dy * dy).sqrt();
            if len < 1e-12 { (1.0, 0.0) } else { (dx / len, dy / len) }
        })
        .collect()
}

/// Clear runs of `Some` shorter than `min` samples.
fn drop_short_runs(v: &mut [Option<(f64, f64)>], min: usize) {
    let mut i = 0;
    while i < v.len() {
        if v[i].is_none() {
            i += 1;
            continue;
        }
        let start = i;
        while i < v.len() && v[i].is_some() {
            i += 1;
        }
        if i - start < min {
            v[start..i].iter_mut().for_each(|x| *x = None);
        }
    }
}

/// Moving average over `2r+1` samples; wraps around on closed lines,
/// clamps at the ends of open ones.
fn box_filter(v: &[f64], r: usize, closed: bool) -> Vec<f64> {
    let n = v.len() as i64;
    if r == 0 || n < 2 {
        return v.to_vec();
    }
    let r = r as i64;
    (0..n)
        .map(|i| {
            let sum: f64 = (i - r..=i + r)
                .map(|j| v[if closed { j.rem_euclid(n - 1) } else { j.clamp(0, n - 1) } as usize])
                .sum();
            sum / (2 * r + 1) as f64
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec() -> BundleSpec {
        BundleSpec::default()
    }

    fn h(y: f64, x0: f64, x1: f64) -> Line {
        vec![(x0, y), (x1, y)]
    }

    /// y of `line` at x (lines here are horizontal-ish in the middle).
    fn y_at(line: &Line, x: f64) -> f64 {
        line.windows(2)
            .find(|w| (w[0].0 - x) * (w[1].0 - x) <= 0.0 && w[0].0 != w[1].0)
            .map(|w| w[0].1 + (w[1].1 - w[0].1) * (x - w[0].0) / (w[1].0 - w[0].0))
            .unwrap()
    }

    #[test]
    fn identical_lines_split_spacing_apart() {
        let out = bundle(&[vec![h(50.0, 0.0, 200.0)], vec![h(50.0, 0.0, 200.0)]], &spec());
        let (a, b) = (y_at(&out[0][0], 100.0), y_at(&out[1][0], 100.0));
        assert!(((a - b).abs() - 2.5).abs() < 1e-6, "{a} {b}");
        assert!(((a + b) / 2.0 - 50.0).abs() < 1e-6, "centred on the track: {a} {b}");
    }

    #[test]
    fn a_reversed_line_keeps_its_side() {
        let same = bundle(&[vec![h(50.0, 0.0, 200.0)], vec![h(50.0, 0.0, 200.0)]], &spec());
        let rev = bundle(&[vec![h(50.0, 0.0, 200.0)], vec![h(50.0, 200.0, 0.0)]], &spec());
        for s in 0..2 {
            assert!((y_at(&same[s][0], 100.0) - y_at(&rev[s][0], 100.0)).abs() < 1e-6, "strand {s}");
        }
    }

    #[test]
    fn a_strands_own_opposite_lines_stay_together() {
        // Strand 0 holds the track twice, once each way (S2 + S25 in one layer).
        let out = bundle(&[vec![h(50.0, 0.0, 200.0), h(50.0, 200.0, 0.0)], vec![h(50.0, 0.0, 200.0)]], &spec());
        let (a0, a1, b) = (y_at(&out[0][0], 100.0), y_at(&out[0][1], 100.0), y_at(&out[1][0], 100.0));
        assert!((a0 - a1).abs() < 1e-6 && ((a0 - b).abs() - 2.5).abs() < 1e-6, "{a0} {a1} {b}");
    }

    #[test]
    fn crossing_line_is_not_shifted_and_does_not_shift() {
        let cross: Line = vec![(100.0, 0.0), (100.0, 100.0)];
        let out = bundle(&[vec![h(50.0, 0.0, 200.0)], vec![h(50.0, 0.0, 200.0)], vec![cross.clone()]], &spec());
        assert_eq!(out[2][0], cross);
        let (a, b) = (y_at(&out[0][0], 100.0), y_at(&out[1][0], 100.0));
        assert!(((a - b).abs() - 2.5).abs() < 1e-6, "two strands at the crossing: {a} {b}");
    }

    #[test]
    fn three_strands_use_three_slots() {
        let l = h(50.0, 0.0, 300.0);
        let out = bundle(&[vec![l.clone()], vec![l.clone()], vec![l]], &spec());
        let ys: Vec<f64> = (0..3).map(|s| y_at(&out[s][0], 150.0)).collect();
        assert!((ys[0] - ys[1]).abs() > 2.4 && (ys[1] - ys[2]).abs() > 2.4 && (ys[1] - 50.0).abs() < 1e-6, "{ys:?}");
    }

    #[test]
    fn short_overlap_is_ignored() {
        // B runs along A for 10 px (< min_run_px 20), then turns away.
        let a = h(50.0, 0.0, 200.0);
        let b: Line = vec![(95.0, 0.0), (95.0, 50.0), (105.0, 50.0), (105.0, 100.0)];
        let out = bundle(&[vec![a.clone()], vec![b.clone()]], &spec());
        assert_eq!(out[0][0], a);
        assert_eq!(out[1][0], b);
    }

    #[test]
    fn strands_ease_in_and_out() {
        // B shares A's middle 100 px only; A must not jump.
        let a = h(50.0, 0.0, 300.0);
        let b: Line = vec![(100.0, 0.0), (100.0, 50.0), (200.0, 50.0), (200.0, 100.0)];
        let out = bundle(&[vec![a], vec![b]], &spec());
        let ys: Vec<f64> = (0..=300).step_by(2).map(|x| y_at(&out[0][0], x as f64)).collect();
        assert!((ys[0] - 50.0).abs() < 1e-6 && (ys[75] - 50.0).abs() > 1.0, "{ys:?}");
        let max_step = ys.windows(2).map(|w| (w[1] - w[0]).abs()).fold(0.0, f64::max);
        assert!(max_step < 0.6, "no kink: {max_step}");
    }

    #[test]
    fn closed_ring_bundles() {
        let sq: Line = vec![(0.0, 0.0), (100.0, 0.0), (100.0, 100.0), (0.0, 100.0), (0.0, 0.0)];
        let out = bundle(&[vec![sq.clone()], vec![sq]], &spec());
        assert!((y_at(&out[0][0], 50.0) - y_at(&out[1][0], 50.0)).abs() > 2.4);
    }
}
