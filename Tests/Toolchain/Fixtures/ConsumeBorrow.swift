struct Owner: ~Copyable { let value: Int }
func finish(_ owner: consuming Owner) {}
func rejected(_ owner: borrowing Owner) { finish(owner) }
