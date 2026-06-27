# This file is managed by resize-btrfs-root.sh.
# The swapfile itself is created explicitly by the script using Btrfs-safe methods.
{ ... }: {
  swapDevices = [
    { device = "/swapfile"; }
  ];
}
