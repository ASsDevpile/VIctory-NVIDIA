//! Opt-in compatibility hooks for known title builds.
//!
//! LOCAL: copied from vitutu1/victory-perf crates/victory-loader/src/hooks.rs, which ported it from
//! ZigZagBoi1/ScarlettPort (`runtime/victory`, GPL-3.0-or-later).
//! Only per-build offsets and short byte signatures live here (asset policy:
//! nothing of the title itself). Every hook checks the build's hash and the
//! exact bytes it replaces, and does nothing otherwise.

use windows_sys::Win32::System::Diagnostics::Debug::FlushInstructionCache;
use windows_sys::Win32::System::Memory::{PAGE_EXECUTE_READWRITE, VirtualProtect};
use windows_sys::Win32::System::Threading::GetCurrentProcess;

/// First 16 hex digits of the BLAKE3 of the Series X 1.0.2.1 executable.
const BUILD_1_0_2_1: &str = "b99f876b74d4a77f";

/// Environment variable that turns the watchdog hook on.
pub(crate) const NO_WATCHDOG_ENV: &str = "VICTORY_NO_WATCHDOG";

/// One code patch: `rva` must hold exactly `expect` before `new` is written.
struct Patch<'a> {
    what: &'static str,
    rva: usize,
    expect: &'a [u8],
    new: &'a [u8],
}

/// The title's watchdog thread ends the process on purpose when its main
/// thread has not advanced for about 30 one-second ticks. Two places do it:
/// the handler it calls (`mov dword ptr [0], imm32`) and, when the handler
/// returns or is unset, a fallback right after the call (`mov dword ptr [0],
/// 0; int3`). Jumping over the whole block returns the loop to its normal
/// path; the first patch makes the handler harmless if something else calls it.
const WATCHDOG: &[Patch<'static>] = &[
    Patch {
        what: "watchdog: skip the call and the fallback fault",
        rva: 0x2215c27,
        // mov rax, [rip + disp32] (the handler pointer)
        expect: &[0x48, 0x8B, 0x05, 0x1A, 0x07, 0xFA, 0x04],
        // jmp +0x18 (to the loop's normal continuation), then NOPs
        new: &[0xEB, 0x18, 0x90, 0x90, 0x90, 0x90, 0x90],
    },
    Patch {
        what: "watchdog: handler's deliberate fault",
        rva: 0x23cf683,
        expect: &[0xC7, 0x04, 0x25, 0, 0, 0, 0, 0x21, 0xD4, 0x8B, 0x4D],
        // an eleven-byte NOP
        new: &[0x66, 0x66, 0x2E, 0x0F, 0x1F, 0x84, 0, 0, 0, 0, 0],
    },
];

/// Applies the watchdog patches whose bytes match. Returns how many applied.
///
/// # Safety
/// `base` is the mapped image whose original BLAKE3 is `hash`, and no title
/// code is running yet.
pub(crate) unsafe fn disarm_watchdog(base: usize, hash: &blake3::Hash) -> usize {
    if !hash.to_hex().starts_with(BUILD_1_0_2_1) {
        return 0;
    }
    WATCHDOG
        .iter()
        // SAFETY: forwarded from this function's contract.
        .filter(|p| unsafe { apply(base, p) })
        .count()
}

/// Environment variable that pins the title's internal render scale
/// (`0.2..=1.0` of the output size). Testing lever, off by default.
pub(crate) const RENDER_SCALE_ENV: &str = "VICTORY_RENDER_SCALE";
/// Environment variable that makes the title use its own temporal upscaler
/// on every console profile (Series S otherwise picks FSR).
pub(crate) const OWN_UPSCALER_ENV: &str = "VICTORY_OWN_UPSCALER";
/// Environment variable that forces the title's FSR path (`fsr`, or `dlss`
/// as the launcher's alias): a DLSS proxy speaks FSR to the title and DLSS
/// to the driver, and only works while FSR runs. It wins over
/// [`OWN_UPSCALER_ENV`].
pub(crate) const UPSCALER_ENV: &str = "VICTORY_UPSCALER";
/// Environment variable naming the DLSS folder: a folder of its own that
/// holds the NGX libraries (`nvngx*.dll` and friends), away from the
/// title's files. Empty or unset, the loader also looks beside the title's
/// executable (where the proxy would load them from).
pub(crate) const DLSS_DIR_ENV: &str = "VICTORY_DLSS_DIR";

/// A patch whose bytes are computed at load time.
struct OwnedPatch {
    what: &'static str,
    rva: usize,
    expect: Vec<u8>,
    new: Vec<u8>,
}

/// The upscaler choice: `mov eax, 6` (own upscaler) then `cmovne eax, ecx`
/// (FSR when the profile asks for it). NOPing the cmovne keeps 6.
const OWN_UPSCALER: Patch<'static> = Patch {
    what: "upscaler: always the title's own",
    rva: 0x7e9426,
    expect: &[0x0F, 0x45, 0xC1],
    new: &[0x0F, 0x1F, 0x00],
};

