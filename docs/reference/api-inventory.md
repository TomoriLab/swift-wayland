# libwayland 1.26.0 API inventory

Status: design baseline, not implemented. Captured on 2026-11-13 from installed public headers.

Every function below has a planned one-to-one compatibility mapping. The spelling `Namespace.c_symbol` is a design identifier, not a compiled Swift declaration. Safe facades are specified by API family in the architecture articles. Function rows were checked against Clang FunctionDecl nodes located in each physical header, including static inline definitions and excluding calls inside function bodies. Named types and macros were extracted lexically. This snapshot is not a substitute for the future complete AST, preprocessing, and exported-symbol coverage gate. Enum members and record fields remain part of their named type contracts; generated protocol metadata is inventoried separately.

Do not interpret the compatibility mapping as a memory-safety guarantee. Raw callbacks, pointer adoption, untyped user data, intrusive lists, and arbitrary marshalling require explicit unsafe access.

## wayland-client-core.h

SHA-256: `936e6d191144358aec15edf1271781ea333a15da96e81bb9c99d137292a8403b`

Planned namespace: `ClientInterop`. Functions: 53.

| C function | Planned compatibility operation | State |
|---|---|---|
| `wl_display_cancel_read` | `ClientInterop.wl_display_cancel_read` | Planned |
| `wl_display_connect` | `ClientInterop.wl_display_connect` | Planned |
| `wl_display_connect_to_fd` | `ClientInterop.wl_display_connect_to_fd` | Planned |
| `wl_display_create_queue` | `ClientInterop.wl_display_create_queue` | Planned |
| `wl_display_create_queue_with_name` | `ClientInterop.wl_display_create_queue_with_name` | Planned |
| `wl_display_disconnect` | `ClientInterop.wl_display_disconnect` | Planned |
| `wl_display_dispatch` | `ClientInterop.wl_display_dispatch` | Planned |
| `wl_display_dispatch_pending` | `ClientInterop.wl_display_dispatch_pending` | Planned |
| `wl_display_dispatch_pending_single` | `ClientInterop.wl_display_dispatch_pending_single` | Planned |
| `wl_display_dispatch_queue` | `ClientInterop.wl_display_dispatch_queue` | Planned |
| `wl_display_dispatch_queue_pending` | `ClientInterop.wl_display_dispatch_queue_pending` | Planned |
| `wl_display_dispatch_queue_pending_single` | `ClientInterop.wl_display_dispatch_queue_pending_single` | Planned |
| `wl_display_dispatch_queue_timeout` | `ClientInterop.wl_display_dispatch_queue_timeout` | Planned |
| `wl_display_dispatch_timeout` | `ClientInterop.wl_display_dispatch_timeout` | Planned |
| `wl_display_flush` | `ClientInterop.wl_display_flush` | Planned |
| `wl_display_get_error` | `ClientInterop.wl_display_get_error` | Planned |
| `wl_display_get_fd` | `ClientInterop.wl_display_get_fd` | Planned |
| `wl_display_get_protocol_error` | `ClientInterop.wl_display_get_protocol_error` | Planned |
| `wl_display_prepare_read` | `ClientInterop.wl_display_prepare_read` | Planned |
| `wl_display_prepare_read_queue` | `ClientInterop.wl_display_prepare_read_queue` | Planned |
| `wl_display_read_events` | `ClientInterop.wl_display_read_events` | Planned |
| `wl_display_roundtrip` | `ClientInterop.wl_display_roundtrip` | Planned |
| `wl_display_roundtrip_queue` | `ClientInterop.wl_display_roundtrip_queue` | Planned |
| `wl_display_set_max_buffer_size` | `ClientInterop.wl_display_set_max_buffer_size` | Planned |
| `wl_event_queue_destroy` | `ClientInterop.wl_event_queue_destroy` | Planned |
| `wl_event_queue_get_name` | `ClientInterop.wl_event_queue_get_name` | Planned |
| `wl_log_set_handler_client` | `ClientInterop.wl_log_set_handler_client` | Planned |
| `wl_proxy_add_dispatcher` | `ClientInterop.wl_proxy_add_dispatcher` | Planned |
| `wl_proxy_add_listener` | `ClientInterop.wl_proxy_add_listener` | Planned |
| `wl_proxy_create` | `ClientInterop.wl_proxy_create` | Planned |
| `wl_proxy_create_wrapper` | `ClientInterop.wl_proxy_create_wrapper` | Planned |
| `wl_proxy_destroy` | `ClientInterop.wl_proxy_destroy` | Planned |
| `wl_proxy_get_class` | `ClientInterop.wl_proxy_get_class` | Planned |
| `wl_proxy_get_display` | `ClientInterop.wl_proxy_get_display` | Planned |
| `wl_proxy_get_id` | `ClientInterop.wl_proxy_get_id` | Planned |
| `wl_proxy_get_interface` | `ClientInterop.wl_proxy_get_interface` | Planned |
| `wl_proxy_get_listener` | `ClientInterop.wl_proxy_get_listener` | Planned |
| `wl_proxy_get_queue` | `ClientInterop.wl_proxy_get_queue` | Planned |
| `wl_proxy_get_tag` | `ClientInterop.wl_proxy_get_tag` | Planned |
| `wl_proxy_get_user_data` | `ClientInterop.wl_proxy_get_user_data` | Planned |
| `wl_proxy_get_version` | `ClientInterop.wl_proxy_get_version` | Planned |
| `wl_proxy_marshal` | `ClientInterop.wl_proxy_marshal` | Planned |
| `wl_proxy_marshal_array` | `ClientInterop.wl_proxy_marshal_array` | Planned |
| `wl_proxy_marshal_array_constructor` | `ClientInterop.wl_proxy_marshal_array_constructor` | Planned |
| `wl_proxy_marshal_array_constructor_versioned` | `ClientInterop.wl_proxy_marshal_array_constructor_versioned` | Planned |
| `wl_proxy_marshal_array_flags` | `ClientInterop.wl_proxy_marshal_array_flags` | Planned |
| `wl_proxy_marshal_constructor` | `ClientInterop.wl_proxy_marshal_constructor` | Planned |
| `wl_proxy_marshal_constructor_versioned` | `ClientInterop.wl_proxy_marshal_constructor_versioned` | Planned |
| `wl_proxy_marshal_flags` | `ClientInterop.wl_proxy_marshal_flags` | Planned |
| `wl_proxy_set_queue` | `ClientInterop.wl_proxy_set_queue` | Planned |
| `wl_proxy_set_tag` | `ClientInterop.wl_proxy_set_tag` | Planned |
| `wl_proxy_set_user_data` | `ClientInterop.wl_proxy_set_user_data` | Planned |
| `wl_proxy_wrapper_destroy` | `ClientInterop.wl_proxy_wrapper_destroy` | Planned |

Named type contracts: `wl_display`, `wl_event_queue`, `wl_proxy`.

Macro contracts: `WAYLAND_CLIENT_CORE_H`, `WL_MARSHAL_FLAG_DESTROY`.

## wayland-client-protocol.h

SHA-256: `09d49cd7a692a122a76d0bf5cc1dabd5b5f84c2af634353ffbe67d4ee23fb0e4`

Planned namespace: `ClientProtocolInterop`. Functions: 169.

