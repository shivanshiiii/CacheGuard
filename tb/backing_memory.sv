`timescale 1ns/1ps
// Simulation-only deterministic ROM, one outstanding request, reproducible stalls.
module backing_memory (
    input logic clk, rst,
    input logic req_valid,
    output logic req_ready,
    input logic [31:0] req_addr,
    output logic rsp_valid,
    input logic rsp_ready,
    output logic [31:0] rsp_data,
    input integer latency_cycles,
    input integer jitter_cycles,
    input integer stall_period,
    input logic block_requests
);
    logic busy;
    logic [31:0] addr_q;
    integer remaining, tick, serial;

    function automatic [31:0] rom_word(input logic [31:0] byte_address);
        logic [31:0] aligned, rotated;
        begin
            aligned = {byte_address[31:2], 2'b00};
            rotated = {aligned[15:0], aligned[31:16]};
            rom_word = (aligned * 32'h9e3779b1) ^ rotated ^ 32'hc0decafe;
        end
    endfunction

    always_comb begin
        req_ready = !rst && !busy && !rsp_valid && !block_requests;
        if ((stall_period > 0) && ((tick % stall_period) == 0))
            req_ready = 0;
    end

    always @(posedge clk) begin
        if (rst) begin
            busy <= 0;
            rsp_valid <= 0;
            rsp_data <= 0;
            addr_q <= 0;
            remaining <= 0;
            tick <= 0;
            serial <= 0;
        end else begin
            tick <= tick + 1;
            if (rsp_valid && rsp_ready)
                rsp_valid <= 0;
            if (req_valid && req_ready) begin
                assert (req_addr[1:0] == 0) else $fatal(1, "Unaligned memory request");
                assert (latency_cycles >= 1 && jitter_cycles >= 0)
                    else $fatal(1, "Bad memory latency configuration");
                addr_q <= req_addr;
                remaining <= latency_cycles - 1 +
                             ((jitter_cycles > 0) ? (serial % (jitter_cycles+1)) : 0);
                serial <= serial + 1;
                busy <= 1;
            end else if (busy) begin
                if (remaining == 0) begin
                    rsp_data <= rom_word(addr_q);
                    rsp_valid <= 1;
                    busy <= 0;
                end else remaining <= remaining - 1;
            end
        end
    end
endmodule
