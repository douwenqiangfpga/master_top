module CLK_DRIVER(
    input sclk,
    input rst_n,
    output clk_out1
);
reg     [ 4:0]    clk_cnt;
reg               clk_45k;
always @(negedge sclk or negedge rst_n) begin
    if (!rst_n) begin
        clk_cnt <= 1'b1;
        clk_45k <= 1'b0;
    end
    else  begin
        clk_cnt <= clk_cnt + 1;
        if(clk_cnt == 'd21) begin
            clk_cnt <= 'd0;
            clk_45k <= ~clk_45k;
        end
   end
end
assign clk_out1 = clk_45k;
endmodule