module PULSE_EXPAND #(
    parameter EXPAND_NUM = 1    // 脉宽拓展多少个时钟周期
)(
    input  clk,
    input  rst_n,
    input  sig_in,
    output sig_out
);

reg       sig_out_r;
reg [7:0] count;
reg [1:0] state;

localparam idle     = 2'b00,
           wait_end = 2'b01,
           expand   = 2'b10;

assign sig_out = sig_out_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sig_out_r <= 0;
        count     <= 1;
        state     <= idle;
    end
    else begin
        sig_out_r <= 0;

        case (state)
            idle: begin
                if (sig_in) begin
                    sig_out_r <= 1;
                    state     <= wait_end;
                end
            end

            wait_end: begin
                sig_out_r <= 1;
                if (!sig_in)
                    state <= expand;
            end

            expand: begin
                sig_out_r <= 1;
                count     <= count + 1;

                if (count == EXPAND_NUM) begin
                    sig_out_r <= 0;
                    state     <= idle;
                    count     <= 1;
                end
            end
        endcase
    end
end

endmodule