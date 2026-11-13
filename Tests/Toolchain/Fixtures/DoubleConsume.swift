struct Owner: ~Copyable { let value: Int }
func finish(_ owner: consuming Owner) {}
func rejected() {
    let owner = Owner(value: 1)
    finish(owner)
    finish(owner)
}
