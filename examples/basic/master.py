from migen import *
from migen.fhdl import verilog


class Example(Module):
    def __init__(self):
        self.specials.mem = Memory(32, 100, init=list(range(20)))
        p1 = self.mem.get_port(write_capable=True)
        self.specials += p1
        self.ios = {p1.adr, p1.dat_r, p1.we, p1.dat_w}


if __name__ == "__main__":
    example = Example()
    print(verilog.convert(example, example.ios))
