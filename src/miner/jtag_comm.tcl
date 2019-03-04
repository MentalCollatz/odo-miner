# JTAG Communication Functions
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

# User API Functions
# These should be generic and be the same no matter what the underlying FPGA is.
# Use these to interact with the FPGA.

# Program the FPGA with the specified .sof file
proc program_fpga {hardware_name sof_name} {
    post_message -type info "Programming $hardware_name with $sof_name"

    # cancel any existing sources and probes
    catch end_insystem_source_probe

    if {[catch {exec quartus_pgm -c $hardware_name -m JTAG -o "P;$sof_name"} result]} {
        post_message -type error "Programming failed:"
        puts $result
        return 0
    } else {
        post_message -type info "Programming successful."
        return 1
    }
}

# Find the appropriate .sof file for the given hardware and seed
proc get_sof_name {hardware_name seed} {
    # TODO: support more boards
    # TODO: automatically identify correct device
    return "../projects/cyclone_v_gx_starter_kit/output_files/miner_$seed.sof"
}

# Initialize the FPGA
proc fpga_init {hardware_name} {
    set device_name [find_miner_fpga $hardware_name]

    if {$device_name eq ""} {
        return 0
    }
    start_insystem_source_probe -hardware_name $hardware_name -device_name $device_name
    post_message -type info "Mining fpga found: $hardware_name $device_name"
    return 1
}

set fpga_current_work ""
set fpga_last_nonce ""

# Push new work to the FPGA
proc push_work_to_fpga {work} {
    global fpga_current_work

    write_instance "WRK1" [string range $work 0 71]
    write_instance "WRK2" [string range $work 72 151]
    set fpga_current_work [string range $work 0 151]

    # Reset the last nonce.  This isn't strictly necessary, but prevents a race
    # condition that would result in us occasionally submitting bad shares.
    get_result_from_fpga
}

proc clear_fpga_work {} {
    global fpga_current_work
    set fpga_current_work ""
}

# Get a new result from the FPGA if one is available and format it for submission.
# If no results are available, returns empty string
proc get_result_from_fpga {} {
    global fpga_last_nonce
    global fpga_current_work

    if {$fpga_current_work eq ""} {
        return
    }

    set golden_nonce [read_instance GNON]

    if {$golden_nonce ne $fpga_last_nonce} {
        set fpga_last_nonce $golden_nonce
        return $fpga_current_work$golden_nonce
    }
}

# Currently unused.  TODO: on startup, see if the FPGA is alread running the
# correct seed and skip reprogramming it.
proc get_fpga_seed {} {
    return [read_instance SEED]
}

# Variable target mining is supported.
proc set_work_target {target} {
    # also support designs with hard-coded target
    if {[instance_exists TRGT]} {
        write_instance TRGT $target
    }
}

# Ask the user which hardware to use
proc select_hardware {} {
    set hardware_names [get_hardware_names]

    set len 0

    puts "Listing available hardware"

    # List out all hardware names and the devices connected to them
    foreach hardware_name $hardware_names {
        puts "$len) $hardware_name"
        incr len

        foreach device_name [get_device_names -hardware_name $hardware_name] {
            puts "\t$device_name"
        }
    }

    if {$len == 0} {
        post_message -type error "There are no Altera devices currently connected."
        post_message -type error "Please connect an Altera FPGA and re-run this script."
        qexit -error
    }

    incr len -1
    while {1} {
        puts -nonewline "\nWhich USB device would you like to scan? "
        gets stdin selected_hardware_id
        puts ""

        if {[catch {lindex $hardware_names [expr {int($selected_hardware_id)}]} hardware_name]
            || $hardware_name eq ""} {
            post_message -type error "Invalid choice. Enter a number from 0 to $len"
        } else {
            post_message -type info "Selected USB device: $hardware_name\n"
            return $hardware_name
        }
    }
}

###
# Internal FPGA/JTAG APIs are below
# These should not be accessed outside of this script
###################################

set fpga_instances [dict create]
set fpga_last_nonce 0

# Search the specified FPGA device for all Sources and Probes
proc find_instances {hardware_name device_name} {
    global fpga_instances

    set fpga_instances [dict create]

    if {[catch {

        foreach instance [get_insystem_source_probe_instance_info -hardware_name $hardware_name -device_name $device_name] {
            dict set fpga_instances [lindex $instance 3] [lindex $instance 0]
        }

    } exc]} {
        post_message -type error "find_instances failed:"
        puts $exc
        set fpga_instances [dict create]
    }
}

proc instance_id {name} {
    global fpga_instances
    return [dict get $fpga_instances $name]
}

# FPGA uses big endian, miner scripts use little endian
proc reverse_hex {hex_str} {
    return [binary encode hex [string reverse [binary decode hex $hex_str]]]
}

proc write_instance {name value} {
    return [write_source_data -instance_index [instance_id $name] -value_in_hex -value [reverse_hex $value]]
}

proc read_instance {name} {
    return [reverse_hex [read_probe_data -instance_index [instance_id $name] -value_in_hex]]
}

proc instance_exists {name} {
    global fpga_instances
    return [dict exists $fpga_instances $name]
}

# Try to find an FPGA on the JTAG chain that has mining firmware loaded into it.
proc find_miner_fpga {hardware_name} {
    if {[catch {get_device_names -hardware_name $hardware_name} device_names]} {
        post_message -type error "get_device_names: $device_names"
        return
    }

    foreach device_name $device_names {
        if {[check_if_fpga_is_miner $hardware_name $device_name]} {
            return $device_name
        }
    }
}

# Check if the specified FPGA is loaded with miner firmware
proc check_if_fpga_is_miner {hardware_name device_name} {
    find_instances $hardware_name $device_name

    set expected [list WRK1 WRK2 GNON SEED]
    foreach inst $expected {
        if {![instance_exists $inst]} {
            return 0
        }
    }
    return 1
}

