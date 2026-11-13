# Core protocol inventory

Status: planned generation for both client and server. Source: installed libwayland 1.26.0 `wayland.xml`.

SHA-256: `cc860987e54f8d85c940e97fa1270c69b6e4ad31fbcf5a7f00107ce1157f5e07`

For every request, generate a client sender and server handler. For every event, generate a server sender and client handler. Preserve wire opcode order, since-version, destructor status, nullability, enum references, and interface identity. Generic new_id also carries interface/version metadata. No implementation exists yet.

## wl_display (version 1)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `sync` | 1 | no | callback:new_id:wl_callback |
| request | 1 | `get_registry` | 1 | no | registry:new_id:wl_registry |
| event | 0 | `error` | 1 | no | object_id:object; code:uint; message:string |
| event | 1 | `delete_id` | 1 | no | id:uint |

Enum `error`; bitfield=false; since=1: `invalid_object=0` (since 1), `invalid_method=1` (since 1), `no_memory=2` (since 1), `implementation=3` (since 1).

## wl_registry (version 1)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `bind` | 1 | no | name:uint; id:new_id |
| event | 0 | `global` | 1 | no | name:uint; interface:string; version:uint |
| event | 1 | `global_remove` | 1 | no | name:uint |

## wl_callback (version 1)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| event | 0 | `done` | 1 | yes | callback_data:uint |

## wl_compositor (version 7)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `create_surface` | 1 | no | id:new_id:wl_surface |
| request | 1 | `create_region` | 1 | no | id:new_id:wl_region |
| request | 2 | `release` | 7 | yes | None |

## wl_shm_pool (version 3)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `create_buffer` | 1 | no | id:new_id:wl_buffer; offset:int; width:int; height:int; stride:int; format:uint:wl_shm.format |
| request | 1 | `destroy` | 1 | yes | None |
| request | 2 | `resize` | 1 | no | size:int |

Enum `error`; bitfield=false; since=3: `invalid_format=0` (since 1), `invalid_stride=1` (since 1).

## wl_shm (version 3)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `create_pool` | 1 | no | id:new_id:wl_shm_pool; fd:fd; size:int |
| request | 1 | `release` | 2 | yes | None |
| event | 0 | `format` | 1 | no | format:uint:format |

Enum `error`; bitfield=false; since=3: `invalid_format=0` (since 1), `invalid_stride=1` (since 1), `invalid_fd=2` (since 1).

