//! NVIDIA NGX DLSS Super Resolution for the title's FidelityFX upscale.
//!
//! The NGX interface is adapted from the GPL-3.0 implementation in
//! https://github.com/rhythmhere/rhythm-VI. It is called only from the opt-in FFX dispatch hook;
//! failed initialisation, feature creation, or evaluation falls back to the
//! title's original FFX dispatch.

use std::ffi::{c_char, c_int, c_uint, c_void};
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

use windows::Win32::Graphics::Direct3D12::*;
use windows::core::Interface;

type NgxResult = c_int;
const NGX_SUCCESS: NgxResult = 1;
const FEATURE_SUPER_SAMPLING: c_int = 1;
const ENGINE_CUSTOM: c_int = 0;
const VERSION_API: c_int = 0x15;

const FLAG_HDR: c_int = 1 << 0;
const FLAG_MV_LOW_RES: c_int = 1 << 1;
const FLAG_MV_JITTERED: c_int = 1 << 2;
const FLAG_DEPTH_INVERTED: c_int = 1 << 3;
const FLAG_AUTO_EXPOSURE: c_int = 1 << 6;

#[allow(dead_code)]
#[repr(C)]
struct PathList {
    paths: *const *const u16,
    count: c_uint,
}

#[allow(dead_code)]
#[repr(C)]
struct Logging {
    callback: *const c_void,
    minimum: c_int,
    disable_other_sinks: bool,
}

#[allow(dead_code)]
#[repr(C)]
struct CommonInfo {
    paths: PathList,
    internal: *const c_void,
    logging: Logging,
}

#[link(name = "nvsdk_ngx_d", kind = "static")]
unsafe extern "C" {
    fn NVSDK_NGX_D3D12_Init_with_ProjectID(
        project: *const c_char,
        engine: c_int,
        engine_version: *const c_char,
        data_path: *const u16,
        device: *mut c_void,
        info: *const CommonInfo,
        version: c_int,
    ) -> NgxResult;
    fn NVSDK_NGX_D3D12_GetCapabilityParameters(out: *mut *mut c_void) -> NgxResult;
    fn NVSDK_NGX_D3D12_CreateFeature(
        list: *mut c_void,
        feature: c_int,
        params: *mut c_void,
        out: *mut *mut c_void,
    ) -> NgxResult;
    fn NVSDK_NGX_D3D12_ReleaseFeature(handle: *mut c_void) -> NgxResult;
    fn NVSDK_NGX_D3D12_EvaluateFeature_C(
        list: *mut c_void,
        handle: *const c_void,
        params: *const c_void,
        callback: *const c_void,
    ) -> NgxResult;
    fn NVSDK_NGX_Parameter_SetUI(params: *mut c_void, name: *const c_char, value: c_uint);
    fn NVSDK_NGX_Parameter_SetI(params: *mut c_void, name: *const c_char, value: c_int);
    fn NVSDK_NGX_Parameter_SetF(params: *mut c_void, name: *const c_char, value: f32);
    fn NVSDK_NGX_Parameter_SetD3d12Resource(
        params: *mut c_void,
        name: *const c_char,
        value: *mut c_void,
    );
    fn NVSDK_NGX_Parameter_GetI(
        params: *mut c_void,
        name: *const c_char,
        out: *mut c_int,
    ) -> NgxResult;
}

macro_rules! ngx_name {
    ($name:literal) => {
        concat!($name, "\0").as_ptr().cast::<c_char>()
    };
}

pub(crate) struct Inputs<'a> {
    pub colour: &'a ID3D12Resource,
    pub depth: Option<&'a ID3D12Resource>,
    pub motion: Option<&'a ID3D12Resource>,
    pub exposure: Option<&'a ID3D12Resource>,
    pub output: &'a ID3D12Resource,
    pub jitter: [f32; 2],
    pub motion_scale: [f32; 2],
    pub render: [u32; 2],
    pub reset: bool,
    pub pre_exposure: f32,
    pub near: f32,
    pub far: f32,
    pub frame_ms: f32,
}

