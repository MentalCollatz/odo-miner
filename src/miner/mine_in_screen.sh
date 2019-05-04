#!/bin/bash

# Start a screen session with one window per detected mining device

# Copyright (C) 2019 MentalCollatz
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

cd "$( dirname "${BASH_SOURCE[0]}" )"

if [ $# -gt 1 ]
then
    echo "usage: $0 [screen_name]" 1>&2
    exit 1
fi

if [ -z "$QUARTUSPATH" ]
then
    JTAGCONFIG=$(which jtagconfig)
    if [ -z "$JTAGCONFIG" ]
    then
        echo 'Error: could not locate jtagconfig, please set $QUARTUSPATH' 1>&2
        exit 1
    fi
else
    JTAGCONFIG="$QUARTUSPATH/jtagconfig"
fi

# make sure screen is installed
if ! hash screen 2>/dev/null
then
    echo "You must install 'screen' before using this script" >&2
    if hash command_not_found_handle 2>/dev/null
    then
        command_not_found_handle screen
    fi
    exit 1
fi

SCREEN=miners
if [ $# -eq 1 ]
then
    SCREEN="$1"
fi

if screen -S "$SCREEN" -X select . >/dev/null
then
    echo "Error: screen '$SCREEN' already exists." 1>&2
    exit 1
fi
screen -dmS "$SCREEN"

STARTED=0
while read DEVICE
do
    screen -dr "$SCREEN" -X setenv DEVICE "$DEVICE"
    screen -dr "$SCREEN" -X screen -t "$DEVICE"
    screen -dr "$SCREEN" -p "$DEVICE" -X stuff "./mine_dev.sh"$'\r'
    echo "Started $DEVICE"
    let STARTED+=1
done < <("$JTAGCONFIG" | sed -n 's/^[0-9]\+) //p')

EXPECTED=$( lsusb -d 09fb: | wc -l )
if [ $STARTED -eq $EXPECTED ]
then
    echo "Started $STARTED miners" 1>&2
else
    echo "Warning: Expected $EXPECTED miners, started $STARTED" 1>&2
fi