Enum `format`; bitfield=false; since=1: `argb8888=0` (since 1), `xrgb8888=1` (since 1), `c8=0x20203843` (since 1), `rgb332=0x38424752` (since 1), `bgr233=0x38524742` (since 1), `xrgb4444=0x32315258` (since 1), `xbgr4444=0x32314258` (since 1), `rgbx4444=0x32315852` (since 1), `bgrx4444=0x32315842` (since 1), `argb4444=0x32315241` (since 1), `abgr4444=0x32314241` (since 1), `rgba4444=0x32314152` (since 1), `bgra4444=0x32314142` (since 1), `xrgb1555=0x35315258` (since 1), `xbgr1555=0x35314258` (since 1), `rgbx5551=0x35315852` (since 1), `bgrx5551=0x35315842` (since 1), `argb1555=0x35315241` (since 1), `abgr1555=0x35314241` (since 1), `rgba5551=0x35314152` (since 1), `bgra5551=0x35314142` (since 1), `rgb565=0x36314752` (since 1), `bgr565=0x36314742` (since 1), `rgb888=0x34324752` (since 1), `bgr888=0x34324742` (since 1), `xbgr8888=0x34324258` (since 1), `rgbx8888=0x34325852` (since 1), `bgrx8888=0x34325842` (since 1), `abgr8888=0x34324241` (since 1), `rgba8888=0x34324152` (since 1), `bgra8888=0x34324142` (since 1), `xrgb2101010=0x30335258` (since 1), `xbgr2101010=0x30334258` (since 1), `rgbx1010102=0x30335852` (since 1), `bgrx1010102=0x30335842` (since 1), `argb2101010=0x30335241` (since 1), `abgr2101010=0x30334241` (since 1), `rgba1010102=0x30334152` (since 1), `bgra1010102=0x30334142` (since 1), `yuyv=0x56595559` (since 1), `yvyu=0x55595659` (since 1), `uyvy=0x59565955` (since 1), `vyuy=0x59555956` (since 1), `ayuv=0x56555941` (since 1), `nv12=0x3231564e` (since 1), `nv21=0x3132564e` (since 1), `nv16=0x3631564e` (since 1), `nv61=0x3136564e` (since 1), `yuv410=0x39565559` (since 1), `yvu410=0x39555659` (since 1), `yuv411=0x31315559` (since 1), `yvu411=0x31315659` (since 1), `yuv420=0x32315559` (since 1), `yvu420=0x32315659` (since 1), `yuv422=0x36315559` (since 1), `yvu422=0x36315659` (since 1), `yuv444=0x34325559` (since 1), `yvu444=0x34325659` (since 1), `r8=0x20203852` (since 1), `r16=0x20363152` (since 1), `rg88=0x38384752` (since 1), `gr88=0x38385247` (since 1), `rg1616=0x32334752` (since 1), `gr1616=0x32335247` (since 1), `xrgb16161616f=0x48345258` (since 1), `xbgr16161616f=0x48344258` (since 1), `argb16161616f=0x48345241` (since 1), `abgr16161616f=0x48344241` (since 1), `xyuv8888=0x56555958` (since 1), `vuy888=0x34325556` (since 1), `vuy101010=0x30335556` (since 1), `y210=0x30313259` (since 1), `y212=0x32313259` (since 1), `y216=0x36313259` (since 1), `y410=0x30313459` (since 1), `y412=0x32313459` (since 1), `y416=0x36313459` (since 1), `xvyu2101010=0x30335658` (since 1), `xvyu12_16161616=0x36335658` (since 1), `xvyu16161616=0x38345658` (since 1), `y0l0=0x304c3059` (since 1), `x0l0=0x304c3058` (since 1), `y0l2=0x324c3059` (since 1), `x0l2=0x324c3058` (since 1), `yuv420_8bit=0x38305559` (since 1), `yuv420_10bit=0x30315559` (since 1), `xrgb8888_a8=0x38415258` (since 1), `xbgr8888_a8=0x38414258` (since 1), `rgbx8888_a8=0x38415852` (since 1), `bgrx8888_a8=0x38415842` (since 1), `rgb888_a8=0x38413852` (since 1), `bgr888_a8=0x38413842` (since 1), `rgb565_a8=0x38413552` (since 1), `bgr565_a8=0x38413542` (since 1), `nv24=0x3432564e` (since 1), `nv42=0x3234564e` (since 1), `p210=0x30313250` (since 1), `p010=0x30313050` (since 1), `p012=0x32313050` (since 1), `p016=0x36313050` (since 1), `axbxgxrx106106106106=0x30314241` (since 1), `nv15=0x3531564e` (since 1), `q410=0x30313451` (since 1), `q401=0x31303451` (since 1), `xrgb16161616=0x38345258` (since 1), `xbgr16161616=0x38344258` (since 1), `argb16161616=0x38345241` (since 1), `abgr16161616=0x38344241` (since 1), `c1=0x20203143` (since 1), `c2=0x20203243` (since 1), `c4=0x20203443` (since 1), `d1=0x20203144` (since 1), `d2=0x20203244` (since 1), `d4=0x20203444` (since 1), `d8=0x20203844` (since 1), `r1=0x20203152` (since 1), `r2=0x20203252` (since 1), `r4=0x20203452` (since 1), `r10=0x20303152` (since 1), `r12=0x20323152` (since 1), `avuy8888=0x59555641` (since 1), `xvuy8888=0x59555658` (since 1), `p030=0x30333050` (since 1), `rgb161616=0x38344752` (since 1), `bgr161616=0x38344742` (since 1), `r16f=0x48202052` (since 1), `gr1616f=0x48205247` (since 1), `bgr161616f=0x48524742` (since 1), `r32f=0x46202052` (since 1), `gr3232f=0x46205247` (since 1), `bgr323232f=0x46524742` (since 1), `abgr32323232f=0x46384241` (since 1), `nv20=0x3032564e` (since 1), `nv30=0x3033564e` (since 1), `s010=0x30313053` (since 1), `s210=0x30313253` (since 1), `s410=0x30313453` (since 1), `s012=0x32313053` (since 1), `s212=0x32313253` (since 1), `s412=0x32313453` (since 1), `s016=0x36313053` (since 1), `s216=0x36313253` (since 1), `s416=0x36313453` (since 1), `xvuy2101010=0x30335958` (since 1), `p230=0x30333250` (since 1), `t430=0x30333454` (since 1), `y8=0x59455247` (since 1), `xyyy2101010=0x34415059` (since 1).

## wl_buffer (version 1)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `destroy` | 1 | yes | None |
| event | 0 | `release` | 1 | no | None |

