{ ... }:

{
  programs.starship = {
    enable = true;
    settings = {
      format = ''
        $directory$git_branch$git_status$fill$lua$python$nix_shell$rust$docker_context$jobs$cmd_duration$line_break$character'';

      python = {
        style = "teal";
        symbol = "󰌠";
        format = "[$symbol$pyenv_prefix($version )(($virtualenv) )]($style)";
        pyenv_version_name = true;
        pyenv_prefix = "";
      };

      fill = {
        symbol = " ";
        disabled = false;
      };
      directory = {
	format = "[$path ]($style)[$read_only]($read_only_style) ";
	truncation_length = 3;
	truncation_symbol = "_/";
	truncate_to_repo = false;
        home_symbol = "~";
        read_only = " ";
        read_only_style = "red";
        repo_root_format = "[$before_root_path]($style)[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style) ";
      };
      directory.substitutions = {
        "Documents" = " ";
        "Downloads" = " ";
        "Music" = " ";
        "Pictures" = " ";
      };
      git_branch = {
        format = "[$symbol$branch(:$remote_branch)]($style) ";
        symbol = " ";
        style = "bold purple bg:0xFCA17D";
        truncation_length = 9223372036854775807;
        truncation_symbol = "…";
        only_attached = false;
        always_show_remote = false;
        ignore_branches = [];
        disabled = false;
      };
      git_status = {
        ahead = "🏎💨$count";
        behind = "😰$count";
        conflicted = "🏳";
        deleted = "🗑";
        disabled = false;
        diverged = "😵";
        format = "([$all_status$ahead_behind]($style) )";
        ignore_submodules = false;
        modified = "📝";
        renamed = "👅";
        staged = "[++($count)](green)";
        stashed = "📦";
        style = "red bold bg:0xFCA17D";
        untracked = "🤷";
        up_to_date = "✓";
      };
    };
  };
}
