#[test]
fn window_icon_has_enough_pixels_for_high_density_desktops() {
    let context = tauri::generate_context!();
    let icon = context.default_window_icon().expect("packaged window icon");
    assert!(icon.width() >= 256 && icon.height() >= 256);
}
