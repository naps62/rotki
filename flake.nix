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

        # Python with required version
        python = pkgs.python311;
        
        # Rust toolchain
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rustfmt" "clippy" ];
        };

        # Python environment with available dependencies
        rotki-python-env = python.withPackages (ps: with ps; [
          # Core dependencies available in nixpkgs
          gevent
          greenlet
          requests
          urllib3
          jsonschema
          beautifulsoup4
          cryptography
          flask
          flask-cors
          marshmallow
          werkzeug
          packaging
          pyjwt
          google-api-python-client
          google-auth
          setuptools
          setuptools-scm
          wheel
          pip
          # Ethereum/crypto dependencies
          eth-utils
          eth-abi
          eth-account
          eth-typing
          coincurve
          # Additional required dependencies
          more-itertools
          regex
          filetype
          maxminddb
          # Development tools
          pytest
          mypy
          pylint
        ]);

        # Colibri Rust service
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
          
          OPENSSL_NO_VENDOR = 1;
          
          # Skip tests during build
          doCheck = false;
          
          meta = with pkgs.lib; {
            description = "Colibri - Performance-critical Rust service for Rotki";
            homepage = "https://rotki.com";
            license = licenses.agpl3Only;
          };
        };

        # Frontend Electron app
        rotki-electron = pkgs.stdenv.mkDerivation rec {
          pname = "rotki-electron";
          version = "1.39.1";
          
          src = ./frontend/app;
          
          nativeBuildInputs = with pkgs; [
            nodejs_22
            pnpm
            python3
            pkg-config
            makeWrapper
          ];
          
          buildInputs = with pkgs; [
            cairo
            pango
            libpng
            libjpeg
            giflib
            librsvg
            pixman
            electron
          ];
          
          buildPhase = ''
            export HOME=$TMPDIR
            export npm_config_cache=$TMPDIR/.npm
            export ELECTRON_CACHE=$TMPDIR/.electron
            export ELECTRON_BUILDER_CACHE=$TMPDIR/.electron-builder
            
            # Install dependencies
            cd ..
            pnpm install --frozen-lockfile
            
            # Build the app
            cd app
            pnpm run build
            
            # Create a simple electron wrapper
            mkdir -p electron-dist
            cp -r dist electron-dist/
            
            # Create package.json for electron
            cat > electron-dist/package.json << 'EOF'
            {
              "name": "rotki",
              "version": "1.39.1",
              "main": "main.js",
              "scripts": {
                "start": "electron ."
              }
            }
            EOF
            
            # Create main.js for electron
            cat > electron-dist/main.js << 'EOF'
            const { app, BrowserWindow } = require('electron');
            const path = require('path');
            
            function createWindow() {
              const win = new BrowserWindow({
                width: 1200,
                height: 800,
                webPreferences: {
                  nodeIntegration: true,
                  contextIsolation: false
                }
              });
              
              win.loadFile('dist/index.html');
            }
            
            app.whenReady().then(createWindow);
            
            app.on('window-all-closed', () => {
              if (process.platform !== 'darwin') {
                app.quit();
              }
            });
            
            app.on('activate', () => {
              if (BrowserWindow.getAllWindows().length === 0) {
                createWindow();
              }
            });
            EOF
          '';
          
          installPhase = ''
            mkdir -p $out/lib/rotki-electron
            cp -r electron-dist/* $out/lib/rotki-electron/
            
            # Create wrapper script
            mkdir -p $out/bin
            makeWrapper ${pkgs.electron}/bin/electron $out/bin/rotki \
              --add-flags "$out/lib/rotki-electron" \
              --set ELECTRON_IS_DEV 0
          '';
          
          meta = with pkgs.lib; {
            description = "Rotki Electron desktop application";
            homepage = "https://rotki.com";
            license = licenses.agpl3Only;
            platforms = platforms.linux ++ platforms.darwin;
          };
        };

        # Main Rotki package - combines backend, frontend, and Colibri
        rotki = pkgs.writeShellScriptBin "rotki" ''
          set -e
          
          # Check if we're in the right directory for development mode
          if [ -f "rotkehlchen/__main__.py" ]; then
            echo "🔧 Development mode detected"
            
            # Set up environment
            export PYTHONPATH="${toString ./.}:$PYTHONPATH"
            export PATH="${pkgs.lib.makeBinPath [ colibri pkgs.uv ]}:$PATH"
            
            # Check if .venv exists and create/sync if needed
            if [ ! -d ".venv" ]; then
              echo "🔧 Setting up Python virtual environment..."
              ${pkgs.uv}/bin/uv venv --python ${rotki-python-env}/bin/python
            fi
            
            # Always sync dependencies to ensure they're up to date
            echo "📦 Installing/updating Python dependencies..."
            ${pkgs.uv}/bin/uv sync --frozen
            
            echo "🚀 Starting Rotki in development mode..."
            echo "   Use 'cd frontend && pnpm dev' for the full app"
            echo "   Backend: .venv/bin/python"
            echo "   Colibri: ${colibri}/bin/colibri"
            echo ""
            
            # Run rotki backend
            exec .venv/bin/python -m rotkehlchen "$@"
          else
            echo "🚀 Starting Rotki Electron App..."
            echo "   Colibri: ${colibri}/bin/colibri"
            echo ""
            
            # Start Colibri in background
            ${colibri}/bin/colibri --database ~/.rotki/global.db --port 4343 &
            COLIBRI_PID=$!
            
            # Cleanup function
            cleanup() {
              echo "Shutting down Colibri..."
              kill $COLIBRI_PID 2>/dev/null || true
            }
            trap cleanup EXIT
            
            # Run the Electron app
            exec ${rotki-electron}/bin/rotki "$@"
          fi
        '';

        # Development shell
        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            rotki-python-env
            uv
            rustToolchain
            cargo
            nodejs_22
            pnpm
            sqlite
            openssl
            libffi
            pkg-config
            git
            gnumake
            cairo
            pango
            libpng
            libjpeg
            giflib
            librsvg
            pixman
            electron
            gcc
            glibc
            colibri
          ];
          
          shellHook = ''
            echo "🚀 Welcome to Rotki development environment!"
            echo ""
            echo "📦 Available tools:"
            echo "  Python: $(python --version)"
            echo "  UV: $(uv --version)"
            echo "  Rust: $(rustc --version)"
            echo "  Node.js: $(node --version)"
            echo "  pnpm: $(pnpm --version)"
            echo "  Colibri: ${colibri}/bin/colibri"
            echo ""
            echo "🛠️  Quick start:"
            echo "  nix run                     - Run Rotki (after installing deps)"
            echo "  uv sync                     - Install Python dependencies"
            echo "  pnpm install                - Install frontend dependencies"
            echo "  pnpm dev                    - Start full development environment"
            echo "  cd colibri && cargo build   - Build Colibri service"
            echo ""
            echo "📚 More commands in CLAUDE.md"
            echo ""
            
            # Set up environment variables
            export PYTHONPATH="${toString ./.}:$PYTHONPATH"
            export RUST_SRC_PATH="${rustToolchain}/lib/rustlib/src/rust/src"
            export PATH="${colibri}/bin:$PATH"
            
            # Library paths for native dependencies
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath (with pkgs; [ 
              openssl sqlite libffi stdenv.cc.cc cairo pango libpng libjpeg giflib librsvg pixman
            ])}:$LD_LIBRARY_PATH"
            
            # PKG_CONFIG_PATH for native modules
            export PKG_CONFIG_PATH="${pkgs.lib.makeSearchPathOutput "dev" "lib/pkgconfig" (with pkgs; [
              cairo pango libpng libjpeg giflib librsvg pixman openssl sqlite libffi
            ])}:$PKG_CONFIG_PATH"
            
            echo "✅ Environment ready! Try 'nix run' to start Rotki"
          '';
        };

      in
      {
        packages = {
          default = rotki;
          rotki = rotki;
          rotki-electron = rotki-electron;
          colibri = colibri;
        };

        apps = {
          default = flake-utils.lib.mkApp {
            drv = rotki;
          };
          
          rotki = flake-utils.lib.mkApp {
            drv = rotki;
          };
          
          colibri = flake-utils.lib.mkApp {
            drv = colibri;
            exePath = "/bin/colibri";
          };
        };

        devShells.default = devShell;
      }
    );
}