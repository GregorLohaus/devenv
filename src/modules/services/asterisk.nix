{ pkgs, lib, config, ... }:

let
  cfg = config.services.asterisk;
  types = lib.types;

  # SIP uses UDP by default, but devenv's port allocator still gives us a
  # stable conflict-free port value to inject into pjsip.conf.
  basePort = cfg.port;
  allocatedPort = config.processes.asterisk.ports.main.value;
  baseAriPort = cfg.ari.port;
  allocatedAriPort = if cfg.ari.enable then config.processes.asterisk.ports.ari.value else baseAriPort;

  bindAddress = if cfg.bind == null then "0.0.0.0" else cfg.bind;
  ariBindAddress = if cfg.ari.bind == null then "0.0.0.0" else cfg.ari.bind;
  stateDir = config.env.DEVENV_STATE + "/asterisk";
  runtimeDir = config.env.DEVENV_RUNTIME + "/asterisk";
  configDir = stateDir + "/config";
  cacheDir = stateDir + "/cache";
  dataDir = stateDir + "/lib";
  packageDataDir = "${cfg.package}/var/lib/asterisk";
  logDir = stateDir + "/log";
  spoolDir = stateDir + "/spool";

  defaultModules = [
    "res_pjproject.so"
    "res_sorcery_config.so"
    "res_sorcery_memory.so"
    "res_sorcery_astdb.so"
    "res_pjsip.so"
    "res_pjsip_pubsub.so"
    "res_pjsip_session.so"
    "res_rtp_asterisk.so"
    "res_pjsip_endpoint_identifier_ip.so"
    "res_pjsip_endpoint_identifier_user.so"
    "res_pjsip_authenticator_digest.so"
    "res_pjsip_outbound_authenticator_digest.so"
    "res_pjsip_registrar.so"
    "res_pjsip_sdp_rtp.so"
    "chan_pjsip.so"
    "pbx_config.so"
    "app_echo.so"
    "app_dial.so"
    "codec_ulaw.so"
    "codec_alaw.so"
  ];

  ariModules = [
    "res_http_websocket.so"
    "res_websocket_client.so"
    "res_stasis.so"
    "res_ari.so"
    "res_ari_model.so"
    "app_stasis.so"
    "res_stasis_answer.so"
    "res_stasis_device_state.so"
    "res_stasis_playback.so"
    "res_stasis_recording.so"
    "res_stasis_snoop.so"
    "res_ari_applications.so"
    "res_ari_asterisk.so"
    "res_ari_bridges.so"
    "res_ari_channels.so"
    "res_ari_device_states.so"
    "res_ari_endpoints.so"
    "res_ari_events.so"
    "res_ari_playbacks.so"
    "res_ari_recordings.so"
    "res_ari_sounds.so"
    "app_exec.so"
  ];

  modulesConfig = lib.concatStringsSep "\n" (
    [
      "autoload=${if cfg.modules.autoload then "yes" else "no"}"
    ]
    ++ map (module: "preload = ${module}") cfg.modules.preload
    ++ map (module: "load = ${module}") (cfg.modules.load ++ lib.optionals cfg.ari.enable ariModules)
    ++ map (module: "noload = ${module}") cfg.modules.noload
  );

  defaultConfigFiles = {
    "asterisk.conf" = ''
      [directories]
      astetcdir => ${configDir}
      astmoddir => ${cfg.package}/lib/asterisk/modules
      astvarlibdir => ${dataDir}
      astdbdir => ${dataDir}
      astkeydir => ${dataDir}/keys
      astcachedir => ${cacheDir}
      astdatadir => ${packageDataDir}
      astagidir => ${dataDir}/agi-bin
      astspooldir => ${spoolDir}
      astrundir => ${runtimeDir}
      astlogdir => ${logDir}
      astsbindir => ${cfg.package}/bin

      [options]
      nofork=yes
      quiet=no
      verbose=${toString cfg.verbose}
      timestamp=yes
      ${cfg.extraAsteriskConfig}

      [files]
      astctl = asterisk.ctl
    '';

    "modules.conf" = ''
      [modules]
      ${modulesConfig}
      ${cfg.extraModulesConfig}
    '';

    "pjsip.conf" = ''
      [devenv-udp]
      type=transport
      protocol=udp
      bind=${bindAddress}:${toString allocatedPort}
      ${cfg.extraPjsipConfig}
    '';

    "extensions.conf" = ''
      [general]
      static=yes
      writeprotect=no

      [default]

      [internal]
      ${cfg.extraExtensionsConfig}
    '';

    "logger.conf" = ''
      [general]
      dateformat = %F %T

      [logfiles]
      console => notice,warning,error,verbose
      ${cfg.extraLoggerConfig}
    '';

    "stasis.conf" = ''
      [taskpool]

      [declined_message_types]
    '';

    "ccss.conf" = ''
      [general]
      enabled = no
    '';

    "cdr.conf" = ''
      [general]
      enable = no
    '';

    "cel.conf" = ''
      [general]
      enable = no
    '';

    "features.conf" = ''
      [general]

      [featuremap]

      [applicationmap]
    '';

    "indications.conf" = ''
      [general]
      country = us

      [us]
      description = United States / North America
      ringcadence = 2000,4000
      dial = 350+440
      busy = 480+620/500,0/500
      ring = 440+480/2000,0/4000
      congestion = 480+620/250,0/250
      callwaiting = 440/300,0/10000
      dialrecall = 350+440
      record = 1400/500,0/15000
      info = !950/330,!1400/330,!1800/330,0/1000
      stutter = 350+440
    '';

    "acl.conf" = "";

    "manager.conf" = ''
      [general]
      enabled = no
    '';

    "udptl.conf" = ''
      [general]
      udptlstart = 4000
      udptlend = 4999
    '';

    "pjproject.conf" = ''
      [startup]
      type = startup
    '';
  };

  ariConfigFiles = {
    "ari.conf" = ''
      [general]
      enabled = yes
      pretty = ${if cfg.ari.pretty then "yes" else "no"}
      ${lib.optionalString (cfg.ari.allowedOrigins != null) "allowed_origins = ${cfg.ari.allowedOrigins}"}
      ${cfg.ari.extraAriConfig}

      [${cfg.ari.username}]
      type = user
      read_only = ${if cfg.ari.readOnly then "yes" else "no"}
      password = ${cfg.ari.password}
      password_format = plain
    '';

    "http.conf" = ''
      [general]
      enabled = yes
      bindaddr = ${ariBindAddress}
      bindport = ${toString allocatedAriPort}
      tlsenable = no
      ${cfg.ari.extraHttpConfig}
    '';

    "websocket_client.conf" = "";
  };

  generatedConfigFiles = defaultConfigFiles // lib.optionalAttrs cfg.ari.enable ariConfigFiles;
  configFiles = generatedConfigFiles // cfg.configFiles // cfg.extraConfigFiles;
  configSourceDir = pkgs.linkFarm "asterisk-config" (
    lib.mapAttrsToList
      (name: text: {
        inherit name;
        path = pkgs.writeText name text;
      })
      configFiles
  );

  reservedConfigFileNames = builtins.attrNames generatedConfigFiles;
  collidingConfigFileNames = lib.intersectLists reservedConfigFileNames (builtins.attrNames cfg.extraConfigFiles);
