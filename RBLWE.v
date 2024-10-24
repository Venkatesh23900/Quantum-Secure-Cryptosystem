module RBLWE(clk, reset, load, c1_in, c2_in, r2_in, start, message_out, valid);

    // Threshold range
    parameter MIN_THRESHOLD = 64;
    parameter MAX_THRESHOLD = 192;
    
    input clk;
    input reset;
    input load;

    input [7:0] c1_in;
    input [7:0] c2_in;
    input r2_in;

    input start;

    output reg message_out;
    output reg valid;


    // Storing the input test vectors
    reg [2047:0] c1;
    reg [2047:0] c2;
    reg [255:0] r2;

    // Intermediate registers for computation
    reg [2047:0] row_product;
    reg [2047:0] mem_state;

    reg [7:0] load_cnt;
    reg [7:0] row_cnt;
    reg [7:0] shifts;
    reg [8:0] add_cnt;

    reg load_done;
    reg row_done;
    reg mult_done;
    reg add_done;
    reg out_done;


    // FSM states
    parameter [3:0] IDLE =          4'd0,
                    LOAD =          4'd1,
                    WAIT_START =    4'd2,
                    MULT_ROW =      4'd3,
                    REDUCE_ROW =    4'd4,
                    ADD_ROW =       4'd5,
                    ROW_DONE =      4'd6,
                    MULT_DONE =     4'd7,
                    ADD_C2 =        4'd8,
                    THRESHOLD =     4'd9,
                    DONE =          4'd10;

    // State vectors
    reg [3:0] state, next_state;

    // State transition
    always@(posedge clk, posedge reset) begin
        if(reset) begin
            state <= IDLE;
        end

        else begin
            state <= next_state;
        end
    end

    // Next state logic
    always@(*) begin
        case(state)
            IDLE: begin
                if(load) next_state <= LOAD;
                else next_state <= IDLE;
            end

            LOAD: begin
                if(load_done) next_state <= WAIT_START;
                else next_state <= LOAD;
            end

            WAIT_START: begin
                if(start) next_state <= MULT_ROW;
                else next_state <= WAIT_START;
            end

            MULT_ROW: begin
                next_state <= REDUCE_ROW;
            end

            REDUCE_ROW: begin
                if(shifts) begin
                    next_state <= REDUCE_ROW;
                end

                else begin
                    next_state <= ADD_ROW;
                end
            end

            ADD_ROW: begin
                if(row_done) begin
                    next_state <= ROW_DONE;
                end

                else begin
                    next_state <= ADD_ROW;
                end
            end

            ROW_DONE: begin
                if(mult_done) begin
                    next_state <= MULT_DONE;
                end

                else begin
                    next_state <= MULT_ROW;
                end
            end

            MULT_DONE: begin
                next_state <= ADD_C2;
            end

            ADD_C2: begin
                if(add_done) next_state <= THRESHOLD;
                else next_state <= ADD_C2;
            end

            THRESHOLD: begin
                if(out_done) next_state <= DONE;
                else next_state <= THRESHOLD;
            end

            DONE: begin
                next_state <= IDLE;
            end
            default: begin
                next_state <=IDLE;
            end
        endcase
    end



    // RBLWE datapath logic
    always@(posedge clk) begin
        case(next_state)
            IDLE: begin
                c1 <= 0;
                c2 <= 0;
                r2 <= 0;                
                row_product <= 0;
                mem_state <= 0;
                load_cnt <= 0;
                row_cnt <= 0;
                shifts <= 0;
                add_cnt <= 0;
                load_done <= 0;
                row_done <= 0;
                mult_done <= 0;
                add_done <= 0;
                out_done <= 0;
                message_out <= 0;
                valid <= 0;
            end

            LOAD: begin
                if(load_cnt <= 8'hFF) begin
                    c1[8*load_cnt +: 8] <= c1_in;
                    c2[8*load_cnt +: 8] <= c2_in;
                    r2[load_cnt] <= r2_in;
                    load_cnt <= load_cnt + 1;
                end

                if(load_cnt == 8'hFF) begin
                    load_done <= 1;
                    load_cnt <= 0;
                end
            end

            MULT_ROW: begin
                row_product <= r2[row_cnt] ? c1 : 2048'b0;
                shifts <= row_cnt;
            end

            REDUCE_ROW: begin
                if(shifts) begin
                    row_product <= (row_product[2047:2040]) ? {row_product[2039:0],(8'hFF - row_product[2047:2040] + 1'b1)} : {row_product[2039:0], 8'b0};
                    shifts <= (shifts - 1);
                end
            end

            ADD_ROW: begin
                if(add_cnt <= 8'hFF) begin
                    mem_state[8*add_cnt +: 8] <= (mem_state[8*add_cnt +: 8] + row_product[8*add_cnt +: 8]) & 8'hFF;
                    add_cnt <= add_cnt + 1;
                end
                
                if(add_cnt == 8'hFF) begin 
                    row_done <= 1;
                    add_cnt <= 0;
                end
            end

            ROW_DONE: begin
                if(row_cnt <= 8'hFF) begin
                    row_cnt <= row_cnt + 1;
                    row_done <= 0;
                end

                if(row_cnt == 8'hFF) begin
                    mult_done <= 1;
                    row_cnt <= 0;
                end
            end

            ADD_C2: begin
                if(add_cnt <= 8'hFF) begin
                    mem_state[8*add_cnt +: 8] <= (mem_state[8*add_cnt +: 8] + c2[8*add_cnt +: 8]) & 8'hFF;
                    add_cnt <= add_cnt + 1;
                end

                if(add_cnt == 8'hFF) begin
                    add_done <= 1;
                    add_cnt <= 0;
                end
            end

            THRESHOLD: begin
                if (add_cnt <= 8'hFF) begin
                    message_out <= (mem_state[8*add_cnt +: 8] > MIN_THRESHOLD) && (mem_state[8*add_cnt +: 8] < MAX_THRESHOLD) ? 1 : 0;
                    valid <= 1;
                    add_cnt <= add_cnt + 1;
                end

                else begin
                    valid <= 0;
                    add_cnt <= 0;
                    out_done <= 1;
                end
            end
        endcase
    end
endmodule