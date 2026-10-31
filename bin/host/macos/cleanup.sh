#!/bin/bash

brew uninstall --force krunkit
brew uninstall --force libkrun
brew uninstall --force libkrunfw
brew uninstall --force virglrenderer

brew uninstall --ignore-dependencies virglrenderer

brew untap libkrun/krun
brew untap slp/krun

brew untrust libkrun/krun
brew untrust slp/krun

brew cleanup -s
brew autoremove
