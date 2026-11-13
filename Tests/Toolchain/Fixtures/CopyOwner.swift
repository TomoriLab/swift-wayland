struct Owner: ~Copyable { let value: Int }
func rejected(_ owner: borrowing Owner) {
    let duplicate = copy owner
    _ = duplicate
}
