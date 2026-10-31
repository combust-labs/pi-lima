#!/usr/bin/env bash
set -euo pipefail

# Official krunkit/libkrun Homebrew tap.
brew tap slp/krun

# Installs krunkit and its libkrun dependencies.
brew trust --formula slp/krun/libkrun
brew trust --formula slp/krun/krunkit
brew trust --formula slp/krun/gvproxy
brew trust --formula slp/krun/libkrunfw
brew trust --formula slp/krun/virglrenderer

brew install krunkit

krunkit --version