`timescale 1ns/1ps

module spi_drive_compare_tb;
    reg         clk_160M = 1'b0;
    reg         clk_100M = 1'b0;
    reg         rst_n = 1'b0;
    reg [47:0]  i_spi_tx_data = 48'd0;
    reg         i_spi_tx_st = 1'b0;
    reg [15:0]  i_spi_rx_bit_wide = 16'd0;
    reg         i_spi_miso1 = 1'b1;
    reg         i_spi_miso2 = 1'b0;
    reg         i_spi_miso3 = 1'b1;
    reg         i_spi_miso4 = 1'b0;

    wire        o_spi_sclk;
    wire        o_spi_cs;
    wire        o_spi_mosi;
    wire        o_spi_tx_done;
    wire [367:0] o_spi_rx_data1;
    wire [367:0] o_spi_rx_data2;
    wire [367:0] o_spi_rx_data3;
    wire [367:0] o_spi_rx_data4;
    wire        o_spi_rx_done;
    wire [3:0]  o_spi_state;

    GTP_GRS GRS_INST (
        .GRS_N(1'b1)
    );

    reg [8*64-1:0] case_name;
    reg [8*256-1:0] log_name;
    integer log_fh;
    integer active;
    integer rise_count;
    integer fall_count;
    integer mosi_sample_count;
    integer sclk_toggle_count;
    integer done_width_100m;
    integer test_fail;
    integer fail_count = 0;
    integer txn_id;
    integer payload_bits;
    integer fifo1_wr_count;
    integer fifo1_rd_count;
    integer fifo1_not_empty_seen;
    integer fifo1_empty_at_rd;
    time    start_time;
    time    cs_low_time;
    time    done_time;
    time    last_sclk_toggle;
    time    min_half_period;
    time    max_half_period;
    reg [47:0] sampled_mosi;
    reg [47:0] expected_tx_data;
    reg [367:0] fifo1_wr_data_sample;
    reg [367:0] fifo1_rd_data_sample;

    always #3.125 clk_160M = ~clk_160M;
    always #5 clk_100M = ~clk_100M;

    SPI_DRIVE dut (
        .clk_160M(clk_160M),
        .clk_100M(clk_100M),
        .rst_n(rst_n),
        .o_spi_sclk(o_spi_sclk),
        .o_spi_cs(o_spi_cs),
        .o_spi_mosi(o_spi_mosi),
        .i_spi_tx_data(i_spi_tx_data),
        .i_spi_tx_st(i_spi_tx_st),
        .i_spi_rx_bit_wide(i_spi_rx_bit_wide),
        .o_spi_tx_done(o_spi_tx_done),
        .i_spi_miso1(i_spi_miso1),
        .i_spi_miso2(i_spi_miso2),
        .i_spi_miso3(i_spi_miso3),
        .i_spi_miso4(i_spi_miso4),
        .o_spi_rx_data1(o_spi_rx_data1),
        .o_spi_rx_data2(o_spi_rx_data2),
        .o_spi_rx_data3(o_spi_rx_data3),
        .o_spi_rx_data4(o_spi_rx_data4),
        .o_spi_rx_done(o_spi_rx_done),
        .o_spi_state(o_spi_state)
    );

    function [367:0] low_mask;
        input integer bits;
        integer i;
        begin
            low_mask = 368'd0;
            for(i = 0; i < bits; i = i + 1)
                low_mask[i] = 1'b1;
        end
    endfunction

    task reset_monitors;
        begin
            active               = 0;
            rise_count           = 0;
            fall_count           = 0;
            mosi_sample_count    = 0;
            sclk_toggle_count    = 0;
            done_width_100m      = 0;
            test_fail            = 0;
            fifo1_wr_count       = 0;
            fifo1_rd_count       = 0;
            fifo1_not_empty_seen = 0;
            fifo1_empty_at_rd    = 0;
            start_time           = 0;
            cs_low_time          = 0;
            done_time            = 0;
            last_sclk_toggle     = 0;
            min_half_period      = 0;
            max_half_period      = 0;
            sampled_mosi         = 48'd0;
            expected_tx_data     = 48'd0;
            fifo1_wr_data_sample = 368'd0;
            fifo1_rd_data_sample = 368'd0;
        end
    endtask

    always @(posedge dut.SPI_FIFO1_INST.wr_clk) begin
        if(active && dut.SPI_FIFO1_INST.wr_en) begin
            fifo1_wr_count = fifo1_wr_count + 1;
            fifo1_wr_data_sample = dut.SPI_FIFO1_INST.wr_data;
        end
    end

    always @(posedge dut.SPI_FIFO1_INST.rd_clk) begin
        if(active) begin
            if(dut.SPI_FIFO1_INST.rd_empty === 1'b0)
                fifo1_not_empty_seen = 1;
            if(dut.SPI_FIFO1_INST.rd_en) begin
                fifo1_rd_count = fifo1_rd_count + 1;
                fifo1_empty_at_rd = (dut.SPI_FIFO1_INST.rd_empty === 1'b1);
                fifo1_rd_data_sample = dut.SPI_FIFO1_INST.rd_data;
            end
        end
    end

    always @(negedge o_spi_cs) begin
        if(active)
            cs_low_time = $time;
    end

    always @(posedge o_spi_sclk or negedge o_spi_sclk) begin
        if(active && !o_spi_cs) begin
            sclk_toggle_count = sclk_toggle_count + 1;
            if(last_sclk_toggle != 0) begin
                if((min_half_period == 0) || (($time - last_sclk_toggle) < min_half_period))
                    min_half_period = $time - last_sclk_toggle;
                if(($time - last_sclk_toggle) > max_half_period)
                    max_half_period = $time - last_sclk_toggle;
            end
            last_sclk_toggle = $time;
        end
    end

    always @(posedge o_spi_sclk) begin
        if(active && !o_spi_cs)
            rise_count = rise_count + 1;
    end

    always @(negedge o_spi_sclk) begin
        if(active && !o_spi_cs) begin
            fall_count = fall_count + 1;
            if((rise_count >= 1) && (rise_count <= 48)) begin
                sampled_mosi = {sampled_mosi[46:0], o_spi_mosi};
                mosi_sample_count = mosi_sample_count + 1;
            end
        end
    end

    task run_transaction;
        input [8*24-1:0] label;
        input [15:0] width;
        input [47:0] tx_data;
        reg [367:0] mask;
        reg done_rx1_ok;
        reg done_rx2_ok;
        reg done_rx3_ok;
        reg done_rx4_ok;
        reg delay_rx1_ok;
        reg delay_rx2_ok;
        reg delay_rx3_ok;
        reg delay_rx4_ok;
        begin
            txn_id = txn_id + 1;
            reset_monitors();
            expected_tx_data = tx_data;
            payload_bits = width - 16'd26;
            mask = low_mask(payload_bits);

            @(posedge clk_100M);
            i_spi_rx_bit_wide <= width;
            i_spi_tx_data     <= tx_data;
            active = 1;
            start_time = $time;

            i_spi_tx_st <= 1'b1;
            @(posedge clk_100M);
            i_spi_tx_st <= 1'b0;

            wait(o_spi_rx_done === 1'b1);
            done_time = $time;
            done_rx1_ok = ((o_spi_rx_data1 & mask) === mask);
            done_rx2_ok = ((o_spi_rx_data2 & mask) === 368'd0);
            done_rx3_ok = ((o_spi_rx_data3 & mask) === mask);
            done_rx4_ok = ((o_spi_rx_data4 & mask) === 368'd0);

            while(o_spi_rx_done === 1'b1) begin
                done_width_100m = done_width_100m + 1;
                @(posedge clk_100M);
            end

            repeat(8) @(posedge clk_100M);
            active = 0;

            delay_rx1_ok = ((o_spi_rx_data1 & mask) === mask);
            delay_rx2_ok = ((o_spi_rx_data2 & mask) === 368'd0);
            delay_rx3_ok = ((o_spi_rx_data3 & mask) === mask);
            delay_rx4_ok = ((o_spi_rx_data4 & mask) === 368'd0);

            if(mosi_sample_count != 48)
                test_fail = 1;
            if(sampled_mosi !== expected_tx_data)
                test_fail = 1;
            if(!done_rx1_ok)
                test_fail = 1;
            if(!done_rx2_ok)
                test_fail = 1;
            if(!done_rx3_ok)
                test_fail = 1;
            if(!done_rx4_ok)
                test_fail = 1;
            if(done_width_100m <= 0)
                test_fail = 1;

            if(test_fail)
                fail_count = fail_count + 1;

            $fdisplay(log_fh,
                "CASE=%0s TXN=%0d LABEL=%0s WIDTH=%0d PAYLOAD=%0d FAIL=%0d MOSI_SAMPLES=%0d MOSI_MATCH=%0d DONE_RX1_OK=%0d DONE_RX2_OK=%0d DONE_RX3_OK=%0d DONE_RX4_OK=%0d DELAY_RX1_OK=%0d DELAY_RX2_OK=%0d DELAY_RX3_OK=%0d DELAY_RX4_OK=%0d RISE=%0d FALL=%0d TOGGLE=%0d DONE_WIDTH_100M=%0d F1_WR=%0d F1_RD=%0d F1_NOTEMPTY=%0d F1_EMPTY_AT_RD=%0d F1_WR_OK=%0d F1_WR_LO=%016h F1_RD_LO=%016h RX1_LO=%016h START_NS=%0t CS_LOW_NS=%0t DONE_NS=%0t MIN_HALF_NS=%0t MAX_HALF_NS=%0t TX_DONE=%b STATE=%h",
                case_name, txn_id, label, width, payload_bits, test_fail,
                mosi_sample_count, (sampled_mosi === expected_tx_data),
                done_rx1_ok, done_rx2_ok, done_rx3_ok, done_rx4_ok,
                delay_rx1_ok, delay_rx2_ok, delay_rx3_ok, delay_rx4_ok,
                rise_count, fall_count, sclk_toggle_count, done_width_100m,
                fifo1_wr_count, fifo1_rd_count, fifo1_not_empty_seen, fifo1_empty_at_rd,
                ((fifo1_wr_data_sample & mask) === mask),
                fifo1_wr_data_sample[63:0], fifo1_rd_data_sample[63:0], o_spi_rx_data1[63:0],
                start_time, cs_low_time, done_time, min_half_period, max_half_period,
                o_spi_tx_done, o_spi_state);

            repeat(20) @(posedge clk_100M);
        end
    endtask

    initial begin
        if(!$value$plusargs("CASE=%s", case_name))
            case_name = "unknown";
        if(!$value$plusargs("LOG=%s", log_name))
            log_name = "spi_drive_compare_summary.txt";

        log_fh = $fopen(log_name, "w");
        if(log_fh == 0) begin
            $display("Cannot open log file: %0s", log_name);
            $finish;
        end

        txn_id = 0;
        reset_monitors();

        repeat(8) @(posedge clk_100M);
        rst_n <= 1'b1;
        repeat(8) @(posedge clk_100M);

        run_transaction("CTRL_48",  16'd74,  48'hA55A_1234_C3C3);
        run_transaction("RR_160",   16'd186, 48'h0F0F_F00D_55AA);
        run_transaction("ALL_368",  16'd394, 48'h1357_2468_ABCD);

        $fdisplay(log_fh, "CASE=%0s TOTAL_FAIL=%0d", case_name, fail_count);
        $fclose(log_fh);
        if(fail_count != 0) begin
            $display("SPI compare test failed: %0d failures", fail_count);
            $finish;
        end
        $display("SPI compare test passed for %0s", case_name);
        $finish;
    end
endmodule
