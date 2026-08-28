{
  pkgs,
  ...
}:

{
  # uv downloads generic-linux CPython builds, and pip ships wheels (torch,
  # numpy, tokenizers) linked the same way. Neither can start on NixOS,
  # because they look for /lib64/ld-linux-x86-64.so.2, which does not exist
  # here. nix-ld supplies that loader plus a library search path, so a
  # `uv venv` and the wheels inside it run without patchelf or an FHS shell.
  #
  # This is what makes editor tooling that must import project code (the
  # torchtyc LSP, pytest under a uv venv) work outside `nix develop`.
  programs.nix-ld.enable = true;

  programs.nix-ld.libraries = with pkgs; [
    # libstdc++ and libgomp: every torch wheel needs both.
    stdenv.cc.cc.lib
    zlib
    openssl
    # numpy, scipy, and anything that dlopens a BLAS at import time.
    blas
    lapack
    # cv2, matplotlib, and torchvision reach for these even on headless runs.
    glib
    libGL
    xorg.libX11
    xorg.libXext
    zstd
  ];
}