## wl_data_offer (version 4)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `accept` | 1 | no | serial:uint; mime_type:string:nullable |
| request | 1 | `receive` | 1 | no | mime_type:string; fd:fd |
| request | 2 | `destroy` | 1 | yes | None |
| request | 3 | `finish` | 3 | no | None |
| request | 4 | `set_actions` | 3 | no | dnd_actions:uint:wl_data_device_manager.dnd_action; preferred_action:uint:wl_data_device_manager.dnd_action |
| event | 0 | `offer` | 1 | no | mime_type:string |
| event | 1 | `source_actions` | 3 | no | source_actions:uint:wl_data_device_manager.dnd_action |
| event | 2 | `action` | 3 | no | dnd_action:uint:wl_data_device_manager.dnd_action |

Enum `error`; bitfield=false; since=1: `invalid_finish=0` (since 1), `invalid_action_mask=1` (since 1), `invalid_action=2` (since 1), `invalid_offer=3` (since 1).

## wl_data_source (version 4)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `offer` | 1 | no | mime_type:string |
| request | 1 | `destroy` | 1 | yes | None |
| request | 2 | `set_actions` | 3 | no | dnd_actions:uint:wl_data_device_manager.dnd_action |
| event | 0 | `target` | 1 | no | mime_type:string:nullable |
| event | 1 | `send` | 1 | no | mime_type:string; fd:fd |
| event | 2 | `cancelled` | 1 | no | None |
| event | 3 | `dnd_drop_performed` | 3 | no | None |
| event | 4 | `dnd_finished` | 3 | no | None |
| event | 5 | `action` | 3 | no | dnd_action:uint:wl_data_device_manager.dnd_action |

Enum `error`; bitfield=false; since=1: `invalid_action_mask=0` (since 1), `invalid_source=1` (since 1).

## wl_data_device (version 4)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `start_drag` | 1 | no | source:object:wl_data_source:nullable; origin:object:wl_surface; icon:object:wl_surface:nullable; serial:uint |
| request | 1 | `set_selection` | 1 | no | source:object:wl_data_source:nullable; serial:uint |
| request | 2 | `release` | 2 | yes | None |
| event | 0 | `data_offer` | 1 | no | id:new_id:wl_data_offer |
| event | 1 | `enter` | 1 | no | serial:uint; surface:object:wl_surface; x:fixed; y:fixed; id:object:wl_data_offer:nullable |
| event | 2 | `leave` | 1 | no | None |
| event | 3 | `motion` | 1 | no | time:uint; x:fixed; y:fixed |
| event | 4 | `drop` | 1 | no | None |
| event | 5 | `selection` | 1 | no | id:object:wl_data_offer:nullable |

Enum `error`; bitfield=false; since=1: `role=0` (since 1), `used_source=1` (since 1).

## wl_data_device_manager (version 4)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `create_data_source` | 1 | no | id:new_id:wl_data_source |
| request | 1 | `get_data_device` | 1 | no | id:new_id:wl_data_device; seat:object:wl_seat |
| request | 2 | `release` | 4 | yes | None |

Enum `dnd_action`; bitfield=true; since=3: `none=0` (since 1), `copy=1` (since 1), `move=2` (since 1), `ask=4` (since 1).

## wl_shell (version 1)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `get_shell_surface` | 1 | no | id:new_id:wl_shell_surface; surface:object:wl_surface |

Enum `error`; bitfield=false; since=1: `role=0` (since 1).

## wl_shell_surface (version 1)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `pong` | 1 | no | serial:uint |
| request | 1 | `move` | 1 | no | seat:object:wl_seat; serial:uint |
| request | 2 | `resize` | 1 | no | seat:object:wl_seat; serial:uint; edges:uint:resize |
| request | 3 | `set_toplevel` | 1 | no | None |
| request | 4 | `set_transient` | 1 | no | parent:object:wl_surface; x:int; y:int; flags:uint:transient |
| request | 5 | `set_fullscreen` | 1 | no | method:uint:fullscreen_method; framerate:uint; output:object:wl_output:nullable |
| request | 6 | `set_popup` | 1 | no | seat:object:wl_seat; serial:uint; parent:object:wl_surface; x:int; y:int; flags:uint:transient |
| request | 7 | `set_maximized` | 1 | no | output:object:wl_output:nullable |
| request | 8 | `set_title` | 1 | no | title:string |
| request | 9 | `set_class` | 1 | no | class_:string |
| event | 0 | `ping` | 1 | no | serial:uint |
| event | 1 | `configure` | 1 | no | edges:uint:resize; width:int; height:int |
| event | 2 | `popup_done` | 1 | no | None |

