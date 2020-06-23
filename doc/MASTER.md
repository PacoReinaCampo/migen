# 1. INTRODUCTION

# 2. PROJECTS

```
  module top(
    input         sys_clk,
    input         sys_rst,
    input         we,
    output        ack,
    output        error,
    input  [31:0] dat_w,
    output [31:0] dat_r,
    input  [ 6:0] adr
  );

  reg [31:0] mem[0:99];
  reg [ 6:0] memadr;

  always @(posedge sys_clk) begin
    if (we) begin
      mem[adr] <= dat_w;
      ack      <= 1'b1;
    end
    else begin
      ack <= 1'b0;
    end
    memadr <= adr;
  end

  assign dat_r = mem[memadr];
  assign error = 1'b0;

  initial begin
    $readmemh("mem.init", mem);
  end
endmodule
```

# 3. WORKFLOW

# 4. CONCLUSION
