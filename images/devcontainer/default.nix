# A fat and modifiable Nix image
{ dockerTools
, closureInfo
, bashInteractive
, cacert
, coreutils
, curl
, direnv
, gcc-unwrapped
, gitReallyMinimal
, glibc
, gnugrep
, gnutar
, gzip
, iana-etc
, iproute
, lib
, nix
, openssh
, procps
, sedutil
, shadow
, xz
, mkUserEnvironment
}:
let
  channel = builtins.getEnv("NIXPKGS_CHANNEL");

  # generate a user profile for the image
  profile = mkUserEnvironment {
    derivations = [
      # core utils
      coreutils
      procps
      gnugrep

      # add /bin/sh
      bashInteractive
      nix

      # runtime dependencies of nix
      cacert
      gitReallyMinimal
      gnutar
      gzip
      xz

      # for haskell binaries
      iana-etc

      # for user management
      shadow

      # for the vscode extension
      gcc-unwrapped
      iproute
      sedutil

    ];
  };

  image = dockerTools.buildImage {
    name = "devcontainer";

    contents = [ ];

    extraCommands = ''
      # create the Nix DB
      export NIX_REMOTE=local?root=$PWD
      export USER=nobody
      ${nix}/bin/nix-store --load-db < ${closureInfo { rootPaths = [ profile ]; }}/registration

      # set the user profile
      ${profile}/bin/nix-env --profile nix/var/nix/profiles/default --set ${profile}

      # minimal
      mkdir -p bin usr/bin
      ln -s /nix/var/nix/profiles/default/bin/sh bin/sh
      ln -s /nix/var/nix/profiles/default/bin/env usr/bin/env

      # might as well...
      ln -s /nix/var/nix/profiles/default/bin/bash bin/bash

      # setup shadow, bashrc
      mkdir home
      cp -r ${./root/etc} etc
      chmod +w etc etc/group etc/passwd etc/shadow

      # setup iana-etc for haskell binaries
      ln -s /nix/var/nix/profiles/default/etc/protocols etc/protocols
      ln -s /nix/var/nix/profiles/default/etc/services etc/services

      # make sure /tmp exists
      mkdir -m 0777 tmp

      # allow ubuntu ELF binaries to run. VSCode copies it's own.
      mkdir -p lib64
      ln -s ${glibc}/lib64/ld-linux-x86-64.so.2 lib64/ld-linux-x86-64.so.2

      # VSCode assumes that /sbin/ip exists
      mkdir sbin
      ln -s /nix/var/nix/profiles/default/bin/ip sbin/ip
    '';

    config = {
      Cmd = [ "/nix/var/nix/profiles/default/bin/bash" ];
      Env = [
        "ENV=/nix/var/nix/profiles/default/etc/profile.d/nix.sh"
        "GIT_SSL_CAINFO=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt"
        "LD_LIBRARY_PATH=/nix/var/nix/profiles/default/lib"
        "PAGER=cat"
        "PATH=/nix/var/nix/profiles/default/bin"
        "SSL_CERT_FILE=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt"
      ]
      ++ lib.optional
        (channel != "")
        "NIX_PATH=nixpkgs=channel:${channel}"
      ;
      Labels = {
        # https://github.com/microscaling/microscaling/blob/55a2d7b91ce7513e07f8b1fd91bbed8df59aed5a/Dockerfile#L22-L33
        "org.label-schema.vcs-ref" = "master";
        "org.label-schema.vcs-url" = "https://github.com/nix-community/docker-nixpkgs";
      };
    };
  };
in
image // {
  meta = image.meta // {
    description = "Nix devcontainer for VSCode";
  };
}