| C function | Planned compatibility operation | State |
|---|---|---|
| `wl_buffer_add_listener` | `ClientProtocolInterop.wl_buffer_add_listener` | Planned |
| `wl_buffer_destroy` | `ClientProtocolInterop.wl_buffer_destroy` | Planned |
| `wl_buffer_get_user_data` | `ClientProtocolInterop.wl_buffer_get_user_data` | Planned |
| `wl_buffer_get_version` | `ClientProtocolInterop.wl_buffer_get_version` | Planned |
| `wl_buffer_set_user_data` | `ClientProtocolInterop.wl_buffer_set_user_data` | Planned |
| `wl_callback_add_listener` | `ClientProtocolInterop.wl_callback_add_listener` | Planned |
| `wl_callback_destroy` | `ClientProtocolInterop.wl_callback_destroy` | Planned |
| `wl_callback_get_user_data` | `ClientProtocolInterop.wl_callback_get_user_data` | Planned |
| `wl_callback_get_version` | `ClientProtocolInterop.wl_callback_get_version` | Planned |
| `wl_callback_set_user_data` | `ClientProtocolInterop.wl_callback_set_user_data` | Planned |
| `wl_compositor_create_region` | `ClientProtocolInterop.wl_compositor_create_region` | Planned |
| `wl_compositor_create_surface` | `ClientProtocolInterop.wl_compositor_create_surface` | Planned |
| `wl_compositor_destroy` | `ClientProtocolInterop.wl_compositor_destroy` | Planned |
| `wl_compositor_get_user_data` | `ClientProtocolInterop.wl_compositor_get_user_data` | Planned |
| `wl_compositor_get_version` | `ClientProtocolInterop.wl_compositor_get_version` | Planned |
| `wl_compositor_release` | `ClientProtocolInterop.wl_compositor_release` | Planned |
| `wl_compositor_set_user_data` | `ClientProtocolInterop.wl_compositor_set_user_data` | Planned |
| `wl_data_device_add_listener` | `ClientProtocolInterop.wl_data_device_add_listener` | Planned |
| `wl_data_device_destroy` | `ClientProtocolInterop.wl_data_device_destroy` | Planned |
| `wl_data_device_get_user_data` | `ClientProtocolInterop.wl_data_device_get_user_data` | Planned |
| `wl_data_device_get_version` | `ClientProtocolInterop.wl_data_device_get_version` | Planned |
| `wl_data_device_manager_create_data_source` | `ClientProtocolInterop.wl_data_device_manager_create_data_source` | Planned |
| `wl_data_device_manager_destroy` | `ClientProtocolInterop.wl_data_device_manager_destroy` | Planned |
| `wl_data_device_manager_get_data_device` | `ClientProtocolInterop.wl_data_device_manager_get_data_device` | Planned |
| `wl_data_device_manager_get_user_data` | `ClientProtocolInterop.wl_data_device_manager_get_user_data` | Planned |
| `wl_data_device_manager_get_version` | `ClientProtocolInterop.wl_data_device_manager_get_version` | Planned |
| `wl_data_device_manager_release` | `ClientProtocolInterop.wl_data_device_manager_release` | Planned |
| `wl_data_device_manager_set_user_data` | `ClientProtocolInterop.wl_data_device_manager_set_user_data` | Planned |
| `wl_data_device_release` | `ClientProtocolInterop.wl_data_device_release` | Planned |
| `wl_data_device_set_selection` | `ClientProtocolInterop.wl_data_device_set_selection` | Planned |
| `wl_data_device_set_user_data` | `ClientProtocolInterop.wl_data_device_set_user_data` | Planned |
| `wl_data_device_start_drag` | `ClientProtocolInterop.wl_data_device_start_drag` | Planned |
| `wl_data_offer_accept` | `ClientProtocolInterop.wl_data_offer_accept` | Planned |
| `wl_data_offer_add_listener` | `ClientProtocolInterop.wl_data_offer_add_listener` | Planned |
| `wl_data_offer_destroy` | `ClientProtocolInterop.wl_data_offer_destroy` | Planned |
| `wl_data_offer_finish` | `ClientProtocolInterop.wl_data_offer_finish` | Planned |
| `wl_data_offer_get_user_data` | `ClientProtocolInterop.wl_data_offer_get_user_data` | Planned |
| `wl_data_offer_get_version` | `ClientProtocolInterop.wl_data_offer_get_version` | Planned |
| `wl_data_offer_receive` | `ClientProtocolInterop.wl_data_offer_receive` | Planned |
| `wl_data_offer_set_actions` | `ClientProtocolInterop.wl_data_offer_set_actions` | Planned |
| `wl_data_offer_set_user_data` | `ClientProtocolInterop.wl_data_offer_set_user_data` | Planned |
| `wl_data_source_add_listener` | `ClientProtocolInterop.wl_data_source_add_listener` | Planned |
| `wl_data_source_destroy` | `ClientProtocolInterop.wl_data_source_destroy` | Planned |
| `wl_data_source_get_user_data` | `ClientProtocolInterop.wl_data_source_get_user_data` | Planned |
| `wl_data_source_get_version` | `ClientProtocolInterop.wl_data_source_get_version` | Planned |
| `wl_data_source_offer` | `ClientProtocolInterop.wl_data_source_offer` | Planned |
| `wl_data_source_set_actions` | `ClientProtocolInterop.wl_data_source_set_actions` | Planned |
| `wl_data_source_set_user_data` | `ClientProtocolInterop.wl_data_source_set_user_data` | Planned |
| `wl_display_add_listener` | `ClientProtocolInterop.wl_display_add_listener` | Planned |
| `wl_display_get_registry` | `ClientProtocolInterop.wl_display_get_registry` | Planned |
| `wl_display_get_user_data` | `ClientProtocolInterop.wl_display_get_user_data` | Planned |
| `wl_display_get_version` | `ClientProtocolInterop.wl_display_get_version` | Planned |
| `wl_display_set_user_data` | `ClientProtocolInterop.wl_display_set_user_data` | Planned |
| `wl_display_sync` | `ClientProtocolInterop.wl_display_sync` | Planned |
| `wl_fixes_ack_global_remove` | `ClientProtocolInterop.wl_fixes_ack_global_remove` | Planned |
| `wl_fixes_destroy` | `ClientProtocolInterop.wl_fixes_destroy` | Planned |
| `wl_fixes_destroy_registry` | `ClientProtocolInterop.wl_fixes_destroy_registry` | Planned |
| `wl_fixes_get_user_data` | `ClientProtocolInterop.wl_fixes_get_user_data` | Planned |
| `wl_fixes_get_version` | `ClientProtocolInterop.wl_fixes_get_version` | Planned |
| `wl_fixes_set_user_data` | `ClientProtocolInterop.wl_fixes_set_user_data` | Planned |
| `wl_keyboard_add_listener` | `ClientProtocolInterop.wl_keyboard_add_listener` | Planned |
| `wl_keyboard_destroy` | `ClientProtocolInterop.wl_keyboard_destroy` | Planned |
| `wl_keyboard_get_user_data` | `ClientProtocolInterop.wl_keyboard_get_user_data` | Planned |
| `wl_keyboard_get_version` | `ClientProtocolInterop.wl_keyboard_get_version` | Planned |
| `wl_keyboard_release` | `ClientProtocolInterop.wl_keyboard_release` | Planned |
| `wl_keyboard_set_user_data` | `ClientProtocolInterop.wl_keyboard_set_user_data` | Planned |
| `wl_output_add_listener` | `ClientProtocolInterop.wl_output_add_listener` | Planned |
| `wl_output_destroy` | `ClientProtocolInterop.wl_output_destroy` | Planned |
| `wl_output_get_user_data` | `ClientProtocolInterop.wl_output_get_user_data` | Planned |
| `wl_output_get_version` | `ClientProtocolInterop.wl_output_get_version` | Planned |
| `wl_output_release` | `ClientProtocolInterop.wl_output_release` | Planned |
| `wl_output_set_user_data` | `ClientProtocolInterop.wl_output_set_user_data` | Planned |
| `wl_pointer_add_listener` | `ClientProtocolInterop.wl_pointer_add_listener` | Planned |
| `wl_pointer_destroy` | `ClientProtocolInterop.wl_pointer_destroy` | Planned |
| `wl_pointer_get_user_data` | `ClientProtocolInterop.wl_pointer_get_user_data` | Planned |
| `wl_pointer_get_version` | `ClientProtocolInterop.wl_pointer_get_version` | Planned |
| `wl_pointer_release` | `ClientProtocolInterop.wl_pointer_release` | Planned |
| `wl_pointer_set_cursor` | `ClientProtocolInterop.wl_pointer_set_cursor` | Planned |
| `wl_pointer_set_user_data` | `ClientProtocolInterop.wl_pointer_set_user_data` | Planned |
| `wl_region_add` | `ClientProtocolInterop.wl_region_add` | Planned |
| `wl_region_destroy` | `ClientProtocolInterop.wl_region_destroy` | Planned |
| `wl_region_get_user_data` | `ClientProtocolInterop.wl_region_get_user_data` | Planned |
| `wl_region_get_version` | `ClientProtocolInterop.wl_region_get_version` | Planned |
| `wl_region_set_user_data` | `ClientProtocolInterop.wl_region_set_user_data` | Planned |
| `wl_region_subtract` | `ClientProtocolInterop.wl_region_subtract` | Planned |
| `wl_registry_add_listener` | `ClientProtocolInterop.wl_registry_add_listener` | Planned |
| `wl_registry_bind` | `ClientProtocolInterop.wl_registry_bind` | Planned |
| `wl_registry_destroy` | `ClientProtocolInterop.wl_registry_destroy` | Planned |
| `wl_registry_get_user_data` | `ClientProtocolInterop.wl_registry_get_user_data` | Planned |
| `wl_registry_get_version` | `ClientProtocolInterop.wl_registry_get_version` | Planned |
| `wl_registry_set_user_data` | `ClientProtocolInterop.wl_registry_set_user_data` | Planned |
| `wl_seat_add_listener` | `ClientProtocolInterop.wl_seat_add_listener` | Planned |
| `wl_seat_destroy` | `ClientProtocolInterop.wl_seat_destroy` | Planned |
| `wl_seat_get_keyboard` | `ClientProtocolInterop.wl_seat_get_keyboard` | Planned |
| `wl_seat_get_pointer` | `ClientProtocolInterop.wl_seat_get_pointer` | Planned |
| `wl_seat_get_touch` | `ClientProtocolInterop.wl_seat_get_touch` | Planned |
| `wl_seat_get_user_data` | `ClientProtocolInterop.wl_seat_get_user_data` | Planned |
| `wl_seat_get_version` | `ClientProtocolInterop.wl_seat_get_version` | Planned |
| `wl_seat_release` | `ClientProtocolInterop.wl_seat_release` | Planned |
| `wl_seat_set_user_data` | `ClientProtocolInterop.wl_seat_set_user_data` | Planned |
| `wl_shell_destroy` | `ClientProtocolInterop.wl_shell_destroy` | Planned |
| `wl_shell_get_shell_surface` | `ClientProtocolInterop.wl_shell_get_shell_surface` | Planned |
| `wl_shell_get_user_data` | `ClientProtocolInterop.wl_shell_get_user_data` | Planned |
| `wl_shell_get_version` | `ClientProtocolInterop.wl_shell_get_version` | Planned |
| `wl_shell_set_user_data` | `ClientProtocolInterop.wl_shell_set_user_data` | Planned |
| `wl_shell_surface_add_listener` | `ClientProtocolInterop.wl_shell_surface_add_listener` | Planned |
| `wl_shell_surface_destroy` | `ClientProtocolInterop.wl_shell_surface_destroy` | Planned |
| `wl_shell_surface_get_user_data` | `ClientProtocolInterop.wl_shell_surface_get_user_data` | Planned |
| `wl_shell_surface_get_version` | `ClientProtocolInterop.wl_shell_surface_get_version` | Planned |
| `wl_shell_surface_move` | `ClientProtocolInterop.wl_shell_surface_move` | Planned |
| `wl_shell_surface_pong` | `ClientProtocolInterop.wl_shell_surface_pong` | Planned |
| `wl_shell_surface_resize` | `ClientProtocolInterop.wl_shell_surface_resize` | Planned |
| `wl_shell_surface_set_class` | `ClientProtocolInterop.wl_shell_surface_set_class` | Planned |
| `wl_shell_surface_set_fullscreen` | `ClientProtocolInterop.wl_shell_surface_set_fullscreen` | Planned |
| `wl_shell_surface_set_maximized` | `ClientProtocolInterop.wl_shell_surface_set_maximized` | Planned |
| `wl_shell_surface_set_popup` | `ClientProtocolInterop.wl_shell_surface_set_popup` | Planned |
| `wl_shell_surface_set_title` | `ClientProtocolInterop.wl_shell_surface_set_title` | Planned |
| `wl_shell_surface_set_toplevel` | `ClientProtocolInterop.wl_shell_surface_set_toplevel` | Planned |
| `wl_shell_surface_set_transient` | `ClientProtocolInterop.wl_shell_surface_set_transient` | Planned |
| `wl_shell_surface_set_user_data` | `ClientProtocolInterop.wl_shell_surface_set_user_data` | Planned |
| `wl_shm_add_listener` | `ClientProtocolInterop.wl_shm_add_listener` | Planned |
| `wl_shm_create_pool` | `ClientProtocolInterop.wl_shm_create_pool` | Planned |
| `wl_shm_destroy` | `ClientProtocolInterop.wl_shm_destroy` | Planned |
| `wl_shm_get_user_data` | `ClientProtocolInterop.wl_shm_get_user_data` | Planned |
| `wl_shm_get_version` | `ClientProtocolInterop.wl_shm_get_version` | Planned |
| `wl_shm_pool_create_buffer` | `ClientProtocolInterop.wl_shm_pool_create_buffer` | Planned |
| `wl_shm_pool_destroy` | `ClientProtocolInterop.wl_shm_pool_destroy` | Planned |
| `wl_shm_pool_get_user_data` | `ClientProtocolInterop.wl_shm_pool_get_user_data` | Planned |
| `wl_shm_pool_get_version` | `ClientProtocolInterop.wl_shm_pool_get_version` | Planned |
| `wl_shm_pool_resize` | `ClientProtocolInterop.wl_shm_pool_resize` | Planned |
| `wl_shm_pool_set_user_data` | `ClientProtocolInterop.wl_shm_pool_set_user_data` | Planned |
| `wl_shm_release` | `ClientProtocolInterop.wl_shm_release` | Planned |
| `wl_shm_set_user_data` | `ClientProtocolInterop.wl_shm_set_user_data` | Planned |
| `wl_subcompositor_destroy` | `ClientProtocolInterop.wl_subcompositor_destroy` | Planned |
| `wl_subcompositor_get_subsurface` | `ClientProtocolInterop.wl_subcompositor_get_subsurface` | Planned |
| `wl_subcompositor_get_user_data` | `ClientProtocolInterop.wl_subcompositor_get_user_data` | Planned |
| `wl_subcompositor_get_version` | `ClientProtocolInterop.wl_subcompositor_get_version` | Planned |
| `wl_subcompositor_set_user_data` | `ClientProtocolInterop.wl_subcompositor_set_user_data` | Planned |
| `wl_subsurface_destroy` | `ClientProtocolInterop.wl_subsurface_destroy` | Planned |
| `wl_subsurface_get_user_data` | `ClientProtocolInterop.wl_subsurface_get_user_data` | Planned |
| `wl_subsurface_get_version` | `ClientProtocolInterop.wl_subsurface_get_version` | Planned |
| `wl_subsurface_place_above` | `ClientProtocolInterop.wl_subsurface_place_above` | Planned |
| `wl_subsurface_place_below` | `ClientProtocolInterop.wl_subsurface_place_below` | Planned |
| `wl_subsurface_set_desync` | `ClientProtocolInterop.wl_subsurface_set_desync` | Planned |
| `wl_subsurface_set_position` | `ClientProtocolInterop.wl_subsurface_set_position` | Planned |
| `wl_subsurface_set_sync` | `ClientProtocolInterop.wl_subsurface_set_sync` | Planned |
| `wl_subsurface_set_user_data` | `ClientProtocolInterop.wl_subsurface_set_user_data` | Planned |
| `wl_surface_add_listener` | `ClientProtocolInterop.wl_surface_add_listener` | Planned |
| `wl_surface_attach` | `ClientProtocolInterop.wl_surface_attach` | Planned |
| `wl_surface_commit` | `ClientProtocolInterop.wl_surface_commit` | Planned |
| `wl_surface_damage` | `ClientProtocolInterop.wl_surface_damage` | Planned |
| `wl_surface_damage_buffer` | `ClientProtocolInterop.wl_surface_damage_buffer` | Planned |
| `wl_surface_destroy` | `ClientProtocolInterop.wl_surface_destroy` | Planned |
| `wl_surface_frame` | `ClientProtocolInterop.wl_surface_frame` | Planned |
| `wl_surface_get_release` | `ClientProtocolInterop.wl_surface_get_release` | Planned |
| `wl_surface_get_user_data` | `ClientProtocolInterop.wl_surface_get_user_data` | Planned |
| `wl_surface_get_version` | `ClientProtocolInterop.wl_surface_get_version` | Planned |
| `wl_surface_offset` | `ClientProtocolInterop.wl_surface_offset` | Planned |
| `wl_surface_set_buffer_scale` | `ClientProtocolInterop.wl_surface_set_buffer_scale` | Planned |
| `wl_surface_set_buffer_transform` | `ClientProtocolInterop.wl_surface_set_buffer_transform` | Planned |
| `wl_surface_set_input_region` | `ClientProtocolInterop.wl_surface_set_input_region` | Planned |
| `wl_surface_set_opaque_region` | `ClientProtocolInterop.wl_surface_set_opaque_region` | Planned |
| `wl_surface_set_user_data` | `ClientProtocolInterop.wl_surface_set_user_data` | Planned |
| `wl_touch_add_listener` | `ClientProtocolInterop.wl_touch_add_listener` | Planned |
| `wl_touch_destroy` | `ClientProtocolInterop.wl_touch_destroy` | Planned |
| `wl_touch_get_user_data` | `ClientProtocolInterop.wl_touch_get_user_data` | Planned |
| `wl_touch_get_version` | `ClientProtocolInterop.wl_touch_get_version` | Planned |
| `wl_touch_release` | `ClientProtocolInterop.wl_touch_release` | Planned |
| `wl_touch_set_user_data` | `ClientProtocolInterop.wl_touch_set_user_data` | Planned |

