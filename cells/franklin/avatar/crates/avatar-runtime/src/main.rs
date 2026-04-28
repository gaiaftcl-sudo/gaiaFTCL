fn main() {
    let passes = avatar_render::pass_chain();
    println!("franklin avatar runtime active");
    println!("render pass chain: {}", passes.join(" -> "));
}
