/*边沿检测模块,可检测信号的上升沿和下降沿*/
module EDGE_CKECK(
    input  clk,
    input  rst_n,
    input  sign,
    output rise_edge,
    output fall_edge,
    output both_edge
);

reg sign_r1;
reg sign_r2;

always @(posedge clk) begin
    sign_r1 <= sign;
    sign_r2 <= sign_r1;
end

assign rise_edge = (((sign_r1 == 1) && (sign_r2 == 0)) && (rst_n == 1)) ? 1 : 0;
assign fall_edge = (((sign_r1 == 0) && (sign_r2 == 1)) && (rst_n == 1)) ? 1 : 0;
assign both_edge = rise_edge || fall_edge;

endmodule