Named type contracts: `wl_buffer`, `wl_buffer_listener`, `wl_callback`, `wl_callback_listener`, `wl_compositor`, `wl_data_device`, `wl_data_device_error`, `wl_data_device_listener`, `wl_data_device_manager`, `wl_data_device_manager_dnd_action`, `wl_data_offer`, `wl_data_offer_error`, `wl_data_offer_listener`, `wl_data_source`, `wl_data_source_error`, `wl_data_source_listener`, `wl_display`, `wl_display_error`, `wl_display_listener`, `wl_fixes`, `wl_fixes_error`, `wl_keyboard`, `wl_keyboard_key_state`, `wl_keyboard_keymap_format`, `wl_keyboard_listener`, `wl_output`, `wl_output_listener`, `wl_output_mode`, `wl_output_subpixel`, `wl_output_transform`, `wl_pointer`, `wl_pointer_axis`, `wl_pointer_axis_relative_direction`, `wl_pointer_axis_source`, `wl_pointer_button_state`, `wl_pointer_error`, `wl_pointer_listener`, `wl_region`, `wl_registry`, `wl_registry_listener`, `wl_seat`, `wl_seat_capability`, `wl_seat_error`, `wl_seat_listener`, `wl_shell`, `wl_shell_error`, `wl_shell_surface`, `wl_shell_surface_fullscreen_method`, `wl_shell_surface_listener`, `wl_shell_surface_resize`, `wl_shell_surface_transient`, `wl_shm`, `wl_shm_error`, `wl_shm_format`, `wl_shm_listener`, `wl_shm_pool`, `wl_shm_pool_error`, `wl_subcompositor`, `wl_subcompositor_error`, `wl_subsurface`, `wl_subsurface_error`, `wl_surface`, `wl_surface_error`, `wl_surface_listener`, `wl_touch`, `wl_touch_listener`.

