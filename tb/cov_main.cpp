// cov_main.cpp -- minimal Verilator main used only by `make cov`.
// (The auto-generated --binary main does not write the coverage file.)
#include <memory>
#include "Vtb_uart_apb.h"
#include "verilated.h"
#include "verilated_cov.h"

int main(int argc, char** argv) {
  const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
  contextp->commandArgs(argc, argv);
  const std::unique_ptr<Vtb_uart_apb> top{new Vtb_uart_apb{contextp.get(), "TOP"}};
  while (!contextp->gotFinish()) {
    top->eval();
    if (!top->eventsPending()) break;
    contextp->time(top->nextTimeSlot());
  }
  top->final();
  contextp->coveragep()->write("coverage.dat");
  return 0;
}
