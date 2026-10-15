`timescale 1ns/1ps

module tbmast;

reg clk;
reg rst_n;
reg start;
reg rw;
reg [6:0] address;
reg [7:0] reg_addr;
reg [7:0] data_wr;

wire [7:0] data_rd;
wire busy;
wire done;
wire ack_error;
wire scl;
tri1 sda;
wire [7:0] slave_out;

integer failures;
integer timeout_count;

master #(
    .CLK_DIVIDER(4)
) uut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .rw(rw),
    .address(address),
    .reg_addr(reg_addr),
    .data_wr(data_wr),
    .data_rd(data_rd),
    .busy(busy),
    .done(done),
    .ack_error(ack_error),
    .scl(scl),
    .sda(sda)
);

slave #(
    .SLAVE_ADDRESS(7'h52)
) slv (
    .clk(clk),
    .rst_n(rst_n),
    .scl(scl),
    .sda(sda),
    .out(slave_out)
);

always #5 clk = ~clk;

task pulse_start;
begin
    @(posedge clk);
    start <= 1'b1;
    @(posedge clk);
    start <= 1'b0;
end
endtask

task wait_done;
begin
    timeout_count = 0;
    while (!done && (timeout_count < 5000)) begin
        @(posedge clk);
        timeout_count = timeout_count + 1;
    end

    if (!done) begin
        failures = failures + 1;
        $display("FAIL: I2C transaction timed out");
    end
end
endtask

task check_equal;
    input [7:0] got;
    input [7:0] exp;
    input [127:0] name;
begin
    if (got !== exp) begin
        failures = failures + 1;
        $display("FAIL: %0s got=%h exp=%h", name, got, exp);
    end
end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    start = 1'b0;
    rw = 1'b0;
    address = 7'h52;
    reg_addr = 8'h00;
    data_wr = 8'h00;
    failures = 0;

    repeat (4) @(posedge clk);
    rst_n <= 1'b1;

    // Read the slave's power-on value at register 0x10.
    rw <= 1'b1;
    reg_addr <= 8'h10;
    data_wr <= 8'h00;
    pulse_start;
    wait_done;
    if (ack_error) begin
        failures = failures + 1;
        $display("FAIL: unexpected ACK error during default read");
    end
    check_equal(data_rd, 8'h5A, "default read");

    // Write one byte and read it back using a repeated-start read.
    rw <= 1'b0;
    reg_addr <= 8'h12;
    data_wr <= 8'hA5;
    pulse_start;
    wait_done;
    if (ack_error) begin
        failures = failures + 1;
        $display("FAIL: unexpected ACK error during write");
    end

    rw <= 1'b1;
    reg_addr <= 8'h12;
    data_wr <= 8'h00;
    pulse_start;
    wait_done;
    if (ack_error) begin
        failures = failures + 1;
        $display("FAIL: unexpected ACK error during readback");
    end
    check_equal(data_rd, 8'hA5, "write/readback");
    check_equal(slave_out, 8'hA5, "slave mirror");

    if (failures == 0) begin
        $display("tbmast: PASS");
    end else begin
        $display("tbmast: FAIL (%0d failures)", failures);
        $fatal(1);
    end
end

endmodule