Macro contracts: `WAYLAND_CLIENT_PROTOCOL_H`, `WL_BUFFER_DESTROY`, `WL_BUFFER_DESTROY_SINCE_VERSION`, `WL_BUFFER_INTERFACE`, `WL_BUFFER_RELEASE_SINCE_VERSION`, `WL_CALLBACK_DONE_SINCE_VERSION`, `WL_CALLBACK_INTERFACE`, `WL_COMPOSITOR_CREATE_REGION`, `WL_COMPOSITOR_CREATE_REGION_SINCE_VERSION`, `WL_COMPOSITOR_CREATE_SURFACE`, `WL_COMPOSITOR_CREATE_SURFACE_SINCE_VERSION`, `WL_COMPOSITOR_INTERFACE`, `WL_COMPOSITOR_RELEASE`, `WL_COMPOSITOR_RELEASE_SINCE_VERSION`, `WL_DATA_DEVICE_DATA_OFFER_SINCE_VERSION`, `WL_DATA_DEVICE_DROP_SINCE_VERSION`, `WL_DATA_DEVICE_ENTER_SINCE_VERSION`, `WL_DATA_DEVICE_ERROR_ENUM`, `WL_DATA_DEVICE_INTERFACE`, `WL_DATA_DEVICE_LEAVE_SINCE_VERSION`, `WL_DATA_DEVICE_MANAGER_CREATE_DATA_SOURCE`, `WL_DATA_DEVICE_MANAGER_CREATE_DATA_SOURCE_SINCE_VERSION`, `WL_DATA_DEVICE_MANAGER_DND_ACTION_ENUM`, `WL_DATA_DEVICE_MANAGER_GET_DATA_DEVICE`, `WL_DATA_DEVICE_MANAGER_GET_DATA_DEVICE_SINCE_VERSION`, `WL_DATA_DEVICE_MANAGER_INTERFACE`, `WL_DATA_DEVICE_MANAGER_RELEASE`, `WL_DATA_DEVICE_MANAGER_RELEASE_SINCE_VERSION`, `WL_DATA_DEVICE_MOTION_SINCE_VERSION`, `WL_DATA_DEVICE_RELEASE`, `WL_DATA_DEVICE_RELEASE_SINCE_VERSION`, `WL_DATA_DEVICE_SELECTION_SINCE_VERSION`, `WL_DATA_DEVICE_SET_SELECTION`, `WL_DATA_DEVICE_SET_SELECTION_SINCE_VERSION`, `WL_DATA_DEVICE_START_DRAG`, `WL_DATA_DEVICE_START_DRAG_SINCE_VERSION`, `WL_DATA_OFFER_ACCEPT`, `WL_DATA_OFFER_ACCEPT_SINCE_VERSION`, `WL_DATA_OFFER_ACTION_SINCE_VERSION`, `WL_DATA_OFFER_DESTROY`, `WL_DATA_OFFER_DESTROY_SINCE_VERSION`, `WL_DATA_OFFER_ERROR_ENUM`, `WL_DATA_OFFER_FINISH`, `WL_DATA_OFFER_FINISH_SINCE_VERSION`, `WL_DATA_OFFER_INTERFACE`, `WL_DATA_OFFER_OFFER_SINCE_VERSION`, `WL_DATA_OFFER_RECEIVE`, `WL_DATA_OFFER_RECEIVE_SINCE_VERSION`, `WL_DATA_OFFER_SET_ACTIONS`, `WL_DATA_OFFER_SET_ACTIONS_SINCE_VERSION`, `WL_DATA_OFFER_SOURCE_ACTIONS_SINCE_VERSION`, `WL_DATA_SOURCE_ACTION_SINCE_VERSION`, `WL_DATA_SOURCE_CANCELLED_SINCE_VERSION`, `WL_DATA_SOURCE_DESTROY`, `WL_DATA_SOURCE_DESTROY_SINCE_VERSION`, `WL_DATA_SOURCE_DND_DROP_PERFORMED_SINCE_VERSION`, `WL_DATA_SOURCE_DND_FINISHED_SINCE_VERSION`, `WL_DATA_SOURCE_ERROR_ENUM`, `WL_DATA_SOURCE_INTERFACE`, `WL_DATA_SOURCE_OFFER`, `WL_DATA_SOURCE_OFFER_SINCE_VERSION`, `WL_DATA_SOURCE_SEND_SINCE_VERSION`, `WL_DATA_SOURCE_SET_ACTIONS`, `WL_DATA_SOURCE_SET_ACTIONS_SINCE_VERSION`, `WL_DATA_SOURCE_TARGET_SINCE_VERSION`, `WL_DISPLAY_DELETE_ID_SINCE_VERSION`, `WL_DISPLAY_ERROR_ENUM`, `WL_DISPLAY_ERROR_SINCE_VERSION`, `WL_DISPLAY_GET_REGISTRY`, `WL_DISPLAY_GET_REGISTRY_SINCE_VERSION`, `WL_DISPLAY_INTERFACE`, `WL_DISPLAY_SYNC`, `WL_DISPLAY_SYNC_SINCE_VERSION`, `WL_FIXES_ACK_GLOBAL_REMOVE`, `WL_FIXES_ACK_GLOBAL_REMOVE_SINCE_VERSION`, `WL_FIXES_DESTROY`, `WL_FIXES_DESTROY_REGISTRY`, `WL_FIXES_DESTROY_REGISTRY_SINCE_VERSION`, `WL_FIXES_DESTROY_SINCE_VERSION`, `WL_FIXES_ERROR_ENUM`, `WL_FIXES_INTERFACE`, `WL_KEYBOARD_ENTER_SINCE_VERSION`, `WL_KEYBOARD_INTERFACE`, `WL_KEYBOARD_KEYMAP_FORMAT_ENUM`, `WL_KEYBOARD_KEYMAP_SINCE_VERSION`, `WL_KEYBOARD_KEY_SINCE_VERSION`, `WL_KEYBOARD_KEY_STATE_ENUM`, `WL_KEYBOARD_KEY_STATE_REPEATED_SINCE_VERSION`, `WL_KEYBOARD_LEAVE_SINCE_VERSION`, `WL_KEYBOARD_MODIFIERS_SINCE_VERSION`, `WL_KEYBOARD_RELEASE`, `WL_KEYBOARD_RELEASE_SINCE_VERSION`, `WL_KEYBOARD_REPEAT_INFO_SINCE_VERSION`, `WL_OUTPUT_DESCRIPTION_SINCE_VERSION`, `WL_OUTPUT_DONE_SINCE_VERSION`, `WL_OUTPUT_GEOMETRY_SINCE_VERSION`, `WL_OUTPUT_INTERFACE`, `WL_OUTPUT_MODE_ENUM`, `WL_OUTPUT_MODE_SINCE_VERSION`, `WL_OUTPUT_NAME_SINCE_VERSION`, `WL_OUTPUT_RELEASE`, `WL_OUTPUT_RELEASE_SINCE_VERSION`, `WL_OUTPUT_SCALE_SINCE_VERSION`, `WL_OUTPUT_SUBPIXEL_ENUM`, `WL_OUTPUT_TRANSFORM_ENUM`, `WL_POINTER_AXIS_DISCRETE_SINCE_VERSION`, `WL_POINTER_AXIS_ENUM`, `WL_POINTER_AXIS_RELATIVE_DIRECTION_ENUM`, `WL_POINTER_AXIS_RELATIVE_DIRECTION_SINCE_VERSION`, `WL_POINTER_AXIS_SINCE_VERSION`, `WL_POINTER_AXIS_SOURCE_ENUM`, `WL_POINTER_AXIS_SOURCE_SINCE_VERSION`, `WL_POINTER_AXIS_SOURCE_WHEEL_TILT_SINCE_VERSION`, `WL_POINTER_AXIS_STOP_SINCE_VERSION`, `WL_POINTER_AXIS_VALUE120_SINCE_VERSION`, `WL_POINTER_BUTTON_SINCE_VERSION`, `WL_POINTER_BUTTON_STATE_ENUM`, `WL_POINTER_ENTER_SINCE_VERSION`, `WL_POINTER_ERROR_ENUM`, `WL_POINTER_FRAME_SINCE_VERSION`, `WL_POINTER_INTERFACE`, `WL_POINTER_LEAVE_SINCE_VERSION`, `WL_POINTER_MOTION_SINCE_VERSION`, `WL_POINTER_RELEASE`, `WL_POINTER_RELEASE_SINCE_VERSION`, `WL_POINTER_SET_CURSOR`, `WL_POINTER_SET_CURSOR_SINCE_VERSION`, `WL_POINTER_WARP_SINCE_VERSION`, `WL_REGION_ADD`, `WL_REGION_ADD_SINCE_VERSION`, `WL_REGION_DESTROY`, `WL_REGION_DESTROY_SINCE_VERSION`, `WL_REGION_INTERFACE`, `WL_REGION_SUBTRACT`, `WL_REGION_SUBTRACT_SINCE_VERSION`, `WL_REGISTRY_BIND`, `WL_REGISTRY_BIND_SINCE_VERSION`, `WL_REGISTRY_GLOBAL_REMOVE_SINCE_VERSION`, `WL_REGISTRY_GLOBAL_SINCE_VERSION`, `WL_REGISTRY_INTERFACE`, `WL_SEAT_CAPABILITIES_SINCE_VERSION`, `WL_SEAT_CAPABILITY_ENUM`, `WL_SEAT_ERROR_ENUM`, `WL_SEAT_GET_KEYBOARD`, `WL_SEAT_GET_KEYBOARD_SINCE_VERSION`, `WL_SEAT_GET_POINTER`, `WL_SEAT_GET_POINTER_SINCE_VERSION`, `WL_SEAT_GET_TOUCH`, `WL_SEAT_GET_TOUCH_SINCE_VERSION`, `WL_SEAT_INTERFACE`, `WL_SEAT_NAME_SINCE_VERSION`, `WL_SEAT_RELEASE`, `WL_SEAT_RELEASE_SINCE_VERSION`, `WL_SHELL_ERROR_ENUM`, `WL_SHELL_GET_SHELL_SURFACE`, `WL_SHELL_GET_SHELL_SURFACE_SINCE_VERSION`, `WL_SHELL_INTERFACE`, `WL_SHELL_SURFACE_CONFIGURE_SINCE_VERSION`, `WL_SHELL_SURFACE_FULLSCREEN_METHOD_ENUM`, `WL_SHELL_SURFACE_INTERFACE`, `WL_SHELL_SURFACE_MOVE`, `WL_SHELL_SURFACE_MOVE_SINCE_VERSION`, `WL_SHELL_SURFACE_PING_SINCE_VERSION`, `WL_SHELL_SURFACE_PONG`, `WL_SHELL_SURFACE_PONG_SINCE_VERSION`, `WL_SHELL_SURFACE_POPUP_DONE_SINCE_VERSION`, `WL_SHELL_SURFACE_RESIZE`, `WL_SHELL_SURFACE_RESIZE_ENUM`, `WL_SHELL_SURFACE_RESIZE_SINCE_VERSION`, `WL_SHELL_SURFACE_SET_CLASS`, `WL_SHELL_SURFACE_SET_CLASS_SINCE_VERSION`, `WL_SHELL_SURFACE_SET_FULLSCREEN`, `WL_SHELL_SURFACE_SET_FULLSCREEN_SINCE_VERSION`, `WL_SHELL_SURFACE_SET_MAXIMIZED`, `WL_SHELL_SURFACE_SET_MAXIMIZED_SINCE_VERSION`, `WL_SHELL_SURFACE_SET_POPUP`, `WL_SHELL_SURFACE_SET_POPUP_SINCE_VERSION`, `WL_SHELL_SURFACE_SET_TITLE`, `WL_SHELL_SURFACE_SET_TITLE_SINCE_VERSION`, `WL_SHELL_SURFACE_SET_TOPLEVEL`, `WL_SHELL_SURFACE_SET_TOPLEVEL_SINCE_VERSION`, `WL_SHELL_SURFACE_SET_TRANSIENT`, `WL_SHELL_SURFACE_SET_TRANSIENT_SINCE_VERSION`, `WL_SHELL_SURFACE_TRANSIENT_ENUM`, `WL_SHM_CREATE_POOL`, `WL_SHM_CREATE_POOL_SINCE_VERSION`, `WL_SHM_ERROR_ENUM`, `WL_SHM_FORMAT_ENUM`, `WL_SHM_FORMAT_SINCE_VERSION`, `WL_SHM_INTERFACE`, `WL_SHM_POOL_CREATE_BUFFER`, `WL_SHM_POOL_CREATE_BUFFER_SINCE_VERSION`, `WL_SHM_POOL_DESTROY`, `WL_SHM_POOL_DESTROY_SINCE_VERSION`, `WL_SHM_POOL_ERROR_ENUM`, `WL_SHM_POOL_INTERFACE`, `WL_SHM_POOL_RESIZE`, `WL_SHM_POOL_RESIZE_SINCE_VERSION`, `WL_SHM_RELEASE`, `WL_SHM_RELEASE_SINCE_VERSION`, `WL_SUBCOMPOSITOR_DESTROY`, `WL_SUBCOMPOSITOR_DESTROY_SINCE_VERSION`, `WL_SUBCOMPOSITOR_ERROR_ENUM`, `WL_SUBCOMPOSITOR_GET_SUBSURFACE`, `WL_SUBCOMPOSITOR_GET_SUBSURFACE_SINCE_VERSION`, `WL_SUBCOMPOSITOR_INTERFACE`, `WL_SUBSURFACE_DESTROY`, `WL_SUBSURFACE_DESTROY_SINCE_VERSION`, `WL_SUBSURFACE_ERROR_ENUM`, `WL_SUBSURFACE_INTERFACE`, `WL_SUBSURFACE_PLACE_ABOVE`, `WL_SUBSURFACE_PLACE_ABOVE_SINCE_VERSION`, `WL_SUBSURFACE_PLACE_BELOW`, `WL_SUBSURFACE_PLACE_BELOW_SINCE_VERSION`, `WL_SUBSURFACE_SET_DESYNC`, `WL_SUBSURFACE_SET_DESYNC_SINCE_VERSION`, `WL_SUBSURFACE_SET_POSITION`, `WL_SUBSURFACE_SET_POSITION_SINCE_VERSION`, `WL_SUBSURFACE_SET_SYNC`, `WL_SUBSURFACE_SET_SYNC_SINCE_VERSION`, `WL_SURFACE_ATTACH`, `WL_SURFACE_ATTACH_SINCE_VERSION`, `WL_SURFACE_COMMIT`, `WL_SURFACE_COMMIT_SINCE_VERSION`, `WL_SURFACE_DAMAGE`, `WL_SURFACE_DAMAGE_BUFFER`, `WL_SURFACE_DAMAGE_BUFFER_SINCE_VERSION`, `WL_SURFACE_DAMAGE_SINCE_VERSION`, `WL_SURFACE_DESTROY`, `WL_SURFACE_DESTROY_SINCE_VERSION`, `WL_SURFACE_ENTER_SINCE_VERSION`, `WL_SURFACE_ERROR_ENUM`, `WL_SURFACE_FRAME`, `WL_SURFACE_FRAME_SINCE_VERSION`, `WL_SURFACE_GET_RELEASE`, `WL_SURFACE_GET_RELEASE_SINCE_VERSION`, `WL_SURFACE_INTERFACE`, `WL_SURFACE_LEAVE_SINCE_VERSION`, `WL_SURFACE_OFFSET`, `WL_SURFACE_OFFSET_SINCE_VERSION`, `WL_SURFACE_PREFERRED_BUFFER_SCALE_SINCE_VERSION`, `WL_SURFACE_PREFERRED_BUFFER_TRANSFORM_SINCE_VERSION`, `WL_SURFACE_SET_BUFFER_SCALE`, `WL_SURFACE_SET_BUFFER_SCALE_SINCE_VERSION`, `WL_SURFACE_SET_BUFFER_TRANSFORM`, `WL_SURFACE_SET_BUFFER_TRANSFORM_SINCE_VERSION`, `WL_SURFACE_SET_INPUT_REGION`, `WL_SURFACE_SET_INPUT_REGION_SINCE_VERSION`, `WL_SURFACE_SET_OPAQUE_REGION`, `WL_SURFACE_SET_OPAQUE_REGION_SINCE_VERSION`, `WL_TOUCH_CANCEL_SINCE_VERSION`, `WL_TOUCH_DOWN_SINCE_VERSION`, `WL_TOUCH_FRAME_SINCE_VERSION`, `WL_TOUCH_INTERFACE`, `WL_TOUCH_MOTION_SINCE_VERSION`, `WL_TOUCH_ORIENTATION_SINCE_VERSION`, `WL_TOUCH_RELEASE`, `WL_TOUCH_RELEASE_SINCE_VERSION`, `WL_TOUCH_SHAPE_SINCE_VERSION`, `WL_TOUCH_UP_SINCE_VERSION`.

## wayland-client.h

SHA-256: `e9dd1fb014aa6ad848cb7d241cc223b1a70fc0b17fed5997262024e4c05532f7`

Planned namespace: `ClientInterop`. Functions: 0.

Macro contracts: `WAYLAND_CLIENT_H`.

## wayland-cursor.h

SHA-256: `0d9db66fab24f906e72b3640132ba0d90ca6a6b8c39e7bf2b9cfdc25cc15df38`

Planned namespace: `CursorInterop`. Functions: 6.

| C function | Planned compatibility operation | State |
|---|---|---|
| `wl_cursor_frame` | `CursorInterop.wl_cursor_frame` | Planned |
| `wl_cursor_frame_and_duration` | `CursorInterop.wl_cursor_frame_and_duration` | Planned |
| `wl_cursor_image_get_buffer` | `CursorInterop.wl_cursor_image_get_buffer` | Planned |
| `wl_cursor_theme_destroy` | `CursorInterop.wl_cursor_theme_destroy` | Planned |
| `wl_cursor_theme_get_cursor` | `CursorInterop.wl_cursor_theme_get_cursor` | Planned |
| `wl_cursor_theme_load` | `CursorInterop.wl_cursor_theme_load` | Planned |

Named type contracts: `wl_buffer`, `wl_cursor`, `wl_cursor_image`, `wl_cursor_theme`, `wl_shm`.

Macro contracts: `WAYLAND_CURSOR_H`.

## wayland-egl-core.h

SHA-256: `07cd540e327a028066da1dc79dc25126641509857a4478560471540cf1b35c42`

Planned namespace: `EGLInterop`. Functions: 4.

| C function | Planned compatibility operation | State |
|---|---|---|
| `wl_egl_window_create` | `EGLInterop.wl_egl_window_create` | Planned |
| `wl_egl_window_destroy` | `EGLInterop.wl_egl_window_destroy` | Planned |
| `wl_egl_window_get_attached_size` | `EGLInterop.wl_egl_window_get_attached_size` | Planned |
| `wl_egl_window_resize` | `EGLInterop.wl_egl_window_resize` | Planned |

Named type contracts: `wl_egl_window`, `wl_surface`.

Macro contracts: `WAYLAND_EGL_CORE_H`, `WL_EGL_PLATFORM`.

## wayland-egl.h

