#!/usr/bin/env bash
# Removes the tools installed for recording AeroControl's demos, and nothing else.
# swiftly and its Swift toolchain stay: building the AeroSpace fork needs them.
set -u

brew uninstall --cask keycastr kap
brew uninstall gifski cmatrix cbonsai pipes-sh asciiquarium tty-clock figlet lolcat
# lolcat's dependencies, installed with it; brew refuses if anything else still needs them
brew uninstall ruby libyaml
