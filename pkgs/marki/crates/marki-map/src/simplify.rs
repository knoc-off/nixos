//! Douglas-Peucker polyline simplification.
//!
//! Operates on projected (pixel) coordinates so the tolerance is in
//! pixels — a 0.5 px tolerance removes sub-pixel detail that wouldn't
//! be visible in the rendered SVG. Because the projector maps degrees
//! to pixels proportional to zoom, this auto-adapts: a 600 px Germany
//! keeps fine detail while a 600 px world map aggressively simplifies.

/// Simplify a polyline using the Douglas-Peucker algorithm.
/// `epsilon` is the maximum perpendicular distance (in the same units
/// as the input coordinates — typically projected pixels) a point may
/// deviate from the simplified line before it's kept.
///
/// Returns the simplified points. A ring with fewer than 3 output
/// points is returned unchanged (can't simplify a triangle further
/// without collapsing it).
pub fn simplify(pts: &[(f64, f64)], epsilon: f64) -> Vec<(f64, f64)> {
    if pts.len() < 3 || epsilon <= 0.0 {
        return pts.to_vec();
    }
    let mut keep = vec![false; pts.len()];
    keep[0] = true;
    keep[pts.len() - 1] = true;
    dp_recurse(pts, 0, pts.len() - 1, epsilon, &mut keep);
    pts.iter()
        .zip(keep.iter())
        .filter(|(_, k)| **k)
        .map(|(&p, _)| p)
        .collect()
}

fn dp_recurse(pts: &[(f64, f64)], start: usize, end: usize, epsilon: f64, keep: &mut [bool]) {
    if end <= start + 1 {
        return;
    }
    let mut max_dist = 0.0;
    let mut max_idx = start;
    let (ax, ay) = pts[start];
    let (bx, by) = pts[end];
    let dx = bx - ax;
    let dy = by - ay;
    let len_sq = dx * dx + dy * dy;

    for i in (start + 1)..end {
        let (px, py) = pts[i];
        let dist = if len_sq < 1e-18 {
            // Start == end: use point-to-point distance.
            ((px - ax).powi(2) + (py - ay).powi(2)).sqrt()
        } else {
            // Perpendicular distance from point to line segment.
            ((dy * px - dx * py + bx * ay - by * ax) / len_sq.sqrt()).abs()
        };
        if dist > max_dist {
            max_dist = dist;
            max_idx = i;
        }
    }
    if max_dist > epsilon {
        keep[max_idx] = true;
        dp_recurse(pts, start, max_idx, epsilon, keep);
        dp_recurse(pts, max_idx, end, epsilon, keep);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn collinear_points_removed() {
        // Straight horizontal line — all interior points are collinear.
        let pts: Vec<(f64, f64)> = (0..10).map(|i| (i as f64, 0.0)).collect();
        let out = simplify(&pts, 0.5);
        assert_eq!(out.len(), 2); // just endpoints
        assert_eq!(out[0], (0.0, 0.0));
        assert_eq!(out[1], (9.0, 0.0));
    }

    #[test]
    fn square_corners_preserved() {
        let pts = vec![
            (0.0, 0.0),
            (10.0, 0.0),
            (10.0, 10.0),
            (0.0, 10.0),
            (0.0, 0.0),
        ];
        let out = simplify(&pts, 0.5);
        assert_eq!(out.len(), 5); // all corners kept
    }

    #[test]
    fn zero_tolerance_is_passthrough() {
        let pts = vec![(0.0, 0.0), (1.0, 0.1), (2.0, 0.0)];
        let out = simplify(&pts, 0.0);
        assert_eq!(out.len(), 3);
    }

    #[test]
    fn too_few_points_unchanged() {
        let pts = vec![(0.0, 0.0), (1.0, 1.0)];
        assert_eq!(simplify(&pts, 1.0).len(), 2);
        assert_eq!(simplify(&[], 1.0).len(), 0);
    }

    #[test]
    fn significant_deviation_kept() {
        // Triangle: middle point deviates 5.0 from the baseline.
        let pts = vec![(0.0, 0.0), (5.0, 5.0), (10.0, 0.0)];
        let out = simplify(&pts, 1.0);
        assert_eq!(out.len(), 3); // peak kept
        let out2 = simplify(&pts, 10.0);
        assert_eq!(out2.len(), 2); // peak removed
    }
}
