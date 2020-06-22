from migen import *
from migen.fhdl import verilog


class Example(Module):
    def __init__(self):
        self.specials.mem = Memory(32, 100, init=list(range(20)))
        p1 = self.mem.get_port(write_capable=True)
        self.specials += p1
        self.ios = {p1.m2s_addr, p1.s2m_data, p1.s2m_ack, p1.s2m_error, p1.m2s_we, p1.m2s_data}


if __name__ == "__main__":
    example = Example()
    print(verilog.convert(example, example.ios))
