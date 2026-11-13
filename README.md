# WaylandKit

A Swift-native interface to Wayland.

WaylandKit is a library being designed to help Swift developers build Wayland clients and compositors on Linux. It aims to bring libwayland's capabilities to Swift through APIs that feel natural to Swift developers, with memory safety and clear resource ownership at the center of the design.

The project is developed in this repository as `swift-wayland`.

## Goals

- Put memory safety first while keeping performance suitable for desktop applications and compositors.
- Cover the complete public libwayland API for both clients and servers.
- Use modern Swift features to make resource lifetimes easier to manage correctly.
- Keep the library maintainable and provide detailed documentation with Swift DocC.

## Project status

WaylandKit is currently in the design phase. The repository contains architecture and safety specifications; an installable library and usage examples are not available yet.

See the [design documentation](docs/README.md) for the proposed architecture, decisions, and development plan.

## License

SPDX-License-Identifier: LGPL-3.0-or-later

swift-wayland is free software: you can redistribute it and/or modify it
under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

swift-wayland is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU Lesser General Public License for more details.

See [LICENSE](LICENSE) for the GNU Lesser General Public License version 3
and [COPYING](COPYING) for the GNU General Public License version 3,
whose terms it incorporates.

## AI-Generated Code Notice

Parts of this project were created with assistance from AI tools (e.g. large language models). All AI-assisted contributions were reviewed and adapted by maintainers before inclusion. If you need provenance for specific changes, please refer to the Git history and commit messages.