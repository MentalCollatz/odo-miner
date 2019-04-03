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

set known_projects [list \
    [list cyclone_v_gx_starter_kit 1 USB-Blaster 0x02B020DD] \
    [list de10_nano 2 DE-SoC 0x4BA00477 0x02D020DD] \
    [list arria_v_gx_starter_kit 1 USB-BlasterII 0x02A030DD 0x020A40DD] \
]

# Extract the parenthesized hex code from a device name
proc device_id {device_name} {
    if {[regexp {\(([0-9A-Fx]+)\)$} $device_name _ res]} {
        return $res
    }
}

# Find the appropriate .sof file for the given hardware and seed
proc get_sof_name {project_name seed} {
    return "../projects/$project_name/output_files/miner_$seed.sof"
}

# Get the project name and position of the relevant device in the jtag chain
proc get_project {hardware_name device_names} {
    global known_projects

    set bracket_pos [string first { [} $hardware_name]
    if {$bracket_pos != -1} {
        set hardware_prefix [string range $hardware_name 0 $bracket_pos-1]
        set device_ids [lmap device $device_names {
            device_id $device
        }]

        foreach project $known_projects {
            set expected_hardware [lindex $project 2]
            set expected_devices [lrange $project 3 end]
            if {$hardware_prefix == $expected_hardware && $device_ids == $expected_devices} {
                return [lrange $project 0 1]
            }
        }
    }

    post_message -type error "Unable to identify project"
    return ""
}

