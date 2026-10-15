`timescale 1ns/1ps

module slave
#(
    parameter [6:0] SLAVE_ADDRESS = 7'h52
)
(
    input clk,
    input rst_n,
    input scl,
    inout wire sda,
    output reg [7:0] out
);

localparam STATE_IDLE          = 3'd0;
localparam STATE_RX_ADDRESS    = 3'd1;
localparam STATE_RX_REGISTER   = 3'd2;
localparam STATE_RX_WRITE      = 3'd3;
localparam STATE_TX_READ       = 3'd4;
localparam STATE_WAIT_RD_ACK   = 3'd5;

reg [2:0] state;
reg [2:0] next_state;
reg [2:0] bit_index;
reg [7:0] rx_shift;
reg [7:0] tx_shift;
reg [7:0] reg_ptr;
reg [7:0] assembled_byte;
reg sda_drive_low;
reg ack_pending;
reg ack_active;
reg ack_drive_low;
reg tx_last;

reg scl_q;
reg sda_q;

reg [7:0] storage [0:255];
integer init_i;

wire sda_in;
assign sda = sda_drive_low ? 1'b0 : 1'bz;
assign sda_in = sda;

initial begin
    for (init_i = 0; init_i < 256; init_i = init_i + 1) begin
        storage[init_i] = 8'd0;
    end
    storage[8'h10] = 8'h5A;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= STATE_IDLE;
        next_state <= STATE_IDLE;
        bit_index <= 3'd7;
        rx_shift <= 8'd0;
        tx_shift <= 8'd0;
        reg_ptr <= 8'd0;
        assembled_byte <= 8'd0;
        sda_drive_low <= 1'b0;
        ack_pending <= 1'b0;
        ack_active <= 1'b0;
        ack_drive_low <= 1'b0;
        tx_last <= 1'b0;
        scl_q <= 1'b1;
        sda_q <= 1'b1;
        out <= 8'd0;
    end else begin
        if (scl_q && !sda_in && sda_q) begin
            state <= STATE_RX_ADDRESS;
            next_state <= STATE_IDLE;
            bit_index <= 3'd7;
            rx_shift <= 8'd0;
            ack_pending <= 1'b0;
            ack_active <= 1'b0;
            tx_last <= 1'b0;
            sda_drive_low <= 1'b0;
        end else if (scl_q && sda_in && !sda_q) begin
            state <= STATE_IDLE;
            next_state <= STATE_IDLE;
            ack_pending <= 1'b0;
            ack_active <= 1'b0;
            sda_drive_low <= 1'b0;
        end else if (!scl_q && scl) begin
            case (state)
                STATE_RX_ADDRESS,
                STATE_RX_REGISTER,
                STATE_RX_WRITE: begin
                    assembled_byte = {rx_shift[6:0], sda_in};
                    rx_shift <= assembled_byte;

                    if (bit_index == 3'd0) begin
                        case (state)
                            STATE_RX_ADDRESS: begin
                                ack_pending <= 1'b1;
                                ack_drive_low <= (assembled_byte[7:1] == SLAVE_ADDRESS);
                                if (assembled_byte[7:1] == SLAVE_ADDRESS) begin
                                    if (assembled_byte[0]) begin
                                        next_state <= STATE_TX_READ;
                                        tx_shift <= storage[reg_ptr];
                                        out <= storage[reg_ptr];
                                    end else begin
                                        next_state <= STATE_RX_REGISTER;
                                    end
                                end else begin
                                    next_state <= STATE_IDLE;
                                end
                                bit_index <= 3'd7;
                                rx_shift <= 8'd0;
                            end

                            STATE_RX_REGISTER: begin
                                reg_ptr <= assembled_byte;
                                out <= storage[assembled_byte];
                                ack_pending <= 1'b1;
                                ack_drive_low <= 1'b1;
                                next_state <= STATE_RX_WRITE;
                                bit_index <= 3'd7;
                                rx_shift <= 8'd0;
                            end

                            default: begin
                                storage[reg_ptr] <= assembled_byte;
                                out <= assembled_byte;
                                reg_ptr <= reg_ptr + 8'd1;
                                ack_pending <= 1'b1;
                                ack_drive_low <= 1'b1;
                                next_state <= STATE_RX_WRITE;
                                bit_index <= 3'd7;
                                rx_shift <= 8'd0;
                            end
                        endcase
                    end else begin
                        bit_index <= bit_index - 3'd1;
                    end
                end

                STATE_TX_READ: begin
                    // tx_last marks that bit 0 has been driven, so this rising
                    // edge is the master's sample of the final bit.
                    if (tx_last) begin
                        state <= STATE_WAIT_RD_ACK;
                    end
                end

                STATE_WAIT_RD_ACK: begin
                    if (!sda_in) begin
                        reg_ptr <= reg_ptr + 8'd1;
                        tx_shift <= storage[reg_ptr + 8'd1];
                        out <= storage[reg_ptr + 8'd1];
                        bit_index <= 3'd7;
                        tx_last <= 1'b0;
                        state <= STATE_TX_READ;
                    end else begin
                        state <= STATE_IDLE;
                    end
                end

                default: begin
                end
            endcase
        end else if (scl_q && !scl) begin
            if (ack_active) begin
                ack_active <= 1'b0;
                state <= next_state;
                rx_shift <= 8'd0;
                tx_last <= 1'b0;
                // The first bit of a read byte must already be on the bus during
                // the SCL-low period that follows the address ACK. Releasing sda
                // here and waiting for the next falling edge makes the master
                // sample the idle-high line as the MSB.
                if (next_state == STATE_TX_READ) begin
                    sda_drive_low <= ~tx_shift[3'd7];
                    bit_index <= 3'd6;
                end else begin
                    sda_drive_low <= 1'b0;
                    bit_index <= 3'd7;
                end
            end else if (ack_pending) begin
                sda_drive_low <= ack_drive_low;
                ack_active <= 1'b1;
                ack_pending <= 1'b0;
            end else if (state == STATE_TX_READ) begin
                sda_drive_low <= ~tx_shift[bit_index];
                if (bit_index != 3'd0) begin
                    bit_index <= bit_index - 3'd1;
                end else begin
                    tx_last <= 1'b1;
                end
            end else if (state == STATE_WAIT_RD_ACK) begin
                sda_drive_low <= 1'b0;
            end
        end

        scl_q <= scl;
        sda_q <= sda_in;
    end
end

endmodule
