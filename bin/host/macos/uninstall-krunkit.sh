#!/bin/bash

brew uninstall --ignore-dependencies virglrenderer

brew uninstall --force krunkit
brew uninstall --force libkrun
brew uninstall --force libkrunfw
brew uninstall --force virglrenderer

brew untap slp/krun
brew untrust slp/krun

brew cleanup -s
brew autoremove