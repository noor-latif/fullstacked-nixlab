# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../modules/mox.nix
    ];

  # Bootloader.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;
  # Use provided UUIDs instead of blkid probing (required for btrfs subvolumes)
  boot.loader.grub.fsIdentifier = "provided";

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Stockholm";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "sv_SE.UTF-8";
    LC_IDENTIFICATION = "sv_SE.UTF-8";
    LC_MEASUREMENT = "sv_SE.UTF-8";
    LC_MONETARY = "sv_SE.UTF-8";
    LC_NAME = "sv_SE.UTF-8";
    LC_NUMERIC = "sv_SE.UTF-8";
    LC_PAPER = "sv_SE.UTF-8";
    LC_TELEPHONE = "sv_SE.UTF-8";
    LC_TIME = "sv_SE.UTF-8";
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "se";
    variant = "";
  };

  # Configure console keymap
  console.keyMap = "sv-latin1";

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users."noor" = {
    isNormalUser = true;
    description = "noor latif";
    extraGroups = [ "docker" "networkmanager" "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMD1a6dnz8xFdZR+yAS+/YHmatPnBEz+xyg8GcVkltYg noor@latif"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDU6iYvZ76pfJ29nap9ZNkHKlRjg1krWjzzZr4HUs71KR6VO0YxKvSFeXOdIZdXcQU9gSI3RZTZ5Tzt+jaThAZPAYFcn7YxHip1nC1ytsEP9mSmmqmXAxToacURhAQvvblrSEE0Fn5ANkSBQASGw+/0KWi5BIvcQs1Loo0cfShpEq8Lts5Rtd3pmzpv2n7bDfhd63K+eivfKEfLmeRDGEa9dSlcL0qLahBKJGSDcpv+9n9ZcS4O9ZaDqF0C6lwIxnm2j4umgW8rllgXxazIaJ/j158LqQiJ/2c0uiQWAURpJ5Ji/Jff6bKDmFGAptPn1X2UbQ4kiV8KKQ65fjrIeKfREKbYVBeMIJFq2zpxqm5HPoGKRoFiJ0nwa35bPFszaMtkG8LXrSHnx44rzMMOhxlcrV+pz1uIStLn/Dbmg8g8OMCGSSH3/xaCG+MrTN2Drx+nyS6PTl9nePEnoeH7Wmkc8YNzBkw8Mmw6pijtz5zx6jfiSDwHhQjtY6wUhHLy1fY48asC0qmpBw5tb676939TsPuvKob+dbEHSaTkMHO8DNnZXmwz4Ohz57uMDb8KlF9zM99vEWvkzRwsw0xKvYDH8BO1S+YI6ceP6LhU9/5Qx6tUScjL6X8AvIq6xTSv1/wKKgot1oAMWq9+CF3C4QjoXzV7nIFCOETmKQbeeVKBiQ== #SSH ID - @noorlatif"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC1xwkhzEy//NoXRXL5v+jZ+z3CzTgvjjJo64944muBOszYKM4V7JWIaabqElWqVolVJdX8uMFJDm5TY2i5DF9eiP7IeeNL2E6rsMdOmgCXwBBAe1zKyAN8JOgMjCGqV15CjBS8IqfaPbAPwNLlbLPcHRQe+NU02KsbKOSkJy0wwDeRtAcoetwesu9D3fVwGWe3+HoKJOp1rO/Y1Kwfc927clUWwHUzvqVz7ioHnpGF9rP71Ly19ZnMdWmD9VRqwJ8fco1LSB+y7hR8yoLbjfEzlLj84nZZ16lOXm9RXUHDgmdVAsftKvHS9s+swkMrVWpX4wm3Ed9yzp43iOY5dYtxDH/6d/pG4sz40crBEPLAiH1lqsHbqTeRqIMVaB0DBH0Al82Bita3u4Ha7JJ4yxDapRUUZVdiS7izykPJ65bJAKVQgBonP8qmMITNPFVYmn+lkfaVQ8aHieELjv4dc/2Mqp1Hc+2YRZ4U5XQE2jVi4E94e2MRJ/xvF4v/9Mqnmy9sMCYNYIODnCTagHhEFD3NGMAXRRnEHSQ/fAU7BXuv02WDhk61Ntyc/BLBxZGNfOItD5RvqKckLyTbT3mtq046zljJJepUx4V+vsGHzMjWlAR7+dJuJ6KDISVatYh0l4LPcANGmy8b7uCqtaU+zsi0Nk+WOoM+Uy6xBtpTfi2ghw== #SSH ID - @noorlatif"
    ];
    packages = with pkgs; [];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    docker-compose
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  wget
  ];

  environment.shellAliases = {
    apply = "sudo nixos-rebuild switch --flake /home/noor/dev/pangolin-mailserver-vps#nixos";
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable QEMU guest agent for VM filesystem and diagnostics reporting.
  services.qemuGuest.enable = true;

  # Enable hardened, key-only SSH access.
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      AllowUsers = [ "noor" ];
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 ];
    allowedUDPPorts = [ 51820 21820 ];
  };
  security.sudo.wheelNeedsPassword = true;
  services.fail2ban.enable = true;

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "26.05"; # Did you read the comment?

}
