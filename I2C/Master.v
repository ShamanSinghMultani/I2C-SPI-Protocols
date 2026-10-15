`timescale 1ns/1ps

module master
#(
    parameter CLK_DIVIDER = 8
)
(
    input clk,
    input rst_n,
    input start,
    input rw,
    input [6:0] address,
    input [7:0] reg_addr,
    input [7:0] data_wr,
    output reg [7:0] data_rd,
    output reg busy,
    output reg done,
    output reg ack_error,
    output reg scl,
    inout wire sda
);

localparam STATE_IDLE       = 4'd0;
localparam STATE_START      = 4'd1;
localparam STATE_SEND_AW    = 4'd2;
localparam STATE_ACK_AW     = 4'd3;
localparam STATE_SEND_REG   = 4'd4;
localparam STATE_ACK_REG    = 4'd5;
localparam STATE_SEND_DATA  = 4'd6;
localparam STATE_ACK_DATA   = 4'd7;
localparam STATE_RESTART    = 4'd8;
localparam STATE_SEND_AR    = 4'd9;
localparam STATE_ACK_AR     = 4'd10;
localparam STATE_READ_DATA  = 4'd11;
localparam STATE_SEND_NACK  = 4'd12;
localparam STATE_STOP       = 4'd13;

reg sda_drive_low;
reg [3:0] state;
reg [1:0] phase;
reg [2:0] bit_index;
reg [7:0] shifter;
reg [7:0] read_shift;
reg [15:0] clk_count;

reg rw_latched;
reg [6:0] address_latched;
reg [7:0] reg_addr_latched;
reg [7:0] data_wr_latched;

wire divider_hit;
wire sda_in;

assign divider_hit = (clk_count == (CLK_DIVIDER - 1));
assign sda = sda_drive_low ? 1'b0 : 1'bz;
assign sda_in = sda;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_rd <= 8'd0;
        busy <= 1'b0;
        done <= 1'b0;
        ack_error <= 1'b0;
        scl <= 1'b1;
        sda_drive_low <= 1'b0;
        state <= STATE_IDLE;
        phase <= 2'd0;
        bit_index <= 3'd7;
        shifter <= 8'd0;
        read_shift <= 8'd0;
        clk_count <= 16'd0;
        rw_latched <= 1'b0;
        address_latched <= 7'd0;
        reg_addr_latched <= 8'd0;
        data_wr_latched <= 8'd0;
    end else begin
        done <= 1'b0;

        if (busy) begin
            if (divider_hit) begin
                clk_count <= 16'd0;
            end else begin
                clk_count <= clk_count + 16'd1;
            end
        end else begin
            clk_count <= 16'd0;
        end

        if (!busy && start) begin
            busy <= 1'b1;
            ack_error <= 1'b0;
            data_rd <= 8'd0;
            scl <= 1'b1;
            sda_drive_low <= 1'b0;
            state <= STATE_START;
            phase <= 2'd0;
            bit_index <= 3'd7;
            read_shift <= 8'd0;
            rw_latched <= rw;
            address_latched <= address;
            reg_addr_latched <= reg_addr;
            data_wr_latched <= data_wr;
        end else if (busy && divider_hit) begin
            case (state)
                STATE_START: begin
                    case (phase)
                        2'd0: begin
                            scl <= 1'b1;
                            sda_drive_low <= 1'b0;
                            phase <= 2'd1;
                        end
                        2'd1: begin
                            scl <= 1'b1;
                            sda_drive_low <= 1'b1;
                            phase <= 2'd2;
                        end
                        2'd2: begin
                            scl <= 1'b0;
                            sda_drive_low <= 1'b1;
                            phase <= 2'd3;
                        end
                        default: begin
                            shifter <= {address_latched, 1'b0};
                            bit_index <= 3'd7;
                            phase <= 2'd0;
                            state <= STATE_SEND_AW;
                        end
                    endcase
                end

                STATE_SEND_AW,
                STATE_SEND_REG,
                STATE_SEND_DATA,
                STATE_SEND_AR: begin
                    case (phase)
                        2'd0: begin
                            scl <= 1'b0;
                            sda_drive_low <= ~shifter[bit_index];
                            phase <= 2'd1;
                        end
                        2'd1: begin
                            scl <= 1'b1;
                            phase <= 2'd2;
                        end
                        2'd2: begin
                            phase <= 2'd3;
                        end
                        default: begin
                            scl <= 1'b0;
                            if (bit_index == 3'd0) begin
                                bit_index <= 3'd7;
                                phase <= 2'd0;
                                case (state)
                                    STATE_SEND_AW: state <= STATE_ACK_AW;
                                    STATE_SEND_REG: state <= STATE_ACK_REG;
                                    STATE_SEND_DATA: state <= STATE_ACK_DATA;
                                    default: state <= STATE_ACK_AR;
                                endcase
                            end else begin
                                bit_index <= bit_index - 3'd1;
                                phase <= 2'd0;
                            end
                        end
                    endcase
                end

                STATE_ACK_AW,
                STATE_ACK_REG,
                STATE_ACK_DATA,
                STATE_ACK_AR: begin
                    case (phase)
                        2'd0: begin
                            scl <= 1'b0;
                            sda_drive_low <= 1'b0;
                            phase <= 2'd1;
                        end
                        2'd1: begin
                            scl <= 1'b1;
                            phase <= 2'd2;
                        end
                        2'd2: begin
                            if (sda_in) begin
                                ack_error <= 1'b1;
                            end
                            phase <= 2'd3;
                        end
                        default: begin
                            scl <= 1'b0;
                            phase <= 2'd0;
                            if (sda_in) begin
                                state <= STATE_STOP;
                            end else begin
                                case (state)
                                    STATE_ACK_AW: begin
                                        shifter <= reg_addr_latched;
                                        state <= STATE_SEND_REG;
                                    end
                                    STATE_ACK_REG: begin
                                        if (rw_latched) begin
                                            state <= STATE_RESTART;
                                        end else begin
                                            shifter <= data_wr_latched;
                                            state <= STATE_SEND_DATA;
                                        end
                                    end
                                    STATE_ACK_DATA: begin
                                        state <= STATE_STOP;
                                    end
                                    default: begin
                                        bit_index <= 3'd7;
                                        read_shift <= 8'd0;
                                        state <= STATE_READ_DATA;
                                    end
                                endcase
                            end
                        end
                    endcase
                end

                STATE_RESTART: begin
                    case (phase)
                        2'd0: begin
                            scl <= 1'b0;
                            sda_drive_low <= 1'b0;
                            phase <= 2'd1;
                        end
                        2'd1: begin
                            scl <= 1'b1;
                            sda_drive_low <= 1'b0;
                            phase <= 2'd2;
                        end
                        2'd2: begin
                            scl <= 1'b1;
                            sda_drive_low <= 1'b1;
                            phase <= 2'd3;
                        end
                        default: begin
                            scl <= 1'b0;
                            sda_drive_low <= 1'b1;
                            shifter <= {address_latched, 1'b1};
                            bit_index <= 3'd7;
                            phase <= 2'd0;
                            state <= STATE_SEND_AR;
                        end
                    endcase
                end

                STATE_READ_DATA: begin
                    case (phase)
                        2'd0: begin
                            scl <= 1'b0;
                            sda_drive_low <= 1'b0;
                            phase <= 2'd1;
                        end
                        2'd1: begin
                            scl <= 1'b1;
                            phase <= 2'd2;
                        end
                        2'd2: begin
                            read_shift[bit_index] <= sda_in;
                            phase <= 2'd3;
                        end
                        default: begin
                            scl <= 1'b0;
                            if (bit_index == 3'd0) begin
                                data_rd <= {read_shift[7:1], sda_in};
                                bit_index <= 3'd7;
                                phase <= 2'd0;
                                state <= STATE_SEND_NACK;
                            end else begin
                                bit_index <= bit_index - 3'd1;
                                phase <= 2'd0;
                            end
                        end
                    endcase
                end

                STATE_SEND_NACK: begin
                    case (phase)
                        2'd0: begin
                            scl <= 1'b0;
                            sda_drive_low <= 1'b0;
                            phase <= 2'd1;
                        end
                        2'd1: begin
                            scl <= 1'b1;
                            phase <= 2'd2;
                        end
                        2'd2: begin
                            phase <= 2'd3;
                        end
                        default: begin
                            scl <= 1'b0;
                            phase <= 2'd0;
                            state <= STATE_STOP;
                        end
                    endcase
                end

                STATE_STOP: begin
                    case (phase)
                        2'd0: begin
                            scl <= 1'b0;
                            sda_drive_low <= 1'b1;
                            phase <= 2'd1;
                        end
                        2'd1: begin
                            scl <= 1'b1;
                            sda_drive_low <= 1'b1;
                            phase <= 2'd2;
                        end
                        2'd2: begin
                            scl <= 1'b1;
                            sda_drive_low <= 1'b0;
                            phase <= 2'd3;
                        end
                        default: begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            scl <= 1'b1;
                            sda_drive_low <= 1'b0;
                            state <= STATE_IDLE;
                            phase <= 2'd0;
                        end
                    endcase
                end

                default: begin
                    state <= STATE_IDLE;
                    phase <= 2'd0;
                    busy <= 1'b0;
                    scl <= 1'b1;
                    sda_drive_low <= 1'b0;
                end
            endcase
        end
    end
end

endmodule
