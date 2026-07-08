/*
 * Master/slave FPGA SPI receive module.
 * MOSI is sampled once per synchronized SCLK rising edge, so the receive
 * logic follows the external SPI clock instead of a fixed 200 MHz divider.
 */

module COM_RECEIVE
(
    input               i_clk           ,
    input               i_rst_n         ,

    input               i_com_sclk      ,
    input               i_mosi          /*synthesis PAP_MARK_DEBUG = "true"*/,
    input               i_clk_200M      /*synthesis PAP_MARK_DEBUG = "true"*/,
    output      [15:0]  o_rece_data     /*synthesis PAP_MARK_DEBUG = "true"*/,
    output              o_rece_one_word /*synthesis PAP_MARK_DEBUG = "true"*/
);

//************* Define Parameters and Internal Signals *************//

parameter WORD_LEN = 16;

reg  [15:0] r_rece_data          /*synthesis PAP_MARK_DEBUG = "true"*/;
reg  [15:0] r_rece_word_200      /*synthesis PAP_MARK_DEBUG = "true"*/;
reg  [15:0] r_rece_word_i_clk    /*synthesis PAP_MARK_DEBUG = "true"*/;
reg  [4:0]  r_rece_bit_cnt       /*synthesis PAP_MARK_DEBUG = "true"*/;
reg  [2:0]  r_sclk_sync          /*synthesis PAP_MARK_DEBUG = "true"*/;
reg  [1:0]  r_mosi_sync          /*synthesis PAP_MARK_DEBUG = "true"*/;
wire        w_sclk_rise          /*synthesis PAP_MARK_DEBUG = "true"*/;
reg         r_rece_toggle_200    /*synthesis PAP_MARK_DEBUG = "true"*/;
reg  [2:0]  r_rece_toggle_sync   /*synthesis PAP_MARK_DEBUG = "true"*/;
reg         r_test_data_valid_1  /*synthesis PAP_MARK_DEBUG = "true"*/;
reg         r_rece_one_word      /*synthesis PAP_MARK_DEBUG = "true"*/;
reg         r_rece_one_word_d0   /*synthesis PAP_MARK_DEBUG = "true"*/;
wire        w_rece_word_pulse    /*synthesis PAP_MARK_DEBUG = "true"*/;

//*********************** Main Code ************************//

assign o_rece_data     = r_rece_word_i_clk;
assign o_rece_one_word = r_rece_one_word;

assign w_sclk_rise = r_sclk_sync[1] & ~r_sclk_sync[2];
assign w_rece_word_pulse = r_rece_toggle_sync[2] ^ r_rece_toggle_sync[1];

always @(posedge i_clk_200M or negedge i_rst_n) begin
    if (!i_rst_n) begin
        r_sclk_sync <= 3'b111;
        r_mosi_sync <= 2'b00;
    end else begin
        r_sclk_sync <= {r_sclk_sync[1:0], i_com_sclk};
        r_mosi_sync <= {r_mosi_sync[0], i_mosi};
    end
end

always @(posedge i_clk_200M or negedge i_rst_n) begin
    if (!i_rst_n) begin
        r_rece_data         <= 16'd0;
        r_rece_word_200     <= 16'd0;
        r_rece_bit_cnt      <= 5'd0;
        r_rece_toggle_200   <= 1'b0;
        r_test_data_valid_1 <= 1'b0;
    end else begin
        r_test_data_valid_1 <= 1'b0;
        if (w_sclk_rise) begin
            r_rece_data <= {r_rece_data[WORD_LEN-2:0], r_mosi_sync[1]};
            if (r_rece_bit_cnt == WORD_LEN - 1) begin
                r_rece_bit_cnt      <= 5'd0;
                r_rece_word_200     <= {r_rece_data[WORD_LEN-2:0], r_mosi_sync[1]};
                r_rece_toggle_200   <= ~r_rece_toggle_200;
                r_test_data_valid_1 <= 1'b1;
            end else begin
                r_rece_bit_cnt <= r_rece_bit_cnt + 5'd1;
            end
        end
    end
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        r_rece_toggle_sync <= 3'b000;
        r_rece_word_i_clk  <= 16'd0;
        r_rece_one_word    <= 1'b0;
        r_rece_one_word_d0 <= 1'b0;
    end else begin
        r_rece_toggle_sync <= {r_rece_toggle_sync[1:0], r_rece_toggle_200};

        r_rece_one_word    <= r_rece_one_word_d0;
        r_rece_one_word_d0 <= 1'b0;

        if (w_rece_word_pulse) begin
            r_rece_word_i_clk <= r_rece_word_200;
            r_rece_one_word_d0 <= 1'b1;
        end
    end
end

endmodule
