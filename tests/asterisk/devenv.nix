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
      port = 18088;
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
    grep -qx "load = res_stasis_recording.so" "$ASTERISK_CONFIG_DIR/modules.conf"
    grep -qx "enabled = yes" "$ASTERISK_CONFIG_DIR/ari.conf"
    grep -qx "bindport = ${toString ariPort}" "$ASTERISK_CONFIG_DIR/http.conf"
    test -f "$ASTERISK_CONFIG_DIR/websocket_client.conf"
    grep -qx "enable = no" "$ASTERISK_CONFIG_DIR/cdr.conf"
    grep -qx "displayconnects = no" "$ASTERISK_CONFIG_DIR/manager.conf"
    grep -qx "type = startup" "$ASTERISK_CONFIG_DIR/pjproject.conf"
    test "$(grep -n "load = res_stasis_recording.so" "$ASTERISK_CONFIG_DIR/modules.conf" | cut -d: -f1)" -lt \
      "$(grep -n "load = res_ari_recordings.so" "$ASTERISK_CONFIG_DIR/modules.conf" | cut -d: -f1)"
    test -S "$ASTERISK_RUNTIME_DIR/asterisk.ctl"

    ${pkgs.asterisk}/bin/asterisk \
      -C "$ASTERISK_CONFIG_DIR/asterisk.conf" \
      -rx "core show uptime"

    ${pkgs.asterisk}/bin/asterisk \
      -C "$ASTERISK_CONFIG_DIR/asterisk.conf" \
      -rx "pjsip show transports" | grep -q devenv-udp

    ${pkgs.asterisk}/bin/asterisk \
      -C "$ASTERISK_CONFIG_DIR/asterisk.conf" \
      -rx "ari show status" | grep -q "Enabled: Yes"

    ${pkgs.asterisk}/bin/asterisk \
      -C "$ASTERISK_CONFIG_DIR/asterisk.conf" \
      -rx "ari show users" | grep -q "$ASTERISK_ARI_USERNAME"
  '';
}
