`timescale 1ns/1ps
// Fixed 8-line x 4-word storage. Only metadata needs reset.
module cacheguard_array #(
    parameter ENABLE_PARITY = 1
) (
    input wire clk,
    input wire rst,
    input wire [2:0] lookup_index,
    input wire [24:0] lookup_tag,
    input wire [1:0] lookup_word,
    output wire tag_hit,
    output wire [31:0] read_data,
    output wire parity_bad,
    input wire invalidate,
    input wire write_word,
    input wire [1:0] refill_word,
    input wire [31:0] refill_data,
    input wire commit_line
);
    reg [7:0] valid;
    reg [24:0] tags [0:7];
    reg [31:0] data [0:31];
    wire [4:0] read_slot = {lookup_index, lookup_word};
    wire [4:0] write_slot = {lookup_index, refill_word};

    assign tag_hit = valid[lookup_index] && (tags[lookup_index] == lookup_tag);
    assign read_data = data[read_slot];

    generate
        if (ENABLE_PARITY != 0) begin : g_parity
            reg parity [0:31];
            assign parity_bad = (^read_data) ^ parity[read_slot];
            always @(posedge clk) begin
                if (!rst && write_word)
                    parity[write_slot] <= ^refill_data;
            end
        end else begin : g_no_parity
            assign parity_bad = 1'b0;
        end
    endgenerate

    always @(posedge clk) begin
        if (rst) begin
            valid <= 8'b0;
        end else begin
            if (invalidate)
                valid[lookup_index] <= 1'b0;
            if (write_word)
                data[write_slot] <= refill_data;
            if (commit_line) begin
                tags[lookup_index] <= lookup_tag;
                valid[lookup_index] <= 1'b1;
            end
        end
    end
endmodule
