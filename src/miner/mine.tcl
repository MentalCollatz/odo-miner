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
# stratum params
set stratum_idstring ""
set stratum_ntime ""
set stratum_nonce2 ""

# change the epoch, and reprogram the fpga to the new seed
proc advance_epoch {seed} {
    global prev_results
    global epoch_results
    global last_seed
    global last_warning
    global hardware_name
    global project_config
    if {$seed == 0} {
        if {$seed != $last_warning} {
            status_print -type warning "Pool is unable to provide work."
            set last_warning $seed
        }
        return 0
    }
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
            status_print -type warning "File $sof does not exist, unable to mine."
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
    global last_warning
    if {$seed != $last_seed} {
        if {![advance_epoch $seed]} {
            clear_fpga_work
            return
        }
    }
    set_work_target $target
    push_work_to_fpga $data
    if {$last_warning == 0} {
        status_print -type info "Received work from pool."
        set last_warning ""
    }
}

proc set_work_stratum {data target seed idstring ntime nonce2} {
    global stratum_idstring
    global stratum_ntime
    global stratum_nonce2

    set stratum_idstring $idstring
    set stratum_ntime $ntime
    set stratum_nonce2 $nonce2

    set_work $data $target $seed
}

proc add_result {status} {
    global config_output
    global epoch_results
    dict incr epoch_results $status
    set count [dict get $epoch_results $status]
    if {$status eq "accepted"} {
        set type info
    } elseif {$status eq "stale" || $status eq "inconclusive"} {
        set type warning
    } else {
        set type error
    }
    if {$config_output eq "verbose"} {
        status_print -type $type "result $status"
    } else {
        if {$count <= 10} {
            status_print -type $type "result $status"
        } elseif {$count <= 100 && ($count % 10) == 0} {
            status_print -type $type "result (x10) $status"
        } elseif {($count % 100) == 0} {
            status_print -type $type "result (x100) $status"
        }
        if {$count == 10} {
            post_message -type $type "Future $status results will be batched in 10s"
        }
        if {$count == 100} {
            post_message -type $type "Future $status results will be batched in 100s"
        }
    }
}

proc receive_data {conn} {
    fconfigure $conn -blocking 1
    gets $conn data
    if {$data eq ""} {
        status_print -type error "Lost connection to pool"
        qexit -error
    }
    set args [split $data]
    set command [lindex $args 0]
    set args [lrange $args 1 end]
    if {$command eq "work" && [llength $args] == 3} {
        # work <data> <target> <seed>
        set_work {*}$args
    } elseif {$command eq "work" && [llength $args] == 6} {
        # work <data> <target> <seed> <idstring> <ntime> <nonce2>
        set_work_stratum {*}$args
    # result <status>
    } elseif {$command eq "result" && [llength $args] == 1} {
        add_result {*}$args
    } elseif {$command eq "connected"} {
        status_print -type info "connected to $args"
    } elseif {$command eq "set_subscribe_params"} {
        # auth after subscribe response
        pool_auth $conn
    } elseif {$command eq "authorized"} {
        status_print -type info "authorized"
    } elseif {$command eq "set_target"} {
        status_print -type info "pool target $args"
    } elseif {$command eq "reconnect"} {
        status_print -type info "reconnect request received, clear work"
        clear_fpga_work
    } else {
        status_print -type warning "Unknown command: $command $args"
    }
    fconfigure $conn -blocking 0
}

proc submit_nonce {conn nonce} {
    global stratum_idstring
    global stratum_ntime
    global stratum_nonce2

    fconfigure $conn -blocking 1
    puts $conn "submit_nonce $nonce $stratum_idstring $stratum_ntime $stratum_nonce2"
    flush $conn
    fconfigure $conn -blocking 0
}

proc submit_work {conn work} {
    fconfigure $conn -blocking 1
    puts $conn "submit $work"
    flush $conn
    fconfigure $conn -blocking 0
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
    if {$project_config eq ""} {
        post_message -type error "Unable to identify project for hardware"
        qexit -error
    }
}

# Create a connection to the pool (or bridge, as will likely be the case)
proc create_pool_conn {} {
    global config_host
    global default_stratum_port
    global default_solo_port
    global config_mode
    if {$config_mode eq "stratum"} {
        set conn [socket $config_host $default_stratum_port]
    } else {
        set conn [socket $config_host $default_solo_port]
    }
    fconfigure $conn -translation binary
    fconfigure $conn -buffering line
    fconfigure $conn -blocking 0
    fileevent $conn readable [list receive_data $conn]
    return $conn
}

proc pool_auth {conn} {
    global miner_id
    # leave only numbers from miner_id
    regsub -all -- {[^0-9]} $miner_id "" worker
    fconfigure $conn -blocking 1
    puts $conn "auth $worker"
    status_print "auth request for worker $worker"
    flush $conn
    fconfigure $conn -blocking 0
}

proc wait_for_nonce {conn} {
    global config_mode
    while {1} {
        set solved_work [get_result_from_fpga]
        if {$solved_work ne ""} {
            if {$config_mode eq "stratum"} {
                submit_nonce $conn $solved_work
            } else {
                submit_work $conn $solved_work
            }
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
set conn [create_pool_conn]
wait_for_nonce $conn
