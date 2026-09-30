{
  lib,
  pkgs,
  ...
}:
let
  dataset = "zroot/ds1/persist";
  userProperties = [
    ":disko-zfs-inherit-alpha"
    ":disko-zfs-inherit-beta"
    ":disko-zfs-inherit-gamma"
  ];
in
{
  diskoConfig = import ../../disko.nix;

  initialConfig = {
    disko.devices.zpool."zroot".datasets."ds1/persist".options = {
      mountpoint = "legacy";
      atime = "on";
      ":disko-zfs-inherit-alpha" = "alpha";
      ":disko-zfs-inherit-beta" = "beta";
      ":disko-zfs-inherit-gamma" = "gamma";
    };

    systemd.services.disko-zfs-inherit-multiple-initial-state = {
      wantedBy = [ "multi-user.target" ];
      requires = [ "disko-zfs.service" ];
      after = [ "disko-zfs.service" ];
      unitConfig.ConditionPathExists = "!/run/disko-zfs-inherit-multiple-initial-state";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.zfs ];
      script = ''
        test "$(zfs get -H -o value atime ${dataset})" = on
        test "$(zfs get -H -o source atime ${dataset})" = local
        ${lib.concatMapStringsSep "\n" (property: ''
          test "$(zfs get -H -o value ${property} ${dataset})" = ${lib.removePrefix ":disko-zfs-inherit-" property}
          test "$(zfs get -H -o source ${property} ${dataset})" = local
        '') userProperties}
        touch /run/disko-zfs-inherit-multiple-initial-state
      '';
    };
  };

  newConfig = {
    disko.devices.zpool."zroot".datasets."ds1/persist".options = lib.mkForce {
      mountpoint = "legacy";
    };
  };

  extraTestScript = ''
    assert_zfs_property("${dataset}", "mountpoint", "legacy")
    machine.succeed("test -f /run/disko-zfs-inherit-multiple-initial-state")

    assert_zfs_property("${dataset}", "atime", "off")
    machine.succeed("test \"$(zfs get -H -o source atime ${dataset})\" = default -o \"$(zfs get -H -o source atime ${dataset})\" = \"inherited from zroot\"")

    ${lib.concatMapStringsSep "\n" (property: ''
      machine.succeed("test \"$(zfs get -H -o source ${property} ${dataset})\" = -")
    '') userProperties}

    machine.succeed("systemctl restart disko-zfs")
  '';
}
