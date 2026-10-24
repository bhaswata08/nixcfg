{
  ...
}:

{

  nix.settings = {
    # Unset, these are max-jobs = auto (16 on this CPU) and cores = 0
    # (unlimited threads per job), so one `nh os switch` could run 16
    # derivations of 16 threads each. On a 16-thread laptop with 15GiB of RAM
    # and zram as the only swap, that starved the session it was launched from:
    # the desktop paged out, and zram then compressed on the same cores the
    # build had taken. 4 x 4 keeps the ceiling at the thread count the machine
    # actually has.
    max-jobs = 4;
    cores = 4;
  };

  # Build processes inherit these from the daemon. At the defaults ("other" and
  # best-effort) compilers compete with niri and the browser on equal footing
  # for both CPU and disk. idle means a build only runs when nothing else wants
  # the machine, which can starve a rebuild under sustained load; on a laptop
  # that is the right way round.
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";

}