/// Read-only float constants of this build usable as the FSR scale:
/// value, RVA.
const FSR_SCALES: [(f32, usize); 4] = [
    (0.5, 0x5fc6edc),
    (0.4, 0x5fc6f90),
    (1.0 / 3.0, 0x615a240),
    (0.75, 0x6159b04),
];

/// The render-scale patches for `scale`, with the image at `base`:
/// - the own upscaler's minimum scale (an immediate, 2/3 by default) set to
///   `scale` and its maximum made equal to the minimum (`vmaxss` → `vmovss`),
///   so the scale is fixed;
/// - FSR's scale (a load of 2/3 on Series S) pointed at a constant equal to
///   `scale`, when this build has one, and its maximum size made the scaled
///   size (vtable slot 11 → slot 10's function).
fn render_scale_patches(base: usize, scale: f32, fsr: bool) -> Vec<OwnedPatch> {
    let mut patches = vec![
        OwnedPatch {
            what: "render scale: own upscaler minimum",
            rva: 0x28f1e7e,
            expect: vec![0xAB, 0xAA, 0x2A, 0x3F],
            new: scale.to_le_bytes().to_vec(),
        },
        OwnedPatch {
            what: "render scale: own upscaler maximum = minimum",
            rva: 0x28f1e87,
            expect: vec![0xC5, 0xFA, 0x5F, 0x86, 0x90, 0, 0, 0],
            new: vec![0xC5, 0xFA, 0x10, 0x86, 0x90, 0, 0, 0],
        },
    ];
    if !fsr {
        return patches;
    }
    match FSR_SCALES.iter().find(|(v, _)| (v - scale).abs() < 1e-3) {
        Some(&(_, constant)) => {
            // vmovss xmm0, [rip + disp32]; the next instruction is at +8.
            const LOAD: usize = 0x28ef6b2;
            let disp = (constant as i64 - (LOAD as i64 + 8)) as i32;
            let mut new = vec![0xC5, 0xFA, 0x10, 0x05];
            new.extend_from_slice(&disp.to_le_bytes());
            patches.push(OwnedPatch {
                what: "render scale: FSR scale",
                rva: LOAD,
                expect: vec![0xC5, 0xFA, 0x10, 0x05, 0xA2, 0xE2, 0x86, 0x03],
                new,
            });
            patches.push(OwnedPatch {
                what: "render scale: FSR maximum = scaled size",
                rva: 0x6300ba8,
                expect: ((base + 0x28ef6f0) as u64).to_le_bytes().to_vec(),
                new: ((base + 0x28ef680) as u64).to_le_bytes().to_vec(),
            });
        }
        None => tracing::warn!(
            scale,
            "no FSR constant for this scale (0.5, 0.4, 1/3, 0.75); FSR keeps its own (use {OWN_UPSCALER_ENV}=1)"
        ),
    }
    patches
}

/// The scale `VICTORY_RENDER_SCALE` asks for, if valid.
fn parse_scale(text: &str) -> Option<f32> {
    let v: f32 = text.trim().parse().ok()?;
    (0.2..=1.0).contains(&v).then_some(v)
}

/// The folder an NVIDIA NGX library was found in, if anywhere: the
/// [`DLSS_DIR_ENV`] folder first (DLSS's own folder, never the title's
/// files), then beside the title's executable (the loader runs in the
/// title's process, and a proxy there loads from its own folder). A DLSS
/// setup needs one: the proxy that takes the title's FSR calls loads it.
fn ngx_dir() -> Option<std::path::PathBuf> {
    let named = std::env::var_os(DLSS_DIR_ENV)
        .filter(|d| !d.is_empty())
        .map(std::path::PathBuf::from);
    let beside = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|p| p.to_path_buf()));
    [named, beside].into_iter().flatten().find(|dir| {
        std::fs::read_dir(dir)
            .into_iter()
            .flatten()
            .flatten()
            .any(|e| {
                let name = e.file_name();
                let name = name.to_string_lossy();
                name.len() > 4
                    && name.rsplit('.').next() == Some("dll")
                    && name.to_ascii_lowercase().starts_with("nvngx")
            })
    })
}

