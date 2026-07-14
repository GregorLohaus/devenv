{ pkgs, lib, config, ... }:

let
  cfg = config.services.asterisk;
  types = lib.types;

  # SIP uses UDP by default, but devenv's port allocator still gives us a
  # stable conflict-free port value to inject into pjsip.conf.
  basePort = cfg.port;
  allocatedPort = config.processes.asterisk.ports.main.value;

  bindAddress = if cfg.bind == null then "0.0.0.0" else cfg.bind;
  stateDir = config.env.DEVENV_STATE + "/asterisk";
  runtimeDir = config.env.DEVENV_RUNTIME + "/asterisk";
  configDir = stateDir + "/config";
  cacheDir = stateDir + "/cache";
  dataDir = stateDir + "/lib";
  logDir = stateDir + "/log";
  spoolDir = stateDir + "/spool";

  generatedConfigFiles = {
    "asterisk.conf" = ''
      [directories]
      astetcdir => ${configDir}
      astmoddir => ${cfg.package}/lib/asterisk/modules
      astvarlibdir => ${dataDir}
      astdbdir => ${dataDir}
      astkeydir => ${dataDir}/keys
      astcachedir => ${cacheDir}
      astdatadir => ${cfg.package}/share/asterisk
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
      autoload=yes
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
  };

  configFiles = generatedConfigFiles // cfg.extraConfigFiles;
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
        noload => chan_sip.so
      '';
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

    extraConfigFiles = lib.mkOption {
      type = types.attrsOf types.lines;
      default = { };
      description = ''
        Additional Asterisk configuration files to place in `astetcdir`.
        Generated core files cannot be replaced through this option.
      '';
      example = lib.literalExpression ''
        {
          "manager.conf" = "[general]\nenabled=yes\nbindaddr=127.0.0.1\nport=5038\n";
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
      ports.main.allocate = basePort;
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
