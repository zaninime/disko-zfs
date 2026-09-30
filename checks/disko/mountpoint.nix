{ ... }:
let
  diskoConfig = {
    disko.devices = {
      disk.x = {
        type = "disk";
        device = "/dev/vda";
        imageSize = "4G";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "64M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };

      zpool.zroot = {
        type = "zpool";
        mountpoint = "/pool-root";
        rootFsOptions = {
          compression = "zstd";
        };
        datasets = {
          root = {
            type = "zfs_fs";
            mountpoint = "/";
            options.mountpoint = "legacy";
          };
          native = {
            type = "zfs_fs";
            mountpoint = "/native";
          };
          explicit = {
            type = "zfs_fs";
            mountpoint = "/top-level-is-overridden";
            options.mountpoint = "/explicit";
          };
          legacy = {
            type = "zfs_fs";
            mountpoint = "/legacy";
            options.mountpoint = "legacy";
          };
          none = {
            type = "zfs_fs";
            mountpoint = "/none";
            options.mountpoint = "none";
          };
          unmounted = {
            type = "zfs_fs";
            options.canmount = "off";
          };
        };
      };
    };
  };

  assertEffectiveProperties =
    { config, pkgs, ... }:
    let
      datasets = config.disko.zfs.settings.datasets;
    in
    {
      environment.systemPackages = [ config.disko.zfs.package ];
      environment.etc."disko-zfs-spec.json".source =
        (pkgs.formats.json { }).generate "disko-zfs-spec.json" config.disko.zfs.settings;

      assertions = [
        {
          assertion = datasets.zroot.properties.mountpoint == "/pool-root";
          message = "The pool root must use the zpool mountpoint.";
        }
        {
          assertion = datasets."zroot/native".properties.mountpoint == "/native";
          message = "A zfs_fs mountpoint must be preserved as a ZFS property.";
        }
        {
          assertion = datasets."zroot/explicit".properties.mountpoint == "/explicit";
          message = "options.mountpoint must override a zfs_fs mountpoint.";
        }
        {
          assertion = datasets."zroot/legacy".properties.mountpoint == "legacy";
          message = "An explicit legacy mountpoint must be preserved.";
        }
        {
          assertion = datasets."zroot/none".properties.mountpoint == "none";
          message = "An explicit none mountpoint must be preserved.";
        }
        {
          assertion = !(datasets."zroot/unmounted".properties ? mountpoint);
          message = "An absent zfs_fs mountpoint must not synthesize a property.";
        }
      ];
    };
in
{
  inherit diskoConfig;

  initialConfig = {
    imports = [
      diskoConfig
      assertEffectiveProperties
    ];
  };

  newConfig = {
    imports = [ assertEffectiveProperties ];
  };

  extraTestScript = ''
    for dataset, mountpoint in {
      "zroot": "/pool-root",
      "zroot/native": "/native",
      "zroot/explicit": "/explicit",
      "zroot/legacy": "legacy",
      "zroot/none": "none",
    }.items():
      assert machine.succeed(
        f"zfs get -H -o value,source mountpoint {dataset}"
      ).strip() == f"{mountpoint}\tlocal"

    machine.succeed("systemctl restart disko-zfs")
    for dataset, mountpoint in {
      "zroot": "/pool-root",
      "zroot/native": "/native",
      "zroot/explicit": "/explicit",
      "zroot/legacy": "legacy",
      "zroot/none": "none",
    }.items():
      assert machine.succeed(
        f"zfs get -H -o value,source mountpoint {dataset}"
      ).strip() == f"{mountpoint}\tlocal"

    plan = machine.succeed("disko-zfs plan --spec /etc/disko-zfs-spec.json")
    assert "mountpoint" not in plan
  '';
}