#[derive(Clone, Copy, PartialEq, Eq)]
struct FeatureKey {
    input: [u32; 2],
    output: [u32; 2],
    flags: u32,
}

struct Feature {
    handle: *mut c_void,
    key: FeatureKey,
}

struct Dlss {
    params: *mut c_void,
    feature: Option<Feature>,
    failed_key: Option<FeatureKey>,
}

// NGX is process-wide; every call below is serialized by this mutex.
unsafe impl Send for Dlss {}

static DLSS: Mutex<Option<Option<Dlss>>> = Mutex::new(None);

struct Options {
    quality: c_int,
    motion_sign: f32,
    jitter_sign: f32,
    sharpness: f32,
    hdr: Option<bool>,
    depth_inverted: Option<bool>,
    preset: c_uint,
}

static OPTIONS: OnceLock<Options> = OnceLock::new();

fn options() -> &'static Options {
    OPTIONS.get_or_init(|| {
        let quality = match std::env::var("VICTORY_DLSS_QUALITY") {
            Ok(value) => match value.trim().parse::<c_int>() {
                Ok(value) if (0..=5).contains(&value) => value,
                _ => {
                    tracing::warn!(value, "VICTORY_DLSS_QUALITY must be an integer from 0 to 5; using quality mode");
                    2
                }
            },
            Err(_) => 2,
        };
        let motion_sign = setting_sign("VICTORY_DLSS_MV_SIGN");
        let jitter_sign = setting_sign("VICTORY_DLSS_JITTER_SIGN");
        let sharpness = setting_f32("VICTORY_DLSS_SHARPNESS", 0.0).clamp(0.0, 1.0);
        let hdr = setting_bool("VICTORY_DLSS_HDR");
        let depth_inverted = setting_bool("VICTORY_DLSS_DEPTH_INVERTED");
        let preset = match std::env::var("VICTORY_DLSS_PRESET") {
            Ok(value) => match value.trim() {
                "J" => 10,
                "K" => 11,
                "L" => 12,
                "M" => 13,
                "" => 0,
                _ => {
                    tracing::warn!(value, "VICTORY_DLSS_PRESET must be J, K, L, or M; using the SDK default");
                    0
                }
            },
            Err(_) => 0,
        };
        Options {
            quality,
            motion_sign,
            jitter_sign,
            sharpness,
            hdr,
            depth_inverted,
            preset,
        }
    })
}

fn setting_f32(name: &'static str, default: f32) -> f32 {
    match std::env::var(name) {
        Ok(value) => match value.trim().parse::<f32>() {
            Ok(value) if value.is_finite() => value,
            _ => {
                tracing::warn!(name, value, "invalid DLSS numeric setting; using its default");
                default
            }
        },
        Err(_) => default,
    }
}

fn setting_sign(name: &'static str) -> f32 {
    match std::env::var(name) {
        Ok(value) => match value.trim().parse::<f32>() {
            Ok(value) if value == -1.0 || value == 1.0 => value,
            _ => {
                tracing::warn!(name, value, "DLSS sign setting must be -1 or 1; using 1");
                1.0
            }
        },
        Err(_) => 1.0,
    }
}

fn setting_bool(name: &'static str) -> Option<bool> {
    match std::env::var(name) {
        Ok(value) if value.trim() == "1" => Some(true),
        Ok(value) if value.trim() == "0" => Some(false),
        Ok(value) => {
            tracing::warn!(name, value, "DLSS boolean setting must be 0 or 1; using automatic detection");
            None
        }
        Err(_) => None,
    }
}

fn runtime_dir() -> Option<PathBuf> {
    std::env::var_os("VICTORY_DLSS_DIR")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .or_else(|| {
            std::env::current_exe()
                .ok()
                .and_then(|path| path.parent().map(PathBuf::from))
        })
}