SHA-256: `e33be2aa8a700a508d175106c12ea5713faf1c9d9f189d6f8af951849a504abd`

Planned namespace: `EGLInterop`. Functions: 0.

Macro contracts: `WAYLAND_EGL_H`.

## wayland-server-core.h

SHA-256: `f5ef7113e406057c41404a15b19307afaac7adb445f72269e30eca072bf928cd`

Planned namespace: `ServerInterop`. Functions: 113.

| C function | Planned compatibility operation | State |
|---|---|---|
| `wl_client_add_destroy_late_listener` | `ServerInterop.wl_client_add_destroy_late_listener` | Planned |
| `wl_client_add_destroy_listener` | `ServerInterop.wl_client_add_destroy_listener` | Planned |
| `wl_client_add_resource_created_listener` | `ServerInterop.wl_client_add_resource_created_listener` | Planned |
| `wl_client_create` | `ServerInterop.wl_client_create` | Planned |
| `wl_client_destroy` | `ServerInterop.wl_client_destroy` | Planned |
| `wl_client_flush` | `ServerInterop.wl_client_flush` | Planned |
| `wl_client_for_each_resource` | `ServerInterop.wl_client_for_each_resource` | Planned |
| `wl_client_from_link` | `ServerInterop.wl_client_from_link` | Planned |
| `wl_client_get_credentials` | `ServerInterop.wl_client_get_credentials` | Planned |
| `wl_client_get_destroy_late_listener` | `ServerInterop.wl_client_get_destroy_late_listener` | Planned |
| `wl_client_get_destroy_listener` | `ServerInterop.wl_client_get_destroy_listener` | Planned |
| `wl_client_get_display` | `ServerInterop.wl_client_get_display` | Planned |
| `wl_client_get_fd` | `ServerInterop.wl_client_get_fd` | Planned |
| `wl_client_get_link` | `ServerInterop.wl_client_get_link` | Planned |
| `wl_client_get_object` | `ServerInterop.wl_client_get_object` | Planned |
| `wl_client_get_user_data` | `ServerInterop.wl_client_get_user_data` | Planned |
| `wl_client_post_implementation_error` | `ServerInterop.wl_client_post_implementation_error` | Planned |
| `wl_client_post_no_memory` | `ServerInterop.wl_client_post_no_memory` | Planned |
| `wl_client_set_max_buffer_size` | `ServerInterop.wl_client_set_max_buffer_size` | Planned |
| `wl_client_set_user_data` | `ServerInterop.wl_client_set_user_data` | Planned |
| `wl_display_add_client_created_listener` | `ServerInterop.wl_display_add_client_created_listener` | Planned |
| `wl_display_add_destroy_listener` | `ServerInterop.wl_display_add_destroy_listener` | Planned |
| `wl_display_add_protocol_logger` | `ServerInterop.wl_display_add_protocol_logger` | Planned |
| `wl_display_add_shm_format` | `ServerInterop.wl_display_add_shm_format` | Planned |
| `wl_display_add_socket` | `ServerInterop.wl_display_add_socket` | Planned |
| `wl_display_add_socket_auto` | `ServerInterop.wl_display_add_socket_auto` | Planned |
| `wl_display_add_socket_fd` | `ServerInterop.wl_display_add_socket_fd` | Planned |
| `wl_display_create` | `ServerInterop.wl_display_create` | Planned |
| `wl_display_destroy` | `ServerInterop.wl_display_destroy` | Planned |
| `wl_display_destroy_clients` | `ServerInterop.wl_display_destroy_clients` | Planned |
| `wl_display_flush_clients` | `ServerInterop.wl_display_flush_clients` | Planned |
| `wl_display_get_client_list` | `ServerInterop.wl_display_get_client_list` | Planned |
| `wl_display_get_destroy_listener` | `ServerInterop.wl_display_get_destroy_listener` | Planned |
| `wl_display_get_event_loop` | `ServerInterop.wl_display_get_event_loop` | Planned |
| `wl_display_get_serial` | `ServerInterop.wl_display_get_serial` | Planned |
| `wl_display_init_shm` | `ServerInterop.wl_display_init_shm` | Planned |
| `wl_display_next_serial` | `ServerInterop.wl_display_next_serial` | Planned |
| `wl_display_remove_socket_fd` | `ServerInterop.wl_display_remove_socket_fd` | Planned |
| `wl_display_run` | `ServerInterop.wl_display_run` | Planned |
| `wl_display_set_default_max_buffer_size` | `ServerInterop.wl_display_set_default_max_buffer_size` | Planned |
| `wl_display_set_global_filter` | `ServerInterop.wl_display_set_global_filter` | Planned |
| `wl_display_terminate` | `ServerInterop.wl_display_terminate` | Planned |
| `wl_event_loop_add_destroy_listener` | `ServerInterop.wl_event_loop_add_destroy_listener` | Planned |
| `wl_event_loop_add_fd` | `ServerInterop.wl_event_loop_add_fd` | Planned |
| `wl_event_loop_add_idle` | `ServerInterop.wl_event_loop_add_idle` | Planned |
| `wl_event_loop_add_signal` | `ServerInterop.wl_event_loop_add_signal` | Planned |
| `wl_event_loop_add_timer` | `ServerInterop.wl_event_loop_add_timer` | Planned |
| `wl_event_loop_create` | `ServerInterop.wl_event_loop_create` | Planned |
| `wl_event_loop_destroy` | `ServerInterop.wl_event_loop_destroy` | Planned |
| `wl_event_loop_dispatch` | `ServerInterop.wl_event_loop_dispatch` | Planned |
| `wl_event_loop_dispatch_idle` | `ServerInterop.wl_event_loop_dispatch_idle` | Planned |
| `wl_event_loop_get_destroy_listener` | `ServerInterop.wl_event_loop_get_destroy_listener` | Planned |
| `wl_event_loop_get_fd` | `ServerInterop.wl_event_loop_get_fd` | Planned |
| `wl_event_source_check` | `ServerInterop.wl_event_source_check` | Planned |
| `wl_event_source_fd_update` | `ServerInterop.wl_event_source_fd_update` | Planned |
| `wl_event_source_remove` | `ServerInterop.wl_event_source_remove` | Planned |
| `wl_event_source_timer_update` | `ServerInterop.wl_event_source_timer_update` | Planned |
| `wl_fixes_handle_ack_global_remove` | `ServerInterop.wl_fixes_handle_ack_global_remove` | Planned |
| `wl_global_create` | `ServerInterop.wl_global_create` | Planned |
| `wl_global_destroy` | `ServerInterop.wl_global_destroy` | Planned |
| `wl_global_get_display` | `ServerInterop.wl_global_get_display` | Planned |
| `wl_global_get_interface` | `ServerInterop.wl_global_get_interface` | Planned |
| `wl_global_get_name` | `ServerInterop.wl_global_get_name` | Planned |
| `wl_global_get_user_data` | `ServerInterop.wl_global_get_user_data` | Planned |
| `wl_global_get_version` | `ServerInterop.wl_global_get_version` | Planned |
| `wl_global_remove` | `ServerInterop.wl_global_remove` | Planned |
| `wl_global_set_user_data` | `ServerInterop.wl_global_set_user_data` | Planned |
| `wl_global_set_withdrawn_listener` | `ServerInterop.wl_global_set_withdrawn_listener` | Planned |
| `wl_log_set_handler_server` | `ServerInterop.wl_log_set_handler_server` | Planned |
| `wl_protocol_logger_destroy` | `ServerInterop.wl_protocol_logger_destroy` | Planned |
| `wl_resource_add_destroy_listener` | `ServerInterop.wl_resource_add_destroy_listener` | Planned |
| `wl_resource_create` | `ServerInterop.wl_resource_create` | Planned |
| `wl_resource_destroy` | `ServerInterop.wl_resource_destroy` | Planned |
| `wl_resource_find_for_client` | `ServerInterop.wl_resource_find_for_client` | Planned |
| `wl_resource_from_link` | `ServerInterop.wl_resource_from_link` | Planned |
| `wl_resource_get_class` | `ServerInterop.wl_resource_get_class` | Planned |
| `wl_resource_get_client` | `ServerInterop.wl_resource_get_client` | Planned |
| `wl_resource_get_destroy_listener` | `ServerInterop.wl_resource_get_destroy_listener` | Planned |
| `wl_resource_get_id` | `ServerInterop.wl_resource_get_id` | Planned |
| `wl_resource_get_interface` | `ServerInterop.wl_resource_get_interface` | Planned |
| `wl_resource_get_link` | `ServerInterop.wl_resource_get_link` | Planned |
| `wl_resource_get_user_data` | `ServerInterop.wl_resource_get_user_data` | Planned |
| `wl_resource_get_version` | `ServerInterop.wl_resource_get_version` | Planned |
| `wl_resource_instance_of` | `ServerInterop.wl_resource_instance_of` | Planned |
| `wl_resource_post_error` | `ServerInterop.wl_resource_post_error` | Planned |
| `wl_resource_post_error_vargs` | `ServerInterop.wl_resource_post_error_vargs` | Planned |
| `wl_resource_post_event` | `ServerInterop.wl_resource_post_event` | Planned |
| `wl_resource_post_event_array` | `ServerInterop.wl_resource_post_event_array` | Planned |
| `wl_resource_post_no_memory` | `ServerInterop.wl_resource_post_no_memory` | Planned |
| `wl_resource_queue_event` | `ServerInterop.wl_resource_queue_event` | Planned |
| `wl_resource_queue_event_array` | `ServerInterop.wl_resource_queue_event_array` | Planned |
| `wl_resource_set_destructor` | `ServerInterop.wl_resource_set_destructor` | Planned |
| `wl_resource_set_dispatcher` | `ServerInterop.wl_resource_set_dispatcher` | Planned |
| `wl_resource_set_implementation` | `ServerInterop.wl_resource_set_implementation` | Planned |
| `wl_resource_set_user_data` | `ServerInterop.wl_resource_set_user_data` | Planned |
| `wl_shm_buffer_begin_access` | `ServerInterop.wl_shm_buffer_begin_access` | Planned |
| `wl_shm_buffer_create` | `ServerInterop.wl_shm_buffer_create` | Planned |
| `wl_shm_buffer_end_access` | `ServerInterop.wl_shm_buffer_end_access` | Planned |
| `wl_shm_buffer_get` | `ServerInterop.wl_shm_buffer_get` | Planned |
| `wl_shm_buffer_get_data` | `ServerInterop.wl_shm_buffer_get_data` | Planned |
| `wl_shm_buffer_get_format` | `ServerInterop.wl_shm_buffer_get_format` | Planned |
| `wl_shm_buffer_get_height` | `ServerInterop.wl_shm_buffer_get_height` | Planned |
| `wl_shm_buffer_get_stride` | `ServerInterop.wl_shm_buffer_get_stride` | Planned |
| `wl_shm_buffer_get_width` | `ServerInterop.wl_shm_buffer_get_width` | Planned |
| `wl_shm_buffer_ref` | `ServerInterop.wl_shm_buffer_ref` | Planned |
| `wl_shm_buffer_ref_pool` | `ServerInterop.wl_shm_buffer_ref_pool` | Planned |
| `wl_shm_buffer_unref` | `ServerInterop.wl_shm_buffer_unref` | Planned |
| `wl_shm_pool_unref` | `ServerInterop.wl_shm_pool_unref` | Planned |
| `wl_signal_add` | `ServerInterop.wl_signal_add` | Planned |
| `wl_signal_emit` | `ServerInterop.wl_signal_emit` | Planned |
| `wl_signal_emit_mutable` | `ServerInterop.wl_signal_emit_mutable` | Planned |
| `wl_signal_get` | `ServerInterop.wl_signal_get` | Planned |
| `wl_signal_init` | `ServerInterop.wl_signal_init` | Planned |

