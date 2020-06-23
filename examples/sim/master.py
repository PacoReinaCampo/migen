from migen import *


# adr   <=> m2s_addr
# dat_r <=> s2m_data
# ack   <=> s2m_ack
# error <=> s2m_error
# we    <=> m2s_we
# dat_w <=> m2s_data


class mem(Module):
    def __init__(self):
        # Initialize the beginning of the memory with integers
        # from 0 to 19.
        self.specials.mem = Memory(32, 100, init=list(range(20)))
        p1 = self.mem.get_port(write_capable=True)
        self.specials += p1
        self.ios = {p1.adr, p1.dat_r, p1.ack, p1.error, p1.we, p1.dat_w}


def master(dut):
    # write (only first 5 values)
    for i in range(5):
        yield dut.mem[i].eq(2*i+1)
    # remember: values are written after the tick, and read before the tick.
    # wait one tick for the memory to update.
    yield
    # read what we have written, plus some initialization data
    for i in range(10):
        value = yield dut.mem[i]
        print("[Data: {}, Address: {}]".format(value, i))


if __name__ == "__main__":
    dut = mem()
    run_simulation(dut, master(dut))
