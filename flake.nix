{
  description = "rotki project with uv-managed virtualenv";

  inputs = {
    nixpkgs.url          = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url      = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        unstable = nixpkgs-unstable.legacyPackages.${system};

        python311         = pkgs.python311;
        nodejsWithPython  = pkgs.nodejs_22.override { python3 = python311; };
        nodePackages      = pkgs.nodePackages.override { nodejs = nodejsWithPython; };
        pnpmWithPython311 = unstable.pnpm;

          buildInputs = [
            pkgs.gcc
            pkgs.stdenv.cc.cc.lib
            pkgs.bash
            pkgs.git
            pkgs.lzma
            pnpmWithPython311
            python311   # interpreter uv will bind into the venv
            pkgs.uv     # blazing-fast venv + installer
          ];

        devShell = pkgs.mkShell {
          name = "rotki-dev";
          inherit buildInputs;

          shellHook = ''
            # Installs deps and auto-creates .venv if missing
            uv sync

            # Install frontend dependencies
            cd frontend
            pnpm install
            cd ..
          '';
        };
      in { inherit devShell; });
}