/// Applies the resolution levers asked for in the environment
/// ([`RENDER_SCALE_ENV`], [`OWN_UPSCALER_ENV`]). Returns how many applied.
///
/// # Safety
/// As `disarm_watchdog`.
pub(crate) unsafe fn resolution_levers(base: usize, hash: &blake3::Hash) -> usize {
    let scale = std::env::var(RENDER_SCALE_ENV).ok();
    let upscaler = std::env::var(UPSCALER_ENV)
        .ok()
        .map(|v| v.trim().to_ascii_lowercase());
    let fsr_forced = matches!(upscaler.as_deref(), Some("fsr") | Some("dlss"));
    if fsr_forced && std::env::var_os(OWN_UPSCALER_ENV).is_some_and(|v| v != "0") {
        tracing::info!(
            "{UPSCALER_ENV} runs the title's FSR path; {OWN_UPSCALER_ENV} is left aside"
        );
    }
    let own = !fsr_forced && std::env::var_os(OWN_UPSCALER_ENV).is_some_and(|v| v != "0");
    if scale.is_none() && !own && !fsr_forced {
        return 0;
    }
    // Every image the loader maps comes here (the title's DLLs too); only
    // the 1.0.2.1 executable has the patched places.
    if !hash.to_hex().starts_with(BUILD_1_0_2_1) {
        tracing::debug!("resolution levers: not the 1.0.2.1 executable; nothing patched");
        return 0;
    }
    let mut applied = 0;
    if upscaler.as_deref() == Some("dlss") {
        let dir = ngx_dir().map(|d| d.display().to_string());
        tracing::info!(
            "DLSS: the title runs its FSR path and the NVIDIA libraries stay out of the game's folder ({UPSCALER_ENV}=dlss); {}",
            dir.as_deref()
                .map(|d| format!("the NGX libraries are at {d}"))
                .unwrap_or_else(|| format!(
                    "no NGX library found (without one FSR stays as it is); put nvngx*.dll in a folder of its own and name it with {DLSS_DIR_ENV}"
                ))
        );
    }
    if own {
        // SAFETY: forwarded from this function's contract.
        applied += usize::from(unsafe { apply(base, &OWN_UPSCALER) });
    }
    if let Some(text) = scale {
        match parse_scale(&text) {
            Some(scale) => {
                // With the own upscaler forced, FSR is left as it is; in its
                // place `VICTORY_UPSCALER` runs FSR itself.
                for p in render_scale_patches(base, scale, fsr_forced || !own) {
                    let p = Patch {
                        what: p.what,
                        rva: p.rva,
                        expect: &p.expect,
                        new: &p.new,
                    };
                    // SAFETY: forwarded from this function's contract.
                    applied += usize::from(unsafe { apply(base, &p) });
                }
            }
            None => tracing::warn!(text, "{RENDER_SCALE_ENV} wants a number in 0.2..=1.0"),
        }
    }
    applied
}

/// # Safety
/// See `disarm_watchdog`.
unsafe fn apply(base: usize, p: &Patch<'_>) -> bool {
    let at = (base + p.rva) as *mut u8;
    // SAFETY: the offset is inside the mapped .text of this exact build.
    let now = unsafe { std::slice::from_raw_parts(at, p.expect.len()) };
    if now != p.expect || p.new.len() != p.expect.len() {
        tracing::warn!(
            what = p.what,
            "hook skipped: the bytes are not the expected ones"
        );
        return false;
    }
    let mut old = 0;
    // SAFETY: changing the protection of those bytes only, restored below.
    if unsafe { VirtualProtect(at as _, p.new.len(), PAGE_EXECUTE_READWRITE, &mut old) } == 0 {
        return false;
    }
    // SAFETY: writable now; the bytes are the ones checked above.
    unsafe {
        std::ptr::copy_nonoverlapping(p.new.as_ptr(), at, p.new.len());
        VirtualProtect(at as _, p.new.len(), old, &mut old);
        FlushInstructionCache(GetCurrentProcess(), at as _, p.new.len());
    }
    tracing::info!(what = p.what, "hook applied");
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scales_outside_the_floor_are_refused() {
        assert_eq!(parse_scale("0.5"), Some(0.5));
        assert_eq!(parse_scale(" 1 "), Some(1.0));
        assert_eq!(parse_scale("0.1"), None);
        assert_eq!(parse_scale("1.5"), None);
        assert_eq!(parse_scale("half"), None);
    }

    #[test]
    fn half_scale_patches_both_upscalers() {
        let base = 0x7ff0_0000_0000;
        let p = render_scale_patches(base, 0.5, true);
        assert_eq!(p.len(), 4);
        assert_eq!(p[0].new, 0.5f32.to_le_bytes());
        // The FSR load now reads 0.5 at 0x5fc6edc: disp from the next instruction.
        assert_eq!(p[2].new, [0xC5, 0xFA, 0x10, 0x05, 0x22, 0x78, 0x6D, 0x03]);
        assert_eq!(p[3].new, ((base + 0x28ef680) as u64).to_le_bytes());
        assert!(p.iter().all(|p| p.new.len() == p.expect.len()));
    }

    #[test]
    fn odd_scales_patch_only_the_own_upscaler() {
        assert_eq!(render_scale_patches(0, 0.6, true).len(), 2);
        assert_eq!(render_scale_patches(0, 0.5, false).len(), 2);
    }
}
