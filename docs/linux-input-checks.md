# Linux dictation input: T-928

## Finding, 2026-09-17

The reported symptom was numbers and symbols replacing dictated words on
Omarchy. The failure is reproducible **without recording or transcription**:
`wtype` sends a known sentence to a plain GTK field, a plain WebKit textarea,
and Linger's production `Composer`. Native Wayland accepts the sentence;
XWayland does not. Slowing typing from 1 to 30 ms does not repair it.

The downloaded `linger_0.1.0_amd64.AppImage` contains this assignment in
`apprun-hooks/linuxdeploy-plugin-gtk.sh`:

```bash
export GDK_BACKEND=x11
```

That selects XWayland on a Wayland desktop, even if `GDK_BACKEND=wayland` was
set before launching. The launcher cites
[Tauri's AppImage/Wayland compatibility issue](https://github.com/tauri-apps/tauri/issues/8541).
The input driver also has an
[XWayland compatibility report](https://github.com/atx/wtype/issues/62).
These are context, not substitutes for the local reproduction.

The isolated native test produced:

| Input route | GTK field | Plain WebKit | Linger composer |
|---|---|---|---|
| Wayland, wtype at 1 ms | Exact | Exact | Exact |
| Wayland, wtype at 30 ms | Exact | Exact | Exact |
| XWayland, wtype at 1 ms | Changed | Changed | Changed |
| XWayland, wtype at 30 ms | Changed | Changed | Changed |
| Wayland, clipboard + native paste | Exact | Exact | Exact |
| XWayland, clipboard + native paste | Exact | Exact | Exact |

The plain WebKit XWayland test turned `hello world! Voice 123.` into
`122345362784930-14`. This locates the corruption below the composer; changing
the text after receipt would not recover the original words. The composer
paste control also preserves Unicode and multiple lines without submitting.

Environment: GTK 3.24.52, WebKitGTK 2.52.6, wtype 0.4, wl-clipboard 2.3.0,
XWayland 24.1.13, labwc 0.20.2 with wlroots 0.20.2. The installed Voxtype
1.0.1 configuration selects simulated typing. The comparison uses its output
driver directly, not a model or a microphone. Labwc and its missing libraries
were extracted into disposable storage, not installed on the user's system.

## Workaround and limits

Use Voxtype's per-recording clipboard output and **physical Ctrl+V**, as shown
in the [user guide](user-guide.md#appimage-troubleshooting). Its `--clipboard`
and `--no-auto-submit` flags were checked against the installed CLI. The native
test uses `wl-copy` and the widget's paste action. It does not test a physical
key press or a spoken recording, and does not claim those end-to-end checks
passed. Automatic paste still synthesizes keys, so it is not the recommended
control.

The AppImage itself has not been rebuilt or changed by this task. A packaged
native Wayland option needs its own startup, input, graphics and update tests,
including computers that needed the documented GBM workaround. Do not remove
the packaging fallback based only on a system-WebKit developer test. T-929
tracks that follow-up. No server change, protocol change, text rewriting or
dictation feature was added to Linger.

## Repeat the native comparison

This is a Linux developer diagnostic, not an end-user setup step. It needs
the normal client development dependencies, a C compiler, `pkg-config`,
WebKitGTK 4.1 development headers, `labwc`, `Xwayland`, `wtype`, `wl-copy`,
`dbus-run-session`, `timeout`, `curl` and `rg`. It installs nothing. Run from
the repository:

```bash
scripts/linux-input-check.sh
```

The script creates a private, headless compositor, private clipboard and
private configuration directories. It has no physical input backend and
does not read window titles, type into the live desktop, use a real account,
record audio or contact a Linger server. Vite serves the fixture on loopback
port 1422; the production composer uses an API stub that rejects submission.
Temporary processes and files are removed when the comparison ends.

`MATCH` means exact synthetic text and, for the composer, no submission.
`DIFFERENT` under XWayland typing reproduces the compatibility defect; it is
**not** a passing input check. Clipboard and native Wayland must all match.
The script exits nonzero for missing results, a timeout or a failed control.
It prints only results for the owned fixture, not desktop diagnostics.

The ordinary `pnpm test:browser` suite includes a smaller composer regression
for typing and Unicode/multiline insertion in Chromium and WebKit. That test
is useful in CI but bypasses `wtype` and cannot prove this Linux issue fixed.
