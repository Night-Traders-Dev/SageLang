## Unit test for metal.vga module

import metal.vga as vga
import assert

proc test_vga():
    print("Testing metal.vga...")

    # Test attribute creation
    let attr = vga.make_attr(vga.WHITE, vga.BLUE)
    assert.assert_equal(vga.BLUE, (attr >> 4) & 15, "Background color match")
    assert.assert_equal(vga.WHITE, attr & 15, "Foreground color match")

    # Test clear screen
    vga.clear(vga.BLACK)
    assert.assert_equal(32, vga.read_char_at(0, 0), "Clear screen space character")

    # Test putchar_at
    let test_attr = vga.make_attr(vga.GREEN, vga.BLACK)
    vga.putchar_at(10, 5, "S", test_attr)
    assert.assert_equal(ord("S"), vga.read_char_at(10, 5), "Character code match at (10,5)")
    assert.assert_equal(test_attr, vga.read_attr_at(10, 5), "Attribute byte match at (10,5)")

    # Test puts
    vga.puts(0, 0, "SageOS", test_attr)
    assert.assert_equal(ord("S"), vga.read_char_at(0, 0), "puts char 0")
    assert.assert_equal(ord("a"), vga.read_char_at(1, 0), "puts char 1")
    assert.assert_equal(ord("g"), vga.read_char_at(2, 0), "puts char 2")
    assert.assert_equal(ord("e"), vga.read_char_at(3, 0), "puts char 3")
    assert.assert_equal(ord("O"), vga.read_char_at(4, 0), "puts char 4")
    assert.assert_equal(ord("S"), vga.read_char_at(5, 0), "puts char 5")

    # Test progress bar
    vga.draw_progress_bar(0, 2, 10, 50, test_attr)
    assert.assert_equal(ord("["), vga.read_char_at(0, 2), "Progress bar left bracket")
    assert.assert_equal(ord("="), vga.read_char_at(1, 2), "Progress bar fill char 1")
    assert.assert_equal(ord("="), vga.read_char_at(4, 2), "Progress bar fill char 4")
    assert.assert_equal(ord(" "), vga.read_char_at(5, 2), "Progress bar empty char 5")
    assert.assert_equal(ord("]"), vga.read_char_at(9, 2), "Progress bar right bracket")

    print("metal.vga tests passed successfully!")

proc main():
    test_vga()

main()
