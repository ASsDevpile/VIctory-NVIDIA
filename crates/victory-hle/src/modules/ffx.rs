//! Intercepts the title's FidelityFX upscale dispatch when DLSS is selected.
//! Other dispatches, and failed DLSS attempts, go to the title's own export.
//! The NGX bridge follows the GPL-3.0 implementation in
//! https://github.com/rhythmhere/rhythm-VI, adapted here to avoid its
//! optional AMD PC-upscaler provider dependency.

#![allow(non_snake_case)]

use std::ffi::c_void;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Once;

use crate::{HleModule, hle_export};

const DISPATCH_UPSCALE: u64 = 0x0001_0001;
const FFX_API_RETURN_ERROR: u32 = 1;
const LOADER_DLL: &str = "amd_fidelityfx_loader_xbox.dll";

#[allow(dead_code)]
#[repr(C)]
struct Header {
    kind: u64,
    next: *const Header,
}

#[allow(dead_code)]
#[repr(C)]
#[derive(Clone, Copy)]
struct Resource {
    resource: *mut c_void,
    description: [u32; 8],
    state: u32,
}

#[allow(dead_code)]
#[repr(C)]
struct UpscaleDispatch {
    header: Header,
    list: *mut c_void,
    resources: [Resource; 7],
    jitter: [f32; 2],
    motion_scale: [f32; 2],
    render_size: [u32; 2],
    upscale_size: [u32; 2],
    settings: [u32; 10],
}

const _: () = assert!(std::mem::size_of::<Resource>() == 0x30);
const _: () = assert!(std::mem::size_of::<UpscaleDispatch>() == 0x1b0);
const _: () = assert!(std::mem::offset_of!(UpscaleDispatch, resources) == 0x18);
const _: () = assert!(std::mem::offset_of!(UpscaleDispatch, jitter) == 0x168);
const _: () = assert!(std::mem::offset_of!(UpscaleDispatch, settings) == 0x188);

type Dispatch = unsafe extern "system" fn(*mut *mut c_void, *const Header) -> u32;

static ORIGINAL: AtomicUsize = AtomicUsize::new(0);

fn original_dispatch() -> Option<Dispatch> {
    let cached = ORIGINAL.load(Ordering::Relaxed);
    if cached != 0 {
        // SAFETY: cached only after resolving the named export from the loaded
        // title DLL, and that module remains loaded for the run.
        return Some(unsafe { std::mem::transmute::<usize, Dispatch>(cached) });
    }

    use windows_sys::Win32::System::LibraryLoader::GetProcAddress;

    // The title image is mapped from a cache filename, so find it by its
    // original package path rather than its OS module name.
    let module = crate::runtime::image_named(LOADER_DLL)? as *mut c_void;
    // SAFETY: the title's mapped FFX image is live and its export name is
    // static and NUL-terminated.
    let function = unsafe { GetProcAddress(module, c"ffxDispatch".as_ptr().cast()) }?;
    let address = function as *const () as usize;
    let _ = ORIGINAL.compare_exchange(0, address, Ordering::Relaxed, Ordering::Relaxed);
    // SAFETY: the title's exported function has the FFX dispatch ABI.
    Some(unsafe { std::mem::transmute::<usize, Dispatch>(address) })
}

extern "system" fn ffxDispatch(context: *mut *mut c_void, desc: *const Header) -> u32 {
    let Some(dispatch) = original_dispatch() else {
        static WARNED: Once = Once::new();
        WARNED.call_once(|| {
            tracing::error!(
                dll = LOADER_DLL,
                "DLSS dispatch could not find the title's original ffxDispatch; returning FFX_API_RETURN_ERROR"
            );
        });
        return FFX_API_RETURN_ERROR;
    };

    if !requested() || desc.is_null() {
        // SAFETY: arguments are forwarded unchanged to the original export.
        return unsafe { dispatch(context, desc) };
    }

    // SAFETY: the title passes a valid FFX dispatch descriptor.
    let header = unsafe { &*desc };
    if header.kind == DISPATCH_UPSCALE {
        // SAFETY: the descriptor type identifies the complete upscale layout.
        let upscale = unsafe { &*desc.cast::<UpscaleDispatch>() };
        let up = victory_gpu::list::Upscale {
            colour: upscale.resources[0].resource as usize as u64,
            depth: upscale.resources[1].resource as usize as u64,
            motion: upscale.resources[2].resource as usize as u64,
            exposure: upscale.resources[3].resource as usize as u64,
            output: upscale.resources[6].resource as usize as u64,
            render: upscale.render_size,
            jitter: upscale.jitter,
            motion_scale: upscale.motion_scale,
            reset: upscale.settings[4] & 0xff != 0,
            pre_exposure: f32::from_bits(upscale.settings[3]),
            near: f32::from_bits(upscale.settings[5]),
            far: f32::from_bits(upscale.settings[6]),
            frame_ms: f32::from_bits(upscale.settings[2]),
        };
        if victory_gpu::list::upscale(upscale.list, &up) {
            return 0;
        }
    }

    // SAFETY: DLSS did not replace this dispatch; preserve the title's FFX
    // implementation for non-upscale work and all fallback cases.
    unsafe { dispatch(context, desc) }
}

pub(crate) fn requested() -> bool {
    std::env::var("VICTORY_UPSCALER")
        .is_ok_and(|value| value.trim().eq_ignore_ascii_case("dlss"))
}

pub(crate) fn module() -> HleModule {
    HleModule {
        name: "ffx-dlss",
        dlls: &[LOADER_DLL],
        exports: vec![hle_export!(ffxDispatch)],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ffx_upscale_dispatch_layout_matches_the_sdk() {
        use std::mem::offset_of;

        assert_eq!(std::mem::size_of::<Header>(), 16);
        assert_eq!(offset_of!(UpscaleDispatch, list), 0x10);
        assert_eq!(offset_of!(UpscaleDispatch, resources), 0x18);
        assert_eq!(offset_of!(UpscaleDispatch, jitter), 0x168);
        assert_eq!(offset_of!(UpscaleDispatch, motion_scale), 0x170);
        assert_eq!(offset_of!(UpscaleDispatch, render_size), 0x178);
        assert_eq!(offset_of!(UpscaleDispatch, upscale_size), 0x180);
        assert_eq!(offset_of!(UpscaleDispatch, settings), 0x188);
    }
}
