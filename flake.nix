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

            nix run .#usage | .#default

            nix run .#mdlint-run
            nix run .#mdlint-help

            nix develop .#default
            nix develop .#ci-markdown
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

        configMarkdownLint = pkgs.writeTextFile {
          name = ".markdownlintrc";
          text = builtins.readFile ./.markdownlintrc;
        };

        ci-help-markdownlint-cli = pkgs.writeShellApplication {
          name = "ci-help-markdownlint-cli";
          text = ''
            printf "CI Markdown Usaage\n"
            printf "\n"
            printf "Available Scripts:\n"
            printf "\tci-help-markdownlint-cli\n"
            printf "\tci-run-markdownlint-cli\n"
            printf "\tci-run-markdownlint-cli-with-reviewdog\n"
            printf "\n"
            printf "Config: %s\n" "${configMarkdownLint}"
            printf "\n"
            printf "Variables:\n"
            printf "\tMARKDOWNCLI_IGNORE=(\"--ignore\" \"./dirname\")\n"
            printf "\tMARKDOWNCLI_FLAGS=(\".\")\n"
            printf "\tREVIEWDOG_REPORT_LEVEL=\"error\" # info warning\n"
            printf "\tREVIEWDOG_REPORTER=\"github-pr-check\" # github-check github-pr-review github-pr-annotations\n"
            printf "\tREVIEWDOG_FAIL_LEVEL=\"any\" # error\n"
            printf "\n"
            printf "Versions:\n"
            printf "\treviewdog version: "
            reviewdog --version
            printf "\tmarkdownlint-cli version: "
            markdownlint --version
            printf "\n"
          '';
        };

        ci-run-markdownlint-cli = pkgs.writeShellApplication {
          name = "ci-run-markdownlint-cli";
          text = ''
            # CHANGELOG.md:5:1 MD033/no-inline-html Inline HTML [Element: h2]
            # CHANGELOG.md:9 MD001/heading-increment/header-increment Heading levels should only increment by one level at a time [Expected: h2; Actual: h3]

            if [[ -z ''${MARKDOWNCLI_IGNORE:-} ]]; then
              export MARKDOWNCLI_IGNORE=("--ignore" "./pages-gh")
            fi
            if [[ -z ''${MARKDOWNCLI_FLAGS:-} ]]; then
              export MARKDOWNCLI_FLAGS=(".")
            fi

            ${pkgs.lib.getExe pkgs.markdownlint-cli} --config="${configMarkdownLint}" "''${MARKDOWNCLI_IGNORE[@]:-}" "''${MARKDOWNCLI_FLAGS[@]}" "''${@}"
          '';
        };

        ci-run-markdownlint-cli-with-reviewdog = pkgs.writeShellApplication {
          name = "ci-run-markdownlint-cli-with-reviewdog";
          text = ''
            printf "Running %s ci linter...\n" "markdownlint-cli"
            printf "\n"

            ${pkgs.lib.getExe ci-run-markdownlint-cli} |
              ${pkgs.lib.getExe pkgs.gnused} -r -e 's/^(.*[.]md:[0-9]+) (.*)$/\1:1 \2/g' |
                ${pkgs.lib.getExe pkgs.reviewdog} -tee -efm="%f:%l:%c: %m" -name="markdownlint" \
                -level="''${REVIEWDOG_REPORT_LEVEL:-error}" \
                -reporter="''${REVIEWDOG_REPORTER:-github-pr-check}" \
                -fail-level="''${REVIEWDOG_FAIL_LEVEL:-any}"

            printf "Done\n"
          '';
        };

        ciMarkdownScripts = [
          ci-help-markdownlint-cli
          ci-run-markdownlint-cli
          ci-run-markdownlint-cli-with-reviewdog
        ];

        # note: don't know if I want to use this
        ciEnvMarkdown = pkgs.buildEnv {
          name = "${name}-ci-markdown-env";
          paths = [
            ciMarkdownScripts
            (pkgs.runCommand "config" { } ''
              mkdir -pv $out/etc/markdownlint
              cp -v ${configMarkdownLint} $out/etc/markdownlint/config.json
            '')
          ];
          buildInputs = with pkgs; [
            makeWrapper
          ];
          postBuild = ''
            extra_bin_paths="${pkgs.lib.makeBinPath ciMarkdownScripts}"
            printf "Adding extra bin paths to wrapper scripts: %s\n" "$extra_bin_paths"
            printf "\n"

            for p in "$out"/bin/*; do
              if [[ ! -x $p ]]; then
                continue
              fi
              echo wrapProgram "$p" --set PATH "$extra_bin_paths"
              wrapProgram "$p" --set PATH "$extra_bin_paths"
            done
          '';
        };

        ciScripts = ciMarkdownScripts;
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

          mdlint-help = {
            type = "app";
            pname = "mdlint-help";
            inherit version;
            name = "${pname}-${version}";
            program = "${pkgs.lib.getExe ci-help-markdownlint-cli}";
            meta = metadata // {
              description = "Markdown Lint CLI Wrapper Usage";
            };
          };

          mdlint-run = {
            type = "app";
            pname = "mdlint-run";
            inherit version;
            name = "${pname}-${version}";
            program = "${pkgs.lib.getExe ci-run-markdownlint-cli}";
            meta = metadata // {
              description = "Markdown Lint CLI Wrapper Tool";
            };
          };
        };

        devShells = {
          default = pkgs.mkShell rec {
            packages =
              with pkgs;
              [
                bashInteractive
              ]
              ++ ciScripts;

            shellMotd = ''
              Starting ${name}

              nix develop .#default shell...
            '';

            shellHook = ''
              ${pkgs.lib.getExe pkgs.cowsay} "${shellMotd}"
            '';
          };

          ci-test = pkgs.mkShell {
            buildInputs = with pkgs; [
              bashInteractive
            ];
            shellHook = ''
              ${pkgs.lib.getExe pkgs.cowsay} "Welcome to .#ci-test devShell!"
              printf "\n"
            '';
          };

          ci-markdown = pkgs.mkShell {
            buildInputs =
              with pkgs;
              [
                markdownlint-cli
                reviewdog
              ]
              ++ ciMarkdownScripts;
            shellHook = ''
              ${pkgs.lib.getExe pkgs.cowsay} "Welcome to .#ci-markdown devShell!"
              printf "\n"

              ci-help-markdownlint-cli

              export MARKDOWNCLI_IGNORE=("--ignore" "./pages-gh")
              export MARKDOWNCLI_FLAGS=(".")

              export REVIEWDOG_REPORT_LEVEL="error" # info warning error
              export REVIEWDOG_REPORTER="github-check" # github-check github-pr-check github-pr-review github-pr-annotations
              export REVIEWDOG_FAIL_LEVEL="any" # any error
            '';
          };
        };
      }
    );
}
