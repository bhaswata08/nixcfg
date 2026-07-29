# config.nu
#
# Installed by:
# version = "0.108.0"
#
# This file is used to override default Nushell settings, define
# (or import) custom commands, or run any other startup tasks.
# See https://www.nushell.sh/book/configuration.html
#
# Nushell sets "sensible defaults" for most configuration settings, 
# so your `config.nu` only needs to override these defaults if desired.
#
# You can open this file in your default editor using:
#     config nu
#
# You can also pretty-print and page through the documentation for configuration
# options using:
#     config nu --doc | nu-highlight | less -R
# $env.config.show_banner = false
# $env.config.buffer_editor = "nvim"
# $env.config.edit_mode = 'vi'
# $env.config.cursor_shape = {
#   vi_insert: block  # or 'line'
#   vi_normal: underscore
# }
$env.config = {
  show_banner: false
  buffer_editor: "nvim"
  highlight_resolved_externals: true
  edit_mode: vi

  cursor_shape : {
    vi_insert: block  # or 'line'
    vi_normal: underscore
  }
  completions: {
    external: {
      enable: true
      max_results: 100
    }
  }
  menus: [
    {
      name: completion_menu
      only_buffer_difference: false
      marker: "| "
      type: {
        layout: columnar 
        columns: 4
        col_width: 20
        col_padding: 2
      }
      style: {
        text: green
        selected_text: green_reverse
        description_text: yellow
      }
    }
    {
      name: history_menu
      only_buffer_difference: true
      marker: "? "
      type: {
        layout: list
        page_size: 10
      }
      style: {
        text: green
        selected_text: green_reverse
        description_text: yellow
      }
    }
    {
      name: help_menu
      only_buffer_difference: true
      marker: "? "
      type: {
        layout: description
        columns: 4
        col_width: 20   # Optional value. If missing all the screen width is used to calculate column width
        col_padding: 2
        selection_rows: 4
        description_rows: 10
      }
      style: {
        text: green
        selected_text: green_reverse
        description_text: yellow
      }
    }

    {
      name: commands_menu
      only_buffer_difference: false
      marker: "# "
      type: {
        layout: columnar
        columns: 4
        col_width: 20
        col_padding: 2
      }
      style: {
        text: green
        selected_text: green_reverse
        description_text: yellow
      }
      source: { |buffer, position|
        $nu.scope.commands
        | where command =~ $buffer
        | each { |it| {value: $it.command description: $it.usage} }
      }
    }
    {
      name: vars_menu
      only_buffer_difference: true
      marker: "# "
      type: {
        layout: list
        page_size: 10
      }
      style: {
        text: green
        selected_text: green_reverse
        description_text: yellow
      }
      source: { |buffer, position|
        $nu.scope.vars
        | where name =~ $buffer
        | sort-by name
        | each { |it| {value: $it.name description: $it.type} }
      }
    }
    {
      name: commands_with_description
      only_buffer_difference: true
      marker: "# "
      type: {
        layout: description
        columns: 4
        col_width: 20
        col_padding: 2
        selection_rows: 4
        description_rows: 10
      }
      style: {
        text: green
        selected_text: green_reverse
        description_text: yellow
      }
      source: { |buffer, position|
        $nu.scope.commands
        | where command =~ $buffer
        | each { |it| {value: $it.command description: $it.usage} }
      }
    }
  ]
  keybindings: [
    {
      name: completion_menu
      modifier: none
      keycode: tab
      mode: vi_insert # Options: emacs vi_normal vi_insert
      event: {
        until: [
          { send: menu name: completion_menu }
          { send: menunext }
        ]
      }
    }
    {
      name: completion_previous
      modifier: shift
      keycode: backtab
      mode: [emacs, vi_normal, vi_insert] # Note: You can add the same keybinding to all modes by using a list
      event: { send: menuprevious }
    }
    {
      name: history_menu
      modifier: control
      keycode: char_x
      mode: vi_normal
      event: {
        until: [
          { send: menu name: history_menu }
          { send: menupagenext }
        ]
      }
    }
    {
      name: history_previous
      modifier: control
      keycode: char_z
      mode: vi_normal
      event: {
        until: [
          { send: menupageprevious }
          { edit: undo }
        ]
      }
    }
    # Keybindings used to trigger the user defined menus
    {
      name: commands_menu
      modifier: control
      keycode: char_t
      mode: [emacs, vi_normal, vi_insert]
      event: { send: menu name: commands_menu }
    }
    {
      name: vars_menu
      modifier: control
      keycode: char_y
      mode: [emacs, vi_normal, vi_insert]
      event: { send: menu name: vars_menu }
    }
    {
      name: commands_with_description
      modifier: control
      keycode: char_u
      mode: [emacs, vi_normal, vi_insert]
      event: { send: menu name: commands_with_description }
    }
    {
      name: delete_one_word_backward
      modifier: alt
      keycode: backspace
      mode: [emacs, vi_insert]
      event: { edit: backspaceword }
    }
  ]
}



