switch:
    nh os switch .

boot:
    nh os boot .

test:
    nh os test .

# Every nh build leaves a gcroot in /tmp pinning its whole system closure,
# and nothing removes them. 17 had piled up by October 2026, holding 134 GiB
# of store between them, which is why the weekly nix-gc kept freeing almost
# nothing. 14d is the window modules/garbagecollector.nix already uses.
# Drop old generations and the gcroots nh left behind
clean:
    nh clean all --keep 3 --keep-since 14d

update:
    nix flake update
    git add flake.lock
    git commit -m "global(flake.lock): update flake lock"
    git push
