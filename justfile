switch:
    nh os switch .

boot:
    nh os boot .

test:
    nh os test .

update:
    NIX_CONFIG="access-tokens = github.com=$(gh auth token)" nix flake update
    git add flake.lock
    git diff --cached --quiet flake.lock || { git commit -m "global(flake.lock): update flake lock" flake.lock && git push; }
