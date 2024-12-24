module main

import gg
import gx
import os
import rand
import sokol.sapp
import vbmp

const scale = 20

// emulated keys
enum Keys {
	one
	two
	three
	four
	q
	w
	e
	r
	a
	s
	d
	f
	z
	x
	c
	v
}

// chip-8 system
struct System {
mut:
	memory [4096]u8
	pc     u16
	i      u16
	stack  []u16
	delay  u8
	sound  u8 // TODO play beep when sound timer is above 0
	v      [16]u8
	scr    [64][32]bool

	paused bool

	pressed bool
	key     Keys

	gg    &gg.Context = unsafe { nil }
	frame int
}

// push on to the stack
fn (mut sys System) push(val u16) {
	sys.stack << val
}

// pop off the stack
fn (mut sys System) pop() u16 {
	if sys.stack.len > 0 {
		return sys.stack.pop()
	} else {
		eprintln('ERROR: pop on empty stack')
		return 0
	}
}

// fetch the current instruction
fn (mut sys System) fetch() u16 {
	b1 := u16(sys.memory[sys.pc])
	b2 := sys.memory[sys.pc + 1]
	return u16(b1 << 8 + b2)
}

// clear screen
fn (mut sys System) clear_screen() {
	for i in 0 .. sys.scr.len {
		for j in 0 .. sys.scr[i].len {
			sys.scr[i][j] = false
		}
	}
}

fn (mut sys System) print_screen() {
	mut bmp := vbmp.new(64, 32)
	for i in 0 .. sys.scr.len {
		for j in 0 .. sys.scr[i].len {
			color := u8(if sys.scr[i][j] { 255 } else { 0 })
			bmp.set_pixel(i, u32(sys.scr[i].len - j - 1), color, color, color) or { panic(err) }
		}
	}
	bmp.write('${sys.frame}.bmp') or { panic(err) }
}

