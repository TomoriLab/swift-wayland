struct Owner: ~Copyable { let value: Int }
func finish(_ owner: consuming Owner) {}
func inspect(_ owner: borrowing Owner) -> Int { owner.value }
func rejected() -> Int {
    let owner = Owner(value: 1)
    finish(owner)
    return inspect(owner)
}