Enum `resize`; bitfield=true; since=1: `none=0` (since 1), `top=1` (since 1), `bottom=2` (since 1), `left=4` (since 1), `top_left=5` (since 1), `bottom_left=6` (since 1), `right=8` (since 1), `top_right=9` (since 1), `bottom_right=10` (since 1).

Enum `transient`; bitfield=true; since=1: `inactive=0x1` (since 1).

Enum `fullscreen_method`; bitfield=false; since=1: `default=0` (since 1), `scale=1` (since 1), `driver=2` (since 1), `fill=3` (since 1).

## wl_surface (version 7)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `destroy` | 1 | yes | None |
| request | 1 | `attach` | 1 | no | buffer:object:wl_buffer:nullable; x:int; y:int |
| request | 2 | `damage` | 1 | no | x:int; y:int; width:int; height:int |
| request | 3 | `frame` | 1 | no | callback:new_id:wl_callback |
| request | 4 | `set_opaque_region` | 1 | no | region:object:wl_region:nullable |
| request | 5 | `set_input_region` | 1 | no | region:object:wl_region:nullable |
| request | 6 | `commit` | 1 | no | None |
| request | 7 | `set_buffer_transform` | 2 | no | transform:int:wl_output.transform |
| request | 8 | `set_buffer_scale` | 3 | no | scale:int |
| request | 9 | `damage_buffer` | 4 | no | x:int; y:int; width:int; height:int |
| request | 10 | `offset` | 5 | no | x:int; y:int |
| request | 11 | `get_release` | 7 | no | callback:new_id:wl_callback |
| event | 0 | `enter` | 1 | no | output:object:wl_output |
| event | 1 | `leave` | 1 | no | output:object:wl_output |
| event | 2 | `preferred_buffer_scale` | 6 | no | factor:int |
| event | 3 | `preferred_buffer_transform` | 6 | no | transform:uint:wl_output.transform |

Enum `error`; bitfield=false; since=1: `invalid_scale=0` (since 1), `invalid_transform=1` (since 1), `invalid_size=2` (since 1), `invalid_offset=3` (since 1), `defunct_role_object=4` (since 1), `no_buffer=5` (since 1).

## wl_seat (version 11)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `get_pointer` | 1 | no | id:new_id:wl_pointer |
| request | 1 | `get_keyboard` | 1 | no | id:new_id:wl_keyboard |
| request | 2 | `get_touch` | 1 | no | id:new_id:wl_touch |
| request | 3 | `release` | 5 | yes | None |
| event | 0 | `capabilities` | 1 | no | capabilities:uint:capability |
| event | 1 | `name` | 2 | no | name:string |

Enum `capability`; bitfield=true; since=1: `pointer=1` (since 1), `keyboard=2` (since 1), `touch=4` (since 1).

Enum `error`; bitfield=false; since=1: `missing_capability=0` (since 1).

## wl_pointer (version 11)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `set_cursor` | 1 | no | serial:uint; surface:object:wl_surface:nullable; hotspot_x:int; hotspot_y:int |
| request | 1 | `release` | 3 | yes | None |
| event | 0 | `enter` | 1 | no | serial:uint; surface:object:wl_surface; surface_x:fixed; surface_y:fixed |
| event | 1 | `leave` | 1 | no | serial:uint; surface:object:wl_surface |
| event | 2 | `motion` | 1 | no | time:uint; surface_x:fixed; surface_y:fixed |
| event | 3 | `button` | 1 | no | serial:uint; time:uint; button:uint; state:uint:button_state |
| event | 4 | `axis` | 1 | no | time:uint; axis:uint:axis; value:fixed |
| event | 5 | `frame` | 5 | no | None |
| event | 6 | `axis_source` | 5 | no | axis_source:uint:axis_source |
| event | 7 | `axis_stop` | 5 | no | time:uint; axis:uint:axis |
| event | 8 | `axis_discrete` | 5 | no | axis:uint:axis; discrete:int |
| event | 9 | `axis_value120` | 8 | no | axis:uint:axis; value120:int |
| event | 10 | `axis_relative_direction` | 9 | no | axis:uint:axis; direction:uint:axis_relative_direction |
| event | 11 | `warp` | 11 | no | surface_x:fixed; surface_y:fixed |

Enum `error`; bitfield=false; since=1: `role=0` (since 1).

Enum `button_state`; bitfield=false; since=1: `released=0` (since 1), `pressed=1` (since 1).

Enum `axis`; bitfield=false; since=1: `vertical_scroll=0` (since 1), `horizontal_scroll=1` (since 1).

Enum `axis_source`; bitfield=false; since=1: `wheel=0` (since 1), `finger=1` (since 1), `continuous=2` (since 1), `wheel_tilt=3` (since 6).

