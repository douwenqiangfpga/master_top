transcript on

set root_candidates [list \
    [file normalize [pwd]] \
    [file normalize [file join [pwd] ".."]] \
    [file normalize [file join [pwd] ".." ".."]] \
]

foreach candidate $root_candidates {
    if {[file exists [file join $candidate "rtl" "SPI_DRIVE.v"]] &&
        [file exists [file join $candidate "sim" "tb_spi_drive.v"]]} {
        set root_dir $candidate
        break
    }
}

if {![info exists root_dir]} {
    error "Cannot find project root. Run this script from E:/FPGA/ainuo/BTS7501/master."
}

cd $root_dir

puts "Project root: $root_dir"

if {![file exists work]} {
    vlib work
}
vmap work work

vlog +incdir+rtl sim/tb_spi_drive.v rtl/SPI_DRIVE.v

vsim -voptargs=+acc work.tb_spi_drive

proc add_wave_safe {args} {
    if {[catch {eval add wave $args} msg]} {
        puts "Skip wave: $msg"
    }
}

catch {view wave}
catch {delete wave *}

add_wave_safe -divider TB_CLK_RST
add_wave_safe /tb_spi_drive/clk_160M
add_wave_safe /tb_spi_drive/clk_100M
add_wave_safe /tb_spi_drive/rst_n
add_wave_safe /tb_spi_drive/i_spi_tx_st

add_wave_safe -divider SPI_PAD
add_wave_safe /tb_spi_drive/o_spi_cs
add_wave_safe /tb_spi_drive/o_spi_sclk
add_wave_safe /tb_spi_drive/o_spi_mosi
add_wave_safe /tb_spi_drive/i_spi_miso1
add_wave_safe /tb_spi_drive/i_spi_miso2
add_wave_safe /tb_spi_drive/i_spi_miso3
add_wave_safe /tb_spi_drive/i_spi_miso4

add_wave_safe -divider SCLK_PHASE
add_wave_safe -radix unsigned /tb_spi_drive/dut/clk_cnt
add_wave_safe /tb_spi_drive/dut/r_spi_cs_d0
add_wave_safe /tb_spi_drive/dut/spi_sclk_toggle
add_wave_safe /tb_spi_drive/dut/spi_sclk_pos
add_wave_safe /tb_spi_drive/dut/spi_sclk_neg
add_wave_safe /tb_spi_drive/dut/spi_sclk_neg_d

add_wave_safe -divider TX_PATH
add_wave_safe -radix hex      /tb_spi_drive/dut/r_spi_tx_data
add_wave_safe -radix hex      /tb_spi_drive/dut/r_spi_tx_reg
add_wave_safe -radix unsigned /tb_spi_drive/dut/r_spi_tx_bit_cnt
add_wave_safe /tb_spi_drive/dut/r_spi_tx_cnt_done
add_wave_safe /tb_spi_drive/o_spi_tx_done

add_wave_safe -divider RX_WINDOW
add_wave_safe -radix unsigned /tb_spi_drive/dut/r_spi_rx_bit_wide_d0
add_wave_safe -radix unsigned /tb_spi_drive/dut/w_spi_rx_cap_first
add_wave_safe -radix unsigned /tb_spi_drive/dut/w_spi_rx_cap_last
add_wave_safe -radix unsigned /tb_spi_drive/dut/w_spi_rx_done_last
add_wave_safe -radix unsigned /tb_spi_drive/dut/w_spi_rx_data_bits
add_wave_safe -radix unsigned /tb_spi_drive/dut/r_spi_rx_bit_cnt
add_wave_safe /tb_spi_drive/dut/r_spi_rx_cnt_done
add_wave_safe /tb_spi_drive/dut/r_spi_rx_done
add_wave_safe /tb_spi_drive/o_spi_rx_done

add_wave_safe -divider RX_DATA
add_wave_safe -radix hex /tb_spi_drive/dut/r_spi_rx_data1
add_wave_safe -radix hex /tb_spi_drive/dut/r_spi_rx_data2
add_wave_safe -radix hex /tb_spi_drive/dut/r_spi_rx_data3
add_wave_safe -radix hex /tb_spi_drive/dut/r_spi_rx_data4
add_wave_safe -radix hex /tb_spi_drive/o_spi_rx_data1
add_wave_safe -radix hex /tb_spi_drive/o_spi_rx_data2
add_wave_safe -radix hex /tb_spi_drive/o_spi_rx_data3
add_wave_safe -radix hex /tb_spi_drive/o_spi_rx_data4

add_wave_safe -divider SLAVE_MODEL
add_wave_safe -radix hex      /tb_spi_drive/slave_rx_shift
add_wave_safe -radix hex      /tb_spi_drive/slave_rx_last
add_wave_safe -radix unsigned /tb_spi_drive/slave_rx_cnt
add_wave_safe -radix unsigned /tb_spi_drive/slave_rx_last_cnt
add_wave_safe -radix unsigned /tb_spi_drive/miso_delay_cnt
add_wave_safe -radix unsigned /tb_spi_drive/miso_bit_cnt

run -all

catch {wave zoom full}
puts "SPI_DRIVE simulation finished."
