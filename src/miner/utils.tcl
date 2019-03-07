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

proc keep_trying {attempts command args} {
    while {1} {
        if {[catch {$command {*}$args} res]} {
            set res [string trim $res]
            post_message -type warning "Command `$command $args` failed:"
            puts $res
            incr attempts -1
            if {$attempts > 0} {
                after 1
            } else {
                post_message -type error "Too many failures, aborting"
                qexit -error
            }
        } else {
            return $res
        }
    }
}