# Hooks

# --- herdr automatic tab naming -------------------------------------------------
# Names the current herdr tab after the running command (e.g. `btop` -> "btop") and
# resets to the current directory's basename at the prompt. If you manually rename a
# tab (prefix+shift+t), the hook detects the change and stops auto-naming that tab for
# the rest of the shell session, so your name sticks.
def herdr-active [] {
  ($env.HERDR_ENV? | default "" | is-not-empty) and ($env.HERDR_TAB_ID? | is-not-empty)
}
def herdr-statefile [] {
  $nu.temp-dir | path join $"herdr-tabname-($env.HERDR_PANE_ID? | default $env.HERDR_TAB_ID | str replace --all ':' '_').nuon"
}
def herdr-tab-label [] {
  try { herdr tab get $env.HERDR_TAB_ID | from json | get result.tab.label } catch { null }
}
def herdr-set-tab [name: string] {
  if (not (herdr-active)) { return }
  let sf = (herdr-statefile)
  let st = (if ($sf | path exists) { open $sf } else { {managed: null, manual: false} })
  if $st.manual { return }
  let cur = (herdr-tab-label)
  # Current label differs from the last name we set => user renamed it manually.
  if ($st.managed != null) and ($cur != null) and ($cur != $st.managed) {
    {managed: $st.managed, manual: true} | save -f $sf
    return
  }
  if ($name | is-empty) or ($cur == $name) { return }
  herdr tab rename $env.HERDR_TAB_ID $name | ignore
  {managed: $name, manual: false} | save -f $sf
}
# Fresh baseline each shell start (a reused pane id must not inherit stale state).
if (herdr-active) { try { rm --force (herdr-statefile) } }

$env.config.hooks.pre_execution = (
  $env.config.hooks.pre_execution | append {||
    let name = (
      commandline | str trim | split row " "
      | where {|w| ($w | is-not-empty) and ($w | str contains "=") == false and $w != "sudo" and $w != "doas"}
      | get -o 0 | default ""
    )
    herdr-set-tab $name
  }
)
# At the prompt, reset to the current directory's basename. Replace the `let name`
# expression with a fixed string (e.g. `let name = "nu"`) for a static idle name.
$env.config.hooks.pre_prompt = (
  $env.config.hooks.pre_prompt | append {||
    let dir = ($env.PWD | path basename)
    let name = (if ($dir | is-empty) { $env.PWD } else { $dir })
    herdr-set-tab $name
  }
)
# --------------------------------------------------------------------------------

mkdir ($nu.data-dir | path join "vendor/autoload")
starship init nu | save -f ($nu.data-dir | path join "vendor/autoload/starship.nu")
source ~/.config/nushell/zoxide.nu
source ~/.config/nushell/aliases.nu
source ~/.config/nushell/completions.nu
source ~/.config/nushell/customfunctions.nu
# source ./zoxide.nu
# source ./aliases.nu
# source ./completions.nu
