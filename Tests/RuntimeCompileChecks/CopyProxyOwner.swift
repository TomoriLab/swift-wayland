import WaylandRuntime
func rejected<Context: AnyObject>(_ owner: borrowing ProxyDispatcherOwner<Context>) {
    let duplicate = copy owner
    _ = duplicate
}
