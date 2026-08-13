{
  ...
}:

{

  nix.gc = {
    automatic = true;
    dates = "weekly";
    # 3d threw away every rollback target within days of a switch. 14d keeps a
    # couple of weeks of generations to boot back into.
    options = "--delete-older-than 14d";
    persistent = true;
  };

  # Hard-link identical files in the store. Costs one scan per week, saves
  # noticeably more than the GC does.
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };

}
