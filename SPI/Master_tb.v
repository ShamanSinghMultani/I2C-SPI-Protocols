`timescale 1ns/1ps

module SPI_Master_tb;

parameter CLK_FREQUENCE = 50_000_000;
parameter SPI_FREQUENCE = 5_000_000;
parameter DATA_WIDTH    = 8;
parameter CPOL          = 0;
parameter CPHA          = 0;

reg clk;
reg rst_n;
reg [DATA_WIDTH-1:0] data_m_in;
reg [DATA_WIDTH-1:0] data_s_in;
reg start_m;
reg saw_data_valid;

wire finish_m;
wire [DATA_WIDTH-1:0] data_m_out;
wire [DATA_WIDTH-1:0] data_s_out;
wire data_valid_s;

integer failures;

SPI_loopback #(
    .CLK_FREQUENCE(CLK_FREQUENCE),
    .SPI_FREQUENCE(SPI_FREQUENCE),
    .DATA_WIDTH(DATA_WIDTH),
    .CPOL(CPOL),
    .CPHA(CPHA)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .data_m_in(data_m_in),
    .data_s_in(data_s_in),
    .start_m(start_m),
    .finish_m(finish_m),
    .data_m_out(data_m_out),
    .data_s_out(data_s_out),
    .data_valid_s(data_valid_s)
);

always #10 clk = ~clk;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        saw_data_valid <= 1'b0;
    end else if (start_m) begin
        saw_data_valid <= 1'b0;
    end else if (data_valid_s) begin
        saw_data_valid <= 1'b1;
    end
end

task run_transfer;
    input [DATA_WIDTH-1:0] tx_master;
    input [DATA_WIDTH-1:0] tx_slave;
begin
    data_m_in <= tx_master;
    data_s_in <= tx_slave;
    saw_data_valid <= 1'b0;

    @(posedge clk);
    start_m <= 1'b1;
    @(posedge clk);
    start_m <= 1'b0;

    wait (finish_m);
    @(posedge clk);

    if (data_m_out !== tx_slave) begin
        failures = failures + 1;
        $display("FAIL: master expected %h got %h", tx_slave, data_m_out);
    end

    if (!saw_data_valid || (data_s_out !== tx_master)) begin
        failures = failures + 1;
        $display("FAIL: slave expected %h got %h valid_seen=%0d", tx_master, data_s_out, saw_data_valid);
    end
end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    start_m = 1'b0;
    saw_data_valid = 1'b0;
    data_m_in = {DATA_WIDTH{1'b0}};
    data_s_in = {DATA_WIDTH{1'b0}};
    failures = 0;

    repeat (3) @(posedge clk);
    rst_n <= 1'b1;

    run_transfer(8'hA5, 8'h3C);
    run_transfer(8'h5A, 8'hC3);
    run_transfer(8'hF0, 8'h0F);

    if (failures == 0) begin
        $display("SPI_Master_tb: PASS");
    end else begin
        $display("SPI_Master_tb: FAIL (%0d failures)", failures);
        $fatal(1);
    end
end

endmodule
