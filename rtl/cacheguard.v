`timescale 1ns/1ps
// Blocking, read-only, word-aligned cache. Reset must also flush the memory peer.
module cacheguard #(
    parameter ENABLE_PARITY = 1
) (
    input wire clk,
    input wire rst,
    input wire cpu_req_valid,
    output wire cpu_req_ready,
    input wire [31:0] cpu_req_addr,
    output wire cpu_rsp_valid,
    input wire cpu_rsp_ready,
    output reg [31:0] cpu_rsp_data,
    output reg cpu_rsp_error,
    output wire mem_req_valid,
    input wire mem_req_ready,
    output wire [31:0] mem_req_addr,
    input wire mem_rsp_valid,
    output wire mem_rsp_ready,
    input wire [31:0] mem_rsp_data,
    output reg evt_hit,
    output reg evt_miss,
    output reg evt_parity_error,
    output reg evt_refill_done
);
    localparam [2:0] IDLE=3'd0, LOOKUP=3'd1, MEM_REQ=3'd2,
                     MEM_WAIT=3'd3, VERIFY=3'd4, RESP=3'd5;
    reg [2:0] state;
    reg [31:0] addr_q;
    reg [1:0] beat;
    wire tag_hit, parity_bad;
    wire [31:0] cached_data;
    wire lookup_failure = (state == LOOKUP) && (addr_q[1:0] == 0) &&
                          (!tag_hit || parity_bad);
    wire verify_failure = (state == VERIFY) && (!tag_hit || parity_bad);
    wire invalidate = !rst && (lookup_failure || verify_failure);
    wire write_word = !rst && (state == MEM_WAIT) && mem_rsp_valid;
    wire commit_line = write_word && (beat == 2'd3);

    assign cpu_req_ready = !rst && (state == IDLE);
    assign cpu_rsp_valid = !rst && (state == RESP);
    assign mem_req_valid = !rst && (state == MEM_REQ);
    assign mem_req_addr = {addr_q[31:4], beat, 2'b00};
    assign mem_rsp_ready = !rst && (state == MEM_WAIT);

    cacheguard_array #(.ENABLE_PARITY(ENABLE_PARITY)) u_array (
        .clk(clk), .rst(rst), .lookup_index(addr_q[6:4]),
        .lookup_tag(addr_q[31:7]), .lookup_word(addr_q[3:2]),
        .tag_hit(tag_hit), .read_data(cached_data), .parity_bad(parity_bad),
        .invalidate(invalidate), .write_word(write_word), .refill_word(beat),
        .refill_data(mem_rsp_data), .commit_line(commit_line)
    );

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            addr_q <= 0;
            beat <= 0;
            cpu_rsp_data <= 0;
            cpu_rsp_error <= 0;
            evt_hit <= 0;
            evt_miss <= 0;
            evt_parity_error <= 0;
            evt_refill_done <= 0;
        end else begin
            evt_hit <= 0;
            evt_miss <= 0;
            evt_parity_error <= 0;
            evt_refill_done <= 0;
            case (state)
                IDLE: begin
                    if (cpu_req_valid) begin
                        addr_q <= cpu_req_addr;
                        cpu_rsp_error <= 0;
                        state <= LOOKUP;
                    end
                end
                LOOKUP: begin
                    if (addr_q[1:0] != 0) begin
                        cpu_rsp_data <= 0;
                        cpu_rsp_error <= 1;
                        state <= RESP;
                    end else begin
                        evt_hit <= tag_hit;
                        evt_miss <= !tag_hit;
                        if (tag_hit && !parity_bad) begin
                            cpu_rsp_data <= cached_data;
                            state <= RESP;
                        end else begin
                            evt_parity_error <= tag_hit && parity_bad;
                            beat <= 0;
                            state <= MEM_REQ;
                        end
                    end
                end
                MEM_REQ: begin
                    if (mem_req_ready)
                        state <= MEM_WAIT;
                end
                MEM_WAIT: begin
                    if (mem_rsp_valid) begin
                        if (beat == 2'd3) begin
                            evt_refill_done <= 1;
                            state <= VERIFY;
                        end else begin
                            beat <= beat + 1'b1;
                            state <= MEM_REQ;
                        end
                    end
                end
                VERIFY: begin
                    // Recheck the requested word, including faults during refill.
                    if (tag_hit && !parity_bad) begin
                        cpu_rsp_data <= cached_data;
                        state <= RESP;
                    end else begin
                        evt_parity_error <= tag_hit && parity_bad;
                        beat <= 0;
                        state <= MEM_REQ;
                    end
                end
                RESP: begin
                    if (cpu_rsp_ready)
                        state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