Enum `axis_relative_direction`; bitfield=false; since=1: `identical=0` (since 1), `inverted=1` (since 1).

## wl_keyboard (version 11)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `release` | 3 | yes | None |
| event | 0 | `keymap` | 1 | no | format:uint:keymap_format; fd:fd; size:uint |
| event | 1 | `enter` | 1 | no | serial:uint; surface:object:wl_surface; keys:array |
| event | 2 | `leave` | 1 | no | serial:uint; surface:object:wl_surface |
| event | 3 | `key` | 1 | no | serial:uint; time:uint; key:uint; state:uint:key_state |
| event | 4 | `modifiers` | 1 | no | serial:uint; mods_depressed:uint; mods_latched:uint; mods_locked:uint; group:uint |
| event | 5 | `repeat_info` | 4 | no | rate:int; delay:int |

Enum `keymap_format`; bitfield=false; since=1: `no_keymap=0` (since 1), `xkb_v1=1` (since 1).

Enum `key_state`; bitfield=false; since=1: `released=0` (since 1), `pressed=1` (since 1), `repeated=2` (since 10).

## wl_touch (version 11)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `release` | 3 | yes | None |
| event | 0 | `down` | 1 | no | serial:uint; time:uint; surface:object:wl_surface; id:int; x:fixed; y:fixed |
| event | 1 | `up` | 1 | no | serial:uint; time:uint; id:int |
| event | 2 | `motion` | 1 | no | time:uint; id:int; x:fixed; y:fixed |
| event | 3 | `frame` | 1 | no | None |
| event | 4 | `cancel` | 1 | no | None |
| event | 5 | `shape` | 6 | no | id:int; major:fixed; minor:fixed |
| event | 6 | `orientation` | 6 | no | id:int; orientation:fixed |

## wl_output (version 4)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `release` | 3 | yes | None |
| event | 0 | `geometry` | 1 | no | x:int; y:int; physical_width:int; physical_height:int; subpixel:int:subpixel; make:string; model:string; transform:int:transform |
| event | 1 | `mode` | 1 | no | flags:uint:mode; width:int; height:int; refresh:int |
| event | 2 | `done` | 2 | no | None |
| event | 3 | `scale` | 2 | no | factor:int |
| event | 4 | `name` | 4 | no | name:string |
| event | 5 | `description` | 4 | no | description:string |

Enum `subpixel`; bitfield=false; since=1: `unknown=0` (since 1), `none=1` (since 1), `horizontal_rgb=2` (since 1), `horizontal_bgr=3` (since 1), `vertical_rgb=4` (since 1), `vertical_bgr=5` (since 1).

Enum `transform`; bitfield=false; since=1: `normal=0` (since 1), `90=1` (since 1), `180=2` (since 1), `270=3` (since 1), `flipped=4` (since 1), `flipped_90=5` (since 1), `flipped_180=6` (since 1), `flipped_270=7` (since 1).

Enum `mode`; bitfield=true; since=1: `current=0x1` (since 1), `preferred=0x2` (since 1).

## wl_region (version 7)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `destroy` | 1 | yes | None |
| request | 1 | `add` | 1 | no | x:int; y:int; width:int; height:int |
| request | 2 | `subtract` | 1 | no | x:int; y:int; width:int; height:int |

## wl_subcompositor (version 1)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `destroy` | 1 | yes | None |
| request | 1 | `get_subsurface` | 1 | no | id:new_id:wl_subsurface; surface:object:wl_surface; parent:object:wl_surface |

Enum `error`; bitfield=false; since=1: `bad_surface=0` (since 1), `bad_parent=1` (since 1).

## wl_subsurface (version 1)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `destroy` | 1 | yes | None |
| request | 1 | `set_position` | 1 | no | x:int; y:int |
| request | 2 | `place_above` | 1 | no | sibling:object:wl_surface |
| request | 3 | `place_below` | 1 | no | sibling:object:wl_surface |
| request | 4 | `set_sync` | 1 | no | None |
| request | 5 | `set_desync` | 1 | no | None |

Enum `error`; bitfield=false; since=1: `bad_surface=0` (since 1).

## wl_fixes (version 2)

| Direction | Opcode | Message | Since | Destructor | Arguments |
|---|---:|---|---:|---|---|
| request | 0 | `destroy` | 1 | yes | None |
| request | 1 | `destroy_registry` | 1 | no | registry:object:wl_registry |
| request | 2 | `ack_global_remove` | 2 | no | registry:object:wl_registry; name:uint |

Enum `error`; bitfield=false; since=1: `invalid_ack_remove=0` (since 1).