in
{
  options.services.asterisk = {
    enable = lib.mkEnableOption "Asterisk PBX";

    package = lib.mkOption {
      type = types.package;
      description = "Which package of Asterisk to use.";
      default = pkgs.asterisk;
      defaultText = lib.literalExpression "pkgs.asterisk";
    };

    bind = lib.mkOption {
      type = types.nullOr types.str;
      default = "127.0.0.1";
      description = ''
        The IP interface for the default PJSIP UDP transport to bind to.
        `null` means "all interfaces".
      '';
      example = "127.0.0.1";
    };

    port = lib.mkOption {
      type = types.port;
      default = 5060;
      description = "The UDP port for the default PJSIP transport.";
    };

    verbose = lib.mkOption {
      type = types.ints.unsigned;
      default = 0;
      description = "Asterisk verbose logging level.";
    };

    extraAsteriskConfig = lib.mkOption {
      type = types.lines;
      default = "";
      description = "Additional text to append to `asterisk.conf` in the `[options]` section.";
    };

    extraModulesConfig = lib.mkOption {
      type = types.lines;
      default = "";
      description = "Additional text to append to `modules.conf` in the `[modules]` section.";
      example = ''
        noload = chan_sip.so
      '';
    };

    modules = {
      autoload = lib.mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether Asterisk should automatically load every available module.
          The default is disabled to keep devenv startup quiet and predictable.
        '';
      };

      load = lib.mkOption {
        type = types.listOf types.str;
        default = defaultModules;
        defaultText = lib.literalExpression ''
          [
            "res_pjproject.so"
            "res_sorcery_config.so"
            "res_sorcery_memory.so"
            "res_sorcery_astdb.so"
            "res_pjsip.so"
            "res_pjsip_pubsub.so"
            "res_pjsip_session.so"
            "res_rtp_asterisk.so"
            "res_pjsip_endpoint_identifier_ip.so"
            "res_pjsip_endpoint_identifier_user.so"
            "res_pjsip_authenticator_digest.so"
            "res_pjsip_outbound_authenticator_digest.so"
            "res_pjsip_registrar.so"
            "res_pjsip_sdp_rtp.so"
            "chan_pjsip.so"
            "pbx_config.so"
            "app_echo.so"
            "app_dial.so"
            "codec_ulaw.so"
            "codec_alaw.so"
          ]
        '';
        description = ''
          Asterisk modules to load explicitly in `modules.conf`.
          Set this to add a larger feature set, or use `lib.mkForce [ ]` together with `modules.autoload = true` to rely entirely on autoloading.
        '';
        example = [
          "res_pjproject.so"
          "res_pjsip.so"
          "chan_pjsip.so"
          "app_echo.so"
        ];
      };

      preload = lib.mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Asterisk modules to preload before normal module loading.";
        example = [ "res_config_sqlite3.so" ];
      };

      noload = lib.mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Asterisk modules to prevent from loading.";
        example = [ "chan_sip.so" ];
      };
    };

    ari = {
      enable = lib.mkEnableOption "Asterisk REST Interface (ARI)";

      bind = lib.mkOption {
        type = types.nullOr types.str;
        default = "127.0.0.1";
        description = ''
          The IP interface for Asterisk's HTTP server, used by ARI.
          `null` means "all interfaces".
        '';
        example = "127.0.0.1";
      };

      port = lib.mkOption {
        type = types.port;
        default = 8088;
        description = "The HTTP port for Asterisk ARI.";
      };

      username = lib.mkOption {
        type = types.str;
        default = "asterisk";
        description = "ARI username.";
      };

      password = lib.mkOption {
        type = types.str;
        default = "asterisk";
        description = ''
          ARI password.
          This is written to the generated `ari.conf` and is visible in the Nix store.
        '';
      };

      readOnly = lib.mkOption {
        type = types.bool;
        default = false;
        description = "Whether the generated ARI user should be read-only.";
      };

      pretty = lib.mkOption {
        type = types.bool;
        default = false;
        description = "Whether ARI responses should be formatted for readability.";
      };

      allowedOrigins = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Comma-separated ARI CORS allowed origins. Use `*` to allow all origins.";
        example = "http://localhost:3000";
      };

      extraAriConfig = lib.mkOption {
        type = types.lines;
        default = "";
        description = "Additional text to append to `ari.conf` in the `[general]` section.";
      };

      extraHttpConfig = lib.mkOption {
        type = types.lines;
        default = "";
        description = "Additional text to append to `http.conf` in the `[general]` section.";
      };
    };

    extraPjsipConfig = lib.mkOption {
      type = types.lines;
      default = "";
      description = "Additional text to append to `pjsip.conf` after the default UDP transport.";
      example = ''
        [6001]
        type=endpoint
        context=internal
        disallow=all
        allow=ulaw
        auth=auth6001
        aors=6001

        [auth6001]
        type=auth
        auth_type=userpass
        password=6001
        username=6001

        [6001]
        type=aor
        max_contacts=1
      '';
    };

    extraExtensionsConfig = lib.mkOption {
      type = types.lines;
      default = "";
      description = "Additional text to append to `extensions.conf` after the generated `[internal]` context.";
    };

    extraLoggerConfig = lib.mkOption {
      type = types.lines;
      default = "";
      description = "Additional text to append to `logger.conf` in the `[logfiles]` section.";
    };

    configFiles = lib.mkOption {
      type = types.attrsOf types.lines;
      default = { };
      description = ''
        Asterisk configuration files to override or add in `astetcdir`.
        Values here are merged over devenv's generated defaults, so this can be used to replace generated files such as `manager.conf`, `cdr.conf`, or `pjproject.conf`.
      '';
      example = lib.literalExpression ''
        {
          "manager.conf" = "[general]\nenabled=yes\nbindaddr=127.0.0.1\nport=5038\n";
        }
      '';
    };

    extraConfigFiles = lib.mkOption {
      type = types.attrsOf types.lines;
      default = { };
      description = ''
        Additional Asterisk configuration files to place in `astetcdir`.
        Generated files cannot be replaced through this option; use `services.asterisk.configFiles` to override generated files.
      '';
      example = lib.literalExpression ''
        {
          "http.conf" = "[general]\nenabled=no\n";
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = collidingConfigFileNames == [ ];
        message = "services.asterisk.extraConfigFiles cannot replace generated files: ${lib.concatStringsSep ", " collidingConfigFileNames}";
      }
    ];

    packages = [ cfg.package ];

    env = {
      ASTERISK_PORT = allocatedPort;
      ASTERISK_HOST = bindAddress;
      ASTERISK_CONFIG_DIR = configDir;
      ASTERISK_STATE_DIR = stateDir;
      ASTERISK_CACHE_DIR = cacheDir;
      ASTERISK_DATA_DIR = dataDir;
      ASTERISK_RUNTIME_DIR = runtimeDir;
      ASTERISK_LOG_DIR = logDir;
      ASTERISK_SPOOL_DIR = spoolDir;
    } // lib.optionalAttrs cfg.ari.enable {
      ASTERISK_ARI_HOST = ariBindAddress;
      ASTERISK_ARI_PORT = allocatedAriPort;
      ASTERISK_ARI_URL = "http://${ariBindAddress}:${toString allocatedAriPort}/ari";
      ASTERISK_ARI_USERNAME = cfg.ari.username;
      ASTERISK_ARI_PASSWORD = cfg.ari.password;
    };

    tasks."devenv:asterisk:setup" = {
      exec = ''
        mkdir -p \
          "$ASTERISK_STATE_DIR" \
          "$ASTERISK_CONFIG_DIR" \
          "$ASTERISK_CACHE_DIR" \
          "$ASTERISK_DATA_DIR" \
          "$ASTERISK_DATA_DIR/agi-bin" \
          "$ASTERISK_DATA_DIR/keys" \
          "$ASTERISK_RUNTIME_DIR" \
          "$ASTERISK_LOG_DIR" \
          "$ASTERISK_SPOOL_DIR"
        chmod 700 "$ASTERISK_RUNTIME_DIR"
        find "$ASTERISK_CONFIG_DIR" -mindepth 1 -maxdepth 1 -type f -delete
        cp -L ${configSourceDir}/* "$ASTERISK_CONFIG_DIR"/
      '';
      before = [ "devenv:processes:asterisk" ];
    };

    processes.asterisk = {
      ports = {
        main.allocate = basePort;
      } // lib.optionalAttrs cfg.ari.enable {
        ari.allocate = baseAriPort;
      };
      exec = "exec ${cfg.package}/bin/asterisk -f -C \"$ASTERISK_CONFIG_DIR/asterisk.conf\"";

      ready = {
        exec = "${cfg.package}/bin/asterisk -C \"$ASTERISK_CONFIG_DIR/asterisk.conf\" -rx 'core show uptime' >/dev/null";
        initial_delay = 2;
        period = 5;
        probe_timeout = 4;
        failure_threshold = 6;
      };
    };
  };
}
