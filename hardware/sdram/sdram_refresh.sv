`timescale 1ns/1ns

// SDRAM initialsation and refresh controller
//
// Refresh strategy:
// - SDRAM needs all 8192 rows refreshed every 64ms
// - One refresh every 64ms/8192 = 7.8us = ~390 cycles at 50MHz
// - Soft deadline at 350 cycles: wait for idle
// - Hard deadline at 400 cycles: force with freeze
//
// Refresh sequence:
// - Precharge all banks
// - Wait tRP (precharge time)
// - Issue AUTO REFRESH
// - Wait tRC (refresh cycle time)

module sdram_refresh (
    input logic      clock,
    input logic      reset,
    input logic      sdram_idle,     // SDRAM has no pending operations

    output logic     precharge_all,
    output logic     refresh,
    output logic     freeze,
    output logic     load_mode
);

logic         init_done, next_init_done;
logic [6:0]   counter, init_counter;
logic [7:0]   refresh_counter, next_refresh_counter;
logic [9:0]   refresh_timer, next_refresh_timer;
logic         refresh_in_progress, next_refresh_in_progress;

always_comb begin
    next_init_done = init_done;
    init_counter = counter;
    next_refresh_counter = refresh_counter;
    next_refresh_timer = (refresh_timer > 0) ? refresh_timer - 1'b1 : 4'b0;
    next_refresh_in_progress = refresh_in_progress;
    precharge_all = 1'b0;
    refresh = 1'b0;
    load_mode = 1'b0;

    freeze = !init_done || refresh_in_progress;

    // Need a refresh every 700 cycles on average
    if (refresh_timer==10'd0) begin
        next_refresh_timer = 10'd700;
        next_refresh_counter = refresh_counter + 1'b1;
    end

    if (!init_done) begin
        // Initialization sequence
        init_counter = counter + 1'b1;
        if (counter == 7'h60)
            next_init_done = 1'b1;
        if (counter == 7'h2)
            precharge_all = 1'b1;
        if (counter == 7'h10 || counter == 7'h20 || counter == 7'h30 || counter == 7'h40)
            refresh = 1'b1;
        if (counter == 7'h50)
            load_mode = 1'b1;
    end else begin
        // Normal operation - periodic refresh

        // If the sdram is idle, and we have refreshes needed then start one.
        if (refresh_counter>0 && sdram_idle && !refresh_in_progress) begin
            next_refresh_in_progress = 1'b1;
            init_counter = 7'h5; 
        end
        // If the number of pending refreshes gets too high then force one anyway even if the sdram 
        // is not idle. In this case we need to wait longer to make sure whateverf transactions are
        // in progress have time to complete.
        if (refresh_counter>127 && !refresh_in_progress) begin
            next_refresh_in_progress = 1'b1;
            init_counter = 7'h0; 
        end


        if (refresh_in_progress) begin
            init_counter = counter + 1'b1;
            // Allow time to make sure any existing transactions have completed.
            if (counter == 7'd8)
                precharge_all = 1'b1;
            // After time for the precharge before the refresh
            if (counter == 7'd11) begin
                 refresh = 1'b1;
                 next_refresh_counter = refresh_counter - 1'b1;
            end
            // If the sdram is still idle and we have more refreshes pending then we can start 
            // the next one immediately after the refresh without waiting for the precharge time again
            if (counter == 7'd19 && sdram_idle && refresh_counter>0)
                init_counter = 7'd11;
            else if (counter==7'd19) begin
                next_refresh_in_progress = 1'b0;
                init_counter = 7'h0;
            end
        end
    end

    // reset
    if (reset) begin
        next_init_done = 1'b0;
        init_counter = 7'h0;
        next_refresh_counter = 8'b0;
        next_refresh_timer = 10'b0;
        next_refresh_in_progress = 1'b0;
    end
end


always_ff @(posedge clock) begin
    init_done <= next_init_done;
    counter <= init_counter;
    refresh_counter <= next_refresh_counter;
    refresh_timer <= next_refresh_timer;
    refresh_in_progress <= next_refresh_in_progress;
end


endmodule