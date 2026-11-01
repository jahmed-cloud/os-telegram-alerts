#!/bin/sh
# Dashboard widgets must not use ES module imports. On OPNsense 26.7 the base
# classes (BaseTableWidget, BaseWidget, ...) are globals with no exports, so one
# import line fails the module load and blanks the whole dashboard grid.
#   sh tests/check-widgets.sh
cd "$(dirname "$0")/.."
DIR=src/opnsense/www/js/widgets

ls "$DIR"/*.js >/dev/null 2>&1 || { echo "FAIL: no widget files in $DIR"; exit 1; }
if grep -nE '^[[:space:]]*import[[:space:]({*"'"'"']' "$DIR"/*.js; then
    echo "FAIL: widget JS must not import; the base classes are globals"
    exit 1
fi
echo "OK: no import lines in $DIR"
