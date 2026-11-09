`timescale 1ns/1ps
// Expected-failure demonstrations, separate from the always-correct scoreboard.
module tb_protection_limits;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, req_valid=0, rsp_ready=0;
    reg [31:0] req_addr=0;
    wire [1:0] req_ready, rsp_valid, rsp_error;
    wire [31:0] rsp_data [0:1];
    integer detections [0:1];
    genvar g;
    generate for (g=0;g<2;g=g+1) begin : variants
        wire mem_req_valid,mem_req_ready,mem_rsp_valid,mem_rsp_ready;
        wire [31:0] mem_req_addr,mem_rsp_data;
        wire hit,miss,err,refill;
        cacheguard #(.ENABLE_PARITY(g)) dut (
            .clk(clk),.rst(rst),.cpu_req_valid(req_valid),.cpu_req_ready(req_ready[g]),
            .cpu_req_addr(req_addr),.cpu_rsp_valid(rsp_valid[g]),.cpu_rsp_ready(rsp_ready),
            .cpu_rsp_data(rsp_data[g]),.cpu_rsp_error(rsp_error[g]),
            .mem_req_valid(mem_req_valid),.mem_req_ready(mem_req_ready),.mem_req_addr(mem_req_addr),
            .mem_rsp_valid(mem_rsp_valid),.mem_rsp_ready(mem_rsp_ready),.mem_rsp_data(mem_rsp_data),
            .evt_hit(hit),.evt_miss(miss),.evt_parity_error(err),.evt_refill_done(refill)
        );
        backing_memory mem (
            .clk(clk),.rst(rst),.req_valid(mem_req_valid),.req_ready(mem_req_ready),.req_addr(mem_req_addr),
            .rsp_valid(mem_rsp_valid),.rsp_ready(mem_rsp_ready),.rsp_data(mem_rsp_data),
            .latency_cycles(2),.jitter_cycles(0),.stall_period(0),.block_requests(1'b0)
        );
        always @(posedge clk) begin
            if (rst) detections[g]<=0;
            else if (err) detections[g]<=detections[g]+1;
        end
    end endgenerate

    task automatic launch_read;
        begin
            @(negedge clk);
            assert (&req_ready) else $fatal(1,"Both variants must be idle");
            req_valid=1;
            @(negedge clk); req_valid=0;
            while (!(&rsp_valid)) @(negedge clk);
            assert (rsp_error==0) else $fatal(1,"Unexpected response error");
        end
    endtask
    task automatic finish_read;
        begin
            rsp_ready=1;
            @(negedge clk); rsp_ready=0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk); rst=0;
        launch_read();
        assert (rsp_data[0]==32'hc0decafe && rsp_data[1]==32'hc0decafe)
            else $fatal(1,"Warm-up data mismatch");
        finish_read();
        variants[0].dut.u_array.data[0] ^= 32'h1;
        variants[1].dut.u_array.data[0] ^= 32'h1;
        launch_read();
        assert (rsp_data[0]==(32'hc0decafe^32'h1) && rsp_data[1]==32'hc0decafe)
            else $fatal(1,"Single-bit baseline/protection demonstration failed");
        assert (detections[0]==0 && detections[1]==1) else $fatal(1,"Detection count mismatch");
        $display("PASS limitation: baseline silently returns a single-bit-corrupted word; protected variant recovers");
        finish_read();
        variants[1].dut.u_array.g_parity.parity[0] ^= 1'b1;
        launch_read();
        assert (rsp_data[1]==32'hc0decafe && detections[1]==2)
            else $fatal(1,"Parity-bit-only error did not trigger recovery");
        $display("PASS parity-bit-only fault detection and recovery");
        finish_read();
        variants[1].dut.u_array.data[0] ^= 32'h3;
        launch_read();
        assert (rsp_data[1]==(32'hc0decafe^32'h3) && detections[1]==2)
            else $fatal(1,"Even-bit limitation demonstration failed");
        $display("PASS limitation: two flipped bits in one word preserve parity and are undetected");
        finish_read();
        $display("PASS protection limits (3 scenarios)");
        $finish;
    end
    initial begin #100000; $fatal(1,"Limits watchdog timeout"); end
endmodule
