{
  description = "Rotki - A privacy-focused crypto portfolio management and tax reporting application";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        
        # Python with required version
        python = pkgs.python311;

        # Main Rotki production package
        rotki = pkgs.stdenv.mkDerivation rec {
          pname = "rotki";
          version = "1.39.1";
          
          src = ./.;
          
          nativeBuildInputs = with pkgs; [
            python
            uv
            makeWrapper
          ];
          
          buildInputs = with pkgs; [
            sqlite
            openssl
            libffi
          ];
          
          buildPhase = ''
            # Set up Python environment using uv
            export UV_PYTHON=${python}/bin/python
            export HOME=$(mktemp -d)
            
            # Install dependencies with uv
            ${pkgs.uv}/bin/uv sync --frozen
            
            # Compile Python bytecode for better performance
            .venv/bin/python -m compileall rotkehlchen/
          '';
          
          installPhase = ''
            mkdir -p $out/lib/rotki
            cp -r rotkehlchen $out/lib/rotki/
            cp -r .venv $out/lib/rotki/
            
            # Create wrapper script
            mkdir -p $out/bin
            makeWrapper $out/lib/rotki/.venv/bin/python $out/bin/rotki \
              --add-flags "-m rotkehlchen" \
              --set PYTHONPATH "$out/lib/rotki:$PYTHONPATH" \
              --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath [ pkgs.sqlite pkgs.openssl pkgs.libffi ]}"
          '';
          
          meta = with pkgs.lib; {
            description = "Rotki - A privacy-focused crypto portfolio management and tax reporting application";
            homepage = "https://rotki.com";
            license = licenses.agpl3Only;
            platforms = platforms.linux ++ platforms.darwin;
          };
        };

      in
      {
        packages = {
          default = rotki;
          rotki = rotki;
        };

        apps = {
          default = flake-utils.lib.mkApp {
            drv = rotki;
          };
          
          rotki = flake-utils.lib.mkApp {
            drv = rotki;
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            python
            uv
            sqlite
            openssl
            libffi
          ];
          
          shellHook = ''
            echo "🚀 Rotki production environment ready!"
            echo "Available commands:"
            echo "  nix run - Run Rotki backend"
            echo "  uv sync - Install dependencies"
            echo "  uv run python -m rotkehlchen - Direct execution"
          '';
        };
      }
    );
}