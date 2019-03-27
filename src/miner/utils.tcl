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

# Current local time in iso8601 format
proc now {} {
    return [clock format [clock seconds] -format "%Y-%m-%d %T"]
}

proc status_print {args} {
    set last [lindex $args end]
    set rest [lrange $args 0 end-1]
    post_message {*}$rest "\[[now]\] $last"
}

proc keep_trying {attempts command args} {
    while {1} {
        if {[catch {$command {*}$args} res]} {
            set res [string trim $res]
            status_print -type warning "Command `$command $args` failed:"
            puts $res
            incr attempts -1
            if {$attempts > 0} {
                after 1
            } else {
                status_print -type error "Too many failures, aborting"
                qexit -error
            }
        } else {
            return $res
        }
    }
}
