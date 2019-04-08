#!/bin/bash

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

if [ -z "$QUARTUSPATH" ]
then
    QUARTUSSTP=$(which quartus_stp)
    if [ -z "$QUARTUSSTP" ]
    then
        echo 'Error: could not locate quartus_stp, please set $QUARTUSPATH' 1>&2
        exit 1
    fi
else
    QUARTUSSTP="$QUARTUSPATH/quartus_stp"
fi

if [ -z "$DEVICE" ]
then
    echo 'Error, $DEVICE is not set' 1>&2
    exit 1
fi

"$QUARTUSSTP" -t mine.tcl "$DEVICE" "$@"
