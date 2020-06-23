from migen import *
from migen.fhdl import verilog


# MEM
class Mem(Module):
    def __init__(self, ADDR_WIDTH, DATA_WIDTH, DEPTH):
        # Internal Array Definition
        memdata = Array(Array(Signal() for a in range(DEPTH)) for b in range(DATA_WIDTH))

        # Internal Signal Definition
        memaddr = Signal(ADDR_WIDTH)

        # Inputs and Outputs
        self.m2s_we = Signal()
        self.s2m_ack = Signal()
        self.s2m_error = Signal()
        self.m2s_addr = Signal(ADDR_WIDTH)
        self.m2s_data = Signal(DATA_WIDTH)
        self.s2m_data = Signal(DATA_WIDTH)

        # Synchronized Part
        for i in range(DATA_WIDTH):
            self.sync += [If(self.m2s_we, memdata[self.m2s_addr][i].eq(self.m2s_data[i]), self.s2m_ack.eq(1)
                         ).Else(self.s2m_ack.eq(0)
                         ),
                         memaddr.eq(self.m2s_addr)
            ]

        # Combinational Part
        self.comb += self.s2m_error.eq(0)
        for i in range(DATA_WIDTH):
            self.comb += self.s2m_data[i].eq(memdata[memaddr][i])


# MASTER
def Master(dut):
    # Writing to Memory
    for i in range(16):
        yield dut.m2s_we.eq(1)
        yield dut.m2s_addr.eq(i)
        yield dut.m2s_data.eq(2*i+1)

    # Update
    yield

    # Reading from Memory
    for i in range(4):
        yield dut.m2s_addr.eq(i)
        print("ADDRESS: {} DATA: {}".format((yield dut.m2s_addr[i]), (yield dut.s2m_data[i])))
        yield


# SYNTHESIS
if __name__ == "__main__":
    mem = Mem(4, 4, 2**4)
    print(verilog.convert(mem))


# SIMULATION
if __name__ == "__main__":
    dut = Mem(4, 4, 2**4)
    run_simulation(dut, Master(dut))
