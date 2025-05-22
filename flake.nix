# flake.nix
{
  description = "My CI tools wrapped in a Nix Flake";

  inputs = {
    nixpkgs.url = "github:nixOS/nixpkgs/nixos-unstable";

    systems.url = "github:vpayno/nix-systems-default";

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };

    treefmt-conf = {
      url = "github:vpayno/nix-treefmt-conf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      treefmt-conf,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pname = "nix-ci-tools";
        version = "20250521.0.0";
        name = "${pname}-${version}";

        pkgs = nixpkgs.legacyPackages.${system};

        usageMessage = ''
          Available ${name} flake commands:

            nix run .#usage
        '';

        metadata = {
          homepage = "https://github.com/vpayno/nix-ci-tools";
          description = "My CI tools wrapped in a Nix Flake";
          license = with pkgs.lib.licenses; [ mit ];
          # maintainers = with pkgs.lib.maintainers; [vpayno];
          maintainers = [
            {
              email = "vpayno@users.noreply.github.com";
              github = "vpayno";
              githubId = 3181575;
              name = "Victor Payno";
            }
          ];
          mainProgram = "showUsage";
        };
      in
      {
        formatter = treefmt-conf.formatter.${system};

        packages = rec {
          default = showUsage;

          # very odd, this doesn't work with pkgs.writeShellApplication
          # odd quoting error when the string usagemessage as new lines
          showUsage = pkgs.writeShellScriptBin "showUsage" ''
            printf "%s" "${usageMessage}"
          '';
        };

        apps = rec {
          default = usage;

          usage = {
            type = "app";
            pname = "usage";
            inherit version;
            name = "${pname}-${version}";
            program = "${pkgs.lib.getExe self.packages.${system}.showUsage}";
            meta = metadata;
          };
        };
      }
    );
}
