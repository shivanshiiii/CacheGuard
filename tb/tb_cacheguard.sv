`timescale 1ns/1ps
module tb_cacheguard;
    parameter ENABLE_PARITY = 1;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, cpu_req_valid=0, cpu_rsp_ready=0;
    reg [31:0] cpu_req_addr=0;
    wire cpu_req_ready, cpu_rsp_valid, cpu_rsp_error;
    wire [31:0] cpu_rsp_data;
    wire mem_req_valid, mem_req_ready, mem_rsp_valid, mem_rsp_ready;
    wire [31:0] mem_req_addr, mem_rsp_data;
    wire evt_hit, evt_miss, evt_parity_error, evt_refill_done;
    integer latency_cycles=1, jitter_cycles=0, stall_period=0;
    reg block_requests=0;
    cacheguard #(.ENABLE_PARITY(ENABLE_PARITY)) dut (.*);
    backing_memory mem (
        .clk(clk), .rst(rst), .req_valid(mem_req_valid), .req_ready(mem_req_ready),
        .req_addr(mem_req_addr), .rsp_valid(mem_rsp_valid), .rsp_ready(mem_rsp_ready),
        .rsp_data(mem_rsp_data), .latency_cycles(latency_cycles),
        .jitter_cycles(jitter_cycles), .stall_period(stall_period),
        .block_requests(block_requests)
    );

    // Independent reference calculation: no calls into the memory model or DUT.
    function automatic [31:0] reference_word(input reg [31:0] a);
        reg [63:0] product;
        reg [31:0] aligned;
        begin
            aligned = (a >> 2) << 2;
            product = {32'b0, aligned} * 64'h000000009e3779b1;
            reference_word = product[31:0] ^ ((aligned << 16) | (aligned >> 16)) ^ 32'hc0decafe;
        end
    endfunction

    integer cycle=0, accepted=0, completed=0, aborted=0;
    integer hits=0, misses=0, errors=0, refills=0, memory_reads=0;
    integer first_latency_sum=0, completion_latency_sum=0, aligned_done=0;
    integer pending_start, pending_words, pending_detection, pending_refills;
    integer recovery_sum=0, recovery_count=0, recovery_max=0;
    integer cpu_stall_cycles=0, mem_stall_cycles=0, rsp_stall_cycles=0;
    integer monitored_cycles=0, faults_injected=0, resets_checked=0;
    integer last_first_latency=0;
    reg pending=0, first_seen=0, mem_outstanding=0;
    reg [31:0] pending_addr;
    reg pending_hit;
    reg [7:0] model_valid=0;
    reg [24:0] model_tags [0:7];
    reg [5:0] state_coverage=0;
    reg [31:0] word_coverage=0, bit_coverage=0;
    reg [1023:0] fault_coverage=0;
    reg prev_cpu_stall=0, prev_mem_stall=0, prev_rsp_stall=0;
    reg [31:0] held_cpu_addr, held_mem_addr, held_rsp_data;
    reg held_rsp_error;
    integer idx, latency;

    // Immediate SystemVerilog assertions are supported by Icarus -g2012.
    // Sampling before NBA updates measures transfers exactly at clock edges.
    always @(posedge clk) begin
        cycle = cycle + 1;
        if (rst) begin
            if (pending) aborted = aborted + 1;
            pending=0;
            mem_outstanding=0;
            model_valid=0;
            prev_cpu_stall=0;
            prev_mem_stall=0;
            prev_rsp_stall=0;
            assert (!cpu_req_ready && !cpu_rsp_valid && !mem_req_valid && !mem_rsp_ready)
                else $fatal(1, "Handshake active during reset");
        end else begin
            monitored_cycles++;
            assert (dut.state <= 5) else $fatal(1, "Illegal FSM state");
            state_coverage[dut.state]=1;
            if (prev_cpu_stall)
                assert (cpu_req_valid && cpu_req_addr===held_cpu_addr)
                    else $fatal(1, "CPU producer changed a stalled request");
            if (prev_mem_stall)
                assert (mem_req_valid && mem_req_addr===held_mem_addr)
                    else $fatal(1, "Memory request not held under backpressure");
            if (prev_rsp_stall)
                assert (cpu_rsp_valid && cpu_rsp_data===held_rsp_data && cpu_rsp_error===held_rsp_error)
                    else $fatal(1, "CPU response changed under backpressure");
            prev_cpu_stall = cpu_req_valid && !cpu_req_ready;
            prev_mem_stall = mem_req_valid && !mem_req_ready;
            prev_rsp_stall = cpu_rsp_valid && !cpu_rsp_ready;
            held_cpu_addr=cpu_req_addr;
            held_mem_addr=mem_req_addr;
            held_rsp_data=cpu_rsp_data;
            held_rsp_error=cpu_rsp_error;
            if (prev_cpu_stall) cpu_stall_cycles++;
            if (prev_mem_stall) mem_stall_cycles++;
            if (prev_rsp_stall) rsp_stall_cycles++;
            if (cpu_req_valid && cpu_req_ready) begin
                assert (!pending) else $fatal(1, "More than one outstanding CPU request");
                pending=1;
                first_seen=0;
                pending_addr=cpu_req_addr;
                pending_start=cycle;
                pending_words=0;
                pending_refills=0;
                pending_detection=-1;
                idx=cpu_req_addr[6:4];
                pending_hit=model_valid[idx] && (model_tags[idx]==cpu_req_addr[31:7]);
                accepted++;
                if (cpu_req_addr[1:0]==0) word_coverage[cpu_req_addr[6:2]]=1;
            end
            if (evt_hit || evt_miss) begin
                assert (pending && pending_addr[1:0]==0)
                    else $fatal(1, "Unexpected classification event");
                assert (evt_hit == pending_hit && evt_miss == !pending_hit)
                    else $fatal(1, "Tag classification disagrees with reference cache");
            end
            if (evt_hit) hits++;
            if (evt_miss) misses++;
            if (evt_parity_error) begin
                errors++;
                assert (ENABLE_PARITY && pending && !cpu_rsp_valid)
                    else $fatal(1, "Parity failure returned a response");
                if (pending_detection < 0) pending_detection=cycle;
            end
            if (evt_refill_done) begin
                refills++;
                pending_refills++;
            end
            if (mem_req_valid && mem_req_ready) begin
                assert (pending && !mem_outstanding && pending_addr[1:0]==0)
                    else $fatal(1, "Unexpected memory request");
                assert (mem_req_addr == ((pending_addr & 32'hfffffff0) + ((pending_words % 4)*4)))
                    else $fatal(1, "Refill order/address mismatch");
                mem_outstanding=1;
                memory_reads++;
                pending_words++;
            end
            if (mem_rsp_valid && mem_rsp_ready) begin
                assert (mem_outstanding) else $fatal(1, "Unexpected memory response");
                mem_outstanding=0;
            end
            if (cpu_rsp_valid) begin
                assert (pending && !mem_outstanding) else $fatal(1, "Unsolicited CPU response");
                assert (cpu_rsp_error === (pending_addr[1:0]!=0))
                    else $fatal(1, "Wrong alignment error status");
                if (pending_addr[1:0]==0) begin
                    assert (cpu_rsp_data === reference_word(pending_addr))
                        else $fatal(1, "DATA MISMATCH addr=%h got=%h expected=%h", pending_addr,
                                    cpu_rsp_data, reference_word(pending_addr));
                    assert ((pending_words % 4)==0 && (pending_hit || pending_words>=4))
                        else $fatal(1, "Response before complete line refill");
                    assert (pending_refills == pending_words/4)
                        else $fatal(1, "Refill completion count mismatch");
                end else assert (pending_words==0 && cpu_rsp_data==0)
                    else $fatal(1, "Misaligned access touched memory");
                if (!first_seen) begin
                    latency=cycle-pending_start;
                    last_first_latency=latency;
                    first_latency_sum+=latency;
                    if (pending_detection >= 0) begin
                        latency=cycle-pending_detection;
                        recovery_sum+=latency;
                        recovery_count++;
                        if (latency>recovery_max) recovery_max=latency;
                    end
                    first_seen=1;
                end
                if (cpu_rsp_ready) begin
                    completion_latency_sum+=cycle-pending_start;
                    completed++;
                    if (pending_addr[1:0]==0) begin
                        aligned_done++;
                        model_valid[pending_addr[6:4]]=1;
                        model_tags[pending_addr[6:4]]=pending_addr[31:7];
                    end
                    pending=0;
                end
            end
        end
    end

    task automatic reset_all;
        begin
            @(negedge clk);
            rst=1; cpu_req_valid=0; cpu_rsp_ready=0; block_requests=0;
            repeat (3) @(negedge clk);
            rst=0;
            @(negedge clk);
        end
    endtask

    task automatic read_one(input reg [31:0] addr, input integer hold_cycles,
                            input integer expected_reads, input integer expected_errors);
        integer m0,e0,c0;
        begin
            @(negedge clk);
            m0=memory_reads; e0=errors; c0=completed;
            cpu_req_addr=addr; cpu_req_valid=1; cpu_rsp_ready=0;
            do @(posedge clk); while (!cpu_req_ready);
            @(negedge clk); cpu_req_valid=0;
            while (!cpu_rsp_valid) @(negedge clk);
            repeat (hold_cycles) @(negedge clk);
            cpu_rsp_ready=1;
            @(negedge clk); cpu_rsp_ready=0;
            assert (completed==c0+1) else $fatal(1, "Driver did not complete read");
            if (expected_reads>=0)
                assert (memory_reads-m0==expected_reads)
                    else $fatal(1, "Memory reads at %h: got %0d expected %0d",addr,memory_reads-m0,expected_reads);
            if (expected_errors>=0)
                assert (errors-e0==expected_errors)
                    else $fatal(1, "Parity event count at %h",addr);
        end
    endtask

    // Keep req_valid continuously high: producer changes address only after acceptance.
    task automatic stream_reads(input integer count);
        integer n,c0;
        begin
            @(negedge clk); c0=completed; cpu_rsp_ready=1; cpu_req_valid=1;
            for (n=0;n<count;n++) begin
                cpu_req_addr=32'h80000000+((n%64)*4);
                do @(posedge clk); while (!cpu_req_ready);
                @(negedge clk);
            end
            cpu_req_valid=0;
            while (completed<c0+count) @(negedge clk);
            cpu_rsp_ready=0;
        end
    endtask

    task automatic reset_in_state(input integer target, input integer target_beat);
        integer c0,a0;
        begin
            reset_all();
            c0=completed; a0=aborted;
            @(negedge clk);
            if (target==2) block_requests=1;
            cpu_req_valid=1; cpu_req_addr=32'habcdef70; cpu_rsp_ready=0;
            do @(posedge clk); while (!cpu_req_ready);
            @(negedge clk); cpu_req_valid=0;
            while (!(dut.state==target && ((target!=3) || dut.beat==target_beat))) @(negedge clk);
            // Coordinated reset cancels the accepted request and any memory response.
            rst=1; cpu_req_valid=0; cpu_rsp_ready=0; block_requests=0;
            repeat (3) @(negedge clk);
            rst=0;
            repeat (12) @(negedge clk);
            assert (completed==c0 && aborted==a0+1 && !cpu_rsp_valid)
                else $fatal(1, "Reset did not cancel pending transaction");
            read_one(32'habcdef70,0,4,0);
            resets_checked++;
        end
    endtask

    reg [31:0] rng=32'h12345678;
    function automatic [31:0] next_random(input reg [31:0] s);
        reg [31:0] x;
        begin
            x=s^(s<<13); x=x^(x>>17); next_random=x^(x<<5);
        end
    endfunction

    integer seed=1, random_count=1000, n,b,slot,c0,e0,m0;
    integer bench_hits,bench_misses,bench_first,bench_completion,bench_reads,bench_done;
    integer fd, bench_n=1000;
    reg [31:0] a;
    string metrics_path, wave_path;

    initial begin
        if ($value$plusargs("seed=%d",seed)) begin end
        rng=seed; if (rng==0) rng=1;
        if ($value$plusargs("random=%d",random_count)) begin end
        if (!$value$plusargs("metrics=%s",metrics_path)) metrics_path="build/metrics.json";
        if ($value$plusargs("vcd=%s",wave_path)) begin
            $dumpfile(wave_path); $dumpvars(0,tb_cacheguard);
        end
        reset_all();
        $display("TEST cold miss, spatial hits, index sweep, conflicts, address extremes");
        read_one(0,0,4,0);
        assert (last_first_latency==15) else $fatal(1,"Cold-miss timing changed");
        read_one(4,0,0,0);
        assert (last_first_latency==2) else $fatal(1,"Hit timing changed");
        read_one(8,0,0,0); read_one(12,0,0,0);
        for (n=1;n<8;n++) read_one(n*16,0,4,0);
        for (n=0;n<32;n++) read_one(n*4,0,0,0);
        read_one(32'h80,0,4,0); read_one(0,0,4,0);
        read_one(32'hfffffffc,0,4,0); read_one(32'h80000000,0,4,0);
        read_one(32'h00000000,0,4,0);
        for (n=1;n<=3;n++) read_one(n,0,0,0);

        $display("TEST CPU backpressure and continuous-valid requests");
        read_one(0,8,0,0); read_one(32'h400,5,4,0);
        stream_reads(64);
        $display("TEST memory latency 1/2/7 plus jitter and request stalls");
        for (n=0;n<3;n++) begin
            latency_cycles=(n==2)?7:n+1; jitter_cycles=n; stall_period=3;
            read_one(32'h1000+n*128,3,4,0);
        end

        $display("TEST coordinated reset in LOOKUP/MEM_REQ/all refill beats/VERIFY/RESP");
        latency_cycles=3; jitter_cycles=0; stall_period=0;
        reset_in_state(1,0); reset_in_state(2,0);
        for (n=0;n<4;n++) reset_in_state(3,n);
        reset_in_state(4,0); reset_in_state(5,0);

        if (ENABLE_PARITY) begin
            $display("TEST all 1024 cache data bit positions, one transient fault at a time");
            latency_cycles=2; jitter_cycles=2; stall_period=3;
            for (slot=0;slot<32;slot++) begin
                a=32'h2000+slot*4;
                for (b=0;b<32;b++) begin
                    read_one(a,0,-1,0);
                    @(negedge clk);
                    dut.u_array.data[slot]=dut.u_array.data[slot]^(32'h1<<b);
                    faults_injected++;
                    fault_coverage[slot*32+b]=1;
                    bit_coverage[b]=1;
                    read_one(a,b%3,4,1);
                    read_one(a,0,0,0);
                end
            end
            $display("TEST deferred detection in a different word of the same line");
            read_one(32'h3000,0,4,0);
            @(negedge clk); dut.u_array.data[2]=dut.u_array.data[2]^32'h80000000;
            faults_injected++;
            read_one(32'h3000,0,0,0); read_one(32'h3008,0,4,1);

            $display("TEST corruption after first refill beat, before line commit");
            reset_all(); latency_cycles=3; jitter_cycles=0; stall_period=0;
            m0=memory_reads; e0=errors; c0=completed;
            @(negedge clk); cpu_req_addr=32'h4000; cpu_req_valid=1; cpu_rsp_ready=1;
            do @(posedge clk); while (!cpu_req_ready);
            @(negedge clk); cpu_req_valid=0;
            while (!(dut.state==2 && dut.beat==1)) @(negedge clk);
            dut.u_array.data[0]=dut.u_array.data[0]^32'h00010000;
            faults_injected++;
            while (completed<c0+1) @(negedge clk);
            cpu_rsp_ready=0;
            assert (memory_reads-m0==8 && errors-e0==1)
                else $fatal(1, "Refill-time fault was not detected and retried");
        end

        $display("TEST randomized locality/conflicts/full-address sequences seed=%0d",seed);
        latency_cycles=1; jitter_cycles=5; stall_period=4;
        for (n=0;n<random_count;n++) begin
            rng=next_random(rng);
            case (n%4)
                0: a=(rng & 32'h0000007c);
                1: a=(rng & 32'h00000ffc);
                2: a=(rng & 32'hfffffffc);
                3: a=(rng & 32'h00000380) | 32'h00000014;
            endcase
            read_one(a,n%4,-1,0);
        end

        // Reproducible, fault-free benchmark, isolated from all directed/reset tests.
        reset_all(); latency_cycles=3; jitter_cycles=2; stall_period=4;
        rng=seed; if (rng==0) rng=1;
        bench_hits=hits; bench_misses=misses; bench_first=first_latency_sum;
        bench_completion=completion_latency_sum; bench_reads=memory_reads; bench_done=completed;
        $display("TEST comparable 1000-read fault-free benchmark");
        for (n=0;n<bench_n;n++) begin
            rng=next_random(rng);
            if ((n%10)<8) a=rng & 32'h7c;
            else a=rng & 32'hffc;
            read_one(a,0,-1,0);
        end
        bench_hits=hits-bench_hits; bench_misses=misses-bench_misses;
        bench_first=first_latency_sum-bench_first;
        bench_completion=completion_latency_sum-bench_completion;
        bench_reads=memory_reads-bench_reads; bench_done=completed-bench_done;
        repeat (3) @(negedge clk);
        assert (!pending && accepted==completed+aborted) else $fatal(1,"Request conservation failed");
        assert (state_coverage==6'b111111 && word_coverage==32'hffffffff)
            else $fatal(1,"Required state/address bins uncovered");
        assert (resets_checked==8 && cpu_stall_cycles>0 && mem_stall_cycles>0 && rsp_stall_cycles>0)
            else $fatal(1,"Missing reset/stall exercise");
        if (ENABLE_PARITY)
            assert (&fault_coverage && errors==faults_injected && recovery_count==faults_injected)
                else $fatal(1,"Fault campaign incomplete");
        $display("PASS parity=%0d seed=%0d accepted=%0d completed=%0d aborted=%0d faults=%0d detected=%0d",
                 ENABLE_PARITY,seed,accepted,completed,aborted,faults_injected,errors);
        fd=$fopen(metrics_path,"w");
        if (!fd) $fatal(1,"Cannot write metrics file");
        $fdisplay(fd,"{");
        $fdisplay(fd,"  \"pass\": true, \"parity\": %0d, \"seed\": %0d,",ENABLE_PARITY,seed);
        $fdisplay(fd,"  \"accepted\": %0d, \"completed\": %0d, \"aborted\": %0d,",accepted,completed,aborted);
        $fdisplay(fd,"  \"faults_injected\": %0d, \"parity_detections\": %0d,",faults_injected,errors);
        $fdisplay(fd,"  \"recovery_count\": %0d, \"recovery_cycles_sum\": %0d, \"recovery_cycles_max\": %0d,",recovery_count,recovery_sum,recovery_max);
        $fdisplay(fd,"  \"reset_scenarios\": %0d, \"state_bins\": %0d, \"word_bins\": %0d,",resets_checked,$countones(state_coverage),$countones(word_coverage));
        $fdisplay(fd,"  \"fault_position_bins\": %0d, \"monitored_cycles\": %0d,",$countones(fault_coverage),monitored_cycles);
        $fdisplay(fd,"  \"checked_hit_cycles\": 2, \"checked_minimum_miss_cycles\": 15,");
        $fdisplay(fd,"  \"cpu_request_stall_cycles\": %0d, \"memory_request_stall_cycles\": %0d, \"cpu_response_stall_cycles\": %0d,",cpu_stall_cycles,mem_stall_cycles,rsp_stall_cycles);
        $fdisplay(fd,"  \"benchmark\": {\"reads\": %0d, \"hits\": %0d, \"misses\": %0d, \"first_response_cycles_sum\": %0d, \"completion_cycles_sum\": %0d, \"memory_word_reads\": %0d}",bench_done,bench_hits,bench_misses,bench_first,bench_completion,bench_reads);
        $fdisplay(fd,"}"); $fclose(fd);
        $finish;
    end

    initial begin
        #200000000;
        $fatal(1,"Global watchdog timeout");
    end
endmodule
