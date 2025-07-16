{
  description = "rotki project with uv-managed virtualenv";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust.url = "github:oxalica/rust-overlay";
    utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      utils,
      rust,
    }:
    utils.lib.eachDefaultSystem (
      system:

      let
        overlays = [ (import rust) ];
        pkgs = import nixpkgs { inherit system overlays; };

        # nodejs = pkgs.nodejs_22;
        # python = pkgs.python311.override { nodejs = pkgs.nodejs_22;};
        # nodejsWithPython = pkgs.nodejs_22.override { python3 = python311; };
        # nodePackages = pkgs.nodePackages.override { nodejs = nodejsWithPython; };
        # pnpmWithPython311 = pkgs.pnpm;

        commonDeps = with pkgs; [
          gcc
          stdenv.cc.cc.lib
          bash
          git
          xz
          python311
          nodejs_22
          pnpm
          uv
        ];

        buildDeps = [ ];

        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" ];
        };
        rustPlatform = pkgs.makeRustPlatform {
          cargo = rustToolchain;
          rustc = rustToolchain;
        };

        # build colibri crate
        colibri = rustPlatform.buildRustPackage (finalAttrs: {
          pname = "colibri";
          version = "0.1.0";

          src = ./colibri;

          # tests currently try to create a database on a parent dir
          # I can't seem to get around this, previously tried with:
          #   src = ./.
          #   cargoRoot = "./colibri";
          # in order to mount the whole repo, but this was running into issues I couldn't figure out
          doCheck = false;

          buildInputs = with pkgs; [ openssl ];
          nativeBuildInputs = with pkgs; [
            pkg-config
            perl
          ];

          cargoDeps = rustPlatform.fetchCargoVendor {
            inherit (finalAttrs)
              pname
              version
              src
              ;
            hash = "sha256-CktDDoDkuJYKyTtNWTQPSz2Dpi8HeQZ11blZqjU6P40=";
          };

          patchPhase = '''';

          installPhase = ''
            mkdir -p $out/bin
            cp -r /build/colibri $out/bin
          '';
        });

      in
      {
        packages.default = colibri;

        devShells.default = pkgs.mkShell {
          name = "rotki-dev";
          buildInputs = commonDeps;
        };
      }
    );
}
