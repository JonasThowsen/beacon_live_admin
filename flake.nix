{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forEachSupportedSystem =
        f:
        inputs.nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            pkgs = import inputs.nixpkgs { inherit system; };
            pkgsUnstable = import inputs.nixpkgs-unstable { inherit system; };
          }
        );

      commonEnv = pkgs: {
        MIX_TAILWIND_PATH = pkgs.lib.getExe pkgs.tailwindcss_4;
        MIX_ESBUILD_PATH = pkgs.lib.getExe pkgs.esbuild;
      };

      beam_pkgs =
        pkgs:
        let
          beamPackages = pkgs.beam.packagesWith pkgs.beam.interpreters.erlang_28;
          elixir = beamPackages.elixir_1_19;
        in
        beamPackages.extend (self: super: { inherit elixir; });
    in
    {
      devShells = forEachSupportedSystem (
        { pkgs, pkgsUnstable }:
        {
          default = pkgs.mkShell {
            packages = (if pkgs.stdenv.isLinux then [ pkgs.inotify-tools ] else [ ]) ++ [
              (beam_pkgs pkgs).elixir_1_19
              pkgs.tailwindcss_4
              pkgs.esbuild
              pkgs.watchman
            ];

            env = commonEnv pkgs;
          };
        }
      );

      packages = forEachSupportedSystem (
        { pkgs, pkgsUnstable }:
        rec {
          beacon_live_admin =
            let
              beamPackages = beam_pkgs pkgs;
              mixNixDeps = pkgs.callPackages ./deps.nix { inherit beamPackages; };
              pname = "beacon_live_admin";
              version = "0.0.1";
            in
            beamPackages.mixRelease {
              inherit pname version mixNixDeps;
              src = pkgs.lib.cleanSource ./.;
              env = commonEnv pkgs;

              postBuild = ''
                # As shown in
                # https://github.com/code-supply/nix-phoenix/blob/2ab9b2f63dd85d5d6a85d61bd4fc5c6d07f65643/flake-template/flake.nix#L62-L64
                ln -sfv ${mixNixDeps.heroicons} deps/heroicons

                mix do \
                  loadpaths --no-deps-check + \
                  assets.deploy --no-deps-check
              '';

              meta.mainProgram = "server";
            };

          default = beacon_live_admin;
        }
      );
    };
}
