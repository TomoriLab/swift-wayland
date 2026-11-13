import WaylandClient
func rejected(_ read: borrowing ClientReadReservation) -> () -> Void {
    { read.cancel() }
}
