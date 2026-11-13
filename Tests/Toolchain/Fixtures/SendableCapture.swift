final class NativeState { var value = 1 }
func rejected(_ state: NativeState) -> @Sendable () -> Int {
    return { state.value }
}
