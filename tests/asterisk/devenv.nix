{ config, pkgs, ... }:

let
  port = config.processes.asterisk.ports.main.value;
  ariPort = config.processes.asterisk.ports.ari.value;
in
{
  services.asterisk = {
    enable = true;
    port = 50600;
    verbose = 1;
    ari = {
      enable = true;
      port = 80880;
      username = "devenv";
      password = "devenv";
    };
    configFiles."manager.conf" = ''
      [general]
      enabled = no
      displayconnects = no
    '';
  };

  enterTest = ''
    test "$ASTERISK_PORT" = "${toString port}"
    test "$ASTERISK_ARI_PORT" = "${toString ariPort}"
    test "$ASTERISK_ARI_URL" = "http://127.0.0.1:${toString ariPort}/ari"
    grep -qx "autoload=no" "$ASTERISK_CONFIG_DIR/modules.conf"
    grep -qx "load = chan_pjsip.so" "$ASTERISK_CONFIG_DIR/modules.conf"
    grep -qx "load = res_ari.so" "$ASTERISK_CONFIG_DIR/modules.conf"
    grep -qx "enabled = yes" "$ASTERISK_CONFIG_DIR/ari.conf"
    grep -qx "bindport = ${toString ariPort}" "$ASTERISK_CONFIG_DIR/http.conf"
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

    ${pkgs.curl}/bin/curl \
      --fail \
      --user "$ASTERISK_ARI_USERNAME:$ASTERISK_ARI_PASSWORD" \
      "$ASTERISK_ARI_URL/asterisk/info" | grep -q '"system"'
  '';
}
