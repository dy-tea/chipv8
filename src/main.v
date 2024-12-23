module main

import gg
import gx
import os
import rand

const scale = 20

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

	pressed bool
	key     u8

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

// decode the current instruction
fn (mut sys System) decode() {
	ins := sys.fetch()
	sys.pc += 2

	nnn := ins & 0x0FFF
	n := ins & 0x000F
	x := (ins >> 8) & 0x000F
	mut y := (ins >> 4) & 0x000F
	kk := u8(ins & 0x00FF)

	println('Call: 0x${int(ins):X}, PC: ${int(sys.pc)}')

	match true {
		// clear screen
		ins == 0x00E0 {
			for i in 0 .. sys.scr.len {
				for j in 0 .. sys.scr[i].len {
					sys.scr[i][j] = false
				}
			}
		}
		// subroutine
		ins == 0x00EE, (ins & 0xF000) == 0x2000 {
			sys.pc = sys.pop()
		}
		// jump nnn
		(ins & 0xF000) == 0x1000 {
			sys.pc = nnn
		}
		// skip v[x], kk
		(ins & 0xF000) == 0x3000 {
			if sys.v[int(x)] == kk {
				sys.pc += 2
			}
		}
		// skip v[x], not kk
		(ins & 0xF000) == 0x4000 {
			if sys.v[int(x)] != kk {
				sys.pc += 2
			}
		}
		// skip v[x], v[y]
		(ins & 0xF000) == 0x5000 {
			if sys.v[int(x)] == sys.v[int(y)] {
				sys.pc += 2
			}
		}
		// skip v[x], not v[y]
		(ins & 0xF000) == 0x9000 {
			if sys.v[int(x)] != sys.v[int(y)] {
				sys.pc += 2
			}
		}
		// set v[x], kk
		(ins & 0xF000) == 0x6000 {
			sys.v[int(x)] = kk
		}
		// add v[x], kk
		(ins & 0xF000) == 0x7000 {
			sys.v[int(x)] += kk
		}
		(ins & 0xF000) == 0x8000 {
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
					sys.v[int(x)] = u8(sys.v[int(x)] != sys.v[int(y)])
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
					if sys.v[int(x)] > sys.v[int(y)] {
						sys.v[0xF] = u8(1)
						sys.v[int(x)] -= sys.v[int(y)]
					} else {
						sys.v[int(x)] = u8(u16(255) + u16(sys.v[int(x)]) - sys.v[int(y)])
					}
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
		// set i, nnn
		(ins & 0xF000) == 0xA000 {
			sys.i = nnn
		}
		// jump nnn offset
		(ins & 0xF000) == 0xB000 {
			sys.pc = x << 8 + kk + sys.v[int(x)]
		}
		// random
		(ins & 0xF000) == 0xC000 {
			sys.v[int(x)] = rand.u8() & kk
		}
		// display
		(ins & 0xF000) == 0xD000 {
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
		// skip key, v[x] pressed
		(ins & 0xF0FF) == 0xE09E {
			if sys.pressed && sys.key == sys.v[int(x)] {
				sys.pc += 2
			}
		}
		// skip key, v[x] not pressed
		(ins & 0xF0FF) == 0xE0A1 {
			if !sys.pressed && sys.key == sys.v[int(x)] {
				sys.pc += 2
			}
		}
		// set v[x], delay
		(ins & 0xF00F) == 0xF007 {
			sys.v[int(x)] = sys.delay
		}
		// set delay, v[x]
		(ins & 0xF0FF) == 0xF015 {
			sys.delay = sys.v[int(x)]
		}
		// set sound, v[x]
		(ins & 0xF0FF) == 0xF018 {
			sys.sound = sys.v[int(x)]
		}
		// add i, v[x]
		(ins & 0xF0FF) == 0xF01E {
			sys.i += sys.v[int(x)]
		}
		// get key
		(ins & 0xF00F) == 0xF00A {
			sys.pc -= 2
		}
		// font character
		(ins & 0xF0FF) == 0xF029 {
			sys.i = sys.v[int(x)] * u16(10)
		}
		// bcd conversion
		(ins & 0xF0FF) == 0xF033 {
			h := u16(sys.v[int(x)] / 100 % 10)
			t := u16(sys.v[int(x)] / 10 % 10)
			o := u16(sys.v[int(x)] % 10)

			sys.i = h + t << 4 + o << 8
		}
		// store
		(ins & 0xF0FF) == 0xF055 {
			for i in 0 .. x {
				sys.memory[i + sys.i] = sys.v[i]
			}
		}
		// load
		(ins & 0xF0FF) == 0xF065 {
			for i in 0 .. x {
				sys.v[i] = sys.memory[i + sys.i]
			}
		}
		ins == 0x0 {
			exit(0)
		}
		else {
			eprintln('ERROR: unknown opcode 0x${int(ins):X}')
		}
	}
}

fn init(mut sys System) {
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

	// write program to memory
	bytes := os.read_bytes('test_opcode.ch8') or { panic(err) }
	println('ROM size: ${bytes.len} bytes')

	for i, v in bytes {
		sys.memory[0x200 + i] = v
	}

	// set pc to start of program
	sys.pc = u16(0x200)
}

fn (mut sys System) update() {
	// update timers at 60hz
	if sys.frame % 60 == 0 {
		sys.delay = if sys.delay == 0 { u8(8) } else { u8(0) }
		sys.sound = if sys.sound == 0 { u8(8) } else { u8(0) }
	}
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

	sys.gg.show_fps()
}

fn (mut sys System) on_key_down(key gg.KeyCode) {
	match key {
		.escape { sys.gg.quit() }
		._1, ._2, ._3, ._4 { sys.key = u8(u16(key) - 49) }
		.q { sys.key = u8(0x4) }
		.w { sys.key = u8(0x5) }
		.e { sys.key = u8(0x6) }
		.r { sys.key = u8(0x7) }
		.a { sys.key = u8(0x8) }
		.s { sys.key = u8(0x9) }
		.d { sys.key = u8(0xA) }
		.f { sys.key = u8(0xB) }
		.z { sys.key = u8(0xC) }
		.x { sys.key = u8(0xD) }
		.c { sys.key = u8(0xE) }
		.v { sys.key = u8(0xF) }
		else {}
	}
}

fn on_event(e &gg.Event, mut sys System) {
	match e.typ {
		.key_down {
			sys.pressed = true
			sys.on_key_down(e.key_code)
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
		width:            64 * scale
		height:           32 * scale
		scale:            20.0
		enable_dragndrop: true
		bg_color:         gx.black
		window_title:     'chipv8'
		init_fn:          init
		frame_fn:         frame
		event_fn:         on_event
		user_data:        system
	)

	system.gg.run()
}
