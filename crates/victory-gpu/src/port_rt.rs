//! Opt-in renderer port for avoiding waits around placed copies
//! (`VICTORY_PORT_RT=1`, off by default).

use std::sync::atomic::{AtomicU64, Ordering::Relaxed};

pub(crate) fn on() -> bool {
    #[cfg(all(windows, feature = "diagnostics"))]
    if let Some(on) = crate::ab::pick("VICTORY_PORT_RT") {
        return on;
    }
    #[cfg(test)]
    if PORT_RT_IN_TEST.get() {
        return true;
    }
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ON.get_or_init(|| crate::switch::on("VICTORY_PORT_RT"))
}

#[cfg(test)]
thread_local! {
    pub(crate) static PORT_RT_IN_TEST: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

static COUNTS: [AtomicU64; 5] = [const { AtomicU64::new(0) }; 5];
pub(crate) const BY_ORDER: usize = 0;
pub(crate) const CUT: usize = 1;
pub(crate) const SAME_LIST: usize = 2;
pub(crate) const REFUSED_OFF: usize = 3;
pub(crate) const FORWARDED: usize = 4;

pub(crate) fn count(what: usize) {
    COUNTS[what].fetch_add(1, Relaxed);
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum Seen {
    Placed {
        dst: usize,
        src: usize,
        len: usize,
        from_upload: bool,
    },
    Writes(usize, usize),
    Anything,
    Nothing,
}

/// Finds an earlier placed copy whose source bytes can supply this fill.
/// `steps` is traversed newest first.
pub(crate) fn forwarded(
    steps: impl Iterator<Item = Seen>,
    src: usize,
    len: usize,
) -> Option<usize> {
    let to = src.checked_add(len)?;
    if len == 0 {
        return None;
    }
    let meet = |a: usize, b: usize, c: usize, d: usize| a < d && c < b;
    let mut later: Vec<(usize, usize)> = Vec::new();
    for step in steps {
        let (from, until) = match step {
            Seen::Placed { dst, src: copy_src, len: copy_len, from_upload } => {
                let dst_end = dst.checked_add(copy_len)?;
                let copy_src_end = copy_src.checked_add(copy_len)?;
                if meet(dst, dst_end, src, to) {
                    let holds = dst <= src && to <= dst_end;
                    let moved = later.iter().any(|&(a, b)| meet(a, b, copy_src, copy_src_end));
                    let apart = !meet(copy_src, copy_src_end, dst, dst_end);
                    return (holds && !moved && apart && from_upload)
                        .then(|| copy_src.checked_add(src - dst))
                        .flatten();
                }
                (dst, dst_end)
            }
            Seen::Writes(from, until) => (from, until),
            Seen::Anything => return None,
            Seen::Nothing => continue,
        };
        if meet(from, until, src, to) {
            return None;
        }
        later.push((from, until));
    }
    None
}

pub(crate) fn line(frames: f64) {
    let frames = frames.max(1.0);
    let n: Vec<f64> = COUNTS.iter().map(|c| c.swap(0, Relaxed) as f64 / frames).collect();
    if on() || n.iter().any(|&v| v > 0.0) {
        tracing::info!(
            "renderer port RT (VICTORY_PORT_RT={}) per frame: {:.2} submissions let through by placed-copy order, \
             {:.2} cut behind a placed copy, {:.2} left to wait in the same list, {:.2} refused with the switch off; \
             {:.1} fills forwarded from a placed copy's source",
            u8::from(on()),
            n[BY_ORDER],
            n[CUT],
            n[SAME_LIST],
            n[REFUSED_OFF],
            n[FORWARDED],
        );
    }
}

#[cfg(test)]
mod tests {
    use super::{Seen, forwarded};

    fn placed(dst: usize, src: usize, len: usize) -> Seen {
        Seen::Placed { dst, src, len, from_upload: true }
    }

    fn walk(steps: &[Seen], src: usize, len: usize) -> Option<usize> {
        forwarded(steps.iter().rev().copied(), src, len)
    }

    #[test]
    fn forwards_ranges_held_by_the_latest_placed_copy() {
        assert_eq!(walk(&[placed(0x1000, 0x8000, 0xb0)], 0x1000, 0xb0), Some(0x8000));
        assert_eq!(walk(&[placed(0x1000, 0x8000, 0x100)], 0x1040, 0x20), Some(0x8040));
        let between = [
            placed(0x1000, 0x8000, 0xb0),
            Seen::Nothing,
            Seen::Writes(0x9000, 0x9100),
            placed(0x3000, 0x4000, 16),
        ];
        assert_eq!(walk(&between, 0x1000, 0xb0), Some(0x8000));
    }

    #[test]
    fn does_not_forward_partial_or_overwritten_ranges() {
        assert_eq!(walk(&[placed(0x1000, 0x8000, 0xb0)], 0x1080, 0x40), None);
        assert_eq!(walk(&[], 0x1000, 0xb0), None);
        assert_eq!(walk(&[placed(0x2000, 0x8000, 0xb0)], 0x1000, 0xb0), None);
        assert_eq!(
            walk(
                &[Seen::Placed {
                    dst: 0x1000,
                    src: 0x8000,
                    len: 0xb0,
                    from_upload: false
                }],
                0x1000,
                0xb0
            ),
            None
        );
        assert_eq!(walk(&[placed(0x1000, 0x1040, 0x100)], 0x1000, 0x40), None);
        for after in [Seen::Writes(0x10a0, 0x10b0), Seen::Writes(0x8010, 0x8020), Seen::Anything] {
            assert_eq!(walk(&[placed(0x1000, 0x8000, 0xb0), after], 0x1000, 0xb0), None);
        }
        assert_eq!(
            walk(&[placed(0x1000, 0x8000, 0xb0), placed(0x1000, 0x9000, 0x10)], 0x1000, 0xb0),
            None
        );
        assert_eq!(
            walk(&[placed(0x1000, 0x9000, 0x10), placed(0x1000, 0x8000, 0xb0)], 0x1000, 0xb0),
            Some(0x8000)
        );
    }

    #[test]
    fn rejects_empty_and_overflowing_ranges() {
        assert_eq!(walk(&[placed(0x1000, 0x8000, 0xb0)], 0x1000, 0), None);
        assert_eq!(walk(&[placed(0x1000, 0x8000, 0xb0)], usize::MAX, 2), None);
        assert_eq!(walk(&[placed(usize::MAX, 0x8000, 2)], 0x1000, 1), None);
    }

    #[test]
    fn switch_can_be_enabled_in_a_test_without_environment_changes() {
        assert!(!super::PORT_RT_IN_TEST.get());
        super::PORT_RT_IN_TEST.set(true);
        assert!(super::on());
        super::PORT_RT_IN_TEST.set(false);
    }
}
