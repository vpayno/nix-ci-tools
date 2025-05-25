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

        flake_repo_url = "github:vpayno/nix-ci-tools";

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

        # very odd, this doesn't work with pkgs.writeShellApplication
        # odd quoting error when the string usagemessage as new lines
        showUsage = pkgs.writeShellScriptBin "showUsage" ''
          printf "%s" "${usageMessage}"
        '';

        configMarkdownLint = pkgs.writeTextFile {
          name = ".markdownlintrc";
          text = builtins.readFile ./.markdownlintrc;
        };

        configMarkdownGitHubWorkflow = pkgs.writeTextFile {
          name = ".github/workflows/markdown.yaml";
          text = builtins.readFile ./.github/workflows/markdown.yaml;
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
            printf "\tgh-wf-setup-mdlint\n"
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
            ${pkgs.lib.getExe pkgs.reviewdog} --version
            printf "\tmarkdownlint-cli version: "
            ${pkgs.lib.getExe pkgs.markdownlint-cli} --version
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

        gh-wf-setup-mdlint = pkgs.writeShellApplication {
          name = "gh-wf-setup-mdlint";
          text = ''
            printf "Running %s GitHub CI workflow CLI...\n" "gh-wf-setup-mdlint"
            printf "\n"

            declare gh_wf_dir=".github/workflows"
            declare target_name
            declare repo_url
            repo_url="$(git remote get-url origin --push | sed -r -e 's|:|/|g; s|git@|https://|g; s/[.]git$//g')"
            declare banner_line="[![Markdown Checks]($repo_url/actions/workflows/markdown.yaml/badge.svg?branch=main)]($repo_url/actions/workflows/markdown.yaml)"

            target_name="$(basename "${configMarkdownGitHubWorkflow}")"
            target_name="''${target_name##*-}"

            if [[ ! -e $gh_wf_dir ]]; then
              printf "ERROR: directory, %s, doesn't exist." "$gh_wf_dir"
              mkdir -pv "$gh_wf_dir"
              printf "\n"
            fi

            if [[ ! -d $gh_wf_dir ]]; then
              printf "ERROR: directory, %s, isn't a directory." "$gh_wf_dir"
              printf "\n"
              exit 1
            fi

            if [[ ! -w $gh_wf_dir ]]; then
              printf "ERROR: directory, %s, isn't writeable." "$gh_wf_dir"
              printf "\n"
              exit 1
            fi

            printf "GitHub Workflow Target: %s\n" "$gh_wf_dir"/"$target_name"
            printf "GitHub README.md Target: %s\n" ./README.md
            printf "\n"

            cp -v "${configMarkdownGitHubWorkflow}" "$gh_wf_dir"/"$target_name"
            chmod -v u+w "$gh_wf_dir"/"$target_name"
            sed -r -i -e 's;CI_TOOL_REPO: ".";CI_TOOL_REPO: '"\"${flake_repo_url}\""';g' "$gh_wf_dir"/"$target_name"

            # add new workflow status badge to line 3 of the README file
            printf "Add GitHub workflow banner entry to %s...\n" "./README.md"
            sed -i -e "3i $banner_line" ./README.md
            printf "\n"

            git status "$gh_wf_dir"/"$target_name" ./README.md
            printf "\n"

            printf "Done\n"
          '';
        };

        ciMarkdownScripts = [
          ci-help-markdownlint-cli
          ci-run-markdownlint-cli
          ci-run-markdownlint-cli-with-reviewdog
          gh-wf-setup-mdlint
        ];

        ciConfigs = [
          configMarkdownLint
        ];

        ciScripts = ciMarkdownScripts;

        ciBundle = pkgs.buildEnv {
          name = "${name}-bundle";
          paths = [
            (pkgs.runCommand "${name}-scripts" { } ''
              mkdir -pv $out/bin
              for f in "${ci-run-markdownlint-cli}"/bin/* "${ci-run-markdownlint-cli-with-reviewdog}"/bin/* "${ci-help-markdownlint-cli}"/bin/* "${gh-wf-setup-mdlint}"/bin/*; do
                cp -v "$f" $out/bin/
              done
              ${pkgs.lib.getExe pkgs.tree} $out
            '')
            (pkgs.runCommand "${name}-config" { } ''
              mkdir -pv $out/etc/markdownlint
              cp -v ${configMarkdownLint} $out/etc/markdownlint/config.json
              ${pkgs.lib.getExe pkgs.tree} $out
            '')
          ];
          buildInputs = with pkgs; [
            makeWrapper
          ];
          pathsToLink = [
            "/bin"
            "/etc"
          ];
          postBuild = ''
            extra_bin_paths="${pkgs.lib.makeBinPath ciScripts}"
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
      in
      {
        formatter = treefmt-conf.formatter.${system};

        packages = rec {
          default = ciBundle;
        };

        apps = rec {
          default = usage;

          usage = {
            type = "app";
            pname = "usage";
            inherit version;
            name = "${pname}-${version}";
            program = "${pkgs.lib.getExe showUsage}";
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
            program = "${pkgs.lib.getexe ci-run-markdownlint-cli}";
            meta = metadata // {
              description = "markdown lint cli wrapper tool";
            };
          };

          gh-wf-setup-mdlint = {
            type = "app";
            pname = "gh-wf-setup-mdlint";
            inherit version;
            name = "${pname}-${version}";
            program = "${pkgs.lib.getexe gh-wf-setup-mdlint}";
            meta = metadata // {
              description = "GitHub CI Workflow Cli";
            };
          };

          ci-gh-help = {
            type = "app";
            pname = "ci-gh-help";
            inherit version;
            name = "${pname}-${version}";
            program = "${pkgs.lib.getExe ci-gh-help}";
            meta = metadata // {
              description = "CI Tools GH Usage";
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
