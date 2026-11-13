import WaylandRuntime
func rejected(_ owner: consuming OwnedFileDescriptor) {
    owner.close()
    owner.close()
}
