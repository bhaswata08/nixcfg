{
  ...
}:
{

  xdg.configFile."niri/config.kdl".text = ''
    // This config is in the KDL format: https://kdl.dev
    // "/-" comments out the following node.
    // Check the wiki for a full description of the configuration:
    // https://niri-wm.github.io/niri/Configuration:-Introduction

    // Input device configuration.
    // Find the full list of options on the wiki:
    // https://niri-wm.github.io/niri/Configuration:-Input

    prefer-no-csd
    input {
        keyboard {
            xkb {
                options "caps:swapescape"
            }
            numlock
        }

        touchpad {
            tap
            dwt
            natural-scroll
        }

        mouse {
        }

        trackpoint {
        }

        // Uncomment this to make the mouse warp to the center of newly focused windows.
        // warp-mouse-to-focus

        // Focus windows and outputs automatically when moving the mouse into them.
        // Setting max-scroll-amount="0%" makes it work only on windows already fully on screen.
        focus-follows-mouse max-scroll-amount="0%"
    }

    output "eDP-1" {
        mode "1920x1080@120.030"
        scale 1.5
        transform "normal"
        position x=1280 y=0
    }
    
    output "HDMI-A-1" {
        mode "1920x1080@60.000"
        scale 1
        transform "normal"
        position x=0 y=0
    }

    layout {
        // Set gaps around windows in logical pixels.
        gaps 10
        center-focused-column "never"

        preset-column-widths {
            proportion 0.33333
            proportion 0.5
            proportion 0.66667
        }

        default-column-width { proportion 0.5; }
        focus-ring {
            width 2

            // TODO: add adaptive colors and moving gradients

            // Colors can be set in a variety of ways:
            // - CSS named colors: "red"
            // - RGB hex: "#rgb", "#rgba", "#rrggbb", "#rrggbbaa"
            // - CSS-like notation: "rgb(255, 127, 0)", rgba(), hsl() and a few others.

            // Color of the ring on the active monitor.
            active-color "#7fc8ff"

            // Color of the ring on inactive monitors.
            //
            // The focus ring only draws around the active window, so the only place
            // where you can see its inactive-color is on other monitors.
            inactive-color "#505050"

            // You can also use gradients. They take precedence over solid colors.
            // Gradients are rendered the same as CSS linear-gradient(angle, from, to).
            // The angle is the same as in linear-gradient, and is optional,
            // defaulting to 180 (top-to-bottom gradient).
            // You can use any CSS linear-gradient tool on the web to set these up.
            // Changing the color space is also supported, check the wiki for more info.
            //
            // active-gradient from="#80c8ff" to="#c7ff7f" angle=45

            // You can also color the gradient relative to the entire view
            // of the workspace, rather than relative to just the window itself.
            // To do that, set relative-to="workspace-view".
            //
            // inactive-gradient from="#505050" to="#808080" angle=45 relative-to="workspace-view"
        }

        // You can also add a border. It's similar to the focus ring, but always visible.
        border {
            off

            width 4
            active-color "#ffc87f"
            inactive-color "#505050"

            // Color of the border around windows that request your attention.
            urgent-color "#9b0000"
        }

        // You can enable drop shadows for windows.
        shadow {
            // Uncomment the next line to enable shadows.
            // on

            // Softness controls the shadow blur radius.
            softness 30

            // Spread expands the shadow.
            spread 5

            // Offset moves the shadow relative to the window.
            offset x=0 y=5

            // You can also change the shadow color and opacity.
            color "#0007"
        }

        struts {
            // left 64
            // right 64
            // top 64
            // bottom 64
        }
    }

    spawn-at-startup "awww-daemon"
    spawn-at-startup "noctalia-shell"
    spawn-at-startup "xwayland-satellite"
    spawn-at-startup "systemctl" "--user" "start" "hyprpolkitagent"
    spawn-at-startup "mpd"
    spawn-at-startup "nm-applet"
    spawn-at-startup "wl-paste" "--watch" "cliphist" "store"
    spawn-at-startup "blueman-applet"
    spawn-at-startup "sunsetr"
    spawn-at-startup "swaync"
    // TODO: Change to quickshell
    // spawn-at-startup "waybar"


    // To run a shell command (with variables, pipes, etc.), use spawn-sh-at-startup:
    // spawn-sh-at-startup "qs -c ~/source/qs/MyAwesomeShell"

    hotkey-overlay {
        // Uncomment this line to disable the "Important Hotkeys" pop-up at startup.
        skip-at-startup
    }
    screenshot-path "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png"
    // screenshot-path null

    // Animation settings.
    // The wiki explains how to configure individual animations:
    // https://niri-wm.github.io/niri/Configuration:-Animations
    animations {
        // Uncomment to turn off all animations.
        // off

        // Slow down all animations by this factor. Values below 1 speed them up instead.
        // slowdown 3.0
    }

    // Window rules let you adjust behavior for individual windows.
    // Find more information on the wiki:
    // https://niri-wm.github.io/niri/Configuration:-Window-Rules

    // Work around WezTerm's initial configure bug
    // by setting an empty default-column-width.
    window-rule {
        // This regular expression is intentionally made as specific as possible,
        // since this is the default config, and we want no false positives.
        // You can get away with just app-id="wezterm" if you want.
        match app-id=r#"^org\.wezfurlong\.wezterm$"#
        default-column-width {}
    }

    window-rule {
        match {}
        opacity 0.87
        draw-border-with-background false
        background-effect {
            blur true
        }
    }

    window-rule {
        match app-id=r#"zen$"# title="^Picture-in-Picture$"
        open-floating true
    }

    window-rule {
        match app-id=r#"^org\.keepassxc\.KeePassXC$"#
        match app-id=r#"^org\.gnome\.World\.Secrets$"#
        block-out-from "screen-capture"
    }

    // Example: enable rounded corners for all windows.
    // (This example rule is commented out with a "/-" in front.)
    window-rule {
        geometry-corner-radius 12
        clip-to-geometry true
    }

    binds {
        // Keys consist of modifiers separated by + signs, followed by an XKB key name
        // in the end. To find an XKB name for a particular key, you may use a program
        // like wev.
        //
        // "Mod" is a special modifier equal to Super when running on a TTY, and to Alt
        // when running as a winit window.
        //
        // Most actions that you can bind here can also be invoked programmatically with
        // `niri msg action do-something`.

        Mod+Shift+Slash { show-hotkey-overlay; }
        Mod+T hotkey-overlay-title="Open a Terminal: ghostty" { spawn "ghostty"; }
        Mod+A hotkey-overlay-title="Run an Application: rofi" { spawn-sh "noctalia-shell ipc call launcher toggle"; }
        Super+Alt+L hotkey-overlay-title="Lock the Screen: hyprlock" { spawn "hyprlock"; }
        Super+B hotkey-overlay-title="Spawn Browser: zen" {spawn "zen"; }
        Super+E hotkey-overlay-title="Spawn Explorer: Dolphin" {spawn "dolphin"; }
        Super+Space hotkey-overlay-title="Spawn runner: Anyrun" { spawn-sh "anyrun --show-results-immediately true | wl-copy" }
        Super+V { spawn-sh "noctalia-shell ipc call launcher clipboard"; }

        XF86AudioRaiseVolume allow-when-locked=true { spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+ -l 1.0"; }
        XF86AudioLowerVolume allow-when-locked=true { spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1-"; }
        XF86AudioMute        allow-when-locked=true { spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"; }
        XF86AudioMicMute     allow-when-locked=true { spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"; }

        // Example media keys mapping using playerctl.
        // This will work with any MPRIS-enabled media player.
        XF86AudioPlay        allow-when-locked=true { spawn-sh "playerctl play-pause"; }
        XF86AudioStop        allow-when-locked=true { spawn-sh "playerctl stop"; }
        XF86AudioPrev        allow-when-locked=true { spawn-sh "playerctl previous"; }
        XF86AudioNext        allow-when-locked=true { spawn-sh "playerctl next"; }

        // Example brightness key mappings for brightnessctl.
        // You can use regular spawn with multiple arguments too (to avoid going through "sh"),
        // but you need to manually put each argument in separate "" quotes.
        XF86MonBrightnessUp allow-when-locked=true { spawn "brightnessctl" "--class=backlight" "set" "+10%"; }
        XF86MonBrightnessDown allow-when-locked=true { spawn "brightnessctl" "--class=backlight" "set" "10%-"; }

        // Open/close the Overview: a zoomed-out view of workspaces and windows.
        // You can also move the mouse into the top-left hot corner,
        // or do a four-finger swipe up on a touchpad.
        Mod+O repeat=false { toggle-overview; }

        Mod+Q repeat=false { close-window; }

        Mod+Left  { focus-column-left; }
        Mod+Down  { focus-window-down; }
        Mod+Up    { focus-window-up; }
        Mod+Right { focus-column-right; }
        Mod+H     { focus-column-left; }
        Mod+J     { focus-window-down; }
        Mod+K     { focus-window-up; }
        Mod+L     { focus-column-right; }

        Mod+Ctrl+Left  { move-column-left; }
        Mod+Ctrl+Down  { move-window-down; }
        Mod+Ctrl+Up    { move-window-up; }
        Mod+Ctrl+Right { move-column-right; }
        Mod+Ctrl+H     { move-column-left; }
        Mod+Ctrl+J     { move-window-down; }
        Mod+Ctrl+K     { move-window-up; }
        Mod+Ctrl+L     { move-column-right; }

        // Alternative commands that move across workspaces when reaching
        // the first or last window in a column.
        // Mod+J     { focus-window-or-workspace-down; }
        // Mod+K     { focus-window-or-workspace-up; }
        // Mod+Ctrl+J     { move-window-down-or-to-workspace-down; }
        // Mod+Ctrl+K     { move-window-up-or-to-workspace-up; }

        Mod+Home { focus-column-first; }
        Mod+End  { focus-column-last; }
        Mod+Ctrl+Home { move-column-to-first; }
        Mod+Ctrl+End  { move-column-to-last; }

        Mod+Shift+Left  { focus-monitor-left; }
        Mod+Shift+Down  { focus-monitor-down; }
        Mod+Shift+Up    { focus-monitor-up; }
        Mod+Shift+Right { focus-monitor-right; }
        Mod+Shift+H     { focus-monitor-left; }
        Mod+Shift+J     { focus-monitor-down; }
        Mod+Shift+K     { focus-monitor-up; }
        Mod+Shift+L     { focus-monitor-right; }

        Mod+Shift+Ctrl+Left  { move-column-to-monitor-left; }
        Mod+Shift+Ctrl+Down  { move-column-to-monitor-down; }
        Mod+Shift+Ctrl+Up    { move-column-to-monitor-up; }
        Mod+Shift+Ctrl+Right { move-column-to-monitor-right; }
        Mod+Shift+Ctrl+H     { move-column-to-monitor-left; }
        Mod+Shift+Ctrl+J     { move-column-to-monitor-down; }
        Mod+Shift+Ctrl+K     { move-column-to-monitor-up; }
        Mod+Shift+Ctrl+L     { move-column-to-monitor-right; }

        // Alternatively, there are commands to move just a single window:
        // Mod+Shift+Ctrl+Left  { move-window-to-monitor-left; }
        // ...

        // And you can also move a whole workspace to another monitor:
        // Mod+Shift+Ctrl+Left  { move-workspace-to-monitor-left; }
        // ...

        Mod+Page_Down      { focus-workspace-down; }
        Mod+Page_Up        { focus-workspace-up; }
        Mod+N              { focus-workspace-down; }
        Mod+P              { focus-workspace-up; }
        Mod+Ctrl+Page_Down { move-column-to-workspace-down; }
        Mod+Ctrl+Page_Up   { move-column-to-workspace-up; }
        Mod+Ctrl+U         { move-column-to-workspace-down; }
        Mod+Ctrl+I         { move-column-to-workspace-up; }

        // Alternatively, there are commands to move just a single window:
        // Mod+Ctrl+Page_Down { move-window-to-workspace-down; }
        // ...

        Mod+Shift+Page_Down { move-workspace-down; }
        Mod+Shift+Page_Up   { move-workspace-up; }
        Mod+Shift+U         { move-workspace-down; }
        Mod+Shift+I         { move-workspace-up; }

        // You can bind mouse wheel scroll ticks using the following syntax.
        // These binds will change direction based on the natural-scroll setting.
        //
        // To avoid scrolling through workspaces really fast, you can use
        // the cooldown-ms property. The bind will be rate-limited to this value.
        // You can set a cooldown on any bind, but it's most useful for the wheel.
        Mod+WheelScrollDown      cooldown-ms=150 { focus-workspace-down; }
        Mod+WheelScrollUp        cooldown-ms=150 { focus-workspace-up; }
        Mod+Ctrl+WheelScrollDown cooldown-ms=150 { move-column-to-workspace-down; }
        Mod+Ctrl+WheelScrollUp   cooldown-ms=150 { move-column-to-workspace-up; }

        Mod+WheelScrollRight      { focus-column-right; }
        Mod+WheelScrollLeft       { focus-column-left; }
        Mod+Ctrl+WheelScrollRight { move-column-right; }
        Mod+Ctrl+WheelScrollLeft  { move-column-left; }

        // Usually scrolling up and down with Shift in applications results in
        // horizontal scrolling; these binds replicate that.
        Mod+Shift+WheelScrollDown      { focus-column-right; }
        Mod+Shift+WheelScrollUp        { focus-column-left; }
        Mod+Ctrl+Shift+WheelScrollDown { move-column-right; }
        Mod+Ctrl+Shift+WheelScrollUp   { move-column-left; }

        // Similarly, you can bind touchpad scroll "ticks".
        // Touchpad scrolling is continuous, so for these binds it is split into
        // discrete intervals.
        // These binds are also affected by touchpad's natural-scroll, so these
        // example binds are "inverted", since we have natural-scroll enabled for
        // touchpads by default.
        // Mod+TouchpadScrollDown { spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.02+"; }
        // Mod+TouchpadScrollUp   { spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.02-"; }

        // You can refer to workspaces by index. However, keep in mind that
        // niri is a dynamic workspace system, so these commands are kind of
        // "best effort". Trying to refer to a workspace index bigger than
        // the current workspace count will instead refer to the bottommost
        // (empty) workspace.
        //
        // For example, with 2 workspaces + 1 empty, indices 3, 4, 5 and so on
        // will all refer to the 3rd workspace.
        Mod+1 { focus-workspace 1; }
        Mod+2 { focus-workspace 2; }
        Mod+3 { focus-workspace 3; }
        Mod+4 { focus-workspace 4; }
        Mod+5 { focus-workspace 5; }
        Mod+6 { focus-workspace 6; }
        Mod+7 { focus-workspace 7; }
        Mod+8 { focus-workspace 8; }
        Mod+9 { focus-workspace 9; }
        Mod+Shift+1 { move-column-to-workspace 1; }
        Mod+Shift+2 { move-column-to-workspace 2; }
        Mod+Shift+3 { move-column-to-workspace 3; }
        Mod+Shift+4 { move-column-to-workspace 4; }
        Mod+Shift+5 { move-column-to-workspace 5; }
        Mod+Shift+6 { move-column-to-workspace 6; }
        Mod+Shift+7 { move-column-to-workspace 7; }
        Mod+Shift+8 { move-column-to-workspace 8; }
        Mod+Shift+9 { move-column-to-workspace 9; }

        // Alternatively, there are commands to move just a single window:
        // Mod+Ctrl+1 { move-window-to-workspace 1; }

        // Switches focus between the current and the previous workspace.
        // Mod+Tab { focus-workspace-previous; }

        // The following binds move the focused window in and out of a column.
        // If the window is alone, they will consume it into the nearby column to the side.
        // If the window is already in a column, they will expel it out.
        Mod+BracketLeft  { consume-or-expel-window-left; }
        Mod+BracketRight { consume-or-expel-window-right; }

        // Consume one window from the right to the bottom of the focused column.
        Mod+Comma  { consume-window-into-column; }
        // Expel the bottom window from the focused column to the right.
        Mod+Period { expel-window-from-column; }

        // Cycle through widths set in preset-column-widths.
        Mod+R { switch-preset-column-width; }
        // Cycling through the presets in reverse order is also possible.
        Mod+Shift+R { switch-preset-column-width-back; }

        Mod+Ctrl+Shift+R { switch-preset-window-height; }
        Mod+Ctrl+R { reset-window-height; }

        Mod+F { maximize-column; }
        Mod+Shift+F { fullscreen-window; }

        // While maximize-column leaves gaps and borders around the window,
        // maximize-window-to-edges doesn't: the window expands to the edges of the screen.
        // This bind corresponds to normal window maximizing,
        // e.g. by double-clicking on the titlebar.
        Mod+M { maximize-window-to-edges; }

        // Expand the focused column to space not taken up by other fully visible columns.
        // Makes the column "fill the rest of the space".
        Mod+Ctrl+F { expand-column-to-available-width; }

        Mod+C { center-column; }

        // Center all fully visible columns on screen.
        Mod+Ctrl+C { center-visible-columns; }

        // Finer width adjustments.
        // This command can also:
        // * set width in pixels: "1000"
        // * adjust width in pixels: "-5" or "+5"
        // * set width as a percentage of screen width: "25%"
        // * adjust width as a percentage of screen width: "-10%" or "+10%"
        // Pixel sizes use logical, or scaled, pixels. I.e. on an output with scale 2.0,
        // set-column-width "100" will make the column occupy 200 physical screen pixels.
        Mod+Minus { set-column-width "-10%"; }
        Mod+Equal { set-column-width "+10%"; }

        // Finer height adjustments when in column with other windows.
        Mod+Shift+Minus { set-window-height "-10%"; }
        Mod+Shift+Equal { set-window-height "+10%"; }

        // Move the focused window between the floating and the tiling layout.
        // Mod+V       { toggle-window-floating; }
        Mod+Shift+V { switch-focus-between-floating-and-tiling; }

        // Toggle tabbed column display mode.
        // Windows in this column will appear as vertical tabs,
        // rather than stacked on top of each other.
        Mod+W { toggle-column-tabbed-display; }

        // Actions to switch layouts.
        // Note: if you uncomment these, make sure you do NOT have
        // a matching layout switch hotkey configured in xkb options above.
        // Having both at once on the same hotkey will break the switching,
        // since it will switch twice upon pressing the hotkey (once by xkb, once by niri).
        // Mod+Space       { switch-layout "next"; }
        // Mod+Shift+Space { switch-layout "prev"; }

        Print { screenshot; }
        Ctrl+Print { screenshot-screen; }
        Alt+Print { screenshot-window; }

        // Applications such as remote-desktop clients and software KVM switches may
        // request that niri stops processing the keyboard shortcuts defined here
        // so they may, for example, forward the key presses as-is to a remote machine.
        // It's a good idea to bind an escape hatch to toggle the inhibitor,
        // so a buggy application can't hold your session hostage.
        //
        // The allow-inhibiting=false property can be applied to other binds as well,
        // which ensures niri always processes them, even when an inhibitor is active.
        Mod+Escape allow-inhibiting=false { toggle-keyboard-shortcuts-inhibit; }

        // The quit action will show a confirmation dialog to avoid accidental exits.
        Mod+Shift+E { quit; }
        Ctrl+Alt+Delete { quit; }

        // Powers off the monitors. To turn them back on, do any input like
        // moving the mouse or pressing any other key.
        Mod+Shift+P { power-off-monitors; }
    }
  '';

}
