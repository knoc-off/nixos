// Tiny program with a loop and locals, purpose-built for the DAP demo.
// The breakpoint lands inside `factorial` so we can watch `acc` and `n` change
// as the debugger steps. Compiled with `-g` (debug info) by run.sh.
fn factorial(n: u64) -> u64 {
    let mut acc: u64 = 1;
    let mut i: u64 = 1;
    while i <= n {
        acc *= i; // <-- breakpoint here: step and watch `acc` / `i` evolve
        i += 1;
    }
    acc
}

fn main() {
    let input: u64 = 5;
    let result = factorial(input);
    println!("factorial({}) = {}", input, result);
}