Named type contracts: `wl_client`, `wl_global`, `wl_listener`, `wl_protocol_logger_message`, `wl_protocol_logger_type`, `wl_signal`.

Macro contracts: `WAYLAND_SERVER_CORE_H`, `wl_client_for_each`, `wl_resource_for_each`, `wl_resource_for_each_safe`.

## wayland-server-protocol.h

SHA-256: `7ed8e780f7f1c2183ade2542d7fbf7ca8aa536ce893021928497a99f4c4f113d`

Planned namespace: `ServerProtocolInterop`. Functions: 88.

| C function | Planned compatibility operation | State |
|---|---|---|
| `wl_buffer_send_release` | `ServerProtocolInterop.wl_buffer_send_release` | Planned |
| `wl_callback_send_done` | `ServerProtocolInterop.wl_callback_send_done` | Planned |
| `wl_data_device_error_is_valid` | `ServerProtocolInterop.wl_data_device_error_is_valid` | Planned |
| `wl_data_device_manager_dnd_action_is_valid` | `ServerProtocolInterop.wl_data_device_manager_dnd_action_is_valid` | Planned |
| `wl_data_device_send_data_offer` | `ServerProtocolInterop.wl_data_device_send_data_offer` | Planned |
| `wl_data_device_send_drop` | `ServerProtocolInterop.wl_data_device_send_drop` | Planned |
| `wl_data_device_send_enter` | `ServerProtocolInterop.wl_data_device_send_enter` | Planned |
| `wl_data_device_send_leave` | `ServerProtocolInterop.wl_data_device_send_leave` | Planned |
| `wl_data_device_send_motion` | `ServerProtocolInterop.wl_data_device_send_motion` | Planned |
| `wl_data_device_send_selection` | `ServerProtocolInterop.wl_data_device_send_selection` | Planned |
| `wl_data_offer_error_is_valid` | `ServerProtocolInterop.wl_data_offer_error_is_valid` | Planned |
| `wl_data_offer_send_action` | `ServerProtocolInterop.wl_data_offer_send_action` | Planned |
| `wl_data_offer_send_offer` | `ServerProtocolInterop.wl_data_offer_send_offer` | Planned |
| `wl_data_offer_send_source_actions` | `ServerProtocolInterop.wl_data_offer_send_source_actions` | Planned |
| `wl_data_source_error_is_valid` | `ServerProtocolInterop.wl_data_source_error_is_valid` | Planned |
| `wl_data_source_send_action` | `ServerProtocolInterop.wl_data_source_send_action` | Planned |
| `wl_data_source_send_cancelled` | `ServerProtocolInterop.wl_data_source_send_cancelled` | Planned |
| `wl_data_source_send_dnd_drop_performed` | `ServerProtocolInterop.wl_data_source_send_dnd_drop_performed` | Planned |
| `wl_data_source_send_dnd_finished` | `ServerProtocolInterop.wl_data_source_send_dnd_finished` | Planned |
| `wl_data_source_send_send` | `ServerProtocolInterop.wl_data_source_send_send` | Planned |
| `wl_data_source_send_target` | `ServerProtocolInterop.wl_data_source_send_target` | Planned |
| `wl_display_error_is_valid` | `ServerProtocolInterop.wl_display_error_is_valid` | Planned |
| `wl_fixes_error_is_valid` | `ServerProtocolInterop.wl_fixes_error_is_valid` | Planned |
| `wl_keyboard_key_state_is_valid` | `ServerProtocolInterop.wl_keyboard_key_state_is_valid` | Planned |
| `wl_keyboard_keymap_format_is_valid` | `ServerProtocolInterop.wl_keyboard_keymap_format_is_valid` | Planned |
| `wl_keyboard_send_enter` | `ServerProtocolInterop.wl_keyboard_send_enter` | Planned |
| `wl_keyboard_send_key` | `ServerProtocolInterop.wl_keyboard_send_key` | Planned |
| `wl_keyboard_send_keymap` | `ServerProtocolInterop.wl_keyboard_send_keymap` | Planned |
| `wl_keyboard_send_leave` | `ServerProtocolInterop.wl_keyboard_send_leave` | Planned |
| `wl_keyboard_send_modifiers` | `ServerProtocolInterop.wl_keyboard_send_modifiers` | Planned |
| `wl_keyboard_send_repeat_info` | `ServerProtocolInterop.wl_keyboard_send_repeat_info` | Planned |
| `wl_output_mode_is_valid` | `ServerProtocolInterop.wl_output_mode_is_valid` | Planned |
| `wl_output_send_description` | `ServerProtocolInterop.wl_output_send_description` | Planned |
| `wl_output_send_done` | `ServerProtocolInterop.wl_output_send_done` | Planned |
| `wl_output_send_geometry` | `ServerProtocolInterop.wl_output_send_geometry` | Planned |
| `wl_output_send_mode` | `ServerProtocolInterop.wl_output_send_mode` | Planned |
| `wl_output_send_name` | `ServerProtocolInterop.wl_output_send_name` | Planned |
| `wl_output_send_scale` | `ServerProtocolInterop.wl_output_send_scale` | Planned |
| `wl_output_subpixel_is_valid` | `ServerProtocolInterop.wl_output_subpixel_is_valid` | Planned |
| `wl_output_transform_is_valid` | `ServerProtocolInterop.wl_output_transform_is_valid` | Planned |
| `wl_pointer_axis_is_valid` | `ServerProtocolInterop.wl_pointer_axis_is_valid` | Planned |
| `wl_pointer_axis_relative_direction_is_valid` | `ServerProtocolInterop.wl_pointer_axis_relative_direction_is_valid` | Planned |
| `wl_pointer_axis_source_is_valid` | `ServerProtocolInterop.wl_pointer_axis_source_is_valid` | Planned |
| `wl_pointer_button_state_is_valid` | `ServerProtocolInterop.wl_pointer_button_state_is_valid` | Planned |
| `wl_pointer_error_is_valid` | `ServerProtocolInterop.wl_pointer_error_is_valid` | Planned |
| `wl_pointer_send_axis` | `ServerProtocolInterop.wl_pointer_send_axis` | Planned |
| `wl_pointer_send_axis_discrete` | `ServerProtocolInterop.wl_pointer_send_axis_discrete` | Planned |
| `wl_pointer_send_axis_relative_direction` | `ServerProtocolInterop.wl_pointer_send_axis_relative_direction` | Planned |
| `wl_pointer_send_axis_source` | `ServerProtocolInterop.wl_pointer_send_axis_source` | Planned |
| `wl_pointer_send_axis_stop` | `ServerProtocolInterop.wl_pointer_send_axis_stop` | Planned |
| `wl_pointer_send_axis_value120` | `ServerProtocolInterop.wl_pointer_send_axis_value120` | Planned |
| `wl_pointer_send_button` | `ServerProtocolInterop.wl_pointer_send_button` | Planned |
| `wl_pointer_send_enter` | `ServerProtocolInterop.wl_pointer_send_enter` | Planned |
| `wl_pointer_send_frame` | `ServerProtocolInterop.wl_pointer_send_frame` | Planned |
| `wl_pointer_send_leave` | `ServerProtocolInterop.wl_pointer_send_leave` | Planned |
| `wl_pointer_send_motion` | `ServerProtocolInterop.wl_pointer_send_motion` | Planned |
| `wl_pointer_send_warp` | `ServerProtocolInterop.wl_pointer_send_warp` | Planned |
| `wl_registry_send_global` | `ServerProtocolInterop.wl_registry_send_global` | Planned |
| `wl_registry_send_global_remove` | `ServerProtocolInterop.wl_registry_send_global_remove` | Planned |
| `wl_seat_capability_is_valid` | `ServerProtocolInterop.wl_seat_capability_is_valid` | Planned |
| `wl_seat_error_is_valid` | `ServerProtocolInterop.wl_seat_error_is_valid` | Planned |
| `wl_seat_send_capabilities` | `ServerProtocolInterop.wl_seat_send_capabilities` | Planned |
| `wl_seat_send_name` | `ServerProtocolInterop.wl_seat_send_name` | Planned |
| `wl_shell_error_is_valid` | `ServerProtocolInterop.wl_shell_error_is_valid` | Planned |
| `wl_shell_surface_fullscreen_method_is_valid` | `ServerProtocolInterop.wl_shell_surface_fullscreen_method_is_valid` | Planned |
| `wl_shell_surface_resize_is_valid` | `ServerProtocolInterop.wl_shell_surface_resize_is_valid` | Planned |
| `wl_shell_surface_send_configure` | `ServerProtocolInterop.wl_shell_surface_send_configure` | Planned |
| `wl_shell_surface_send_ping` | `ServerProtocolInterop.wl_shell_surface_send_ping` | Planned |
| `wl_shell_surface_send_popup_done` | `ServerProtocolInterop.wl_shell_surface_send_popup_done` | Planned |
| `wl_shell_surface_transient_is_valid` | `ServerProtocolInterop.wl_shell_surface_transient_is_valid` | Planned |
| `wl_shm_error_is_valid` | `ServerProtocolInterop.wl_shm_error_is_valid` | Planned |
| `wl_shm_format_is_valid` | `ServerProtocolInterop.wl_shm_format_is_valid` | Planned |
| `wl_shm_pool_error_is_valid` | `ServerProtocolInterop.wl_shm_pool_error_is_valid` | Planned |
| `wl_shm_send_format` | `ServerProtocolInterop.wl_shm_send_format` | Planned |
| `wl_subcompositor_error_is_valid` | `ServerProtocolInterop.wl_subcompositor_error_is_valid` | Planned |
| `wl_subsurface_error_is_valid` | `ServerProtocolInterop.wl_subsurface_error_is_valid` | Planned |
| `wl_surface_error_is_valid` | `ServerProtocolInterop.wl_surface_error_is_valid` | Planned |
| `wl_surface_send_enter` | `ServerProtocolInterop.wl_surface_send_enter` | Planned |
| `wl_surface_send_leave` | `ServerProtocolInterop.wl_surface_send_leave` | Planned |
| `wl_surface_send_preferred_buffer_scale` | `ServerProtocolInterop.wl_surface_send_preferred_buffer_scale` | Planned |
| `wl_surface_send_preferred_buffer_transform` | `ServerProtocolInterop.wl_surface_send_preferred_buffer_transform` | Planned |
| `wl_touch_send_cancel` | `ServerProtocolInterop.wl_touch_send_cancel` | Planned |
| `wl_touch_send_down` | `ServerProtocolInterop.wl_touch_send_down` | Planned |
| `wl_touch_send_frame` | `ServerProtocolInterop.wl_touch_send_frame` | Planned |
| `wl_touch_send_motion` | `ServerProtocolInterop.wl_touch_send_motion` | Planned |
| `wl_touch_send_orientation` | `ServerProtocolInterop.wl_touch_send_orientation` | Planned |
| `wl_touch_send_shape` | `ServerProtocolInterop.wl_touch_send_shape` | Planned |
| `wl_touch_send_up` | `ServerProtocolInterop.wl_touch_send_up` | Planned |

