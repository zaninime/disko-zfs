{
  diskoConfig = import ../../disko.nix;

  newConfig = {
    disko.devices.zpool."zroot".datasets."ds1/volume" = {
      type = "zfs_volume";
      size = "10M";
      options = {
        volblocksize = "4096";
        compression = "zle";
      };
    };
  };

  extraTestScript = ''
    assert_zfs_dataset_exists("zroot/ds1/volume")
    assert_zfs_property("zroot/ds1/volume", "volsize", "10M")
    assert_zfs_property("zroot/ds1/volume", "volblocksize", "4K")
    assert_zfs_property("zroot/ds1/volume", "compression", "zle")
    machine.succeed("test $(zfs list -H -o type zroot/ds1/volume) = volume")

    machine.succeed("systemctl restart disko-zfs")
    machine.succeed("! journalctl -u disko-zfs --since '1 second ago' --no-pager | grep '^+ zfs '")
  '';
}