// decode the current instruction
fn (mut sys System) decode() {
	ins := sys.fetch()

	if sys.paused {
		return
	}

	sys.pc += 2

	nnn := ins & 0x0FFF
	n := ins & 0x000F
	x := (ins & 0x0F00) >> 8
	mut y := (ins & 0x00F0) >> 4
	kk := u8(ins & 0x00FF)

	match ins & 0xF000 {
		0x0000 {
			match ins {
				// clear screen
				0x00E0 {
					sys.clear_screen()
				}
				// subroutine
				0x00EE {
					sys.pc = sys.pop()
				}
				else {
					eprintln('ERROR: unknown opcode 0x${int(ins):X}')
				}
			}
		}
		// set pc, nnn
		0x1000 {
			sys.pc = nnn
		}
		// call subroutine
		0x2000 {
			sys.push(sys.pc)
			sys.pc = nnn
		}
		// skip v[x], kk
		0x3000 {
			if sys.v[int(x)] == kk {
				sys.pc += 2
			}
		}
		// skip v[x], not kk
		0x4000 {
			if sys.v[int(x)] != kk {
				sys.pc += 2
			}
		}
		// skip v[x], v[y]
		0x5000 {
			if sys.v[int(x)] == sys.v[int(y)] {
				sys.pc += 2
			}
		}
		// set v[x], kk
		0x6000 {
			sys.v[int(x)] = kk
		}
		// add v[x], kk
		0x7000 {
			sys.v[int(x)] += kk
		}
		0x8000 {
			match ins & 0x000F {
				// set v[x], v[y]
				0x0 {
					sys.v[int(x)] = sys.v[int(y)]
				}
				// binary or v[x], v[y]
				0x1 {
					sys.v[int(x)] |= sys.v[int(y)]
				}
				// binary and v[x], v[y]
				0x2 {
					sys.v[int(x)] &= sys.v[int(y)]
				}
				// logical xor v[x], v[y]
				0x3 {
					sys.v[int(x)] ^= sys.v[int(y)]
				}
				// add v[x], v[y] with carry
				0x4 {
					sum := sys.v[x] + sys.v[y]

					if sum > 255 {
						sys.v[0xF] = u8(1)
						sys.v[int(x)] = u8(sum - 255)
					} else {
						sys.v[int(x)] = sum
					}
				}
				// sub v[x], v[y] with carry
				0x5 {
					sys.v[0xF] = u8(0)
					if sys.v[int(x)] > sys.v[int(y)] {
						sys.v[0xF] = u8(1)
					}
					sys.v[int(x)] -= sys.v[int(y)]
				}
				// shift v[x], v[y] right
				0x6 {
					sys.v[int(x)] = sys.v[y]
					sys.v[0xF] = u8(sys.v[int(x)] % 2)
					sys.v[int(x)] >>= 1
				}
				// sub v[x], v[y] with carry
				0x7 {
					if sys.v[int(y)] > sys.v[int(x)] {
						sys.v[0xF] = u8(1)
						sys.v[int(y)] -= sys.v[int(x)]
					} else {
						sys.v[int(y)] = u8(u16(255) + u16(sys.v[int(y)]) - sys.v[int(x)])
					}
				}
				// shift v[x], v[y] left
				0xE {
					sys.v[int(x)] = sys.v[y]
					sys.v[0xF] = u8(sys.v[int(x)] >= 8)
					sys.v[int(x)] <<= 1
				}
				else {
					eprintln('ERROR: unknown opcode 0x${int(ins):X}')
				}
			}
		}
		// skip v[x], not v[y]
		0x9000 {
			if sys.v[int(x)] != sys.v[int(y)] {
				sys.pc += 2
			}
		}
		// set i, nnn
		0xA000 {
			sys.i = nnn
		}
		// set pc, nnn + v[0]
		0xB000 {
			sys.pc = nnn + sys.v[0]
		}
		// set v[x], random & kk
		0xC000 {
			sys.v[int(x)] = rand.u8() & kk
		}
		// display
		0xD000 {
			x_coord := sys.v[int(x)] & 63
			y_coord := sys.v[int(y)] & 31
			sys.v[0xF] = 0

			for i in 0 .. n {
				dat := sys.memory[int(sys.i) + i]

				for j in 0 .. 8 {
					if (dat & (0x80 >> j)) != 0 {
						px := (x_coord + j) & 63
						py := (y_coord + i) & 31
						if sys.scr[px][py] {
							sys.v[0xF] = 1
						}
						sys.scr[px][py] = !sys.scr[px][py]
					}
				}
			}
		}
		0xE000 {
			match ins & 0x00FF {
				// skip key, v[x] pressed
				0x9E {
					if sys.pressed && u8(sys.key) == sys.v[int(x)] {
						sys.pc += 2
					}
				}
				// skip key, v[x] not pressed
				0xA1 {
					if !sys.pressed && u8(sys.key) == sys.v[int(x)] {
						sys.pc += 2
					}
				}
				else {
					eprintln('ERROR: unknown opcode 0x${int(ins):X}')
				}
			}
		}
		0xF000 {
			match ins & 0xFF {
				// set v[x], delay
				0x07 {
					sys.v[int(x)] = sys.delay
				}
				// set delay, v[x]
				0x15 {
					sys.delay = sys.v[int(x)]
				}
				// set sound, v[x]
				0x18 {
					sys.sound = sys.v[int(x)]
				}
				// add i, v[x]
				0x1E {
					sys.i += sys.v[int(x)]
				}
				// get key
				0x0A {
					sys.pc -= 2
					sys.v[int(x)] = u8(sys.key)
				}
				// font character
				0x29 {
					sys.i = sys.v[int(x)] * u16(10)
				}
				// bcd conversion
				0x33 {
					sys.memory[int(sys.i)] = u8(sys.v[int(x)] / 100)
					sys.memory[int(sys.i) + 1] = u8((sys.v[int(x)] % 100) / 10)
					sys.memory[int(sys.i) + 2] = u8(sys.v[int(x)] % 10)
				}
				// store
				0x55 {
					for i in 0 .. x + 1 {
						sys.memory[i + sys.i] = sys.v[i]
					}
				}
				// load
				0x65 {
					for i in 0 .. x + 1 {
						sys.v[i] = sys.memory[i + sys.i]
					}
				}
				else {
					eprintln('ERROR: unknown opcode 0x${int(ins):X}')
				}
			}
		}
		else {
			eprintln('ERROR: unknown opcode 0x${int(ins):X}')
		}
	}
}

