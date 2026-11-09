`timescale 1ns/1ps
// Fault-free workload sweep. The main regression owns fault/reset/stall testing.
module tb_workloads;
    parameter ENABLE_PARITY=1;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, cpu_req_valid=0;
    wire cpu_rsp_ready=1'b1;
    reg [31:0] cpu_req_addr=0;
    wire cpu_req_ready,cpu_rsp_valid,cpu_rsp_error;
    wire [31:0] cpu_rsp_data;
    wire mem_req_valid,mem_req_ready,mem_rsp_valid,mem_rsp_ready;
    wire [31:0] mem_req_addr,mem_rsp_data;
    wire evt_hit,evt_miss,evt_parity_error,evt_refill_done;
    integer latency_cycles=1;
    cacheguard #(.ENABLE_PARITY(ENABLE_PARITY)) dut (.*);
    backing_memory mem (
        .clk(clk),.rst(rst),.req_valid(mem_req_valid),.req_ready(mem_req_ready),
        .req_addr(mem_req_addr),.rsp_valid(mem_rsp_valid),.rsp_ready(mem_rsp_ready),
        .rsp_data(mem_rsp_data),.latency_cycles(latency_cycles),
        .jitter_cycles(0),.stall_period(0),.block_requests(1'b0)
    );

    function automatic [31:0] golden(input reg [31:0] address);
        reg [63:0] product;
        begin
            product={32'b0,address}*64'h9e3779b1;
            golden=product[31:0]^(address<<16)^(address>>16)^32'hc0decafe;
        end
    endfunction
    function automatic [31:0] random_next(input reg [31:0] s);
        reg [31:0] x;
        begin x=s^(s<<13); x=x^(x>>17); random_next=x^(x<<5); end
    endfunction

    reg [7:0] valid_model=0;
    reg [24:0] tag_model [0:7];
    reg outstanding=0,expected_hit;
    reg [31:0] expected_addr;
    integer cycle=0,start_cycle,hits=0,misses=0,completed=0;
    integer memory_reads=0,refills=0,cycle_sum=0,expected_cycles,reads_before;

    always @(posedge clk) begin
        cycle++;
        if (!rst) begin
            if (cpu_req_valid && cpu_req_ready) begin
                assert (!outstanding) else $fatal(1,"Duplicate workload request");
                outstanding=1;
                expected_addr=cpu_req_addr;
                expected_hit=valid_model[cpu_req_addr[6:4]] &&
                             tag_model[cpu_req_addr[6:4]]==cpu_req_addr[31:7];
                expected_cycles=expected_hit?2:4*(latency_cycles+2)+3;
                start_cycle=cycle;
                reads_before=memory_reads;
            end
            if (evt_hit || evt_miss)
                assert (outstanding && evt_hit==expected_hit && evt_miss==!expected_hit)
                    else $fatal(1,"Workload reference tag classification mismatch");
            if (evt_hit) hits++;
            if (evt_miss) misses++;
            if (evt_refill_done) refills++;
            assert (!evt_parity_error) else $fatal(1,"Unexpected fault-free parity event");
            if (mem_req_valid && mem_req_ready) memory_reads++;
            if (cpu_rsp_valid) begin
                assert (outstanding && !cpu_rsp_error && cpu_rsp_data===golden(expected_addr))
                    else $fatal(1,"Workload golden-data mismatch");
                assert (cycle-start_cycle==expected_cycles)
                    else $fatal(1,"Workload latency differs from analytic expectation");
                assert (memory_reads-reads_before==(expected_hit?0:4))
                    else $fatal(1,"Wrong workload memory traffic");
                cycle_sum+=cycle-start_cycle;
                valid_model[expected_addr[6:4]]=1;
                tag_model[expected_addr[6:4]]=expected_addr[31:7];
                completed++;
                outstanding=0;
            end
        end
    end

    integer pattern_id=0,n,fd;
    reg [31:0] rng=32'd2026;
    string metrics_path;
    initial begin
        if ($value$plusargs("pattern=%d",pattern_id)) begin end
        if ($value$plusargs("latency=%d",latency_cycles)) begin end
        if (!$value$plusargs("metrics=%s",metrics_path)) metrics_path="build/workload.json";
        assert (pattern_id>=0 && pattern_id<=3 && latency_cycles>=1)
            else $fatal(1,"Invalid workload configuration");
        repeat (3) @(negedge clk); rst=0;
        for (n=0;n<256;n++) begin
            @(negedge clk);
            case (pattern_id)
                0: cpu_req_addr=0;
                1: cpu_req_addr=n*4;
                2: cpu_req_addr=(n%2)*128;
                3: begin rng=random_next(rng); cpu_req_addr=rng & 32'hffc; end
            endcase
            cpu_req_valid=1;
            do @(posedge clk); while (!cpu_req_ready);
            @(negedge clk); cpu_req_valid=0;
            while (completed<n+1) @(negedge clk);
        end
        assert (completed==256 && hits+misses==256 && refills==misses && memory_reads==4*misses)
            else $fatal(1,"Workload conservation check failed");
        fd=$fopen(metrics_path,"w");
        if (!fd) $fatal(1,"Cannot write workload metrics");
        $fdisplay(fd,"{\"pass\":true,\"parity\":%0d,\"pattern\":%0d,\"memory_delay\":%0d,\"reads\":%0d,\"hits\":%0d,\"misses\":%0d,\"cycle_sum\":%0d,\"memory_reads\":%0d}",ENABLE_PARITY,pattern_id,latency_cycles,completed,hits,misses,cycle_sum,memory_reads);
        $fclose(fd);
        $display("PASS workload parity=%0d pattern=%0d delay=%0d hits=%0d misses=%0d cycle_sum=%0d",ENABLE_PARITY,pattern_id,latency_cycles,hits,misses,cycle_sum);
        $finish;
    end
    initial begin #2000000; $fatal(1,"Workload watchdog"); end
endmodule
