# External protocol fixtures

`xdg-shell.xml` is copied unchanged from the installed wayland-protocols 1.49 data package. Its SHA-256 is `7ba7f9c8473deee674cb1f154a18abd0bb0cc072604fc055b0c15e459fc4c7df`. The file retains its upstream copyright and permissive license text. It is a generator interoperability fixture, not an additional runtime dependency or a claim that every extension is bundled.

The fixture references the separately pinned `../wayland.xml`. Validation generates an external Swift consumer and a bounded native descriptor bundle, then compares every message signature with native wayland-scanner output. This exercises core imports, cross-interface cycles, versioned messages, and enums from a real extension protocol.