Named type contracts: `wl_buffer`, `wl_buffer_interface`, `wl_callback`, `wl_client`, `wl_compositor`, `wl_compositor_interface`, `wl_data_device`, `wl_data_device_error`, `wl_data_device_interface`, `wl_data_device_manager`, `wl_data_device_manager_dnd_action`, `wl_data_device_manager_interface`, `wl_data_offer`, `wl_data_offer_error`, `wl_data_offer_interface`, `wl_data_source`, `wl_data_source_error`, `wl_data_source_interface`, `wl_display`, `wl_display_error`, `wl_display_interface`, `wl_fixes`, `wl_fixes_error`, `wl_fixes_interface`, `wl_keyboard`, `wl_keyboard_interface`, `wl_keyboard_key_state`, `wl_keyboard_keymap_format`, `wl_output`, `wl_output_interface`, `wl_output_mode`, `wl_output_subpixel`, `wl_output_transform`, `wl_pointer`, `wl_pointer_axis`, `wl_pointer_axis_relative_direction`, `wl_pointer_axis_source`, `wl_pointer_button_state`, `wl_pointer_error`, `wl_pointer_interface`, `wl_region`, `wl_region_interface`, `wl_registry`, `wl_registry_interface`, `wl_resource`, `wl_seat`, `wl_seat_capability`, `wl_seat_error`, `wl_seat_interface`, `wl_shell`, `wl_shell_error`, `wl_shell_interface`, `wl_shell_surface`, `wl_shell_surface_fullscreen_method`, `wl_shell_surface_interface`, `wl_shell_surface_resize`, `wl_shell_surface_transient`, `wl_shm`, `wl_shm_error`, `wl_shm_format`, `wl_shm_interface`, `wl_shm_pool`, `wl_shm_pool_error`, `wl_shm_pool_interface`, `wl_subcompositor`, `wl_subcompositor_error`, `wl_subcompositor_interface`, `wl_subsurface`, `wl_subsurface_error`, `wl_subsurface_interface`, `wl_surface`, `wl_surface_error`, `wl_surface_interface`, `wl_touch`, `wl_touch_interface`.

Macro contracts: `WAYLAND_SERVER_PROTOCOL_H`, `WL_BUFFER_DESTROY_SINCE_VERSION`, `WL_BUFFER_INTERFACE`, `WL_BUFFER_RELEASE`, `WL_BUFFER_RELEASE_SINCE_VERSION`, `WL_CALLBACK_DONE`, `WL_CALLBACK_DONE_SINCE_VERSION`, `WL_CALLBACK_INTERFACE`, `WL_COMPOSITOR_CREATE_REGION_SINCE_VERSION`, `WL_COMPOSITOR_CREATE_SURFACE_SINCE_VERSION`, `WL_COMPOSITOR_INTERFACE`, `WL_COMPOSITOR_RELEASE_SINCE_VERSION`, `WL_DATA_DEVICE_DATA_OFFER`, `WL_DATA_DEVICE_DATA_OFFER_SINCE_VERSION`, `WL_DATA_DEVICE_DROP`, `WL_DATA_DEVICE_DROP_SINCE_VERSION`, `WL_DATA_DEVICE_ENTER`, `WL_DATA_DEVICE_ENTER_SINCE_VERSION`, `WL_DATA_DEVICE_ERROR_ENUM`, `WL_DATA_DEVICE_ERROR_ENUM_IS_VALID`, `WL_DATA_DEVICE_INTERFACE`, `WL_DATA_DEVICE_LEAVE`, `WL_DATA_DEVICE_LEAVE_SINCE_VERSION`, `WL_DATA_DEVICE_MANAGER_CREATE_DATA_SOURCE_SINCE_VERSION`, `WL_DATA_DEVICE_MANAGER_DND_ACTION_ENUM`, `WL_DATA_DEVICE_MANAGER_DND_ACTION_ENUM_IS_VALID`, `WL_DATA_DEVICE_MANAGER_GET_DATA_DEVICE_SINCE_VERSION`, `WL_DATA_DEVICE_MANAGER_INTERFACE`, `WL_DATA_DEVICE_MANAGER_RELEASE_SINCE_VERSION`, `WL_DATA_DEVICE_MOTION`, `WL_DATA_DEVICE_MOTION_SINCE_VERSION`, `WL_DATA_DEVICE_RELEASE_SINCE_VERSION`, `WL_DATA_DEVICE_SELECTION`, `WL_DATA_DEVICE_SELECTION_SINCE_VERSION`, `WL_DATA_DEVICE_SET_SELECTION_SINCE_VERSION`, `WL_DATA_DEVICE_START_DRAG_SINCE_VERSION`, `WL_DATA_OFFER_ACCEPT_SINCE_VERSION`, `WL_DATA_OFFER_ACTION`, `WL_DATA_OFFER_ACTION_SINCE_VERSION`, `WL_DATA_OFFER_DESTROY_SINCE_VERSION`, `WL_DATA_OFFER_ERROR_ENUM`, `WL_DATA_OFFER_ERROR_ENUM_IS_VALID`, `WL_DATA_OFFER_FINISH_SINCE_VERSION`, `WL_DATA_OFFER_INTERFACE`, `WL_DATA_OFFER_OFFER`, `WL_DATA_OFFER_OFFER_SINCE_VERSION`, `WL_DATA_OFFER_RECEIVE_SINCE_VERSION`, `WL_DATA_OFFER_SET_ACTIONS_SINCE_VERSION`, `WL_DATA_OFFER_SOURCE_ACTIONS`, `WL_DATA_OFFER_SOURCE_ACTIONS_SINCE_VERSION`, `WL_DATA_SOURCE_ACTION`, `WL_DATA_SOURCE_ACTION_SINCE_VERSION`, `WL_DATA_SOURCE_CANCELLED`, `WL_DATA_SOURCE_CANCELLED_SINCE_VERSION`, `WL_DATA_SOURCE_DESTROY_SINCE_VERSION`, `WL_DATA_SOURCE_DND_DROP_PERFORMED`, `WL_DATA_SOURCE_DND_DROP_PERFORMED_SINCE_VERSION`, `WL_DATA_SOURCE_DND_FINISHED`, `WL_DATA_SOURCE_DND_FINISHED_SINCE_VERSION`, `WL_DATA_SOURCE_ERROR_ENUM`, `WL_DATA_SOURCE_ERROR_ENUM_IS_VALID`, `WL_DATA_SOURCE_INTERFACE`, `WL_DATA_SOURCE_OFFER_SINCE_VERSION`, `WL_DATA_SOURCE_SEND`, `WL_DATA_SOURCE_SEND_SINCE_VERSION`, `WL_DATA_SOURCE_SET_ACTIONS_SINCE_VERSION`, `WL_DATA_SOURCE_TARGET`, `WL_DATA_SOURCE_TARGET_SINCE_VERSION`, `WL_DISPLAY_DELETE_ID`, `WL_DISPLAY_DELETE_ID_SINCE_VERSION`, `WL_DISPLAY_ERROR`, `WL_DISPLAY_ERROR_ENUM`, `WL_DISPLAY_ERROR_ENUM_IS_VALID`, `WL_DISPLAY_ERROR_SINCE_VERSION`, `WL_DISPLAY_GET_REGISTRY_SINCE_VERSION`, `WL_DISPLAY_INTERFACE`, `WL_DISPLAY_SYNC_SINCE_VERSION`, `WL_FIXES_ACK_GLOBAL_REMOVE_SINCE_VERSION`, `WL_FIXES_DESTROY_REGISTRY_SINCE_VERSION`, `WL_FIXES_DESTROY_SINCE_VERSION`, `WL_FIXES_ERROR_ENUM`, `WL_FIXES_ERROR_ENUM_IS_VALID`, `WL_FIXES_INTERFACE`, `WL_KEYBOARD_ENTER`, `WL_KEYBOARD_ENTER_SINCE_VERSION`, `WL_KEYBOARD_INTERFACE`, `WL_KEYBOARD_KEY`, `WL_KEYBOARD_KEYMAP`, `WL_KEYBOARD_KEYMAP_FORMAT_ENUM`, `WL_KEYBOARD_KEYMAP_FORMAT_ENUM_IS_VALID`, `WL_KEYBOARD_KEYMAP_SINCE_VERSION`, `WL_KEYBOARD_KEY_SINCE_VERSION`, `WL_KEYBOARD_KEY_STATE_ENUM`, `WL_KEYBOARD_KEY_STATE_ENUM_IS_VALID`, `WL_KEYBOARD_KEY_STATE_REPEATED_SINCE_VERSION`, `WL_KEYBOARD_LEAVE`, `WL_KEYBOARD_LEAVE_SINCE_VERSION`, `WL_KEYBOARD_MODIFIERS`, `WL_KEYBOARD_MODIFIERS_SINCE_VERSION`, `WL_KEYBOARD_RELEASE_SINCE_VERSION`, `WL_KEYBOARD_REPEAT_INFO`, `WL_KEYBOARD_REPEAT_INFO_SINCE_VERSION`, `WL_OUTPUT_DESCRIPTION`, `WL_OUTPUT_DESCRIPTION_SINCE_VERSION`, `WL_OUTPUT_DONE`, `WL_OUTPUT_DONE_SINCE_VERSION`, `WL_OUTPUT_GEOMETRY`, `WL_OUTPUT_GEOMETRY_SINCE_VERSION`, `WL_OUTPUT_INTERFACE`, `WL_OUTPUT_MODE`, `WL_OUTPUT_MODE_ENUM`, `WL_OUTPUT_MODE_ENUM_IS_VALID`, `WL_OUTPUT_MODE_SINCE_VERSION`, `WL_OUTPUT_NAME`, `WL_OUTPUT_NAME_SINCE_VERSION`, `WL_OUTPUT_RELEASE_SINCE_VERSION`, `WL_OUTPUT_SCALE`, `WL_OUTPUT_SCALE_SINCE_VERSION`, `WL_OUTPUT_SUBPIXEL_ENUM`, `WL_OUTPUT_SUBPIXEL_ENUM_IS_VALID`, `WL_OUTPUT_TRANSFORM_ENUM`, `WL_OUTPUT_TRANSFORM_ENUM_IS_VALID`, `WL_POINTER_AXIS`, `WL_POINTER_AXIS_DISCRETE`, `WL_POINTER_AXIS_DISCRETE_SINCE_VERSION`, `WL_POINTER_AXIS_ENUM`, `WL_POINTER_AXIS_ENUM_IS_VALID`, `WL_POINTER_AXIS_RELATIVE_DIRECTION`, `WL_POINTER_AXIS_RELATIVE_DIRECTION_ENUM`, `WL_POINTER_AXIS_RELATIVE_DIRECTION_ENUM_IS_VALID`, `WL_POINTER_AXIS_RELATIVE_DIRECTION_SINCE_VERSION`, `WL_POINTER_AXIS_SINCE_VERSION`, `WL_POINTER_AXIS_SOURCE`, `WL_POINTER_AXIS_SOURCE_ENUM`, `WL_POINTER_AXIS_SOURCE_ENUM_IS_VALID`, `WL_POINTER_AXIS_SOURCE_SINCE_VERSION`, `WL_POINTER_AXIS_SOURCE_WHEEL_TILT_SINCE_VERSION`, `WL_POINTER_AXIS_STOP`, `WL_POINTER_AXIS_STOP_SINCE_VERSION`, `WL_POINTER_AXIS_VALUE120`, `WL_POINTER_AXIS_VALUE120_SINCE_VERSION`, `WL_POINTER_BUTTON`, `WL_POINTER_BUTTON_SINCE_VERSION`, `WL_POINTER_BUTTON_STATE_ENUM`, `WL_POINTER_BUTTON_STATE_ENUM_IS_VALID`, `WL_POINTER_ENTER`, `WL_POINTER_ENTER_SINCE_VERSION`, `WL_POINTER_ERROR_ENUM`, `WL_POINTER_ERROR_ENUM_IS_VALID`, `WL_POINTER_FRAME`, `WL_POINTER_FRAME_SINCE_VERSION`, `WL_POINTER_INTERFACE`, `WL_POINTER_LEAVE`, `WL_POINTER_LEAVE_SINCE_VERSION`, `WL_POINTER_MOTION`, `WL_POINTER_MOTION_SINCE_VERSION`, `WL_POINTER_RELEASE_SINCE_VERSION`, `WL_POINTER_SET_CURSOR_SINCE_VERSION`, `WL_POINTER_WARP`, `WL_POINTER_WARP_SINCE_VERSION`, `WL_REGION_ADD_SINCE_VERSION`, `WL_REGION_DESTROY_SINCE_VERSION`, `WL_REGION_INTERFACE`, `WL_REGION_SUBTRACT_SINCE_VERSION`, `WL_REGISTRY_BIND_SINCE_VERSION`, `WL_REGISTRY_GLOBAL`, `WL_REGISTRY_GLOBAL_REMOVE`, `WL_REGISTRY_GLOBAL_REMOVE_SINCE_VERSION`, `WL_REGISTRY_GLOBAL_SINCE_VERSION`, `WL_REGISTRY_INTERFACE`, `WL_SEAT_CAPABILITIES`, `WL_SEAT_CAPABILITIES_SINCE_VERSION`, `WL_SEAT_CAPABILITY_ENUM`, `WL_SEAT_CAPABILITY_ENUM_IS_VALID`, `WL_SEAT_ERROR_ENUM`, `WL_SEAT_ERROR_ENUM_IS_VALID`, `WL_SEAT_GET_KEYBOARD_SINCE_VERSION`, `WL_SEAT_GET_POINTER_SINCE_VERSION`, `WL_SEAT_GET_TOUCH_SINCE_VERSION`, `WL_SEAT_INTERFACE`, `WL_SEAT_NAME`, `WL_SEAT_NAME_SINCE_VERSION`, `WL_SEAT_RELEASE_SINCE_VERSION`, `WL_SHELL_ERROR_ENUM`, `WL_SHELL_ERROR_ENUM_IS_VALID`, `WL_SHELL_GET_SHELL_SURFACE_SINCE_VERSION`, `WL_SHELL_INTERFACE`, `WL_SHELL_SURFACE_CONFIGURE`, `WL_SHELL_SURFACE_CONFIGURE_SINCE_VERSION`, `WL_SHELL_SURFACE_FULLSCREEN_METHOD_ENUM`, `WL_SHELL_SURFACE_FULLSCREEN_METHOD_ENUM_IS_VALID`, `WL_SHELL_SURFACE_INTERFACE`, `WL_SHELL_SURFACE_MOVE_SINCE_VERSION`, `WL_SHELL_SURFACE_PING`, `WL_SHELL_SURFACE_PING_SINCE_VERSION`, `WL_SHELL_SURFACE_PONG_SINCE_VERSION`, `WL_SHELL_SURFACE_POPUP_DONE`, `WL_SHELL_SURFACE_POPUP_DONE_SINCE_VERSION`, `WL_SHELL_SURFACE_RESIZE_ENUM`, `WL_SHELL_SURFACE_RESIZE_ENUM_IS_VALID`, `WL_SHELL_SURFACE_RESIZE_SINCE_VERSION`, `WL_SHELL_SURFACE_SET_CLASS_SINCE_VERSION`, `WL_SHELL_SURFACE_SET_FULLSCREEN_SINCE_VERSION`, `WL_SHELL_SURFACE_SET_MAXIMIZED_SINCE_VERSION`, `WL_SHELL_SURFACE_SET_POPUP_SINCE_VERSION`, `WL_SHELL_SURFACE_SET_TITLE_SINCE_VERSION`, `WL_SHELL_SURFACE_SET_TOPLEVEL_SINCE_VERSION`, `WL_SHELL_SURFACE_SET_TRANSIENT_SINCE_VERSION`, `WL_SHELL_SURFACE_TRANSIENT_ENUM`, `WL_SHELL_SURFACE_TRANSIENT_ENUM_IS_VALID`, `WL_SHM_CREATE_POOL_SINCE_VERSION`, `WL_SHM_ERROR_ENUM`, `WL_SHM_ERROR_ENUM_IS_VALID`, `WL_SHM_FORMAT`, `WL_SHM_FORMAT_ENUM`, `WL_SHM_FORMAT_ENUM_IS_VALID`, `WL_SHM_FORMAT_SINCE_VERSION`, `WL_SHM_INTERFACE`, `WL_SHM_POOL_CREATE_BUFFER_SINCE_VERSION`, `WL_SHM_POOL_DESTROY_SINCE_VERSION`, `WL_SHM_POOL_ERROR_ENUM`, `WL_SHM_POOL_ERROR_ENUM_IS_VALID`, `WL_SHM_POOL_INTERFACE`, `WL_SHM_POOL_RESIZE_SINCE_VERSION`, `WL_SHM_RELEASE_SINCE_VERSION`, `WL_SUBCOMPOSITOR_DESTROY_SINCE_VERSION`, `WL_SUBCOMPOSITOR_ERROR_ENUM`, `WL_SUBCOMPOSITOR_ERROR_ENUM_IS_VALID`, `WL_SUBCOMPOSITOR_GET_SUBSURFACE_SINCE_VERSION`, `WL_SUBCOMPOSITOR_INTERFACE`, `WL_SUBSURFACE_DESTROY_SINCE_VERSION`, `WL_SUBSURFACE_ERROR_ENUM`, `WL_SUBSURFACE_ERROR_ENUM_IS_VALID`, `WL_SUBSURFACE_INTERFACE`, `WL_SUBSURFACE_PLACE_ABOVE_SINCE_VERSION`, `WL_SUBSURFACE_PLACE_BELOW_SINCE_VERSION`, `WL_SUBSURFACE_SET_DESYNC_SINCE_VERSION`, `WL_SUBSURFACE_SET_POSITION_SINCE_VERSION`, `WL_SUBSURFACE_SET_SYNC_SINCE_VERSION`, `WL_SURFACE_ATTACH_SINCE_VERSION`, `WL_SURFACE_COMMIT_SINCE_VERSION`, `WL_SURFACE_DAMAGE_BUFFER_SINCE_VERSION`, `WL_SURFACE_DAMAGE_SINCE_VERSION`, `WL_SURFACE_DESTROY_SINCE_VERSION`, `WL_SURFACE_ENTER`, `WL_SURFACE_ENTER_SINCE_VERSION`, `WL_SURFACE_ERROR_ENUM`, `WL_SURFACE_ERROR_ENUM_IS_VALID`, `WL_SURFACE_FRAME_SINCE_VERSION`, `WL_SURFACE_GET_RELEASE_SINCE_VERSION`, `WL_SURFACE_INTERFACE`, `WL_SURFACE_LEAVE`, `WL_SURFACE_LEAVE_SINCE_VERSION`, `WL_SURFACE_OFFSET_SINCE_VERSION`, `WL_SURFACE_PREFERRED_BUFFER_SCALE`, `WL_SURFACE_PREFERRED_BUFFER_SCALE_SINCE_VERSION`, `WL_SURFACE_PREFERRED_BUFFER_TRANSFORM`, `WL_SURFACE_PREFERRED_BUFFER_TRANSFORM_SINCE_VERSION`, `WL_SURFACE_SET_BUFFER_SCALE_SINCE_VERSION`, `WL_SURFACE_SET_BUFFER_TRANSFORM_SINCE_VERSION`, `WL_SURFACE_SET_INPUT_REGION_SINCE_VERSION`, `WL_SURFACE_SET_OPAQUE_REGION_SINCE_VERSION`, `WL_TOUCH_CANCEL`, `WL_TOUCH_CANCEL_SINCE_VERSION`, `WL_TOUCH_DOWN`, `WL_TOUCH_DOWN_SINCE_VERSION`, `WL_TOUCH_FRAME`, `WL_TOUCH_FRAME_SINCE_VERSION`, `WL_TOUCH_INTERFACE`, `WL_TOUCH_MOTION`, `WL_TOUCH_MOTION_SINCE_VERSION`, `WL_TOUCH_ORIENTATION`, `WL_TOUCH_ORIENTATION_SINCE_VERSION`, `WL_TOUCH_RELEASE_SINCE_VERSION`, `WL_TOUCH_SHAPE`, `WL_TOUCH_SHAPE_SINCE_VERSION`, `WL_TOUCH_UP`, `WL_TOUCH_UP_SINCE_VERSION`.

