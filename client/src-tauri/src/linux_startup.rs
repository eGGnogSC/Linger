//! A per-launch opt-in that survives the AppImage launcher's X11 fallback.
//! Keep the default unchanged until graphics and input pass on real hardware.

use std::ffi::OsStr;

fn backend(value: Option<&OsStr>) -> Result<Option<&'static str>, &'static str> {
    match value.and_then(OsStr::to_str) {
        None if value.is_none() => Ok(None),
        Some("wayland") => Ok(Some("wayland")),
        Some("x11") => Ok(Some("x11")),
        _ => Err("LINGER_LINUX_BACKEND must be wayland or x11; unset it to use the default."),
    }
}

/// Run before GTK or any worker starts, so the launcher cannot override the choice.
pub fn configure() -> Result<(), &'static str> {
    let requested = std::env::var_os("LINGER_LINUX_BACKEND");
    if let Some(selected) = backend(requested.as_deref())? {
        std::env::set_var("GDK_BACKEND", selected);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::ffi::OsStrExt;

    #[test]
    fn only_an_explicit_supported_choice_overrides_the_launcher() {
        assert_eq!(backend(None), Ok(None));
        assert_eq!(backend(Some(OsStr::new("wayland"))), Ok(Some("wayland")));
        assert_eq!(backend(Some(OsStr::new("x11"))), Ok(Some("x11")));
        for invalid in ["", "auto", "wayland,x11", "WAYLAND"] {
            assert!(backend(Some(OsStr::new(invalid))).is_err());
        }
        assert!(backend(Some(OsStr::from_bytes(&[0xff]))).is_err());
    }
}