fn wide(path: &std::ffi::OsStr) -> Vec<u16> {
    use std::os::windows::ffi::OsStrExt;
    path.encode_wide().chain([0]).collect()
}

fn init(device: &ID3D12Device) -> Option<Dlss> {
    let Some(dir) = runtime_dir() else {
        tracing::warn!("DLSS runtime directory is unavailable; the title's FFX path remains active");
        return None;
    };
    if !dir.join("nvngx_dlss.dll").is_file() {
        tracing::warn!(
            dir = %dir.display(),
            "nvngx_dlss.dll is missing; the title's FFX path remains active"
        );
        return None;
    }

    let data = std::env::temp_dir().join("victory-ngx");
    if let Err(error) = std::fs::create_dir_all(&data) {
        tracing::warn!(%error, path = %data.display(), "could not create the NGX data directory");
        return None;
    }
    let dir_w = wide(dir.as_os_str());
    let data_w = wide(data.as_os_str());
    let paths = [dir_w.as_ptr()];
    let info = CommonInfo {
        paths: PathList {
            paths: paths.as_ptr(),
            count: 1,
        },
        internal: std::ptr::null(),
        logging: Logging {
            callback: std::ptr::null(),
            minimum: 0,
            disable_other_sinks: false,
        },
    };
    let project = c"5e2f9a3c-1b7d-4c8e-9a6f-0d3b2c1e4f57";
    let engine_version = c"1.0";
    // SAFETY: strings, paths, info, and the device stay alive for the call.
    let result = unsafe {
        NVSDK_NGX_D3D12_Init_with_ProjectID(
            project.as_ptr(),
            ENGINE_CUSTOM,
            engine_version.as_ptr(),
            data_w.as_ptr(),
            device.as_raw(),
            &info,
            VERSION_API,
        )
    };
    if result != NGX_SUCCESS {
        tracing::warn!(
            result = format_args!("{result:#x}"),
            dir = %dir.display(),
            "NGX did not initialize; the title's FFX path remains active"
        );
        return None;
    }

    let mut params = std::ptr::null_mut();
    // SAFETY: `params` is a valid out pointer.
    let result = unsafe { NVSDK_NGX_D3D12_GetCapabilityParameters(&mut params) };
    if result != NGX_SUCCESS || params.is_null() {
        tracing::warn!(
            result = format_args!("{result:#x}"),
            "NGX returned no capability parameters"
        );
        return None;
    }
    let mut available = 0;
    // SAFETY: parameters are live and `available` is a valid out pointer.
    let result = unsafe {
        NVSDK_NGX_Parameter_GetI(params, ngx_name!("SuperSampling.Available"), &mut available)
    };
    if result != NGX_SUCCESS || available == 0 {
        tracing::warn!(
            result = format_args!("{result:#x}"),
            available,
            "DLSS Super Resolution is unavailable on this device or driver"
        );
        return None;
    }

    tracing::info!(
        dir = %dir.display(),
        "NGX initialized for DLSS Super Resolution"
    );
    Some(Dlss {
        params,
        feature: None,
        failed_key: None,
    })
}