## wayland-server.h

SHA-256: `b57f978e9c28c3f73f92362cc9b741d0b8f00824fb0afe66eaaac47f979cda28`

Planned namespace: `ServerInterop`. Functions: 5.

| C function | Planned compatibility operation | State |
|---|---|---|
| `wl_client_add_object` | `ServerInterop.wl_client_add_object` | Planned |
| `wl_client_add_resource` | `ServerInterop.wl_client_add_resource` | Planned |
| `wl_client_new_object` | `ServerInterop.wl_client_new_object` | Planned |
| `wl_display_add_global` | `ServerInterop.wl_display_add_global` | Planned |
| `wl_display_remove_global` | `ServerInterop.wl_display_remove_global` | Planned |

Named type contracts: `wl_object`, `wl_resource`.

Macro contracts: `WAYLAND_SERVER_H`.

## wayland-util.h

SHA-256: `f336a00a03fcf442a59dc9e5fcce3fc94b2cbfcbcf0befba018be3657b7ea381`

Planned namespace: `UtilityInterop`. Functions: 14.

| C function | Planned compatibility operation | State |
|---|---|---|
| `wl_array_add` | `UtilityInterop.wl_array_add` | Planned |
| `wl_array_copy` | `UtilityInterop.wl_array_copy` | Planned |
| `wl_array_init` | `UtilityInterop.wl_array_init` | Planned |
| `wl_array_release` | `UtilityInterop.wl_array_release` | Planned |
| `wl_fixed_from_double` | `UtilityInterop.wl_fixed_from_double` | Planned |
| `wl_fixed_from_int` | `UtilityInterop.wl_fixed_from_int` | Planned |
| `wl_fixed_to_double` | `UtilityInterop.wl_fixed_to_double` | Planned |
| `wl_fixed_to_int` | `UtilityInterop.wl_fixed_to_int` | Planned |
| `wl_list_empty` | `UtilityInterop.wl_list_empty` | Planned |
| `wl_list_init` | `UtilityInterop.wl_list_init` | Planned |
| `wl_list_insert` | `UtilityInterop.wl_list_insert` | Planned |
| `wl_list_insert_list` | `UtilityInterop.wl_list_insert_list` | Planned |
| `wl_list_length` | `UtilityInterop.wl_list_length` | Planned |
| `wl_list_remove` | `UtilityInterop.wl_list_remove` | Planned |

Named type contracts: `wl_argument`, `wl_array`, `wl_fixed_t`, `wl_interface`, `wl_iterator_result`, `wl_list`, `wl_message`, `wl_object`.

Macro contracts: `WAYLAND_UTIL_H`, `WL_DEPRECATED`, `WL_EXPORT`, `WL_MAX_MESSAGE_SIZE`, `WL_PRINTF`, `WL_TYPEOF`, `wl_array_for_each`, `wl_container_of`, `wl_list_for_each`, `wl_list_for_each_reverse`, `wl_list_for_each_reverse_safe`, `wl_list_for_each_safe`.

## wayland-version.h

SHA-256: `35578b408ab6a91bea914a1b6e462c5b85018ee1c4f83ce89ddc5b36d4ad74ed`

Planned namespace: `UtilityInterop`. Functions: 0.

Macro contracts: `WAYLAND_VERSION`, `WAYLAND_VERSION_H`, `WAYLAND_VERSION_MAJOR`, `WAYLAND_VERSION_MICRO`, `WAYLAND_VERSION_MINOR`.


## Extraction verification

Function declarations were verified using `clang -x c -fsyntax-only -Xclang -ast-dump=json /usr/include/<header>`. Only FunctionDecl nodes whose declaration locations resolve into the selected header are counted. Header-local functions are counted separately across client and server protocol headers; the total is not a count of unique exported ELF symbols. Type fields, enum members, exported data symbols, and macro expansions require the future semantic coverage manifest.