fn (mut sys System) load_file(file string) {
	// clear memory
	for i in 0 .. sys.memory.len {
		sys.memory[i] = u8(0)
	}

	// clear screen
	sys.clear_screen()

	// clear registers
	sys.i = u16(0)
	sys.stack.clear()
	sys.delay = u8(0)
	sys.sound = u8(0)
	for i in 0 .. sys.v.len {
		sys.v[i] = u8(0)
	}

	// define font
	font := [
		[u8(0xF), u8(0x0), u8(0x9), u8(0x0), u8(0x9), u8(0x0), u8(0x9), u8(0x0), u8(0xF), u8(0x0)],
		[u8(0x2), u8(0x0), u8(0x6), u8(0x0), u8(0x2), u8(0x0), u8(0x2), u8(0x0), u8(0x7), u8(0x0)],
		[u8(0xF), u8(0x0), u8(0x1), u8(0x0), u8(0xF), u8(0x0), u8(0x8), u8(0x0), u8(0xF), u8(0x0)],
		[u8(0xF), u8(0x0), u8(0x1), u8(0x0), u8(0xF), u8(0x0), u8(0x1), u8(0x0), u8(0xF), u8(0x0)],
		[u8(0x9), u8(0x0), u8(0x9), u8(0x0), u8(0xF), u8(0x0), u8(0x1), u8(0x0), u8(0x1), u8(0x0)],
		[u8(0xF), u8(0x0), u8(0x8), u8(0x0), u8(0xF), u8(0x0), u8(0x1), u8(0x0), u8(0xF), u8(0x0)],
		[u8(0xF), u8(0x0), u8(0x8), u8(0x0), u8(0xF), u8(0x0), u8(0x9), u8(0x0), u8(0xF), u8(0x0)],
		[u8(0xF), u8(0x0), u8(0x1), u8(0x0), u8(0x2), u8(0x0), u8(0x4), u8(0x0), u8(0x4), u8(0x0)],
		[u8(0xF), u8(0x0), u8(0x9), u8(0x0), u8(0xF), u8(0x0), u8(0x9), u8(0x0), u8(0xF), u8(0x0)],
		[u8(0xF), u8(0x0), u8(0x9), u8(0x0), u8(0xF), u8(0x0), u8(0x1), u8(0x0), u8(0xF), u8(0x0)],
		[u8(0xF), u8(0x0), u8(0x9), u8(0x0), u8(0xF), u8(0x0), u8(0x9), u8(0x0), u8(0x9), u8(0x0)],
		[u8(0xE), u8(0x0), u8(0x9), u8(0x0), u8(0xE), u8(0x0), u8(0x9), u8(0x0), u8(0xE), u8(0x0)],
		[u8(0xF), u8(0x0), u8(0x8), u8(0x0), u8(0x8), u8(0x0), u8(0x8), u8(0x0), u8(0xF), u8(0x0)],
		[u8(0xE), u8(0x0), u8(0x9), u8(0x0), u8(0x9), u8(0x0), u8(0x9), u8(0x0), u8(0xE), u8(0x0)],
		[u8(0xF), u8(0x0), u8(0x8), u8(0x0), u8(0xF), u8(0x0), u8(0x8), u8(0x0), u8(0xF), u8(0x0)],
		[u8(0xF), u8(0x0), u8(0x8), u8(0x0), u8(0xF), u8(0x0), u8(0x8), u8(0x0), u8(0x8), u8(0x0)],
	]

	// write font to start of memory
	for i, v in font {
		for j in 0 .. v.len {
			sys.memory[i * 10 + j] = font[i][j]
		}
	}

	// read file into memory
	bytes := os.read_bytes(file) or { return }
	println('ROM size: ${bytes.len} bytes')

	for i, v in bytes {
		sys.memory[0x200 + i] = v
	}

	// set pc to start of program
	sys.pc = u16(0x200)
}

fn init(mut sys System) {
	sys.load_file('fishie.ch8')
}

fn (mut sys System) update() {
	// update timers at 60hz
	if sys.delay > 0 {
		sys.delay -= 1
	}
	if sys.sound > 0 {
		sys.sound -= 1
	}

	// run instruction
	sys.decode()
}

fn (sys &System) draw() {
	for i in 0 .. sys.scr.len {
		for j in 0 .. sys.scr[i].len {
			sys.gg.draw_rect_filled(i * scale, j * scale, scale, scale, if sys.scr[i][j] {
				gx.white
			} else {
				gx.black
			})
		}
	}

	if sys.paused {
		sys.gg.draw_text_default(48, 8, 'PAUSED')
	}

	sys.gg.show_fps()
}

fn (mut sys System) on_key_down(key gg.KeyCode) {
	match key {
		.escape { sys.gg.quit() }
		._1 { sys.key = .one }
		._2 { sys.key = .two }
		._3 { sys.key = .three }
		._4 { sys.key = .four }
		.q { sys.key = .q }
		.w { sys.key = .w }
		.e { sys.key = .e }
		.r { sys.key = .r }
		.a { sys.key = .a }
		.s { sys.key = .s }
		.d { sys.key = .d }
		.f { sys.key = .f }
		.z { sys.key = .z }
		.x { sys.key = .x }
		.c { sys.key = .c }
		.v { sys.key = .v }
		.p { sys.print_screen() }
		.space { sys.paused = !sys.paused }
		else {}
	}
}

fn on_event(e &gg.Event, mut sys System) {
	match e.typ {
		.key_down {
			sys.on_key_down(e.key_code)
			sys.pressed = true
		}
		.files_dropped {
			num_dropped := sapp.get_num_dropped_files()
			if num_dropped == 1 {
				sys.load_file(sapp.get_dropped_file_path(0))
			}
		}
		else {
			sys.pressed = false
		}
	}
}

fn frame(mut sys System) {
	sys.frame += 1

	sys.gg.begin()
	sys.update()
	sys.draw()
	sys.gg.end()
}

fn main() {
	mut system := &System{}

	system.gg = gg.new_context(
		width:             64 * scale
		height:            32 * scale
		scale:             f32(scale)
		enable_dragndrop:  true
		max_dropped_files: 1
		bg_color:          gx.black
		window_title:      'chipv8'
		init_fn:           init
		frame_fn:          frame
		event_fn:          on_event
		user_data:         system
	)

	system.gg.run()
}
