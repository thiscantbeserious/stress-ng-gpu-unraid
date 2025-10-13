#!/bin/sh
# Create or refresh a symlink so users can just run "stress-ng"
mkdir -p /usr/local/bin
ln -sfn /opt/stress-ng-gpu/stress-ng /usr/local/bin/stress-ng
