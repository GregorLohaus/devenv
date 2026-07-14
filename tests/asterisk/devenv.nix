{ config, pkgs, ... }:

let
  port = config.processes.asterisk.ports.main.value;
in
{
  services.asterisk = {
    enable = true;
    port = 50600;
    verbose = 1;
    configFiles."manager.conf" = ''
      [general]
      enabled = no
      displayconnects = no
    '';
  };

  enterTest = ''
    test "$ASTERISK_PORT" = "${toString port}"
    grep -qx "autoload=no" "$ASTERISK_CONFIG_DIR/modules.conf"
    grep -qx "load = chan_pjsip.so" "$ASTERISK_CONFIG_DIR/modules.conf"
    grep -qx "enable = no" "$ASTERISK_CONFIG_DIR/cdr.conf"
    grep -qx "displayconnects = no" "$ASTERISK_CONFIG_DIR/manager.conf"
    grep -qx "type = startup" "$ASTERISK_CONFIG_DIR/pjproject.conf"
    test -S "$ASTERISK_RUNTIME_DIR/asterisk.ctl"

    ${pkgs.asterisk}/bin/asterisk \
      -C "$ASTERISK_CONFIG_DIR/asterisk.conf" \
      -rx "core show uptime"

    ${pkgs.asterisk}/bin/asterisk \
      -C "$ASTERISK_CONFIG_DIR/asterisk.conf" \
      -rx "pjsip show transports" | grep -q devenv-udp
  '';
}
