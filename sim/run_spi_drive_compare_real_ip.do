transcript on

set root_candidates [list \
    [file normalize [pwd]] \
    [file normalize [file join [pwd] ".."]] \
    [file normalize [file join [pwd] ".." ".."]] \
]

foreach candidate $root_candidates {
    if {[file exists [file join $candidate "rtl_orign" "SPI_DRIVE.v"]] &&
        [file exists [file join $candidate "sim" "spi_drive_compare_tb.v"]]} {
        set root_dir $candidate
        break
    }
}

if {![info exists root_dir]} {
    error "Cannot find project root. Run this script from E:/FPGA/ainuo/BTS7501/master."
}

set spi_src [file join $root_dir "rtl_orign" "SPI_DRIVE.v"]
set case_name "after_real_ip"

set do_argc 0
if {[info exists argc]} {
    set do_argc $argc
}

if {$do_argc >= 1 && ${1} ne ""} {
    set spi_arg ${1}
    if {[file pathtype $spi_arg] eq "relative"} {
        set spi_src [file normalize [file join $root_dir $spi_arg]]
    } else {
        set spi_src [file normalize $spi_arg]
    }
}
if {$do_argc >= 2 && ${2} ne ""} {
    set case_name ${2}
}

set pango_sim_dir "D:/pango/PDS_2024.2/pango/PDS_2024.2/arch/vendor/pango/verilog/simulation"
if {[info exists env(PANGO_SIM_DIR)]} {
    set pango_sim_dir [file normalize $env(PANGO_SIM_DIR)]
}
if {$do_argc >= 3 && ${3} ne ""} {
    set pango_sim_dir [file normalize ${3}]
}

proc require_file {path} {
    if {![file exists $path]} {
        error "Required file not found: $path"
    }
}

proc vlog_must {path} {
    require_file $path
    puts "vlog $path"
    if {[catch {vlog $path} msg]} {
        error $msg
    }
}

proc compile_spi_fifo {ip_root fifo_name} {
    set fifo_dir [file join $ip_root $fifo_name]
    vlog_must [file join $fifo_dir "rtl" "ipml_fifo_ctrl_v1_4_${fifo_name}.v"]
    vlog_must [file join $fifo_dir "rtl" "ipml_sdpram_v1_12_${fifo_name}.v"]
    vlog_must [file join $fifo_dir "rtl" "ipml_fifo_v1_12_${fifo_name}.v"]
    vlog_must [file join $fifo_dir "${fifo_name}.v"]
}

require_file $spi_src
require_file [file join $pango_sim_dir "GTP_DRM18K.v"]
require_file [file join $pango_sim_dir "GTP_GRS.v"]

cd $root_dir
puts "Project root: $root_dir"
puts "SPI source  : $spi_src"
puts "Case name   : $case_name"
puts "Pango sim   : $pango_sim_dir"

set run_dir [file join $root_dir "pic" "_comm_compare" "run"]
file mkdir $run_dir
set log_file [file join $run_dir "${case_name}_summary.txt"]

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog_must [file join $pango_sim_dir "GTP_DRM18K.v"]
vlog_must [file join $pango_sim_dir "GTP_GRS.v"]

set ip_root [file join $root_dir "prj" "project" "ipcore"]
compile_spi_fifo $ip_root "SPI_FIFO_MISO1"
compile_spi_fifo $ip_root "SPI_FIFO_MISO2"
compile_spi_fifo $ip_root "SPI_FIFO_MISO3"
compile_spi_fifo $ip_root "SPI_FIFO_MISO4"

vlog_must $spi_src
vlog_must [file join $root_dir "sim" "spi_drive_compare_tb.v"]

vsim -voptargs=+acc work.spi_drive_compare_tb +CASE=$case_name +LOG=$log_file
run -all

puts "Summary: $log_file"
quit -f