pub(crate) fn record(
    device: &ID3D12Device,
    list: &ID3D12GraphicsCommandList,
    inputs: &Inputs<'_>,
) -> bool {
    if inputs.depth.is_none() || inputs.motion.is_none() {
        return false;
    }
    if !inputs.frame_ms.is_finite()
        || inputs.jitter.into_iter().any(|value| !value.is_finite())
        || inputs
            .motion_scale
            .into_iter()
            .any(|value| !value.is_finite())
    {
        static WARNED: std::sync::Once = std::sync::Once::new();
        WARNED.call_once(|| {
            tracing::warn!(
                "DLSS received non-finite timing or camera data; using the original FFX dispatch"
            );
        });
        return false;
    }

    let mut guard = DLSS.lock().unwrap_or_else(|error| error.into_inner());
    let Some(dlss) = guard.get_or_insert_with(|| init(device)) else {
        return false;
    };

    // SAFETY: the title's resources are held by the command list.
    let (output_desc, colour_desc) = unsafe { (inputs.output.GetDesc(), inputs.colour.GetDesc()) };
    let output_size = [output_desc.Width as u32, output_desc.Height];
    let input_size = [colour_desc.Width as u32, colour_desc.Height];
    if input_size.contains(&0) || output_size.contains(&0) {
        tracing::warn!(?input_size, ?output_size, "DLSS received a zero-sized texture");
        return false;
    }

    let opts = options();
    let hdr = opts.hdr.unwrap_or(matches!(colour_desc.Format.0, 2 | 10 | 26 | 24 | 9));
    let depth_inverted = opts
        .depth_inverted
        .unwrap_or(inputs.near > inputs.far);
    let mut flags = FLAG_MV_LOW_RES | FLAG_MV_JITTERED;
    if hdr {
        flags |= FLAG_HDR;
    }
    if depth_inverted {
        flags |= FLAG_DEPTH_INVERTED;
    }
    if inputs.exposure.is_none() {
        flags |= FLAG_AUTO_EXPOSURE;
    }
    let key = FeatureKey {
        input: input_size,
        output: output_size,
        flags: flags as u32,
    };
    if dlss.failed_key == Some(key) {
        return false;
    }

    let params = dlss.params;
    if dlss.feature.as_ref().is_none_or(|feature| feature.key != key) {
        if let Some(old) = dlss.feature.take() {
            // SAFETY: NGX created this feature handle.
            unsafe { NVSDK_NGX_D3D12_ReleaseFeature(old.handle) };
        }
        let mut handle = std::ptr::null_mut();
        // SAFETY: parameters and command list are live; NGX writes the feature handle.
        let result = unsafe {
            NVSDK_NGX_Parameter_SetUI(params, ngx_name!("CreationNodeMask"), 1);
            NVSDK_NGX_Parameter_SetUI(params, ngx_name!("VisibilityNodeMask"), 1);
            NVSDK_NGX_Parameter_SetUI(params, ngx_name!("Width"), input_size[0]);
            NVSDK_NGX_Parameter_SetUI(params, ngx_name!("Height"), input_size[1]);
            NVSDK_NGX_Parameter_SetUI(params, ngx_name!("OutWidth"), output_size[0]);
            NVSDK_NGX_Parameter_SetUI(params, ngx_name!("OutHeight"), output_size[1]);
            NVSDK_NGX_Parameter_SetI(params, ngx_name!("PerfQualityValue"), opts.quality);
            NVSDK_NGX_Parameter_SetI(params, ngx_name!("DLSS.Feature.Create.Flags"), flags);
            NVSDK_NGX_Parameter_SetI(params, ngx_name!("DLSS.Enable.Output.Subrects"), 0);
            if opts.preset != 0 {
                for mode in [
                    ngx_name!("DLSS.Hint.Render.Preset.DLAA"),
                    ngx_name!("DLSS.Hint.Render.Preset.Quality"),
                    ngx_name!("DLSS.Hint.Render.Preset.Balanced"),
                    ngx_name!("DLSS.Hint.Render.Preset.Performance"),
                    ngx_name!("DLSS.Hint.Render.Preset.UltraPerformance"),
                    ngx_name!("DLSS.Hint.Render.Preset.UltraQuality"),
                ] {
                    NVSDK_NGX_Parameter_SetUI(params, mode, opts.preset);
                }
            }
            NVSDK_NGX_D3D12_CreateFeature(
                list.as_raw(),
                FEATURE_SUPER_SAMPLING,
                params,
                &mut handle,
            )
        };
        if result != NGX_SUCCESS || handle.is_null() {
            dlss.failed_key = Some(key);
            tracing::warn!(
                result = format_args!("{result:#x}"),
                ?input_size,
                ?output_size,
                "NGX could not create DLSS for these dimensions; using the title's FFX path"
            );
            return false;
        }
        tracing::info!(
            ?input_size,
            ?output_size,
            hdr,
            depth_inverted,
            quality = opts.quality,
            "DLSS feature created"
        );
        dlss.feature = Some(Feature { handle, key });
    }

    let Some(feature) = dlss.feature.as_ref() else {
        return false;
    };
    let mv_scale = |value: f32| {
        let value = if value == 0.0 { 1.0 } else { value };
        opts.motion_sign * value
    };
    let raw = |resource: Option<&ID3D12Resource>| {
        resource.map_or(std::ptr::null_mut(), |resource| resource.as_raw())
    };
    let render = [
        if inputs.render[0] == 0 {
            input_size[0]
        } else {
            inputs.render[0]
        }
        .min(input_size[0]),
        if inputs.render[1] == 0 {
            input_size[1]
        } else {
            inputs.render[1]
        }
        .min(input_size[1]),
    ];
    // SAFETY: the feature, resources and parameters remain live for NGX's call.
    let result = unsafe {
        NVSDK_NGX_Parameter_SetD3d12Resource(params, ngx_name!("Color"), inputs.colour.as_raw());
        NVSDK_NGX_Parameter_SetD3d12Resource(params, ngx_name!("Output"), inputs.output.as_raw());
        NVSDK_NGX_Parameter_SetD3d12Resource(params, ngx_name!("Depth"), raw(inputs.depth));
        NVSDK_NGX_Parameter_SetD3d12Resource(
            params,
            ngx_name!("MotionVectors"),
            raw(inputs.motion),
        );
        NVSDK_NGX_Parameter_SetD3d12Resource(
            params,
            ngx_name!("ExposureTexture"),
            raw(inputs.exposure),
        );
        NVSDK_NGX_Parameter_SetF(
            params,
            ngx_name!("Jitter.Offset.X"),
            opts.jitter_sign * inputs.jitter[0],
        );
        NVSDK_NGX_Parameter_SetF(
            params,
            ngx_name!("Jitter.Offset.Y"),
            opts.jitter_sign * inputs.jitter[1],
        );
        NVSDK_NGX_Parameter_SetF(params, ngx_name!("MV.Scale.X"), mv_scale(inputs.motion_scale[0]));
        NVSDK_NGX_Parameter_SetF(params, ngx_name!("MV.Scale.Y"), mv_scale(inputs.motion_scale[1]));
        NVSDK_NGX_Parameter_SetI(
            params,
            ngx_name!("Reset"),
            if inputs.reset { 1 } else { 0 },
        );
        NVSDK_NGX_Parameter_SetF(params, ngx_name!("Sharpness"), opts.sharpness);
        NVSDK_NGX_Parameter_SetF(
            params,
            ngx_name!("DLSS.Pre.Exposure"),
            if inputs.pre_exposure.is_finite() && inputs.pre_exposure > 0.0 {
                inputs.pre_exposure
            } else {
                1.0
            },
        );
        NVSDK_NGX_Parameter_SetF(params, ngx_name!("FrameTimeDeltaInMsec"), inputs.frame_ms);
        NVSDK_NGX_Parameter_SetUI(
            params,
            ngx_name!("DLSS.Render.Subrect.Dimensions.Width"),
            render[0],
        );
        NVSDK_NGX_Parameter_SetUI(
            params,
            ngx_name!("DLSS.Render.Subrect.Dimensions.Height"),
            render[1],
        );
        NVSDK_NGX_D3D12_EvaluateFeature_C(
            list.as_raw(),
            feature.handle,
            params,
            std::ptr::null(),
        )
    };
    if result != NGX_SUCCESS {
        dlss.failed_key = Some(key);
        static WARNED: std::sync::Once = std::sync::Once::new();
        WARNED.call_once(|| {
            tracing::warn!(
                result = format_args!("{result:#x}"),
                "DLSS evaluation failed; using the title's FFX path"
            );
        });
        return false;
    }
    true
}
