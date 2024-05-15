`include "SPI_Slave.v"

// Class for input data to DUT to be randomized
class inData;
    rand bit i_Rst_L;
    rand bit [7:0] i_TX_Byte;

    constraint rst_const {i_Rst_L dist {0:=2,1:=98};};

endclass;

interface slave_int #(parameter SPI_MODE = 1)(input clk);

    logic            i_Rst_L;    // FPGA Reset, active low
    logic            o_RX_DV;    // Data Valid pulse (1 clock cycle)
    logic   [7:0]    o_RX_Byte;  // Byte received on MOSI
    logic            i_TX_DV;    // Data Valid pulse to register i_TX_Byte
    logic   [7:0]    i_TX_Byte;  // Byte to serialize to MISO.  

    logic            o_SPI_MISO;
    logic            i_SPI_MOSI;
    logic            i_SPI_CS_n;        // active low

    clocking cb @(posedge clk); // for tb
        output i_TX_DV;
        output i_TX_Byte;
        output i_SPI_MOSI;
        input o_RX_DV;
        input o_RX_Byte;
    endclocking

    modport TB (clocking cb, output i_Rst_L, i_SPI_CS_n, input o_SPI_MISO);

endinterface

module top;

    parameter SPI_MODE = 1;

    // clk generation
    bit i_Clk,i_SPI_Clk;
    always #4 i_Clk = ~i_Clk;
    always #16 i_SPI_Clk = ~i_SPI_Clk;

    // instance of interface
    slave_int #(SPI_MODE) int_inst(i_SPI_Clk);

    // DUT instance
    SPI_Slave #(SPI_MODE) dut_inst (.i_Rst_L(int_inst.i_Rst_L),
    .i_Clk(i_Clk),
    .o_RX_DV(int_inst.o_RX_DV),
    .o_RX_Byte(int_inst.o_RX_Byte),
    .i_TX_DV(int_inst.i_TX_DV),
    .i_TX_Byte(int_inst.i_TX_Byte),
    .i_SPI_Clk(i_SPI_Clk),
    .o_SPI_MISO(int_inst.o_SPI_MISO),
    .i_SPI_MOSI(int_inst.i_SPI_MOSI),
    .i_SPI_CS_n(int_inst.i_SPI_CS_n)
    );

    // tb instance
    SPI_Slave_tb tb_inst (int_inst.TB);

    // get ouput waveform
    initial begin
        $dumpfile("test.vcd");
        $dumpvars;
    end

endmodule


module SPI_Slave_tb(slave_int int_inst);

    // object of input data class
    inData data;
    logic [2:0] count;
    logic [7:0] accumulate_reg;
    logic [5:0] Num_Tran; // This can be increased
    logic [7:0] rand_data;
    logic Single_Tran; // 1: Single Transaction, 0: Multiple Transactions

    task Reset();
        int_inst.i_Rst_L = 0; // active low
        int_inst.i_SPI_CS_n = 1; // initially no communication
        repeat(10) @int_inst.cb;

        $display("i_Rst_L = %0b, o_RX_DV = %0b, o_RX_Byte = %0b, i_TX_DV = %0b, i_TX_Byte = %0b, o_SPI_MISO = %0b, i_SPI_MOSI = %0b, i_SPI_CS_n = %0b", int_inst.i_Rst_L,int_inst.cb.o_RX_DV, int_inst.cb.o_RX_Byte,int_inst.i_TX_DV,int_inst.i_TX_Byte,int_inst.o_SPI_MISO,int_inst.i_SPI_MOSI,int_inst.i_SPI_CS_n);
        
        int_inst.i_Rst_L = 1;
        repeat(10) @int_inst.cb;
    endtask

    task OneTransaction(input [7:0] data);
      @int_inst.cb;
      int_inst.i_SPI_CS_n    <= 1'b0; // start communication
      // ---- for parallel to serial ---- //
      int_inst.i_TX_Byte <= data; // parallel data to send serially
      int_inst.i_TX_DV   <= 1'b1; // raise i_TX_DV so slave registers i_TX_Byte
      // ---- for serial to parallel ---- //
      count = 1;
      int_inst.i_SPI_MOSI = $random; // send first serial MOSI bit
      // accumulate sent bits for checking that SPI Slave outputs the correct byte
      accumulate_reg = {accumulate_reg[6:0],int_inst.i_SPI_MOSI};
      
      for (int i = 7; i >= 0; i--)begin
          @int_inst.cb;
          // ---- for serial to parallel ---- //
          if(i!=0) begin // perform one less iteration of shifting
              count +=1;
              int_inst.i_SPI_MOSI = $random;
              accumulate_reg = {accumulate_reg[6:0],int_inst.i_SPI_MOSI };  
          end

          // ---- for parallel to serial ---- //
          if(i==7)
              int_inst.i_TX_DV <= 1'b0;
          if (data[i] != int_inst.o_SPI_MISO)
              $display("Error, parallel to serial conversion failed, i_TX_Byte = %0b, o_SPI_MISO = %0b, ptr = %0b", data , int_inst.o_SPI_MISO,i);
          else
              $display("Success parallel to serial conversion, i_TX_Byte = %0b, o_SPI_MISO = %0b, ptr = %0b", data , int_inst.o_SPI_MISO,i);
        end

        @int_inst.cb;
        int_inst.i_SPI_CS_n    <= 1'b1; // end communication since one transaction
    endtask

    task MultipleTransaction(input [7:0] data);

        // ---- for parallel to serial ---- //
        int_inst.i_TX_Byte <= data; // parallel data to send serially
        int_inst.i_TX_DV   <= 1'b1; // raise i_TX_DV so slave registers i_TX_Byte

        // ---- for serial to parallel ---- //
        count = 1; // count of bits sent serially
        int_inst.i_SPI_MOSI = $random; // send first serial MOSI bit
        // accumulate sent bits for checking that SPI Slave outputs the correct byte
        accumulate_reg = {accumulate_reg[6:0],int_inst.i_SPI_MOSI};
        
        for (int i = 7; i >= 0; i--)begin
            @int_inst.cb;
            // ---- for serial to parallel ---- //
            if(i!=0) begin // perform one less iteration of shifting
                count +=1; // increment count, each clock cycle an additional bit is sent
                int_inst.i_SPI_MOSI = $random;
                accumulate_reg = {accumulate_reg[6:0],int_inst.i_SPI_MOSI };   
            end

            // ---- for parallel to serial ---- //
            if(i==7) // since we raise i_TX_DV for only one cycle
                int_inst.i_TX_DV <= 1'b0;
            
            if (data[i] != int_inst.o_SPI_MISO) // parallel to serial self-checking
                $display("Error, parallel to serial conversion failed, i_TX_Byte = %0b, o_SPI_MISO = %0b, ptr = %0b", data , int_inst.o_SPI_MISO,i);
            else
                $display("Success parallel to serial conversion, i_TX_Byte = %0b, o_SPI_MISO = %0b, ptr = %0b", data , int_inst.o_SPI_MISO,i);
          end
    endtask

    // Monitor RX
    always@(posedge int_inst.o_RX_DV)
    begin
        if (int_inst.o_RX_Byte !== accumulate_reg)
            $display("Error, serial to parallel conversion failed. o_RX_Byte = %0b, Expected = %0b",int_inst.o_RX_Byte,accumulate_reg);
        else
            $display("Serial to parallel conversion succesful. o_RX_Byte = %0b, Expected = %0b",int_inst.o_RX_Byte,accumulate_reg);
    end

    initial begin

        data = new();
        // --------- Initially resetting DUT --------- //
        Reset();


        for (int i = 0; i<100; i++) begin
            if(data.randomize()) begin
                $display("Randomization succesful!");
		// To test Single Transaction feature and Multi Transaction feature
		Single_Tran = $random;
                int_inst.i_Rst_L = data.i_Rst_L;
                if(!data.i_Rst_L) begin // Reset Activated (active low)
		    $display("RESET ACTIVATED");
                    @int_inst.cb;
                end
                else if(Single_Tran) begin // Single Transaction
                    $display("Single transaction");
                    OneTransaction(data.i_TX_Byte);
                end
                else begin
                    Num_Tran = $urandom_range(2,63);
                    $display("Multi transactions %0d",Num_Tran);
                    @int_inst.cb;
                    int_inst.i_SPI_CS_n    <= 1'b0;
                    for(int i = 0; i<Num_Tran;i++) begin
                        rand_data = $random;
                        MultipleTransaction(rand_data);
                    end
                    @int_inst.cb;
                    int_inst.i_SPI_CS_n    <= 1'b1;
                end
            end
            else
                $display("Randomization Failed");
        end
        
        
	#300; $finish;
    end

endmodule
