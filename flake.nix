{
  description = "My environment for OPLSS 2023";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let supportedSystems = [
      "aarch64-linux"
      "i686-linux"
      "x86_64-linux"
    ]; in
    flake-utils.lib.eachSystem supportedSystems (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
 #           (
 #             hself: hsuper: {
 # mkDerivation = args: hsuper.mkDerivation (args // {
 #   doCheck = false;
 # });
#}
#            )
          ];
          config = { allowUnfree = true; };
        };
#        stack-wrapped = pkgs.symlinkJoin {
#          name = "stack"; # will be available as the usual `stack` in terminal
#          paths = [ pkgs.stack ];
#          buildInputs = [ pkgs.makeWrapper ];
#          postBuild = ''
#            wrapProgram $out/bin/stack \
#              --add-flags "\
#                --no-nix \
#                --system-ghc \
#                --no-install-ghc \
#              "
#          '';
#        };
        devTools = with pkgs; [
#          stack-wrapped
          haskell.packages.ghc927.cabal-install
            haskell.packages.ghc927.ghc
            haskell.packages.ghc927.ghcid
            haskell.packages.ghc927.haskell-language-server
            zlib
            coq
            coqPackages.coqide
            compcert
        ];
      in
      {
        devShell = pkgs.mkShell {
          buildInputs = devTools;
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath devTools;
        };
      });
}
