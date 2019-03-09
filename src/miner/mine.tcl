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

package require http

source jtag_comm.tcl
source config.tcl

# stats for previous epochs
set prev_results [dict create]
# stats for current epoch
set epoch_results [dict create accepted 0]
# most recent seed seen
set last_seed ""
# most recent seed with missing sof file
set last_warning ""

# change the epoch, and reprogram the fpga to the new seed
proc advance_epoch {seed} {
    global prev_results
    global epoch_results
    global last_seed
    global last_warning
    global hardware_name
    global project_config
    if {$last_seed != ""} {
        post_message -type info "Results for last epoch:"
        dict for {key value} $epoch_results {
            post_message -type info "$key: $value"
            dict incr prev_results $key $value
        }
        set last_seed ""
    }
    set sof [get_sof_name [lindex $project_config 0] $seed]
    if {![file exists $sof]} {
        if {$seed != $last_warning} {
            post_message -type warning "File $sof does not exist, unable to mine."
            post_message -type warning "Please ensure autocompile.sh is running."
            set last_warning $seed
        }
        return 0
    }
    if {![program_fpga $hardware_name $sof [lindex $project_config 1]] || ![fpga_init $hardware_name]} {
        return 0
    }
    set last_seed $seed
    set epoch_results [dict create accepted 0]
    return 1
}

proc set_work {data target seed} {
    global last_seed
    if {$seed != $last_seed} {
        if {![advance_epoch $seed]} {
            clear_fpga_work
            return
        }
    }
    set_work_target $target
    push_work_to_fpga $data
}

proc add_result {status} {
    global epoch_results
    dict incr epoch_results $status
    if {$status eq "accepted"} {
        post_message -type info "result accepted"
    } elseif {$status eq "stale"} {
        post_message -type warning "result stale"
    } elseif {$status eq "bad"} {
        post_message -type error "result bad"
    }
}

proc receive_data {conn} {
    fconfigure $conn -blocking 1
    gets $conn data
    if {$data == ""} {
        post_message -type error "Lost connection to pool"
        qexit -error
    }
    set args [split $data]
    set command [lindex $args 0]
    set args [lrange $args 1 end]
    # work <data> <target> <seed>
    if {$command eq "work" && [llength $args] == 3} {
        set_work {*}$args
    # result <status>
    } elseif {$command eq "result" && [llength $args] == 1} {
        add_result {*}$args
    } else {
        post_message -type warning "Unknown command: $command $args"
    }
    fconfigure $conn -blocking 0
}

proc submit_work {conn work} {
    puts $conn "submit $work"
    flush $conn
}

# Allow user to specify hardware via command line. Otherwise provide a list
# of available hardware to choose from.
proc choose_hardware {argv} {
    global hardware_name
    global project_config
    global miner_id
    if {[llength $argv] == 1} {
        set hardware_name [lindex $argv 0]
    } else {
        set hardware_name [select_hardware]
    }
    set miner_id [lindex [split $hardware_name] 1]
    set project_config [identify_project $hardware_name]
    if {$project_config == ""} {
        post_message -type error "Unable to identify project for hardware"
        qexit -error
    }
}

# Create a connection to the pool (or bridge, as will likely be the case)
proc create_pool_conn {host port} {
    set conn [socket $host $port]
    fconfigure $conn -translation binary
    fconfigure $conn -buffering line
    fconfigure $conn -blocking 0
    fileevent $conn readable [list receive_data $conn]
    return $conn
}

proc wait_for_nonce {conn} {
    while {1} {
        set solved_work [get_result_from_fpga]
        if {$solved_work ne ""} {
            submit_work $conn $solved_work
        }
        # Allow pool connection to process
        update
        # throttle a bit
        after 1
    }
}

choose_hardware $argv
#if {[fpga_init $hardware_name]} {
#    set last_seed [get_fpga_seed]
#}
set conn [create_pool_conn $config_host $config_port]
wait_for_nonce $conn

