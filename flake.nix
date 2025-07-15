{
  description = "Rotki - A privacy-focused crypto portfolio management and tax reporting application";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        # Python dependencies
        python = pkgs.python311;
        pythonPackages = python.pkgs;

        # Rust toolchain
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rustfmt" "clippy" ];
        };

        # Node.js and pnpm
        nodejs = pkgs.nodejs_22;
        pnpm = pkgs.pnpm;

        # Python backend derivation
        rotkehlchen-backend = pythonPackages.buildPythonPackage rec {
          pname = "rotkehlchen";
          version = "1.39.1";
          
          src = ./.;
          
          format = "pyproject";
          
          nativeBuildInputs = with pythonPackages; [
            setuptools
            setuptools-scm
            wheel
          ];
          
          propagatedBuildInputs = with pythonPackages; [
            gevent
            greenlet
            gevent-websocket
            web3
            eth-account
            eth-typing
            requests
            urllib3
            coincurve
            jsonschema
            beautifulsoup4
            cryptography
            flask
            flask-cors
            marshmallow
            webargs
            werkzeug
            packaging
            pyjwt
            google-api-python-client
            google-auth
            polars
            # Add other dependencies as needed
          ];
          
          buildInputs = with pkgs; [
            sqlite
            openssl
            libffi
          ];
          
          # Skip tests during build
          doCheck = false;
          
          meta = with pkgs.lib; {
            description = "Accounting, asset management and tax report helper for cryptocurrencies";
            homepage = "https://rotki.com";
            license = licenses.agpl3Only;
            maintainers = [ ];
          };
        };

        # Rust Colibri service derivation
        colibri = pkgs.rustPlatform.buildRustPackage rec {
          pname = "colibri";
          version = "0.1.0";
          
          src = ./colibri;
          
          cargoLock = {
            lockFile = ./colibri/Cargo.lock;
          };
          
          nativeBuildInputs = with pkgs; [
            pkg-config
            rustToolchain
          ];
          
          buildInputs = with pkgs; [
            openssl
            sqlite
          ];
          
          # Environment variables for build
          OPENSSL_NO_VENDOR = 1;
          
          meta = with pkgs.lib; {
            description = "Colibri - Performance-critical Rust service for Rotki";
            license = licenses.agpl3Only;
            maintainers = [ ];
          };
        };

        # Frontend derivation
        rotki-frontend = pkgs.stdenv.mkDerivation rec {
          pname = "rotki-frontend";
          version = "1.39.1";
          
          src = ./frontend;
          
          nativeBuildInputs = with pkgs; [
            nodejs
            pnpm
            python3
          ];
          
          buildInputs = with pkgs; [
            # Required for node-gyp and native dependencies
            pkg-config
            cairo
            pango
            libpng
            libjpeg
            giflib
            librsvg
            pixman
          ];
          
          configurePhase = ''
            export HOME=$TMPDIR
            export PNPM_HOME=$TMPDIR/.pnpm
            export PATH=$PNPM_HOME:$PATH
            
            # Install dependencies
            pnpm install --frozen-lockfile
          '';
          
          buildPhase = ''
            cd app
            pnpm run build
          '';
          
          installPhase = ''
            mkdir -p $out
            cp -r app/dist/* $out/
          '';
          
          meta = with pkgs.lib; {
            description = "Rotki frontend - Vue.js/TypeScript Electron application";
            license = licenses.agpl3Only;
            maintainers = [ ];
          };
        };

        # Complete Rotki package
        rotki = pkgs.stdenv.mkDerivation rec {
          pname = "rotki";
          version = "1.39.1";
          
          src = ./.;
          
          buildInputs = [
            rotkehlchen-backend
            colibri
            rotki-frontend
          ];
          
          installPhase = ''
            mkdir -p $out/bin
            mkdir -p $out/lib/rotki
            
            # Install backend
            cp -r ${rotkehlchen-backend}/lib/python*/site-packages/rotkehlchen $out/lib/rotki/
            
            # Install colibri service
            cp ${colibri}/bin/colibri $out/bin/
            
            # Install frontend
            cp -r ${rotki-frontend}/* $out/lib/rotki/frontend/
            
            # Create wrapper script
            cat > $out/bin/rotki << 'EOF'
            #!/bin/bash
            export PYTHONPATH="$out/lib/rotki:$PYTHONPATH"
            exec ${python}/bin/python -m rotkehlchen "$@"
            EOF
            chmod +x $out/bin/rotki
          '';
          
          meta = with pkgs.lib; {
            description = "A privacy-focused crypto portfolio management and tax reporting application";
            homepage = "https://rotki.com";
            license = licenses.agpl3Only;
            maintainers = [ ];
            platforms = platforms.linux ++ platforms.darwin;
          };
        };

      in
      {
        packages = {
          default = rotki;
          rotki = rotki;
          rotkehlchen-backend = rotkehlchen-backend;
          colibri = colibri;
          rotki-frontend = rotki-frontend;
        };

        apps = {
          default = flake-utils.lib.mkApp {
            drv = rotki;
            exePath = "/bin/rotki";
          };
          
          rotki = flake-utils.lib.mkApp {
            drv = rotki;
            exePath = "/bin/rotki";
          };
          
          colibri = flake-utils.lib.mkApp {
            drv = colibri;
            exePath = "/bin/colibri";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Python development
            python
            pythonPackages.pip
            pythonPackages.setuptools
            pythonPackages.wheel
            uv
            
            # Rust development
            rustToolchain
            cargo
            
            # Node.js development
            nodejs
            pnpm
            
            # System dependencies
            sqlite
            openssl
            libffi
            pkg-config
            
            # Development tools
            git
            gnumake
            
            # Frontend build dependencies
            cairo
            pango
            libpng
            libjpeg
            giflib
            librsvg
            pixman
            
            # Optional: Electron for desktop development
            electron
          ];
          
          shellHook = ''
            echo "🚀 Rotki development environment"
            echo "📦 Python: $(python --version)"
            echo "🦀 Rust: $(rustc --version)"
            echo "📟 Node.js: $(node --version)"
            echo "📦 pnpm: $(pnpm --version)"
            echo ""
            echo "Available commands:"
            echo "  pnpm dev          - Start full development environment"
            echo "  pnpm dev:web      - Start web-only development"
            echo "  uv run python pytestgeventwrapper.py - Run backend tests"
            echo "  cd frontend && pnpm run test:unit - Run frontend tests"
            echo "  cd colibri && cargo build - Build Colibri service"
            echo ""
            echo "For more commands, see CLAUDE.md"
          '';
          
          # Environment variables
          PYTHONPATH = "${toString ./.}:$PYTHONPATH";
          RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/src";
          
          # Required for some Python packages
          LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath (with pkgs; [ 
            openssl
            sqlite
            libffi
            stdenv.cc.cc
          ])}:$LD_LIBRARY_PATH";
        };
      }
    );
}